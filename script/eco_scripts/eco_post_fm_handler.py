#!/usr/bin/env python3
"""
eco_post_fm_handler.py — Deterministic post-Step-6 wrapper.

Auto-fix-and-resubmit loop for FM ABORT cases that have known netlist-patch
fixes (e.g., duplicate wire decl). Replaces the wasteful "spawn next
ROUND_ORCHESTRATOR for ABORT recovery" pattern with an in-process loop:

  Step 6 ABORT → classify → patch netlist → resubmit FM → loop (max 3)

Only escalates to ROUND_ORCHESTRATOR when:
  - The abort type isn't auto-fixable (ABORT_LINK, ABORT_SVF, ABORT_OTHER, or
    ABORT_NETLIST with unknown pattern)
  - OR all 3 in-process fix attempts exhausted

This removes:
  - 5-15 min orchestrator-spawn overhead per ABORT recovery cycle
  - Agent context-pressure failure mode (orchestrator dropping recovery
    silently — see runs 20260511083831 and 20260511201004)
  - Wasted full FM cycles waiting for an agent that exits without spawning

Behavior contract:
  - status == "PASS"  → exit 0 (downstream FINAL_ORCHESTRATOR takes over)
  - status == "FAIL"  → exit 0 (ROUND_ORCHESTRATOR Mode A-H analysis required)
  - status == "ABORT":
      classifier runs → if auto-fixable → apply patch → resubmit FM → loop
      otherwise → write handoff with FM_FAILED and escalate

Usage:
    python3 eco_post_fm_handler.py \\
        --fm-verify  data/<TAG>_eco_fm_verify.json \\
        --logs-dir   <REF_DIR>/logs \\
        --tag        <TAG> \\
        --round      1 \\
        --base-dir   <BASE_DIR> \\
        --ref-dir    <REF_DIR> \\
        --tile       <TILE> \\
        --jira       <JIRA> \\
        --handoff    <BASE_DIR>/data/<TAG>_round_handoff.json \\
        --max-attempts 3
"""
import argparse, gzip, json, os, re, subprocess, sys
from pathlib import Path

# Auto-fixable abort patterns. Each entry maps a pattern_kind from
# eco_extract_fm_abort_cause.py to a fix function.
AUTO_FIXABLE_PATTERNS = {
    'duplicate_wire_decl',
    'verilog_parse_error',  # often co-occurs with duplicate_wire_decl
}


def _read_gz(path):
    with gzip.open(path, 'rt') as f:
        return f.read()


def _write_gz(path, text):
    """Write gzip atomically (write to .tmp then rename)."""
    tmp = path + '.tmp'
    with gzip.open(tmp, 'wt') as f:
        f.write(text)
    os.replace(tmp, path)


