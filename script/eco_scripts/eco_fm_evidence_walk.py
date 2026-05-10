#!/usr/bin/env python3
"""eco_fm_evidence_walk.py — Comprehensive FM artifact walker for eco_fm_analyzer.

Walks every relevant FM-generated report + log for every failing target and
emits a structured per-DFF dossier JSON. The eco_fm_analyzer reads this JSON
instead of re-greping every report individually each round (saves tokens,
guarantees completeness, makes evidence auditable).

Output: <BASE_DIR>/data/<TAG>_eco_fm_evidence_round<N>.json

Top-level structure:
  {
    "loop_verdict": "RERUN_SAME_ROUND" | "ADVANCE_NEXT_ROUND" | "CONVERGED",
    "verdict_reason": "...",
    "per_target": {
      "<target_name>": {
        "status": "PASS" | "FAIL" | "ABORT" | "NOT_RUN",
        "abort_diagnostics": {...},   # populated if ABORT
        "failing_diagnostics": {...}, # populated if FAIL
      }
    },
    "tune_directives_status": {...},
    "summary_signals": [...]   # high-level findings to surface to analyzer
  }

Verdict triage runs FIRST. If any target is ABORT, the verdict is
RERUN_SAME_ROUND and only abort_diagnostics is populated (cone analysis
would be invalid anyway). If all PASS, verdict is CONVERGED. Otherwise
ADVANCE_NEXT_ROUND with full failing_diagnostics.
"""
from __future__ import annotations

import argparse
import gzip
import json
import os
import re
import sys
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Any


FM_TARGETS = [
    "FmEqvEcoSynthesizeVsSynRtl",
    "FmEqvEcoPrePlaceVsEcoSynthesize",
    "FmEqvEcoRouteVsEcoPrePlace",
]

# Patterns we extract from FM stdout logs
LOG_ERROR_PATTERNS = re.compile(
    r"^Error:|FE-LINK-\d+|FM-\d+|CMD-\d+|FMR_VLOG-\d+|"
    r"Duplicate wire/tri/wand/wor declaration|"
    r"AMD-WARN: eco|"
    r"Unresolved references|"
    r"no corresponding port",
    re.MULTILINE,
)


# ---------------------------------------------------------------------------
# I/O helpers
# ---------------------------------------------------------------------------

def read_gz_text(path: Path) -> str:
    if not path.exists():
        return ""
    try:
        with gzip.open(path, "rt", errors="replace") as f:
            return f.read()
    except (OSError, EOFError) as e:
        return f"[READ_ERROR: {e}]"


def read_text(path: Path) -> str:
    if not path.exists():
        return ""
    try:
        return path.read_text(errors="replace")
    except OSError as e:
        return f"[READ_ERROR: {e}]"


def read_json(path: Path) -> Any:
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as e:
        return {"_read_error": str(e)}


# ---------------------------------------------------------------------------
# Phase 1A — Verdict triage
# ---------------------------------------------------------------------------

def initial_verdict(fm_verify: dict | None) -> tuple[str, str, dict]:
    """Triage from eco_fm_verify.json. Returns (verdict, reason, per_target_status)."""
    per_target: dict[str, str] = {}
    if not fm_verify:
        return ("RERUN_SAME_ROUND", "eco_fm_verify.json missing or empty", per_target)

    for tgt in FM_TARGETS:
        entry = fm_verify.get(tgt)
        if entry is None:
            per_target[tgt] = "MISSING"
            continue
        if isinstance(entry, dict):
            per_target[tgt] = entry.get("status", "UNKNOWN")
        else:
            # Old format: string status; ABORT may appear as "FAIL" with 0 failing
            per_target[tgt] = str(entry)

    statuses = list(per_target.values())

    if any(s == "ABORT" for s in statuses):
        aborted = [t for t, s in per_target.items() if s == "ABORT"]
        return ("RERUN_SAME_ROUND", f"FM ABORT on: {', '.join(aborted)}", per_target)

    if any(s == "MISSING" or s == "NOT_RUN" for s in statuses):
        miss = [t for t, s in per_target.items() if s in ("MISSING", "NOT_RUN")]
        return ("RERUN_SAME_ROUND", f"Missing/not-run targets: {', '.join(miss)}", per_target)

    if all(s == "PASS" for s in statuses):
        return ("CONVERGED", "All 3 FM targets PASS", per_target)

    failing = [t for t, s in per_target.items() if s == "FAIL"]
    return ("ADVANCE_NEXT_ROUND", f"FM FAIL on: {', '.join(failing)}", per_target)


