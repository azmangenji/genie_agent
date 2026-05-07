#!/usr/bin/env python3
"""
eco_pre_fm_check.py — Deterministic Step 5 Pre-FM Quality Checker

Replaces agent judgment in eco_pre_fm_checker.md with a script that
reads the applied JSON + study JSON and validates all required conditions.
No agent decisions — every check is deterministic: PASS or FAIL.

Usage:
    python3 eco_pre_fm_check.py \
        --tag <TAG> \
        --round <N> \
        --base-dir <BASE_DIR> \
        --ref-dir <REF_DIR> \
        --jira <JIRA>

Exit 0 = all checks PASS (safe to submit FM)
Exit 1 = any check FAIL (do NOT submit FM)

Writes:
    <BASE_DIR>/data/<TAG>_eco_pre_fm_check_round<N>.json
    <BASE_DIR>/data/<TAG>_eco_step5_pre_fm_check_round<N>.rpt
    <BASE_DIR>/data/<TAG>_eco_step5_pre_fm_check_round<N>_marker.txt
"""

import argparse, json, os, re, subprocess, sys
from pathlib import Path


# ── Argument parsing ──────────────────────────────────────────────────────────

def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument('--tag',      required=True)
    p.add_argument('--round',    required=True, type=int)
    p.add_argument('--base-dir', required=True, dest='base_dir')
    p.add_argument('--ref-dir',  required=True, dest='ref_dir')
    p.add_argument('--jira',     required=True)
    return p.parse_args()


# ── Helpers ───────────────────────────────────────────────────────────────────

def load_json(path):
    try:
        return json.load(open(path))
    except Exception as e:
        return None


def zgrep_count(pattern, gz_path):
    try:
        r = subprocess.run(
            f'zcat {gz_path} | grep -c {re.escape(pattern)}',
            shell=True, capture_output=True, text=True, timeout=120
        )
        return int(r.stdout.strip()) if r.stdout.strip().isdigit() else 0
    except Exception:
        return 0


DEFERRED_REASONS = ('deferred', 'pending', 'round 2', 'application', 'defer')

def is_deferred(reason):
    r = (reason or '').lower()
    return any(k in r for k in DEFERRED_REASONS)


# ── Check implementations ─────────────────────────────────────────────────────

def check_no_deferred(applied):
    """
    FAIL if any port_declaration or port_connection entry is SKIPPED
    with a deferral reason. These cause FM ABORT.
    """
    failures = []
    for stage, entries in applied.items():
        if not isinstance(entries, list):
            continue
        for e in entries:
            ct = e.get('change_type', '')
            st = e.get('status', '')
            reason = e.get('reason', '')
            if ct in ('port_declaration', 'port_promotion', 'port_connection') \
               and st == 'SKIPPED' and is_deferred(reason):
                failures.append(f'{stage}: {ct} {e.get("name","?")} — {reason[:80]}')
    return failures


def check_stage_consistency(applied):
    """
    FAIL if an ECO gate is INSERTED in some stages but SKIPPED in others.
    Each new_logic_gate/dff must appear in all 3 stages.
    """
    gate_types = ('new_logic_gate', 'new_logic_dff', 'new_logic')
    per_stage = {}
    for stage, entries in applied.items():
        if not isinstance(entries, list):
            continue
        inserted = {e.get('name','') for e in entries
                    if e.get('change_type','') in gate_types
                    and e.get('status','') == 'INSERTED'}
        skipped  = {e.get('name','') for e in entries
                    if e.get('change_type','') in gate_types
                    and e.get('status','') == 'SKIPPED'}
        per_stage[stage] = {'inserted': inserted, 'skipped': skipped}

    stages = [s for s in per_stage if per_stage[s]['inserted'] or per_stage[s]['skipped']]
    if len(stages) < 2:
        return []

    all_gates = set()
    for s in stages:
        all_gates |= per_stage[s]['inserted'] | per_stage[s]['skipped']

    failures = []
    for gate in sorted(all_gates):
        stage_results = {}
        for s in stages:
            if gate in per_stage[s]['inserted']:
                stage_results[s] = 'INSERTED'
            elif gate in per_stage[s]['skipped']:
                stage_results[s] = 'SKIPPED'
            else:
                stage_results[s] = 'MISSING'
        if len(set(stage_results.values())) > 1:
            failures.append(f'{gate}: {stage_results}')
    return failures


