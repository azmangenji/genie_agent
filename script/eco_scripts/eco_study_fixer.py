#!/usr/bin/env python3
"""
eco_study_fixer.py — Auto-apply deterministic fixes to eco_preeco_study.json
based on eco_validate_step3.py issues.

Called by STUDY_ORCHESTRATOR after the validator fails. Handles deterministic
fixes only; non-deterministic issues (UNRESOLVABLE after script) are left for
agent/engineer intervention.

Usage:
    python3 script/eco_scripts/eco_study_fixer.py \\
        --study   data/<TAG>_eco_preeco_study.json \\
        --issues  data/<TAG>_eco_validate_step3.json \\
        --rtl-diff data/<TAG>_eco_rtl_diff.json \\
        --ref-dir <REF_DIR> \\
        --raw-rpts data/*_find_equivalent_nets_raw*.rpt \\
        --step2-rpt data/<TAG>_eco_step2_fenets.rpt \\
        --output  data/<TAG>_eco_preeco_study.json

Returns exit code 0 if all issues fixed, 1 if issues remain (need manual fix).
Prints summary of fixes applied and remaining issues.
"""
import argparse, glob, json, os, re, subprocess, sys

STAGES = ('Synthesize', 'PrePlace', 'Route')


# ── helpers ───────────────────────────────────────────────────────────────────

def run_resolve(ref_dir, synth_net, stage):
    """Run eco_resolve_synth_internal.py. Returns resolved_net or 'UNRESOLVABLE'."""
    script = os.path.join(os.path.dirname(__file__), 'eco_resolve_synth_internal.py')
    out = '/tmp/eco_study_fixer_resolve.json'
    try:
        subprocess.run(
            f'python3 {script} --ref-dir {ref_dir} --synth-net {synth_net} '
            f'--stage {stage} --output {out}',
            shell=True, timeout=120, capture_output=True)
        r = json.load(open(out))
        return r.get('resolved_net', 'UNRESOLVABLE')
    except Exception:
        return 'UNRESOLVABLE'


def read_raw_polarity(raw_rpts, cell_inst):
    """Read FM (+/-) polarity for a cell instance from raw rpt files."""
    raw_text = ''
    for rp in sorted(raw_rpts):
        try:
            raw_text += open(rp).read()
        except Exception:
            pass
    if not raw_text:
        return None
    m = re.search(
        r'Impl\s+Net\s+([+\-])\s+i:[^\n]+/' + re.escape(cell_inst) + r'/',
        raw_text)
    return m.group(1) if m else None


def read_condition_resolutions(step2_rpt):
    """Parse CONDITION_INPUT_RESOLUTIONS from step2 rpt."""
    res = {}
    if not step2_rpt or not os.path.exists(step2_rpt):
        return res
    for line in open(step2_rpt):
        m = re.match(r'\s+(\w+):\s+resolved=(\S+)', line)
        if m:
            res[m.group(1)] = m.group(2)
    return res


# ── per-issue fixers ──────────────────────────────────────────────────────────

def fix_andterm_wrong_polarity(study, issue_text, raw_rpts):
    """ANDTERM-WRONG-POLARITY: flip gate function based on FM polarity."""
    inst_m = re.search(r"'(eco_\w+)'\s+uses\s+(NOR2|INR2)\s+but.*\(([+\-])\)", issue_text)
    if not inst_m:
        return False
    inst, wrong, fm_pol = inst_m.group(1), inst_m.group(2), inst_m.group(3)
    correct = 'INR2' if fm_pol == '+' else 'NOR2'
    if wrong == correct:
        return False
    # INR2 cell: A1&~B1 / NOR2 cell: ~(A1|A2)
    cell_map = {'INR2': 'INR2D1BWP136P5M156H3P48CPDLVT',
                'NOR2': 'NR2D1SPG1AMDBWP136P5M156H3P48CPDLVT'}
    fixed = 0
    for stage in STAGES:
        for e in study.get(stage, []):
            if e.get('instance_name') == inst and e.get('gate_function') == wrong:
                e['gate_function'] = correct
                e['cell_type'] = cell_map.get(correct, correct)
                fixed += 1
    return fixed > 0


def fix_net_absent(study, issue_text, ref_dir):
    """NET-ABSENT-IN-STAGE: run eco_resolve_synth_internal.py to find correct net."""
    m = re.search(r'(Synthesize|PrePlace|Route)\s+(eco_\w+)\.(\w+)\s+=\s+\'(\S+)\'', issue_text)
    if not m:
        return False, 'parse_failed'
    stage, inst, pin, wrong_net = m.group(1), m.group(2), m.group(3), m.group(4)
    if stage == 'Synthesize':
        return False, 'synth_absent_manual'
    # Determine Synth net for this pin
    synth_net = None
    for e in study.get('Synthesize', []):
        if e.get('instance_name') == inst:
            pps = e.get('port_connections_per_stage', {})
            synth_net = (pps.get('Synthesize') or {}).get(pin) or \
                        (e.get('port_connections') or {}).get(pin)
            break
    if not synth_net or any(synth_net.startswith(p) for p in
                             ('UNRESOLVABLE', 'PENDING', 'MODE_H', 'NEEDS', "1'b")):
        return False, 'no_synth_net'
    resolved = run_resolve(ref_dir, synth_net, stage)
    if resolved == 'UNRESOLVABLE':
        return False, f'unresolvable:{synth_net}'
    # Apply fix across all study stage entries
    fixed = 0
    for st in STAGES:
        for e in study.get(st, []):
            if e.get('instance_name') != inst:
                continue
            pps = e.setdefault('port_connections_per_stage', {})
            pps.setdefault(stage, {})[pin] = resolved
            fixed += 1
    return fixed > 0, f'{synth_net}→{resolved}'