# ---------------------------------------------------------------------------
# Phase 1B — Abort diagnostics
# ---------------------------------------------------------------------------

def diagnose_abort(target: str, ref_dir: Path) -> dict:
    """Walk only abort-relevant artifacts: log, runtime.rpt, eco_applied."""
    out: dict[str, Any] = {
        "abort_type": "ABORT_OTHER",
        "log_excerpts": [],
        "fm_error_codes": [],
        "missing_ports": [],
        "duplicate_wires": [],
        "syntax_errors": [],
        "runtime_phase_failed": None,
    }

    log_path = ref_dir / "logs" / f"{target}.log.gz"
    log_text = read_gz_text(log_path)

    if not log_text:
        out["log_excerpts"] = ["[log file missing]"]
        return out

    # Extract error/warning lines (cap at 200 to keep JSON manageable)
    matches = list(LOG_ERROR_PATTERNS.finditer(log_text))
    excerpts: list[str] = []
    for m in matches[:200]:
        line_start = log_text.rfind("\n", 0, m.start()) + 1
        line_end = log_text.find("\n", m.end())
        if line_end == -1:
            line_end = len(log_text)
        excerpts.append(log_text[line_start:line_end].strip())
    out["log_excerpts"] = excerpts

    # Extract specific error codes
    code_re = re.compile(r"(FE-LINK-\d+|FM-\d+|CMD-\d+|FMR_VLOG-\d+)")
    codes = sorted(set(code_re.findall(log_text)))
    out["fm_error_codes"] = codes

    # Classify abort_type
    if any(c.startswith("CMD-") for c in codes):
        out["abort_type"] = "ABORT_SVF"
    elif any(c == "FE-LINK-7" for c in codes):
        # Sub-classify: FE-LINK-7 on TECH_LIB_DB cell vs user module
        tech_lib_link = re.search(r"FE-LINK-7.*TECH_LIB_DB", log_text)
        out["abort_type"] = "ABORT_LINK_CELL" if tech_lib_link else "ABORT_LINK"
    elif any(c in ("FM-234", "FM-156") for c in codes):
        out["abort_type"] = "ABORT_LINK"
    elif "FM-001" in codes or "FM-599" in codes:
        out["abort_type"] = "ABORT_NETLIST"
    elif "Duplicate wire/tri/wand/wor declaration" in log_text:
        out["abort_type"] = "ABORT_NETLIST"
        # Extract names
        for m in re.finditer(r"Duplicate wire/tri/wand/wor declaration for '([^']+)'", log_text):
            out["duplicate_wires"].append(m.group(1))

    # Extract missing ports from FE-LINK-7
    for m in re.finditer(
        r"The pin '([^']+)' of '([^']+)' has no corresponding port on '([^']+)'",
        log_text,
    ):
        out["missing_ports"].append(
            {"pin": m.group(1), "instance": m.group(2), "module": m.group(3)}
        )

    # Runtime rpt — which phase errored
    runtime_rpt = read_gz_text(ref_dir / "rpts" / target / f"{target}__runtime.rpt.gz")
    if runtime_rpt:
        for line in runtime_rpt.splitlines():
            if "error" in line:
                # Format: TileName  Overall  Constraints  PreVerify  Match  Verify  Loops  Reports
                cols = line.split()
                phases = ["Overall", "Constraints", "PreVerify", "Match", "Verify", "Loops", "Reports"]
                for i, c in enumerate(cols):
                    if c == "error" and i - 1 < len(phases):
                        out["runtime_phase_failed"] = phases[min(i - 1, len(phases) - 1)]
                        break
                if out["runtime_phase_failed"]:
                    break

    return out


# ---------------------------------------------------------------------------
# Phase 1C — Failing-point diagnostics
# ---------------------------------------------------------------------------

@dataclass
class FailingPointDossier:
    ref_path: str = ""
    impl_path: str = ""
    ref_cell_type: str = ""        # DFF / DFF0X / DFF1X / LATCG / etc.
    impl_cell_type: str = ""
    instance_name: str = ""
    is_eco_inserted: bool = False  # matches eco_<jira>_ pattern
    cone_inputs_unmatched: list[dict] = field(default_factory=list)
    required_inputs: list[dict] = field(default_factory=list)
    rejected_guidance: list[str] = field(default_factory=list)
    failing_reverse_clock_gating: list[dict] = field(default_factory=list)
    matched_via: str = ""          # Auto / Name / User(Last) / SVF


