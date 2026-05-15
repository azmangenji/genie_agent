#!/usr/bin/env python3
"""
eco_validate_step1.py — Deterministic Step 1 validator for eco_rtl_diff.json.
Runs as the post-rtl_diff_analyzer self-check; fails the orchestrator on any
defect so wrong RTL-diff data never reaches Step 2/3/4.

Checks performed:
  - MUX-select polarity (D-MUX-6 cross-checks 1-5; the original purpose)
  - Phantom WIRE/BUF pseudo-cells in any gate chain
  - new_port hygiene (declaration_type set; no duplicates)
  - port_connection completeness (inst/port/net populated)
  - Cell truth-table match: every gate in d_input_gate_chain /
    new_condition_gate_chain has preeco_cell_type whose actual boolean function
    equals the claimed gate_function (per script/eco_scripts/cell_libraries/*.json)

Usage:
    python3 script/eco_scripts/eco_validate_step1.py \
        --rtl-diff data/<TAG>_eco_rtl_diff.json \
        --output   data/<TAG>_eco_validate_step1.json

Exit: 0 = all wire_swap entries pass, 1 = any failure.
"""
import argparse, json, os, re, sys

# Prefixes that mean the cell's output goes LOW when its inputs go HIGH.
# Keep generic — covers TSMC/AMD/GF library naming conventions.
INVERTING_PREFIXES = ('XNOR', 'XNR', 'NAND', 'NOR', 'INR', 'INV', 'IND', 'ND', 'NR')
BACKTRACK_PHRASES  = ('wait', 'actually', 're-analyz', 'correcting', 'inverts')

# Gate output when ALL combinational inputs are at logic 1.
# Used in Check 4 only when the new condition is a pure AND/OR/NAND/NOR of the
# gate's inputs — covers ~95% of MUX-select rewires.
GATE_OUT_WHEN_INPUTS_HIGH = {
    'AND2': 1, 'AND3': 1, 'AND4': 1, 'AN2': 1, 'AN3': 1, 'AN4': 1,
    'OR2':  1, 'OR3':  1, 'OR4':  1,
    'NAND2': 0, 'NAND3': 0, 'NAND4': 0, 'ND2': 0, 'ND3': 0, 'ND4': 0,
    'NOR2':  0, 'NOR3':  0, 'NOR4':  0, 'NR2': 0, 'NR3': 0, 'NR4': 0,
    'INV': 0, 'BUF': 1, 'XOR2': 0, 'XNOR2': 1,
}


def is_inverting(cell_type):
    """True if first uppercase token of cell_type starts with an inverting prefix."""
    if not cell_type:
        return None
    m = re.match(r'^([A-Z]+)', cell_type)
    if not m:
        return None
    prefix = m.group(1)
    # Longest match wins so 'NAND' isn't misread as starting with 'NA'.
    return any(prefix.startswith(p) for p in sorted(INVERTING_PREFIXES, key=len, reverse=True))


def evaluate_condition_at_inputs_high(expr):
    """
    Return condition value when every bare input signal is logic 1.
    Supports ~, &, |, parentheses. Returns None if expression too complex.
    """
    if not expr:
        return None
    # Strip whitespace; substitute every bare identifier with '1'
    e = re.sub(r'[A-Za-z_][A-Za-z_0-9\[\]]*', '1', expr)
    # Translate Verilog operators to Python
    e = e.replace('~', ' not ').replace('&&', ' and ').replace('||', ' or ')
    e = e.replace('&', ' and ').replace('|', ' or ')
    try:
        return int(bool(eval(e, {'__builtins__': {}}, {})))
    except Exception:
        return None


def check_entry(entry):
    """Run the 5 cross-checks on one wire_swap entry. Return list of issues."""
    issues = []
    cell  = entry.get('mux_select_old_driver_cell_type')
    inv   = entry.get('mux_select_old_driver_inverting')
    s_val = entry.get('mux_select_old_S_when_condition_true')
    branch = entry.get('mux_select_branch_true_on')
    gate  = entry.get('mux_select_gate_function')
    rsn   = (entry.get('mux_select_reasoning') or '').lower()

    if cell is None or inv is None or s_val is None or branch is None:
        issues.append('MISSING_FIELDS: D-MUX-3/4/5 derivation fields not recorded — re-run Step 1')
        return issues

    # 1. cell type prefix vs inverting flag
    exp_inv = is_inverting(cell)
    if exp_inv is None:
        issues.append(f'CHECK1: cannot parse cell_type prefix from {cell!r}')
    elif exp_inv != bool(inv):
        issues.append(f'CHECK1: cell_type {cell} prefix is_inverting={exp_inv} but flag={inv}')

    # 2. S follows inverting flag
    exp_s = 0 if inv else 1
    if s_val != exp_s:
        issues.append(f'CHECK2: inverting={inv} requires old_S={exp_s} but field={s_val}')

    # 3. branch follows S
    exp_branch = 'I0' if s_val == 0 else 'I1'
    if branch != exp_branch:
        issues.append(f'CHECK3: old_S={s_val} requires branch_true_on={exp_branch} but field={branch}')

    # 4. gate function output @ all-inputs-high equals required new S (best effort)
    if gate in GATE_OUT_WHEN_INPUTS_HIGH:
        # The "condition TRUE" case is normally the all-inputs-high case for
        # AND-style conditions. For ~A|~B style conditions the agent should
        # have inverted the polarity decision in D-MUX-4 (gate becomes AND).
        # If the gate output at all-inputs-high == required_S, the gate's TRUE
        # case is NOT the all-inputs-high case — that means the new condition
        # is something other than a pure AND of all inputs and we need the
        # actual condition expression to evaluate. We attempt that next.
        gate_at_high = GATE_OUT_WHEN_INPUTS_HIGH[gate]
        # Try to read the condition expression from a context_line / reasoning
        cond_expr = entry.get('context_line', '') or ''
        m = re.search(r'\(([^?)]+)\)\s*\?', cond_expr)
        new_cond_at_high = evaluate_condition_at_inputs_high(m.group(1)) if m else None
        if new_cond_at_high is not None:
            # When gate output AT condition=TRUE must equal s_val, and we have
            # the condition's value at inputs-high, we know what gate output to
            # require at inputs-high: must equal s_val if condition_at_high==1,
            # or != s_val if condition_at_high==0 (in which case any gate
            # behaviour at inputs-high is acceptable; skip).
            if new_cond_at_high == 1 and gate_at_high != s_val:
                issues.append(
                    f'CHECK4: gate {gate} outputs {gate_at_high} at inputs=high; '
                    f'new condition=TRUE at inputs=high requires gate output={s_val}'
                )

    # 5. reasoning stability
    bad = [w for w in BACKTRACK_PHRASES if w in rsn]
    if bad:
        issues.append(f'CHECK5: reasoning contains backtracking phrases {bad} — derivation unstable')

    return issues


