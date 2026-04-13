# ECO Analyze Orchestrator Guide

**You are the ECO orchestrator agent.** The main Claude session has spawned you to execute the full ECO analyze flow. Your inputs (TAG, REF_DIR, TILE, LOG_FILE, SPEC_FILE) were passed in your prompt.

**Working directory:** Always `cd` to the directory containing `runs/` and `data/` (the BASE_DIR = parent of LOG_FILE's `runs/` folder) before any file operations.

---

## CRITICAL RULES

1. **No hardcoded signal names** — all net names come from RTL diff output
2. **Instance names, NOT module names** — hierarchy paths use instance names (e.g., `ARB`, `TIM`) not module names (`umcarb`, `umctim`)
3. **Study PreEco before touching PostEco** — always read PreEco netlist first to confirm cell+pin
4. **Single-occurrence rule** — if old_net appears >1 time on a pin in PostEco, skip and report AMBIGUOUS
5. **Backup always** — `cp PostEco/${stage}.v.gz PostEco/${stage}.v.gz.bak_${tag}` before any edit
6. **new_logic = report only** — do NOT auto-insert cells; only rewire existing connections
7. **Polarity rule** — only use `+` (non-inverted) impl nets for rewiring, never `-` (inverted)
8. **Bus dual-query** — for bus signals `reg [N:0] X`, query both `X` and `X_0_` to find gate-level name
9. **PostEco FM verification** — always run all 3 PostEco targets after applying ECO

---

## PRE-FLIGHT

Before any step:
1. `cd <BASE_DIR>` (parent of `runs/` folder from LOG_FILE)
2. `cd <REF_DIR>` to verify it exists
3. Confirm `data/PreEco/SynRtl/` and `data/SynRtl/` both exist
4. Return to BASE_DIR

---

## STEP 1 — RTL Diff Analysis

**Spawn a sub-agent (general-purpose)** with the content of `config/eco_agents/rtl_diff_analyzer.md` prepended to the prompt. Pass:
- `REF_DIR`, `TILE`, `TAG`, `BASE_DIR`
- Task: Run RTL diff, extract changed signals, determine nets to query, build verified hierarchy paths
- Output: `data/<TAG>_eco_rtl_diff.json`

Wait for the sub-agent to complete and read `data/<TAG>_eco_rtl_diff.json`.

---

## STEP 2 — Run find_equivalent_nets

Using the `nets_to_query` list from Step 1:

1. Build the comma-separated net list from all `net_path` entries in `nets_to_query`
2. Call the existing script directly:
   ```bash
   cd <BASE_DIR>
   tcsh -f script/rtg_oss_feint/supra/find_equivalent_nets.csh \
     "refDir:<REF_DIR>" \
     "<TAG>_fenets" \
     "target:" \
     "netName:<net1>,<net2>,..." \
     "tile:<TILE>"
   ```
   - `target:` (empty) defaults to all 3 PreEco FM targets
   - Poll `data/<TAG>_fenets_spec` every 2 minutes until `FIND_EQUIVALENT_NETS_COMPLETE` appears or 60-min timeout
3. Read all results from `data/<TAG>_fenets_spec`

### FM-036 Fallback Strategy

If any net returns `Error: Unknown name ... (FM-036)`:

1. **Try bus variant**: retry with `_0_` suffix (e.g., `SignalName` → `SignalName_0_`)
2. **Try parent hierarchy**: strip one level of hierarchy (e.g., `ARB/TIM/signal` → `ARB/signal`)
3. **Direct netlist grep**:
   ```bash
   zcat <REF_DIR>/data/PreEco/Synthesize.v.gz | grep -n "SignalName"
   ```
4. **Use RTL diff context**: search PreEco netlist by structural proximity from surrounding code
5. **Mark as fm_failed** and rely on Step 3 direct netlist study — do NOT abort the flow

---

## STEP 3 — Study PreEco Gate-Level Netlist

**Spawn a sub-agent (general-purpose)** with the content of `config/eco_agents/eco_netlist_studier.md` prepended. Pass:
- `REF_DIR`, `TAG`, `BASE_DIR`
- The find_equivalent_nets results (impl cell+pin names per stage)
- Task: For each impl cell in FM output, find instantiation in PreEco netlist, extract port connections, confirm old_net on expected pin
- Output: `data/<TAG>_eco_preeco_study.json`

Format of output:
```json
{
  "Synthesize": [
    {
      "cell_name": "<from FM output>",
      "pin": "<pin from FM output>",
      "old_net": "<from RTL diff>",
      "new_net": "<from RTL diff>",
      "line_context": "<surrounding verilog lines>",
      "confirmed": true
    }
  ],
  "PrePlace": [...],
  "Route": [...]
}
```

---

## STEP 4 — Apply ECO to PostEco Netlists

**Spawn a sub-agent (general-purpose)** with the content of `config/eco_agents/eco_applier.md` prepended. Pass:
- `REF_DIR`, `TAG`, `BASE_DIR`
- The PreEco study JSON from Step 3
- Task: For each confirmed cell, backup PostEco netlist, locate same cell, verify old_net on pin, replace with new_net, recompress, verify
- Output: `data/<TAG>_eco_applied.json`

Format of output:
```json
{
  "Synthesize": [
    {"cell_name": "...", "pin": "...", "old_net": "...", "new_net": "...", "status": "APPLIED"},
    {"cell_name": "...", "pin": "...", "old_net": "...", "new_net": "...", "status": "SKIPPED", "reason": "AMBIGUOUS"}
  ],
  "PrePlace": [...],
  "Route": [...]
}
```

---

## STEP 5 — PostEco Formality Verification

After PostEco netlists are updated, run the 3 PostEco FM targets:

```tcsh
cd <REF_DIR>
set curr_dir = `pwd | sed 's/\// /g' | awk '{print $NF}'`

foreach tgt (FmEqvEcoSynthesizeVsSynRtl FmEqvEcoPrePlaceVsEcoSynthesize FmEqvEcoRouteVsEcoPrePlace)
    TileBuilderTerm -x "serascmd -find_jobs 'name=~${tgt} dir=~${curr_dir}' --action reset"
    sleep 20
    TileBuilderTerm -x "serascmd -find_jobs 'name=~${tgt} dir=~${curr_dir}' --action run"
end
```

Poll status (180-min timeout, 15-min intervals):
```tcsh
TileBuilderTerm -x "TileBuilderShow >& /tmp/tb_eco_status_<TAG>.log"
grep "FmEqvEco" /tmp/tb_eco_status_<TAG>.log | awk '{print $1, $NF}'
```

Check results via `.dat` files in `rpts/<target>/`:
- `lecResult: SUCCEEDED` + `exitVal: 0` → PASS
- `lecResult: FAILED` or `numberOfNonEqPoints: > 0` → FAIL
- If FAIL: read `rpts/<target>/__failing_points.rpt.gz` for details

Write `data/<TAG>_eco_fm_verify.json`:
```json
{
  "FmEqvEcoSynthesizeVsSynRtl": "PASS",
  "FmEqvEcoPrePlaceVsEcoSynthesize": "PASS",
  "FmEqvEcoRouteVsEcoPrePlace": "PASS",
  "failing_points": []
}
```

---

## STEP 6 — Generate HTML Report

Write `data/<TAG>_eco_report.html` with sections:
1. **RTL Diff Summary** — files changed, change types, signals involved
2. **Net Analysis** — find_equivalent_nets results per net per stage
3. **PreEco Netlist Study** — confirmed cell/pin/context per stage
4. **ECO Actions Applied** — before/after, APPLIED vs SKIPPED with reasons
5. **PostEco FM Verification** — PASS/FAIL per target, failing points if any

---

## STEP 7 — Send Email

Read email recipients from `data/<TAG>_analysis_email` if it exists, otherwise use `assignment.csv` debugger field.

Send email with:
- Subject: `[ECO Analysis Complete] <TILE> @ <REF_DIR> (<TAG>)`
- Body: Summary of changes applied, FM verification results, link to HTML report path

---

## Output Files Summary

| File | Content |
|------|---------|
| `data/<TAG>_eco_rtl_diff.json` | RTL diff analysis + nets to query |
| `data/<TAG>_fenets_spec` | find_equivalent_nets results |
| `data/<TAG>_eco_preeco_study.json` | PreEco netlist confirmation |
| `data/<TAG>_eco_applied.json` | ECO changes applied/skipped |
| `data/<TAG>_eco_fm_verify.json` | PostEco FM verification |
| `data/<TAG>_eco_report.html` | Full HTML report |
