# SpgDFT Violation Extractor Agent

**PERMISSIONS:** You have FULL READ ACCESS to all files under /proj/. Do not ask for permission - just read the files directly.

Extract **unfiltered ERROR** violations from the SpyGlass DFT report.

## Input
- `ref_dir`: Tree directory
- `ip`: IP name (umc9_3, oss7_2, gmc13_1a)
- `tag`: Task tag (e.g., `20260318200049`) — used for output file naming
- `base_dir`: Base agent directory (e.g., `/proj/.../main_agent`) — used for output file path

---

## Path Selection — Check Spec First

Before doing anything, check whether a spec file exists with a `#table#` section:

1. `<base_dir>/data/<tag>_spg_dft_email.spec`
2. `<base_dir>/data/<tag>_spec`

- **If either exists with `#table#`** → follow **Path A** (spec is authoritative)
- **If neither exists** (e.g., analyze-fixer launched without a prior run) → follow **Path B** (read directly from `moresimple.rpt`)

---

## Path A: Spec File Exists

### Step A1: Parse the Summary Table

Find the `#table#` section in the spec file:

```
Tiles,Total_Errors,Filtered_Errors(RSMU/DFT),Unfiltered_Errors(RSMU/DFT),Filtered_List,Logfile
umc_top,16,12,4,/proj/.../spg_dft_filtered_umc_top.txt,/proj/.../moresimple.rpt
```

Extract:
- `report_path` = `Logfile` column
- `total_violations` = `Total_Errors`
- `rsmu_dft_skipped` = `Filtered_Errors(RSMU/DFT)`
- `focus_violations` = `Unfiltered_Errors(RSMU/DFT)`

**These are the authoritative counts. Do NOT recount from the report file.**

### Step A2: Parse the Unfiltered Error Details Section

Look for:
```
======================================================================
Unfiltered Error Details:
======================================================================
```

Each violation line format:
```
[<id>]   <rule>   [<alias>]   Error   <rtl_file>   <line>   <fanout>   <message>
```

Extract all lines from this section. These are already the correct unfiltered violations.

For each line extract:
- `id`: value inside `[...]` at start of line
- `rule`: first word after the id brackets
- `severity`: always `"Error"`
- `module`: extract from message (e.g., `[in 'umcsmn']` or from signal path)
- `message`: full message text
- `signal_name`: extract from message (signal name in quotes or after "port ")

Then proceed to **Step 3: Build Output JSON**.

---

## Path B: No Spec File — Read Directly from moresimple.rpt

### Step B1: Find moresimple.rpt

Read `<base_dir>/config/IP_CONFIG.yaml` to resolve the report path without slow recursive globbing.

Detect IP family from `ip` name:
- Starts with `umc` → family = `umc`, default tile = `umc_top`
- Starts with `oss` → family = `oss`, default tile = `osssys`
- Starts with `gmc` → family = `gmc`, default tile = `gmc_w_phy`

Get `path_pattern` from `<family>.reports.spg_dft.path_pattern` in IP_CONFIG.yaml.
Substitute `{tile}` in the pattern with the default tile name (if no `{tile}` placeholder, use pattern as-is).

Run to find the most recently modified matching file:
```bash
ls -t <ref_dir>/<resolved_pattern> 2>/dev/null | head -1
```

Use the resulting path as `moresimple.rpt`. If no file found, report error and stop.

### Step B2: Read Filter Patterns

Read the filter file at:
```
<base_dir>/script/rtg_oss_feint/umc/spg_dft_error_filter.txt
```

The file has sections `[general]` and `[<ip_name>]`. Collect all regex patterns from:
- `[general]` section — applies to all IPs
- `[<ip>]` section matching the input `ip` name (case-insensitive)

Skip comment lines (starting with `#`) and empty lines.

### Step B3: Apply Filter — Same Logic as spg_dft_error_extract.pl

Read `moresimple.rpt`. For each line:

1. Skip lines that do NOT match `Error` or `ERROR` as a severity word (i.e., `\s+(Error|ERROR)\s+` must appear in the line — not just anywhere in the text)
2. For matching lines: check against every collected filter pattern
   - If the line matches **any** pattern → `filtered_errors++`, skip
   - If the line matches **none** → `unfiltered_errors++`, add to violations list

Compute:
- `total_violations` = `filtered_errors + unfiltered_errors`
- `rsmu_dft_skipped` = `filtered_errors`
- `focus_violations` = `unfiltered_errors`

`report_path` = path to `moresimple.rpt` found in Step B1.

### Step B4: Parse Each Unfiltered Violation Line

For each line in the unfiltered list, extract:
- `id`: value inside `[...]` at start of line
- `rule`: first word after the id brackets
- `severity`: `"Error"`
- `module`: extract from message (e.g., `[in 'umcsmn']` or from signal path)
- `message`: full message text
- `signal_name`: extract from message (signal name in quotes or after "port ")

Then proceed to **Step 3: Build Output JSON**.

---

## Step 3: Build Output JSON

```json
{
  "report_path": "<path to moresimple.rpt>",
  "total_violations": "<total Error lines>",
  "rsmu_dft_skipped": "<filtered count>",
  "focus_violations": "<unfiltered count>",
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

---

## Instructions Summary

**Path A (spec exists):**
1. Find spec file: check `<base_dir>/data/<tag>_spg_dft_email.spec` first, then `<base_dir>/data/<tag>_spec`
2. Parse summary table: extract report_path, total_violations, rsmu_dft_skipped, focus_violations
3. Parse "Unfiltered Error Details:" section: extract all violation lines
4. For each violation line: extract id, rule, severity, module, message, signal_name
5. Build `violations_by_rule` count from the extracted violations
6. Write output JSON to disk

**Path B (no spec):**
1. Glob for `moresimple.rpt` under `<ref_dir>/out/...`
2. Read filter patterns from `<base_dir>/script/rtg_oss_feint/umc/spg_dft_error_filter.txt` (`[general]` + `[<ip>]` sections)
3. For each `Error|ERROR` line in moresimple.rpt: apply filter patterns — matched → filtered, unmatched → unfiltered violations
4. For each unfiltered line: extract id, rule, severity, module, message, signal_name
5. Build `violations_by_rule` count from the extracted violations
6. Write output JSON to disk

---

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

---

## SELF-CHECK Before Finishing

Before ending your turn, verify:

1. **Did you write `data/<tag>_extractor_spgdft.json` using the Write tool?** → If not, do it now — do NOT finish without it
2. **Did you accidentally modify any source files?** → Wrong — this agent is read-only

Do NOT finish your turn until the output JSON is written to disk.
