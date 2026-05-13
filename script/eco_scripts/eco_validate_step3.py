#!/usr/bin/env python3
"""
eco_validate_step3.py — Validate eco_preeco_study.json completeness before Step 4.

This script enforces the Step 3 output contract. If any required data is missing,
it prints a FAIL with specific reasons so the ORCHESTRATOR can re-spawn
eco_netlist_studier or eco_expand_chains to fill the gap.

Usage:
    python3 script/eco_scripts/eco_validate_step3.py \
        --study    data/<TAG>_eco_preeco_study.json \
        --rtl-diff data/<TAG>_eco_rtl_diff.json \
        --ref-dir  <REF_DIR> \
        --tag      <TAG> \
        --output   data/<TAG>_eco_validate_step3.json

Exit: 0 = PASS (all complete), 1 = FAIL (issues found)
"""

import argparse, json, os, re, subprocess, sys
from pathlib import Path

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--study',    required=True)
    p.add_argument('--rtl-diff', required=True)
    p.add_argument('--ref-dir',  required=True)
    p.add_argument('--tag',      required=True)
    p.add_argument('--output',   required=True)
    args = p.parse_args()

    study    = json.loads(Path(args.study).read_text())
    rtl_diff = json.loads(Path(args.rtl_diff).read_text())
    issues   = []

    # ── 1. All 3 stages present and non-empty ────────────────────────────────
    for stage in ['Synthesize', 'PrePlace', 'Route']:
        entries = study.get(stage, [])
        if not entries:
            issues.append(f"CRITICAL: {stage} entries empty — eco_netlist_studier produced no output for this stage")

    # ── 2. Every DFF with d_input_gate_chain has gate entries expanded ───────
    for change in rtl_diff.get('changes', []):
        chain = change.get('d_input_gate_chain')
        if not chain:
            continue
        target = change.get('target_register', '') or change.get('new_token', '')
        chain_inst_names = {g.get('instance_name','') for g in chain if g.get('instance_name')}
        for stage in ['Synthesize', 'PrePlace', 'Route']:
            existing = {e.get('instance_name','') for e in study.get(stage,[])
                       if e.get('change_type') in ('new_logic_gate','new_logic_dff','new_logic')}
            missing = chain_inst_names - existing
            if missing:
                issues.append(f"CRITICAL: {stage} missing d-input gate chain entries for {target}: {missing} — run eco_expand_chains.py")

    # ── 3. DFF entries have port_connections_per_stage for all 3 stages ─────
    for stage in ['Synthesize', 'PrePlace', 'Route']:
        for e in study.get(stage, []):
            if e.get('change_type') not in ('new_logic_dff', 'new_logic'):
                continue
            if not e.get('confirmed', True):
                continue
            inst = e.get('instance_name', '?')
            pcs = e.get('port_connections_per_stage', {})
            for chk_stage in ['Synthesize', 'PrePlace', 'Route']:
                if not pcs.get(chk_stage):
                    issues.append(f"HIGH: DFF {inst} in {stage} missing port_connections_per_stage[{chk_stage}] — eco_netlist_studier Phase 0b-STAGE-NETS incomplete")

    # ── 3b. Mode S consistency: when requires_scan_stitching/mode_S_applied is
    #        true on a DFF, every per-stage entry list (Synthesize/PrePlace/Route)
    #        must carry the SAME port_connections_per_stage map. The 9868 R1 bug
    #        was the Route-stage entry overriding its own SE/SI to neighbor-DFF
    #        nets while Synthesize/PrePlace entries used the bridge port names.
    by_inst = {}
    for stage in ['Synthesize', 'PrePlace', 'Route']:
        for e in study.get(stage, []):
            if e.get('change_type') not in ('new_logic_dff', 'new_logic'):
                continue
            if not (e.get('mode_S_applied') or e.get('requires_scan_stitching')):
                continue
            by_inst.setdefault(e.get('instance_name','?'), {})[stage] = \
                (e.get('port_connections_per_stage', {}),
                 e.get('mode_S_strategy_per_stage', {}))
    for inst, per_entry in by_inst.items():
        if len(per_entry) < 2:
            continue
        ref_stage = sorted(per_entry.keys())[0]
        ref_pcs, ref_strat = per_entry[ref_stage]
        for stage_entry, (pcs, strat) in per_entry.items():
            if stage_entry == ref_stage:
                continue
            for chk_stage in ('Synthesize', 'PrePlace', 'Route'):
                # Asymmetric Mode S: a stage entry can legitimately use a
                # different strategy (neighbor_dff vs bridge_port) per stage
                # — engineer's own pattern. Only flag mismatch when BOTH
                # entries declared the SAME strategy for chk_stage AND yet
                # disagreed on the actual SE/SI/CP nets — that's a real bug.
                ref_chk_strat = (ref_strat or {}).get(chk_stage)
                cmp_chk_strat = (strat or {}).get(chk_stage)
                if ref_chk_strat and cmp_chk_strat and ref_chk_strat != cmp_chk_strat:
                    continue  # asymmetric strategy — comparison meaningless
                ref_pin = ref_pcs.get(chk_stage, {}) or {}
                cmp_pin = pcs.get(chk_stage, {}) or {}
                for pin in ('SE', 'SI', 'CP'):
                    a, b = ref_pin.get(pin), cmp_pin.get(pin)
                    if a != b:
                        issues.append(
                            f"HIGH: Mode S {inst} stage_entry[{stage_entry}] differs from "
                            f"stage_entry[{ref_stage}] for port_connections_per_stage[{chk_stage}].{pin}: "
                            f"{a!r} vs {b!r} — when both entries use the same Mode S strategy "
                            f"for this stage, the per-stage map MUST agree.")

    # ── 3c. Mode S completeness: when a DFF is marked mode_S_applied=true the
    #        study MUST contain matching port_declaration entries for the SI_in,
    #        SE_in and Q_out bridge ports referenced by the DFF's
    #        port_connections_per_stage, AND an `assign` change wiring Q_out to
    #        the DFF's Q net. Without these, eco_passes_2_4 will leave the
    #        bridge ports undeclared and Step 5 Check 17 catches it later — but
    #        we want to fail fast at Step 3.
    decl_set = set()       # (module_name, signal_name)
    assign_set = set()     # (module_name, lhs)
    for stage in ['Synthesize']:
        for e in study.get(stage, []):
            ct = e.get('change_type', '')
            if ct == 'port_declaration':
                decl_set.add((e.get('module_name', ''), e.get('signal_name', '')))
            elif ct == 'assign':
                decl_set  # no-op
                assign_set.add((e.get('module_name', ''),
                                e.get('lhs') or e.get('signal_name', '')))
    for stage in ['Synthesize']:
        for e in study.get(stage, []):
            if e.get('change_type') not in ('new_logic_dff', 'new_logic'):
                continue
            if not (e.get('mode_S_applied') or e.get('requires_scan_stitching')):
                continue
            inst = e.get('instance_name', '?')
            mod = e.get('module_name', '')
            strat_per_stage = e.get('mode_S_strategy_per_stage') or {}
            # Only require bridge port_decls + assign when at least one stage
            # uses bridge_port strategy. neighbor_dff strategy needs no bridge.
            uses_bridge = any(strat_per_stage.get(s) == 'bridge_port'
                              for s in ('PrePlace', 'Route'))
            if not uses_bridge and strat_per_stage:
                continue  # explicit neighbor_dff strategy → no bridge needed
            pp_pcs = (e.get('port_connections_per_stage') or {}).get('PrePlace', {}) or {}
            si_name = pp_pcs.get('SI', '')
            se_name = pp_pcs.get('SE', '')
            base_match = re.match(r'(ECO_\w+?)_SI_in$', si_name) if si_name else None
            qo_name = f'{base_match.group(1)}_Q_out' if base_match else None
            for port_name in (si_name, se_name, qo_name):
                if not port_name or port_name in ("1'b0", "1'b1"):
                    continue
                # Skip if this name is a real netlist signal (neighbor_dff
                # strategy in PP keeps SI/SE pointing at neighbor nets — not
                # bridge ports — so port_decl shouldn't exist for it)
                if not port_name.startswith('ECO_'):
                    continue
                if (mod, port_name) not in decl_set:
                    issues.append(
                        f"HIGH: Mode S {inst} (mode_S_applied=true) references bridge "
                        f"port {port_name!r} on module {mod!r} but no matching "
                        f"`port_declaration` entry exists in the study — eco_passes_2_4 "
                        f"will leave this port undeclared. Add the port_declaration "
                        f"or switch mode_S_strategy_per_stage to neighbor_dff for "
                        f"the affected stage with a justification.")
            if qo_name and (mod, qo_name) not in assign_set:
                issues.append(
                    f"HIGH: Mode S {inst} (mode_S_applied=true) needs an `assign "
                    f"{qo_name} = <Q net>;` change in module {mod!r} but no matching "
                    f"`assign` entry exists in the study — Q_out will be left undriven.")

            # Bridge wire driver requirement (closes 9868 R1 dangling-bridge bug):
            # for each bridge_port stage, the parent module MUST contain an
            # `assign eco<jira>_si_bridge = <real net>` and same for se_bridge.
            for chk_stage in ('PrePlace', 'Route'):
                if strat_per_stage.get(chk_stage) != 'bridge_port':
                    continue
                m = re.match(r'ECO_(\w+?)_SI_in$', si_name) if si_name else None
                if not m:
                    continue
                jira_part = m.group(1)
                for bridge in (f'eco{jira_part}_si_bridge', f'eco{jira_part}_se_bridge'):
                    found = any(lhs == bridge for (_, lhs) in assign_set)
                    if not found:
                        issues.append(
                            f"HIGH: Mode S {inst} stage={chk_stage} bridge_port strategy "
                            f"requires an `assign {bridge} = <parent_neighbor_net>` at the "
                            f"parent scope — without it the bridge wire dangles undriven "
                            f"and FM sees globally unmatched SE/SI on the new DFF.")

            # GAP-4b enforcement: bridge buffer source wire must be verified
            # stage-stable PP↔Route. The studier should record in the entry:
            #   bridge_source_pp_route_match: { si: bool, se: bool }
            # set true ONLY after checking the wire's parent-level driver is the
            # SAME logical net in both PP and Route (via fenets rename map or
            # structural cone trace). False / missing → fail this check.
            uses_bridge_pp_route = (strat_per_stage.get('PrePlace') == 'bridge_port'
                                    or strat_per_stage.get('Route') == 'bridge_port')
            if uses_bridge_pp_route:
                bsm = e.get('bridge_source_pp_route_match') or {}
                for pin in ('si', 'se'):
                    if bsm.get(pin) is not True:
                        issues.append(
                            f"HIGH: GAP-4b — Mode S {inst} bridge_port (PP/Route) requires "
                            f"`bridge_source_pp_route_match.{pin}: true` in the study entry. "
                            f"Studier must verify the {pin.upper()} bridge buffer source wire "
                            f"has a stage-stable parent driver across PP→Route (use fenets "
                            f"rename map). Missing/false = bridge cone diverges across stages "
                            f"and FM fails on the new DFF.")

            # GAP-4 + GAP-4c enforcement (studier-side): when bridge_port chosen,
            # the study JSON MUST also contain matching companion entries:
            #   - sibling_pin_consolidation entries (one per pin: SE, sometimes SI)
            #   - si_consumer_replace entry (closes the bridge Q output)
            # Without these, the bridge plumbing dangles and FM fails.
            if uses_bridge_pp_route:
                # Aggregate companion entries from any stage of study JSON
                all_entries = []
                for s in ('Synthesize', 'PrePlace', 'Route'):
                    all_entries.extend(study.get(s, []))
                jira_part = ''
                if isinstance(si_name, str):
                    m = re.match(r'ECO_(\w+?)_SI_in$', si_name)
                    if m:
                        jira_part = m.group(1)
                # GAP-4: at least one sibling_pin_consolidation entry referencing
                # this DFF's bridge wire (ECO_<jira>_SE_out)
                want_se_net = f'ECO_{jira_part}_SE_out' if jira_part else None
                consol_found = any(
                    ce.get('change_type') == 'sibling_pin_consolidation'
                    and ce.get('pin_name') == 'SE'
                    and (want_se_net is None or ce.get('new_net') == want_se_net)
                    for ce in all_entries
                )
                if not consol_found:
                    issues.append(
                        f"HIGH: GAP-4 — Mode S {inst} uses bridge_port but no "
                        f"`sibling_pin_consolidation` entry (pin_name=SE"
                        f"{f', new_net={want_se_net}' if want_se_net else ''}) found in study. "
                        f"Bridge SE port is not consumed by sibling DFFs → FM cone divergence.")
                # GAP-4c: at least one si_consumer_replace entry referencing
                # this DFF's bridge Q port (ECO_<jira>_Q_in)
                want_q_net = f'ECO_{jira_part}_Q_in' if jira_part else None
                qclose_found = any(
                    ce.get('change_type') == 'si_consumer_replace'
                    and (want_q_net is None or ce.get('new_si_net') == want_q_net)
                    for ce in all_entries
                )
                if not qclose_found:
                    issues.append(
                        f"HIGH: GAP-4c — Mode S {inst} uses bridge_port but no "
                        f"`si_consumer_replace` entry"
                        f"{f' (new_si_net={want_q_net})' if want_q_net else ''} found in study. "
                        f"Bridge Q output dangles in sibling module → DFT scan break + FM warns.")

    # ── 3d. Mode S decision must match Step 1 (rtl_diff). When Step 1 emits
    #        requires_scan_stitching=true on a new_logic_dff, the studier MUST
    #        carry that decision through (mode_S_applied=true OR an explicit
    #        scan_stitching_skipped_reason justification). Silent downgrade
    #        bypasses the entire Mode S pipeline and was the actual cause of
    #        9868 R1 fresh-run Round 2 going wrong on EcoUseSdpOutstRdCnt.
    diff_decisions = {}  # instance_name → (requires_scan_stitching, skipped_reason)
    for c in rtl_diff.get('changes', []):
        if c.get('change_type') not in ('new_logic', 'new_logic_dff'):
            continue
        dff_inst = c.get('dff_instance_name') or (
            (c.get('target_register') or '') + '_reg' if c.get('target_register') else '')
        if dff_inst:
            diff_decisions[dff_inst] = (
                bool(c.get('requires_scan_stitching')),
                c.get('scan_stitching_skipped_reason') or '')
    seen_in_study = set()
    for stage in ['Synthesize']:
        for e in study.get(stage, []):
            if e.get('change_type') not in ('new_logic_dff', 'new_logic'):
                continue
            inst = e.get('instance_name', '?')
            if inst not in diff_decisions:
                continue
            seen_in_study.add(inst)
            diff_required, _ = diff_decisions[inst]
            study_applied = bool(
                e.get('mode_S_applied') or e.get('requires_scan_stitching'))
            study_skip_reason = e.get('scan_stitching_skipped_reason') or ''
            if diff_required and not study_applied and not study_skip_reason:
                issues.append(
                    f"HIGH: Mode S decision downgrade — rtl_diff set "
                    f"requires_scan_stitching=true for {inst} but study has "
                    f"mode_S_applied/requires_scan_stitching=false WITHOUT a "
                    f"`scan_stitching_skipped_reason`. Studier cannot silently "
                    f"opt out — either honor Step 1's decision (emit Mode S "
                    f"port_decls + assign + bridged SE/SI) or supply an "
                    f"auditable justification field.")

    # ── 3e. Cross-check port_connection ↔ port_declaration. Every port_connection
    #        targeting a child instance MUST reference a port name that either
    #        (a) is already declared in the child module's PreEco SynRtl source,
    #        OR (b) appears as a port_declaration entry in the study for that
    #        child module. Missing → FE-LINK-7 ABORT during FM elaboration
    #        (observed on 9868 fresh run R1: NeedFreqAdj port_connection with
    #        no matching port on umcarbctrlsw).
    rtl_dir = os.path.join(args.ref_dir, 'data', 'PreEco', 'SynRtl')
    pre_existing_ports = {}  # module_name → set(port_name)
    if os.path.isdir(rtl_dir):
        port_decl_re = re.compile(
            r'\b(?:input|output|inout)\b[^;]*?\b([A-Za-z_]\w*)\s*[;,)]',
            re.MULTILINE)
        # Anchor `module` to start-of-line (with optional leading whitespace).
        # The `\bmodule\b` form matched the keyword `for` from a procedural
        # `for(...)` block in some files because `\b` allows match anywhere.
        mod_re = re.compile(r'^\s*module\s+(\w+)\b', re.MULTILINE)
        for root, _, files in os.walk(rtl_dir):
            for f in files:
                if not f.endswith(('.v','.sv')):
                    continue
                try:
                    txt = Path(os.path.join(root, f)).read_text(errors='ignore')
                except Exception:
                    continue
                # Cheap pass: any module-port direction-keyword in this file
                # contributes to that file's signal pool. Bucket by the first
                # `module <name>` we see (most ECO targets are 1-module-per-file).
                m = mod_re.search(txt)
                if not m:
                    continue
                mod_name = m.group(1)
                # Also try the tile-prefixed form 'ddrss_umccmd_t_<base>'
                ports = set()
                for pm in port_decl_re.finditer(txt):
                    ports.add(pm.group(1))
                pre_existing_ports.setdefault(mod_name, set()).update(ports)
                # Mirror under the prefixed name(s) so lookups work either way
                for prefix in ('ddrss_umccmd_t_', 'ddrss_'):
                    pre_existing_ports.setdefault(prefix + mod_name, set()).update(ports)
    # Add port_decls from study (mirror under prefixed + bare module names so
    # lookups work whether child_module_name uses tile prefix or not)
    study_ports_per_mod = {}  # module_name → set(port_name)
    for e in study.get('Synthesize', []):
        if e.get('change_type') == 'port_declaration':
            mod = e.get('module_name','')
            sig = e.get('signal_name','')
            if not (mod and sig):
                continue
            study_ports_per_mod.setdefault(mod, set()).add(sig)
            for prefix in ('ddrss_umccmd_t_', 'ddrss_'):
                if mod.startswith(prefix):
                    study_ports_per_mod.setdefault(mod[len(prefix):], set()).add(sig)
                else:
                    study_ports_per_mod.setdefault(prefix + mod, set()).add(sig)
    # Walk every port_connection and verify the target port exists
    for stage in ['Synthesize']:
        for e in study.get(stage, []):
            if e.get('change_type') != 'port_connection':
                continue
            child_mod = e.get('child_module_name') or ''
            inst = e.get('instance_name','?')
            port = e.get('port_name','?')
            if not child_mod:
                issues.append(
                    f"HIGH: port_connection {inst!r} (port {port!r}) is missing "
                    f"the mandatory `child_module_name` field — Step 3 cannot "
                    f"verify the port exists. Without this field a missing "
                    f"port_decl slips to FM and triggers FE-LINK-7 ABORT. "
                    f"Studier must emit child_module_name on every port_connection.")
                continue
            in_pre = port in pre_existing_ports.get(child_mod, set())
            in_study = port in study_ports_per_mod.get(child_mod, set())
            if not (in_pre or in_study):
                issues.append(
                    f"HIGH: port_connection {inst}.{port} → child_module={child_mod!r} "
                    f"references a port that is NEITHER pre-existing in PreEco SynRtl "
                    f"NOR added by a `port_declaration` entry in this study. "
                    f"FM elaboration will FE-LINK-7 ABORT. Add a port_declaration "
                    f"entry for {child_mod}.{port} or reference an existing port name.")

    # ── 4. No empty module_name AND empty instance_scope for new_logic entries
    for stage in ['Synthesize']:
        for e in study.get(stage, []):
            if e.get('change_type') not in ('new_logic_gate','new_logic_dff','new_logic'):
                continue
            if not e.get('confirmed', True):
                continue
            mod = e.get('module_name','')
            scope = e.get('instance_scope','')
            inst = e.get('instance_name','?')
            if not mod and not scope:
                issues.append(f"HIGH: {inst} has no module_name AND no instance_scope — eco_applier cannot find insertion point")

    # ── 5. No UNRESOLVABLE inputs without alternatives on confirmed gates ────
    for stage in ['Synthesize']:
        for e in study.get(stage, []):
            if not e.get('confirmed', True):
                continue
            pcs = e.get('port_connections_per_stage', {}).get(stage) or e.get('port_connections', {})
            inst = e.get('instance_name', '?')
            for pin, net in pcs.items():
                if str(net).startswith('UNRESOLVABLE_IN_'):
                    issues.append(f"MEDIUM: {inst}.{pin} = {net} — condition input unresolved; eco_fenets_runner re-query may be needed")

    # ── 6. and_term changes: GAP-15 result must be present ──────────────────
    and_term_changes = [c for c in rtl_diff.get('changes',[]) if c.get('change_type') == 'and_term']
    gap15_file = Path(args.study.replace('_eco_preeco_study.json', '_eco_gap15_check.json'))
    if and_term_changes and not gap15_file.exists():
        issues.append(f"HIGH: and_term changes present but eco_gap15_check.json missing — eco_gap15_check.py was not run")

    # ── 7. eco_expand_chains must have run ───────────────────────────────────
    marker = Path(args.study).parent / f"{args.tag}_eco_preeco_study_eco_expand_chains_marker.txt"
    if not marker.exists():
        issues.append(f"MEDIUM: eco_expand_chains_marker.txt not found — eco_expand_chains.py may not have run")

    # ── 8. Each rewire entry has old_net, new_net, AND a resolvable cell_name ─
    for stage in ['Synthesize']:
        for e in study.get(stage, []):
            if e.get('change_type') != 'rewire':
                continue
            if not e.get('old_net') or not e.get('new_net'):
                issues.append(f"HIGH: rewire entry {e.get('cell_name','?')} missing old_net or new_net")
            cell = (e.get('cell_name')
                    or (e.get('per_stage_cell_name') or {}).get(stage)
                    or (e.get('cell_name_per_stage') or {}).get(stage)
                    or (e.get('mux_cell_instance_per_stage') or {}).get(stage))
            if not cell:
                issues.append(f"HIGH: rewire entry pin={e.get('pin','?')} {e.get('old_net')}→{e.get('new_net')} has no cell_name in any known field (checked: cell_name, per_stage_cell_name, cell_name_per_stage, mux_cell_instance_per_stage)")

    # ── 9. Every n_eco_* input net must have a driver in some entry's output ─
    OUT_PINS = {'Z','ZN','ZN1','Q','QN','CO'}
    for stage in ['Synthesize', 'PrePlace', 'Route']:
        driven = {n for e in study.get(stage, [])
                    for p, n in (e.get('port_connections') or {}).items()
                    if p in OUT_PINS and isinstance(n, str)}
        for e in study.get(stage, []):
            if not e.get('confirmed', True):
                continue
            for pin, net in (e.get('port_connections') or {}).items():
                if pin in OUT_PINS or not isinstance(net, str):
                    continue
                if net.startswith('n_eco_') and net not in driven:
                    issues.append(f"CRITICAL: {e.get('instance_name','?')}.{pin}={net} in {stage} — undriven ECO net (no entry's Z/ZN/Q drives it)")

    # ── 10. Stale-reference guard: when a port_connection renames net A→B,
    # no other entry's input pin may still reference A (becomes stale post-Step 4)
    for stage in ['Synthesize', 'PrePlace', 'Route']:
        renames = {}  # old_net → new_net
        for e in study.get(stage, []):
            nb = e.get('net_name_before')
            na = e.get('net_name_after')
            if isinstance(nb, dict):
                nb = nb.get(stage)
            if nb and na:
                renames[nb] = na
        for e in study.get(stage, []):
            if not e.get('confirmed', True):
                continue
            for pin, net in (e.get('port_connections') or {}).items():
                if pin in OUT_PINS or not isinstance(net, str):
                    continue
                if net in renames:
                    issues.append(f"HIGH: {e.get('instance_name','?')}.{pin}={net} in {stage} — net is being renamed to {renames[net]} by another entry; update this reference or skip the rename")

    # ── 11. Mode I — UNCONNECTED bus rename at parent must be paired with
    # child-scope wire-up entry when child output port is internally undriven.
    # Without the pair, parent renames a dangling pin → FM sees X → DFF0X.
    # Detect by netlist scan: open child module body and check whether the
    # matching bit slot at any sub-instance bus is also UNCONNECTED_*.
    import gzip, re as _re
    _child_bodies = {}  # module_name → comment-stripped body text
    def _load_child_body(mod):
        if mod in _child_bodies:
            return _child_bodies[mod]
        body = ''
        for stage in ('Synthesize',):
            # Prefer round-1 backup (pristine pre-Step4); fall back to current PostEco
            base = os.path.join(args.ref_dir, 'data', 'PostEco')
            cands = sorted(os.path.join(base, n) for n in (os.listdir(base) if os.path.isdir(base) else []) if n.startswith(f'{stage}.v.gz.bak_'))
            gz = cands[0] if cands else os.path.join(base, f'{stage}.v.gz')
            if not os.path.exists(gz):
                continue
            try:
                with gzip.open(gz, 'rt') as fh: text = fh.read()
            except Exception:
                continue
            text = _re.sub(r'/\*.*?\*/', '', text, flags=_re.DOTALL)
            text = _re.sub(r'//[^\n]*', '', text)
            m = _re.search(rf'^module\s+{_re.escape(mod)}\b.*?^endmodule\b', text, _re.DOTALL | _re.MULTILINE)
            if m:
                body = m.group(0); break
        _child_bodies[mod] = body
        return body
    if os.path.isdir(os.path.join(args.ref_dir, 'data', 'PostEco')):
        for stage in ['Synthesize']:
            for e in study.get(stage, []):
                if e.get('change_type') != 'port_connection': continue
                if not e.get('confirmed', True): continue
                if e.get('bus_bit_index') is None: continue
                orig = e.get('original_unconnected_net', '') or ''
                if not orig.startswith(('UNCONNECTED_', 'SYNOPSYS_UNCONNECTED_')): continue
                child_mod = e.get('submodule_type') or ''
                bbi = e.get('bus_bit_index')
                port = e.get('port_name') or ''
                if not child_mod or not port: continue
                # Look for the paired child-scope entry: module_name=child_mod, bus_bit_index=bbi
                paired = any(
                    p.get('change_type') == 'port_connection'
                    and (p.get('module_name') == child_mod or p.get('parent_module') == child_mod)
                    and p.get('bus_bit_index') == bbi
                    and (p.get('net_name') or '') == f"{port}[{bbi}]"
                    for p in study.get(stage, []))
                if paired: continue
                # Confirm child body has UNCONNECTED at this bit position of any sub-inst bus
                body = _load_child_body(child_mod)
                if not body: continue
                # Heuristic: any sub-instance with bus port containing UNCONNECTED_\d+ at the same MSB-first position
                hit = False
                for cm in _re.finditer(r'\.\s*(\w+)\s*\(\s*\{([^{}]+)\}\s*\)', body):
                    elems = [x.strip() for x in cm.group(2).split(',') if x.strip()]
                    pos = len(elems) - 1 - bbi
                    if 0 <= pos < len(elems) and _re.match(r'^(SYNOPSYS_)?UNCONNECTED_\d+$', elems[pos]):
                        hit = True; break
                if hit:
                    issues.append(f"CRITICAL: Mode I gap — parent rename of {orig} at {child_mod}.{port}[{bbi}] but no paired child-scope port_connection wires {port}[{bbi}] internally. Add entry: module_name={child_mod}, bus_bit_index={bbi}, net_name={port}[{bbi}]")

    # ── 12. Cell truth-table check: every new_logic_gate's cell_type must
    # actually compute the claimed gate_function. Catches the case where a
    # cell name suggests one boolean function but the library cell computes
    # a different one (common for inverter-input compound cells).
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    try:
        import eco_cell_truth_tables as _ett
    except ImportError:
        _ett = None
    if _ett is not None:
        for stage in ['Synthesize']:  # truth table is stage-invariant
            for e in study.get(stage, []):
                if e.get('change_type') not in ('new_logic_gate', 'new_logic'): continue
                if not e.get('confirmed', True): continue
                cell = e.get('cell_type', '')
                fn = e.get('gate_function', '')
                if not cell or not fn: continue
                m, why = _ett.cell_function_matches(cell, fn, ref_dir=args.ref_dir)
                inst = e.get('instance_name', '?')
                if m is False:
                    issues.append(f"CRITICAL: ECO {inst} cell_type={cell!r} does NOT compute claimed gate_function={fn!r} — {why}. Pick a cell whose family matches, or update gate_function to reflect actual cell logic.")
                elif m is None and _ett.family_of(cell) and fn not in _ett.ABSTRACT_GATE_FUNCTIONS:
                    # Both unknown → uncovered cell; warn so the library JSON can be extended
                    issues.append(f"MEDIUM: ECO {inst} cell_type={cell!r} (family={_ett.family_of(cell)!r}) and gate_function={fn!r} not covered — cannot verify functional correctness. Add to script/eco_scripts/cell_libraries/<your_lib>.json.")

    # ── 13. Scan-bridge SE/SI for new ECO DFFs in P&R: WARN when SE/SI is a
    # constant in P&R stages. Constants may pass FM if the DFF's clock cone
    # doesn't cross scan_cntl logic (e.g. CP=wrp_clk_*), but they fail when
    # CP touches the main clock domain (CP=UCLK*) — the new DFF appears as a
    # scan-isolated island. MEDIUM (not CRITICAL) because the right answer
    # depends on the DFF's clock cone depth, which the validator can't fully
    # determine without simulating FM's cone analysis.
    for stage in ['PrePlace', 'Route']:
        for e in study.get(stage, []):
            if e.get('change_type') not in ('new_logic_dff', 'new_logic'): continue
            if not e.get('confirmed', True): continue
            inst = e.get('instance_name', '?')
            pcs = (e.get('port_connections_per_stage') or {}).get(stage) or e.get('port_connections') or {}
            cp  = pcs.get('CP', '')
            for pin in ('SE', 'SI'):
                v = pcs.get(pin)
                if isinstance(v, str) and v.strip() in ("1'b0", "1'b1", "0", "1"):
                    risk = ("HIGH-RISK" if isinstance(cp, str) and cp.upper().startswith(('UCLK','CLK','MCLK'))
                            else "low-risk")
                    issues.append(f"MEDIUM: ECO DFF {inst}.{pin} in {stage} = {v!r} (constant) — {risk} of scan-cone divergence (CP={cp!r}). If FM rejects this DFF, hook to a neighboring DFF's per-stage {pin} net (Mode S scan-stitching).")

    # ── 14. Per-stage CP/SE/SI must come from an existing DFF in the same scope
    # for each stage. Catches "force same-as-Synthesize" anti-pattern and
    # ensures per-stage net names actually exist.
    # _neighbors helper is hoisted to function scope so Check 25 (per-stage
    # wrapper-clock detection) can reuse the same cache without re-reading
    # 50MB+ gz files.
    import gzip as _gz
    neighbor_cache = {}
    def _neighbors(stage, mod):
        key = (stage, mod)
        if key in neighbor_cache:
            return neighbor_cache[key]
        base = os.path.join(args.ref_dir, 'data', 'PostEco')
        cands = sorted(os.path.join(base, n) for n in (os.listdir(base) if os.path.isdir(base) else []) if n.startswith(f'{stage}.v.gz.bak_'))
        gz = cands[0] if cands else os.path.join(base, f'{stage}.v.gz')
        sets = {'CP': set(), 'SE': set(), 'SI': set()}
        if os.path.exists(gz):
            try:
                with _gz.open(gz, 'rt') as f: text = f.read()
                text = _re.sub(r'/\*.*?\*/', '', text, flags=_re.DOTALL)
                text = _re.sub(r'//[^\n]*', '', text)
                body_m = _re.search(rf'^module\s+{_re.escape(mod)}(?:_0)?\b.*?^endmodule\b', text, _re.DOTALL | _re.MULTILINE)
                if body_m:
                    body = body_m.group(0)
                    for pin in ('CP', 'SE', 'SI'):
                        for m in _re.finditer(rf'\.\s*{pin}\s*\(\s*([^)]+?)\s*\)', body):
                            sets[pin].add(m.group(1).strip())
            except Exception:
                pass
        neighbor_cache[key] = sets
        return sets
    if os.path.isdir(os.path.join(args.ref_dir, 'data', 'PostEco')):
        for stage in ['Synthesize', 'PrePlace', 'Route']:
            for e in study.get(stage, []):
                if e.get('change_type') not in ('new_logic_dff', 'new_logic'): continue
                if not e.get('confirmed', True): continue
                inst = e.get('instance_name', '?')
                mod  = e.get('module_name')
                if not mod: continue
                pcs = (e.get('port_connections_per_stage') or {}).get(stage) or e.get('port_connections') or {}
                neigh = _neighbors(stage, mod)
                # Mode S exemption: when the DFF is bridged via Mode S ports, the
                # SE/SI nets are by design new bridge ports that no existing DFF
                # uses. Skip the SE/SI mismatch check for these — Check 3c already
                # verifies the bridge ports are declared.
                mode_s_active = bool(e.get('mode_S_applied') or e.get('requires_scan_stitching'))
                for pin in ('CP', 'SE', 'SI'):
                    v = pcs.get(pin)
                    if not isinstance(v, str) or not neigh.get(pin):
                        continue
                    if mode_s_active and pin in ('SE', 'SI'):
                        continue
                    # Constant on SE/SI in Synthesize is always OK; constant in P&R
                    # is covered by Check 15 (skip duplicate flag here).
                    if v.strip() in ("1'b0", "1'b1") and pin in ('SE', 'SI'):
                        continue
                    if v.strip() not in neigh[pin]:
                        sample = list(neigh[pin])[:3]
                        # CP mismatch: HIGH (real failure mode — clock cone divergence).
                        # SE/SI mismatch: MEDIUM (engineer may legitimately use parent-scope
                        # bridge wires not in module-scope neighbor set).
                        sev = "HIGH" if pin == "CP" else "MEDIUM"
                        issues.append(f"{sev}: ECO DFF {inst}.{pin} in {stage}={v!r} not used by any existing DFF in module {mod!r}. Existing values include {sample}. {'Pick one of those' if pin == 'CP' else 'Either pick a neighbor value OR add as new bridge port'} for per-stage consistency.")

    # ── 25. PER-STAGE-CP-WRAPPER-CLOCK: detect tile-top wrapper-clock swap.
    # At tile-top wrapper scope, RTL DFFs use the raw clock (e.g. UCLK01) in
    # Synthesize, but P&R inserts wrapper clock-gating cells that derive
    # `wrp_clk_*` and existing module-sibling DFFs use the wrapper clock in
    # PP/Route. A new ECO DFF at this scope MUST swap CP per stage:
    #   Synthesize: <UCLK*>     PP: wrp_clk_*     Route: wrp_clk_*
    # Engineer 9868 EcoUseSdpOutstRdCnt does exactly this. Without the swap,
    # the new DFF runs on a different clock from its module siblings — passes
    # FM cone equivalence (UCLK01 ≡ wrp_clk_1 logically) but breaks DFT scan
    # testability and clock-gating coverage. Reuses _neighbors() cache from
    # Check 14.
    if os.path.isdir(os.path.join(args.ref_dir, 'data', 'PostEco')):
        for e in study.get('Synthesize', []):
            if e.get('change_type') not in ('new_logic_dff', 'new_logic'):
                continue
            if not e.get('confirmed', True):
                continue
            inst = e.get('instance_name', '?')
            mod  = e.get('module_name')
            if not mod:
                continue
            pcs_per_stage = e.get('port_connections_per_stage') or {}
            # Detect the wrapper-clock domain by inspecting PrePlace neighbor CPs
            # (RTL-level naming wrp_clk_* survives into PP; Route stage applies
            # CTS-renaming so wrp_clk_1 might become FxCts_ZCTSNET_<N>).
            pp_neigh = _neighbors('PrePlace', mod)
            pp_neigh_cps = list(pp_neigh.get('CP', set()))
            if not pp_neigh_cps:
                continue
            wrp_pp = [n for n in pp_neigh_cps if _re.search(r'wrp_clk', n, _re.IGNORECASE)]
            if not wrp_pp:
                continue  # no wrapper-clock present in this module
            # PrePlace check — when wrapper clock exists in module AND new DFF uses
            # raw UCLK (the Synth-stage clock), studier missed the wrapper swap.
            pp_cp = (pcs_per_stage.get('PrePlace', {}) or {}).get('CP', '').strip()
            if pp_cp and _re.match(r'UCLK\d?$', pp_cp, _re.IGNORECASE):
                sample = sorted(set(wrp_pp))[:3]
                issues.append(
                    f"HIGH/25-WRAPPER-CLOCK-MISSED: ECO DFF {inst}.CP in PrePlace "
                    f"= {pp_cp!r} but {len(wrp_pp)}/{len(pp_neigh_cps)} existing "
                    f"DFFs in module {mod!r} use wrapper clock(s) {sample}. New "
                    f"DFFs at this scope MUST swap CP per stage: Synth keeps the "
                    f"raw clock (UCLK*), but PP MUST use wrp_clk_*. Otherwise the "
                    f"DFF runs on a different clock domain from its siblings — "
                    f"breaks clock-gating and DFT scan coverage. Update "
                    f"port_connections_per_stage['PrePlace'].CP to one of the "
                    f"wrp_clk_* nets above.")
            # Route check — CP must be in Route's neighbor CP set (CTS-renamed
            # wrapper). Reject UCLK01 (raw clock) AND non-CP-domain values.
            rt_cp = (pcs_per_stage.get('Route', {}) or {}).get('CP', '').strip()
            rt_neigh = _neighbors('Route', mod)
            rt_neigh_cps = rt_neigh.get('CP', set())
            if rt_cp and rt_neigh_cps:
                # Route CP should NOT be the raw UCLK* (that's the Synth-stage clock)
                # AND should be in the existing module DFF CP set.
                if _re.match(r'UCLK\d', rt_cp, _re.IGNORECASE):
                    sample = sorted(c for c in rt_neigh_cps if 'fxcts' in c.lower() or 'wrp_clk' in c.lower())[:3]
                    issues.append(
                        f"HIGH/25-WRAPPER-CLOCK-MISSED: ECO DFF {inst}.CP in Route "
                        f"= {rt_cp!r} (raw clock) but module {mod!r} is wrapper-clock "
                        f"dominated. Route CP must be a CTS-renamed wrapper clock "
                        f"(e.g. {sample}); using the raw UCLK clock leaves the new "
                        f"DFF on a different clock domain from siblings.")

    # ── 15. Every confirmed entry must have non-empty `reason`, `notes`, and
    # `source` — these populate the Step 3 RPT and serve as the audit trail for
    # round-N re-studier. Empty fields = un-traceable change.
    REQUIRED_CTX = ('reason', 'notes', 'source')
    for stage in ['Synthesize']:  # check Synthesize as canonical; per-stage entries inherit
        for e in study.get(stage, []):
            if not e.get('confirmed', True): continue
            inst = e.get('instance_name') or e.get('cell_name') or e.get('signal_name', '?')
            ct = e.get('change_type', '?')
            missing = [k for k in REQUIRED_CTX if not (e.get(k) or '').strip()]
            if missing:
                issues.append(f"MEDIUM: {ct} {inst} missing context field(s) {missing} — studier must populate `reason`/`notes`/`source` per eco_netlist_studier.md 0e.")

    # ── 16. Chain-injection schema: every gate entry produced by
    #         eco_expand_chains.py must carry the structural fields the applier
    #         depends on. Catches silently malformed chain output before it
    #         poisons Step 4.
    REQUIRED_GATE_FIELDS = ('instance_name', 'cell_type', 'gate_function', 'port_connections')
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        for e in study.get(stage, []):
            if e.get('change_type') != 'new_logic_gate':
                continue
            inst = e.get('instance_name', '?')
            missing = [f for f in REQUIRED_GATE_FIELDS if not e.get(f)]
            if missing:
                issues.append(f"CRITICAL: chain-injection schema — new_logic_gate {inst} in {stage} missing {missing}; eco_expand_chains.py output malformed")
                continue
            pcs = e.get('port_connections', {})
            if not isinstance(pcs, dict) or not pcs:
                issues.append(f"CRITICAL: chain-injection schema — new_logic_gate {inst} in {stage} has empty port_connections")
                continue
            for pin, net in pcs.items():
                if net is None or (isinstance(net, str) and not net.strip()):
                    issues.append(f"CRITICAL: chain-injection schema — new_logic_gate {inst}.{pin} in {stage} = {net!r} (empty/null)")

    # ── 17. Strategy/Entry mutual exclusion: bridge plumbing entries
    #        (sibling_pin_consolidation, si_consumer_replace, port_declaration /
    #        port_connection with bridge_port_role or is_mode_s_stitch) are valid
    #        ONLY when the corresponding DFF's PP/Route port_connections_per_stage
    #        actually consume those bridge port names. Mixing — bridge plumbing
    #        emitted but DFF SI/SE wired to neighbor wires — leaves the bridge
    #        ports declared on host with no parent wireup → Step 5 catches it as
    #        MODE_S_BRIDGE_NOT_WIRED. Catch it here at Step 3 instead.
    has_neighbor_dff = False
    has_bridge_port  = False
    dff_pcs_wires = set()  # all SI/SE values used by new DFFs in PP/Route
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        for e in study.get(stage, []):
            if e.get('change_type') not in ('new_logic_dff', 'new_logic'):
                continue
            strat_per_stage = e.get('mode_S_strategy_per_stage') or {}
            for s in ('PrePlace', 'Route'):
                v = strat_per_stage.get(s)
                if v == 'neighbor_dff':
                    has_neighbor_dff = True
                elif v == 'bridge_port':
                    has_bridge_port = True
                pcs = (e.get('port_connections_per_stage') or {}).get(s) or {}
                for pin in ('SI', 'SE'):
                    w = pcs.get(pin)
                    if isinstance(w, str) and w.strip() not in ("1'b0", "1'b1", ''):
                        dff_pcs_wires.add(w.strip())
    BRIDGE_TYPES = ('sibling_pin_consolidation', 'si_consumer_replace')
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        for e in study.get(stage, []):
            ct = e.get('change_type')
            is_bridge_artifact = (
                ct in BRIDGE_TYPES
                or e.get('bridge_port_role')
                or (ct in ('port_declaration', 'port_connection') and e.get('is_mode_s_stitch'))
            )
            if not is_bridge_artifact:
                continue
            # Strategy explicitly declared neighbor_dff → forbidden
            if has_neighbor_dff and not has_bridge_port:
                issues.append(
                    f"HIGH: Strategy/Entry contradiction — bridge artifact {ct!r} "
                    f"({e.get('port_name') or e.get('change_index') or e.get('sibling_module','?')!r}) "
                    f"in {stage} but no DFF uses bridge_port strategy. "
                    f"Either switch the DFF's mode_S_strategy_per_stage to bridge_port "
                    f"(and wire SI/SE to the bridge port names), or drop this bridge entry.")
                continue
            # No explicit strategy, but bridge port name not actually consumed by any DFF SI/SE
            if ct == 'port_declaration' and e.get('is_mode_s_stitch'):
                pn = e.get('port_name', '')
                if pn and pn not in dff_pcs_wires:
                    issues.append(
                        f"HIGH: Bridge port {pn!r} declared in {stage} on module "
                        f"{e.get('module_name','?')!r} but no new DFF's SI/SE consumes it "
                        f"in port_connections_per_stage — Step 5 will fail with "
                        f"MODE_S_BRIDGE_NOT_WIRED. Either wire DFF SI/SE to {pn!r}, "
                        f"or drop this port_declaration (strategy is neighbor_dff).")

    # ── 18. Q-closure consumer must structurally exist in the named sibling.
    #        si_consumer_replace.consumer_dff_inst MUST appear in sibling_module's
    #        body in the PreEco netlist; otherwise applier silently no-ops.
    seen_consumer_check = set()
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        for e in study.get(stage, []):
            if e.get('change_type') != 'si_consumer_replace':
                continue
            sib = e.get('sibling_module', '') or ''
            consumer = e.get('consumer_dff_inst', '') or ''
            key = (sib, consumer)
            if not sib or not consumer or key in seen_consumer_check:
                continue
            seen_consumer_check.add(key)
            # Module-scoped grep in PreEco PrePlace
            netlist = f'{args.ref_dir}/data/PreEco/PrePlace.v.gz'
            if not Path(netlist).exists():
                continue
            try:
                # Extract sibling module body, then count consumer instances
                cmd = (f"zcat '{netlist}' | "
                       f"awk '/^module\\s+\\S*{re.escape(sib.replace('ddrss_umccmd_t_',''))}/,"
                       f"/^endmodule/' | "
                       f"grep -c '\\b{re.escape(consumer)}\\b'")
                r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
                count = int(r.stdout.strip() or '0')
            except Exception:
                count = -1
            if count == 0:
                issues.append(
                    f"HIGH: Q-closure consumer {consumer!r} not found in sibling "
                    f"{sib!r} body (PreEco PrePlace). Applier will silently no-op the "
                    f".SI rewire — DFT scan break + FM Und cut-point.")

    # ── 19. Per-stage wire existence: pcs[stage].SI and .SE MUST exist in the
    #        corresponding stage's PreEco netlist. Catches the PP→Route copy-paste
    #        bug where studier reuses PP wire names that CTS removed in Route.
    seen_wire_check = set()
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        netlist = f'{args.ref_dir}/data/PreEco/{stage}.v.gz'
        if not Path(netlist).exists():
            continue
        for e in study.get(stage, []):
            if e.get('change_type') not in ('new_logic_dff', 'new_logic'):
                continue
            inst = e.get('instance_name', '?')
            pcs = e.get('port_connections_per_stage', {}).get(stage, {}) or {}
            for pin in ('SI', 'SE'):
                wire = pcs.get(pin)
                if not isinstance(wire, str) or not wire:
                    continue
                # Skip constants and ECO-introduced ports/wires
                if wire.startswith(("1'b", "0'b", "1'h")) or wire.startswith(('ECO_', 'eco')):
                    continue
                key = (stage, wire)
                if key in seen_wire_check:
                    continue
                seen_wire_check.add(key)
                try:
                    r = subprocess.run(
                        f"zgrep -c '\\b{re.escape(wire)}\\b' '{netlist}'",
                        shell=True, capture_output=True, text=True, timeout=30)
                    count = int(r.stdout.strip() or '0')
                except Exception:
                    count = -1
                if count == 0:
                    issues.append(
                        f"CRITICAL: Per-stage wire missing — DFF {inst} stage={stage} "
                        f".{pin}={wire!r} does NOT exist in PreEco/{stage}.v.gz "
                        f"(0 hits). Likely PP→Route copy-paste; studier MUST run "
                        f"per-stage neighbor_dff lookup independently from each stage's netlist.")

    # ── 20. Consolidation cluster minimum size: when bridge_port is chosen,
    #        sibling_pin_consolidation.consolidation_target_dffs MUST have ≥10
    #        DFF instances. Smaller clusters indicate weak scan-en cluster — bridge
    #        is symbolic only and FM cone matching is unstable.
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        for e in study.get(stage, []):
            if e.get('change_type') != 'sibling_pin_consolidation':
                continue
            tgts = e.get('consolidation_target_dffs') or []
            if len(tgts) < 10:
                issues.append(
                    f"HIGH: Consolidation cluster too small — sibling_pin_consolidation "
                    f"in {stage} sibling={e.get('sibling_module','?')!r} pin={e.get('pin_name','?')!r} "
                    f"has only {len(tgts)} DFFs (minimum 10). The picker found a sparse "
                    f"scan-en cluster — bridge will not be a meaningful scan path. "
                    f"Either re-pick sibling with stronger cluster, or fall back to "
                    f"neighbor_dff strategy for this DFF.")

    # ── 21. mode_S_applied consistency: when mode_S_strategy_per_stage names a real
    #        scan-integration strategy (neighbor_dff or bridge_port) for any P&R
    #        stage, mode_S_applied MUST be true. Null/false silently disables
    #        Mode S downstream.
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        for e in study.get(stage, []):
            if e.get('change_type') not in ('new_logic_dff', 'new_logic'):
                continue
            strat = e.get('mode_S_strategy_per_stage') or {}
            real_pp_rt = any(strat.get(s) in ('neighbor_dff', 'bridge_port')
                             for s in ('PrePlace', 'Route'))
            if real_pp_rt and e.get('mode_S_applied') is not True:
                issues.append(
                    f"HIGH: mode_S_applied missing — DFF {e.get('instance_name','?')} in {stage} "
                    f"has real Mode-S strategy in PP/Route ({strat}) but mode_S_applied="
                    f"{e.get('mode_S_applied')!r}. Set mode_S_applied: true so downstream "
                    f"recognizes the DFF as Mode-S handled.")

    # ── 22. CTS-touched Route scan wire forces bridge_port. When neighbor_dff is
    # picked for Route and the chosen SE/SI is on a post-CTS or post-OPT-CTS
    # wire, FM cone walks through CTS infrastructure that DIFFERS between PreEco
    # and PostEco (CTS rebalances when a new DFF changes fanout/loading) → cone
    # divergence → Failing Compare Points. Safe fix: bridge_port routes SI/SE
    # through fresh parent-level ports so the ECO DFF stays off the CTS tree.
    # PrePlace HFSNET wires are NOT flagged — HFS is deterministic w.r.t. fanout
    # so PreEco-PP and PostEco-PP HFSNET topology matches; PP=neighbor_dff with
    # HFSNET is engineer's actual pattern and FM-safe.
    CTS_TOUCHED = _re.compile(r'(FxOptCts_|FxCts_|_CLKBUF_|_CTSBUF_)', _re.IGNORECASE)
    for stage in ('Route',):
        for e in study.get(stage, []):
            if e.get('change_type') not in ('new_logic_dff', 'new_logic'):
                continue
            if not e.get('requires_scan_stitching'):
                continue
            if not e.get('confirmed', True):
                continue
            inst = e.get('instance_name') or e.get('dff_instance_name', '?')
            pcs  = (e.get('port_connections_per_stage') or {}).get(stage) or {}
            strat = (e.get('mode_S_strategy_per_stage') or {}).get(stage) or 'neighbor_dff'
            for pin in ('SE', 'SI'):
                v = pcs.get(pin, '')
                if not isinstance(v, str) or v.strip() in ("1'b0", "1'b1"):
                    continue
                if not CTS_TOUCHED.search(v):
                    continue
                # Allow bridge_port to use any wire (it's a parent-level port
                # name, not a direct CTS net hookup).
                if strat == 'bridge_port':
                    continue
                issues.append(
                    f"HIGH: ECO DFF {inst}.{pin} in {stage} = {v!r} is on a CTS/OPT-touched scan wire — "
                    f"strategy={strat!r} hooks the new DFF directly into the post-CTS scan cone, which "
                    f"FM walks through CTS infrastructure that does not exist in PreEco → cone divergence "
                    f"→ Failing Compare Points. MUST switch to bridge_port: route SI/SE through fresh "
                    f"parent-level ports + sibling consolidation (see eco_pick_bridge_dffs.py output). "
                    f"Bridge_port keeps the new DFF OFF the CTS-touched scan tree.")

    # ── 23. BRIDGE-SOURCE-IN-MAP: when bridge_port strategy is chosen for any
    # P&R stage, the anchor wire driving that bridge MUST appear as a key in
    # eco_fenets_rename_map.json. Missing key = FM-036 silent failure upstream
    # → studier has no per-stage equivalence data → bridges built on guessed
    # wires → FM Route divergence. Force a hard failure here so the orchestrator
    # restarts Step 1+2 with corrected mode_s_anchor.fm_scope.
    rename_map_path = args.study.replace('_eco_preeco_study.json', '_eco_fenets_rename_map.json')
    if os.path.isfile(rename_map_path):
        try:
            rmap = json.loads(Path(rename_map_path).read_text())
        except Exception:
            rmap = {}
        rmap_keys = set(k for k in rmap.keys() if k != '_metadata')
        for stage in ('Synthesize', 'PrePlace', 'Route'):
            for e in study.get(stage, []):
                if e.get('change_type') not in ('new_logic_dff', 'new_logic'):
                    continue
                strat = e.get('mode_S_strategy_per_stage') or {}
                inst = e.get('instance_name') or e.get('dff_instance_name', '?')
                # Surface the explicit BLOCKED marker as a hard fail
                for s in ('PrePlace', 'Route'):
                    if strat.get(s) == 'BLOCKED_NO_RENAME_MAP':
                        issues.append(
                            f"HIGH: ECO DFF {inst} stage={s} mode_S_strategy="
                            f"'BLOCKED_NO_RENAME_MAP' — studier could not find rename_map "
                            f"entry for the chosen anchor wire. Re-run Step 1 with "
                            f"corrected mode_s_anchor.fm_scope (instance hierarchy, NOT "
                            f"module-type names), then re-run Step 2.")
                # If bridge_port chosen but anchor wires aren't in rename_map → fail
                bridges_used = [s for s in ('PrePlace', 'Route') if strat.get(s) == 'bridge_port']
                if not bridges_used:
                    continue
                # Pull anchor wires from the ECO DFF's source rtl_diff change
                ci = e.get('change_index')
                src_change = next((c for c in (rtl_diff.get('changes') or []) if c.get('change_index') == ci), None)
                if not src_change:
                    continue
                anc = src_change.get('mode_s_anchor') or {}
                for role, field in (('SI', 'anchor_si_wire'), ('SE', 'anchor_se_wire')):
                    wire = anc.get(field)
                    if not wire:
                        continue
                    # Match wire against rename_map keys (suffix or exact)
                    hit = (wire in rmap_keys) or any(k.endswith('/' + wire) for k in rmap_keys)
                    if not hit:
                        issues.append(
                            f"HIGH/23-BRIDGE-SOURCE-IN-MAP: ECO DFF {inst} uses bridge_port "
                            f"strategy in {bridges_used} but anchor {role} wire {wire!r} has "
                            f"NO entry in {os.path.basename(rename_map_path)} — FM did not "
                            f"return per-stage equivalence (likely FM-036). Bridge would be "
                            f"built on a wire studier never validated across PP/Route → FM "
                            f"divergence guaranteed. Fix Step 1 mode_s_anchor.fm_scope and "
                            f"re-run Step 2 before retrying Step 3.")

    # ── 24. BRIDGE-ARTIFACT-SET-COMPLETE: when any new DFF uses bridge_port
    # strategy in PP or Route, the study MUST contain the COMPLETE set of ~17
    # artifact types per bridge. The previous failure mode (run 20260511083831):
    # Studier emitted bridge port_declarations on the host module but skipped
    # parent wire_declarations, parent instance_hookups, sibling buffer cells,
    # sibling consolidation, and Q-closure → FM elaboration ABORTED on every
    # target because parent scope referenced undeclared bridge wires. Step 5
    # didn't catch it (only validates per-module syntax), Step 6 wasted FM
    # runtime to discover it.
    #
    # Required artifact types per bridge (run eco_emit_bridge_plumbing.py to
    # generate them deterministically):
    #   1. port_declaration × 6 (host SI/SE/Q + sibling SI/SE/Q)
    #   2. wire_declaration × 3 (parent-scope bridge wires)
    #   3. port_connection × 6 (parent-scope instance hookups: host + sibling)
    #   4. sibling_pin_consolidation × ≥1 (SE pin, ≥10 DFF cluster)
    #   5. si_consumer_replace × 1 (Q-closure)
    #   6. new_logic × 2 (Route only: SI buffer + SE buffer)
    REQUIRED_ROLES_ALL_STAGES = {
        # role → (change_type, count, description)
        ('host_si',     'port_declaration'): 'host SI bridge input port',
        ('host_se',     'port_declaration'): 'host SE bridge input port',
        ('host_q',      'port_declaration'): 'host Q bridge output port',
        ('sibling_si',  'port_declaration'): 'sibling SI bridge output port',
        ('sibling_se',  'port_declaration'): 'sibling SE bridge output port',
        ('sibling_q',   'port_declaration'): 'sibling Q bridge input port',
        ('parent_wire', 'wire_declaration'): 'parent-scope bridge wires (need ≥3)',
        ('host_si',     'port_connection'):  'parent hookup: host instance .SI_in(bridge)',
        ('host_se',     'port_connection'):  'parent hookup: host instance .SE_in(bridge)',
        ('host_q',      'port_connection'):  'parent hookup: host instance .Q_out(bridge)',
        ('sibling_si',  'port_connection'):  'parent hookup: sibling instance .SI_out(bridge)',
        ('sibling_se',  'port_connection'):  'parent hookup: sibling instance .SE_out(bridge)',
        ('sibling_q',   'port_connection'):  'parent hookup: sibling instance .Q_in(bridge)',
    }
    REQUIRED_ROLES_PP_ROUTE = {
        ('sibling_se', 'sibling_pin_consolidation'): 'sibling SE-pin consolidation (≥10 DFFs)',
        ('sibling_q',  'si_consumer_replace'):       'Q-closure: rewire sibling DFF.SI to Q_in',
    }
    REQUIRED_ROLES_ROUTE_ONLY = {
        ('sibling_si_driver', 'new_logic'): 'Route: SI bridge buffer cell',
        ('sibling_se_driver', 'new_logic'): 'Route: SE bridge buffer cell',
    }
    # Collect (for_dff, mode_S_strategy_per_stage) for every DFF that picked bridge_port
    bridge_dffs = []
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        for e in study.get(stage, []):
            if e.get('change_type') not in ('new_logic_dff', 'new_logic'):
                continue
            strat = e.get('mode_S_strategy_per_stage') or {}
            stages_using_bridge = [s for s in ('PrePlace', 'Route') if strat.get(s) == 'bridge_port']
            if stages_using_bridge:
                bridge_dffs.append({
                    'inst':   e.get('instance_name') or e.get('dff_instance_name', '?'),
                    'stages': stages_using_bridge,
                })
    # Dedupe (same DFF appears in all 3 stage entries)
    seen = set(); uniq_bridge_dffs = []
    for b in bridge_dffs:
        if b['inst'] in seen: continue
        seen.add(b['inst']); uniq_bridge_dffs.append(b)
    for bd in uniq_bridge_dffs:
        inst = bd['inst']
        # Build per-stage role-set for this DFF
        for stage in ('Synthesize', 'PrePlace', 'Route'):
            if stage not in ('PrePlace', 'Route') and stage not in bd['stages']:
                # Synth requires the all-stage subset only when ANY P&R stage is bridge_port
                pass
            present = set()
            wire_count = 0
            for e in study.get(stage, []):
                # Match entries tagged for THIS DFF (if for_dff field present) or
                # any bridge artifact (if studier didn't tag — be lenient on legacy).
                if e.get('for_dff') and e.get('for_dff') != inst:
                    continue
                role = e.get('bridge_port_role')
                ct = e.get('change_type')
                if not role or not ct:
                    continue
                present.add((role, ct))
                if (role, ct) == ('parent_wire', 'wire_declaration'):
                    wire_count += 1
            # Always-required roles
            for key, desc in REQUIRED_ROLES_ALL_STAGES.items():
                if key not in present:
                    issues.append(
                        f"HIGH/24-BRIDGE-ARTIFACT-MISSING: ECO DFF {inst} stage={stage} "
                        f"missing {key[1]} with bridge_port_role={key[0]!r} ({desc}). "
                        f"Run eco_emit_bridge_plumbing.py and splice its {stage} list "
                        f"into the study; do NOT hand-derive bridge artifacts.")
            # PP/Route-required roles
            if stage in ('PrePlace', 'Route'):
                for key, desc in REQUIRED_ROLES_PP_ROUTE.items():
                    if key not in present:
                        issues.append(
                            f"HIGH/24-BRIDGE-ARTIFACT-MISSING: ECO DFF {inst} stage={stage} "
                            f"missing {key[1]} with bridge_port_role={key[0]!r} ({desc}). "
                            f"Bridge_port without consolidation/Q-closure leaves sibling "
                            f"output ports undriven → FM ABORT on elaboration.")
            # Route-only roles (buffers)
            if stage == 'Route':
                for key, desc in REQUIRED_ROLES_ROUTE_ONLY.items():
                    if key not in present:
                        issues.append(
                            f"HIGH/24-BRIDGE-ARTIFACT-MISSING: ECO DFF {inst} stage=Route "
                            f"missing {key[1]} with bridge_port_role={key[0]!r} ({desc}). "
                            f"Without buffer cells the sibling output port has no driver "
                            f"→ FM ABORT.")
            # Wire count: parent_wire role must appear ≥3 times (si/se/q bridges)
            if wire_count < 3 and ('parent_wire', 'wire_declaration') in present:
                issues.append(
                    f"HIGH/24-BRIDGE-WIRE-COUNT: ECO DFF {inst} stage={stage} has only "
                    f"{wire_count} parent_wire wire_declaration(s); need ≥3 (si/se/q "
                    f"bridges). eco_emit_bridge_plumbing.py emits all 3 — partial "
                    f"emission means studier hand-edited the output.")
            # Consolidation cluster size sanity (separate from Check 20 which
            # checks per-entry; this checks per-DFF-bridge presence)
            for e in study.get(stage, []):
                if e.get('change_type') != 'sibling_pin_consolidation':
                    continue
                if e.get('for_dff') and e.get('for_dff') != inst:
                    continue
                cluster = e.get('consolidation_target_dffs') or []
                if len(cluster) < 10:
                    issues.append(
                        f"HIGH/24-CONSOLIDATION-TOO-SMALL: ECO DFF {inst} stage={stage} "
                        f"sibling_pin_consolidation cluster has {len(cluster)} DFFs "
                        f"(<10). Bridge_port requires ≥10-DFF cluster (per studier MD §374) "
                        f"or fall back to neighbor_dff strategy.")

    # ── 26. NAMED-NET FORMAT + SCOPE-LEAK SUSPECT DETECTION ────────────────
    # Two related checks for unconnected_rewires entries:
    # (a) named_net MUST be a flat Verilog identifier — no brackets, no spaces.
    #     Bracket form (e.g. "REG_UmcCfgEco[1]") is illegal in `wire <name>;`
    #     declarations. Run 20260512070625 root cause: studier emitted
    #     `named_net: "REG_UmcCfgEco[1]"` → applier wrote `wire REG_UmcCfgEco[1];`
    #     → FM SVR-4/SVR-64/FM-599 ABORT → 5 hours misdiagnosis.
    #     The applier's eco_perl_spec.py auto-sanitizes, but this validator
    #     flags the studier-side root cause so engineer can fix at source.
    # (b) When N entries across N different modules share the same `named_net`
    #     value AND the same `original` UNCONNECTED name, that's a likely
    #     scope-leak symptom — the studier may have broadcast a substitution
    #     that should have been scoped to ONE module (the actual target).
    NAMED_NET_RE = re.compile(r'^[A-Za-z_]\w*$')
    from collections import defaultdict
    rewires_by_named = defaultdict(list)   # named_net -> [(stage, mod, inst, orig)]
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        for e in study.get(stage, []):
            mod = e.get('module_name', '')
            for ur in e.get('unconnected_rewires', []) or []:
                named = ur.get('named_net', '')
                orig  = ur.get('original_unconnected', '')
                inst  = ur.get('port_bus_instance', '') or e.get('instance_name', '')
                if not named:
                    continue
                # (a) Format check
                if not NAMED_NET_RE.match(named):
                    issues.append(
                        f"HIGH/26-NAMED-NET-FORMAT: stage={stage} mod={mod} "
                        f"named_net={named!r} is not a flat Verilog identifier. "
                        f"Use underscore-escape form (e.g. 'X_1_' instead of 'X[1]'). "
                        f"Applier auto-sanitizes but studier should emit correct "
                        f"form directly. See eco_netlist_studier.md §0b-UNCONNECTED "
                        f"format constraints.")
                rewires_by_named[(named, orig)].append((stage, mod, inst))

    # (b) Scope-leak suspect: same (named, orig) used in entries with DIFFERENT
    # modules. Allowed: same (named, orig) appears in 3 entries (one per stage)
    # for the SAME module — that's normal multi-stage. Flag when the modules
    # set has >1 distinct module per stage.
    for (named, orig), occurrences in rewires_by_named.items():
        # Group by stage
        per_stage_mods = defaultdict(set)
        for stage, mod, inst in occurrences:
            per_stage_mods[stage].add(mod)
        for stage, mods in per_stage_mods.items():
            if len(mods) > 1:
                issues.append(
                    f"WARN/26-SCOPE-LEAK-SUSPECT: stage={stage} the same rename "
                    f"(orig={orig!r} → named={named!r}) targets {len(mods)} different "
                    f"modules: {sorted(mods)[:5]}. Applier executes per-instance, "
                    f"so each entry results in its own substitution — this LOOKS "
                    f"like a scope-leak. Verify all targets are intentional; if "
                    f"only ONE module needs the rename, drop the others to avoid "
                    f"polluting unrelated module scopes.")

    # ── 27. CLOCK-STAGE-STABILITY for new DFFs ──────────────────────────────
    # For each new_logic_dff, check that port_connections_per_stage[*].CP
    # references wires from the SAME clock domain across all 3 stages.
    # Failure mode: studier picks Synth=ClkA, PP=ClkA, Route=<ClkB-tree
    # CTS-rebalanced antenna fix> — different clock domain in Route → FM
    # logical mismatch.
    #
    # Heuristic: extract the "root clock token" from each per-stage CP wire
    # name. Patterns like '<clk_token>_buf_*', '<clk_token>_cts_*',
    # 'ant_fix_net_*_<clk_token>_*', 'FxOptCts_*<clk_token>*', etc., should
    # all share the same <clk_token>. If the tokens disagree, fail.
    CLK_TOKEN_RE = re.compile(r'\b([A-Za-z_][A-Za-z0-9_]*?clk[A-Za-z0-9_]*|'
                              r'[A-Z][A-Z0-9]*CLK[A-Z0-9_]*)', re.IGNORECASE)
    def _extract_clock_tokens(cp_value):
        """Find all clock-like tokens in a CP wire/cell name. Returns set."""
        if not cp_value:
            return set()
        tokens = set()
        for m in CLK_TOKEN_RE.finditer(cp_value):
            tok = m.group(1).upper()
            # Strip common decorators
            for suffix in ('_CTS', '_BUF', '_INV', '_GATE'):
                if tok.endswith(suffix):
                    tok = tok[:-len(suffix)]
            tokens.add(tok)
        return tokens

    for stage in ('Synthesize', 'PrePlace', 'Route'):
        for e in study.get(stage, []):
            if e.get('change_type') not in ('new_logic_dff', 'new_logic'):
                continue
            inst = e.get('instance_name', '?')
            pcs = e.get('port_connections_per_stage', {})
            if not pcs:
                continue
            per_stage_tokens = {}
            for st in ('Synthesize', 'PrePlace', 'Route'):
                cp = (pcs.get(st) or {}).get('CP', '')
                per_stage_tokens[st] = _extract_clock_tokens(cp)
            # Find any pairwise disjoint set (no common token across stages)
            non_empty = {st: tks for st, tks in per_stage_tokens.items() if tks}
            if len(non_empty) >= 2:
                common = set.intersection(*non_empty.values())
                if not common:
                    issues.append(
                        f"HIGH/27-CLOCK-STAGE-MISMATCH: DFF {inst} per-stage CP "
                        f"references DIFFERENT clock domains: " +
                        ', '.join(f"{st}=tokens{sorted(tks)}" for st, tks in per_stage_tokens.items() if tks) +
                        f". A new DFF must clock on the SAME logical clock across "
                        f"all 3 PostEco stages (CTS-rebalanced names are OK as long "
                        f"as the clock-token root matches). Mismatch → FM logical "
                        f"mismatch on this DFF. Studier should re-pick CP per stage "
                        f"to ensure all 3 belong to the same clock tree (verify by "
                        f"tracing each CP wire's source register's CP recursively).")

    # ── Result ───────────────────────────────────────────────────────────────
    passed = len(issues) == 0
    result = {'tag': args.tag, 'passed': passed, 'issues': issues, 'issue_count': len(issues)}
    Path(args.output).write_text(json.dumps(result, indent=2))

    marker_txt = (
        f"ECO_SCRIPT_LAUNCHED: eco_validate_step3.py\n"
        f"  passed: {passed}\n"
        f"  issues: {len(issues)}\n"
        f"  output: {args.output}"
    )
    print(marker_txt)
    if issues:
        print("\nISSUES FOUND:")
        for i in issues:
            print(f"  - {i}")
    else:
        print("\nStep 3 output COMPLETE — all checks passed.")

    Path(args.output.replace('.json','_marker.txt')).write_text(marker_txt + '\n')
    return 0 if passed else 1

if __name__ == '__main__':
    sys.exit(main())