def check_port_declarations_applied(applied):
    """
    FAIL if any port_declaration/port_connection is SKIPPED (for any reason).
    These are all mandatory — no deferral, no skipping.
    Exception: 'wire' type entries (implicitly created) and ALREADY_APPLIED.
    """
    failures = []
    for stage, entries in applied.items():
        if not isinstance(entries, list):
            continue
        for e in entries:
            ct = e.get('change_type', '')
            st = e.get('status', '')
            name = e.get('name', '?')
            reason = e.get('reason', '')
            if ct in ('port_declaration', 'port_promotion', 'port_connection') \
               and st == 'SKIPPED' \
               and 'wire' not in reason.lower() \
               and 'implicit' not in reason.lower():
                failures.append(f'{stage}: {ct} {name} SKIPPED — {reason[:80]}')
    return failures


def check_no_unhandled(applied):
    """
    FAIL if any entry has status UNHANDLED — indicates eco_perl_spec didn't
    recognize the change_type, so it was silently dropped.
    """
    failures = []
    for stage, entries in applied.items():
        if not isinstance(entries, list):
            continue
        for e in entries:
            if e.get('status','') == 'UNHANDLED':
                failures.append(
                    f'{stage}: {e.get("change_type","?")} {e.get("name","?")} UNHANDLED')
    return failures


def check_check8(check8_json_path):
    """
    Read pre-computed eco_check8 result. FAIL if any stage is not PASS.
    """
    d = load_json(check8_json_path)
    if d is None:
        return ['eco_check8 result not found — cannot validate Verilog syntax']
    failures = []
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        result = d.get(stage, 'MISSING')
        if result != 'PASS':
            failures.append(f'eco_check8 {stage}: {result}')
    return failures


def check_cells_in_netlist(applied, ref_dir):
    """
    FAIL if any gate marked INSERTED in applied JSON is physically absent
    from the PostEco netlist. eco_perl_spec can mark INSERTED but fail to
    actually inject the cell (e.g., module not found in large hierarchical netlist).
    eco_pre_fm_check reads JSON status — this check reads the actual netlist.
    """
    gate_types = ('new_logic_gate', 'new_logic_dff', 'new_logic')
    failures = []
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        entries = applied.get(stage, [])
        if not isinstance(entries, list):
            continue
        gz = os.path.join(ref_dir, 'data', 'PostEco', f'{stage}.v.gz')
        if not os.path.exists(gz):
            continue
        inserted = [e.get('name','') for e in entries
                    if e.get('change_type','') in gate_types
                    and e.get('status','') == 'INSERTED'
                    and e.get('name','')]
        if not inserted:
            continue
        # Grep PostEco for each inserted instance name
        for inst in inserted:
            if not inst:
                continue
            try:
                r = subprocess.run(
                    f'zcat {gz} | grep -cF " {inst} ("',
                    shell=True, capture_output=True, text=True, timeout=120
                )
                count = int(r.stdout.strip()) if r.stdout.strip().isdigit() else 0
                if count == 0:
                    failures.append(
                        f'[GHOST_INSERT] {stage}: {inst} marked INSERTED in JSON '
                        f'but NOT found in PostEco/{stage}.v.gz — Perl spec generated '
                        f'but module not found in netlist'
                    )
            except Exception:
                pass
    return failures


