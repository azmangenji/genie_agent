# Lint Violation Extractor Agent

**PERMISSIONS:** You have FULL READ ACCESS to all files under /proj/. Do not ask for permission - just read the files directly.

Extract **ERROR severity** unwaived lint violations.

## Input
- `ref_dir`: Tree directory
- `ip`: IP name (umc9_3, oss7_2, gmc13_1a)
- `tag`: Task tag (e.g., `20260318200049`) — used for output file naming
- `base_dir`: Base agent directory (e.g., `/proj/.../main_agent`) — used for output file path

## Severity Filter

**ERROR only** — skip Warning/Info.

## Report File by IP Family

| IP Family | Report File |
|-----------|-------------|
| `umc*` | `leda_waiver.log` |
| `gmc*` | `leda_waiver.log` |
| `oss*` | `spyglass_lint.txt` |

## Report Paths

Read `config/IP_CONFIG.yaml` → Get path pattern for `lint` report.

| IP Family | Default Tile |
|-----------|--------------|
| `umc*` | `umc_top` |
| `oss*` | `osssys` |
| `gmc*` | `gmc_gmcctrl_t` |

## LOW_RISK Patterns to SKIP

Filter out violations where filename or signal contains (case-insensitive):
`rsmu`, `rdft`, `dft_`, `jtag`, `scan_`, `bist_`, `test_mode`, `tdr_`

## What to Extract

From "Unwaived" section, for each **Error** severity violation:
- `code`: Lint rule code from report
- `severity`: Error
- `filename`: RTL file path
- `line`: Line number
- `message`: Error message
- `signal_name`: Extracted from message

## Output JSON

```json
{
  "report_path": "/proj/.../leda_waiver.log",
  "total_unwaived": 45,
  "rsmu_dft_skipped": 30,
  "focus_violations": 15,
  "violations_by_code": {
    "<code_from_report>": 8
  },
  "top_violations": [
    {
      "code": "<code_from_report>",
      "severity": "Error",
      "filename": "src/rtl/.../module.sv",
      "line": 45,
      "message": "<message_from_report>",
      "signal_name": "<extracted_signal>"
    }
  ]
}
```

## Instructions

1. Find report using Glob (leda_waiver.log for UMC/GMC, spyglass_lint.txt for OSS)
2. Find "Unwaived" section
3. Extract **Error severity only** — skip Warning/Info
4. Filter out LOW_RISK patterns
5. Return up to 10 violations

## Config File

Lint waivers: `src/meta/tools/lint/waivers/<tile>_waivers.tcl` (varies by project)

---

## Output Storage

**MANDATORY — Write your JSON output to disk. Do NOT just return results as text.**

Write output file: `<base_dir>/data/<tag>_extractor_lint.json`

Use the Write tool:
```
Write file: <base_dir>/data/<tag>_extractor_lint.json
Content: <your JSON output>
```

The report compiler reads this file from disk. If you do not write it, the final report will be incomplete.