def parse_failing_points(rpt_text: str) -> list[dict]:
    """Parse __failing_points.rpt.gz and return one dict per failing compare point."""
    points: list[dict] = []
    if not rpt_text:
        return points
    # Each failing point block:
    #   Ref  DFF        r:/.../<inst>
    #   Impl DFF0X      i:/.../<inst>
    block_re = re.compile(
        r"\s*Ref\s+(\S+)\s+(r:[^\s]+)\s*\n\s*Impl\s+(\S+)\s+(i:[^\s]+)",
        re.MULTILINE,
    )
    for m in block_re.finditer(rpt_text):
        points.append(
            {
                "ref_cell_type": m.group(1),
                "ref_path": m.group(2),
                "impl_cell_type": m.group(3),
                "impl_path": m.group(4),
            }
        )
    return points


def parse_analyze_points(rpt_text: str, jira_pattern: str = r"eco_\d+_") -> dict:
    """Parse __analyze_points.rpt.gz into structured fields."""
    out: dict[str, Any] = {
        "unmatched_cone_inputs": [],
        "required_inputs": [],
        "rejected_guidance_commands": [],
        "failing_reverse_clock_gating": [],
    }
    if not rpt_text:
        return out

    # "Found N Unmatched Cone Inputs" section
    unmatched_section = re.search(
        r"Found \d+ Unmatched Cone Inputs(.*?)(?:Found \d+|---{20,}\nAnalysis Completed)",
        rpt_text, re.DOTALL,
    )
    if unmatched_section:
        for entry in re.finditer(
            r"((?:r|i):[^\s\n]+)\s*\n\s*(.+?)(?=\n(?:r|i):|\n\s*-{5,})",
            unmatched_section.group(1), re.DOTALL,
        ):
            net = entry.group(1).strip()
            desc = entry.group(2).strip()
            out["unmatched_cone_inputs"].append({"net": net, "description": desc[:500]})

    # "Found N Required Input" section
    required_section = re.search(
        r"Found \d+ Required Input.?(.*?)(?:Found \d+|---{20,}\nAnalysis Completed)",
        rpt_text, re.DOTALL,
    )
    if required_section:
        for entry in re.finditer(
            r"((?:r|i):[^\s\n]+)\s*\n\s*Fans out to.*?logic value '(\d|X|Z)'",
            required_section.group(1), re.DOTALL,
        ):
            out["required_inputs"].append(
                {"net": entry.group(1).strip(), "logic_value": entry.group(2)}
            )

    # "Found N Rejected Guidance Commands" section
    rejected_section = re.search(
        r"Found \d+ Rejected Guidance Commands(.*?)(?:Found \d+|---{20,}\nAnalysis Completed)",
        rpt_text, re.DOTALL,
    )
    if rejected_section:
        for line in rejected_section.group(1).splitlines():
            line = line.strip()
            if line and not line.startswith("-") and "command" not in line.lower():
                out["rejected_guidance_commands"].append(line)

    # "Found N Failing Reverse Clock Gating"
    rcg_section = re.search(
        r"Found \d+ Failing Reverse Clock Gating(.*?)(?:Found \d+|---{20,}\nAnalysis Completed)",
        rpt_text, re.DOTALL,
    )
    if rcg_section:
        for entry in re.finditer(
            r"((?:r|i):[^\s\n]+)\s*\n\s*Is a LatCG.*?(?=\n(?:r|i):|\n\s*-{5,}|\Z)",
            rcg_section.group(1), re.DOTALL,
        ):
            out["failing_reverse_clock_gating"].append({"latcg_path": entry.group(1).strip()})

    return out


def parse_undriven_nets(rpt_text: str) -> list[str]:
    """Parse __before_verify_undriven_nets.rpt.gz → list of (i:|r:)... net paths."""
    if not rpt_text:
        return []
    return [line.strip() for line in rpt_text.splitlines()
            if line.strip().startswith(("i:/", "r:/"))]


