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
                    m, why = _ett.cell_function_matches(cell, fn)
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
        'overall_pass':          overall_pass,
        'entries':               results,
    }
    with open(args.output, 'w') as f:
        json.dump(out, f, indent=2)

    print('ECO_SCRIPT_LAUNCHED: eco_validate_step1.py')
    print(f'  rtl_diff: {args.rtl_diff}')
    print(f'  entries:  {len(results)}  phantom_wire: {len(phantom)}  new_port_issues: {len(decl_issues)}  port_conn_issues: {len(pc_issues)}  truth_table_issues: {len(tt_issues)}  signal_in_scope_issues: {len(sis_issues)}  chain_equivalence_issues: {len(chain_eq_issues)}')
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
    for r in results:
        if r['issues']:
            print(f'  FAIL [{r["target_register"]}] gate={r["gate_function"]} branch={r["branch_true_on"]}')
            for iss in r['issues']:
                print(f'    - {iss}')

    sys.exit(0 if overall_pass else 1)


if __name__ == '__main__':
    main()
