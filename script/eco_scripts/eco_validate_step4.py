#!/usr/bin/env python3
"""
eco_validate_step4.py — Validate eco_applied_round<N>.json completeness before Step 5.

Checks that eco_applier produced complete, valid output with no silently-skipped
critical entries that Step 5 and FM would miss.

Usage:
    python3 script/eco_scripts/eco_validate_step4.py \
        --applied  data/<TAG>_eco_applied_round<N>.json \
        --study    data/<TAG>_eco_preeco_study.json \
        --ref-dir  <REF_DIR> \
        --tag      <TAG> \
        --round    <N> \
        --output   data/<TAG>_eco_validate_step4_round<N>.json

Exit: 0 = PASS, 1 = FAIL
"""

import argparse, gzip, json, re, subprocess, sys
from pathlib import Path


# ── Helpers ──────────────────────────────────────────────────────────────────

# Verilog wire decls must use a flat identifier — bracket form `wire X[N];` is
# illegal (FM rejects with SVR-4 + SVR-64 + FM-599). Same check exists in
# eco_pre_fm_check.py Check 22; this is the post-apply / pre-Step-5 mirror.
_BAD_WIRE_DECL = re.compile(r'^\s*(wire|tri|wand|wor|reg)\s+(\w+)\[(\d+)\]\s*;\s*$')


def lint_postEco_grammar(ref_dir):
    """Walk each PostEco netlist; return list of (file, line, kind, text) for
    every illegal `wire <name>[<bit>] ;` decl. The applier's auto-sanitize in
    eco_perl_spec.py SHOULD have flattened these — this validator is the
    safety net catching anything that slipped through."""
    failures = []
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        path = Path(ref_dir) / 'data' / 'PostEco' / f'{stage}.v.gz'
        if not path.is_file():
            continue
        try:
            with gzip.open(path, 'rt', errors='replace') as f:
                for ln_idx, line in enumerate(f, start=1):
                    bm = _BAD_WIRE_DECL.match(line)
                    if bm:
                        kind, name, bit = bm.group(1), bm.group(2), bm.group(3)
                        failures.append({
                            'stage': stage, 'line': ln_idx,
                            'kind': kind, 'name': name, 'bit': bit,
                            'text': line.rstrip(),
                            'fix_hint': f'flatten to `{kind} {name}_{bit}_ ;`',
                        })
        except Exception as e:
            failures.append({'stage': stage, 'note': f'cannot read: {e}'})
    return failures


