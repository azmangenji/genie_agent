#!/usr/bin/env python3
"""eco_fm_xstage_compare.py — 3-way Synth/PrePlace/Route PostEco comparator
for failing DFF cones.

For each failing DFF identified by `eco_fm_evidence_walk.py`, walk back the
D/CP/SE/SI cones up to N hops in each stage's PostEco netlist and emit a
structured comparison so eco_fm_analyzer can spot stage-divergent wires,
black-boxed cells, parent-instance hookup deltas, etc.

Output: <BASE_DIR>/data/<TAG>_eco_fm_xstage_round<N>.json

Top-level structure:
  {
    "per_failing_dff": {
      "<inst_name>": {
        "stages": {
          "Synthesize": {"D": "<net>", "CP": "<net>", "SE": "<net>",
                         "SI": "<net>", "cell_type": "...",
                         "driver_chain_D": [...], ...},
          "PrePlace":   {...},
          "Route":      {...}
        },
        "wire_decls_per_stage": {
          "<wire>": {
            "Synth": {"declared_as": "wire|input|output", "drivers": [...]},
            "PrePlace": {...},
            "Route": {...}
          }
        },
        "deltas": {
          "pin_changes":     [{"pin": "SE", "stages": {"Synth": "1'b0", "PrePlace": "X", "Route": "Y"}}],
          "wire_present_per_stage": [{"wire": "X", "Synth": True, "PrePlace": False, "Route": True}],
          "cell_blackboxed":         [{"cell": "X", "missing_in": ["PrePlace", "Route"]}]
        }
      }
    }
  }

Skip if loop_verdict in evidence walk == RERUN_SAME_ROUND or CONVERGED —
xstage compare is only useful for ADVANCE_NEXT_ROUND.
"""
from __future__ import annotations

import argparse
import gzip
import json
import re
import sys
from pathlib import Path
from typing import Any


STAGES = ["Synthesize", "PrePlace", "Route"]

PIN_PATTERNS = {
    "D":  re.compile(r"\.\s*D\s*\(\s*([^\s,)]+)\s*\)"),
    "CP": re.compile(r"\.\s*CP\s*\(\s*([^\s,)]+)\s*\)"),
    "SE": re.compile(r"\.\s*SE\s*\(\s*([^\s,)]+)\s*\)"),
    "SI": re.compile(r"\.\s*SI\s*\(\s*([^\s,)]+)\s*\)"),
}

# Driver pins on combinational/sequential cells we walk back through
OUTPUT_PIN_RE = re.compile(
    r"\.\s*(Z|ZN|ZN1|Q|Q1|Q2|Q3|Q4|Q5|Q6|Q7|Q8)\s*\(\s*([^\s,)]+)\s*\)"
)
# Generic instance start (cell_type inst_name ( ) — allow leading whitespace (FC indents 2 spaces)
INST_START_RE = re.compile(r"^[ \t]*([A-Z][A-Z0-9_]+)\s+([a-zA-Z_][a-zA-Z0-9_\[\]]+)\s*\(", re.MULTILINE)


def read_gz_text(path: Path) -> str:
    if not path.exists():
        return ""
    try:
        with gzip.open(path, "rt", errors="replace") as f:
            return f.read()
    except (OSError, EOFError):
        return ""


