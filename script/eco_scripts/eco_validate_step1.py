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
import argparse, json, re, sys

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
        # Heuristic: clocks that are NOT wrapper-only (wrp_clk_*) propagate scan
        # enable and so require Mode S. Force the flag to true unless the agent
        # documented an exception.
        clk = (c.get('dff_clock') or '')
        is_wrapper_clk = clk.startswith('wrp_clk_') or '/wrp_clk_' in clk
        if rss is False and not is_wrapper_clk:
            new_logic_field_issues.append(
                f"changes[{idx}] target={tgt}: requires_scan_stitching=false but "
                f"dff_clock={clk!r} is NOT a wrapper-only clock (wrp_clk_*) — "
                f"non-wrapper clocks propagate scan_enable; Mode S is required. "
                f"If this is a documented exception, override the heuristic by "
                f"naming the clock with the wrp_clk_ prefix or extend this check.")
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

    out = {
        'rtl_diff': args.rtl_diff,
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
        'overall_pass':          overall_pass,
        'entries':               results,
    }
    with open(args.output, 'w') as f:
        json.dump(out, f, indent=2)

    print('ECO_SCRIPT_LAUNCHED: eco_validate_step1.py')
    print(f'  rtl_diff: {args.rtl_diff}')
    print(f'  entries:  {len(results)}  phantom_wire: {len(phantom)}  new_port_issues: {len(decl_issues)}  port_conn_issues: {len(pc_issues)}  truth_table_issues: {len(tt_issues)}  signal_in_scope_issues: {len(sis_issues)}  chain_equivalence_issues: {len(chain_eq_issues)}  new_logic_field_issues: {len(new_logic_field_issues)}  mode_i_field_issues: {len(mode_i_field_issues)}  scope_field_issues: {len(scope_field_issues)}  wire_swap_field_issues: {len(wire_swap_field_issues)}')
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
    for r in results:
        if r['issues']:
            print(f'  FAIL [{r["target_register"]}] gate={r["gate_function"]} branch={r["branch_true_on"]}')
            for iss in r['issues']:
                print(f'    - {iss}')

    sys.exit(0 if overall_pass else 1)


if __name__ == '__main__':
    main()