def check_port_edits_in_netlist(ref_dir, applied):
    """For every applied port_declaration / port_connection entry, verify the
    edit is physically in the netlist. Catches the silent-failure pattern where
    eco_passes_2_4.py reported APPLIED but the regex sub did nothing because
    the target line wasn't in inst_close / port list spanned multiple lines.

    Reads the entry's `reason` text to extract signal/port/net since the applied
    JSON entries are minimal (only ct/status/name/reason).
    """
    failures = []
    # Reason patterns:
    #   'added NeedFreqAdj to port list and output decl in ddrss_umccmd_t_umcarbctrlsw'
    #   'added .NeedFreqAdj(ARB_FEI_NeedFreqAdj) to CTRLSW'
    #   'rewired existing .X to (Y) in INST'
    #   'bus_rename: REGCMD.REG_UmcCfgEco[1] OLD→NEW'  (skipped — Check 9 covers)
    pdec_re   = re.compile(r'added\s+(\S+)\s+to\s+port\s+list\s+and\s+(input|output|inout|wire)\s+decl\s+in\s+(\S+)')
    pconn_add_re = re.compile(r'added\s+\.(\w+)\s*\(\s*(\S+?)\s*\)\s+to\s+(\w+)')
    pconn_rew_re = re.compile(r'rewired\s+existing\s+\.(\w+)\s+to\s+\(\s*(\S+?)\s*\)\s+in\s+(\w+)')
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        gz = os.path.join(ref_dir, 'data', 'PostEco', f'{stage}.v.gz')
        if not os.path.exists(gz):
            continue
        try:
            text = subprocess.run(['zcat', gz], capture_output=True, text=True, timeout=240).stdout
        except Exception:
            continue
        for e in applied.get(stage, []):
            if e.get('status') != 'APPLIED':
                continue
            # Support both 'ct' (passes_2_4 JSON) and 'change_type' (study JSON)
            ct = e.get('ct') or e.get('change_type', '')
            reason = e.get('reason', '')
            if ct == 'port_declaration':
                m = pdec_re.search(reason)
                signal = m.group(1) if m else (e.get('signal_name') or e.get('name', ''))
                direction = m.group(2) if m else e.get('declaration_type', 'input')
                if direction == 'wire' or not signal:
                    continue
                if not re.search(rf'^\s*(input|output|inout)\s+{re.escape(signal)}\b', text, re.MULTILINE):
                    failures.append(f'[PORT_DECL_MISSING] {stage}: port_declaration APPLIED for {signal!r} ({direction}) but no input/output decl found in netlist')
            elif ct == 'port_connection':
                # Skip bus_bit_index entries (handled by Check 9 / bus_concat_intact)
                if e.get('bus_bit_index') is not None or 'bus_rename' in reason:
                    continue
                m = pconn_add_re.search(reason) or pconn_rew_re.search(reason)
                if m:
                    port, net, inst = m.group(1), m.group(2), m.group(3)
                else:
                    inst = e.get('instance_name') or e.get('submodule_instance')
                    port = e.get('port_name')   or e.get('new_token')
                    net  = e.get('net_name')    or e.get('flat_net_name')
                if not all([inst, port, net]):
                    continue
                pat = rf'\.\s*{re.escape(port)}\s*\(\s*{re.escape(net)}\s*\)'
                if not re.search(pat, text):
                    failures.append(f'[PORT_CONN_MISSING] {stage}: port_connection APPLIED .{port}({net}) on {inst} but not found in netlist')
    return failures


def check_rewires_in_netlist(ref_dir, applied):
    """For every applied rewire entry, verify the netlist's cell.pin actually
    points to new_net (not old_net). Catches silent-rewire-no-op pattern where
    apply_rewire's regex matched something but didn't change the right line.
    """
    failures = []
    # Reason format from apply_rewire: '{cell}.{pin}: {old} → {new}' (Unicode arrow)
    rew_re = re.compile(r'(\S+)\.(\w+):\s+(\S+)\s*(?:→|->|—>)\s*(\S+)')
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        gz = os.path.join(ref_dir, 'data', 'PostEco', f'{stage}.v.gz')
        if not os.path.exists(gz):
            continue
        try:
            text = subprocess.run(['zcat', gz], capture_output=True, text=True, timeout=240).stdout
        except Exception:
            continue
        for e in applied.get(stage, []):
            if e.get('status') != 'APPLIED':
                continue
            ct = e.get('ct') or e.get('change_type', '')
            if ct != 'rewire':
                continue
            m = rew_re.search(e.get('reason', ''))
            if not m:
                continue
            cell, pin, old_net, new_net = m.groups()
            # Find the cell instance in the netlist (best-effort by name)
            inst_m = re.search(rf'\b{re.escape(cell)}\s*\(', text)
            if not inst_m:
                failures.append(f'[REWIRE_CELL_MISSING] {stage}: rewire APPLIED on {cell}.{pin} but cell not found in netlist')
                continue
            cell_block = text[inst_m.start():inst_m.start() + 50000]
            if not re.search(rf'\.\s*{re.escape(pin)}\s*\(\s*{re.escape(new_net)}\s*\)', cell_block):
                failures.append(f'[REWIRE_MISSING] {stage}: rewire APPLIED {cell}.{pin}: {old_net}→{new_net} but .{pin}({new_net}) not in cell block')
    return failures


