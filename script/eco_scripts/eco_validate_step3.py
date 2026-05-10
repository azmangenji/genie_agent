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
    if os.path.isdir(os.path.join(args.ref_dir, 'data', 'PostEco')):
        import gzip as _gz
        # Cache: (stage, module_name) → set of CP/SE/SI per pin used by existing DFFs
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