def signals_in_module(text, module_name):
    """Return set of signal names visible in the given module: ports + wire decls
    + cell output nets. Uses comment-stripped Verilog text."""
    m = re.search(rf'^module\s+{re.escape(module_name)}(?:_0)?\b.*?^endmodule\b',
                  text, re.MULTILINE | re.DOTALL)
    if not m:
        return set()
    body = m.group(0)
    sigs = set()
    # Ports: `input [...] foo;` / `output [...] foo;` / `inout [...] foo;`
    for pm in re.finditer(r'^\s*(?:input|output|inout)\s+(?:\[[^\]]+\]\s+)?(\w+)\s*[;,]',
                          body, re.MULTILINE):
        sigs.add(pm.group(1))
    # Wire decls: `wire [...] foo;`
    for wm in re.finditer(r'^\s*wire\s+(?:\[[^\]]+\]\s+)?(\w+)\s*[;,]',
                          body, re.MULTILINE):
        sigs.add(wm.group(1))
    # Cell outputs: any `.Z(net)` / `.ZN(net)` / `.Q(net)` / `.QN(net)` / `.CO(net)`
    for cm in re.finditer(r'\.\s*(?:Z|ZN|ZN1|Q|QN|CO)\s*\(\s*(\w+)\s*\)', body):
        sigs.add(cm.group(1))
    return sigs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--rtl-diff', required=True)
    ap.add_argument('--ref-dir',  default=None,
                    help='REF_DIR with data/PreEco/<stage>.v.gz for signal-in-scope check')
    ap.add_argument('--output',   required=True)
    args = ap.parse_args()

    rtl_diff = json.load(open(args.rtl_diff))
    results, overall_pass = [], True

    # Phantom-cell scan: 'WIRE'/'BUF' as gate_function or cell_type is not a real
    # library cell — emit empty chain instead. Caught in any chain, any change_type.
    phantom = []
    for idx, c in enumerate(rtl_diff.get('changes', [])):
        for fld in ('d_input_gate_chain', 'new_condition_gate_chain'):
            for g in (c.get(fld) or []):
                if g.get('gate_function') in ('WIRE',) or g.get('cell_type') in ('WIRE',):
                    phantom.append(f'changes[{idx}].{fld} seq={g.get("seq")}: phantom WIRE pseudo-cell — emit empty chain')
    if phantom:
        overall_pass = False

    # new_port hygiene: declaration_type must be set, and (module, signal) must
    # not appear as new_port more than once (catches misclassified wire decls).
    decl_issues, seen = [], {}
    for idx, c in enumerate(rtl_diff.get('changes', [])):
        if c.get('change_type') != 'new_port':
            continue
        dt = c.get('declaration_type')
        if dt not in ('input', 'output', 'wire'):
            decl_issues.append(f'changes[{idx}] new_port {c.get("new_token")!r} in {c.get("module_name")!r}: declaration_type={dt!r} (must be input/output/wire)')
        key = (c.get('module_name'), c.get('new_token'))
        if key in seen:
            decl_issues.append(f'changes[{idx}] duplicate new_port for module={key[0]!r} signal={key[1]!r} (first at index {seen[key]})')
        else:
            seen[key] = idx
    if decl_issues:
        overall_pass = False

    # port_connection completeness: every entry must have inst/port/net populated
    # under SOME field name (canonical or alternative). Catches incomplete entries
    # that would silently SKIP in eco_passes_2_4.py.
    pc_issues = []
    for idx, c in enumerate(rtl_diff.get('changes', [])):
        if c.get('change_type') != 'port_connection':
            continue
        inst = c.get('instance_name') or c.get('submodule_instance')
        port = c.get('port_name')     or c.get('new_token')
        net  = c.get('net_name')      or c.get('flat_net_name')
        if not all([inst, port, net]):
            pc_issues.append(f'changes[{idx}] port_connection in {c.get("module_name")!r}: missing inst={inst!r}/port={port!r}/net={net!r}')
    if pc_issues:
        overall_pass = False

    # Signal-in-scope check: every input signal referenced by a chain entry must
    # exist in the target module — as a port, wire decl, or cell output. Missing
    # signals cause undriven inputs in the inserted gate → FM cone divergence.
    sis_issues = []
    if args.ref_dir:
        import gzip as _gz, os as _os
        # Load Synthesize PreEco module text once (per module — cache by name)
        gz = _os.path.join(args.ref_dir, 'data', 'PreEco', 'Synthesize.v.gz')
        if not _os.path.exists(gz):
            gz = _os.path.join(args.ref_dir, 'data', 'PostEco', 'Synthesize.v.gz')
        if _os.path.exists(gz):
            try:
                with _gz.open(gz, 'rt') as f:
                    raw = f.read()
                raw = re.sub(r'/\*.*?\*/', '', raw, flags=re.DOTALL)
                raw = re.sub(r'//[^\n]*', '', raw)
            except Exception:
                raw = ''
            mod_sig_cache = {}
            def _sigs(mod):
                if mod not in mod_sig_cache:
                    mod_sig_cache[mod] = signals_in_module(raw, mod) if raw else set()
                return mod_sig_cache[mod]
            for idx, c in enumerate(rtl_diff.get('changes', [])):
                target_mod = c.get('declaring_module') or c.get('module_name')
                if not target_mod:
                    continue
                sigs = _sigs(target_mod)
                if not sigs:
                    continue  # module not found — silent skip (probably a tile-prefix variant)
                for fld in ('d_input_gate_chain', 'new_condition_gate_chain'):
                    for g in (c.get(fld) or []):
                        for inp in (g.get('inputs') or []):
                            if not isinstance(inp, str):
                                continue
                            base = re.sub(r'\[[^\]]*\]', '', inp).strip()  # strip bit select
                            if not base or base.startswith(('1\'b', '0\'b')):
                                continue
                            if base.startswith('n_eco_'):
                                continue  # internal ECO net, may not yet exist
                            if base not in sigs:
                                # Suggest closest in-scope match (heuristic: same prefix)
                                cand = next((s for s in sigs if s.startswith(base) or base.startswith(s)), None)
                                hint = f' (closest in-scope: {cand!r})' if cand else ''
                                sis_issues.append(
                                    f'changes[{idx}].{fld} seq={g.get("seq")}: input {inp!r} '
                                    f'NOT in scope of module {target_mod!r}{hint}. '
                                    f'Pick the in-scope alias or promote the signal as a new port.')
    if sis_issues:
        overall_pass = False

    # Truth-table check: every gate in d_input_gate_chain / new_condition_gate_chain
    # must have preeco_cell_type whose actual boolean function matches the claimed
    # gate_function. Catches the case where Step 1 picked a cell whose name suggests
    # one logic family but the cell actually computes something different.
    tt_issues = []
    try:
        import os as _os, sys as _sys
        _sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
        import eco_cell_truth_tables as _ett
    except ImportError:
        _ett = None
    if _ett is not None:
        for idx, c in enumerate(rtl_diff.get('changes', [])):
            for fld in ('d_input_gate_chain', 'new_condition_gate_chain'):
                for g in (c.get(fld) or []):
                    cell = g.get('preeco_cell_type') or g.get('cell_type') or ''
                    fn   = g.get('gate_function') or ''
                    if not cell or not fn:
                        continue
                    m, why = _ett.cell_function_matches(cell, fn, ref_dir=args.ref_dir)
                    if m is False:
                        tt_issues.append(f'changes[{idx}].{fld} seq={g.get("seq")}: cell={cell!r} does NOT compute claimed {fn!r} — {why}')
    if tt_issues:
        overall_pass = False

    # Whole-chain equivalence (Gap E): for every d_input_gate_chain, compose
    # the gates' boolean functions and verify the composed expression matches
    # the RTL spec stored in `d_input_expected_function`. Catches the
    # "individual cells valid but chain composition wrong for the role" class
    # of bug — Step 1 truth-table check (cell vs gate_function) cannot.
    #
    # The reference field `d_input_expected_function` is MANDATORY for any
    # change with a non-empty d_input_gate_chain — without it Gap E cannot
    # verify the chain's boolean intent, leaving a silent gap that allowed
    # the original 9868 INR3+IAOI21 bug through. If missing → HIGH issue
    # (forces rtl_diff_analyzer to re-emit the change with the field).
    chain_eq_issues = []
    try:
        import eco_chain_equivalence as _ece
    except ImportError:
        _ece = None
    if _ece is not None:
        for idx, c in enumerate(rtl_diff.get('changes', [])):
            chain = c.get('d_input_gate_chain') or []
            if not chain:
                continue  # no chain to check
            ref_expr = c.get('d_input_expected_function')
            if not ref_expr:
                # Mandatory reference missing — block flow
                chain_eq_issues.append(
                    f"changes[{idx}] target={c.get('target_register','?')}: "
                    f"d_input_gate_chain present ({len(chain)} gates) but "
                    f"`d_input_expected_function` field MISSING. "
                    f"rtl_diff_analyzer must emit this field — see rtl_diff_analyzer.md "
                    f"'MANDATORY whole-chain equivalence reference field (Gap E)' rule.")
                continue
            dff_d = chain[-1].get('output_net') if chain else None
            if not dff_d:
                continue
            impl_expr, inputs, comp_issues = _ece.compose_chain(chain, dff_d)
            if impl_expr is None:
                chain_eq_issues.append(f"changes[{idx}] target={c.get('target_register','?')}: cannot compose chain — {'; '.join(comp_issues)}")
                continue
            ref_vars = sorted(set(re.findall(r'\b[A-Za-z_]\w*\b', ref_expr)) - {'and','or','not'})
            all_vars = sorted(set(inputs) | set(ref_vars))
            eq, details = _ece.equivalent(impl_expr, ref_expr, all_vars)
            if eq is False:
                preview = '; '.join(f"{combo}→impl={iv},ref={rv}" for combo, iv, rv in details[:3])
                chain_eq_issues.append(
                    f"changes[{idx}] target={c.get('target_register','?')}: chain NOT EQUIVALENT to RTL spec — "
                    f"{len(details)} mismatching combo(s). First: {preview}")
            elif eq is None:
                # Inconclusive (e.g., > 12 inputs); record as warning
                chain_eq_issues.append(
                    f"changes[{idx}] target={c.get('target_register','?')}: chain equivalence INCONCLUSIVE — {details}")
    if chain_eq_issues:
        overall_pass = False

    # Mandatory-fields check for new_logic / new_logic_dff entries — every such
    # entry MUST have dff_clock (Step 3 needs it to pick neighbor DFF for per-stage
    # CP + Mode S clock-domain match), AND must have a non-empty d_input_gate_chain
    # + d_input_expected_function whenever has_sync_reset is true OR
    # requires_scan_stitching is true (sync-reset RTL collapses into a combinational
    # gate at the D-input, and any new ECO DFF we stitch needs a defined D logic).
    new_logic_field_issues = []
    for idx, c in enumerate(rtl_diff.get('changes', [])):
        if c.get('change_type') not in ('new_logic', 'new_logic_dff'):
            continue
        tgt = c.get('target_register') or c.get('new_token') or '?'
        if not c.get('dff_clock'):
            new_logic_field_issues.append(
                f"changes[{idx}] target={tgt}: `dff_clock` MISSING — "
                f"required for Step 3 per-stage CP + Mode S clock-domain match")
        # Mode S decision MUST be explicit on every new_logic_dff. If the agent
        # opts out (false), require a justification so the skip is auditable.
        rss = c.get('requires_scan_stitching')
        if rss is None:
            new_logic_field_issues.append(
                f"changes[{idx}] target={tgt}: `requires_scan_stitching` MISSING — "
                f"explicit true/false required (default true for any non-wrapper-clock DFF)")
        elif rss is False and not c.get('scan_stitching_skipped_reason'):
            new_logic_field_issues.append(
                f"changes[{idx}] target={tgt}: requires_scan_stitching=false but "
                f"`scan_stitching_skipped_reason` MISSING — opt-out must cite why "
                f"(e.g. 'wrapper-only clock {c.get('dff_clock')!r} never carries scan_enable')")
        elif rss is True:
            anchor = c.get('mode_s_anchor') or {}
            missing_anchor = [k for k in ('sibling_module', 'anchor_dff', 'fm_scope')
                              if not anchor.get(k)]
            if missing_anchor:
                new_logic_field_issues.append(
                    f"changes[{idx}] target={tgt} [FAIL/13-FM-SCOPE-MISSING]: "
                    f"requires_scan_stitching=true but `mode_s_anchor` missing fields "
                    f"{missing_anchor}. fm_scope (instance hierarchy from tile-internal "
                    f"root to sibling, e.g. 'ARB/DCQARB') MUST come from "
                    f"eco_pick_sibling.py recommended_pick.fm_scope. Without it Step 2 "
                    f"Cat 8 queries use module-type names and FM returns Unknown name "
                    f"(FM-036) on every anchor — Step 3 then has no bridge data.")
            elif '/' in (anchor.get('fm_scope') or ''):
                # Sanity: fm_scope must look like instance/instance, not contain
                # any module-type token (e.g. ddrss_<tile>_t_<peer>). Module-type
                # tokens always start with the tile prefix.
                fms = anchor['fm_scope']
                bad = [tok for tok in fms.split('/') if tok.startswith('ddrss_')]
                if bad:
                    new_logic_field_issues.append(
                        f"changes[{idx}] target={tgt} [FAIL/13-FM-SCOPE-MODULE-TYPE]: "
                        f"mode_s_anchor.fm_scope={fms!r} contains module-type token(s) "
                        f"{bad} — must be INSTANCE names only (e.g. 'ARB/DCQARB'). "
                        f"Re-run eco_pick_sibling.py with --tile-module set, then copy "
                        f"recommended_pick.fm_scope verbatim.")
            else:
                # Check 12 — SIBLING-IS-SELF: sibling_module MUST be a peer module
                # different from the host. Picking the host module as its own sibling
                # is a degenerate self-loop that defeats the bridge_port strategy.
                sib  = (anchor.get('sibling_module') or '').strip()
                host = (c.get('module_name') or '').strip()
                # Also derive host from scope's last segment as a fallback
                if not host:
                    scope = (c.get('scope') or c.get('instance_scope') or '').strip()
                    if scope:
                        host = scope.split('/')[-1]
                # Compare with stripped trailing _0/_1 (DFT suffix variants)
                def _norm(name):
                    return re.sub(r'_\d+$', '', name)
                if sib and host and (_norm(sib) == _norm(host) or
                                     _norm(sib).endswith('_'+_norm(host)) or
                                     _norm(host).endswith('_'+_norm(sib))):
                    new_logic_field_issues.append(
                        f"changes[{idx}] target={tgt} [FAIL/12-SIBLING-IS-SELF]: "
                        f"mode_s_anchor.sibling_module={sib!r} matches the host module "
                        f"{host!r}. Bridge_port requires a PEER module under the same "
                        f"parent — using host as its own sibling is a degenerate self-loop "
                        f"that produces no real cross-module bridging. Pick a different "
                        f"peer module under the host's parent that contains scan-chain DFFs.")
        # Heuristic: clocks that are NOT wrapper-only (wrp_clk_*) propagate scan
        # enable and so require Mode S. The agent may opt out by claiming the
        # picker returned null — but that claim MUST be backed by an actual
        # sibling_pick JSON on disk with `recommended_pick: null` (proof of
        # execution). Without the proof file, the agent fabricated the reason
        # to satisfy the validator escape hatch.
        clk = (c.get('dff_clock') or '')
        is_wrapper_clk = clk.startswith('wrp_clk_') or '/wrp_clk_' in clk
        skip_reason = c.get('scan_stitching_skipped_reason') or ''
        eco_pick_sibling_null_claimed = 'eco_pick_sibling returned null' in skip_reason
        # Verify the claim — sibling_pick file must exist AND recommended_pick must be null.
        eco_pick_sibling_null_proven = False
        if eco_pick_sibling_null_claimed and tgt:
            import os as _os, glob as _glob, json as _json
            data_dir = _os.path.dirname(_os.path.abspath(args.rtl_diff))
            tag_match = re.match(r'(\d{14})', _os.path.basename(args.rtl_diff))
            if tag_match:
                tag = tag_match.group(1)
                # Try multiple naming variants the agent may use
                candidates = (_glob.glob(_os.path.join(data_dir, f'{tag}_eco_sibling_pick_{tgt}*.json'))
                              + _glob.glob(_os.path.join(data_dir, f'{tag}_eco_sibling_pick_{tgt[:20]}*.json')))
                for sp_path in candidates:
                    try:
                        sp = _json.loads(open(sp_path).read())
                        if sp.get('recommended_pick') is None:
                            eco_pick_sibling_null_proven = True
                            break
                    except Exception:
                        pass
        if eco_pick_sibling_null_claimed and not eco_pick_sibling_null_proven:
            new_logic_field_issues.append(
                f"changes[{idx}] target={tgt}: scan_stitching_skipped_reason claims "
                f"'eco_pick_sibling returned null' but NO sibling_pick JSON file exists "
                f"on disk with recommended_pick: null. Agent must actually invoke "
                f"`python3 script/eco_scripts/eco_pick_sibling.py --host-module {c.get('module_name','?')!r} "
                f"--tile-module <tile> --output data/<TAG>_eco_sibling_pick_{tgt}.json` "
                f"and only after that file is on disk with recommended_pick=null may "
                f"this opt-out reason be claimed. Fabricating the reason to bypass "
                f"Mode-S enforcement is FORBIDDEN.")
        if rss is False and not is_wrapper_clk and not eco_pick_sibling_null_proven:
            new_logic_field_issues.append(
                f"changes[{idx}] target={tgt}: requires_scan_stitching=false but "
                f"dff_clock={clk!r} is NOT a wrapper-only clock (wrp_clk_*) — "
                f"non-wrapper clocks propagate scan_enable; Mode S is required. "
                f"Valid opt-outs: (a) wrp_clk_* clock, (b) sibling_pick JSON on disk "
                f"with recommended_pick=null. If this is a documented exception, "
                f"override the heuristic by naming the clock with the wrp_clk_ prefix.")
        needs_chain = c.get('has_sync_reset') or c.get('requires_scan_stitching')
        chain = c.get('d_input_gate_chain') or []
        d_in_net = c.get('d_input_net') or ''
        # UNCONNECTED placeholder ⇒ PreEco DFF has no D-driver; chain MUST replace it
        is_unconnected_d = d_in_net.startswith(('UNCONNECTED_', 'SYNOPSYS_UNCONNECTED_'))
        if (needs_chain or is_unconnected_d) and not chain:
            new_logic_field_issues.append(
                f"changes[{idx}] target={tgt}: `d_input_gate_chain` empty but "
                f"has_sync_reset={c.get('has_sync_reset')} / "
                f"requires_scan_stitching={c.get('requires_scan_stitching')} / "
                f"d_input_net={d_in_net!r} — emit at least the sync-reset "
                f"combinational gate (D = ~reset & next_value)")
        if (needs_chain or is_unconnected_d) and not c.get('d_input_expected_function'):
            new_logic_field_issues.append(
                f"changes[{idx}] target={tgt}: `d_input_expected_function` MISSING "
                f"(needed by Gap E equivalence check)")
        # When has_sync_reset is true, agent MUST decide whether reset is baked
        # into the D-input combinational gate (DFF cell has no RN pin) or fed
        # through a separate reset port. Missing field blocks Step 3 from
        # picking the right DFF stitching pattern.
        if c.get('has_sync_reset') and c.get('reset_baked_in_d_input') is None:
            new_logic_field_issues.append(
                f"changes[{idx}] target={tgt}: `reset_baked_in_d_input` MISSING "
                f"(has_sync_reset=true requires explicit true/false — true if DFF "
                f"cell has no RN pin and reset is AND-ed into D, false if DFF has RN)")
    if new_logic_field_issues:
        overall_pass = False

    # Mode I source-port info — when a new_logic_dff has d_input_net starting
    # with UNCONNECTED_*, Step 3 needs to know which submodule output port
    # the UNCONNECTED was originally tied to so it can emit the paired Mode I
    # port_connection. Require submodule_instance + port_name + bus_bit_index.
    mode_i_field_issues = []
    for idx, c in enumerate(rtl_diff.get('changes', [])):
        if c.get('change_type') not in ('new_logic', 'new_logic_dff'):
            continue
        d_in = c.get('d_input_net') or ''
        if not d_in.startswith(('UNCONNECTED_', 'SYNOPSYS_UNCONNECTED_')):
            continue
        tgt = c.get('target_register') or c.get('new_token') or '?'
        for f in ('submodule_instance', 'port_name', 'bus_bit_index'):
            if c.get(f) is None:
                mode_i_field_issues.append(
                    f"changes[{idx}] target={tgt}: d_input_net={d_in!r} (UNCONNECTED) but "
                    f"`{f}` MISSING — Step 3 needs it to emit the Mode I paired "
                    f"child-scope port_connection")
    if mode_i_field_issues:
        overall_pass = False

    # Hierarchy/scope path — every new_logic_dff must specify the full netlist
    # scope (e.g. 'umccmd/ARB/CTRLSW') in `scope` or `instance_scope` so Step 3
    # can land the new DFF in the correct instance when the host module has
    # multiple instantiations.
    scope_field_issues = []
    for idx, c in enumerate(rtl_diff.get('changes', [])):
        if c.get('change_type') not in ('new_logic', 'new_logic_dff'):
            continue
        if not (c.get('scope') or c.get('instance_scope')):
            tgt = c.get('target_register') or c.get('new_token') or '?'
            scope_field_issues.append(
                f"changes[{idx}] target={tgt}: `scope` (or `instance_scope`) MISSING — "
                f"required by Step 3 to disambiguate when host module {c.get('module_name','?')!r} "
                f"is instantiated multiple times")
    if scope_field_issues:
        overall_pass = False

    # wire_swap MUX context — even when polarity is NOT pending, the agent must
    # emit mux_select_gate_function + mux_select_branch_true_on +
    # mux_select_i0_net + mux_select_i1_net so Step 3 can apply the rewire
    # correctly. Currently only polarity_pending entries get the existing
    # check_entry pass; non-pending entries can ship without I0/I1 nets.
    wire_swap_field_issues = []
    for idx, c in enumerate(rtl_diff.get('changes', [])):
        if c.get('change_type') != 'wire_swap':
            continue
        if c.get('mux_select_polarity_pending'):
            continue  # check_entry handles these
        tgt = c.get('target_register') or c.get('new_token') or '?'
        for f in ('mux_select_gate_function', 'mux_select_branch_true_on',
                  'mux_select_i0_net', 'mux_select_i1_net'):
            if not c.get(f):
                wire_swap_field_issues.append(
                    f"changes[{idx}] target={tgt}: wire_swap missing `{f}` — "
                    f"Step 3 needs full MUX context to apply rewire")
    if wire_swap_field_issues:
        overall_pass = False

    # UNCONNECTED-as-variable check — chain inputs and d_input_expected_function
    # must NEVER reference a literal `UNCONNECTED_<N>` placeholder as a signal.
    # The placeholder marks an undriven net in PreEco; the agent must trace it
    # to the real RTL source (e.g. REG_UmcCfgEco[1]) and rewrite the chain
    # against that. Letting UNCONNECTED leak through makes Gap E equivalence
    # vacuously true while the actual ECO is wired to a phantom signal.
    unconnected_var_issues = []
    _UNC_RE = re.compile(r'\bUNCONNECTED_\d+\b')
    for idx, c in enumerate(rtl_diff.get('changes', [])):
        if c.get('change_type') not in ('new_logic', 'new_logic_dff'):
            continue
        tgt = c.get('target_register') or c.get('new_token') or '?'
        ref = c.get('d_input_expected_function') or ''
        m = _UNC_RE.findall(ref)
        if m:
            unconnected_var_issues.append(
                f"changes[{idx}] target={tgt}: d_input_expected_function references "
                f"UNCONNECTED placeholder(s) {sorted(set(m))} — trace to the real "
                f"RTL source signal and rewrite (UNCONNECTED is not a real signal)")
        for g in (c.get('d_input_gate_chain') or []):
            for inp in (g.get('inputs') or []):
                if _UNC_RE.search(str(inp)):
                    unconnected_var_issues.append(
                        f"changes[{idx}] target={tgt}: chain seq={g.get('seq','?')} "
                        f"input {inp!r} is an UNCONNECTED placeholder — trace it to "
                        f"the real source signal")
    if unconnected_var_issues:
        overall_pass = False

    for idx, c in enumerate(rtl_diff.get('changes', [])):
        if c.get('change_type') != 'wire_swap' or c.get('mux_select_polarity_pending'):
            continue
        issues = check_entry(c)
        results.append({
            'change_index': idx,
            'target_register': c.get('target_register'),
            'gate_function':   c.get('mux_select_gate_function'),
            'branch_true_on':  c.get('mux_select_branch_true_on'),
            'passed': not issues,
            'issues': issues,
        })
        if issues:
            overall_pass = False

    # Check 9: Chain Compactness (GAP-8) — flag d_input_gate_chain that's
    # significantly larger than achievable via boolean simplification (De Morgan
    # transform, bus-equality folding, existing-inverted-signal reuse).
    # Engineer reference for 9868: 4-cell chain (INV+XOR2+OR4+NR2) vs our
    # 7-cell chain (NOR3+INV+AN4+OR2+INV+INV+AN4) for same boolean function.
    # Larger chain = larger cone for FM = higher chance of cone divergence
    # across PP/Route stages. WARN issues do not block; FAIL only on grossly
    # oversized chains.
    chain_compact_issues = []
    for idx, c in enumerate(rtl_diff.get('changes', [])):
        chain = c.get('d_input_gate_chain') or []
        if len(chain) < 4:
            continue
        tgt = c.get('target_register') or '?'

        # 9a — De Morgan opportunity: ≥2 INV cells whose outputs feed into a
        # final AND gate. Suggest collapsing to OR-of-positive + NOR transformation.
        inv_cells = [g for g in chain if (g.get('gate_function') or '').upper() == 'INV']
        final_gate = chain[-1] if chain else {}
        final_fn = (final_gate.get('gate_function') or '').upper()
        if len(inv_cells) >= 2 and final_fn.startswith('AN'):
            inv_outputs = {g.get('output_net') for g in inv_cells}
            and_inputs = set(final_gate.get('inputs', []))
            consumed = inv_outputs & and_inputs
            if len(consumed) >= 2:
                saved = len(consumed) - 1  # OR-N + NR2 replaces N INVs feeding ANDN
                chain_compact_issues.append(
                    f"changes[{idx}] target={tgt} [WARN/9a-DEMORGAN]: "
                    f"{len(consumed)} INV cells feed final {final_fn}. "
                    f"De Morgan transform → 1 OR{len(consumed)+1} + 1 NR2 "
                    f"saves ~{saved} cells. Engineer pattern preferred for FM cone simplicity.")

        # 9b — Bus equality fold: NOR3 + INV + AND4 + OR2 sequence likely came
        # from `(B==K1) | (B==K2)` where K1=000, K2=011. If K1, K2 differ in
        # ≤2 bits, can fold to XOR2 + OR2 + NR2 (smaller cone).
        nor_cells = [g for g in chain if (g.get('gate_function') or '').upper().startswith(('NOR', 'NR'))]
        and_after_inv = False
        for i, g in enumerate(chain[:-1]):
            if (g.get('gate_function') or '').upper() == 'INV':
                next_g = chain[i+1]
                if (next_g.get('gate_function') or '').upper().startswith('AN'):
                    and_after_inv = True
                    break
        or_in_chain = any((g.get('gate_function') or '').upper().startswith(('OR', 'OR2', 'OR3', 'OR4'))
                          for g in chain)
        if nor_cells and and_after_inv and or_in_chain:
            chain_compact_issues.append(
                f"changes[{idx}] target={tgt} [WARN/9b-BUS-FOLD]: "
                f"chain has NOR+INV+AND+OR sequence likely from `(bus==K1) | (bus==K2)`. "
                f"If K1,K2 differ by 1-2 bits → XOR2 fold saves cells.")

        # 9c — Existing inverted signal reuse: each INV cell in the chain whose
        # input is an RTL-level signal (not n_eco_*) is a candidate. The studier
        # should look for an EXISTING wire in PreEco that already produces the
        # inverted form — and use that wire per-stage instead of adding a new
        # INV cell. Each new INV widens the FM cone walk.
        # Per-INV: WARN. Aggregate: FAIL when ≥2 NEW INVs without reuse_existing_wire.
        unreused_invs = []
        for inv in inv_cells:
            inputs = inv.get('inputs') or []
            if not inputs:
                continue
            target_signal = inputs[0]
            # Skip if input is already an internal eco net or constant
            if target_signal.startswith(('n_eco_', "1'b", "1'b1", "1'b0")):
                continue
            # Skip if studier already marked this INV as reusing existing wire
            if inv.get('reuse_existing_wire') is True:
                continue
            unreused_invs.append((inv.get('seq', '?'), target_signal))
            chain_compact_issues.append(
                f"changes[{idx}] target={tgt} [WARN/9c-REUSE-INV] "
                f"seq={inv.get('seq','?')}: INV({target_signal}) is a NEW cell. "
                f"Studier should grep PreEco for an existing wire = ~{target_signal} "
                f"(per-stage rename like FxPlace_ZINV_*) and reuse it instead. "
                f"Reduces FM cone divergence risk across PP/Route.")
        if len(unreused_invs) >= 2:
            chain_compact_issues.append(
                f"changes[{idx}] target={tgt} [FAIL/9c-MULTI-INV-NO-REUSE]: "
                f"{len(unreused_invs)} new INV cells without `reuse_existing_wire`: "
                f"{[f'{s}=INV({sig})' for s, sig in unreused_invs]}. "
                f"≥2 unreused INVs → high cone-divergence risk across PP/Route. "
                f"Studier MUST search PreEco for existing inverted wires and emit "
                f"`reuse_existing_wire: true` + `inputs_per_stage` on each.")
            overall_pass = False

        # Check 9c-v2: per-stage reuse verification — if reuse_existing_wire=true is
        # claimed, BOTH PrePlace AND Route must have use_existing_wire=true in
        # inputs_per_stage. Synth-only reuse doesn't count (Synth has no CTS-renamed
        # wires; the cell still needs to be inserted, and PP/Route are where cone
        # divergence happens). Catches the bypass pattern where the agent sets
        # reuse=true on a flag basis without backing per-stage data.
        for inv in inv_cells:
            if inv.get('reuse_existing_wire') is not True:
                continue
            ips = inv.get('inputs_per_stage') or {}
            pp_ok = (ips.get('PrePlace') or {}).get('use_existing_wire') is True
            rt_ok = (ips.get('Route') or {}).get('use_existing_wire') is True
            if not (pp_ok and rt_ok):
                chain_compact_issues.append(
                    f"changes[{idx}] target={tgt} [FAIL/9c-FAKE-REUSE] "
                    f"seq={inv.get('seq','?')}: reuse_existing_wire=true claimed but "
                    f"inputs_per_stage shows PP.use_existing_wire={pp_ok}, "
                    f"Route.use_existing_wire={rt_ok}. Reuse claim must be backed "
                    f"by existing wires in BOTH PP AND Route (the stages where "
                    f"FM cone divergence happens). Synth-only reuse is NOT enough.")
                overall_pass = False

        # Check 11 — DEMORGAN-MISSED: structural detection of the forbidden pattern
        # "≥2 INV cells whose outputs feed a common ANDN gate". Independent of any
        # reuse_existing_wire flag. Catches "literal text-to-cell" decomposition
        # that should have been rewritten via De Morgan to NOR-N + outer gate.
        # Triggers regardless of whether reuse claims are populated, because the
        # topology itself is FM-risky.
        and_consumers = {}  # output_net of INV → list of (downstream_gate, seq) that consume it
        for inv in inv_cells:
            ip_net = inv.get('output_net')
            if not ip_net:
                continue
            for g in chain:
                if g is inv:
                    continue
                gf = (g.get('gate_function') or '').upper()
                if not gf.startswith(('AN', 'AND')):
                    continue
                if ip_net in (g.get('inputs') or []):
                    and_consumers.setdefault(g.get('seq', '?'), []).append(inv.get('seq', '?'))
        for and_seq, inv_seqs in and_consumers.items():
            if len(inv_seqs) >= 2:
                chain_compact_issues.append(
                    f"changes[{idx}] target={tgt} [FAIL/11-DEMORGAN-MISSED]: "
                    f"AND gate seq={and_seq} consumes outputs of {len(inv_seqs)} INV cells "
                    f"({inv_seqs}). FORBIDDEN pattern — De Morgan transform required: "
                    f"collect the negated terms into a single NOR-N gate instead of "
                    f"emitting per-term INV cells feeding a common AND. NOR absorbs "
                    f"negation in its truth table; per-term INVs widen FM cone walks "
                    f"through CTS-rebalanced infrastructure → cone divergence on "
                    f"PP/Route stages.")
                overall_pass = False

        # 9d — Excessive cell count: if cells > 1.2× distinct RTL-input count
        # (heuristic for "AND-of-positive-terms" verbosity), flag as FAIL.
        # Engineer's reference chain for 9868: 4 cells for 5 inputs (0.8× ratio).
        # Threshold of 1.2× catches our verbose 7-cell chain (1.4× ratio) while
        # tolerating small overhead (e.g. 5 cells for 4 inputs).
        distinct_inputs = set()
        for g in chain:
            for inp in (g.get('inputs') or []):
                if inp and not inp.startswith('n_eco_') and not inp.startswith("1'b"):
                    distinct_inputs.add(inp)
        if distinct_inputs:
            # Rule: chain cell count must not EXCEED distinct input count.
            # Engineer 9868: 4 cells for 6 inputs (well under). Our verbose
            # chain: 7 cells for 6 inputs (exceeds). Each gate combines ≥2
            # signals into 1, so a well-decomposed chain has cells ≤ inputs - 1.
            # Using just `inputs` as the threshold gives a small safety margin.
            expected_max = max(4, len(distinct_inputs))
            if len(chain) > expected_max:
                chain_compact_issues.append(
                    f"changes[{idx}] target={tgt} [FAIL/9d-OVERSIZED]: "
                    f"chain has {len(chain)} cells for {len(distinct_inputs)} distinct RTL inputs "
                    f"({sorted(distinct_inputs)[:5]}...). "
                    f"Expected ≤{expected_max} cells. Mandatory simplification pass needed "
                    f"(De Morgan + bus-fold + compound-cell preference). "
                    f"See rtl_diff_analyzer.md §E2.5.")
                overall_pass = False

    # Check 9e — Compound gate preference: detect consecutive gate pairs (gate_i →
    # gate_i+1) where gate_i's output feeds ONLY gate_i+1 and the combined function
    # matches a known compound gate family. Using simple primitive chains (OR2→AND2,
    # AND2→OR2, etc.) when a compound exists creates intermediate wires that FM must
    # trace back to RTL without SVF → compare point failures on downstream DFFs.
    _COMPOUND_PATTERNS = {
        # OR + AND family → OA/OAI
        ('OR2',  'AND2')  : 'OA21/OA12',
        ('OR2',  'AN2')   : 'OA21/OA12',
        ('OR3',  'AND2')  : 'OA31',
        ('OR2',  'AND3')  : 'OA211',
        # AND + OR family → AO/AOI
        ('AND2', 'OR2')   : 'AO21',
        ('AND2', 'OR3')   : 'AO211',
        ('AND3', 'OR2')   : 'AO31',
        # OR + NAND/NOR → OAI/AOI
        ('OR2',  'NAND2') : 'OAI21',
        ('OR2',  'ND2')   : 'OAI21',
        ('OR3',  'NAND2') : 'OAI31',
        ('AND2', 'NOR2')  : 'AOI21',
        ('AND2', 'NR2')   : 'AOI21',
        ('AND3', 'NOR2')  : 'AOI31',
        # INV + AND/NAND → NAND (De Morgan: ~(A&B) = NAND2)
        ('INV',  'AND2')  : 'NAND2/INR2 (INV input absorbed into NAND)',
        ('INV',  'AN2')   : 'NAND2/INR2 (INV input absorbed into NAND)',
        ('INV',  'AND3')  : 'NAND3/INR3 (INV input absorbed into NAND)',
        # INV + OR/NOR → NOR (De Morgan: ~(A|B) = NOR2)
        ('INV',  'OR2')   : 'NOR2/INR2 (INV input absorbed into NOR)',
        ('INV',  'NOR2')  : 'AND2 (double inversion: INV+NOR = AND)',
        ('INV',  'NR2')   : 'AND2 (double inversion)',
        # XOR/XNOR patterns
        ('INV',  'XNOR2') : 'XOR2 (INV+XNOR = XOR)',
        ('INV',  'XOR2')  : 'XNOR2 (INV+XOR = XNOR)',
    }
    for idx, c in enumerate(rtl_diff.get('changes', [])):
        for chain_field in ('new_condition_gate_chain', 'd_input_gate_chain'):
            chain = c.get(chain_field) or []
            if len(chain) < 2:
                continue
            # Map each n_eco_* net to list of gate indices that consume it
            output_to_consumers = {}
            for gi, g in enumerate(chain):
                for inp in (g.get('inputs') or []):
                    base = str(inp).split('[')[0]
                    if base.startswith('n_eco_'):
                        output_to_consumers.setdefault(base, []).append(gi)
            for gi in range(len(chain) - 1):
                g1 = chain[gi]
                g1_out = str(g1.get('output_net') or '').split('[')[0]
                if not g1_out.startswith('n_eco_'):
                    continue
                consumers = output_to_consumers.get(g1_out, [])
                if not consumers:
                    continue
                g1f = g1.get('gate_function', '').upper()
                tgt = c.get('target_register') or c.get('old_token') or '?'

                if len(consumers) == 1:
                    # Single consumer — can fold g1+g2 into one compound gate
                    g2 = chain[consumers[0]]
                    g2f = g2.get('gate_function', '').upper()
                    compound = _COMPOUND_PATTERNS.get((g1f, g2f))
                    if compound:
                        chain_compact_issues.append(
                            f"changes[{idx}] target={tgt} [FAIL/9e-COMPOUND-PREFER]: "
                            f"{g1f}(seq={g1.get('seq')})→{g2f}(seq={g2.get('seq')}) "
                            f"can be a single compound cell ({compound}). "
                            f"Compound gates avoid intermediate wires FM cannot trace to RTL. "
                            f"Apply E4d (rtl_diff_analyzer.md §E2.5/E4d).")
                        overall_pass = False
                else:
                    # Multiple consumers — g1 output fans to N gates of same type.
                    # Each consumer can become a separate compound gate using g1's raw
                    # inputs directly, eliminating the shared intermediate wire entirely.
                    consumer_funcs = set(chain[ci].get('gate_function','').upper() for ci in consumers)
                    if len(consumer_funcs) == 1:
                        g2f = next(iter(consumer_funcs))
                        compound = _COMPOUND_PATTERNS.get((g1f, g2f))
                        if compound:
                            chain_compact_issues.append(
                                f"changes[{idx}] target={tgt} [FAIL/9e-COMPOUND-PREFER]: "
                                f"{g1f}(seq={g1.get('seq')}) fans to {len(consumers)} {g2f} gates "
                                f"— each consumer can be an independent compound cell ({compound}) "
                                f"using {g1f}'s raw inputs directly, eliminating the shared "
                                f"intermediate wire '{g1_out}' that FM cannot trace to RTL. "
                                f"Apply E4d (rtl_diff_analyzer.md §E2.5/E4d).")
                            overall_pass = False

    # Check 10: Reset signal must be present in chain when reset_baked_in_d_input=True.
    # When the DFF has no RN/R reset pin and reset is sync, the reset must be baked
    # into the D-input combinational chain. If the reset signal is missing from
    # both d_input_expected_function AND every chain entry's inputs, the chain is
    # functionally INCOMPLETE — DFF will not zero out during reset → FM Synth-vs-RTL
    # mismatch on the new DFF.
    reset_inclusion_issues = []
    for idx, c in enumerate(rtl_diff.get('changes', [])):
        if c.get('change_type') not in ('new_logic', 'new_logic_dff'):
            continue
        if not c.get('reset_baked_in_d_input'):
            continue
        rst = c.get('reset_signal') or ''
        if not rst:
            continue
        tgt = c.get('target_register') or '?'
        chain = c.get('d_input_gate_chain') or []
        expr = c.get('d_input_expected_function') or ''
        # Reset name may appear as IReset, IReset_, or with bit-select; bare-word search.
        rst_word_re = re.compile(rf'\b{re.escape(rst)}\b')
        in_expr  = bool(rst_word_re.search(expr))
        in_chain = False
        for g in chain:
            for inp in (g.get('inputs') or []):
                if isinstance(inp, str) and rst_word_re.search(inp):
                    in_chain = True; break
            if in_chain: break
            # Also accept reset reuse via reuse_existing_wire pointing to the reset register's Q
            ips = g.get('inputs_per_stage') or {}
            for stg_wire in ips.values():
                if isinstance(stg_wire, str) and rst_word_re.search(stg_wire):
                    in_chain = True; break
            if in_chain: break
        if not in_expr and not in_chain:
            reset_inclusion_issues.append(
                f"changes[{idx}] target={tgt} [FAIL/10-RESET-MISSING]: "
                f"reset_baked_in_d_input=True with reset_signal={rst!r} but the reset name "
                f"appears in NEITHER d_input_expected_function NOR any chain entry's inputs. "
                f"DFF has no reset pin → reset MUST be baked into D as `~{rst} & <data_logic>`. "
                f"FM Synth-vs-RTL will fail (D=function-of-inputs in netlist vs D=0 during reset in RTL).")
            overall_pass = False
        elif not in_expr:
            reset_inclusion_issues.append(
                f"changes[{idx}] target={tgt} [FAIL/10-RESET-MISSING-EXPR]: "
                f"reset_signal={rst!r} appears in chain but NOT in d_input_expected_function. "
                f"Chain-equivalence check (Gap E) will pass against an incomplete reference → "
                f"silently masks reset-handling bugs. Update d_input_expected_function to include `~{rst}`.")
            overall_pass = False
        elif not in_chain:
            reset_inclusion_issues.append(
                f"changes[{idx}] target={tgt} [FAIL/10-RESET-MISSING-CHAIN]: "
                f"d_input_expected_function references {rst!r} but no chain entry consumes it. "
                f"Chain is functionally incomplete vs declared expected_function.")
            overall_pass = False

    # ── Check 27 — MUX_SELECT field consistency ─────────────────────────────
    # When mux_select_i{0,1}_net SHOULD come from new_select_inputs (because
    # the new MUX inputs are new_port signals, not yet in netlist), assert the
    # values agree. Run 20260512070625 root cause #2: AI populated
    # mux_select_i0_net="ctmn_517750" (random CTS-renamed wire) while
    # new_select_inputs[0]="EcoUseSdpOutstRdCnt" (correct). Studier may pick
    # the wrong field downstream → wrong AND2 inputs → FM logical mismatch.
    mux_select_issues = []
    rtl_diff_doc = json.loads(open(args.rtl_diff).read())
    for idx, ch in enumerate(rtl_diff_doc.get('changes', [])):
        if ch.get('change_type') != 'wire_swap':
            continue
        new_inputs = ch.get('new_select_inputs') or []
        from_change = ch.get('new_select_inputs_from_change') or []
        if not new_inputs or len(new_inputs) < 2:
            continue
        i0_net = ch.get('mux_select_i0_net')
        i1_net = ch.get('mux_select_i1_net')
        # Only enforce when the corresponding flag says new_port
        for k, field_name, actual in (
            (0, 'mux_select_i0_net', i0_net),
            (1, 'mux_select_i1_net', i1_net),
        ):
            if k >= len(from_change) or not from_change[k]:
                continue   # not a new_port — flat-net resolve is allowed
            expected = new_inputs[k]
            if actual != expected:
                tgt = ch.get('target_register') or ch.get('new_token') or '?'
                mux_select_issues.append(
                    f"changes[{idx}] target={tgt} [FAIL/27-MUX-SELECT-FIELD-MISMATCH]: "
                    f"{field_name}={actual!r} but new_select_inputs[{k}]={expected!r} "
                    f"(new_select_inputs_from_change[{k}]=true means this signal is a new_port "
                    f"that doesn't exist as a flat net yet). The {field_name} field must equal "
                    f"the symbolic RTL name from new_select_inputs[k] — flat-net-resolve grabbed "
                    f"an unrelated wire. Step 3 studier reading {field_name} would build the "
                    f"wrong AND2 inputs → FM logical mismatch on {tgt}. "
                    f"Fix Step E mux_select branch to use new_select_inputs[k] verbatim when "
                    f"new_select_inputs_from_change[k]=true."
                )
                overall_pass = False

    # Check: and_term misclassified — should be wire_swap + intermediate_net_insertion
    # When an and_term change has a new_condition_gate_chain containing MUX2 gates,
    # the agent misclassified a priority chain as a simple gating term. This causes
    # the studier to do a simple gate modification and skip the full MUX cascade.
    and_term_mux_issues = []
    for idx, c in enumerate(rtl_diff.get('changes', [])):
        if c.get('change_type') != 'and_term':
            continue
        chain = c.get('new_condition_gate_chain') or []
        has_mux = any(g.get('gate_function', '').upper().startswith('MUX') for g in chain)
        if has_mux:
            and_term_mux_issues.append(
                f"changes[{idx}]: change_type='and_term' but new_condition_gate_chain "
                f"contains MUX2 gate(s) — this is a priority chain, NOT a simple and_term. "
                f"Must be classified as 'wire_swap' with fallback_strategy='intermediate_net_insertion'. "
                f"Studier will do simple gate modification and skip the MUX cascade.")
            overall_pass = False

    # Check: PENDING_FM_RESOLUTION on gate-structural inputs (inverted / comparison)
    # Check 9f — intermediate_net_insertion uses stage-unstable signals.
    # When intermediate_net_insertion is chosen but the new_condition_gate_chain
    # contains signals with 0 occurrences in any PreEco stage (synthesis-only
    # internal nets like phfnn_*, N<6-digit> synthesis nodes, etc.), the chain
    # will produce per-stage divergence that FM cannot verify without SVF.
    # Fix: use driver_substitution strategy instead — find a named intermediate
    # net in the backward cone, rename its driver, add compound gates using ONLY
    # stage-stable signals (new ECO ports, primary inputs).
    intermed_ins_issues = []
    if args.ref_dir:
        _preeco_gz = {
            s: os.path.join(args.ref_dir, 'data', 'PreEco', f'{s}.v.gz')
            for s in ('Synthesize', 'PrePlace', 'Route')
        }
        for idx, c in enumerate(rtl_diff.get('changes', [])):
            if c.get('fallback_strategy') != 'intermediate_net_insertion':
                continue
            chain = c.get('new_condition_gate_chain') or []
            tgt = c.get('target_register') or c.get('old_token') or '?'
            for g in chain:
                for inp in (g.get('inputs') or []):
                    if not isinstance(inp, str): continue
                    base = inp.split('[')[0]
                    # PENDING_ECO_PORT signals are VALID — new ECO ports are stage-stable
                    # (they exist after ECO application). Do NOT flag these.
                    if 'PENDING_ECO_PORT' in base:
                        continue
                    # PENDING_FM_RESOLUTION signals are explicitly stage-unstable —
                    # flag them directly instead of skipping
                    if 'PENDING_FM_RESOLUTION' in base:
                        raw = base.replace('PENDING_FM_RESOLUTION:', '')
                        intermed_ins_issues.append(
                            f"changes[{idx}] target={tgt} [FAIL/9f-PENDING-UNSTABLE]: "
                            f"intermediate_net_insertion gate uses PENDING_FM_RESOLUTION "
                            f"signal '{raw}' — stage-unstable by definition (FM-036 in P&R stages). "
                            f"Use driver_substitution with only ECO ports and primary inputs.")
                        overall_pass = False
                        continue
                    if base.startswith(("1'b", "0'b", "n_eco_", "SEQMAP_NET", "PENDING", "ECO_")): continue
                    # Check existence in all 3 PreEco stages
                    for stage, gz in _preeco_gz.items():
                        if not os.path.exists(gz): continue
                        try:
                            import subprocess as _sp
                            r = _sp.run(f'zgrep -c "{base}" {gz}',
                                shell=True, capture_output=True, text=True, timeout=30)
                            cnt = int(r.stdout.strip()) if r.stdout.strip().isdigit() else 0
                            if cnt == 0:
                                intermed_ins_issues.append(
                                    f"changes[{idx}] target={tgt} [FAIL/9f-STAGE-UNSTABLE]: "
                                    f"intermediate_net_insertion gate uses '{base}' which has "
                                    f"0 occurrences in {stage} PreEco — signal won't survive P&R. "
                                    f"Use driver_substitution: find a named net 2-3 hops upstream "
                                    f"of the pivot net, rename its driver, add compound gates using "
                                    f"only stage-stable signals (ECO ports, primary inputs).")
                                overall_pass = False
                                break  # one stage failure is enough to flag
                        except Exception:
                            pass

    # Check 9g — driver_substitution rules enforcement
    # Validates all 5 mandatory rules for driver_substitution target selection.
    driver_sub_issues = []
    for idx, c in enumerate(rtl_diff.get('changes', [])):
        if c.get('fallback_strategy') != 'driver_substitution': continue
        tgt = c.get('driver_sub_target_net', '')
        chain = c.get('new_condition_gate_chain') or []
        old_tok = c.get('old_token') or c.get('new_token') or '?'

        # Rule 1: target must NOT be the pivot net itself (SEQMAP_NET_*, old_token)
        if tgt and (tgt == old_tok or 'SEQMAP_NET' in tgt or tgt.startswith('SEQMAP')):
            driver_sub_issues.append(
                f"changes[{idx}] [FAIL/9g-DRVSUB-PIVOT-TARGET]: driver_sub_target_net='{tgt}' "
                f"is the pivot net itself — NEVER target the pivot net. Walk 2-5 hops UPSTREAM "
                f"to find a named intermediate net (ctmn_*) driven by a compound gate. "
                f"The pivot net path must remain UNCHANGED.")
            overall_pass = False

        # Rule 1b: driver_sub_renamed_to MUST appear in at least one gate's inputs
        # Without this, the old default expression (ECO_<jira>_net_orig) is completely
        # lost — the chain has no fallback case when no condition is true.
        renamed_to = c.get('driver_sub_renamed_to', '')
        if renamed_to and chain:
            uses_renamed = any(renamed_to in str(g.get('inputs', [])) for g in chain)
            if not uses_renamed:
                driver_sub_issues.append(
                    f"changes[{idx}] [FAIL/9g-DRVSUB-NO-DEFAULT]: driver_substitution chain "
                    f"never uses '{renamed_to}' (the renamed old expression) as a gate input. "
                    f"The old default case (BothArbPickCmds/old_expr) is completely lost. "
                    f"The final combination gate MUST include '{renamed_to}' as input — "
                    f"e.g. OA12(Cond2_trigger, {renamed_to}, ~Cond1_trigger) → {tgt}.")
                overall_pass = False

        # Rule 2: Last gate in chain MUST output driver_sub_target_net
        if chain and tgt:
            last_out = chain[-1].get('output_net', '')
            if last_out != tgt:
                driver_sub_issues.append(
                    f"changes[{idx}] [FAIL/9g-DRVSUB-INCOMPLETE]: driver_substitution chain "
                    f"last gate outputs '{last_out}' but must output '{tgt}' (driver_sub_target_net). "
                    f"The chain is INCOMPLETE — missing the final combination gate that drives "
                    f"'{tgt}' with the combined logic: "
                    f"(old_expr=ECO_<jira>_net_orig, Cond1_trigger, Cond2_trigger). "
                    f"Without this, '{tgt}' is UNDRIVEN after rename → FM ABORT. "
                    f"Add a final gate (e.g. OA12/OAI21/AO21) that combines the condition "
                    f"outputs + ECO_<jira>_net_orig and outputs '{tgt}'.")
                overall_pass = False

        # Rule 3: No MUX2 cascade in driver_substitution chains
        mux_gates = [g for g in chain if 'MUX' in g.get('gate_function','').upper()]
        if mux_gates:
            driver_sub_issues.append(
                f"changes[{idx}] [FAIL/9g-DRVSUB-NO-MUX]: driver_substitution chain contains "
                f"{len(mux_gates)} MUX2 gate(s) — MUX cascade belongs to intermediate_net_insertion only. "
                f"driver_substitution uses OA12/OAI21/AN3/ND3 compound gates DIRECTLY replacing "
                f"the target net driver. Remove MUX gates and use compound gates instead.")
            overall_pass = False

        # Rule: No PENDING_FM_RESOLUTION in driver_substitution chain (Check 9g)
        # Rule 4b: when driver_substitution has PENDING conditions, they must be REMOVED
        # from the chain — not kept and resolved in Step 2.
        pending_found = []
        for g in chain:
            for inp in (g.get('inputs') or []):
                if 'PENDING_FM_RESOLUTION' in str(inp):
                    raw = str(inp).replace('PENDING_FM_RESOLUTION:', '')
                    pending_found.append(raw)
        if pending_found:
            driver_sub_issues.append(
                f"changes[{idx}] [FAIL/9g-DRVSUB-PENDING]: driver_substitution chain contains "
                f"PENDING_FM_RESOLUTION signals: {list(set(pending_found))}. "
                f"These conditions MUST be removed from the chain (Rule 4b) — "
                f"driver_substitution uses only stage-stable signals. "
                f"Keep only conditions that use ECO ports and primary inputs. "
                f"If removed conditions are logically required, fall through to E4c.")
            overall_pass = False

    # Check 9h — driver_substitution: at least one stage-stable condition must remain
    # after removing PENDING_FM_RESOLUTION conditions. If all conditions were PENDING,
    # driver_substitution cannot be used at all — fall through to E4c/E4d.
    driver_sub_empty_issues = []
    for idx, c in enumerate(rtl_diff.get('changes', [])):
        if c.get('fallback_strategy') != 'driver_substitution': continue
        chain = c.get('new_condition_gate_chain') or []
        tgt = c.get('old_token') or c.get('new_token') or '?'
        # Count gates with ALL inputs stage-stable (no PENDING_FM_RESOLUTION)
        stable_gates = []
        for g in chain:
            all_stable = all('PENDING_FM_RESOLUTION' not in str(i) for i in (g.get('inputs') or []))
            if all_stable and 'MUX' not in g.get('gate_function','').upper():
                stable_gates.append(g.get('seq','?'))
        if chain and not stable_gates:
            driver_sub_empty_issues.append(
                f"changes[{idx}] target={tgt} [FAIL/9h-DRVSUB-EMPTY]: after removing "
                f"PENDING_FM_RESOLUTION conditions, NO stage-stable gate conditions remain. "
                f"driver_substitution requires at least one condition using only ECO ports "
                f"and primary inputs. Fall through to E4c/E4d instead.")
            overall_pass = False

    # These should be decomposed as INV/NAND/AND gates, not marked as PENDING.
    # PENDING is only valid for raw RTL signal names that V3 grep cannot find.
    pending_structural_issues = []
    for idx, c in enumerate(rtl_diff.get('changes', [])):
        for fld in ('d_input_gate_chain', 'new_condition_gate_chain'):
            for g in (c.get(fld) or []):
                for inp in (g.get('inputs') or []):
                    if not isinstance(inp, str) or not inp.startswith('PENDING_FM_RESOLUTION:'):
                        continue
                    raw = inp[len('PENDING_FM_RESOLUTION:'):]
                    # Structural patterns that should never be PENDING.
                    # Rule: if the PENDING name itself describes a gate operation
                    # (~X inversion, X==K comparison) it should be decomposed as
                    # a gate — not looked up by FM.
                    # Heuristic: common synthesis suffixes that indicate the signal
                    # is a derived/inverted/compared form rather than a raw RTL reg.
                    structural = bool(re.search(
                        r'(_inv\d*|_bar|_n|_neq\w*|_eq\w*|_not\w*|_inverted)$',
                        raw, re.IGNORECASE
                    ))
                    if structural:
                        pending_structural_issues.append(
                            f"changes[{idx}].{fld}[{g.get('seq','?')}]: "
                            f"input {inp!r} looks like a gate operation (~X or X==K bit) "
                            f"that should be decomposed as INV/NAND/AND gate, not PENDING_FM_RESOLUTION. "
                            f"Only raw RTL signal names that fail V3 grep should be PENDING.")
                        overall_pass = False

    out = {
        'rtl_diff': args.rtl_diff,
        'mux_select_issue_count': len(mux_select_issues),
        'mux_select_issues':      mux_select_issues,
        'wire_swap_count':       len(results),
        'phantom_wire_count':    len(phantom),
        'phantom_wire_issues':   phantom,
        'new_port_issue_count':  len(decl_issues),
        'new_port_issues':       decl_issues,
        'port_conn_issue_count': len(pc_issues),
        'port_conn_issues':      pc_issues,
        'truth_table_issue_count': len(tt_issues),
        'truth_table_issues':      tt_issues,
        'signal_in_scope_issue_count': len(sis_issues),
        'signal_in_scope_issues':      sis_issues,
        'chain_equivalence_issue_count': len(chain_eq_issues),
        'chain_equivalence_issues':      chain_eq_issues,
        'new_logic_field_issue_count':   len(new_logic_field_issues),
        'new_logic_field_issues':        new_logic_field_issues,
        'mode_i_field_issue_count':      len(mode_i_field_issues),
        'mode_i_field_issues':           mode_i_field_issues,
        'scope_field_issue_count':       len(scope_field_issues),
        'scope_field_issues':            scope_field_issues,
        'wire_swap_field_issue_count':   len(wire_swap_field_issues),
        'wire_swap_field_issues':        wire_swap_field_issues,
        'unconnected_var_issue_count':   len(unconnected_var_issues),
        'unconnected_var_issues':        unconnected_var_issues,
        'chain_compactness_issue_count': len(chain_compact_issues),
        'chain_compactness_issues':      chain_compact_issues,
        'reset_inclusion_issue_count':   len(reset_inclusion_issues),
        'reset_inclusion_issues':        reset_inclusion_issues,
        'and_term_mux_issue_count':        len(and_term_mux_issues),
        'and_term_mux_issues':             and_term_mux_issues,
        'driver_sub_issue_count':          len(driver_sub_issues),
        'driver_sub_issues':               driver_sub_issues,
        'driver_sub_empty_issue_count':    len(driver_sub_empty_issues),
        'driver_sub_empty_issues':         driver_sub_empty_issues,
        'intermed_ins_issue_count':        len(intermed_ins_issues),
        'intermed_ins_issues':             intermed_ins_issues,
        'pending_structural_issue_count': len(pending_structural_issues),
        'pending_structural_issues':      pending_structural_issues,
        'overall_pass':          overall_pass,
        'entries':               results,
    }
    with open(args.output, 'w') as f:
        json.dump(out, f, indent=2)

    print('ECO_SCRIPT_LAUNCHED: eco_validate_step1.py')
    print(f'  rtl_diff: {args.rtl_diff}')
    print(f'  entries:  {len(results)}  phantom_wire: {len(phantom)}  new_port_issues: {len(decl_issues)}  port_conn_issues: {len(pc_issues)}  truth_table_issues: {len(tt_issues)}  signal_in_scope_issues: {len(sis_issues)}  chain_equivalence_issues: {len(chain_eq_issues)}  new_logic_field_issues: {len(new_logic_field_issues)}  mode_i_field_issues: {len(mode_i_field_issues)}  scope_field_issues: {len(scope_field_issues)}  wire_swap_field_issues: {len(wire_swap_field_issues)}  unconnected_var_issues: {len(unconnected_var_issues)}  chain_compactness_issues: {len(chain_compact_issues)}  reset_inclusion_issues: {len(reset_inclusion_issues)}')
    print(f'  overall:  {"PASS" if overall_pass else "FAIL"}')
    for p in phantom:
        print(f'    - {p}')
    for p in decl_issues:
        print(f'    - {p}')
    for p in pc_issues:
        print(f'    - {p}')
    for p in tt_issues:
        print(f'    - {p}')
    for p in sis_issues:
        print(f'    - {p}')
    for p in chain_eq_issues:
        print(f'    - {p}')
    for p in new_logic_field_issues:
        print(f'    - {p}')
    for p in mode_i_field_issues:
        print(f'    - {p}')
    for p in scope_field_issues:
        print(f'    - {p}')
    for p in wire_swap_field_issues:
        print(f'    - {p}')
    for p in unconnected_var_issues:
        print(f'    - {p}')
    for p in chain_compact_issues:
        print(f'    - {p}')
    for p in reset_inclusion_issues:
        print(f'    - {p}')
    for r in results:
        if r['issues']:
            print(f'  FAIL [{r["target_register"]}] gate={r["gate_function"]} branch={r["branch_true_on"]}')
            for iss in r['issues']:
                print(f'    - {iss}')

    sys.exit(0 if overall_pass else 1)


if __name__ == '__main__':
    main()
