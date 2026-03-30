# SpgDFT Violation Extractor Agent

**PERMISSIONS:** You have FULL READ ACCESS to all files under /proj/. Do not ask for permission - just read the files directly.

Extract **unfiltered ERROR** violations from the spec file written by the run script.

## Input
- `ref_dir`: Tree directory
- `ip`: IP name (umc9_3, oss7_2, gmc13_1a)
- `tag`: Task tag (e.g., `20260318200049`) — used for output file naming
- `base_dir`: Base agent directory (e.g., `/proj/.../main_agent`) — used for output file path

## Source of Truth — Spec File

The run script already determines which violations are filtered vs unfiltered. **Do NOT re-parse or re-filter moresimple.rpt.** Read the violations directly from the spec file.

### Step 1: Find the Spec File

Check in order:

1. **full_static_check** — `<base_dir>/data/<tag>_spg_dft_email.spec`
2. **Individual run** — `<base_dir>/data/<tag>_spec`

Use whichever exists. The individual run `<tag>_spec` and the full_static_check `<tag>_spg_dft_email.spec` have the same format.

### Step 2: Parse the Spec File

The spec file contains two key sections:

**Summary table** (after `#table#`):
```
Tiles,Total_Errors,Filtered_Errors(RSMU/DFT),Unfiltered_Errors(RSMU/DFT),Filtered_List,Logfile
umc_top,16,12,4,/proj/.../spg_dft_filtered_umc_top.txt,/proj/.../moresimple.rpt
```

Extract from this table:
- `report_path` = Logfile column (path to moresimple.rpt)
- `total_violations` = Total_Errors
- `rsmu_dft_skipped` = Filtered_Errors(RSMU/DFT)
- `focus_violations` = Unfiltered_Errors(RSMU/DFT)

**Unfiltered Error Details** section:
```
======================================================================
Unfiltered Error Details:
======================================================================
[<id>]   <rule>   [<alias>]   Error   <rtl_file>   <line>   <fanout>   <message>
...
```

Parse each violation line from this section. These are already the correct unfiltered violations — extract them all.

### Step 3: Parse Each Violation Line

Each line format:
```
[<id>]   <rule>   [<alias>]   Error   <rtl_file>   <line>   <fanout>   <message>
```

Extract:
- `id`: value inside `[...]` at start of line
- `rule`: first word after the id brackets
- `severity`: always `"Error"`
- `module`: extract from message (e.g., `[in 'umcsmn']` or from the signal path)
- `message`: full message text (last column)
- `signal_name`: extract from message text (signal name in quotes or after "port ")

## Output JSON

```json
{
  "report_path": "/proj/.../moresimple.rpt",
  "total_violations": "<total from summary table>",
  "rsmu_dft_skipped": "<filtered count from summary table>",
  "focus_violations": "<unfiltered count from summary table>",
  "violations_by_rule": {
    "<rule_name>": "<count>"
  },
  "top_violations": [
    {
      "id": "<id from report>",
      "rule": "<rule from report>",
      "severity": "Error",
      "module": "<module from message>",
      "message": "<full message from report>",
      "signal_name": "<signal extracted from message>"
    }
  ]
}
```

## Instructions

1. Find spec file: check `<base_dir>/data/<tag>_spg_dft_email.spec` first, then `<base_dir>/data/<tag>_spec`
2. Parse summary table: extract report_path, total_violations, rsmu_dft_skipped, focus_violations
3. Parse "Unfiltered Error Details:" section: extract all violation lines
4. For each violation line: extract id, rule, severity, module, message, signal_name
5. Build `violations_by_rule` count from the extracted violations
6. Write output JSON to disk

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
