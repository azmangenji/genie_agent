#!/usr/bin/env python3
"""eco_build_final_html.py — Deterministic final HTML report for FINAL_ORCHESTRATOR.

Reads all per-round artifacts + summary RPT and emits a clean, well-styled
HTML report. Replaces agent-written HTML which produced inconsistent styling.

Usage:
    python3 script/eco_scripts/eco_build_final_html.py \
        --tag <TAG> --jira <JIRA> --tile <TILE> \
        --base-dir <BASE_DIR> \
        --total-rounds <N> \
        --ai-eco-flow-dir <AI_ECO_FLOW_DIR> \
        [--output <path>]
"""
import argparse, html, json, os, sys
from pathlib import Path

# Shared CSS — same family as eco_build_round_html.py
CSS = """
body{font-family:Arial,sans-serif;margin:20px;background:#f5f5f5;color:#333;max-width:1200px}
h1{color:#2c3e50;border-bottom:3px solid #3498db;padding-bottom:10px}
h2{color:#34495e;border-bottom:2px solid #bdc3c7;padding-bottom:6px;margin-top:24px}
h3{color:#555;margin-top:16px;border-left:4px solid #3498db;padding-left:8px}
table{border-collapse:collapse;width:100%;margin:10px 0;background:white}
th{background:#3498db;color:white;padding:8px 12px;text-align:left;font-size:12px}
td{padding:7px 12px;border-bottom:1px solid #eee;font-size:12px}
.pass{color:#27ae60;font-weight:bold} .fail{color:#e74c3c;font-weight:bold}
.warn{color:#e67e22;font-weight:bold} .abort{color:#e67e22;font-weight:bold}
.box{background:white;border:1px solid #ddd;padding:14px;margin:10px 0;border-radius:4px}
.success{background:#d4edda;border:1px solid #c3e6cb;padding:12px;margin:10px 0;border-radius:4px}
.alert{background:#fef3cd;border:1px solid #ffc107;padding:12px;margin:10px 0;border-radius:4px}
.error{background:#f8d7da;border:1px solid #f5c6cb;padding:12px;margin:10px 0;border-radius:4px}
pre{background:#f4f4f4;font-family:monospace;font-size:11px;padding:10px;overflow-x:auto;border:1px solid #ddd;border-radius:3px}
code{background:#f4f4f4;font-family:monospace;font-size:11px;padding:2px 5px}
""".strip()

def esc(s): return html.escape(str(s)) if s is not None else ""

def _artifact_rows(data, tag):
    files = [
        data / f"{tag}_eco_rtl_diff.json",
        data / f"{tag}_eco_step1_rtl_diff.rpt",
        data / f"{tag}_eco_step2_fenets.rpt",
        data / f"{tag}_eco_preeco_study.json",
        data / f"{tag}_eco_summary.rpt",
    ]
    rows = ""
    for f in files:
        chk = "<span class='pass'>✓</span>" if f.exists() else "<span class='fail'>✗</span>"
        rows += f"<tr><td><code>{esc(f.name)}</code></td><td>{chk}</td></tr>"
    return rows

def read_text(p):
    try: return Path(p).read_text(errors="replace") if Path(p).exists() else ""
    except: return ""

def read_json(p):
    try: return json.loads(Path(p).read_text()) if Path(p).exists() else None
    except: return None

def status_badge(s):
    s = str(s).upper()
    cls = {"PASS":"pass","CONVERGED":"pass","FM_PASSED":"pass",
           "FAIL":"fail","FM_FAILED":"fail","MAX_ROUNDS":"warn",
           "ABORT":"abort","STOP":"warn"}.get(s,"")
    return f"<span class='{cls}'>{esc(s)}</span>" if cls else esc(s)