def find_inst_block(text: str, inst_name: str) -> tuple[str, str] | None:
    """Find a cell instance block in the text. Returns (cell_type, block_text) or None.

    A block is from the cell-type line through the matching `) ;` terminator.
    Handles multi-line port lists.
    """
    # Search for an instance line that ends with `inst_name (` (with whitespace tolerance)
    pat = re.compile(
        r"^[ \t]*([A-Z][A-Z0-9_]+)\s+" + re.escape(inst_name) + r"\s*\(",
        re.MULTILINE,
    )
    m = pat.search(text)
    if not m:
        return None
    start = m.start()
    cell_type = m.group(1)
    # Walk forward until we find `) ;` outside braces
    i = m.end()
    depth = 1   # count of unclosed (
    n = len(text)
    while i < n and depth > 0:
        c = text[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                # Skip to ';' on same logical line
                semi = text.find(";", i)
                if semi == -1:
                    semi = i
                return (cell_type, text[start:semi + 1])
        i += 1
    return None


def extract_pin(block: str, pin: str) -> str:
    """Extract pin connection net name from instance block."""
    pat = PIN_PATTERNS.get(pin)
    if not pat:
        pat = re.compile(r"\.\s*" + re.escape(pin) + r"\s*\(\s*([^\s,)]+)\s*\)")
    m = pat.search(block)
    return m.group(1) if m else ""


def find_driver(text: str, net: str) -> dict | None:
    """Find a cell instance whose output (Z/ZN/Q/...) drives `net`. Return one driver."""
    if not net or net.startswith("1'b") or net.startswith("0'b"):
        return None
    # Find any line matching `.{Z|ZN|ZN1|Q...}( <net> )`
    needle = re.compile(
        r"\.\s*(Z|ZN|ZN1|Q|Q1|Q2|Q3|Q4|Q5|Q6|Q7|Q8)\s*\(\s*" + re.escape(net) + r"\s*\)"
    )
    m = needle.search(text)
    if not m:
        # Could also be an `assign net = expr;`
        assign_re = re.compile(r"\bassign\s+" + re.escape(net) + r"\s*=\s*([^;]+);")
        am = assign_re.search(text)
        if am:
            return {"driver_kind": "assign", "expression": am.group(1).strip()[:100]}
        return None
    # Walk back to find the instance start (cell_type inst_name)
    start = m.start()
    # Look back up to 2000 chars for `<CELL> <inst> (`
    snippet = text[max(0, start - 2000):start]
    inst_starts = list(INST_START_RE.finditer(snippet))
    if not inst_starts:
        return {"driver_kind": "unresolved", "out_pin": m.group(1)}
    last_inst = inst_starts[-1]
    cell_type = last_inst.group(1)
    inst_name = last_inst.group(2)
    return {
        "driver_kind": "cell",
        "cell_type": cell_type,
        "instance": inst_name,
        "out_pin": m.group(1),
    }


def trace_chain(text: str, net: str, depth: int = 5) -> list[dict]:
    """Walk back ≤ depth hops from a pin-net through driver instances."""
    chain: list[dict] = []
    current = net
    seen = set()
    for _ in range(depth):
        if not current or current in seen:
            break
        seen.add(current)
        driver = find_driver(text, current)
        if not driver:
            chain.append({"net": current, "driver": None})
            break
        chain.append({"net": current, "driver": driver})
        # If the driver is an `assign`, stop — the expression is opaque to us
        if driver.get("driver_kind") != "cell":
            break
        # Walk to first input net of the driver instance (we just record the cell, don't traverse all inputs)
        block = find_inst_block(text, driver["instance"])
        if not block:
            break
        # Extract A1 / I / D as candidate next net
        candidate = ""
        for cand_pin in ("A1", "I", "I0", "A", "D"):
            v = extract_pin(block[1] if isinstance(block, tuple) else block, cand_pin)
            if v:
                candidate = v
                break
        current = candidate
    return chain


def wire_decl_status(text: str, wire: str) -> dict:
    """Categorize wire declaration: input port / output port / local wire / not declared."""
    out = {"declared_as": "absent", "first_decl_line_excerpt": ""}
    # `^input  <wire> ;` (note 2 spaces — fusion compiler style)
    for kind in ("input", "output", "wire"):
        pat = re.compile(rf"^\s*{kind}\s+(\[\d+:\d+\]\s+)?{re.escape(wire)}\s*;",
                         re.MULTILINE)
        m = pat.search(text)
        if m:
            out["declared_as"] = kind
            line_start = text.rfind("\n", 0, m.start()) + 1
            line_end = text.find("\n", m.end())
            out["first_decl_line_excerpt"] = text[line_start:line_end].strip()
            return out
    return out


def cell_present(text: str, inst_name: str) -> bool:
    pat = re.compile(r"^[ \t]*[A-Z][A-Z0-9_]+\s+" + re.escape(inst_name) + r"\s*\(", re.MULTILINE)
    return bool(pat.search(text))


def compare_dff(inst_name: str, stage_texts: dict[str, str], depth: int = 5) -> dict:
    """Build per-stage pin map + driver chain + decl status for one failing DFF."""
    per_stage: dict[str, dict] = {}
    pin_changes: list[dict] = []

    for stage, text in stage_texts.items():
        block_info = find_inst_block(text, inst_name)
        if not block_info:
            per_stage[stage] = {"present": False}
            continue
        cell_type, block = block_info
        pins = {pin: extract_pin(block, pin) for pin in PIN_PATTERNS}
        chain_d = trace_chain(text, pins["D"], depth=depth) if pins["D"] else []
        per_stage[stage] = {
            "present": True,
            "cell_type": cell_type,
            "pins": pins,
            "driver_chain_D": chain_d,
        }

    # Compute pin deltas across stages
    if all(per_stage.get(s, {}).get("present") for s in STAGES):
        for pin in PIN_PATTERNS:
            vals = {s: per_stage[s]["pins"].get(pin, "") for s in STAGES}
            uniq = set(vals.values())
            if len(uniq) > 1:
                pin_changes.append({"pin": pin, "stages": vals})

    # Wire decl status for each pin's net per stage
    wire_decls: dict[str, dict] = {}
    interesting_wires = set()
    for s in STAGES:
        ps = per_stage.get(s, {})
        if ps.get("present"):
            for v in ps["pins"].values():
                if v and not v.startswith("1'b") and not v.startswith("0'b"):
                    interesting_wires.add(v)

    for w in interesting_wires:
        wire_decls[w] = {s: wire_decl_status(stage_texts[s], w) for s in STAGES}

    # Cell-present matrix for cells appearing in driver chains
    cells_in_chain = set()
    for s in STAGES:
        ps = per_stage.get(s, {})
        for hop in ps.get("driver_chain_D", []):
            d = hop.get("driver")
            if d and d.get("driver_kind") == "cell":
                cells_in_chain.add(d["instance"])
    cell_presence = {
        c: {s: cell_present(stage_texts[s], c) for s in STAGES}
        for c in cells_in_chain
    }
    blackboxed = []
    for c, presence in cell_presence.items():
        # Present in Synth but missing in P&R → potential black-box
        if presence.get("Synthesize") and not (presence.get("PrePlace") and presence.get("Route")):
            missing = [s for s in ("PrePlace", "Route") if not presence.get(s)]
            blackboxed.append({"cell": c, "missing_in": missing})

    # Wire-presence delta
    wire_present_delta = []
    for w, statuses in wire_decls.items():
        present = {s: statuses[s]["declared_as"] != "absent" for s in STAGES}
        if len(set(present.values())) > 1:
            wire_present_delta.append({"wire": w, **present})

    return {
        "stages": per_stage,
        "wire_decls_per_stage": wire_decls,
        "cell_presence_per_stage": cell_presence,
        "deltas": {
            "pin_changes": pin_changes,
            "wire_present_per_stage": wire_present_delta,
            "cell_blackboxed": blackboxed,
        },
    }


def write_rpt(out_rpt: Path, output: dict) -> None:
    """Human-readable RPT companion to xstage JSON."""
    lines: list[str] = []
    sep = "=" * 80
    lines.append(sep)
    lines.append(f"STEP 6 — Cross-Stage Netlist Compare (Round {output.get('round','?')})")
    lines.append(f"TAG={output.get('tag','?')}  |  loop_verdict={output.get('loop_verdict','?')}")
    lines.append(sep)

    if output.get("skipped"):
        lines.append(f"SKIPPED: {output.get('reason','')}")
        lines.append(sep)
        out_rpt.write_text("\n".join(lines) + "\n")
        return

    n = output.get("failing_dff_count", 0)
    lines.append(f"Failing DFFs analyzed: {n}")
    lines.append(f"Driver chain walk depth: {output.get('depth')} hops per pin")
    lines.append("")

    for inst, dff in output.get("per_failing_dff", {}).items():
        lines.append(f"--- {inst} ---")
        # Per-stage pin map
        for s in STAGES:
            si = dff.get("stages", {}).get(s, {})
            if not si.get("present"):
                lines.append(f"  {s:11s}: NOT FOUND")
                continue
            pins = si.get("pins", {})
            lines.append(f"  {s:11s}: cell={si.get('cell_type','?')}")
            lines.append(f"               D={pins.get('D','')}, CP={pins.get('CP','')}, "
                         f"SE={pins.get('SE','')}, SI={pins.get('SI','')}")

        # Deltas
        d = dff.get("deltas", {})
        if d.get("pin_changes"):
            lines.append(f"  Pin deltas across stages:")
            for pc in d["pin_changes"]:
                lines.append(f"    {pc['pin']}: {pc['stages']}")
        if d.get("wire_present_per_stage"):
            lines.append(f"  Wire presence deltas:")
            for w in d["wire_present_per_stage"][:10]:
                lines.append(f"    {w}")
        if d.get("cell_blackboxed"):
            lines.append(f"  Cell blackboxed (Synth-only):")
            for bb in d["cell_blackboxed"][:5]:
                lines.append(f"    {bb['cell']} (missing in {bb['missing_in']})")
        lines.append("")

    lines.append(sep)
    out_rpt.write_text("\n".join(lines) + "\n")


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--tag", required=True)
    p.add_argument("--round", type=int, required=True)
    p.add_argument("--ref-dir", required=True)
    p.add_argument("--base-dir", required=True)
    p.add_argument("--evidence-json", default=None,
                   help="Path to eco_fm_evidence_round<N>.json (default: derived)")
    p.add_argument("--output", default=None)
    p.add_argument("--depth", type=int, default=5, help="Driver chain walk depth")
    p.add_argument("--ai-eco-flow-dir", default=None,
                   help="If set, also write a companion .rpt summary to this dir")
    args = p.parse_args()

    base_dir = Path(args.base_dir)
    ref_dir = Path(args.ref_dir)
    evidence_path = Path(args.evidence_json) if args.evidence_json else (
        base_dir / "data" / f"{args.tag}_eco_fm_evidence_round{args.round}.json"
    )
    out_path = Path(args.output) if args.output else (
        base_dir / "data" / f"{args.tag}_eco_fm_xstage_round{args.round}.json"
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)

    if not evidence_path.exists():
        print(f"FAIL: evidence JSON not found: {evidence_path}", file=sys.stderr)
        return 1
    evidence = json.loads(evidence_path.read_text())

    verdict = evidence.get("loop_verdict", "")
    if verdict != "ADVANCE_NEXT_ROUND":
        # Skip — xstage compare is only useful for FAIL cases
        skip_output = {"tag": args.tag, "round": args.round, "skipped": True,
                       "loop_verdict": verdict,
                       "reason": f"loop_verdict={verdict} (not ADVANCE_NEXT_ROUND)"}
        out_path.write_text(json.dumps(skip_output, indent=2))
        print(f"SKIP: verdict={verdict} (xstage compare only runs for ADVANCE_NEXT_ROUND)")
        print(f"      → wrote stub {out_path}")
        if args.ai_eco_flow_dir:
            rpt_path = Path(args.ai_eco_flow_dir) / f"{args.tag}_eco_step6_xstage_compare_round{args.round}.rpt"
            rpt_path.parent.mkdir(parents=True, exist_ok=True)
            write_rpt(rpt_path, skip_output)
            print(f"      → wrote rpt {rpt_path}")
        return 0

    # Collect all unique failing DFF instance names
    failing_insts: set[str] = set()
    for tgt, details in evidence.get("per_target", {}).items():
        diag = details.get("failing_diagnostics", {})
        for d in diag.get("per_dff_dossiers", []):
            if d.get("instance_name"):
                failing_insts.add(d["instance_name"])

    if not failing_insts:
        out_path.write_text(json.dumps(
            {"tag": args.tag, "round": args.round, "per_failing_dff": {},
             "note": "No failing DFF instances found in evidence"},
            indent=2,
        ))
        print(f"NOTE: no failing DFFs in evidence — wrote empty stub {out_path}")
        return 0

    # Read all 3 stage netlists once
    stage_texts: dict[str, str] = {}
    for stage in STAGES:
        stage_texts[stage] = read_gz_text(ref_dir / "data" / "PostEco" / f"{stage}.v.gz")
        size_kb = len(stage_texts[stage]) // 1024
        print(f"  loaded {stage}: {size_kb}KB")

    per_failing_dff = {}
    for inst in sorted(failing_insts):
        per_failing_dff[inst] = compare_dff(inst, stage_texts, depth=args.depth)
        print(f"  compared {inst}: "
              f"pin_changes={len(per_failing_dff[inst]['deltas']['pin_changes'])}, "
              f"wire_deltas={len(per_failing_dff[inst]['deltas']['wire_present_per_stage'])}, "
              f"blackboxed={len(per_failing_dff[inst]['deltas']['cell_blackboxed'])}")

    output = {
        "tag": args.tag,
        "round": args.round,
        "loop_verdict": verdict,
        "depth": args.depth,
        "failing_dff_count": len(failing_insts),
        "per_failing_dff": per_failing_dff,
        "input_artifacts": {
            "evidence_json": str(evidence_path),
            "stage_netlists": {s: str(ref_dir / "data" / "PostEco" / f"{s}.v.gz") for s in STAGES},
        },
    }
    out_path.write_text(json.dumps(output, indent=2))
    print(f"ECO_RPT_GENERATED: xstage compare → {out_path}")

    if args.ai_eco_flow_dir:
        rpt_path = Path(args.ai_eco_flow_dir) / f"{args.tag}_eco_step6_xstage_compare_round{args.round}.rpt"
        rpt_path.parent.mkdir(parents=True, exist_ok=True)
        write_rpt(rpt_path, output)
        print(f"ECO_RPT_GENERATED: rpt → {rpt_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
