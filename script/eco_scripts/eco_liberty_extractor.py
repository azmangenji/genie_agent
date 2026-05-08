#!/usr/bin/env python3
"""
eco_liberty_extractor.py — Extract cell truth tables from Liberty (.lib.gz) files.

Scans <REF_DIR>/tech/synopsys/ccs/*.lib.gz, parses function fields for every
cell's output pin, translates Liberty boolean syntax to Python boolean expressions,
and writes a JSON cache file that eco_cell_truth_tables.py loads at priority 1
(before the bundled cell_libraries/*.json fallback).

This eliminates the need to manually maintain per-process-node JSON files.
Any tile, any process node — run once, cache forever (or --force to refresh).

Usage:
  python3 eco_liberty_extractor.py --ref-dir <REF_DIR>
  python3 eco_liberty_extractor.py --ref-dir <REF_DIR> --force     # re-extract even if cache exists
  python3 eco_liberty_extractor.py --ref-dir <REF_DIR> --output /custom/path/cache.json

Output: <REF_DIR>/data/eco_cell_library.json  (or --output path)

Exit: 0 = success (cells extracted), 1 = error or no Liberty files found.
"""
import argparse, gzip, json, os, re, sys, time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

# ── Liberty parser ─────────────────────────────────────────────────────────

CELL_RE = re.compile(r'^\s*cell\s*\(\s*(\w+)\s*\)\s*\{')
PIN_RE  = re.compile(r'^\s*pin\s*\(\s*(\w+)\s*\)\s*\{')
FUNC_RE = re.compile(r'^\s*function\s*:\s*"([^"]*)"\s*;')
DIR_RE  = re.compile(r'^\s*direction\s*:\s*"?(\w+)"?\s*;')


def parse_liberty_file(path):
    """Parse a .lib.gz file. Return {cell_name: {pin_name: liberty_func_str}}.
    Only output pins (direction=output) with a function field are included."""
    cells = {}
    cur_cell, cur_pin, pin_dir, pin_func = None, None, {}, {}
    try:
        with gzip.open(path, 'rt', errors='ignore') as f:
            for line in f:
                m = CELL_RE.match(line)
                if m:
                    cur_cell = m.group(1)
                    cur_pin  = None
                    continue
                if cur_cell is None:
                    continue
                pm = PIN_RE.match(line)
                if pm:
                    cur_pin = pm.group(1)
                    continue
                if cur_pin is None:
                    continue
                dm = DIR_RE.match(line)
                if dm:
                    pin_dir[(cur_cell, cur_pin)] = dm.group(1)
                    continue
                fm = FUNC_RE.match(line)
                if fm:
                    pin_func[(cur_cell, cur_pin)] = fm.group(1)
    except Exception as e:
        return {}, str(e)

    for (c, p), fn in pin_func.items():
        if pin_dir.get((c, p)) == 'output':
            cells.setdefault(c, {})[p] = fn

    return cells, None


# ── Liberty boolean → Python boolean translation ───────────────────────────

def liberty_to_python(fn):
    """Translate Liberty boolean function string to Python boolean expression.
    Liberty syntax:
      space (between tokens) → AND (&)
      + → OR (|)
      ! → NOT (~)
      ^ → XOR (^)
      () → grouping (preserved)
    """
    s = fn.strip()
    s = s.replace('!', '~')
    s = s.replace('+', '|')
    s = re.sub(r'\s+', ' ', s)
    # Insert & between adjacent tokens/groups separated by space
    s = re.sub(r'([\w\)])\s+([\w\(\~])', r'\1 & \2', s)
    return s


# ── Family extraction (cell name → family prefix) ──────────────────────────

_FAM_RE = re.compile(r'^([A-Z]+\d*)D\d+[A-Z0-9]*$')

def family_of(cell_name):
    """Extract family prefix. AN2D1BWP... → AN2. None if unrecognized."""
    m = _FAM_RE.match(cell_name)
    return m.group(1) if m else None


# ── Library file selection ─────────────────────────────────────────────────