def build_html(args):
    tag   = args.tag
    jira  = args.jira
    tile  = args.tile
    base  = Path(args.base_dir)
    total = args.total_rounds
    data  = base / "data"

    handoff     = read_json(data / f"{tag}_round_handoff.json") or {}
    fm_verify   = read_json(data / f"{tag}_eco_fm_verify.json") or {}
    fixer_state = read_json(data / f"{tag}_eco_fixer_state") or {}
    rtl_diff    = read_json(data / f"{tag}_eco_rtl_diff.json") or {}
    summary_rpt = read_text(data / f"{tag}_eco_summary.rpt")

    final_verdict = handoff.get("status", fm_verify.get("verdict", "UNKNOWN"))
    next_phase    = handoff.get("next_phase", "UNKNOWN")
    ref_dir       = handoff.get("ref_dir", "")

    # ── Subject line (embedded as HTML comment for genie_cli) ──────────────
    verdict_word = "PASS" if "PASS" in final_verdict.upper() else (
        "MAX_ROUNDS" if "MAX" in final_verdict.upper() else "FAIL")
    subject = f"[ECO {jira} FINAL] {tile} — {verdict_word} ({tag})"

    # ── Verdict banner ──────────────────────────────────────────────────────
    banner_color = {"PASS":"#27ae60","CONVERGED":"#27ae60"}.get(
        verdict_word, "#e74c3c" if verdict_word == "FAIL" else "#e67e22")

    # ── Per-round FM table ──────────────────────────────────────────────────
    round_rows = ""
    for rnd in range(1, total + 1):
        rpt_path = data / f"{tag}_eco_step6_fm_verify_round{rnd}.rpt"
        rpt_text = read_text(rpt_path)
        import re
        tgt_results = []
        for tgt in ("FmEqvEcoSynthesizeVsSynRtl",
                    "FmEqvEcoPrePlaceVsEcoSynthesize",
                    "FmEqvEcoRouteVsEcoPrePlace"):
            m = re.search(
                rf'{re.escape(tgt)}\s*[:\|]\s*(PASS|FAIL|ABORT\S*)'
                rf'(?:\[failing(?:_count)?:\s*(\d+)\]|\([^)]*?(\d+)\s+failing)?',
                rpt_text)
            if m:
                st = m.group(1)
                ct = int(m.group(2) or m.group(3) or 0)
                short = tgt.replace("FmEqvEco","").replace("VsEco","→").replace("VsSynRtl","→SynRtl")
                cls = "pass" if st=="PASS" else "fail"
                tgt_results.append(f"<span class='{cls}'>{esc(short)}: {st}({ct})</span>")
        analysis = read_json(data / f"{tag}_eco_fm_analysis_round{rnd}.json") or {}
        diag = esc(analysis.get("diagnosis","—")[:120])
        round_rows += (
            f"<tr><td>{rnd}</td>"
            f"<td>{'<br>'.join(tgt_results) or '—'}</td>"
            f"<td>{diag}</td></tr>"
        )

    # ── RTL changes summary ─────────────────────────────────────────────────
    changes = rtl_diff.get("changes", [])
    rtl_rows = "".join(
        f"<tr><td>{esc(c.get('change_type',''))}</td>"
        f"<td>{esc(c.get('new_token') or c.get('old_token',''))}</td>"
        f"<td>{esc(c.get('module_name',''))}</td>"
        f"<td>{esc(c.get('fallback_strategy',''))}</td></tr>"
        for c in changes[:30]
    )

    # ── Summary RPT (raw) ───────────────────────────────────────────────────
    summary_block = f"<pre>{esc(summary_rpt[:8000])}</pre>" if summary_rpt else "<p><i>eco_summary.rpt not available</i></p>"

    html_out = f"""<!-- subject: {subject} -->
<!DOCTYPE html>
<html><head><meta charset="utf-8">
<title>ECO Final Report — {esc(jira)}</title>
<style>{CSS}</style></head>
<body>

<h1>ECO Analysis Final Report — JIRA {esc(jira)} ({esc(tile)})</h1>

<div class="box">
<table>
<tr><td><b>Tag:</b> {esc(tag)}</td><td><b>JIRA:</b> {esc(jira)}</td>
    <td><b>Tile:</b> {esc(tile)}</td><td><b>Total Rounds:</b> {total}</td></tr>
<tr><td colspan="4"><b>TileBuilder:</b> {esc(ref_dir)}</td></tr>
</table>
</div>

<div style="background:{banner_color};color:white;padding:14px 20px;border-radius:6px;margin-bottom:18px">
  <div style="font-size:14px;opacity:0.85">FINAL VERDICT</div>
  <div style="font-size:24px;font-weight:bold;margin-top:4px">{esc(verdict_word)}</div>
  <div style="font-size:13px;margin-top:6px">{esc(final_verdict)} — {esc(next_phase)}</div>
</div>

<h2>FM Results Per Round</h2>
<table>
<tr style="background:#3498db;color:white"><th>Round</th><th>FM Targets</th><th>Diagnosis (brief)</th></tr>
{round_rows or '<tr><td colspan="3"><i>No round data</i></td></tr>'}
</table>

<h2>RTL Changes (Step 1 — {len(changes)} total)</h2>
<table>
<tr style="background:#3498db;color:white"><th>Type</th><th>Signal</th><th>Module</th><th>Strategy</th></tr>
{rtl_rows or '<tr><td colspan="4"><i>No RTL diff data</i></td></tr>'}
</table>

<h2>Summary Report</h2>
{summary_block}

<h2>Artifacts</h2>
<table>
<tr style="background:#3498db;color:white"><th>File</th><th>Exists</th></tr>
{_artifact_rows(data, tag)}
</table>

</body></html>"""

    return html_out, subject


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", required=True)
    ap.add_argument("--jira", required=True)
    ap.add_argument("--tile", required=True)
    ap.add_argument("--base-dir", required=True)
    ap.add_argument("--total-rounds", type=int, required=True)
    ap.add_argument("--ai-eco-flow-dir", default=None)
    ap.add_argument("--output", default=None)
    args = ap.parse_args()

    html_out, subject = build_html(args)

    out_path = Path(args.output) if args.output else (
        Path(args.base_dir) / "data" / f"{args.tag}_eco_report.html"
    )
    out_path.write_text(html_out)
    print(f"ECO_RPT_GENERATED: final HTML → {out_path}")

    if args.ai_eco_flow_dir:
        import shutil
        dst = Path(args.ai_eco_flow_dir) / f"{args.tag}_eco_report.html"
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(out_path, dst)
        print(f"  synced to {dst}")


if __name__ == "__main__":
    main()