def fix_duplicate_wire_decl(stage_path, dup_net_name):
    """Remove duplicate `wire <dup_net_name> ;` lines in the netlist.

    Strategy: in each module body, keep the FIRST `wire <name> ;` decl, delete
    every subsequent identical decl. Order matters (Verilog/FM treats first as
    canonical, later as duplicate). Also handles the implicit-wire-conflict
    case: if `.PORT(<name>)` appears BEFORE `wire <name> ;` in same module,
    delete the explicit decl entirely (Verilog auto-creates the wire from the
    port connection, explicit decl is the duplicate).

    Returns count of lines removed.
    """
    if not os.path.exists(stage_path):
        return 0
    text = _read_gz(stage_path)
    lines = text.split('\n')
    decl_re = re.compile(rf'^\s*wire\s+(?:\[[^\]]+\]\s+)?{re.escape(dup_net_name)}\s*;')
    port_re = re.compile(rf'\.\s*\w+\s*\(\s*{re.escape(dup_net_name)}\s*\)')
    # Walk module-by-module
    modified = []
    in_module = False
    cur_mod_start = None
    cur_decl_seen = False
    cur_port_use_first_idx = -1
    cur_decl_lines = []  # list of line indices with the dup decl
    out_lines = []
    for idx, ln in enumerate(lines):
        if re.match(r'^module\s+', ln):
            in_module = True
            cur_decl_seen = False
            cur_port_use_first_idx = -1
            cur_decl_lines = []
            cur_mod_start = idx
            out_lines.append(ln)
            continue
        if re.match(r'^\s*endmodule', ln):
            # Decide which decls to remove
            # Case A: implicit-wire-conflict (port-use comes before decl)
            #   → remove ALL explicit decls
            # Case B: pure duplicate (>1 explicit decl)
            #   → keep first, remove rest
            kill_idxs = set()
            if cur_port_use_first_idx >= 0 and cur_decl_lines:
                first_decl_idx = cur_decl_lines[0]
                if cur_port_use_first_idx < first_decl_idx:
                    # implicit-wire-conflict — remove ALL explicit decls
                    kill_idxs = set(cur_decl_lines)
                else:
                    # decl is canonical; remove only later duplicates
                    kill_idxs = set(cur_decl_lines[1:])
            elif len(cur_decl_lines) > 1:
                kill_idxs = set(cur_decl_lines[1:])
            if kill_idxs:
                # Reconstruct module body without killed lines
                new_body = [out_lines[i] for i in range(cur_mod_start + 1, len(out_lines))
                            if (cur_mod_start + 1 + (i - cur_mod_start - 1)) not in kill_idxs]
                # Actually simpler: walk out_lines and skip killed indices that
                # were in original lines positions.
                # Translate kill_idxs (which are indices into `lines`) to
                # equivalent positions in out_lines (which mirrored lines so far)
                # Since out_lines == lines[cur_mod_start..idx-1], indices align.
                rebuilt = [out_lines[0:cur_mod_start + 1]]  # everything before module
                rebuilt = list(out_lines)  # full so far
                # Remove from rebuilt those whose original index is in kill_idxs
                # out_lines has been built 1:1 with lines so far (no removals yet)
                # so rebuilt[i] corresponds to lines[i].
                rebuilt = [rebuilt[i] for i in range(len(rebuilt)) if i not in kill_idxs]
                out_lines = rebuilt
                modified.extend(sorted(kill_idxs))
            in_module = False
            out_lines.append(ln)
            continue
        if in_module:
            if decl_re.match(ln):
                cur_decl_lines.append(idx)
            elif port_re.search(ln):
                if cur_port_use_first_idx < 0:
                    cur_port_use_first_idx = idx
        out_lines.append(ln)
    if modified:
        _write_gz(stage_path, '\n'.join(out_lines))
    return len(modified)


def apply_fixes(classifications, ref_dir):
    """Apply auto-fixes for each classification entry. Returns dict of
    {target: [list of (pattern_kind, fix_summary)]}."""
    applied = {}
    for c in classifications:
        kind = c.get('pattern_kind', '')
        target = c.get('target', '')
        match = c.get('match', '')
        if kind == 'duplicate_wire_decl' and match:
            # Determine which stage this target's netlist is. Both REF and IMPL
            # comparisons share the same PostEco netlists, so apply to all 3
            # stages (the duplicate is the same in all stages where applier ran).
            removed_total = 0
            for stage in ('Synthesize', 'PrePlace', 'Route'):
                gz = os.path.join(ref_dir, 'data', 'PostEco', f'{stage}.v.gz')
                removed = fix_duplicate_wire_decl(gz, match)
                if removed:
                    removed_total += removed
                    applied.setdefault(target, []).append(
                        (kind, f'{stage}: removed {removed} duplicate `wire {match} ;` line(s)'))
        elif kind == 'verilog_parse_error':
            # Often a downstream symptom of duplicate_wire_decl above; no
            # additional fix needed here. The duplicate_wire_decl fix removes
            # the underlying cause.
            pass
    return applied


def write_handoff(handoff_path, base_dict, status, loop_verdict, extra=None):
    """Atomically merge into existing handoff (or create new)."""
    out = {}
    if os.path.exists(handoff_path):
        try:
            out = json.loads(Path(handoff_path).read_text())
        except Exception:
            out = {}
    out.update(base_dict)
    out['status'] = status
    out['loop_verdict'] = loop_verdict
    if extra:
        out.update(extra)
    Path(handoff_path).write_text(json.dumps(out, indent=2))


