# Lint Violation Extractor Agent

**PERMISSIONS:** You have FULL READ ACCESS to all files under /proj/. Do not ask for permission - just read the files directly.

Extract lint violations and counts.

## Input
- `ref_dir`: Tree directory
- `ip`: IP name
- `tag`: Task tag — used for output file naming
- `base_dir`: Base agent directory — used for output file path

---

## Path Selection — Read Spec First

Before doing anything, check whether `<base_dir>/data/<tag>_spec` exists AND contains a `#table#` section:

- **If YES** → follow **Path A** (spec file is authoritative — do NOT re-read the log file)
- **If NO** (no spec, or spec has no `#table#`) → follow **Path B** (read directly from `leda_waiver.log`)

---

## Path A: Spec File Exists

### Step A1: Read Counts from Spec File (AUTHORITATIVE)

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

### Step A2: Read Violation Details from Spec File

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

Then proceed to **Step 3: Group by RTL File**.

---

## Path B: No Spec File — Read Directly from leda_waiver.log

Used when no spec file exists (e.g., analyze-fixer launched without a prior lint run).

### Step B1: Find leda_waiver.log

Read `<base_dir>/config/IP_CONFIG.yaml` to resolve the report path without slow recursive globbing.

Detect IP family from `ip` name:
- Starts with `umc` → family = `umc`, default tile = `umc_top`
- Starts with `oss` → family = `oss`, default tile = `osssys`
- Starts with `gmc` → family = `gmc`, default tile = `gmc_gmcctrl_t`

Get `path_pattern` from `<family>.reports.lint.path_pattern` in IP_CONFIG.yaml.
Substitute `{tile}` in the pattern with the default tile name (if no `{tile}` placeholder, use pattern as-is).

Run to find the most recently modified matching file:
```bash
ls -t <ref_dir>/<resolved_pattern> 2>/dev/null | head -1
```

Use the resulting path as `leda_waiver.log`.

**⚠️ REPORT MISSING HANDLING — CRITICAL:**
If no file found (empty output from ls):
- Do NOT proceed with empty data — that would produce `focus_violations: 0` which looks like CLEAN
- Write output JSON with `"report_missing": true`, `"focus_violations": 0`, `"total_unwaived": 0`, `"report_path": null`
- Include a `"note": "leda_waiver.log not found — check did not complete or path pattern is wrong"`
- Write this JSON to disk and STOP — do not attempt to parse a missing file

### Step B2: Parse the Unwaived Section

Read the file. Look for the section marker:

```
Unwaived
```

Once inside the Unwaived section, collect every line that matches the pipe-separated format with a digit line number:

```
| <code> | <error> | <type> | <filename> | <line_number> | <message> |
```

A valid violation line has `| <digits> |` somewhere in it. Lines with only dashes or wildcards (`.*`) are not violations — skip them.

Stop collecting when you hit `Unused Waivers` or `Waived` section markers.

### Step B3: Apply RSMU/DFT Filter (same logic as lint_error_extract.pl)

For each collected violation line, parse fields from right to left:
1. Last field → `message`
2. Second to last → `line_number`
3. Third to last → `filename`
4. Fourth to last → `type`
5. Fifth to last → `error`
6. Everything remaining → `code` (joined if split across pipes)

**Filter rule — identical to lint_error_extract.pl line 82:**

```
if filename matches /rsmu|dft/ (case-insensitive):
    filtered_count++
    skip — do NOT add to violations list
else:
    unfiltered violations list
```

Compute counts:
- `total_unwaived` = all valid pipe-separated digit lines in Unwaived section
- `filtered_count` = count where filename matches `rsmu` or `dft` (case-insensitive)
- `focus_violations` = `total_unwaived - filtered_count`

### Step B4: Get Report Path

`report_path` = the leda_waiver.log path found in Step B1.

Then proceed to **Step 3: Group by RTL File**.

---

## Step 3: Group by RTL File

Group all extracted violations (from Path A or Path B) by their RTL filename into `violations_by_file`.

If the filename is a basename only, resolve the full path by globbing under `<ref_dir>/src/rtl/`.

---

## Step 4: Build Output JSON

```json
{
  "report_path": "<path to leda_waiver.log or null if missing>",
  "report_missing": false,
  "spec_file": "<base_dir>/data/<tag>_spec",
  "total_unwaived": 0,
  "filtered_count": 0,
  "focus_violations": 0,
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

**`focus_violations` MUST equal `total_unwaived - filtered_count` — never adjust it.**
**All count fields (`total_unwaived`, `filtered_count`, `focus_violations`, `unique_files`) MUST be integers, not strings.**
**`report_missing` MUST be `false` (boolean) for successful reads, `true` only when report file was not found.**

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

---

## SELF-CHECK Before Finishing

Before ending your turn, verify:

1. **Did you write `data/<tag>_extractor_lint.json` using the Write tool?** → If not, do it now — do NOT finish without it
2. **Did you accidentally add waiver entries?** → Wrong — lint extractors are read-only, no file modifications

Do NOT finish your turn until the output JSON is written to disk.