def fix_pending_unresolved(study, issue_text, ref_dir):
    """PENDING-UNRESOLVED: run eco_resolve_synth_internal.py."""
    m = re.search(r'(Synthesize|PrePlace|Route)\s+(eco_\w+).*\[(\w+)\]\.(\w+)\s+=\s+\w+:(\w+)',
                  issue_text)
    if not m:
        return False, 'parse_failed'
    study_stage, inst, pps_stage, pin, sig = (m.group(1), m.group(2), m.group(3),
                                               m.group(4), m.group(5))
    if pps_stage == 'Synthesize':
        return False, 'synth_pending_manual'
    # Find synth resolved net from condition_resolutions or study
    synth_net = None
    for e in study.get('Synthesize', []):
        if e.get('instance_name') == inst:
            pps = e.get('port_connections_per_stage', {})
            synth_net = (pps.get('Synthesize') or {}).get(pin)
            break
    if not synth_net or any(synth_net.startswith(p) for p in
                             ('UNRESOLVABLE', 'PENDING', 'MODE_H', 'NEEDS')):
        return False, 'no_synth_net'
    resolved = run_resolve(ref_dir, synth_net, pps_stage)
    if resolved == 'UNRESOLVABLE':
        return False, f'unresolvable:{synth_net}'
    fixed = 0
    for st in STAGES:
        for e in study.get(st, []):
            if e.get('instance_name') != inst:
                continue
            pps = e.setdefault('port_connections_per_stage', {})
            pps.setdefault(pps_stage, {})[pin] = resolved
            fixed += 1
    return fixed > 0, f'{synth_net}→{resolved}'


def fix_condition_polarity(study, issue_text, cond_res):
    """CONDITION-POLARITY: replace wrong Synth net with resolved net."""
    m = re.search(r"(eco_\w+)\.(\w+)\s+=\s+'(\S+)'.*resolved.*to\s+'(\S+)'", issue_text)
    if not m:
        return False
    inst, pin, wrong, correct = m.group(1), m.group(2), m.group(3), m.group(4)
    fixed = 0
    for stage in STAGES:
        for e in study.get(stage, []):
            if e.get('instance_name') != inst:
                continue
            pps = e.get('port_connections_per_stage', {})
            synth_p = pps.get('Synthesize', {})
            if synth_p.get(pin) == wrong:
                synth_p[pin] = correct
                fixed += 1
            pcs = e.get('port_connections', {})
            if pcs.get(pin) == wrong:
                pcs[pin] = correct
                fixed += 1
    return fixed > 0


def fix_rewire_cell_absent(study, issue_text):
    """REWIRE-CELL-ABSENT: mark for manual fix (needs rename_map lookup)."""
    # This requires rename_map — flag as manual for now
    return False, 'needs_rename_map_lookup'


# ── main ──────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--study',    required=True)
    ap.add_argument('--issues',   required=True, help='eco_validate_step3.json')
    ap.add_argument('--rtl-diff', required=True)
    ap.add_argument('--ref-dir',  required=True)
    ap.add_argument('--raw-rpts', nargs='*', default=[])
    ap.add_argument('--step2-rpt', default='')
    ap.add_argument('--output',   required=True)
    args = ap.parse_args()

    study = json.load(open(args.study))
    validate = json.load(open(args.issues))
    issues = validate.get('issues', [])
    raw_rpts = args.raw_rpts or glob.glob(os.path.join(
        os.path.dirname(args.study), '*_find_equivalent_nets_raw*.rpt'))
    cond_res = read_condition_resolutions(args.step2_rpt)

    if not issues:
        print('No issues to fix.')
        json.dump(study, open(args.output, 'w'), indent=2)
        sys.exit(0)

    fixed_list = []
    remaining = []

    for issue in issues:
        applied = False
        detail = ''

        if 'ANDTERM-WRONG-POLARITY' in issue:
            applied = fix_andterm_wrong_polarity(study, issue, raw_rpts)
            detail = 'flip NOR2↔INR2'

        elif 'NET-ABSENT-IN-STAGE' in issue:
            applied, detail = fix_net_absent(study, issue, args.ref_dir)

        elif 'PENDING-UNRESOLVED' in issue:
            applied, detail = fix_pending_unresolved(study, issue, args.ref_dir)

        elif 'CONDITION-POLARITY' in issue:
            applied = fix_condition_polarity(study, issue, cond_res)
            detail = 'replace with resolved net'

        elif 'REWIRE-CELL-ABSENT' in issue:
            applied, detail = fix_rewire_cell_absent(study, issue)

        if applied:
            fixed_list.append(f'FIXED [{detail}]: {issue[:80]}...')
        else:
            remaining.append(f'MANUAL [{detail}]: {issue[:80]}...')

    json.dump(study, open(args.output, 'w'), indent=2)

    print(f'\n=== eco_study_fixer results ===')
    print(f'Fixed:     {len(fixed_list)}')
    print(f'Remaining: {len(remaining)}')
    for f in fixed_list:
        print(f'  ✅ {f}')
    for r in remaining:
        print(f'  ❌ {r}')

    sys.exit(0 if not remaining else 1)


if __name__ == '__main__':
    main()