def parse_user_added_constants(rpt_text: str) -> list[str]:
    """Parse _user_added_constants.rpt.gz → list of net paths."""
    if not rpt_text:
        return []
    return [line.strip() for line in rpt_text.splitlines()
            if line.strip().startswith(("i:/", "r:/"))]


def parse_before_verify_constants(rpt_text: str) -> list[dict]:
    """Parse __before_verify_constants.rpt.gz → list of {value, type, path}."""
    if not rpt_text:
        return []
    out = []
    for line in rpt_text.splitlines():
        m = re.match(r"\s*(\d+)\s+(\w+)\s+((?:r|i):/\S+)", line)
        if m:
            out.append({"value": m.group(1), "type": m.group(2), "path": m.group(3)})
    return out


def parse_before_verify_directives(rpt_text: str) -> list[dict]:
    """Parse __before_verify_directives.rpt.gz directive status table."""
    if not rpt_text:
        return []
    out = []
    in_table = False
    for line in rpt_text.splitlines():
        if line.startswith("Design "):
            in_table = True
            continue
        if in_table and line.strip() and not line.startswith("-"):
            cols = line.split()
            if len(cols) >= 4:
                out.append({"design": cols[0], "instance": cols[1],
                            "directive": cols[2], "status": cols[3]})
    return out


def count_svf_operations(rpt_text: str) -> int:
    if not rpt_text:
        return 0
    return rpt_text.count("Operation Id:")


def parse_matched_via(rpt_text: str, dff_path_substring: str) -> str:
    """For a given failing DFF path substring, find how it matched (Auto/User(Last)/SVF/Name)."""
    if not rpt_text:
        return ""
    # Look for the Ref line containing dff_path_substring; the prefix word indicates match type
    for m in re.finditer(
        r"\s*Ref\s+\w+\s+(\S*)\s+(r:[^\s]+)", rpt_text):
        match_via = m.group(1)
        path = m.group(2)
        if dff_path_substring in path:
            return match_via or "Auto"
    return ""


def diagnose_failing(target: str, ref_dir: Path,
                     jira_pattern: str = r"eco_\d+_") -> dict:
    """Walk all failing-point relevant artifacts."""
    rpt_dir = ref_dir / "rpts" / target

    failing_text = read_gz_text(rpt_dir / f"{target}__failing_points.rpt.gz")
    analyze_text = read_gz_text(rpt_dir / f"{target}__analyze_points.rpt.gz")
    undriven_text = read_gz_text(rpt_dir / f"{target}__before_verify_undriven_nets.rpt.gz")
    user_const_text = read_gz_text(rpt_dir / f"{target}_user_added_constants.rpt.gz")
    before_const_text = read_gz_text(rpt_dir / f"{target}__before_verify_constants.rpt.gz")
    directives_text = read_gz_text(rpt_dir / f"{target}__before_verify_directives.rpt.gz")
    matched_text = read_gz_text(rpt_dir / f"{target}__matched_points.rpt.gz")

    # Per-DFF dossiers
    failing_points = parse_failing_points(failing_text)
    analyze = parse_analyze_points(analyze_text, jira_pattern)

    eco_re = re.compile(jira_pattern)
    dossiers: list[dict] = []
    for fp in failing_points:
        impl_path = fp["impl_path"]
        # extract instance name as last hierarchical segment
        inst_name = impl_path.rsplit("/", 1)[-1]
        is_eco = bool(eco_re.search(inst_name))
        # filter analyze entries that mention this DFF's instance
        per_dff_analyze = {
            "unmatched_cone_inputs": [
                e for e in analyze["unmatched_cone_inputs"]
                if inst_name in e["description"] or inst_name in e["net"]
            ],
            "required_inputs": [
                e for e in analyze["required_inputs"]
                if inst_name in e["net"]
            ],
            "rejected_guidance_commands": analyze["rejected_guidance_commands"],
            "failing_reverse_clock_gating": [
                e for e in analyze["failing_reverse_clock_gating"]
                if inst_name in e["latcg_path"]
            ],
        }
        dossiers.append(
            {
                "ref_path": fp["ref_path"],
                "impl_path": impl_path,
                "ref_cell_type": fp["ref_cell_type"],
                "impl_cell_type": fp["impl_cell_type"],
                "instance_name": inst_name,
                "is_eco_inserted": is_eco,
                "matched_via": parse_matched_via(matched_text, inst_name),
                "cone_analysis": per_dff_analyze,
            }
        )

    # SVF accept/reject counts
    svf_categories = ["change_name", "const", "datapath", "inv_push", "merge",
                      "multibit", "multiplier", "reg_const", "reg_duplication",
                      "reg_merg", "replace"]
    svf_counts = {}
    for cat in svf_categories:
        accept_path = rpt_dir / f"{target}__svf_accept_{cat}.rpt.gz"
        reject_path = rpt_dir / f"{target}__svf_reject_{cat}.rpt.gz"
        svf_counts[cat] = {
            "accepted": count_svf_operations(read_gz_text(accept_path)),
            "rejected": count_svf_operations(read_gz_text(reject_path)),
        }
    # accept_reg_const has its own filename
    svf_counts["reg_const_accept"] = {
        "accepted": count_svf_operations(
            read_gz_text(rpt_dir / f"{target}__svf_accept_reg_const.rpt.gz")
        )
    }

    return {
        "failing_count": len(failing_points),
        "per_dff_dossiers": dossiers,
        "all_undriven_nets": parse_undriven_nets(undriven_text)[:200],
        "tune_constants_applied": parse_user_added_constants(user_const_text),
        "before_verify_constants": parse_before_verify_constants(before_const_text)[:100],
        "before_verify_directives": parse_before_verify_directives(directives_text),
        "svf_operation_counts": svf_counts,
        "log_amd_warns": _extract_amd_warns(ref_dir, target),
    }


