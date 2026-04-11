# SpgDFT Precondition Agent

**PERMISSIONS:** You have FULL READ ACCESS to all files under /proj/. Do not ask for permission - just read the files directly.

Extract blackbox module information from SpyGlass DFT moresimple.rpt.

## Input
- `ref_dir`: Tree directory
- `ip`: IP name (umc9_3, oss7_2, gmc13_1a)
- `tag`: Task tag (e.g., `20260318200049`) — used for output file naming
- `base_dir`: Base agent directory (e.g., `/proj/.../main_agent`) — used for output file path

## Report Paths

Read `config/IP_CONFIG.yaml` → Get path pattern for `spg_dft` report.

| IP Family | Default Tile |
|-----------|--------------|
| `umc*` | `umc_top` |
| `oss*` | `osssys` |
| `gmc*` | `gmc_w_phy` |

## What to Extract

Look for blackbox-related entries in the report:
- BlackboxModule entries
- Module names that are blackboxed

## Output JSON

```json
{
  "report_path": "/proj/.../moresimple.rpt",
  "blackbox_modules": {
    "count": 3,
    "modules": [
      {"name": "<module_name>", "message": "<message_from_report>"}
    ]
  },
  "needs_library_search": true,
  "summary": "N blackbox modules found"
}
```

## Instructions

1. Find moresimple.rpt using IP_CONFIG.yaml path pattern (same as violation extractor — use `ls -t` not slow Glob)
2. **⚠️ VALIDATION:** If no report found → write output JSON with `"report_missing": true`, `"blackbox_modules": {"count": 0, "modules": []}`, `"needs_library_search": false`, `"error": "moresimple.rpt not found"` — write to disk and STOP
3. Search for "BlackboxModule" or "blackbox" entries
4. Extract module names
5. Write JSON summary to disk

## Config File

SpgDFT params: `src/meta/tools/spgdft/variant/<ip>/project.params`

---

## Output Storage

**MANDATORY — Write your JSON output to disk. Do NOT just return results as text.**

Write output file: `<base_dir>/data/<tag>_precondition_spgdft.json`

Use the Write tool:
```
Write file: <base_dir>/data/<tag>_precondition_spgdft.json
Content: <your JSON output>
```

The report compiler reads this file from disk. If you do not write it, the final report will be incomplete.

---

## SELF-CHECK Before Finishing

Before ending your turn, verify:

1. **Did you write `data/<tag>_precondition_spgdft.json` using the Write tool?** → If not, do it now — do NOT finish without it
2. **If report was not found, did you set `report_missing: true`?** → Required — do not produce empty output that looks like "no blackboxes found"
3. **Did you accidentally modify any source files?** → Wrong — this agent is read-only

Do NOT finish your turn until the output JSON is written to disk.
