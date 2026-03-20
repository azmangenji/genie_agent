# SpgDFT Violation Extractor Agent

**PERMISSIONS:** You have FULL READ ACCESS to all files under /proj/. Do not ask for permission - just read the files directly.

Extract **ERROR severity** violations from SpyGlass DFT moresimple.rpt.

## Input
- `ref_dir`: Tree directory
- `ip`: IP name (umc9_3, oss7_2, gmc13_1a)
- `tag`: Task tag (e.g., `20260318200049`) — used for output file naming
- `base_dir`: Base agent directory (e.g., `/proj/.../main_agent`) — used for output file path

## Severity Filter

**ERROR only** — skip Warning/Info.

## Report Paths

Read `config/IP_CONFIG.yaml` → Get path pattern for `spg_dft` report.

| IP Family | Default Tile |
|-----------|--------------|
| `umc*` | `umc_top` |
| `oss*` | `osssys` |
| `gmc*` | `gmc_w_phy` |

## LOW_RISK Patterns to SKIP

Filter out violations where module or signal contains (case-insensitive):
`rsmu`, `rdft`, `dft_`, `jtag`, `scan_`, `bist_`, `test_mode`, `tdr_`

## What to Extract

For each **Error** severity violation:
- `id`: Entry ID from report
- `rule`: DFT rule name from report
- `severity`: Error
- `module`: Affected module
- `message`: Error message
- `signal_name`: Extracted from message

## Output JSON

```json
{
  "report_path": "/proj/.../moresimple.rpt",
  "total_violations": 85,
  "rsmu_dft_skipped": 60,
  "focus_violations": 25,
  "violations_by_rule": {
    "<rule_from_report>": 12
  },
  "top_violations": [
    {
      "id": "<id_from_report>",
      "rule": "<rule_from_report>",
      "severity": "Error",
      "module": "<module_name>",
      "message": "<message_from_report>",
      "signal_name": "<extracted_signal>"
    }
  ]
}
```

## Instructions

1. Find moresimple.rpt using Glob
2. Parse violation entries
3. Extract **Error severity only** — skip Warning/Info
4. Skip BlackboxModule entries (handled by precondition agent)
5. Filter out LOW_RISK patterns
6. Return up to 10 violations

## Config File

SpgDFT params: `src/meta/tools/spgdft/variant/<ip>/project.params`

---

## Output Storage

**MANDATORY — Write your JSON output to disk. Do NOT just return results as text.**

Write output file: `<base_dir>/data/<tag>_extractor_spgdft.json`

Use the Write tool:
```
Write file: <base_dir>/data/<tag>_extractor_spgdft.json
Content: <your JSON output>
```

The report compiler reads this file from disk. If you do not write it, the final report will be incomplete.
