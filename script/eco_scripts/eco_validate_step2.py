#!/usr/bin/env python3
"""
eco_validate_step2.py — Deterministic Step 2 (fenets) validator.

Gates Step 3 handoff. Verifies that for every Mode-S anchor query the
deriver emitted (Cat 8), the raw FM rpt actually returned equivalence
data and the rename map captured per-stage wires.

Checks:
  C1: every Cat 8 query in <tag>_eco_fenets_queries.json appears as a
      `Net:` entry in any of the raw fenets rpts.
  C2: every Cat 8 query receives at least one `Equivalent Nets:` block
      (i.e. FM did NOT respond with FM-036 / Unknown name / empty).
  C3: optional — if eco_bridge_candidates.json exists, every anchor pin
      has at least one candidate with stages_available covering both
      PrePlace and Route.

Exit 0 = pass, 1 = fail. ROUND_ORCHESTRATOR blocks Step 3 handoff on fail.

Usage:
    python3 eco_validate_step2.py \\
        --queries     data/<TAG>_eco_fenets_queries.json \\
        --raw-rpts    data/<FENETS_TAG>_find_equivalent_nets_raw*.rpt \\
        --rename-map  data/<TAG>_eco_fenets_rename_map.json \\
        --candidates  data/<TAG>_eco_bridge_candidates.json   (optional) \\
        --output      data/<TAG>_eco_validate_step2.json
"""
import argparse, glob, json, re, sys
from pathlib import Path


def _load_json(p):
    try:
        return json.loads(Path(p).read_text())
    except Exception:
        return None


