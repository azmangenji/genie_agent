#!/usr/bin/env python3
"""eco_build_final_html.py — Comprehensive final HTML report for FINAL_ORCHESTRATOR.

Produces a full detailed email covering:
  - Steps 1-6 (RTL diff, fenets, study, apply, pre-FM, FM) per original run
  - Per-round breakdown (what changed, what FM said, what analyzer diagnosed)
  - AI_ECO_FLOW_DIR artifact listing

Usage:
    python3 script/eco_scripts/eco_build_final_html.py \
        --tag <TAG> --jira <JIRA> --tile <TILE> \
        --base-dir <BASE_DIR> --total-rounds <N> \
        --ai-eco-flow-dir <AI_ECO_FLOW_DIR> \
        [--ref-dir <REF_DIR>] [--output <path>]
"""
import argparse, html, json, os, re, sys
from pathlib import Path

# ── Inline style constants (email-safe — no <head><style>) ─────────────────
S = {
    "body":    "font-family:Arial,sans-serif;margin:20px;background:#f5f5f5;color:#333;max-width:1200px",
    "h1":      "color:#2c3e50;border-bottom:3px solid #3498db;padding-bottom:10px;font-size:22px",
    "h2":      "color:#34495e;border-bottom:2px solid #bdc3c7;padding-bottom:6px;margin-top:24px;font-size:16px",
    "h3":      "color:#555;border-left:4px solid #3498db;padding-left:8px;margin-top:16px;font-size:14px",
    "table":   "border-collapse:collapse;width:100%;margin:8px 0;background:white",
    "th":      "background:#3498db;color:white;padding:7px 10px;text-align:left;font-size:12px",
    "td":      "padding:6px 10px;border-bottom:1px solid #eee;font-size:12px",
    "td_c":    "padding:6px 10px;border-bottom:1px solid #eee;font-size:12px;color:#555",
    "box":     "background:white;border:1px solid #ddd;padding:12px;margin:8px 0;border-radius:4px",
    "pre":     "background:#f4f4f4;font-family:monospace;font-size:11px;padding:10px;border:1px solid #ddd;border-radius:3px;overflow-x:auto;max-height:400px;overflow-y:auto",
    "pass":    "color:#27ae60;font-weight:bold",
    "fail":    "color:#e74c3c;font-weight:bold",
    "warn":    "color:#e67e22;font-weight:bold",
    "skip":    "color:#999",
}

def e(s):   return html.escape(str(s)) if s is not None else ""
def td(t, style=None):
    st = style or S["td"]
    return f'<td style="{st}">{t}</td>'
def th(t):
    return '<th style="' + S["th"] + '">' + str(t) + '</th>'

def status_span(st):
    st = str(st).upper()
    c = S["pass"] if st in ("PASS","CONVERGED","FM_PASSED") else (
        S["fail"] if st in ("FAIL","FM_FAILED") else S["warn"])
    return f'<span style="{c}">{e(st)}</span>'

def read(p):
    try:
        p = Path(p)
        return p.read_text(errors="replace") if p.exists() else ""
    except: return ""

def readj(p):
    try:
        p = Path(p)
        return json.loads(p.read_text()) if p.exists() else None
    except: return None

def pre_block(text, max_chars=6000):
    if not text: return "<p><i>Not available</i></p>"
    text = text[:max_chars] + ("…" if len(text) > max_chars else "")
    ps = S["pre"]
    return f'<pre style="{ps}">{e(text)}</pre>'

def section(title, content):
    h3s, boxs = S["h3"], S["box"]
    return f'<h3 style="{h3s}">{title}</h3><div style="{boxs}">{content}</div>'

