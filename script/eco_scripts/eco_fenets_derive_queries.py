#!/usr/bin/env python3
"""
eco_fenets_derive_queries.py — Deterministic Step 2 query derivation.

Walks the rtl_diff and emits the COMPLETE set of nets to query through FM
find_equivalent_nets. Replaces hand-picked agent reasoning that historically
silently dropped chain leaves (e.g. 9868: agent queried 4 leaves out of ~10,
dropped IReset → studier later used the wrong per-stage net → FM PP/Route
DFF0X failures).

Categories — same as eco_fenets_runner.md STEP A but enforced as code:

  Cat 1: wire_swap / and_term — both old_token and new_token.
  Cat 2: new_logic_dff dff_clock.
  Cat 3: new_logic_dff reset_signal.
  Cat 4: every chain leaf input that is NOT a `n_eco_*` intermediate or constant.
  Cat 5: port_promotion signal name.
  Cat 6: Mode I UNCONNECTED rename targets (submodule_instance/port_name[bit]).
  Cat 7: explicit hookup hints from rtl_diff (when present).

Output JSON: a list of {net_path, signal, source, ...} entries, deduplicated
by net_path. The fenets agent receives this list as input and may ADD entries
but must NEVER silently DROP any.

Usage:
    python3 eco_fenets_derive_queries.py \\
        --rtl-diff data/<TAG>_eco_rtl_diff.json \\
        --output   data/<TAG>_eco_fenets_queries_raw.json
"""
import argparse, json, re, sys
from pathlib import Path


_SKIP_INPUT_PREFIXES = ("n_eco_", "eco_", "1'b", "0'b", "1'h", "0'h")


def _scope_of(c):
    return c.get('scope') or c.get('instance_scope') or ''


def _abs_path(tile, scope, signal):
    """Build the absolute net path FM expects:
    `<tile>/<scope>/<signal>` — but skip the tile prefix when scope already
    starts with the tile (rtl_diff_analyzer is inconsistent: emits `ARB/CTRLSW`
    relative for child-scope changes, but `umccmd` absolute for top-scope ones).
    """
    parts = []
    if tile and not (scope == tile or scope.startswith(tile + '/')):
        parts.append(tile)
    if scope:
        parts.append(scope)
    parts.append(signal)
    return '/'.join(p.strip('/') for p in parts if p)


def derive(rtl_diff, tile=''):
    out = []
    for idx, c in enumerate(rtl_diff.get('changes', [])):
        ct = c.get('change_type', '')
        scope = _scope_of(c)

        # Cat 1: wire_swap / and_term tokens + the rewired target_register
        if ct in ('wire_swap', 'and_term'):
            for tok_field in ('old_token', 'new_token', 'target_register'):
                t = c.get(tok_field)
                if t:
                    # target_register is the DFF/signal whose driver gets rewired —
                    # often lives at a different scope (the DFF's own module). Use
                    # the change's `target_scope` if present, else fall back to scope.
                    s = c.get('target_scope') if tok_field == 'target_register' else scope
                    out.append({
                        'net_path': _abs_path(tile, s or scope, t),
                        'signal':   t,
                        'category': 1,
                        'source':   f'changes[{idx}].{tok_field}',
                    })

        # Cat 2 + 3 + 4: new_logic_dff context
        if ct in ('new_logic', 'new_logic_dff'):
            if c.get('dff_clock'):
                out.append({
                    'net_path': _abs_path(tile, scope, c['dff_clock']),
                    'signal':   c['dff_clock'],
                    'category': 2,
                    'source':   f'changes[{idx}].dff_clock',
                })
            if c.get('reset_signal'):
                out.append({
                    'net_path': _abs_path(tile, scope, c['reset_signal']),
                    'signal':   c['reset_signal'],
                    'category': 3,
                    'source':   f'changes[{idx}].reset_signal',
                })
            for g in (c.get('d_input_gate_chain') or []):
                for inp in (g.get('inputs') or []):
                    if not isinstance(inp, str):
                        continue
                    base = inp.split('[')[0]
                    if base.startswith(_SKIP_INPUT_PREFIXES):
                        continue
                    if not base:
                        continue
                    out.append({
                        'net_path': _abs_path(tile, scope, base),
                        'signal':   base,
                        'category': 4,
                        'source':   f'changes[{idx}].chain[{g.get("seq", "?")}]',
                    })

        # Cat 5: port_promotion
        if ct == 'port_promotion':
            s = c.get('signal_name') or c.get('new_token')
            if s:
                out.append({
                    'net_path': _abs_path(tile, scope, s),
                    'signal':   s,
                    'category': 5,
                    'source':   f'changes[{idx}].port_promotion',
                })

        # Cat 6: Mode I — UNCONNECTED rename target
        unc = c.get('original_unconnected_net') or c.get('d_input_net') or ''
        if unc.startswith(('UNCONNECTED_', 'SYNOPSYS_UNCONNECTED_')):
            sm = c.get('submodule_instance') or c.get('instance_name', '')
            port = c.get('port_name', '')
            bbi = c.get('bus_bit_index')
            if sm and port and bbi is not None:
                out.append({
                    'net_path':         _abs_path(tile, scope, f'{sm}/{port}[{bbi}]'),
                    'signal':           f'{port}[{bbi}]',
                    'category':         6,
                    'mode_I_candidate': True,
                    'source':           f'changes[{idx}].mode_I_candidate',
                })

        # Cat 7: explicit hookup hints (when rtl_diff_analyzer emits them)
        for h in (c.get('hookup_hints') or []):
            np = h.get('net_path')
            if np:
                out.append({
                    'net_path': np,
                    'signal':   h.get('signal') or np.rsplit('/', 1)[-1],
                    'category': 7,
                    'source':   f'changes[{idx}].hookup_hint',
                })

    # Deduplicate by net_path (preserve first source)
    seen, unique = set(), []
    for q in out:
        if q['net_path'] in seen:
            continue
        seen.add(q['net_path'])
        unique.append(q)
    return unique


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('--rtl-diff', required=True)
    p.add_argument('--tile',     default='',
                   help='Tile name (e.g. umccmd) — prepended to net_path when '
                        'rtl_diff scope is relative. Without this, FM queries '
                        'will miss the tile-root level.')
    p.add_argument('--output',   required=True)
    args = p.parse_args()

    try:
        rtl = json.loads(Path(args.rtl_diff).read_text())
    except Exception as e:
        print(f'FAIL: cannot read rtl_diff: {e}', file=sys.stderr)
        return 1

    queries = derive(rtl, args.tile)
    Path(args.output).write_text(json.dumps(queries, indent=2))

    by_cat = {}
    for q in queries:
        c = q.get('category', '?')
        by_cat[c] = by_cat.get(c, 0) + 1
    print(f'ECO_RPT_GENERATED: queries → {args.output}')
    print(f'  total:    {len(queries)}')
    print(f'  per_cat:  {dict(sorted(by_cat.items()))}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