def _load_raw_rpts(patterns):
    """Concatenate all matching raw rpt files (text)."""
    text_blocks = []
    for pat in patterns:
        for f in sorted(glob.glob(pat)):
            try:
                text_blocks.append(Path(f).read_text())
            except Exception:
                continue
    return '\n'.join(text_blocks)


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('--queries',    required=True, help='fenets_queries.json (post-sanitize)')
    p.add_argument('--queries-raw', required=False, default='',
                   help='fenets_queries_raw.json (pre-sanitize) — required for FROZEN contract check (C4)')
    p.add_argument('--raw-rpts',   nargs='+', default=[], help='glob(s) for raw FM rpts')
    p.add_argument('--rename-map', required=False, default='', help='fenets_rename_map.json')
    p.add_argument('--candidates', required=False, default='', help='eco_bridge_candidates.json (optional)')
    p.add_argument('--output',     required=True)
    args = p.parse_args()

    queries = _load_json(args.queries) or []
    if not isinstance(queries, list):
        print('FAIL: queries file is not a list', file=sys.stderr); return 1

    cat8 = [q for q in queries if q.get('category') == 8 and q.get('mode_s_anchor')]
    issues = []

    raw_text = _load_raw_rpts(args.raw_rpts) if args.raw_rpts else ''

    # C4-marker: sanitize script MUST have produced its marker file. Without the
    # marker, queries.json may have been written by some other mechanism (agent
    # or manual copy) — defeats the deterministic-sanitize guarantee.
    sanitize_marker = args.queries.replace('.json', '_sanitize_marker.txt')
    if not Path(sanitize_marker).is_file():
        issues.append(
            f"C4-marker: sanitize marker file missing — {sanitize_marker!r}. "
            f"Cannot prove eco_fenets_sanitize_queries.py was invoked. "
            f"queries.json may have been produced by agent-side write, copy, "
            f"or skipped sanitize step entirely. Orchestrator MUST run the "
            f"sanitize script per ORCHESTRATOR.md §STEP 2.")

    # C4: FROZEN contract — the sanitized queries.json MUST equal the deriver's
    # sanitize output. Any agent-side rewrite that drops or transforms entries
    # is FORBIDDEN. Compare per-category counts: if any category lost entries
    # between raw and sanitized, the agent bypassed the deterministic sanitize
    # script (history: 9868 R1 lost 4/6 Cat 8 anchor pin queries).
    if args.queries_raw and Path(args.queries_raw).is_file():
        raw_queries = _load_json(args.queries_raw) or []
        # Per-category counts
        from collections import Counter
        raw_cnt = Counter(q.get('category') for q in raw_queries)
        san_cnt = Counter(q.get('category') for q in queries)
        for cat, raw_n in raw_cnt.items():
            san_n = san_cnt.get(cat, 0)
            if san_n < raw_n:
                issues.append(
                    f"C4: FROZEN contract violation — Cat {cat} count dropped from "
                    f"{raw_n} (raw) to {san_n} (sanitized). The sanitize script preserves "
                    f"all entries; an agent-side rewrite is the only way to lose them. "
                    f"FORBIDDEN — re-run orchestrator's deterministic sanitize "
                    f"(eco_fenets_sanitize_queries.py) and do NOT manually edit queries.json.")
        # Also detect path mangling: every raw net_path's clean form must appear in sanitized
        try:
            from eco_fenets_sanitize_queries import collapse_dup_scope
            for q in raw_queries:
                np_raw = q.get('net_path', '')
                np_clean, _ = collapse_dup_scope(np_raw)
                if not any(s.get('net_path') == np_clean for s in queries):
                    cat = q.get('category', '?')
                    issues.append(
                        f"C4: FROZEN contract violation — raw net_path={np_raw!r} (Cat {cat}) "
                        f"missing from sanitized output (expected clean form: {np_clean!r}). "
                        f"Agent likely transformed the path; only collapse_dup_scope is permitted.")
        except ImportError:
            pass  # sanitize_queries module not importable; skip path check

    # C5: per-anchor WIRE coverage — every Cat 8 anchor MUST have wires queried
    # for all 3 roles (SI, SE, Q). Cat 8 entries carry `anchor_pin` as the role
    # label and `anchor_wire` as the actual queried wire. Without all 3 wires,
    # Step 3 lacks data for bridge source selection (SI/SE) or Q-closure pick (Q).
    anchor_role_map = {}  # (sibling, dff) → set of anchor_pin (role) values present
    for q in cat8:
        sib = q.get('sibling_module', '')
        dff = q.get('anchor_dff', '')
        role = q.get('anchor_pin', '')   # field carries the role label (SI/SE/Q)
        if not q.get('anchor_wire'):
            issues.append(
                f"C5: Cat 8 entry has anchor_pin={role!r} but no anchor_wire — "
                f"deriver should emit wire from picker's recommended_pick fields. "
                f"Pin paths return FM-036; wires are queryable.")
            continue
        anchor_role_map.setdefault((sib, dff), set()).add(role)
    for (sib, dff), roles in anchor_role_map.items():
        for required in ('SI', 'SE', 'Q'):
            if required not in roles:
                issues.append(
                    f"C5: anchor {sib}/{dff} missing wire query for role {required!r} — "
                    f"Cat 8 must cover all 3 roles. Without {required} wire, "
                    f"Step 3 lacks data to {'pick bridge source wire' if required in ('SI','SE') else 'verify Q closure'}.")

    # C6: rename map echo-fallback detection — every Cat 1/4 query whose rename_map
    # entry has IDENTICAL strings across all 3 stages (Synth==PP==Route) is suspicious:
    # likely the rename map fell back to "use input name as-is" because FM returned no
    # equivalence data. True stage-stable signals exist but should be the minority.
    if args.rename_map and Path(args.rename_map).is_file():
        rmap = _load_json(args.rename_map) or {}
        echo_fallbacks = []
        for sig_key, stages in rmap.items():
            if sig_key == '_metadata' or not isinstance(stages, dict):
                continue
            syn = stages.get('Synthesize', '')
            pp  = stages.get('PrePlace', '')
            rt  = stages.get('Route', '')
            # Echo fallback: all 3 are the input signal name (the trailing component
            # of the key) AND no '/' suggesting a real cell/pin path
            tail = sig_key.rsplit('/', 1)[-1]
            if syn == pp == rt == tail and '/' not in syn:
                echo_fallbacks.append(sig_key)
        if echo_fallbacks:
            # Filter out known internal-wire signals that FM cannot resolve (expected echo-fallback)
            # These are handled by eco_netlist_studier via direct gate-level grep
            known_internal = {'REG_UmcCfgEco_1_', 'RegRdbRspCredits', 'n_eco_9868_mux_sel',
                              'n_eco_9868_mux_sel', 'BeqCtrlPeSrc'}
            real_fallbacks = [sig for sig in echo_fallbacks
                              if sig.rsplit('/', 1)[-1] not in known_internal]
            if real_fallbacks:
                issues.append(
                    f"C6: rename map echo-fallback detected for {len(real_fallbacks)} signal(s): "
                    f"{real_fallbacks[:5]}... Stage entries identical to input name suggests "
                    f"FM returned no equivalence data and rename_map.py fell back to echoing "
                    f"the input. Studier will use these as if real per-stage names — silently "
                    f"wrong. Investigate FM-036 retries and re-query with corrected paths.")

    # C1 + C2: each Cat 8 query must appear in the raw rpts AND have Equivalent
    # Nets block. NO WAIVERS — every anchor wire MUST resolve in FM. The previous
    # waivers (HFSNET pattern + bare-wire-name pattern) silently passed every
    # FM-036 because EVERY anchor wire is a bare name → studier saw zero
    # equivalence data → built bridges on guessed wires → FM Route failed.
    # Per-Net block parser: walk from this `Net:` line until next `Net:` or EOF
    # — robust to retry rpts where multiple `Net:` lines stack closely.
    net_block_pat = re.compile(r'^Net:\s+(\S+).*?(?=^Net:|\Z)', re.MULTILINE | re.DOTALL)
    net_blocks_by_path = {}
    for nb in net_block_pat.finditer(raw_text):
        path = nb.group(1).strip()
        net_blocks_by_path.setdefault(path, []).append(nb.group(0))
    for q in cat8:
        np_q = q.get('net_path', '')
        ctx  = f"anchor pin={q.get('anchor_pin')} dff={q.get('anchor_dff')} sib={q.get('sibling_module')} wire={q.get('anchor_wire')}"
        if not np_q:
            issues.append(f"C1: Cat 8 entry missing net_path ({ctx})")
            continue
        # Match path with any leading FM-prefix (r:/.../ or i:/.../)
        matching = [b for path, blocks in net_blocks_by_path.items() if path.endswith('/' + np_q) or path == np_q for b in blocks]
        if not matching:
            issues.append(f"C1: anchor query NOT submitted to FM — net_path={np_q!r} ({ctx})")
            continue
        # C2: at least one block must contain `Equivalent Nets:` AND no FM-036/Unknown
        ok = any(('Equivalent Nets' in b) and ('FM-036' not in b) and ('Unknown name' not in b)
                 for b in matching)
        if not ok:
            issues.append(
                f"C2: anchor query returned FM-036 / no equivalence — net_path={np_q!r} ({ctx}). "
                f"Likely cause: scope path uses module-type instead of instance name "
                f"(e.g. 'ddrss_<tile>_t_<peer>/...' vs 'ARB/DCQARB/...'). Re-run "
                f"eco_pick_sibling.py with --tile-module and copy recommended_pick.fm_scope "
                f"into mode_s_anchor.fm_scope, then re-derive Step 2 queries.")

    # C7 — RENAME-COVERAGE: every Cat 8 anchor wire MUST appear as a key in the
    # fenets rename_map.json. If FM returned data, the collator would have
    # written an entry. Missing key = FM-036 + no per-stage data for studier.
    if args.rename_map and Path(args.rename_map).is_file():
        rmap = _load_json(args.rename_map) or {}
        rmap_keys = set(k for k in rmap.keys() if k != '_metadata')
        for q in cat8:
            np_q = q.get('net_path', '')
            if not np_q:
                continue
            # Match by exact key OR by suffix (rmap may key by sibling-internal scope)
            hit = (np_q in rmap_keys) or any(k.endswith('/' + np_q) or np_q.endswith('/' + k) for k in rmap_keys)
            if not hit:
                issues.append(
                    f"C7: anchor wire MISSING from rename_map — net_path={np_q!r} "
                    f"(pin={q.get('anchor_pin')} dff={q.get('anchor_dff')}). "
                    f"FM returned no per-stage equivalence for this wire (almost "
                    f"certainly FM-036). Step 3 studier has no stage-stable bridge "
                    f"source data. Fix Step 1 mode_s_anchor.fm_scope first, then re-run.")

    # C3: bridge_candidates.json (if present) must list ≥1 stage-stable candidate per anchor pin
    if args.candidates and Path(args.candidates).is_file():
        cands = _load_json(args.candidates) or {}
        for q in cat8:
            dff = q.get('anchor_dff'); pin = q.get('anchor_pin')
            key = f"{q.get('sibling_module')}/{dff}"
            entry = cands.get(key, {}).get(pin.lower() + '_candidates') if dff and pin else None
            if not entry:
                issues.append(f"C3: bridge_candidates missing entry for {key}/{pin}")
                continue
            ok = any(set(c.get('stages_available') or []) >= {'PrePlace', 'Route'} for c in entry)
            if not ok:
                issues.append(f"C3: no candidate covers PrePlace+Route for {key}/{pin}")

    out = {
        'queries':            args.queries,
        'queries_raw':        args.queries_raw,
        'cat8_count':         len(cat8),
        'anchor_count':       len(anchor_role_map),
        'issue_count':        len(issues),
        'issues':             issues,
        'overall_pass':       not issues,
    }
    Path(args.output).write_text(json.dumps(out, indent=2))

    print('ECO_SCRIPT_LAUNCHED: eco_validate_step2.py')
    print(f'  queries:    {args.queries}')
    print(f'  cat8:       {len(cat8)}  issues: {len(issues)}')
    print(f'  overall:    {"PASS" if not issues else "FAIL"}')
    for iss in issues:
        print(f'    - {iss}')
    return 0 if not issues else 1


if __name__ == '__main__':
    sys.exit(main())
