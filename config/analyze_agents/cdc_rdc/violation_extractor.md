# CDC/RDC Violation Extractor Agent

**PERMISSIONS:** You have FULL READ ACCESS to all files under /proj/. Do not ask for permission - just read the files directly.

Extract **ERROR severity** violations from CDC and RDC reports.

## Input
- `ref_dir`: Tree directory
- `ip`: IP name
- `check_type`: `cdc_rdc`, `cdc`, or `rdc`
- `tag`: Task tag (e.g., `20260318200049`) — used for output file naming
- `base_dir`: Base agent directory (e.g., `/proj/.../main_agent`) — used for output file path

## Violation Selection - COVER ALL BUCKETS

**Important:** Select violations to cover ALL violation types (buckets), not just pick from one bucket.

For each check (CDC, RDC):
1. First, group violations by type (bucket)
2. Select up to 2-3 violations PER bucket type
3. Total up to 10 violations per check, but distributed across ALL buckets

**Example:** If CDC has 3 violation types:
- `no_sync`: 100 violations → show 3-4 examples
- `series_redundant`: 5 violations → show 2-3 examples
- `reconvergence`: 2 violations → show 2 examples

This ensures coverage of ALL violation types in the analysis.

## Severity Filter

**ERROR only** — skip Warning/Caution/Info.

## Report Paths

Read `<base_dir>/config/IP_CONFIG.yaml` to resolve report paths without slow recursive globbing.

Detect IP family from `ip` name:
- Starts with `umc` → family = `umc`, default tile = `umc_top`
- Starts with `oss` → family = `oss`, default tile = `osssys`
- Starts with `gmc` → family = `gmc`, default tile = `gmc_gmcctrl_t`

For CDC report: get `<family>.reports.cdc.path_pattern`, substitute `{tile}` with default tile, then:
```bash
ls -t <ref_dir>/<resolved_cdc_pattern> 2>/dev/null | head -1
```

For RDC report: get `<family>.reports.rdc.path_pattern`, substitute `{tile}` with default tile, then:
```bash
ls -t <ref_dir>/<resolved_rdc_pattern> 2>/dev/null | head -1
```

If no `{tile}` placeholder exists in the pattern, use it as-is.
Use the resulting paths as the CDC and RDC report files.

## LOW_RISK Patterns to SKIP

Filter out violations where signal path contains (case-insensitive):
`rsmu`, `rdft`, `dft_`, `jtag`, `scan_`, `bist_`, `test_mode`, `sms_fuse`, `tdr_`

## What to Extract

Read the actual report and extract whatever fields exist. Common fields:
- Violation ID
- Violation type
- Severity
- Source signal path
- Destination signal path
- Clock domains (if present in report)
- Module name
- Message

**Do NOT assume any specific violation types or clock names. Extract what the report contains.**

## Instructions

1. Find reports using IP_CONFIG.yaml (see Report Paths above)
2. Read CDC Section 3 (CDC Results) and RDC Section 5 (RDC Results)
3. Parse the violation table - extract whatever columns exist
4. Filter LOW_RISK patterns
5. **Group by violation type first** (bucket)
6. **Select 2-3 violations from EACH bucket** (cover all types)
7. Total up to 10 violations per check, distributed across all buckets
8. Group by clock domain pairs (whatever domains exist in report)

## Output

Return JSON with:
- Report paths found
- Total violation counts per bucket
- Filtered counts per bucket
- Violations grouped by type (bucket)
- Violations grouped by clock pair (extract from report)
- Selected violations: 2-3 per bucket, covering ALL violation types

## Config File

Constraints: `src/meta/tools/cdc0in/variant/<ip>/project.0in_ctrl.v.tcl`

---

## Output Storage

**MANDATORY — Write your JSON output to disk. Do NOT just return results as text.**

Write output file: `<base_dir>/data/<tag>_extractor_cdc.json`

Use the Write tool:
```
Write file: <base_dir>/data/<tag>_extractor_cdc.json
Content: <your JSON output>
```

The report compiler reads this file from disk. If you do not write it, the final report will be incomplete.

---

## Reference Documentation

For CDC/RDC violation types, schemes, and severity definitions:

**`docs/Questa_CDC_RDC_Complete_Reference.md`**

- CDC violation types (no_sync, multi_bits, combo_logic, DMUX, reconvergence)
- RDC domain crossing schemes (rdc_areset, rdc_dff, rdc_isolation_*, rdc_ordered, etc.)
- Reset tree check types (reset_as_data, reset_unresettable_register, nrr_on_reset_path, etc.)

---

## SELF-CHECK Before Finishing

Before ending your turn, verify:

1. **Did you write `data/<tag>_extractor_cdc.json` using the Write tool?** → If not, do it now — do NOT finish without it
2. Did you extract violations from BOTH CDC and RDC reports (when check_type is cdc_rdc)?

Do NOT finish your turn until the output JSON is written to disk.
- Result categories (Violations, Cautions, Evaluations, Proven, Waived)