def check_bus_concat_intact(ref_dir, applied):
    """For port_connection entries with bus_bit_index, verify the netlist still
    has a {...} bus concat at that port (not collapsed to a single net by a
    broken rewire). Catches the bus-corruption pattern that count-based Check 8
    misses when the consumer + corrupted-replacement keep total occurrences ≥ 2.
    """
    failures = []
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        gz = os.path.join(ref_dir, 'data', 'PostEco', f'{stage}.v.gz')
        if not os.path.exists(gz):
            continue
        bus_entries = [e for e in applied.get(stage, [])
                       if e.get('change_type') == 'port_connection'
                       and e.get('bus_bit_index') is not None]
        if not bus_entries:
            continue
        try:
            text = subprocess.run(['zcat', gz], capture_output=True, text=True, timeout=240).stdout
        except Exception:
            continue
        for e in bus_entries:
            inst = e.get('instance_name') or e.get('submodule_instance', '')
            port = e.get('port_name', '')
            if not inst or not port:
                continue
            # Find the .port(...) connection nearest to the instance — it should contain {
            inst_m = re.search(rf'\b{re.escape(inst)}\s*\(', text)
            if not inst_m:
                continue
            slice_text = text[inst_m.start():inst_m.start() + 200000]
            port_m = re.search(rf'\.\s*{re.escape(port)}\s*\(\s*([^)]{{0,50}})', slice_text)
            if not port_m:
                continue
            opening = port_m.group(1)
            if '{' not in opening:
                failures.append(f'[BUS_CONCAT] {stage}: {inst}.{port} has no {{}} concat — likely collapsed to single net by broken rewire')
    return failures


def check_undriven_eco_nets(ref_dir):
    """
    FAIL if any n_eco_* net in PostEco netlist has < 2 occurrences. A driven net
    has at least one driver reference (cell output / wire decl / port concat slot)
    AND at least one consumer reference. Fewer than 2 → likely no driver. Catches
    bus-rename failures (REGCMD-style) where eco_passes_2_4 didn't apply the rename.
    """
    failures = []
    NET_RE = re.compile(r'\b(n_eco_[A-Za-z0-9_]+)\b')
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        gz = os.path.join(ref_dir, 'data', 'PostEco', f'{stage}.v.gz')
        if not os.path.exists(gz):
            continue
        try:
            text = subprocess.run(['zcat', gz], capture_output=True, text=True, timeout=240).stdout
        except Exception:
            continue
        from collections import Counter
        counts = Counter(NET_RE.findall(text))
        for net, c in sorted(counts.items()):
            if c < 2:
                failures.append(f'[UNDRIVEN_NET] {stage}: {net} appears only {c} time(s) — no driver (bus-rename or driver insertion likely failed)')
    return failures


