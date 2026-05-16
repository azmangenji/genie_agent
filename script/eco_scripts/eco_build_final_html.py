#!/usr/bin/env python3
"""eco_build_final_html.py — Comprehensive final HTML report for FINAL_ORCHESTRATOR.

Produces a full detailed email covering Steps 1-6, per-round breakdown,
and AI_ECO_FLOW_DIR artifact listing.

Usage:
    python3 script/eco_scripts/eco_build_final_html.py \
        --tag <TAG> --jira <JIRA> --tile <TILE> \
        --base-dir <BASE_DIR> --total-rounds <N> \
        --ai-eco-flow-dir <AI_ECO_FLOW_DIR> \
        [--ref-dir <REF_DIR>] [--output <path>]
"""
import argparse, html, json, re, sys
from pathlib import Path

# ── Design System (all inline — email-safe) ────────────────────────────────
FONT    = "font-family:Arial,Helvetica,sans-serif"
F_BASE  = f"{FONT};font-size:13px;color:#333"
F_SMALL = f"{FONT};font-size:11px;color:#555"
F_CODE  = "font-family:monospace;font-size:11px;color:#333"

def e(s): return html.escape(str(s)) if s is not None else ""

def badge(status):
    """Coloured status badge."""
    st = str(status).upper()
    if st in ("PASS","CONVERGED","FM_PASSED"):
        bg, fg = "#d4edda", "#155724"
    elif st in ("FAIL","FM_FAILED"):
        bg, fg = "#f8d7da", "#721c24"
    elif st in ("MAX_ROUNDS","WARN","STOP"):
        bg, fg = "#fff3cd", "#856404"
    else:
        bg, fg = "#e2e3e5", "#383d41"
    return (f'<span style="background:{bg};color:{fg};padding:2px 8px;'
            f'border-radius:12px;font-weight:bold;{FONT};font-size:12px">{e(st)}</span>')

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

def section_wrap(title, content, top_margin="24px", color="#3498db", font_size="15px"):
    """A titled section box."""
    return (
        f'<div style="margin-top:{top_margin}">'
        f'<div style="background:{color};color:white;padding:10px 16px;'
        f'border-radius:4px 4px 0 0;{FONT};font-size:{font_size};font-weight:bold">{title}</div>'
        f'<div style="background:white;border:1px solid #d6e4f7;border-top:none;'
        f'padding:14px 16px;border-radius:0 0 4px 4px">{content}</div>'
        f'</div>'
    )

def table(headers, rows, col_widths=None):
    """Consistent table with alternating row shading."""
    # Use one unified th_style — all header cells identical
    th_style = (f"background:#3498db;color:white;padding:8px 10px;text-align:left;"
                f"{FONT};font-size:12px;font-weight:bold;border:1px solid #2980b9;"
                f"white-space:nowrap")
    td_style = (f"padding:6px 10px;{FONT};font-size:12px;color:#333;"
                f"border:1px solid #ddd;vertical-align:top;background:#ffffff;"
                f"word-break:break-word;word-wrap:break-word;max-width:300px")
    td_alt   = (f"padding:6px 10px;{FONT};font-size:12px;color:#333;"
                f"border:1px solid #ddd;vertical-align:top;background:#f0f4f8;"
                f"word-break:break-word;word-wrap:break-word;max-width:300px")

    hdr = "".join(f'<th style="{th_style}">{h}</th>' for h in headers)
    body = ""
    for i, row in enumerate(rows):
        st = td_alt if i % 2 else td_style
        body += "<tr>" + "".join(f'<td style="{st}">{c}</td>' for c in row) + "</tr>"
    return (f'<table cellpadding="0" cellspacing="0" style="border-collapse:collapse;width:100%;table-layout:fixed;margin:8px 0">'
            f'<tr>{hdr}</tr>{body}</table>')

def pre_block(text, max_chars=5000):
    if not text: return f'<p style="{F_SMALL}"><i>Not available</i></p>'
    text = text[:max_chars] + ("\n… (truncated)" if len(text) > max_chars else "")
    return (f'<div style="background:#f8f9fa;border:1px solid #ddd;border-radius:4px;'
            f'padding:10px 12px;margin:6px 0;overflow-x:auto">'
            f'<pre style="margin:0;{F_CODE};white-space:pre-wrap;word-wrap:break-word">'
            f'{e(text)}</pre></div>')