def _extract_amd_warns(ref_dir: Path, target: str) -> list[str]:
    """Extract AMD-WARN lines from FM stdout — indicate tune file get_pins/get_cells failures."""
    log_text = read_gz_text(ref_dir / "logs" / f"{target}.log.gz")
    if not log_text:
        return []
    return [line.strip() for line in log_text.splitlines() if "AMD-WARN: eco" in line][:50]


# ---------------------------------------------------------------------------
# Summary signal extraction (high-level findings for analyzer)
# ---------------------------------------------------------------------------

def build_summary_signals(per_target: dict[str, dict],
                          eco_applied: dict | None) -> list[dict]:
    """High-level findings the analyzer should consider before diving into dossiers."""
    signals: list[dict] = []

    # Signal 1: SKIPPED entries in eco_applied
    if eco_applied:
        for stage, entries in eco_applied.items():
            if stage == "summary" or not isinstance(entries, list):
                continue
            for e in entries:
                if e.get("status") == "SKIPPED":
                    signals.append({
                        "level": "high",
                        "type": "ECO_APPLIED_SKIPPED",
                        "stage": stage,
                        "cell_name": e.get("cell_name", "?"),
                        "reason": e.get("reason", "?"),
                        "hint": "Mode A sub-cause #1 — re-apply skipped change with corrected approach",
                    })
                if e.get("verify_failed") or e.get("status") == "VERIFY_FAILED":
                    signals.append({
                        "level": "high",
                        "type": "ECO_APPLIED_VERIFY_FAILED",
                        "stage": stage,
                        "cell_name": e.get("cell_name", "?"),
                        "hint": "Mode A — debug verify failure; re-apply",
                    })

    # Signal 2: ECO-inserted DFF in failing points
    for tgt, details in per_target.items():
        if details.get("status") != "FAIL":
            continue
        diag = details.get("failing_diagnostics", {})
        for d in diag.get("per_dff_dossiers", []):
            if d.get("is_eco_inserted"):
                signals.append({
                    "level": "critical",
                    "type": "ECO_INSERTED_DFF_FAILING",
                    "target": tgt,
                    "instance": d["instance_name"],
                    "impl_cell_type": d["impl_cell_type"],
                    "hint": "ECO DFF NEVER Mode E. Examine as Mode A/H/D/S based on cone divergence.",
                })

    # Signal 3: undriven net mentioned in any failing-point cone
    for tgt, details in per_target.items():
        if details.get("status") != "FAIL":
            continue
        diag = details.get("failing_diagnostics", {})
        for d in diag.get("per_dff_dossiers", []):
            for inp in d["cone_analysis"]["unmatched_cone_inputs"]:
                desc = inp.get("description", "")
                if "Is globally unmatched" in desc:
                    signals.append({
                        "level": "info",
                        "type": "UNMATCHED_CONE_INPUT",
                        "target": tgt,
                        "instance": d["instance_name"],
                        "net": inp.get("net", ""),
                        "hint": "Trace this cone back to first divergent cell/wire/port.",
                    })

    # Signal 4: rejected SVF guidance affecting any target
    for tgt, details in per_target.items():
        if details.get("status") != "FAIL":
            continue
        diag = details.get("failing_diagnostics", {})
        svf_counts = diag.get("svf_operation_counts", {})
        for cat, c in svf_counts.items():
            if c.get("rejected", 0) > 0:
                signals.append({
                    "level": "info",
                    "type": "SVF_REJECTED",
                    "target": tgt,
                    "category": cat,
                    "count": c["rejected"],
                    "hint": "Correlate with cone analysis; rejected SVF often causes verification failure.",
                })

    # Signal 5: AMD-WARN messages from tune file
    for tgt, details in per_target.items():
        if details.get("status") != "FAIL":
            continue
        warns = details.get("failing_diagnostics", {}).get("log_amd_warns", [])
        if warns:
            signals.append({
                "level": "info",
                "type": "TUNE_FILE_AMD_WARN",
                "target": tgt,
                "warn_count": len(warns),
                "first_warn": warns[0] if warns else "",
                "hint": "Tune file get_pins/get_cells returned empty for some directive — verify pattern matches actual netlist names.",
            })

    return signals


