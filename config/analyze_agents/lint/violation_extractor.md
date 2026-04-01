# Lint Violation Extractor Agent

**PERMISSIONS:** You have FULL READ ACCESS to all files under /proj/. Do not ask for permission - just read the files directly.

Extract **ERROR severity** unwaived lint violations — **ALL of them, grouped by RTL file**.

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
- `filename`: RTL file path (full path)
- `line`: Line number
- `message`: Error message
- `signal_name`: Extracted from message

**Extract ALL violations — no cap. Then group them by RTL filename.**

## Output JSON

```json
{
  "report_path": "/proj/.../leda_waiver.log",
  "total_unwaived": 152,
  "rsmu_dft_skipped": 30,
  "focus_violations": 122,
  "unique_files": 15,
  "violations_by_code": {
    "W_UNDRIVEN": 80,
    "W_UNUSED": 42
  },
  "violations_by_file": {
    "src/rtl/umcdat/umcdat_core.sv": [
      {
        "code": "W_UNDRIVEN",
        "severity": "Error",
        "line": 45,
        "message": "<message from report>",
        "signal_name": "<extracted signal>"
      },
      {
        "code": "W_UNDRIVEN",
        "severity": "Error",
        "line": 226,
        "message": "<message from report>",
        "signal_name": "<extracted signal>"
      }
    ],
    "src/rtl/umccmd/umccmd_ctrl.sv": [
      {
        "code": "W_UNUSED",
        "severity": "Error",
        "line": 88,
        "message": "<message from report>",
        "signal_name": "<extracted signal>"
      }
    ]
  }
}
```

## Instructions

1. Find report using Glob (`leda_waiver.log` for UMC/GMC, `spyglass_lint.txt` for OSS)
2. Find "Unwaived" section
3. Extract **Error severity only** — skip Warning/Info
4. Filter out LOW_RISK patterns
5. Extract **ALL remaining violations** — no limit
6. Group violations by RTL filename into `violations_by_file`
7. Count unique files

## Waiver File (reference only)

Path: `<ref_dir>/src/meta/waivers/lint/variant/<ip>/umc_waivers.xml`

---

## Output Storage

**MANDATORY — Write your JSON output to disk. Do NOT just return results as text.**

Write output file: `<base_dir>/data/<tag>_extractor_lint.json`

Use the Write tool:
```
Write file: <base_dir>/data/<tag>_extractor_lint.json
Content: <your JSON output>
```

The orchestrator reads `violations_by_file` to spawn one RTL analyzer agent per unique RTL file. If you do not write the file, no analysis will run.
