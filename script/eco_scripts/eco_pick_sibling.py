#!/usr/bin/env python3
"""
eco_pick_sibling.py — Deterministic sibling-module picker for Step 1 mode_s_anchor.

Given a host module name (e.g. "umcarbctrlsw"), enumerates peer module instances
under the same parent module, and ranks them by:
  1. DFF count in peer module body
  2. Dominant .SE-net cluster size (most-common SE wire prefix has ≥N members)

Returns the top-ranked peer that is NOT the host module itself. Step 1 agent
reads this output and emits as `mode_s_anchor.sibling_module`.

Usage:
    python3 eco_pick_sibling.py \\
        --netlist     <REF_DIR>/data/PreEco/PrePlace.v.gz \\
        --host-module <module_name>             # e.g. umcarbctrlsw \\
        --output      data/<TAG>_eco_sibling_pick.json \\
        [--top 5]                                # report top N candidates
"""
import argparse, gzip, json, re, sys
from collections import Counter
from pathlib import Path


def _open_text(path):
    if str(path).endswith('.gz'):
        return gzip.open(path, 'rt')
    return open(path, 'r')


# Patterns
DFF_CELL_RE = re.compile(r'^\s*(SDF\w+|MB\w*SDF\w+)\s+([A-Za-z_][A-Za-z_0-9]+)\s*\(')
SE_PIN_RE   = re.compile(r'\.\s*SE\s*\(\s*([A-Za-z_][A-Za-z_0-9\[\]]*)\s*\)')
SI_PIN_RE   = re.compile(r'\.\s*SI\s*\(\s*([A-Za-z_][A-Za-z_0-9\[\]]*)\s*\)')
Q_PIN_RE    = re.compile(r'\.\s*Q\s*\(\s*([A-Za-z_][A-Za-z_0-9\[\]]*)\s*\)')
MOD_DEF_RE  = re.compile(r'^module\s+(\S+?)\s*\(')
MOD_END_RE  = re.compile(r'^\s*endmodule')
# Submodule instantiation:  "<module_name> <inst_name> ("
INST_RE     = re.compile(r'^\s*([A-Za-z_]\w+)\s+([A-Za-z_]\w+)\s*\(')


def find_module_instantiations_in_parent(lines, host_module):
    """Find any module body that instantiates host_module (or a _0/_1/prefix variant).
    Returns (parent_module_name, parent_start_line, parent_end_line, list_of_instantiated_modules).
    Returns (None, None, None, []) if host module instantiation not found."""

    host_pats = [
        re.compile(rf'^\s*{re.escape(host_module)}\s+\w+\s*\('),
        re.compile(rf'^\s*{re.escape(host_module)}_0\s+\w+\s*\('),
        re.compile(rf'^\s*{re.escape(host_module)}_1\s+\w+\s*\('),
        re.compile(rf'^\s*\S+_{re.escape(host_module)}\s+\w+\s*\('),
    ]

    # Walk modules; for each, scan body for host instantiation
    cur_mod = None
    cur_start = None
    candidates = []

    for i, line in enumerate(lines):
        m = MOD_DEF_RE.match(line)
        if m:
            cur_mod = m.group(1)
            cur_start = i
            continue
        if MOD_END_RE.match(line):
            cur_mod = None
            cur_start = None
            continue
        if cur_mod and any(p.match(line) for p in host_pats):
            # Found host instantiation inside cur_mod — this is the parent
            # Walk forward to find endmodule of this parent
            depth = 0
            for j in range(cur_start, len(lines)):
                if MOD_DEF_RE.match(lines[j]):
                    depth += 1
                elif MOD_END_RE.match(lines[j]):
                    depth -= 1
                    if depth == 0:
                        return cur_mod, cur_start, j, _list_instantiations(lines[cur_start:j+1])
            break
    return None, None, None, []


def _list_instantiations(parent_body_lines):
    """Within a module body, list all submodule instantiations — return list of
    (module_type, instance_name) tuples."""
    insts = []
    seen_inst_lines = set()  # avoid double-counting if instance spans multi-line
    for ln in parent_body_lines:
        m = INST_RE.match(ln)
        if not m:
            continue
        mod_type, inst_name = m.group(1), m.group(2)
        # Skip lines that are actually port_decls, wire decls, etc.
        if mod_type in ('input', 'output', 'inout', 'wire', 'reg', 'tri',
                        'assign', 'parameter', 'localparam', 'genvar',
                        'always', 'initial', 'function', 'task', 'module',
                        'endmodule', 'generate', 'endgenerate'):
            continue
        # Skip if mod_type starts with cell library prefix (single cell instance)
        # heuristic: cell types are usually all-uppercase + digits
        if re.match(r'^[A-Z][A-Z0-9_]*\d', mod_type) and len(mod_type) > 4:
            # Looks like a library cell (e.g. INVD1BWP...), skip
            continue
        if (mod_type, inst_name) not in seen_inst_lines:
            seen_inst_lines.add((mod_type, inst_name))
            insts.append((mod_type, inst_name))
    return insts