def parse_fm_rpt(rpt_text):
    """Parse eco_step6_fm_verify_roundN.rpt — return list of (target, status, count)."""
    results = []
    for tgt in ("FmEqvEcoSynthesizeVsSynRtl",
                "FmEqvEcoPrePlaceVsEcoSynthesize",
                "FmEqvEcoRouteVsEcoPrePlace"):
        m = re.search(
            rf'{re.escape(tgt)}\s*[:\|]\s*(PASS|FAIL|ABORT\S*)'
            rf'(?:\s*\[failing(?:_count)?:\s*(\d+)\]'
            rf'|\s*\([^)]*?(\d+)\s+failing'
            rf'|\s*\|\s*(\d+))?',
            rpt_text)
        if m:
            st  = m.group(1)
            cnt = int(m.group(2) or m.group(3) or m.group(4) or 0)
            results.append((tgt, st, cnt))
    return results


def build_html(args):
    tag   = args.tag
    jira  = args.jira
    tile  = args.tile
    base  = Path(args.base_dir)
    total = args.total_rounds
    data  = base / "data"
    ai_flow = Path(args.ai_eco_flow_dir) if args.ai_eco_flow_dir else None

    handoff     = readj(data / f"{tag}_round_handoff.json") or {}
    fixer_state = readj(data / f"{tag}_eco_fixer_state") or {}
    rtl_diff    = readj(data / f"{tag}_eco_rtl_diff.json") or {}
    ref_dir     = args.ref_dir or handoff.get("ref_dir", "")

    final_verdict = handoff.get("status", "UNKNOWN")
    next_phase    = handoff.get("next_phase", "UNKNOWN")
    verdict_word  = ("PASS" if "PASS" in final_verdict.upper() else
                     "MAX_ROUNDS" if "MAX" in final_verdict.upper() else "FAIL")
    banner_color  = {"PASS":"#27ae60","CONVERGED":"#27ae60"}.get(
        verdict_word, "#e74c3c" if verdict_word=="FAIL" else "#e67e22")
    subject = f"[ECO {jira} FINAL] {tile} — {verdict_word} ({tag})"

    # ── HEADER ─────────────────────────────────────────────────────────────
    header = f"""
<table style="{S['table']}">
<tr>{th("Tag")}{th("JIRA")}{th("Tile")}{th("Total Rounds")}{th("Final Verdict")}</tr>
<tr>{td(e(tag))}{td(e(jira))}{td(e(tile))}{td(total)}{td(status_span(verdict_word))}</tr>
<tr><td colspan="5" style="{S['td']}">{th("TileBuilder Dir")}</td></tr>
<tr><td colspan="5" style="{S['td']}">{e(ref_dir)}</td></tr>
</table>"""

    # ── VERDICT BANNER ──────────────────────────────────────────────────────
    banner = f"""
<div style="background:{banner_color};color:white;padding:14px 20px;border-radius:6px;margin:12px 0">
  <div style="font-size:13px;opacity:0.85">FINAL VERDICT</div>
  <div style="font-size:26px;font-weight:bold;margin-top:4px">{e(verdict_word)}</div>
  <div style="font-size:12px;margin-top:6px">{e(final_verdict)} | next_phase: {e(next_phase)}</div>
</div>"""

    # ── STEP 1 — RTL Diff ───────────────────────────────────────────────────
    changes = rtl_diff.get("changes", [])
    chg_rows = "".join(
        f"<tr>{td(e(c.get('change_type','')))}"
        f"{td(e(c.get('new_token') or c.get('old_token','')))}"
        f"{td(e(c.get('module_name','')))}"
        f"{td(e(c.get('fallback_strategy','')) or e(c.get('declaration_type','')))}"
        f"{td(e(c.get('target_register','') or ''))}</tr>"
        for c in changes
    )
    step1_table = f"""
<table style="{S['table']}">
<tr>{th("Change Type")}{th("Signal")}{th("Module")}{th("Strategy/Type")}{th("Target Reg")}</tr>
{chg_rows or ('<tr><td colspan="5" style="' + S['td'] + '"><i>No changes</i></td></tr>')}
</table>"""
    nets = rtl_diff.get("nets_to_query", [])
    nets_list = "".join(f"<li>{e(n.get('net_path',''))}</li>" for n in nets)
    step1 = section(f"Step 1 — RTL Diff ({len(changes)} changes, {len(nets)} nets to query)",
                    step1_table + (f"<p><b>Nets to query:</b></p><ul>{nets_list}</ul>" if nets else ""))

    # ── STEP 2 — Fenets ────────────────────────────────────────────────────
    fenets_rpt = read(data / f"{tag}_eco_step2_fenets.rpt")
    step2 = section("Step 2 — Find Equivalent Nets (Fenets)", pre_block(fenets_rpt))

    # ── STEP 3 — Netlist Study ──────────────────────────────────────────────
    study_rpt   = read(data / f"{tag}_eco_step3_netlist_study_round1.rpt")
    verify_rpt  = read(data / f"{tag}_eco_step3_netlist_verify.rpt")
    collect_rpt = read(data / f"{tag}_eco_step3_collect.rpt")
    study_json  = readj(data / f"{tag}_eco_preeco_study.json") or {}
    synth_count = len(study_json.get("Synthesize", []))
    pp_count    = len(study_json.get("PrePlace", []))
    rt_count    = len(study_json.get("Route", []))
    step3 = section(
        f"Step 3 — Netlist Study (Synth:{synth_count} PP:{pp_count} Route:{rt_count} entries)",
        pre_block(study_rpt or collect_rpt) +
        (f"<p><b>Netlist Verifier:</b></p>{pre_block(verify_rpt)}" if verify_rpt else "")
    )

    # ── PER-ROUND BREAKDOWN ─────────────────────────────────────────────────
    rounds_html = ""
    for rnd in range(1, total + 1):
        # Step 4
        apply_rpt = read(data / f"{tag}_eco_step4_eco_applied_round{rnd}.rpt")
        apply_j   = readj(data / f"{tag}_eco_applied_round{rnd}.json") or {}
        sm = apply_j.get("summary", {})
        apply_summary = (f"applied={sm.get('applied',0)} inserted={sm.get('inserted',0)} "
                         f"already={sm.get('already_applied',0)} skipped={sm.get('skipped',0)} "
                         f"verify_failed={sm.get('verify_failed',0)}")

        # Step 5
        prefm_rpt = read(data / f"{tag}_eco_step5_pre_fm_check_round{rnd}.rpt")
        prefm_j   = readj(data / f"{tag}_eco_pre_fm_check_round{rnd}.json") or {}
        prefm_pass = prefm_j.get("passed", None)
        prefm_status = status_span("PASS" if prefm_pass else "FAIL")

        # Step 6 FM
        fm_rpt  = read(data / f"{tag}_eco_step6_fm_verify_round{rnd}.rpt")
        fm_results = parse_fm_rpt(fm_rpt)
        fm_rows = "".join(
            f"<tr>{td(e(t.replace('FmEqvEco','').replace('VsEco','→').replace('VsSynRtl','→SynRtl')))}"
            f"{td(status_span(st))}{td(str(cnt) if cnt else '—')}</tr>"
            for t, st, cnt in fm_results
        ) if fm_results else ('<tr><td colspan="3" style="' + S["td"] + '"><i>FM not run this round</i></td></tr>')

        # FM Analysis
        analysis = readj(data / f"{tag}_eco_fm_analysis_round{rnd}.json") or {}
        diag     = analysis.get("diagnosis", "—")
        reasoning = analysis.get("root_cause_reasoning", "")
        loop_v   = analysis.get("loop_verdict", "—")
        fm_mode  = analysis.get("failure_mode", "—")
        rev_changes = analysis.get("revised_changes", [])
        rev_rows = "".join(
            f"<tr>{td(e(rc.get('action','')))}"
            f"{td(e(rc.get('cell_name') or rc.get('signal_name','—')))}"
            f"{td(e(rc.get('stage','all')))}"
            f"{td(e(rc.get('rationale','')[:100]))}</tr>"
            for rc in rev_changes[:10]
        )

        prefm_fail_note = ("<br><i>Failures: " + e(str(prefm_j.get("failures",[]))) + "</i>"
                           if not prefm_pass and prefm_j.get("failures") else "")
        analysis_block = ""
        if analysis:
            tbl = ('<table style="' + S['table'] + '"><tr>' + th("Field") + th("Value") + "</tr>"
                   + "<tr>" + td("loop_verdict") + td(status_span(loop_v)) + "</tr>"
                   + "<tr>" + td("failure_mode") + td(e(fm_mode)) + "</tr>"
                   + "<tr>" + td("diagnosis")    + td(e(diag))    + "</tr>"
                   + "</table>")
            analysis_block = "<p><b>FM Analyzer Diagnosis:</b></p>" + tbl
            if reasoning:
                analysis_block += "<p><b>Root Cause:</b> " + e(reasoning[:500]) + "</p>"
            if rev_changes:
                rtbl = ('<p><b>Revised Changes (' + str(len(rev_changes)) + '):</b></p>'
                        '<table style="' + S['table'] + '"><tr>'
                        + th("Action") + th("Cell/Signal") + th("Stage") + th("Rationale")
                        + "</tr>" + rev_rows + "</table>")
                analysis_block += rtbl

        rounds_html += (
            '<div style="' + S['box'] + ';margin-top:16px">'
            + '<h3 style="' + S['h3'] + '">Round ' + str(rnd) + '</h3>'
            + "<p><b>Step 4 — ECO Apply:</b> " + e(apply_summary) + "</p>"
            + pre_block(apply_rpt, 2000)
            + "<p><b>Step 5 — Pre-FM Check:</b> " + prefm_status + prefm_fail_note + "</p>"
            + "<p><b>Step 6 — FM Verification:</b></p>"
            + '<table style="' + S['table'] + '"><tr>'
            + th("Target") + th("Status") + th("Failing Points") + "</tr>"
            + fm_rows + "</table>"
            + analysis_block
            + "</div>"
        )

    # ── AI_ECO_FLOW artifacts ───────────────────────────────────────────────
    artifacts_html = ""
    if ai_flow and ai_flow.exists():
        files = sorted(ai_flow.iterdir())
        art_rows = "".join(
            f"<tr>{td(e(f.name))}{td(e(f'{f.stat().st_size//1024} KB'))}</tr>"
            for f in files if f.is_file()
        )
        artifacts_html = f"""
<h2 style="{S['h2']}">AI_ECO_FLOW Artifacts ({len(files)} files)</h2>
<p style="color:#555;font-size:12px">{e(str(ai_flow))}</p>
<table style="{S['table']}">
<tr>{th("Filename")}{th("Size")}</tr>
{art_rows}
</table>"""

    # ── FINAL ASSEMBLY ──────────────────────────────────────────────────────
    html_out = f"""<!-- subject: {subject} -->
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>ECO Final Report — {e(jira)}</title></head>
<body style="{S['body']}">

<h1 style="{S['h1']}">ECO Analysis Final Report — JIRA {e(jira)} ({e(tile)})</h1>
<div style="{S['box']}">{header}</div>
{banner}

<h2 style="{S['h2']}">Steps 1-3 — Study Phase</h2>
{step1}
{step2}
{step3}

<h2 style="{S['h2']}">Steps 4-6 — Apply & FM Verification (Per Round)</h2>
{rounds_html}

{artifacts_html}

</body></html>"""

    return html_out, subject


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag",          required=True)
    ap.add_argument("--jira",         required=True)
    ap.add_argument("--tile",         required=True)
    ap.add_argument("--base-dir",     required=True)
    ap.add_argument("--total-rounds", type=int, required=True)
    ap.add_argument("--ai-eco-flow-dir", default=None)
    ap.add_argument("--ref-dir",      default=None)
    ap.add_argument("--output",       default=None)
    args = ap.parse_args()

    html_out, subject = build_html(args)

    out_path = Path(args.output) if args.output else (
        Path(args.base_dir) / "data" / f"{args.tag}_eco_report.html")
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
