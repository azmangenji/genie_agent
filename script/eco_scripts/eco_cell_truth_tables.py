#!/usr/bin/env python3
"""
eco_cell_truth_tables.py — Engine for verifying that a chosen cell's boolean
function matches the claimed gate_function.

This module is library-agnostic. It contains:
  - Universal abstract gate-function definitions (AND2, NOR3, AOI21, ... — these
    are mathematical concepts, not tied to any process)
  - Lookup machinery (family_of, truth_table_of, cell_function_matches)

Library-specific data (cell-name → boolean expression) lives in JSON files
under script/eco_scripts/cell_libraries/<library_name>.json. The engine
auto-loads any JSON it finds in that directory and merges them.

Adding support for a new library:
  1. Create script/eco_scripts/cell_libraries/<your_lib>.json
  2. JSON shape: {"<CELL_FAMILY>": {"<output_pin>": "<boolean expression>", ...}}
     Family is the cell-name prefix before drive strength (e.g. AN2D1BWP... → AN2).
     Boolean expression uses Python operators ~, &, |, ^ over input pin names.
  3. Re-run the validator — new entries are picked up automatically.

Adding a single cell to an existing library:
  Edit the relevant JSON. No code changes needed.
"""
import json, os, re

# ── Engine: universal abstract gate-function definitions ─────────────────────
# These are mathematical truth tables for the standard logic functions used
# in study JSON `gate_function` fields. NOT library-specific.

ABSTRACT_GATE_FUNCTIONS = {
    "INV":   {"ZN": "~I"},
    "BUF":   {"Z":  "I"},
    "AND2":  {"Z":  "A1 & A2"},
    "AND3":  {"Z":  "A1 & A2 & A3"},
    "AND4":  {"Z":  "A1 & A2 & A3 & A4"},
    "NAND2": {"ZN": "~(A1 & A2)"},
    "NAND3": {"ZN": "~(A1 & A2 & A3)"},
    "NAND4": {"ZN": "~(A1 & A2 & A3 & A4)"},
    "OR2":   {"Z":  "A1 | A2"},
    "OR3":   {"Z":  "A1 | A2 | A3"},
    "OR4":   {"Z":  "A1 | A2 | A3 | A4"},
    "NOR2":  {"ZN": "~(A1 | A2)"},
    "NOR3":  {"ZN": "~(A1 | A2 | A3)"},
    "NOR4":  {"ZN": "~(A1 | A2 | A3 | A4)"},
    "XOR2":  {"Z":  "A1 ^ A2"},
    "XNOR2": {"ZN": "~(A1 ^ A2)"},
    "AOI21": {"ZN": "~((A1 & A2) | B)"},
    "AOI22": {"ZN": "~((A1 & A2) | (B1 & B2))"},
    "OAI21": {"ZN": "~((A1 | A2) & B)"},
    "OAI22": {"ZN": "~((A1 | A2) & (B1 | B2))"},
    "AO21":  {"Z":  "(A1 & A2) | B"},
    "AO22":  {"Z":  "(A1 & A2) | (B1 & B2)"},
    "OA21":  {"Z":  "(A1 | A2) & B"},
    "OA22":  {"Z":  "(A1 | A2) & (B1 | B2)"},
}

# ── Engine: regex to extract cell family from a full cell-type string ────────
# Family = cell-name prefix before drive strength suffix.
# Example: AN2D1BWP136P5M156H3P48CPDLVT → AN2
# The drive-strength `D\d+` is REQUIRED in the pattern to stop greedy [A-Z]+ from
# consuming letters AFTER the family (e.g. `INV` in INVD1BWP, not `INVD`).
_FAMILY_RE = re.compile(r"^([A-Z]+\d*)D\d+[A-Z0-9]*$")

def family_of(cell_type):
    """Extract the cell family prefix from a full cell_type string. Returns
    None if the format is unrecognized."""
    if not cell_type:
        return None
    m = _FAMILY_RE.match(cell_type)
    return m.group(1) if m else None

# ── Engine: load library cell data from JSON files ───────────────────────────
_LIBRARY_DATA = None

def _load_libraries():
    """Load all *.json files from script/eco_scripts/cell_libraries/ and merge
    them into a single family→truth-table dict. Cached after first call."""
    global _LIBRARY_DATA
    if _LIBRARY_DATA is not None:
        return _LIBRARY_DATA
    _LIBRARY_DATA = {}
    lib_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cell_libraries")
    if not os.path.isdir(lib_dir):
        return _LIBRARY_DATA
    for fname in sorted(os.listdir(lib_dir)):
        if not fname.endswith(".json"):
            continue
        path = os.path.join(lib_dir, fname)
        try:
            with open(path) as f:
                data = json.load(f)
            for family, tt in data.items():
                if family.startswith("_"):
                    continue  # skip metadata keys
                # Last-loaded library wins on conflict; warn could be added
                _LIBRARY_DATA[family] = tt
        except (json.JSONDecodeError, OSError) as e:
            print(f"WARN: failed to load cell library {fname}: {e}")
    return _LIBRARY_DATA

def truth_table_of(cell_type_or_function):
    """Look up truth table for a full cell name OR an abstract gate_function.
    Returns dict {pin: expr} or None if unknown."""
    if not cell_type_or_function:
        return None
    # Try as abstract gate function first
    if cell_type_or_function in ABSTRACT_GATE_FUNCTIONS:
        return ABSTRACT_GATE_FUNCTIONS[cell_type_or_function]
    # Try as full cell name → extract family → look up library data
    fam = family_of(cell_type_or_function)
    if fam is None:
        return None
    libs = _load_libraries()
    return libs.get(fam)

def cell_function_matches(cell_type, gate_function):
    """Compare a chosen cell's truth table to the claimed abstract function.
    Returns (match, reason):
       True  = both known and equivalent
       False = both known and different (definite bug)
       None  = at least one unknown (cannot verify; not necessarily a bug)
    """
    cell_tt = truth_table_of(cell_type)
    func_tt = truth_table_of(gate_function)
    if cell_tt is None and func_tt is None:
        return (None, f"both unknown: cell={cell_type!r} fn={gate_function!r}")
    if cell_tt is None:
        return (None, f"cell family {family_of(cell_type)!r} not in any loaded library JSON")
    if func_tt is None:
        return (None, f"gate_function {gate_function!r} not in abstract function set")
    if cell_tt == func_tt:
        return (True, "match")
    return (False, f"truth table mismatch: cell={cell_tt}, claimed={func_tt}")


if __name__ == "__main__":
    # Self-test: verify engine works against whatever library JSONs are loaded
    libs = _load_libraries()
    print(f"Loaded {len(libs)} cell families from cell_libraries/")
    cases = [
        ("AN2D1BWP136P5M156H3P48CPDLVT", "AND2"),
        ("OR4D1BWP136P5M117H3P48CPDLVT", "OR4"),
        ("NR2D1SPG1AMDBWP136P5M156H3P48CPDLVT", "NOR2"),
        ("INR3D1BWP136P5M156H3P48CPDLVT", "NOR3"),
        ("WeirdCell123", "AND2"),
    ]
    for cell, fn in cases:
        m, why = cell_function_matches(cell, fn)
        print(f"  {cell:50s} vs {fn:8s} → {m} ({why})")