def find_instance_path_to_module(all_lines, target_module, tile_module=None):
    """Walk the netlist and return the FM-resolvable instance hierarchy from
    tile-down to target_module type — e.g. for sibling=ddrss_umccmd_t_umcdcqarb_0
    instantiated as DCQARB inside ddrss_umccmd_t_umcarb (which is instantiated as
    ARB inside the tile), returns 'ARB/DCQARB'.

    FM session is rooted at the tile module's internal scope; its instance path is
    therefore tile-relative. Returns the empty string when target_module is the
    tile itself (top-level — no prefix needed).

    Algorithm: walk modules; for each, scan body for `<target_module> <inst> (`.
    On hit, record (parent_mod, inst_name) and recurse with parent_mod as the new
    target. Stop when target_module == tile_module OR no parent is found.
    """
    if not target_module:
        return ''
    chain = []  # list of inst names from outer→inner
    cur = target_module
    visited = set()
    while True:
        if tile_module and cur == tile_module:
            break
        if cur in visited:
            break  # cycle guard
        visited.add(cur)
        # Find which module instantiates `cur`
        parent_mod = None
        parent_inst = None
        cur_mod = None
        cur_start = None
        inst_pat = re.compile(rf'^\s*{re.escape(cur)}\s+([A-Za-z_]\w*)\s*\(')
        for i, line in enumerate(all_lines):
            m = MOD_DEF_RE.match(line)
            if m:
                cur_mod = m.group(1); cur_start = i; continue
            if MOD_END_RE.match(line):
                cur_mod = None; cur_start = None; continue
            if cur_mod and cur_mod != cur:
                im = inst_pat.match(line)
                if im:
                    # Skip lines that are decls (input/output/wire/...)
                    parent_mod = cur_mod
                    parent_inst = im.group(1)
                    break
        if parent_mod is None:
            break  # cur is top — no parent
        chain.insert(0, parent_inst)
        cur = parent_mod
    return '/'.join(chain)


def find_module_body(lines, mod_name):
    """Find a module's body lines (start to endmodule). Tries exact, _0, _1,
    and tile-prefixed variants. Returns list of body lines."""
    candidates = [
        re.compile(rf'^module\s+{re.escape(mod_name)}\s*\('),
        re.compile(rf'^module\s+{re.escape(mod_name)}_0\s*\('),
        re.compile(rf'^module\s+{re.escape(mod_name)}_1\s*\('),
        re.compile(rf'^module\s+\S+_{re.escape(mod_name)}\s*\('),
    ]
    for i, line in enumerate(lines):
        if any(p.match(line) for p in candidates):
            depth = 0
            for j in range(i, len(lines)):
                if re.match(r'^module\s+', lines[j]):
                    depth += 1
                elif MOD_END_RE.match(lines[j]):
                    depth -= 1
                    if depth == 0:
                        return lines[i:j+1]
    return []