def select_lib_files(lib_dir):
    """Select Liberty files to parse. Strategy:
    - tt0p9v100c corner (typical) for functional truth tables
    - Main cell families only (bwp*/ccs-amd* variants across all gate widths)
    - At least 1 MB (skip stubs)
    - Skip redundant variant suffixes (pmlvt, mrkl, etc.) — functional truth
      tables don't change across PM/marking variants in the same corner.
    """
    lib_dir = Path(lib_dir)
    if not lib_dir.exists():
        return []
    # Priority: amd-confidential main cells at tt corner; all gate widths
    selected = []
    seen_family = set()  # track (gate_width, vt_suffix) to avoid duplicates
    for gz in sorted(lib_dir.glob('*.lib.gz')):
        sz = gz.stat().st_size
        if sz < 500_000:           # skip stubs < 500 KB
            continue
        name = gz.name.lower()
        if 'tt0p9v100c' not in name:  # typical corner only
            continue
        # Extract gate-width + VT suffix for dedup
        # Pattern: tcbn03cbwp136p5m<WIDTH>....<VTSUFFIX>.tt0p9...
        wm  = re.search(r'bwp136p5m\w+', name)
        vtm = re.search(r'(amdconfidential[a-z]+|baselvt|basee?lvt|baseulvt|cstm[a-z]+)\b', name)
        if not wm:
            continue
        key = (wm.group(), vtm.group(1) if vtm else 'other')
        if key in seen_family:
            continue
        seen_family.add(key)
        selected.append(gz)
    return selected


# ── Main ──────────────────────────────────────────────────────────────────

def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('--ref-dir', required=True,
                   help='TileBuilder ref dir containing tech/synopsys/ccs/ and data/')
    p.add_argument('--output', default=None,
                   help='Output JSON path (default: <REF_DIR>/data/eco_cell_library.json)')
    p.add_argument('--force', action='store_true',
                   help='Re-extract even if cache already exists')
    p.add_argument('--workers', type=int, default=8,
                   help='Parallel workers for lib file parsing (default: 8)')
    args = p.parse_args()

    ref_dir = Path(args.ref_dir)
    out_path = Path(args.output) if args.output else ref_dir / 'data' / 'eco_cell_library.json'

    # Skip if cache exists and --force not set
    if out_path.exists() and not args.force:
        n = len(json.loads(out_path.read_text()))
        print(f'ECO_LIBERTY_EXTRACTOR: cache exists at {out_path} ({n} families). Use --force to refresh.')
        return 0

    lib_dir = ref_dir / 'tech' / 'synopsys' / 'ccs'
    libs = select_lib_files(lib_dir)

    if not libs:
        print(f'ECO_LIBERTY_EXTRACTOR: no Liberty files found under {lib_dir}', file=sys.stderr)
        return 1

    print(f'ECO_LIBERTY_EXTRACTOR: scanning {len(libs)} Liberty files from {lib_dir}')
    t0 = time.time()

    # Parse in parallel
    all_cells = {}   # cell_name → {pin: liberty_func}
    errors = []

    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = {ex.submit(parse_liberty_file, lib): lib for lib in libs}
        for i, fut in enumerate(as_completed(futs), 1):
            lib = futs[fut]
            cells, err = fut.result()
            if err:
                errors.append(f'{lib.name}: {err}')
            else:
                all_cells.update(cells)
            sz_mb = lib.stat().st_size / 1024 / 1024
            print(f'  [{i:2d}/{len(libs)}] {lib.name[:60]:60s} ({sz_mb:5.1f} MB) → {len(cells)} cells')

    elapsed = time.time() - t0

    # Build output: {family_prefix → {pin: python_expr}}
    # Multiple cell sizes (e.g. AN2D0P5BWP... and AN2D1BWP...) share the same
    # family (AN2) and same truth table — keep first seen.
    out = {}
    for cell_name, pins in all_cells.items():
        fam = family_of(cell_name)
        if not fam or fam in out:
            continue
        out[fam] = {pin: liberty_to_python(fn) for pin, fn in pins.items()}

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(out, indent=2, sort_keys=True))

    print(f'\nECO_LIBERTY_EXTRACTOR: done in {elapsed:.1f}s')
    print(f'  cells parsed:    {len(all_cells)}')
    print(f'  families stored: {len(out)}')
    print(f'  output:          {out_path}')
    if errors:
        print(f'  warnings ({len(errors)}):')
        for e in errors:
            print(f'    - {e}')

    return 0


if __name__ == '__main__':
    sys.exit(main())