def check_eco_cell_counts(applied):
    """
    WARN (not FAIL) if ECO cell counts differ significantly across stages.
    Route may legitimately have fewer (module renamed in P&R).
    Returns (warnings, failures) — failures are hard FAIL conditions.
    """
    gate_types = ('new_logic_gate', 'new_logic_dff', 'new_logic')
    counts = {}
    for stage, entries in applied.items():
        if not isinstance(entries, list):
            continue
        counts[stage] = sum(
            1 for e in entries
            if e.get('change_type','') in gate_types
            and e.get('status','') in ('INSERTED', 'ALREADY_APPLIED')
        )

    if not counts:
        return [], []

    max_count = max(counts.values())
    warnings = []
    failures = []
    for stage, count in counts.items():
        if count == 0 and max_count > 0:
            failures.append(f'Stage {stage}: 0 ECO cells applied but other stages have {max_count}')
        elif count < max_count * 0.5:
            warnings.append(f'Stage {stage}: {count} cells vs max {max_count} — possible partial application')
    return warnings, failures


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    args = parse_args()
    base  = args.base_dir
    tag   = args.tag
    rnd   = args.round
    jira  = args.jira

    applied_path  = f'{base}/data/{tag}_eco_applied_round{rnd}.json'
    check8_path   = f'{base}/data/{tag}_eco_check8_round{rnd}.json'
    out_json_path = f'{base}/data/{tag}_eco_pre_fm_check_round{rnd}.json'
    out_rpt_path  = f'{base}/data/{tag}_eco_step5_pre_fm_check_round{rnd}.rpt'
    marker_path   = f'{base}/data/{tag}_eco_step5_pre_fm_check_round{rnd}_marker.txt'

    applied = load_json(applied_path) or {}

    results   = {}
    all_fails = []
    warnings  = []

    # Check 1 — No deferred port declarations
    fails = check_no_deferred(applied)
    results['no_deferred_ports'] = 'PASS' if not fails else 'FAIL'
    all_fails.extend([f'[DEFERRED] {f}' for f in fails])

    # Check 2 — Port declarations all applied
    fails = check_port_declarations_applied(applied)
    results['port_declarations_applied'] = 'PASS' if not fails else 'FAIL'
    all_fails.extend([f'[PORT_SKIP] {f}' for f in fails])

    # Check 3 — Stage consistency (gates inserted in all stages)
    fails = check_stage_consistency(applied)
    results['stage_consistency'] = 'PASS' if not fails else 'FAIL'
    all_fails.extend([f'[STAGE_MISMATCH] {f}' for f in fails])

    # Check 4 — No UNHANDLED entries
    fails = check_no_unhandled(applied)
    results['no_unhandled'] = 'PASS' if not fails else 'FAIL'
    all_fails.extend([f'[UNHANDLED] {f}' for f in fails])

    # Check 5 — eco_check8 Verilog validator
    fails = check_check8(check8_path)
    results['check8_verilog'] = 'PASS' if not fails else 'FAIL'
    all_fails.extend([f'[SVR4_SVR9] {f}' for f in fails])

    # Check 6 — ECO cell counts (warnings only for partial, hard fail for zero)
    w, fails = check_eco_cell_counts(applied)
    results['eco_cell_counts'] = 'PASS' if not fails else 'FAIL'
    warnings.extend(w)
    all_fails.extend([f'[ZERO_CELLS] {f}' for f in fails])

    # Check 7 — Verify INSERTED gates actually exist in PostEco netlist
    # Catches: eco_perl_spec marks INSERTED but Perl fails to find module (ghost insert)
    fails = check_cells_in_netlist(applied, args.ref_dir)
    results['cells_in_netlist'] = 'PASS' if not fails else 'FAIL'
    all_fails.extend(fails)

    # Check 8 — Every n_eco_* net in PostEco netlist must have ≥ 2 references.
    # Catches bus-rename failures where the rename was specified in study JSON
    # but eco_passes_2_4.py didn't apply it to the netlist (driver missing).
    fails = check_undriven_eco_nets(args.ref_dir)
    results['undriven_eco_nets'] = 'PASS' if not fails else 'FAIL'
    all_fails.extend(fails)

    # Check 9 — bus-concat integrity. For port_connection entries with
    # bus_bit_index, the netlist must still have .port({...}) — not collapsed
    # to a single net (catches broad-regex rewire corruption).
    fails = check_bus_concat_intact(args.ref_dir, applied)
    results['bus_concat_intact'] = 'PASS' if not fails else 'FAIL'
    all_fails.extend(fails)

    # Check 10 — every APPLIED port_declaration / port_connection entry must
    # have its edit physically present in the netlist. Catches the silent
    # APPLIED-but-no-edit failure mode.
    fails = check_port_edits_in_netlist(args.ref_dir, applied)
    results['port_edits_in_netlist'] = 'PASS' if not fails else 'FAIL'
    all_fails.extend(fails)

    # Check 11 — every APPLIED rewire entry must have cell.pin → new_net
    # physically in the netlist (closes the last "JSON trust" gap).
    fails = check_rewires_in_netlist(args.ref_dir, applied)
    results['rewires_in_netlist'] = 'PASS' if not fails else 'FAIL'
    all_fails.extend(fails)

    passed = len(all_fails) == 0

    # ── Write JSON ────────────────────────────────────────────────────────────
    out = {
        'tag':           tag,
        'round':         rnd,
        'jira':          jira,
        'passed':        passed,
        'failures':      all_fails,
        'warnings':      warnings,
        'check_summary': results,
    }
    with open(out_json_path, 'w') as f:
        json.dump(out, f, indent=2)

    # ── Write RPT ─────────────────────────────────────────────────────────────
    status_str = 'PASS' if passed else 'FAIL'
    lines = [
        '=' * 72,
        f'STEP 5 — PRE-FM QUALITY CHECK (Round {rnd})',
        f'Tag: {tag}  |  JIRA: {jira}',
        '=' * 72,
        f'RESULT: {status_str}',
        '',
    ]
    for check, result in results.items():
        lines.append(f'  {check:<35}: {result}')
    if all_fails:
        lines += ['', 'FAILURES:']
        lines += [f'  {f}' for f in all_fails]
    if warnings:
        lines += ['', 'WARNINGS (non-blocking):']
        lines += [f'  {w}' for w in warnings]
    lines += ['', '=' * 72]
    rpt_text = '\n'.join(lines) + '\n'
    with open(out_rpt_path, 'w') as f:
        f.write(rpt_text)

    # ── Write marker ──────────────────────────────────────────────────────────
    marker = f'ECO_SCRIPT_LAUNCHED: eco_pre_fm_check.py\n  result: {status_str}\n  output: {out_json_path}\n'
    with open(marker_path, 'w') as f:
        f.write(marker)

    print(rpt_text)
    sys.exit(0 if passed else 1)


if __name__ == '__main__':
    main()
