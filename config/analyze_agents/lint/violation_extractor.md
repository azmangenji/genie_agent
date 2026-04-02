# Lint Violation Extractor Agent

**PERMISSIONS:** You have FULL READ ACCESS to all files under /proj/. Do not ask for permission - just read the files directly.

Extract lint violations and counts. **Counts come from the spec file — NOT from re-filtering the report.**

## Input
- `ref_dir`: Tree directory
- `ip`: IP name
- `tag`: Task tag — used for output file naming
- `base_dir`: Base agent directory — used for output file path

---

## Step 1: Read Counts from Spec File (AUTHORITATIVE)

Read: `<base_dir>/data/<tag>_spec`

Find the `#table#` section. It contains a header row followed by data rows with per-tile violation counts. The column names tell you what each value means — read them dynamically:

```
#table#
<col1>,<col2>,<col3>,...,<colN>
<tile>,<val1>,<val2>,...,<valN>
#table end#
```

Identify these columns by name (exact names may vary by IP/tool version):
- **Total unwaived** — column named `Unwaived` (or similar)
- **Filtered count** — column named `Filtered_RSMU/DFT` or `Filtered` (violations already removed by the tool)
- **Focus violations** — column named `Unfiltered_RSMU/DFT` or `Unfiltered` (violations remaining for analysis)
- **Report path** — column named `Logfile` (path to the full lint report file)

Extract these values from the data row(s). Sum across all tiles if multiple rows exist.

**These are the authoritative counts. Do NOT recount or recompute them from the report file.**

---

## Step 2: Read Violation Details from Spec File

The spec file contains a pre-filtered violation detail section — look for a header like:

```
<Tool> Unwaived Violation Details for <tile>:
```

This section lists ONLY the violations that passed the tool's own filter. Read the column header row to understand the fields, then extract each violation row:

- `code`: the lint rule code (column typically named `Code` or `Type`)
- `severity`: `Error`
- `filename`: RTL filename (column typically named `Filename`)
- `line`: line number (column typically named `Line`)
- `message`: violation message (column typically named `Message`)
- `signal_name`: extract from the message — typically the signal or variable name being flagged

**Do NOT apply any additional filtering — the tool already filtered the violations correctly.**

---

## Step 3: Group by RTL File

Group all extracted violations by their RTL filename into `violations_by_file`.

If the filename is a basename only, resolve the full path by globbing under `<ref_dir>/src/rtl/`.

---

## Step 4: Build Output JSON

```json
{
  "report_path": "<path from Logfile column>",
  "spec_file": "<base_dir>/data/<tag>_spec",
  "total_unwaived": "<Unwaived column value>",
  "filtered_count": "<Filtered column value>",
  "focus_violations": "<Unfiltered column value>",
  "unique_files": "<count of unique RTL files>",
  "violations_by_code": {
    "<rule_code_1>": "<count>",
    "<rule_code_2>": "<count>"
  },
  "violations_by_file": {
    "<rtl_file_path>": [
      {
        "code": "<rule code>",
        "severity": "Error",
        "line": "<line number>",
        "message": "<violation message>",
        "signal_name": "<signal or variable name>"
      }
    ]
  }
}
```

**`focus_violations` MUST match the Unfiltered column value from the spec file — never adjust it.**

---

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

The orchestrator reads `violations_by_file` to spawn one RTL analyzer agent per unique RTL file, and reads `focus_violations` / `total_unwaived` / `filtered_count` for the round report. If you do not write the file, no analysis will run.
