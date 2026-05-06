#!/usr/bin/env python3
"""
eco_mux_polarity_check.py — Deterministic validator for MUX-select polarity
fields in eco_rtl_diff.json. Catches the recurring NAND vs AND class of bugs
at Step 1 instead of waiting for FM to fail 6 hours later.

Runs the D-MUX-6 cross-checks from rtl_diff_analyzer.md as pure data checks:
  Check 1: mux_select_old_driver_inverting matches cell_type prefix
  Check 2: mux_select_old_S_when_condition_true follows from inverting flag
  Check 3: mux_select_branch_true_on follows from old_S
  Check 4: mux_select_gate_function output @ new_cond=TRUE equals old_S
           (only enforced when gate is in the simple table below)
  Check 5: mux_select_reasoning has no backtracking phrases

Usage:
    python3 script/eco_scripts/eco_mux_polarity_check.py \
        --rtl-diff data/<TAG>_eco_rtl_diff.json \
        --output   data/<TAG>_eco_mux_polarity_check.json

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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--rtl-diff', required=True)
    ap.add_argument('--output',   required=True)
    args = ap.parse_args()

    rtl_diff = json.load(open(args.rtl_diff))
    results, overall_pass = [], True
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
        'wire_swap_count': len(results),
        'overall_pass':    overall_pass,
        'entries':         results,
    }
    with open(args.output, 'w') as f:
        json.dump(out, f, indent=2)

    print('ECO_SCRIPT_LAUNCHED: eco_mux_polarity_check.py')
    print(f'  rtl_diff: {args.rtl_diff}')
    print(f'  entries:  {len(results)}')
    print(f'  overall:  {"PASS" if overall_pass else "FAIL"}')
    for r in results:
        if r['issues']:
            print(f'  FAIL [{r["target_register"]}] gate={r["gate_function"]} branch={r["branch_true_on"]}')
            for iss in r['issues']:
                print(f'    - {iss}')

    sys.exit(0 if overall_pass else 1)


if __name__ == '__main__':
    main()
