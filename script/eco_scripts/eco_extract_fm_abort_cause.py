#!/usr/bin/env python3
"""
eco_extract_fm_abort_cause.py — Deterministic FM ABORT classification.

Step 6 (eco_fm_runner) writes eco_fm_verify.json with `status: "ABORT"` when
FM died before comparison. Today the orchestrator agent is supposed to read
the raw FM logs, classify the abort, write round_handoff.json with a
remediation hint, and spawn ROUND_ORCHESTRATOR. In practice — after a 3+ hour
FM wait — the orchestrator agent often runs close to its context limit and
exits without spawning the next round.

This script removes the agent dependency: invoke it unconditionally after
Step 6 and it produces the deterministic verdict, classified abort type,
extracted log excerpt, and a remediation hint, written to round_handoff.json.

Abort taxonomy (matches eco_fm_pattern_library.md §B-ABORT-1..4):
  ABORT_NETLIST — Verilog parse failure (FM-599, FM-001, "Duplicate wire/...")
  ABORT_LINK    — Linking/elaboration failure (FM-036 unknown net, FE-LINK-7,
                  port mismatch)
  ABORT_SVF     — SVF guidance error (CMD-005, CMD-010)
  ABORT_OTHER   — Anything else (license, segfault, OOM)

Usage:
    python3 eco_extract_fm_abort_cause.py \\
        --fm-verify   data/<TAG>_eco_fm_verify.json \\
        --logs-dir    <REF_DIR>/logs \\
        --tag         <TAG> \\
        --round       1 \\
        --output      data/<TAG>_eco_fm_abort_classification.json \\
        [--update-round-handoff data/<TAG>_round_handoff.json]
"""
import argparse, gzip, json, os, re, sys
from pathlib import Path


# Abort pattern library — pattern → (abort_type, severity, suggested_action)
ABORT_PATTERNS = [
    # ABORT_NETLIST — Verilog parse / wire decl errors
    (re.compile(r"Duplicate wire/tri/wand/wor declaration for ['\"]([^'\"]+)['\"]"),
     'ABORT_NETLIST',
     'duplicate_wire_decl',
     "Duplicate wire declaration in PostEco netlist for net {match}. Likely "
     "applier inserted a wire decl for a net that already exists in the "
     "netlist. Action: locate the duplicate (Step 5 Check 19 fires on this) "
     "and delete one occurrence; OR fix the applier pass that emitted the "
     "extra decl."),
    (re.compile(r"FM-599"),
     'ABORT_NETLIST',
     'verilog_parse_error',
     "FM-599 generic Verilog parse error. Look for accompanying error message "
     "(often `Duplicate wire`, `Syntax error`, or `Module redefinition`)."),
    (re.compile(r"FM-001"),
     'ABORT_NETLIST',
     'verilog_read_failed',
     "FM-001 Verilog read failure. The read_verilog/read_sverilog command "
     "ignored the file due to errors — check for syntax issues earlier in "
     "the log."),
    (re.compile(r"Module redefinition"),
     'ABORT_NETLIST',
     'module_redefinition',
     "Module redefined — applier likely inserted a duplicate module body. "
     "Revert the duplicate and re-apply."),
    (re.compile(r"^Error:.*[Ss]yntax error", re.MULTILINE),
     'ABORT_NETLIST',
     'verilog_syntax_error',
     "Verilog syntax error from applier output. Check the line referenced in "
     "the FM error message."),
    # ABORT_LINK — Elaboration / port matching failures
    (re.compile(r"FE-LINK-7"),
     'ABORT_LINK',
     'link_failure',
     "FE-LINK-7 elaboration failure. Usually missing port_declaration or "
     "wrong cell pin name. Check Step 5 Check 16 (missing_output_port_decls) "
     "and Check 15 (eco_output_pin_names) outputs."),
    (re.compile(r"Cannot link cell ['\"]?([^'\"]+?)['\"]? to its reference design ['\"]?([^'\"]+?)['\"]?\.\s*\(FE-LINK-2\)"),
     'ABORT_LINK',
     'cell_type_not_in_library',
     "FE-LINK-2: cell {match!r} cannot be linked to its reference design — "
     "the cell type does NOT exist in the technology library FM is loading. "
     "Almost always caused by studier emitting a LOGICAL function name (NOR3, "
     "AND2, NAND2) instead of the TSMC short form (NR3, AN2, ND2). Check Step "
     "5 Check 21 (eco_cell_type_in_library) output for the suggested correction. "
     "Re-study with corrected cell_type that matches what's already in the PreEco "
     "netlist for that module."),
    (re.compile(r"Unresolved references detected during link\.\s*\(FM-234\)"),
     'ABORT_LINK',
     'unresolved_references',
     "FM-234: One or more cell instances reference designs/types not found in "
     "the loaded library. Almost always co-occurs with FE-LINK-2 — see those "
     "messages for the exact cell type(s) missing. Action: fix the cell_type "
     "names in eco_preeco_study.json (use TSMC short forms NR/AN/ND, not "
     "logical NOR/AND/NAND)."),
    (re.compile(r"Failed to set top design to ['\"]?([^'\"]+?)['\"]?\.?\s*\(FM-156\)"),
     'ABORT_LINK',
     'top_design_link_failure',
     "FM-156: cannot set top design {match!r} — usually a downstream symptom "
     "of FE-LINK-2 / FM-234 above. Fix the upstream link errors first; this "
     "will resolve automatically."),
    (re.compile(r"Unknown name: ['\"]([^'\"]+)['\"].*\(FM-036\)"),
     'ABORT_LINK',
     'unknown_net',
     "FM cannot find net {match}. Likely scope/instance path mismatch — "
     "Step 1 mode_s_anchor.fm_scope must use INSTANCE names, not module-type "
     "names. Re-run eco_pick_sibling.py with --tile-module."),
    (re.compile(r"Cannot link reference design"),
     'ABORT_LINK',
     'reference_link_failure',
     "Reference design failed to link. Check upstream Verilog read errors "
     "and ensure the SynRtl bundle is intact."),
    # ABORT_SVF — SVF guidance errors
    (re.compile(r"CMD-005"),
     'ABORT_SVF',
     'svf_command_error',
     "SVF guidance error CMD-005. Action: remove the offending SVF entry — "
     "see eco_fm_pattern_library.md §B-ABORT-2."),
    (re.compile(r"CMD-010"),
     'ABORT_SVF',
     'svf_command_error',
     "SVF guidance error CMD-010. Action: remove the offending SVF entry."),
    # ABORT_OTHER — environment/resource issues
    (re.compile(r"License.*not (?:available|granted|checked out)", re.IGNORECASE),
     'ABORT_OTHER',
     'license_unavailable',
     "FM license not granted. Re-run when license available; not a netlist "
     "issue."),
    (re.compile(r"Out of memory|OOM", re.IGNORECASE),
     'ABORT_OTHER',
     'out_of_memory',
     "FM ran out of memory. Try a larger RAM machine; not a netlist issue."),
    (re.compile(r"Segmentation fault"),
     'ABORT_OTHER',
     'fm_segfault',
     "FM segfaulted. Save the netlist and report to Synopsys; retry on a "
     "different host."),
]