def resubmit_fm(base_dir, ref_dir, tile, log_msg=''):
    """Re-submit FM via genie_cli. Returns (eco_fm_tag, ok)."""
    cmd = ['python3', f'{base_dir}/script/genie_cli.py',
           '-i', f'run post-eco formality at {ref_dir} for {tile}',
           '--execute', '--xterm']
    print(f'[eco_post_fm_handler] resubmit_fm: {" ".join(cmd)}{log_msg}', flush=True)
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=300, cwd=base_dir)
        # Parse the new tag from CLI output (format: "Tag: <14digits>")
        m = re.search(r'Tag:\s*(\d{14})', r.stdout)
        return (m.group(1) if m else None, r.returncode == 0)
    except Exception as e:
        print(f'[eco_post_fm_handler] resubmit_fm ERROR: {e}', file=sys.stderr)
        return (None, False)


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('--fm-verify',  required=True)
    p.add_argument('--logs-dir',   required=True)
    p.add_argument('--tag',        required=True)
    p.add_argument('--round',      type=int, default=1)
    p.add_argument('--base-dir',   required=True)
    p.add_argument('--ref-dir',    required=True)
    p.add_argument('--tile',       required=True)
    p.add_argument('--jira',       required=True)
    p.add_argument('--handoff',    required=True,
                   help='Path to <TAG>_round_handoff.json — written/merged')
    p.add_argument('--max-attempts', type=int, default=3,
                   help='Max in-process auto-fix-and-resubmit attempts per round (default 3)')
    p.add_argument('--no-resubmit', action='store_true',
                   help='Apply fix only, do NOT resubmit FM (for testing)')
    args = p.parse_args()

    base_handoff = {
        'tag':        args.tag,
        'ref_dir':    args.ref_dir,
        'tile':       args.tile,
        'jira':       args.jira,
        'base_dir':   args.base_dir,
        'round':      args.round,
    }

    # Load fm_verify.json
    try:
        fm = json.loads(Path(args.fm_verify).read_text())
    except Exception as e:
        print(f'FAIL: cannot read fm_verify {args.fm_verify}: {e}', file=sys.stderr)
        write_handoff(args.handoff, base_handoff, status='FM_VERIFY_MISSING',
                      loop_verdict='ESCALATE')
        return 1

    status = fm.get('status', 'UNKNOWN')
    if status == 'PASS':
        write_handoff(args.handoff, base_handoff, status='FM_PASSED',
                      loop_verdict='CONVERGED')
        print(f'[eco_post_fm_handler] FM PASSED — handoff written, ready for FINAL_ORCHESTRATOR')
        return 0
    if status == 'FAIL':
        write_handoff(args.handoff, base_handoff, status='FM_FAILED',
                      loop_verdict='ADVANCE_NEXT_ROUND')
        print(f'[eco_post_fm_handler] FM FAILED (logical mismatch) — handoff written, '
              f'ROUND_ORCHESTRATOR Mode A-H analysis required')
        return 0
    if status != 'ABORT':
        write_handoff(args.handoff, base_handoff, status='FM_UNKNOWN_STATUS',
                      loop_verdict='ESCALATE')
        print(f'[eco_post_fm_handler] unknown FM status {status!r} — escalating')
        return 1

    # status == 'ABORT' — try in-process classify-and-fix loop
    # Track attempts in a sidecar file so we don't infinite-loop across
    # post-FM-handler invocations
    attempt_state = f'{args.base_dir}/data/{args.tag}_post_fm_handler_attempts.json'
    attempts = 0
    if os.path.exists(attempt_state):
        try:
            attempts = json.loads(Path(attempt_state).read_text()).get('attempts', 0)
        except Exception:
            pass
    if attempts >= args.max_attempts:
        write_handoff(args.handoff, base_handoff, status='FM_FAILED',
                      loop_verdict='ADVANCE_NEXT_ROUND',
                      extra={'auto_fix_attempts_exhausted': attempts,
                             'note': f'{attempts} auto-fix attempts exhausted; escalate to ROUND_ORCHESTRATOR'})
        print(f'[eco_post_fm_handler] {attempts} attempts exhausted — escalating')
        return 1

    # Invoke classifier
    classifier = f'{args.base_dir}/script/eco_scripts/eco_extract_fm_abort_cause.py'
    abort_class = f'{args.base_dir}/data/{args.tag}_eco_fm_abort_classification.json'
    print(f'[eco_post_fm_handler] ABORT detected (attempt {attempts+1}/{args.max_attempts}); '
          f'invoking classifier...', flush=True)
    cls_cmd = ['python3', classifier,
               '--fm-verify', args.fm_verify,
               '--logs-dir',  args.logs_dir,
               '--tag',       args.tag,
               '--round',     str(args.round),
               '--output',    abort_class,
               '--update-round-handoff', args.handoff]
    cls_r = subprocess.run(cls_cmd, capture_output=True, text=True, timeout=120)
    print(cls_r.stdout)
    if cls_r.returncode != 0:
        print(f'[eco_post_fm_handler] classifier exit={cls_r.returncode}; escalating', file=sys.stderr)
        return 1

    cls_data = json.loads(Path(abort_class).read_text())
    primary = cls_data.get('primary_abort_type', 'ABORT_OTHER')
    classifications = cls_data.get('classifications', [])

    # Decide if any classification is auto-fixable
    fixable = [c for c in classifications if c.get('pattern_kind') in AUTO_FIXABLE_PATTERNS]
    if not fixable:
        # No known auto-fix pattern — escalate to ROUND_ORCHESTRATOR
        write_handoff(args.handoff, base_handoff, status='FM_FAILED',
                      loop_verdict='RERUN_SAME_ROUND',
                      extra={'auto_fixable': False, 'primary_abort_type': primary,
                             'note': 'No auto-fixable pattern; ROUND_ORCHESTRATOR Step 6d analyzer required'})
        print(f'[eco_post_fm_handler] primary={primary} not auto-fixable; escalating to ROUND_ORCHESTRATOR')
        return 1

    # Apply fixes
    applied = apply_fixes(fixable, args.ref_dir)
    if not applied:
        write_handoff(args.handoff, base_handoff, status='FM_FAILED',
                      loop_verdict='RERUN_SAME_ROUND',
                      extra={'auto_fixable': True, 'fix_applied': False,
                             'note': 'Auto-fix patterns matched but no lines actually removed; escalate'})
        print(f'[eco_post_fm_handler] auto-fix matched but no edits applied; escalating')
        return 1

    print(f'[eco_post_fm_handler] AUTO-FIXES APPLIED:')
    for tgt, fixes in applied.items():
        for kind, summary in fixes:
            print(f'  [{tgt}] {kind}: {summary}')

    # Increment attempt counter
    Path(attempt_state).write_text(json.dumps({'attempts': attempts + 1,
                                                'last_primary_abort_type': primary,
                                                'fixes_applied': {k: [s for _, s in v]
                                                                 for k, v in applied.items()}},
                                                indent=2))

    if args.no_resubmit:
        print(f'[eco_post_fm_handler] --no-resubmit set; fix applied but FM not resubmitted')
        return 0

    # Re-submit FM (this triggers another post_eco_formality.csh which will
    # call this wrapper again with a new fm_verify.json — recursive loop until
    # PASS, real FAIL, max attempts, or non-auto-fixable abort)
    new_fm_tag, ok = resubmit_fm(args.base_dir, args.ref_dir, args.tile,
                                 log_msg=f' (round {args.round} attempt {attempts+2}/{args.max_attempts})')
    if not ok or not new_fm_tag:
        print(f'[eco_post_fm_handler] FM resubmission FAILED — escalating', file=sys.stderr)
        write_handoff(args.handoff, base_handoff, status='FM_FAILED',
                      loop_verdict='ESCALATE',
                      extra={'fix_applied_then_resubmit_failed': True})
        return 1
    write_handoff(args.handoff, base_handoff, status='FM_RESUBMITTED',
                  loop_verdict='RERUN_SAME_ROUND',
                  extra={'auto_fix_attempt': attempts + 1,
                         'new_eco_fm_tag': new_fm_tag,
                         'fixes_applied': {k: [s for _, s in v] for k, v in applied.items()}})
    print(f'[eco_post_fm_handler] FM resubmitted as tag {new_fm_tag} — wait for it to complete')
    return 0


if __name__ == '__main__':
    sys.exit(main())
