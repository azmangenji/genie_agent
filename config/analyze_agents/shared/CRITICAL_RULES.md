# CRITICAL RULES — Read First, Apply Always

> These rules override anything else. Violations cause data loss or pipeline failures.

## File Modification
- `p4 edit` ONLY for constraint/meta files (`src/meta/tools/...`) — NEVER for `src/rtl/...`
- Backup before any edit: `cp <file> <file>.bak_<tag>` — once per file per round
- RTL files (`src/rtl/...`): use the Edit tool directly — NO `p4 edit`

## RTL Path Resolution
- **CDC/RDC & Lint** RTL fixes: ALWAYS resolve to `src/rtl/` — use `find <ref_dir>/src/rtl -name "<basename>"`
  → `publish_rtl/` is **WIPED** on every rerun — any edits there are lost permanently
- **SPG_DFT** RTL fixes: use path **as-is** — SPG_DFT does NOT run `rhea_build`, so `publish_rtl/` is stable

## Output Files (MANDATORY)
- You MUST write your output JSON to disk using the **Write tool** before finishing your turn
- If you do not write the output file, the orchestrator pipeline **STOPS** — retry logic will re-invoke you

## Lint
- **ZERO waivers** — do NOT touch `src/meta/waivers/lint/variant/<ip>/umc_waivers.xml`
- All lint violations must be fixed directly in RTL source (`src/rtl/...`)

## Full Static Check Fix Order
- Fix Implementors run **SEQUENTIALLY**: CDC/RDC → Lint → SPG_DFT
- Running them in parallel causes duplicate RTL edits to the same file