# ---------------------------------------------------------------------------
# Tune directives status (cross-target summary)
# ---------------------------------------------------------------------------

def summarize_tune_directives(per_target: dict[str, dict]) -> dict:
    """Aggregate tune-directive landing across all 3 targets."""
    out: dict[str, Any] = {
        "user_added_constants_per_target": {},
        "directives_per_target": {},
    }
    for tgt, details in per_target.items():
        diag = details.get("failing_diagnostics", {})
        out["user_added_constants_per_target"][tgt] = diag.get("tune_constants_applied", [])
        out["directives_per_target"][tgt] = diag.get("before_verify_directives", [])
    return out


# ---------------------------------------------------------------------------
# Main orchestration
# ---------------------------------------------------------------------------

def write_rpt(out_rpt: Path, output: dict) -> None:
    """Human-readable RPT companion to the JSON. Mirrors the pattern of
    other eco_step<N>_*.rpt files in <AI_ECO_FLOW_DIR>."""
    lines: list[str] = []
    sep = "=" * 80
    lines.append(sep)
    lines.append(f"STEP 6 — FM Evidence Walk (Round {output['round']})")
    lines.append(f"TAG={output['tag']}  |  loop_verdict={output['loop_verdict']}")
    lines.append(sep)
    lines.append(f"Verdict reason: {output['verdict_reason']}")
    lines.append("")

    lines.append("--- Per-target status ---")
    for tgt, det in output["per_target"].items():
        st = det.get("status", "?")
        if st == "ABORT":
            ad = det.get("abort_diagnostics", {})
            lines.append(f"  {tgt}: ABORT (type={ad.get('abort_type','?')}, "
                         f"phase={ad.get('runtime_phase_failed','?')}, "
                         f"errors={','.join(ad.get('fm_error_codes',[])[:5])})")
            for mp in ad.get("missing_ports", [])[:5]:
                lines.append(f"      missing port: {mp.get('pin')} on {mp.get('module')}")
        elif st == "FAIL":
            fd = det.get("failing_diagnostics", {})
            n = fd.get("failing_count", 0)
            lines.append(f"  {tgt}: FAIL ({n} failing compare points)")
            for d in fd.get("per_dff_dossiers", [])[:5]:
                eco_marker = " [ECO]" if d.get("is_eco_inserted") else ""
                lines.append(f"      • {d['instance_name']}{eco_marker} "
                             f"(ref={d['ref_cell_type']}, impl={d['impl_cell_type']})")
            if len(fd.get("per_dff_dossiers", [])) > 5:
                lines.append(f"      ... + {len(fd['per_dff_dossiers']) - 5} more")
        else:
            lines.append(f"  {tgt}: {st}")
    lines.append("")

    lines.append("--- Summary signals ---")
    if not output["summary_signals"]:
        lines.append("  (none)")
    else:
        # Group by level
        by_level: dict[str, list[dict]] = {}
        for s in output["summary_signals"]:
            by_level.setdefault(s.get("level", "info"), []).append(s)
        for lvl in ("critical", "high", "info"):
            for s in by_level.get(lvl, []):
                lines.append(f"  [{lvl.upper()}] {s.get('type')}: {s.get('hint','')}")
                for k, v in s.items():
                    if k in ("level", "type", "hint"):
                        continue
                    lines.append(f"      {k}: {v}")
    lines.append("")

    lines.append("--- Tune directives status (cross-target) ---")
    tune = output.get("tune_directives_status", {})
    for tgt, consts in tune.get("user_added_constants_per_target", {}).items():
        lines.append(f"  {tgt}: {len(consts)} user_added_constants applied")
    lines.append("")

    lines.append("--- Output files ---")
    lines.append(f"  evidence JSON: {output['input_artifacts'].get('fm_verify_json','?')}")
    lines.append(sep)

    out_rpt.write_text("\n".join(lines) + "\n")


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--tag", required=True)
    p.add_argument("--round", type=int, required=True)
    p.add_argument("--ref-dir", required=True, help="TileBuilder REF_DIR root")
    p.add_argument("--base-dir", required=True, help="genie_agent users/<user> base dir")
    p.add_argument("--jira-pattern", default=r"eco_\d+_",
                   help="Regex matching ECO-inserted instance names")
    p.add_argument("--output", default=None,
                   help="Output path (default: <BASE_DIR>/data/<TAG>_eco_fm_evidence_round<N>.json)")
    p.add_argument("--ai-eco-flow-dir", default=None,
                   help="If set, also write a companion .rpt summary to this dir")
    args = p.parse_args()

    ref_dir = Path(args.ref_dir)
    base_dir = Path(args.base_dir)
    out_path = Path(args.output) if args.output else (
        base_dir / "data" / f"{args.tag}_eco_fm_evidence_round{args.round}.json"
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)

    # Load eco_fm_verify.json + eco_applied for triage
    fm_verify = read_json(base_dir / "data" / f"{args.tag}_eco_fm_verify.json")
    eco_applied = read_json(base_dir / "data" / f"{args.tag}_eco_applied_round{args.round}.json")

    verdict, reason, per_target_status = initial_verdict(fm_verify if isinstance(fm_verify, dict) else None)

    per_target_details: dict[str, dict] = {}
    for tgt in FM_TARGETS:
        status = per_target_status.get(tgt, "UNKNOWN")
        details: dict[str, Any] = {"status": status}

        if status == "ABORT" or verdict == "RERUN_SAME_ROUND" and status != "PASS":
            details["abort_diagnostics"] = diagnose_abort(tgt, ref_dir)
        elif status == "FAIL":
            details["failing_diagnostics"] = diagnose_failing(tgt, ref_dir, args.jira_pattern)
        # PASS / MISSING / NOT_RUN → no extra walk

        per_target_details[tgt] = details

    summary_signals = build_summary_signals(
        per_target_details,
        eco_applied if isinstance(eco_applied, dict) else None,
    )
    tune_status = summarize_tune_directives(per_target_details)

    output = {
        "tag": args.tag,
        "round": args.round,
        "loop_verdict": verdict,
        "verdict_reason": reason,
        "per_target": per_target_details,
        "tune_directives_status": tune_status,
        "summary_signals": summary_signals,
        "input_artifacts": {
            "ref_dir": str(ref_dir),
            "fm_verify_json": str(base_dir / "data" / f"{args.tag}_eco_fm_verify.json"),
            "eco_applied_json": str(base_dir / "data" / f"{args.tag}_eco_applied_round{args.round}.json"),
        },
    }

    out_path.write_text(json.dumps(output, indent=2))
    print(f"ECO_RPT_GENERATED: evidence walk → {out_path}")

    # Companion RPT (matches existing eco_step<N>_*.rpt convention)
    if args.ai_eco_flow_dir:
        rpt_path = Path(args.ai_eco_flow_dir) / f"{args.tag}_eco_step6_evidence_walk_round{args.round}.rpt"
        rpt_path.parent.mkdir(parents=True, exist_ok=True)
        write_rpt(rpt_path, output)
        print(f"ECO_RPT_GENERATED: rpt → {rpt_path}")

    print(f"  loop_verdict:    {verdict}")
    print(f"  verdict_reason:  {reason}")
    print(f"  per_target:      {per_target_status}")
    print(f"  summary_signals: {len(summary_signals)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