def parse_fm_rpt(rpt_text):
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
            short = tgt.replace("FmEqvEco","").replace("VsEco"," vs Eco").replace("VsSynRtl"," vs SynRtl")
            results.append((short, st, cnt))
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
    rtl_diff    = readj(data / f"{tag}_eco_rtl_diff.json") or {}
    ref_dir     = args.ref_dir or handoff.get("ref_dir", "")
    study_json  = readj(data / f"{tag}_eco_preeco_study.json") or {}

    final_verdict = handoff.get("status", "UNKNOWN")
    next_phase    = handoff.get("next_phase", "UNKNOWN")
    verdict_word  = ("PASS" if "PASS" in final_verdict.upper() else
                     "MAX_ROUNDS" if "MAX" in final_verdict.upper() else "FAIL")
    banner_color  = {"PASS":"#27ae60"}.get(verdict_word,
                    "#e74c3c" if verdict_word=="FAIL" else "#e67e22")
    subject = f"[ECO {jira} FINAL] {tile} — {verdict_word} ({tag})"

    # ── HEADER INFO TABLE ──────────────────────────────────────────────────
    header_tbl = table(
        ["Tag", "JIRA", "Tile", "Total Rounds", "Final Verdict"],
        [[e(tag), e(jira), e(tile), str(total), badge(verdict_word)]]
    )
    if ref_dir:
        header_tbl += f'<p style="{F_SMALL}"><b>TileBuilder:</b> {e(ref_dir)}</p>'

    # ── VERDICT BANNER ─────────────────────────────────────────────────────
    banner = (
        f'<div style="background:{banner_color};color:white;padding:16px 20px;'
        f'border-radius:6px;margin:16px 0">'
        f'<div style="{FONT};font-size:12px;opacity:0.85;margin-bottom:6px">FINAL VERDICT</div>'
        f'<div style="{FONT};font-size:28px;font-weight:bold">{e(verdict_word)}</div>'
        f'<div style="{FONT};font-size:12px;margin-top:8px;opacity:0.9">'
        f'{e(final_verdict)} &nbsp;|&nbsp; next_phase: {e(next_phase)}</div>'
        f'</div>'
    )

    # ── STEP 1 — RTL Diff ─────────────────────────────────────────────────
    changes = rtl_diff.get("changes", [])
    nets    = rtl_diff.get("nets_to_query", [])
    chg_rows = [
        [e(c.get("change_type","")),
         f'<b>{e(c.get("new_token") or c.get("old_token",""))}</b>',
         e(c.get("module_name","")),
         e(c.get("fallback_strategy","") or c.get("declaration_type","")),
         e(c.get("target_register","") or "—")]
        for c in changes
    ]
    nets_rows = [[e(n.get("net_path","")), e(n.get("reason","")[:80])] for n in nets]
    step1_content = (
        f'<p style="{F_BASE}"><b>{len(changes)} changes identified</b></p>'
        + (table(["Change Type","Signal","Module","Strategy/Type","Target Register"], chg_rows)
           if chg_rows else f'<p style="{F_SMALL}"><i>No changes</i></p>')
        + (f'<p style="{F_BASE}"><b>Nets to query ({len(nets)}):</b></p>'
           + table(["Net Path","Reason"], nets_rows) if nets else "")
    )
    step1 = section_wrap(f"Step 1 — RTL Diff Analysis ({len(changes)} changes)", step1_content)

    # ── STEP 2 — Fenets ───────────────────────────────────────────────────
    fenets_rpt = read(data / f"{tag}_eco_step2_fenets.rpt")
    step2 = section_wrap("Step 2 — Find Equivalent Nets (Fenets)", pre_block(fenets_rpt, 3000))

    # ── STEP 3 — Study ────────────────────────────────────────────────────
    from collections import Counter as _Counter
    synth_entries = study_json.get("Synthesize", [])
    pp_entries    = study_json.get("PrePlace", [])
    rt_entries    = study_json.get("Route", [])
    synth_n, pp_n, rt_n = len(synth_entries), len(pp_entries), len(rt_entries)

    # Summary: entry type counts per stage
    ct_synth = _Counter(e.get("change_type","?") for e in synth_entries)
    ct_pp    = _Counter(e.get("change_type","?") for e in pp_entries)
    ct_rt    = _Counter(e.get("change_type","?") for e in rt_entries)
    all_types = sorted(set(ct_synth) | set(ct_pp) | set(ct_rt))
    summary_rows = [[e(t), str(ct_synth.get(t,0)), str(ct_pp.get(t,0)), str(ct_rt.get(t,0))]
                    for t in all_types]
    summary_rows.append([f'<b>Total</b>', f'<b>{synth_n}</b>', f'<b>{pp_n}</b>', f'<b>{rt_n}</b>'])

    # Gate chain entries (new_logic_gate) — use Synthesize as reference
    gate_entries = [en for en in synth_entries if en.get("change_type") == "new_logic_gate"]
    gate_rows = [
        [e(en.get("instance_name","")),
         e(en.get("gate_function","")),
         e(en.get("cell_type","").split("D")[0] if en.get("cell_type") else ""),  # family only
         e(en.get("output_net","")),
         e(en.get("instance_scope",""))]
        for en in gate_entries
    ]

    # Rewire entries
    rewire_entries = [en for en in synth_entries if en.get("change_type") == "rewire"]
    rewire_rows = [
        [e(en.get("cell_name","") or en.get("instance_name","")),
         e(en.get("cell_type","").split("D")[0] if en.get("cell_type") else ""),
         e(en.get("pin","")),
         e(en.get("old_net","")),
         e(en.get("new_net","")),
         e(en.get("instance_scope",""))]
        for en in rewire_entries
    ]

    # Port changes (declaration + connection + promotion)
    port_entries = [en for en in synth_entries if en.get("change_type") in
                    ("port_declaration","port_connection","port_promotion","new_port")]
    port_rows = [
        [e(en.get("change_type","")),
         e(en.get("signal_name","") or en.get("port_name","") or en.get("net_name","")),
         e(en.get("module_name","")),
         e(en.get("instance_name","") or en.get("instance_scope",""))]
        for en in port_entries
    ]

    study_content = (
        f'<p style="{F_BASE}"><b>Entry Type Breakdown per Stage:</b></p>'
        + table(["Change Type","Synthesize","PrePlace","Route"], summary_rows)

        + (f'<p style="{F_BASE}"><b>New Logic Gates ({len(gate_entries)}) — Synthesize reference:</b></p>'
           + table(["Instance","Gate Function","Cell Family","Output Net","Scope"], gate_rows)
           if gate_rows else "")

        + (f'<p style="{F_BASE}"><b>Rewire Entries ({len(rewire_entries)}):</b></p>'
           + table(["Cell","Family","Pin","Old Net","New Net","Scope"], rewire_rows)
           if rewire_rows else "")

        + (f'<p style="{F_BASE}"><b>Port Changes ({len(port_entries)}):</b></p>'
           + table(["Type","Signal/Port","Module","Instance"], port_rows)
           if port_rows else "")
    )
    step3 = section_wrap(
        f"Step 3 — Netlist Study ({synth_n} entries per stage)",
        study_content)

    # ── PER-ROUND BREAKDOWN ────────────────────────────────────────────────
    all_rounds = ""
    for rnd in range(1, total + 1):
        apply_j   = readj(data / f"{tag}_eco_applied_round{rnd}.json") or {}
        sm = apply_j.get("summary", {})
        apply_rpt = read(data / f"{tag}_eco_step4_eco_applied_round{rnd}.rpt")
        prefm_j   = readj(data / f"{tag}_eco_pre_fm_check_round{rnd}.json") or {}
        prefm_pass = prefm_j.get("passed", None)
        fm_rpt    = read(data / f"{tag}_eco_step6_fm_verify_round{rnd}.rpt")
        analysis  = readj(data / f"{tag}_eco_fm_analysis_round{rnd}.json") or {}

        # Step 4 summary
        apply_tbl = table(
            ["Applied","Inserted","Already Applied","Skipped","Verify Failed"],
            [[str(sm.get("applied",0)), str(sm.get("inserted",0)),
              str(sm.get("already_applied",0)), str(sm.get("skipped",0)),
              str(sm.get("verify_failed",0))]]
        )

        # Step 5
        pf_failures = prefm_j.get("failures", [])
        pf_note = ""
        if pf_failures:
            pf_note = ("<p style=\"" + F_SMALL + "\">Failures:<br>"
                       + "<br>".join(e(f) for f in pf_failures[:5]) + "</p>")

        # Step 6 FM
        fm_results = parse_fm_rpt(fm_rpt)
        if fm_results:
            fm_tbl = table(
                ["FM Target","Status","Failing Points"],
                [[e(t), badge(st), str(cnt) if cnt else ("0" if st=="PASS" else "—")]
                 for t, st, cnt in fm_results]
            )
        else:
            fm_tbl = f'<p style="{F_SMALL}"><i>FM not run this round</i></p>'

        # FM Analysis
        diag      = analysis.get("diagnosis","")
        reasoning = analysis.get("root_cause_reasoning","")
        loop_v    = analysis.get("loop_verdict","")
        fm_mode   = analysis.get("failure_mode","")
        rev_changes = analysis.get("revised_changes",[])
        analysis_block = ""
        if analysis:
            ana_tbl = table(
                ["Field","Value"],
                [["Loop Verdict",  badge(loop_v)],
                 ["Failure Mode",  e(fm_mode)],
                 ["Diagnosis",     e(diag)]]
            )
            analysis_block = (
                f'<p style="{F_BASE}"><b>FM Analyzer:</b></p>'
                + ana_tbl
                + (f'<p style="{F_BASE}"><b>Root Cause:</b></p>'
                   f'<p style="{F_SMALL}">{e(reasoning[:500])}</p>' if reasoning else "")
            )
            if rev_changes:
                rc_rows = [
                    [e(rc.get("action","")),
                     e(rc.get("cell_name") or rc.get("signal_name","—")),
                     e(rc.get("stage","all")),
                     e(rc.get("rationale","")[:100])]
                    for rc in rev_changes[:10]
                ]
                analysis_block += (
                    f'<p style="{F_BASE}"><b>Revised Changes ({len(rev_changes)}):</b></p>'
                    + table(["Action","Cell/Signal","Stage","Rationale"], rc_rows)
                )

        round_content = (
            f'<p style="{F_BASE}"><b>Step 4 — ECO Apply:</b></p>'
            + apply_tbl
            + f'<p style="{F_BASE}"><b>Step 5 — Pre-FM Check:</b> {badge("PASS" if prefm_pass else "FAIL")}</p>'
            + pf_note
            + f'<p style="{F_BASE}"><b>Step 6 — FM Verification:</b></p>'
            + fm_tbl
            + analysis_block
        )
        all_rounds += section_wrap(f"Round {rnd}", round_content,
                                    top_margin="12px", color="#1a6fa8", font_size="15px")

    # ── AI_ECO_FLOW ARTIFACTS ──────────────────────────────────────────────
    artifacts_section = ""
    if ai_flow and ai_flow.exists():
        files = sorted(f for f in ai_flow.iterdir() if f.is_file())
        art_rows = [[e(f.name), f"{f.stat().st_size // 1024} KB"] for f in files]
        artifacts_section = section_wrap(
            f"AI_ECO_FLOW Artifacts ({len(files)} files) — {e(str(ai_flow))}",
            table(["Filename", "Size"], art_rows),
            top_margin="24px"
        )

    # ── ASSEMBLE ──────────────────────────────────────────────────────────
    title_div = (
        f'<div style="background:#2c3e50;color:white;padding:18px 24px;border-radius:6px 6px 0 0">'
        f'<div style="{FONT};font-size:20px;font-weight:bold">ECO Analysis Final Report</div>'
        f'<div style="{FONT};font-size:13px;opacity:0.8;margin-top:4px">'
        f'JIRA: {e(jira)} &nbsp;|&nbsp; Tile: {e(tile)} &nbsp;|&nbsp; Tag: {e(tag)}</div>'
        f'</div>'
    )
    header_div = (
        f'<div style="background:white;border:1px solid #d0d7e0;border-top:none;'
        f'padding:14px 16px;margin-bottom:4px">' + header_tbl + '</div>'
    )
    phase1_header = (
        f'<div style="background:#1a252f;color:white;padding:8px 14px;'
        f'border-radius:4px;{FONT};font-size:14px;font-weight:bold;margin-top:20px">'
        f'STUDY PHASE — Steps 1-3</div>'
    )
    phase2_header = (
        f'<div style="background:#1a252f;color:white;padding:8px 14px;'
        f'border-radius:4px;{FONT};font-size:14px;font-weight:bold;margin-top:24px">'
        f'APPLY &amp; FM PHASE — Steps 4-6 (Per Round)</div>'
    )
    body_style = f'background:#f0f3f7;{FONT};font-size:13px;color:#333;margin:0;padding:10px'
    html_out = (
        f'<!-- subject: {subject} -->\n'
        f'<!DOCTYPE html>\n'
        f'<html><head><meta charset="utf-8"><title>ECO Final — {e(jira)}</title></head>\n'
        f'<body style="{body_style}">\n'
        f'<div style="width:700px;margin:0 auto">\n'
        + title_div + '\n'
        + header_div + '\n'
        + banner
        + phase1_header + '\n'
        + step1 + step2 + step3
        + phase2_header + '\n'
        + all_rounds
        + artifacts_section
        + '\n</div></body></html>'
    )

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