def md5(path):
    """Return md5 hash of file, or None if command fails (file missing or error)."""
    try:
        r = subprocess.run(f'md5sum {path}', shell=True, capture_output=True, text=True)
        parts = r.stdout.split()
        return parts[0] if parts else None
    except Exception:
        return None


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--applied',  required=True)
    p.add_argument('--study',    required=True)
    p.add_argument('--ref-dir',  required=True)
    p.add_argument('--tag',      required=True)
    p.add_argument('--round',    required=True, type=int)
    p.add_argument('--output',   required=True)
    args = p.parse_args()

    applied = json.loads(Path(args.applied).read_text())
    study   = json.loads(Path(args.study).read_text())
    issues  = []

    summary = applied.get('summary', {})

    # ── 1. No VERIFY_FAILED entries ──────────────────────────────────────────
    vf = summary.get('verify_failed', 0)
    if vf > 0:
        issues.append(f"CRITICAL: {vf} VERIFY_FAILED entries — PostEco netlist may be corrupted; do NOT submit to FM")

    # ── 2. eco_perl_spec markers exist for all 3 stages ────────────────────
    data_dir = Path(args.applied).parent
    tag = args.tag
    for stage in ['Synthesize', 'PrePlace', 'Route']:
        m = data_dir / f"{tag}_eco_perl_spec_{stage}_marker.txt"
        if not m.exists():
            issues.append(f"HIGH: eco_perl_spec_{stage}_marker.txt missing — eco_perl_spec.py did not run for {stage}")

    # ── 3. PostEco actually changed from PreEco (for stages with insertions) ─
    for stage in ['Synthesize', 'PrePlace', 'Route']:
        stage_entries = applied.get(stage, [])
        has_changes = any(e.get('status') in ('APPLIED','INSERTED') for e in stage_entries)
        if has_changes:
            pre = f"{args.ref_dir}/data/PreEco/{stage}.v.gz"
            post = f"{args.ref_dir}/data/PostEco/{stage}.v.gz"
            pre_md5  = md5(pre)
            post_md5 = md5(post)
            if pre_md5 is None or post_md5 is None:
                issues.append(f"HIGH: {stage} MD5 check failed — PreEco or PostEco file missing/unreadable")
            elif pre_md5 == post_md5:
                issues.append(f"CRITICAL: {stage} PostEco MD5 unchanged from PreEco despite {sum(1 for e in stage_entries if e.get('status') in ('APPLIED','INSERTED'))} applied changes — writes may have failed")

    # ── 4. Every INSERTED entry has instance_name populated ─────────────────
    for stage in ['Synthesize', 'PrePlace', 'Route']:
        for e in applied.get(stage, []):
            if e.get('status') == 'INSERTED':
                if not (e.get('instance_name') or e.get('cell_name') or e.get('signal_name')):
                    issues.append(f"MEDIUM: INSERTED entry in {stage} has no identifier (instance_name/cell_name/signal_name) — RPT will show '?'")

    # ── 5. All confirmed study entries are accounted for ─────────────────────
    for stage in ['Synthesize']:
        study_confirmed = {e.get('instance_name','') or e.get('cell_name','') or e.get('signal_name','')
                          for e in study.get(stage, []) if e.get('confirmed', True) and e.get('change_type') != 'remove_wire_decl'}
        applied_names = {e.get('instance_name','') or e.get('cell_name','') or e.get('signal_name','')
                        for e in applied.get(stage, [])}
        unaccounted = study_confirmed - applied_names - {'', '?'}
        if unaccounted:
            issues.append(f"HIGH: {stage} study entries not found in applied JSON: {list(unaccounted)[:5]} — eco_applier skipped them silently")

    # ── 6. Backup files exist for stages with changes ────────────────────────
    for stage in ['Synthesize', 'PrePlace', 'Route']:
        bak = f"{args.ref_dir}/data/PostEco/{stage}.v.gz.bak_{tag}_round{args.round}"
        if applied.get(stage) and not Path(bak).exists():
            issues.append(f"MEDIUM: Backup {stage}.v.gz.bak_{tag}_round{args.round} not found — revert protection missing")

    # ── 7. GAP-2 enforcement: bus_rename APPLIED entries should carry cleanup
    # tags ([removed_orphan] / [added_decl]) when the old net was an UNCONNECTED.
    # The applier prints these in the status `reason` string — verify presence.
    for stage in ['Synthesize', 'PrePlace', 'Route']:
        for e in applied.get(stage, []):
            if e.get('status') != 'APPLIED':
                continue
            reason = e.get('reason', '')
            if 'bus_rename' not in reason or 'UNCONNECTED' not in reason:
                continue
            if '[' not in reason or ('removed_orphan' not in reason and 'added_decl' not in reason):
                inst = e.get('instance_name') or e.get('cell_name') or '?'
                issues.append(
                    f"HIGH: GAP-2 — {stage} bus_rename on {inst} renamed an UNCONNECTED net but "
                    f"reason text shows no [removed_orphan]/[added_decl] cleanup tag. "
                    f"Orphan wire decl may still exist or new wire missing explicit decl. reason={reason!r}")

    # ── 8. GAP-3 enforcement: bridge_port_role entries MUST be SKIPPED in Synth.
    # Studier marks bridge plumbing entries with bridge_port_role; applier
    # skips them when stage==Synthesize. Audit by cross-referencing study JSON.
    bridge_role_insts = set()
    for s in ('Synthesize', 'PrePlace', 'Route'):
        for e in study.get(s, []):
            if e.get('bridge_port_role'):
                key = e.get('instance_name') or e.get('signal_name') or e.get('cell_name', '')
                if key:
                    bridge_role_insts.add(key)
    for e in applied.get('Synthesize', []):
        key = e.get('instance_name') or e.get('signal_name') or e.get('cell_name', '')
        if key in bridge_role_insts and e.get('status') in ('APPLIED', 'INSERTED'):
            issues.append(
                f"HIGH: GAP-3 — Synthesize entry {key!r} has bridge_port_role in study but was "
                f"APPLIED/INSERTED in Synth (expected SKIPPED — Synth uses constant_zero, no bridge plumbing).")

    # ── 9. Verilog grammar lint on PostEco wire decls ────────────────────────
    # Catches `wire <name>[<bit>] ;` that slipped past the applier's
    # auto-sanitize. Run 20260512070625 root cause #2: studier emitted
    # `named_net: REG_UmcCfgEco[1]` and applier passed it through verbatim.
    # eco_perl_spec.py now auto-converts to flat-net form; this is the safety
    # net catching anything that bypasses the sanitizer (manual edits,
    # corruption, future code paths).
    grammar_failures = lint_postEco_grammar(args.ref_dir)
    for f in grammar_failures:
        if 'note' in f:
            issues.append(f"MEDIUM: GRAMMAR-LINT — {f['stage']}: {f['note']}")
        else:
            issues.append(
                f"CRITICAL: GRAMMAR-LINT — {f['stage']}:{f['line']} illegal wire decl "
                f"`{f['text'].strip()}`. {f['fix_hint']}. FM will reject with "
                f"SVR-4 + SVR-64 + FM-599 → ABORT in PreVerify. Likely cause: "
                f"applier auto-sanitize bypassed OR netlist manually edited.")

    # ── Result ───────────────────────────────────────────────────────────────
    passed = len(issues) == 0
    result = {'tag': tag, 'round': args.round, 'passed': passed, 'issues': issues}
    Path(args.output).write_text(json.dumps(result, indent=2))

    marker_txt = (
        f"ECO_SCRIPT_LAUNCHED: eco_validate_step4.py\n"
        f"  round:  {args.round}\n"
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
        print("\nStep 4 output COMPLETE — all checks passed.")

    Path(args.output.replace('.json','_marker.txt')).write_text(marker_txt + '\n')
    return 0 if passed else 1


if __name__ == '__main__':
    sys.exit(main())
