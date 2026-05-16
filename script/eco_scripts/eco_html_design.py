"""eco_html_design.py — Shared design constants for ECO HTML email builders.

Import from eco_build_round_html.py and eco_build_final_html.py to ensure
consistent styling across all ECO email reports.
"""
import html as _html

FONT    = "font-family:Arial,Helvetica,sans-serif"
F_BASE  = f"{FONT};font-size:13px;color:#333"
F_SMALL = f"{FONT};font-size:11px;color:#555"
F_CODE  = "font-family:monospace;font-size:11px;color:#333"

# Container: fixed 700px for email client compatibility (Outlook ignores max-width)
BODY_STYLE = f"background:#f0f3f7;{FONT};font-size:13px;color:#333;margin:0;padding:10px"
CONTAINER  = 'style="width:700px;margin:0 auto"'

# Table shared styles
TH_STYLE = (f"background:#3498db;color:white;padding:8px 10px;text-align:left;"
            f"{FONT};font-size:12px;font-weight:bold;border:1px solid #2980b9;white-space:nowrap")
TD_STYLE = (f"padding:6px 10px;{FONT};font-size:12px;color:#333;"
            f"border:1px solid #ddd;vertical-align:top;background:#ffffff;"
            f"word-break:break-word;word-wrap:break-word")
TD_ALT   = (f"padding:6px 10px;{FONT};font-size:12px;color:#333;"
            f"border:1px solid #ddd;vertical-align:top;background:#f0f4f8;"
            f"word-break:break-word;word-wrap:break-word")
TABLE_ATTRS = 'cellpadding="0" cellspacing="0" style="border-collapse:collapse;width:100%;table-layout:fixed;margin:8px 0"'

# Section wrap
SECTION_TITLE_STYLE = (f"background:#3498db;color:white;padding:10px 16px;"
                       f"border-radius:4px 4px 0 0;{FONT};font-size:15px;font-weight:bold")
SECTION_BODY_STYLE  = ("background:white;border:1px solid #d6e4f7;border-top:none;"
                       "padding:14px 16px;border-radius:0 0 4px 4px")

# Pre block
PRE_STYLE = (f"background:#f8f9fa;border:1px solid #ddd;border-radius:4px;"
             f"padding:10px 12px;margin:6px 0;overflow-x:auto;"
             f"font-family:monospace;font-size:11px;color:#333;"
             f"white-space:pre-wrap;word-wrap:break-word;max-height:300px;overflow-y:auto")


def esc(s):
    return _html.escape(str(s)) if s is not None else ""


def badge(status):
    st = str(status).upper()
    if st in ("PASS", "CONVERGED", "FM_PASSED"):
        bg, fg = "#d4edda", "#155724"
    elif st in ("FAIL", "FM_FAILED"):
        bg, fg = "#f8d7da", "#721c24"
    elif st in ("MAX_ROUNDS", "WARN", "STOP", "RERUN_SAME_ROUND"):
        bg, fg = "#fff3cd", "#856404"
    elif st == "ADVANCE_NEXT_ROUND":
        bg, fg = "#cce5ff", "#004085"
    else:
        bg, fg = "#e2e3e5", "#383d41"
    return (f'<span style="background:{bg};color:{fg};padding:2px 8px;'
            f'border-radius:12px;font-weight:bold;{FONT};font-size:12px">{esc(st)}</span>')


def section_wrap(title, content, top_margin="16px", color="#3498db"):
    return (
        f'<div style="margin-top:{top_margin}">'
        f'<div style="background:{color};color:white;padding:10px 16px;'
        f'border-radius:4px 4px 0 0;{FONT};font-size:15px;font-weight:bold">{title}</div>'
        f'<div style="{SECTION_BODY_STYLE}">{content}</div>'
        f'</div>'
    )


def tbl(headers, rows):
    hdr = "".join(f'<th style="{TH_STYLE}">{h}</th>' for h in headers)
    body = ""
    for i, row in enumerate(rows):
        st = TD_ALT if i % 2 else TD_STYLE
        body += "<tr>" + "".join(f'<td style="{st}">{c}</td>' for c in row) + "</tr>"
    return f'<table {TABLE_ATTRS}><tr>{hdr}</tr>{body}</table>'


def pre_block(text, max_chars=5000):
    if not text:
        return f'<p style="{F_SMALL}"><i>Not available</i></p>'
    text = text[:max_chars] + ("\n…" if len(text) > max_chars else "")
    return f'<div style="margin:6px 0"><pre style="{PRE_STYLE}">{esc(text)}</pre></div>'