def analyze_module(body_lines, prefix_chars=20):
    """Return (dff_count, dominant_se_cluster_size, dominant_se_prefix,
               anchor_dff, anchor_si_wire, anchor_se_wire, anchor_q_wire).
    For the chosen anchor (first DFF in dominant SE cluster), also extract its
    .SI / .SE / .Q wire names — these are what FM Cat 8 will query (FM accepts
    wires/output-pin nets, not arbitrary input pin paths)."""
    se_nets = []
    # net_prefix → (first DFF instance, its si_wire, se_wire, q_wire)
    dff_info_for_dom_se = {}
    for i, line in enumerate(body_lines):
        m = DFF_CELL_RE.match(line)
        if not m:
            continue
        inst = m.group(2)
        # Walk forward up to ~30 lines to find pin connections
        block = ''
        depth = 0
        for j in range(i, min(i + 30, len(body_lines))):
            block += body_lines[j]
            for ch in body_lines[j].split('//')[0]:
                if ch == '(': depth += 1
                elif ch == ')':
                    depth -= 1
                    if depth == 0:
                        break
            if depth == 0 and j > i:
                break
        sm = SE_PIN_RE.search(block)
        if sm:
            net = sm.group(1)
            se_nets.append(net)
            pfx = net[:prefix_chars]
            if pfx not in dff_info_for_dom_se:
                si_m = SI_PIN_RE.search(block)
                q_m  = Q_PIN_RE.search(block)
                dff_info_for_dom_se[pfx] = (
                    inst,
                    si_m.group(1) if si_m else None,
                    net,                                 # SE wire
                    q_m.group(1) if q_m else None,
                )
    if not se_nets:
        return len(se_nets), 0, None, None, None, None, None
    cluster = Counter(n[:prefix_chars] for n in se_nets)
    dom_pfx, dom_size = cluster.most_common(1)[0]
    info = dff_info_for_dom_se.get(dom_pfx)
    if info:
        anchor, si_w, se_w, q_w = info
    else:
        anchor, si_w, se_w, q_w = None, None, None, None
    return len(se_nets), dom_size, dom_pfx, anchor, si_w, se_w, q_w


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('--netlist', required=True)
    p.add_argument('--host-module', required=True)
    p.add_argument('--output', required=True)
    p.add_argument('--top', type=int, default=5,
                   help='report top N candidates (default 5)')
    p.add_argument('--min-dffs', type=int, default=10,
                   help='minimum SE-cluster size for a peer to be considered viable (default 10)')
    p.add_argument('--tile-module', default='',
                   help='Tile module (e.g. ddrss_umccmd_t_umccmd or umccmd). Used to compute '
                        'fm_scope (FM-resolvable instance path from tile-internal root down to '
                        'sibling). Without it, fm_scope walks all the way to top.')
    args = p.parse_args()

    with _open_text(args.netlist) as f:
        all_lines = f.readlines()

    parent_mod, parent_start, parent_end, instantiations = \
        find_module_instantiations_in_parent(all_lines, args.host_module)

    if parent_mod is None:
        print(f'FAIL: host module {args.host_module!r} not instantiated in any module body',
              file=sys.stderr)
        return 1

    # Filter out host instantiations
    peer_modules = []
    seen_mods = set()
    for mod_type, inst_name in instantiations:
        # Strip _0/_1 suffix for comparison
        base = re.sub(r'_\d+$', '', mod_type)
        host_base = re.sub(r'_\d+$', '', args.host_module)
        if base == host_base or base.endswith('_' + host_base) or host_base.endswith('_' + base):
            continue
        if mod_type in seen_mods:
            continue
        seen_mods.add(mod_type)
        peer_modules.append((mod_type, inst_name))

    # Analyze each peer
    candidates = []
    for mod_type, inst_name in peer_modules:
        body = find_module_body(all_lines, mod_type)
        if not body:
            candidates.append({
                'module': mod_type, 'inst': inst_name,
                'dff_count': 0, 'dominant_se_cluster_size': 0,
                'dominant_se_prefix': None, 'anchor_dff': None,
                'anchor_si_wire': None, 'anchor_se_wire': None, 'anchor_q_wire': None,
                'viable': False, 'note': 'module body not found',
            })
            continue
        dff_count, dom_size, dom_pfx, anchor, si_w, se_w, q_w = analyze_module(body)
        # Compute FM-resolvable instance hierarchy from tile-internal root down
        # to this sibling. FM queries MUST use instance names, not module types,
        # or every find_equivalent_nets returns FM-036 (Unknown name).
        fm_scope = find_instance_path_to_module(all_lines, mod_type, args.tile_module)
        candidates.append({
            'module': mod_type, 'inst': inst_name,
            'fm_scope': fm_scope,
            'dff_count': dff_count,
            'dominant_se_cluster_size': dom_size,
            'dominant_se_prefix': dom_pfx,
            'anchor_dff': anchor,
            'anchor_si_wire': si_w,
            'anchor_se_wire': se_w,
            'anchor_q_wire':  q_w,
            'viable': dom_size >= args.min_dffs,
        })

    # Rank: viable first, then by dominant cluster size desc, then by total DFF count desc
    candidates.sort(key=lambda c: (-int(c['viable']),
                                   -c['dominant_se_cluster_size'],
                                   -c['dff_count']))

    out = {
        'host_module':       args.host_module,
        'parent_module':     parent_mod,
        'peer_count_total':  len(peer_modules),
        'peer_count_viable': sum(1 for c in candidates if c['viable']),
        'top_candidates':    candidates[:args.top],
        'recommended_pick':  candidates[0] if candidates and candidates[0]['viable'] else None,
        'all_candidates':    candidates,
    }
    Path(args.output).write_text(json.dumps(out, indent=2))

    print(f'ECO_RPT_GENERATED: sibling_pick → {args.output}')
    print(f'  host_module:      {args.host_module}')
    print(f'  parent_module:    {parent_mod}')
    print(f'  peers found:      {len(peer_modules)} ({out["peer_count_viable"]} viable)')
    if out['recommended_pick']:
        rec = out['recommended_pick']
        print(f'  RECOMMENDED:      {rec["module"]} (inst={rec["inst"]}, fm_scope={rec.get("fm_scope","?")}, dff_count={rec["dff_count"]}, se_cluster_size={rec["dominant_se_cluster_size"]}, anchor_dff={rec["anchor_dff"]})')
    else:
        print(f'  RECOMMENDED:      <NONE viable> — increase --min-dffs threshold or pick different parent scope')
    print()
    print(f'  Top {args.top} candidates:')
    for c in candidates[:args.top]:
        flag = '✓' if c['viable'] else '✗'
        print(f'    {flag} {c["module"]:50s} dffs={c["dff_count"]:5d}  se_cluster={c["dominant_se_cluster_size"]:5d}  anchor={c["anchor_dff"]}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