def _read_log(path):
    """Read a possibly-gzipped log file as text, capping at 10MB to keep memory bounded."""
    try:
        if str(path).endswith('.gz'):
            with gzip.open(path, 'rt', errors='replace') as f:
                return f.read(10_000_000)
        with open(path, 'r', errors='replace') as f:
            return f.read(10_000_000)
    except Exception:
        return ''


def classify(log_text, target):
    """Return list of {pattern_kind, abort_type, severity, suggested_action,
    match_groups, log_excerpt} for every pattern that fires in the log."""
    hits = []
    for pat, abort_type, kind, action_template in ABORT_PATTERNS:
        for m in pat.finditer(log_text):
            # Extract a small context window around the match (3 lines before, 3 after)
            line_start = log_text.rfind('\n', 0, m.start()) + 1
            line_end   = log_text.find('\n', m.end())
            if line_end == -1:
                line_end = len(log_text)
            # Pull surrounding 3 lines on each side
            before_starts = [m.start()]
            cur = line_start
            for _ in range(3):
                prev_nl = log_text.rfind('\n', 0, cur - 1)
                if prev_nl == -1:
                    break
                before_starts.append(prev_nl + 1)
                cur = prev_nl + 1
            ex_start = before_starts[-1]
            after_ends = [line_end]
            cur = line_end
            for _ in range(3):
                next_nl = log_text.find('\n', cur + 1)
                if next_nl == -1:
                    break
                after_ends.append(next_nl)
                cur = next_nl
            ex_end = after_ends[-1]
            excerpt = log_text[ex_start:ex_end]
            match_str = m.group(1) if m.lastindex else ''
            hits.append({
                'target':           target,
                'abort_type':       abort_type,
                'pattern_kind':     kind,
                'match':            match_str,
                'suggested_action': action_template.format(match=match_str or '<see excerpt>'),
                'log_excerpt':      excerpt.strip()[:600],
            })
    # Dedupe by (target, abort_type, pattern_kind, match) — keep first
    seen = set(); uniq = []
    for h in hits:
        key = (h['target'], h['abort_type'], h['pattern_kind'], h['match'])
        if key in seen:
            continue
        seen.add(key); uniq.append(h)
    return uniq


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('--fm-verify',  required=True, help='eco_fm_verify.json from Step 6')
    p.add_argument('--logs-dir',   required=True, help='REF_DIR/logs containing FmEqv*.log.gz')
    p.add_argument('--tag',        required=True)
    p.add_argument('--round',      type=int, default=1)
    p.add_argument('--output',     required=True, help='Output JSON with classification')
    p.add_argument('--update-round-handoff', default='',
                   help='Optional path to round_handoff.json — script merges '
                        'remediation_hint + abort_classification into it.')
    args = p.parse_args()

    fm_verify = json.loads(Path(args.fm_verify).read_text())
    # Accept both schema variants: top-level `status` (legacy) OR `overall_status`
    # (current eco_fm_runner output). Also accept ABORT detected via per-target
    # status fields when neither top-level field is present.
    top_status = fm_verify.get('status') or fm_verify.get('overall_status') or ''
    if not top_status:
        # Look at per-target nested dicts — if ANY says ABORT, treat as ABORT
        for k, v in fm_verify.items():
            if isinstance(v, dict) and v.get('status') == 'ABORT':
                top_status = 'ABORT'
                break
    if top_status != 'ABORT':
        out = {
            'tag':                args.tag,
            'round':              args.round,
            'status':             top_status,
            'note':               'No ABORT detected — classification skipped.',
        }
        Path(args.output).write_text(json.dumps(out, indent=2))
        print(f'eco_extract_fm_abort_cause.py: status={top_status!r} '
              f'(no ABORT) — wrote {args.output}')
        return 0

    # Find the per-target log file. Convention: <REF_DIR>/logs/<TARGET>.log.gz
    # Per-target value can be EITHER a string ("ABORT") in legacy schema OR a
    # dict {"status": "ABORT", "abort_reason": "...", ...} in current schema.
    targets_status = {k: v for k, v in fm_verify.items()
                      if k.startswith(('FmEqv', 'fm_'))}
    classifications = []
    for target, value in targets_status.items():
        if not target.startswith('FmEqv'):
            continue
        # Normalize value to status string
        if isinstance(value, dict):
            status_str = value.get('status', '')
        else:
            status_str = str(value)
        if status_str != 'ABORT':
            continue
        log_path = os.path.join(args.logs_dir, f'{target}.log.gz')
        if not os.path.exists(log_path):
            log_path = os.path.join(args.logs_dir, f'{target}.log')
            if not os.path.exists(log_path):
                classifications.append({
                    'target':     target,
                    'abort_type': 'ABORT_OTHER',
                    'note':       f'log file not found at {log_path!r}',
                })
                continue
        log_text = _read_log(log_path)
        hits = classify(log_text, target)
        if hits:
            classifications.extend(hits)
        else:
            classifications.append({
                'target':     target,
                'abort_type': 'ABORT_OTHER',
                'note':       'no known abort pattern matched in log; check manually',
                'log_path':   log_path,
            })

    # Aggregate verdict — pick the most-frequent abort_type as primary
    from collections import Counter
    type_counts = Counter(c.get('abort_type', 'ABORT_OTHER') for c in classifications)
    primary_abort_type = type_counts.most_common(1)[0][0] if type_counts else 'ABORT_OTHER'

    # Build remediation hints (deduped by suggested_action)
    seen_actions = set()
    remediation_hints = []
    for c in classifications:
        action = c.get('suggested_action', '')
        if action and action not in seen_actions:
            seen_actions.add(action)
            remediation_hints.append(action)

    out = {
        'tag':                args.tag,
        'round':              args.round,
        'status':             'ABORT',
        'primary_abort_type': primary_abort_type,
        'targets_aborted':    sorted(set(c['target'] for c in classifications)),
        'classifications':    classifications,
        'remediation_hints':  remediation_hints,
        # ABORT NEVER triggers re-study (Step 1/2/3) — per ROUND_ORCHESTRATOR.md
        # line 50 ('ABORT verdict MUST NOT trigger re-study or eco_passes_2_4
        # re-run. Only netlist patches that fix the elaboration error.'). The
        # restart point is always Step 5 (re-validate after patch) → Step 6
        # (resubmit FM), within the same round counter.
        'restart_from_step':  5,
        'rerun_same_round':   True,
        'loop_verdict':       'RERUN_SAME_ROUND',
    }
    Path(args.output).write_text(json.dumps(out, indent=2))

    # Optionally merge into round_handoff.json so the next-round orchestrator
    # has the hint without re-running this script
    if args.update_round_handoff and Path(args.update_round_handoff).is_file():
        try:
            handoff = json.loads(Path(args.update_round_handoff).read_text())
        except Exception:
            handoff = {}
        handoff['fm_abort_classification'] = out
        handoff['loop_verdict']            = 'RERUN_SAME_ROUND'
        Path(args.update_round_handoff).write_text(json.dumps(handoff, indent=2))

    print(f'eco_extract_fm_abort_cause.py: ABORT classified as '
          f'{primary_abort_type} ({len(classifications)} hits across '
          f'{len(set(c["target"] for c in classifications))} targets)')
    for h in remediation_hints:
        print(f'  → {h[:120]}')
    print(f'  output: {args.output}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
