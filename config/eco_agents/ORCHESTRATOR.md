# ECO Analyze Orchestrator Guide

**You are the ECO orchestrator agent.** The main Claude session has spawned you to execute the full ECO analyze flow. Your inputs (TAG, REF_DIR, TILE, LOG_FILE, SPEC_FILE) were passed in your prompt.

**Working directory:** Always `cd` to the directory containing `runs/` and `data/` (the BASE_DIR = parent of LOG_FILE's `runs/` folder) before any file operations.

**Inputs also include JIRA number** — used for naming new_logic ECO cells: `eco_<jira>_<seq>` and nets: `n_eco_<jira>_<seq>`.

---

## CRITICAL RULES

1. **No hardcoded signal names** — all net names come from RTL diff output
2. **Instance names, NOT module names** — hierarchy paths use instance names (e.g., `INST_A`, `INST_B`) not module names (`module_a`, `module_b`)
3. **Study PreEco before touching PostEco** — always read PreEco netlist first to confirm cell+pin
4. **Single-occurrence rule** — if old_net appears >1 time on a pin in PostEco, skip and report AMBIGUOUS
5. **Backup always** — `cp PostEco/${stage}.v.gz PostEco/${stage}.v.gz.bak_${tag}_round${round}` before any edit (round-specific backup so each round can be independently reverted)
6. **new_logic = auto-insert inverter** — when new_net doesn't exist in PostEco, auto-insert a new inverter cell (see eco_applier.md Step 4c); follow with eco_svf_updater to register the cell in EcoChange.svf
7. **Polarity rule** — only use `+` (non-inverted) impl nets for rewiring, never `-` (inverted); for inverted signals use new_logic insert
8. **Bus dual-query** — for bus signals `reg [N:0] X`, query both `X` and `X_0_` to find gate-level name
9. **PostEco FM verification** — always run all 3 PostEco targets after applying ECO
10. **5-round fix loop** — if FM fails, revert → analyze → apply revised strategy → rerun FM; max 5 rounds
11. **Same instance name across all stages** — new_logic cells must use identical instance names in Synthesize, PrePlace, and Route for FM stage-to-stage matching

---

## PRE-FLIGHT

Before any step:
1. `cd <BASE_DIR>` (parent of `runs/` folder from LOG_FILE)
2. `cd <REF_DIR>` to verify it exists
3. Confirm `data/PreEco/SynRtl/` and `data/SynRtl/` both exist
4. Return to BASE_DIR
5. Write `data/<TAG>_eco_analyze` metadata file:
   ```
   tile=<TILE>
   ref_dir=<REF_DIR>
   tag=<TAG>
   jira=<JIRA>
   ```

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
2. Submit via `genie_cli.py` with `--xterm` (live output in popup window, correct TileBuilder/LSF environment):
   ```bash
   cd <BASE_DIR>
   python3 script/genie_cli.py \
     -i "find equivalent nets at <REF_DIR> for <TILE> netName:<net1>,<net2>,..." \
     --execute --xterm
   ```
   This matches the `find_equivalent_nets.csh` instruction in `instruction.csv`. Note the tag generated will be different from `<TAG>` — read it from the CLI output (`Tag: <fenets_tag>`).
3. Poll the actual rpt files every 2 minutes until `FIND_EQUIVALENT_NETS_COMPLETE` appears in all 3, or 60-min timeout:
   ```bash
   grep -c "FIND_EQUIVALENT_NETS_COMPLETE" \
     <REF_DIR>/rpts/FmEqvPreEcoSynthesizeVsPreEcoSynRtl/find_equivalent_nets_<fenets_tag>.txt \
     <REF_DIR>/rpts/FmEqvPreEcoPrePlaceVsPreEcoSynthesize/find_equivalent_nets_<fenets_tag>.txt \
     <REF_DIR>/rpts/FmEqvPreEcoRouteVsPreEcoPrePlace/find_equivalent_nets_<fenets_tag>.txt
   ```
   **Note:** Do NOT poll `data/<fenets_tag>_spec` for this sentinel — `find_equivalent_nets.csh` strips it before writing to the spec file. The rpt files are the authoritative source.
4. Once all 3 rpt files have the sentinel, read all results from `data/<fenets_tag>_spec` (the spec file has the formatted results written at task completion)
5. Consolidate raw FM output into a single file `<BASE_DIR>/data/<fenets_tag>_find_equivalent_nets_raw.rpt` by concatenating all 3 rpt files with clear stage headers:
   ```bash
   {
     echo "================================================================================"
     echo "FIND EQUIVALENT NETS — RAW FM OUTPUT"
     echo "fenets_tag: <fenets_tag>  |  TAG: <TAG>  |  Tile: <TILE>"
     echo "================================================================================"
     echo ""
     echo "================================================================================"
     echo "TARGET: FmEqvPreEcoSynthesizeVsPreEcoSynRtl"
     echo "================================================================================"
     cat <REF_DIR>/rpts/FmEqvPreEcoSynthesizeVsPreEcoSynRtl/find_equivalent_nets_<fenets_tag>.txt
     echo ""
     echo "================================================================================"
     echo "TARGET: FmEqvPreEcoPrePlaceVsPreEcoSynthesize"
     echo "================================================================================"
     cat <REF_DIR>/rpts/FmEqvPreEcoPrePlaceVsPreEcoSynthesize/find_equivalent_nets_<fenets_tag>.txt
     echo ""
     echo "================================================================================"
     echo "TARGET: FmEqvPreEcoRouteVsPreEcoPrePlace"
     echo "================================================================================"
     cat <REF_DIR>/rpts/FmEqvPreEcoRouteVsPreEcoPrePlace/find_equivalent_nets_<fenets_tag>.txt
   } > <BASE_DIR>/data/<fenets_tag>_find_equivalent_nets_raw.rpt
   ```
   Do the same for each FM-036 retry tag — write `<BASE_DIR>/data/<retry_tag>_find_equivalent_nets_raw.rpt` using the same pattern.

**For FM-036 retries**, submit a new genie_cli.py call with the stripped net path — each retry gets its own tag, read from CLI output:
   ```bash
   python3 script/genie_cli.py \
     -i "find equivalent nets at <REF_DIR> for <TILE> netName:<stripped_net_path>" \
     --execute --xterm
   ```

### FM-036 Fallback Strategy

If any net returns `Error: Unknown name ... (FM-036)`:

1. **Bus variant already pre-queried** — the rtl_diff_analyzer sends both `X` and `X_0_` upfront, so the result is already in the same run. Check the other variant's result before doing anything else.

2. **Retry find_equivalent_nets with parent hierarchy** — strip one level from the failing net path and submit a new genie_cli.py call:
   ```bash
   # Original failed: <PARENT_INST>/<CHILD_INST>/<net>
   # Retry with:      <PARENT_INST>/<net>
   python3 script/genie_cli.py \
     -i "find equivalent nets at <REF_DIR> for <TILE> netName:<stripped_net_path>" \
     --execute --xterm
   ```
   Read the new tag from CLI output. Poll the rpt files (NOT the spec file) for the sentinel, same as the main run:
   ```bash
   grep -c "FIND_EQUIVALENT_NETS_COMPLETE" \
     <REF_DIR>/rpts/FmEqvPreEcoSynthesizeVsPreEcoSynRtl/find_equivalent_nets_<retry_tag>.txt \
     <REF_DIR>/rpts/FmEqvPreEcoPrePlaceVsPreEcoSynthesize/find_equivalent_nets_<retry_tag>.txt \
     <REF_DIR>/rpts/FmEqvPreEcoRouteVsPreEcoPrePlace/find_equivalent_nets_<retry_tag>.txt
   ```
   Once all 3 rpt files have the sentinel, read results from `<BASE_DIR>/data/<retry_tag>_spec`.

   **Retry loop rules:**
   - Max **3 retries** (`_retry1`, `_retry2`, `_retry3`)
   - Stop early if the net path has no more `/` — there is no parent level left to try
   - Each retry strips one more hierarchy level from the previous attempt's path
   - If any retry returns a valid impl cell+pin → use it and stop retrying. FM gives the exact gate-level cell name and pin, which is more reliable than grep.

3. **Direct netlist grep** — only if FM retry also fails or times out:
   ```bash
   zcat <REF_DIR>/data/PreEco/Synthesize.v.gz | grep -n "<net_token>"
   ```
   `<net_token>` is the signal name extracted from the failing net path. This finds what it is called in gate-level (may have `_reg` suffix or synthesis renaming).

4. **Use RTL diff context** — if grep finds no match, search by structural proximity (surrounding expression from the diff hunk) to identify the relevant cell.

5. **Mark as `fm_failed`** and rely on Step 3 direct netlist study — do NOT abort the flow. A single failed net does not stop the whole ECO.

---

## STEP 3 — Study PreEco Gate-Level Netlist

**Spawn a sub-agent (general-purpose)** with the content of `config/eco_agents/eco_netlist_studier.md` prepended. Pass:
- `REF_DIR`, `TAG`, `BASE_DIR`
- The exact path to the find_equivalent_nets results: `<BASE_DIR>/data/<fenets_tag>_spec` (use the `<fenets_tag>` read from the genie_cli.py output in Step 2, NOT the main `<TAG>`)
- The RTL diff JSON at `<BASE_DIR>/data/<TAG>_eco_rtl_diff.json` (provides old_net/new_net per change)
- Task: For each impl cell in FM output, find instantiation in PreEco netlist, extract port connections, confirm old_net on expected pin
- Output: `<BASE_DIR>/data/<TAG>_eco_preeco_study.json`

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
- `REF_DIR`, `TAG`, `BASE_DIR`, `JIRA`, `ROUND` (current round number — 1 for initial run, 2/3/... for fixer loop)
- The PreEco study JSON from Step 3
- Task: For each confirmed cell, backup PostEco netlist (using `bak_<TAG>_round<ROUND>` naming), locate same cell, verify old_net on pin, replace with new_net (rewire) or auto-insert inverter (new_logic), recompress, verify
- Output: `<BASE_DIR>/data/<TAG>_eco_applied.json`

Wait for eco_applier sub-agent to complete.

---

## STEP 4b — SVF Entries for new_logic Insertions

Read `data/<TAG>_eco_applied.json`. Check if any entry has `"change_type": "new_logic"` and `"status": "INSERTED"`.

If yes — **spawn a sub-agent (general-purpose)** with the content of `config/eco_agents/eco_svf_updater.md` prepended. Pass:
- `REF_DIR`, `TAG`, `BASE_DIR`, `JIRA`
- Task: Write `eco_change -type insert_cell` entries to `<BASE_DIR>/data/<TAG>_eco_svf_entries.tcl` (do NOT append to EcoChange.svf yet — FmEcoSvfGen will regenerate it and must run first)
- Output: `<BASE_DIR>/data/<TAG>_eco_svf_update.json` + `<BASE_DIR>/data/<TAG>_eco_svf_entries.tcl`

Set `svf_update_needed = true` for use in Step 5.

If no new_logic insertions: set `svf_update_needed = false`, skip Step 4b.

---

## STEP 5 — PostEco Formality Verification

**Guard:** Read `data/<TAG>_eco_applied.json` and check `summary.applied + summary.inserted`. If both are 0, skip this step and Step 6 entirely — go directly to Step 8. Write `data/<TAG>_eco_fm_verify.json` with `"skipped": true, "reason": "no changes applied"` and note this in the HTML report.

### Step 5a — Write FM config file

Write to `<REF_DIR>/data/eco_fm_config` — **fixed filename inside refDir** (NOT tag-based). This is critical: `post_eco_formality.csh` gets its own new tag from genie_cli and uses refDir to find this file, so the filename must NOT include the ECO TAG.

**Initial run (round 1 — all targets):**
```bash
cat > <REF_DIR>/data/eco_fm_config << EOF
ECO_TARGETS=FmEqvEcoSynthesizeVsSynRtl FmEqvEcoPrePlaceVsEcoSynthesize FmEqvEcoRouteVsEcoPrePlace
RUN_SVF_GEN=<1 if svf_update_needed else 0>
ECO_SVF_ENTRIES=<BASE_DIR>/data/<TAG>_eco_svf_entries.tcl
EOF
```

**Subsequent rounds (only failing targets):**
```bash
cat > <REF_DIR>/data/eco_fm_config << EOF
ECO_TARGETS=<space-separated list of failing targets from previous round>
RUN_SVF_GEN=<1 if FmEqvEcoSynthesizeVsSynRtl is in failing list AND svf_update_needed else 0>
ECO_SVF_ENTRIES=<BASE_DIR>/data/<TAG>_eco_svf_entries.tcl
EOF
```

**Key rule:** `RUN_SVF_GEN=1` only when BOTH:
1. `FmEqvEcoSynthesizeVsSynRtl` is in the targets list, AND
2. `svf_update_needed = true` (new_logic cells were inserted)

### Step 5b — Run PostEco FM

```bash
cd <BASE_DIR>
python3 script/genie_cli.py \
  -i "run post eco formality at <REF_DIR> for <TILE>" \
  --execute --xterm
```

The script reads `<REF_DIR>/data/eco_fm_config` automatically (fixed filename, not tag-based). When `RUN_SVF_GEN=1`, it:
1. Resets + runs `FmEcoSvfGen` first (60-min timeout)
2. Appends `ECO_SVF_ENTRIES` to `data/svf/EcoChange.svf` after FmEcoSvfGen completes
3. Resets + runs only the specified `ECO_TARGETS`
4. Polls until all targets complete (180-min timeout)

Read the tag from the CLI output (`Tag: <eco_fm_tag>`). **Save `eco_fm_tag` to `eco_fixer_state` immediately** — it's needed later for eco_fm_analyzer. Poll `<BASE_DIR>/data/<eco_fm_tag>_spec` every 5 minutes until it contains `OVERALL ECO FM RESULT:`.

Parse results. For round 1, write all 3 targets. For subsequent rounds, **merge with previous round's results** — carry forward PASS results from earlier rounds, update only the re-run targets:

```python
# Pseudo-code: merge FM results
cumulative = load previous _eco_fm_verify.json (or start with all "NOT_RUN")
for each target in ECO_TARGETS:
    cumulative[target] = new result (PASS or FAIL)
# targets NOT in ECO_TARGETS keep their previous result
```

Write merged results to `<BASE_DIR>/data/<TAG>_eco_fm_verify.json`:
```json
{
  "FmEqvEcoSynthesizeVsSynRtl": "PASS",
  "FmEqvEcoPrePlaceVsEcoSynthesize": "PASS",
  "FmEqvEcoRouteVsEcoPrePlace": "PASS",
  "failing_points": [],
  "round": 1,
  "eco_fm_tag": "<eco_fm_tag>"
}
```

**OVERALL PASS** = all 3 targets show PASS in the merged JSON.

---

## STEP 6 — Evaluate FM Result and 5-Round Fix Loop

Read `<BASE_DIR>/data/<TAG>_eco_fm_verify.json`. Check if all 3 targets PASS.

### If ALL PASS → go to Step 7 (HTML report)

### If ANY FAIL → enter fix loop

Read or initialize `<BASE_DIR>/data/<TAG>_eco_fixer_state`:
```json
{
  "round": 1,
  "tag": "<TAG>",
  "tile": "<TILE>",
  "ref_dir": "<REF_DIR>",
  "jira": "<JIRA>",
  "max_rounds": 5,
  "strategies_tried": [],
  "fm_results_per_round": [
    {
      "round": 1,
      "eco_fm_tag": "<eco_fm_tag from Step 5b>",
      "failing_targets": ["FmEqvEcoSynthesizeVsSynRtl"],
      "failing_count": 5
    }
  ]
}
```

Save `eco_fm_tag` from Step 5b into `fm_results_per_round` immediately — it is required by eco_fm_analyzer in Step 6d.

#### If round < 5:

**Step 6a — Write per-round HTML and send email:**

First write a compact per-round HTML `<BASE_DIR>/data/<TAG>_eco_report_round<N>.html` covering:
- Round N summary: which targets failed, failing point count per target
- ECO changes attempted this round: cell name, pin, old_net → new_net, status (APPLIED/INSERTED/SKIPPED)
- FM failing points detail: hierarchy paths of failing DFFs
- What will be tried next round (from eco_fm_analyzer if available, else "analyzing...")

Then send:
```bash
cd <BASE_DIR>
python3 script/genie_cli.py --send-eco-email <TAG> --eco-round <round>
```

**Step 6b — Revert PostEco netlists:**

Restore from round-specific backup. Only revert stages that were actually backed up (eco_applier may have skipped a stage if it had no confirmed cells — check file existence first):

```bash
for stage in Synthesize PrePlace Route:
    bak = <REF_DIR>/data/PostEco/<Stage>.v.gz.bak_<TAG>_round<N>
    if bak exists:
        cp bak <REF_DIR>/data/PostEco/<Stage>.v.gz
    else:
        # Stage was skipped in eco_applier — nothing to revert
        print("No backup for <Stage> round <N> — skipping revert")
```

**Step 6c — Clean up SVF entries for next round:**

EcoChange.svf does NOT need reverting — FmEcoSvfGen regenerates it from scratch at the start of each round where `RUN_SVF_GEN=1`. No backup of EcoChange.svf is created or needed.

Only delete the old TCL entries file so the next round's eco_svf_updater writes fresh entries:
```bash
rm -f <BASE_DIR>/data/<TAG>_eco_svf_entries.tcl
```

**Step 6d — Analyze FM failure and get revised strategy:**
**Spawn a sub-agent (general-purpose)** with the content of `config/eco_agents/eco_fm_analyzer.md` prepended. Pass:
- `REF_DIR`, `TAG`, `BASE_DIR`, `ROUND=<round>`
- `eco_fm_tag` — read from `eco_fixer_state.fm_results_per_round[round-1].eco_fm_tag`
- Path to FM spec: `<BASE_DIR>/data/<eco_fm_tag>_spec`
- Path to applied JSON: `<BASE_DIR>/data/<TAG>_eco_applied.json`
- Path to RTL diff: `<BASE_DIR>/data/<TAG>_eco_rtl_diff.json`
- Previous strategies from `eco_fixer_state.strategies_tried`
- Task: Analyze failing points, classify failure mode, recommend revised changes
- Output: `<BASE_DIR>/data/<TAG>_eco_fm_analysis_round<round>.json`

**Step 6e — Translate fm_analyzer output into updated preeco_study JSON and loop:**

Read `<BASE_DIR>/data/<TAG>_eco_fm_analysis_round<N>.json`. For each entry in `revised_changes`, map it to the preeco_study format:

```python
# Load current preeco_study
study = load("<BASE_DIR>/data/<TAG>_eco_preeco_study.json")

for change in fm_analysis["revised_changes"]:
    stage = change["stage"]   # "Synthesize", "PrePlace", "Route", or "ALL"
    stages = ["Synthesize","PrePlace","Route"] if stage=="ALL" else [stage]
    for s in stages:
        # Find matching entry by cell_name+pin, or append if new
        entry = find_or_create(study[s], cell_name=change["cell_name"], pin=change["pin"])
        entry["old_net"]   = change["old_net"]
        entry["new_net"]   = change["new_net"]
        entry["confirmed"] = True
        entry["source"]    = f"fm_analyzer_round{N}"

save("<BASE_DIR>/data/<TAG>_eco_preeco_study.json", study)
```

Then:
1. Append strategy to `eco_fixer_state.strategies_tried`
2. Increment `eco_fixer_state.round` by 1 — save updated fixer_state
3. Set `ROUND = eco_fixer_state.round` (the NEW incremented value)
4. Loop back to **Step 4** — pass `ROUND=<new_value>` explicitly to eco_applier sub-agent

#### If round = 5 (max rounds reached):

Go directly to Step 7 — generate final HTML report with all rounds' history, then send summary email with `--eco-result MAX_ROUNDS_REACHED`.

---

## STEP 7 — Generate Reports (RPT + HTML)

### Step 7a — Write Per-Step RPT Files

**Each agent writes its own RPT** as part of its output (see each agent's md file). The orchestrator writes the Step 2 and Step 5 RPTs directly (since those steps are handled by the orchestrator, not sub-agents).

#### Step 2 RPT — Write after fenets completes

Write `<BASE_DIR>/data/<TAG>_eco_step2_fenets.rpt`.

**Key requirement:** For every net queried, the RPT must clearly state:
1. **Why this net is being queried** — which RTL change drove it (change_type, old_token/new_token from Step 1)
2. **Which block it belongs to** — the declaring module and full instance hierarchy
3. **What FM found** — the raw impl cell+pin results, with filters explained
4. **What was accepted vs rejected** — which results pass the 4 filters and why rejected ones were dropped
5. **What happens next** — what Step 3 will do with these results

Write `<BASE_DIR>/data/<TAG>_eco_step2_fenets.rpt`:

```
================================================================================
STEP 2 — FIND EQUIVALENT NETS
Tag: <TAG>  |  fenets_tag: <fenets_tag>
================================================================================

Purpose:
  Formality (FM) is used to find the gate-level impl cells that correspond
  to each RTL net involved in the ECO change. This bridges the RTL diff
  (Step 1) to the actual gate-level cells that need to be rewired (Step 3+).

Filters applied to all FM results:
  [F1] Polarity (+) only   — (-) lines are inverted nets, never safe to rewire
  [F2] Hierarchy scope     — only cells within the declaring module's instance
                             path; siblings filtered out (they use the net
                             correctly for unrelated purposes)
  [F3] Cell/pin pair only  — bare net aliases (no pin component) discarded
  [F4] Input pins only     — output pins (Z, ZN, Q, QN) skipped; rewiring
                             an output changes the cell's output net name,
                             not its input connection

================================================================================

<For each net in nets_to_query from eco_rtl_diff.json, one block:>

────────────────────────────────────────────────────────────────────────────────
Net [<n>/<total>]: <net_path>
────────────────────────────────────────────────────────────────────────────────
RTL Context:
  This net was queried because the RTL diff in Step 1 found a <change_type>
  in module <module_name> (<file>): <old_token> is being replaced by
  <new_token>. <net_path> is the gate-level scope path to locate where
  <old_token / new_token> is used within instance <INST_A>/.../<INST_B>.
  <If is_bus_variant=true:>
  Note: This is a bus variant query (<signal>_0_) — queried alongside
  <original_signal> to handle gate-level bit-indexed naming.

Declaring Module : <module_name>
Instance Path    : <TILE>/<INST_A>/.../<INST_B>
Scope Filter     : Only impl lines containing /<TILE>/<INST_A>/.../<INST_B>/
                   were accepted (F2 filter)

FM Results per Stage:

  [Synthesize]  (target: FmEqvPreEcoSynthesizeVsPreEcoSynRtl)
    Raw FM lines returned: <N total>
    After filters:
      ACCEPTED : <cell_name> / pin=<pin>  (+)
                 Reason kept  : polarity(+), correct scope, input pin
      ACCEPTED : <cell_name2> / pin=<pin2>  (+)
      REJECTED : <cell_name3> / pin=<pin3>  (-)
                 Reason dropped: (-) polarity — inverted net
      REJECTED : <path>/<bare_net_name>
                 Reason dropped: no pin component (bare net alias, F3)
      REJECTED : <sibling_path>/<cell>/<pin>
                 Reason dropped: outside <INST_A>/.../<INST_B>/ scope (F2)
    Qualifying cells passed to Step 3: <M>

  [PrePlace]  (target: FmEqvPreEcoPrePlaceVsPreEcoSynthesize)
    <same structure>
    <If no FM result / target had failures:>
    FM result  : NOT AVAILABLE — <reason: target had not-compared points /
                 FM-036 error / target failed>
    Action     : Step 3 will use Synthesize fallback for this stage

  [Route]  (target: FmEqvPreEcoRouteVsPreEcoPrePlace)
    <same structure>

<If FM-036 occurred on this net:>
FM-036 Handling:
  FM returned "Error: Unknown name" for path <original_path>
  This means FM does not recognize the signal at this hierarchy level.
  Retry strategy — strip one hierarchy level per retry:
    Original : <INST_A>/<INST_B>/<signal>  →  FM-036
    Retry 1  : <INST_A>/<signal>           →  <FOUND: <cell_name>/<pin> | FM-036>
    Retry 2  : <signal>                    →  <result>
  Outcome    : <Used retry N result — cell <cell_name> / pin <pin> accepted>
               OR <All retries failed — marked fm_failed, Step 3 uses direct grep>

Step 3 will receive:
  Synthesize : <N> qualifying cells  (<cell_name>/pin, <cell_name2>/pin2, ...)
  PrePlace   : <N> qualifying cells  (or: fallback from Synthesize)
  Route      : <N> qualifying cells  (or: fallback from Synthesize)

<Repeat full block for each net>

================================================================================
```

#### Step 5 RPT — Write after FM verification completes (each round)

Write `<BASE_DIR>/data/<TAG>_eco_step5_fm_verify_round<N>.rpt`:

```
================================================================================
STEP 5 — FORMALITY VERIFICATION  (Round <N>)
Tag: <TAG>  |  eco_fm_tag: <eco_fm_tag>
================================================================================

  FmEqvEcoSynthesizeVsSynRtl         : <PASS / FAIL>
  FmEqvEcoPrePlaceVsEcoSynthesize    : <PASS / FAIL>
  FmEqvEcoRouteVsEcoPrePlace         : <PASS / FAIL>

<If any FAIL:>
Failing Points (<N> total):
  Target: FmEqvEcoSynthesizeVsSynRtl
    - <hierarchy path of failing DFF>
    - <hierarchy path of failing DFF>
  Target: FmEqvEcoPrePlaceVsEcoSynthesize
    - <hierarchy path>

OVERALL: <PASS / FAIL>
================================================================================
```

#### Step 7a — Write Summary RPT

After all steps complete, write `<BASE_DIR>/data/<TAG>_eco_summary.rpt`.

All statistics are derived from `data/<TAG>_eco_applied.json`:
- **Cells added**: count unique `inv_inst` values where `change_type=new_logic` AND `status=INSERTED`, deduplicated across stages (same logical cell appears in all 3 stages — count it once)
- **Cells removed**: count of SKIPPED entries where `reason` contains "not found in PostEco" (cell optimized away by P&R — no longer present, no ECO needed). Zero for pure wire_swap runs.
- **Pins disconnected**: count of APPLIED + INSERTED entries per stage (each entry = one pin had old_net removed)
- **Nets/pins connected**: count of APPLIED + INSERTED entries per stage (each entry = one pin received new_net or inv_out)

```
================================================================================
ECO ANALYSIS SUMMARY
================================================================================
Tag         : <TAG>
Tile        : <TILE>
JIRA        : DEUMCIPRTL-<JIRA>
TileBuilder : <REF_DIR>
Generated   : <YYYY-MM-DD HH:MM:SS>
Rounds      : <N>
================================================================================

FINAL STATUS : <PASS / FAIL — MANUAL FIX NEEDED / MAX ROUNDS REACHED>

<If PASS:>  All 3 Formality targets passed. ECO is clean.
<If FAIL:>  Manual fix required. See step5 RPT for failing points.
<If MAX:>   5 rounds attempted. See per-round step5 RPTs for details.

--------------------------------------------------------------------------------
ECO STATISTICS  (from eco_applied.json — all rounds combined)
--------------------------------------------------------------------------------

  Cells Added      : <N>  (new inverter cells inserted for new_logic changes)
  Cells Removed    : <N>  (cells not found in PostEco — optimized away by P&R)
                          <If 0: "(none — all target cells present in PostEco)">

  Pins Disconnected / Nets Connected (per stage):

                     Synthesize    PrePlace    Route
                     ----------    --------    -----
  Pins Disconnected: <N>           <N>         <N>
  Nets Connected   : <N>           <N>         <N>
  Skipped          : <N>           <N>         <N>
  Verify Failed    : <N>           <N>         <N>

  Note: "Pins Disconnected" and "Nets Connected" counts are equal for each stage
        because every disconnected pin is immediately reconnected to the new net.
        Skipped entries were NOT changed — see step4 RPT for reasons.

--------------------------------------------------------------------------------
TIMING & LOL ESTIMATION  (structural analysis — Synthesize PreEco netlist)
--------------------------------------------------------------------------------

  Signal Change : <old_net>  →  <new_net>

  Old Net Driver: <driver_cell_name>  (<cell_type>)  pin=<Z/ZN/Q>
                  <e.g. "combinational NAND2 — inputs from combinational logic">
  New Net Driver: <driver_cell_name>  (<cell_type>)  pin=<Z/ZN/Q>
                  <e.g. "FF Q output — direct register launch point">

  Old Net Fanout: <N>
  New Net Fanout: <N>

  LOL Impact    : <e.g. "new_net source is shallower (FF Q) vs old_net
                          (combinational chain) — fewer logic levels at rewire pin">
  Timing Estimate: <BETTER / LIKELY_BETTER / NEUTRAL / RISK / LOAD_RISK / UNCERTAIN>
  Reasoning     : <plain English — why timing improves/worsens/stays the same>

--------------------------------------------------------------------------------
Per-Step Reports
--------------------------------------------------------------------------------
  <BASE_DIR>/data/<TAG>_eco_step1_rtl_diff.rpt
  <BASE_DIR>/data/<TAG>_eco_step2_fenets.rpt
  <BASE_DIR>/data/<fenets_tag>_find_equivalent_nets_raw.rpt
  <BASE_DIR>/data/<TAG>_eco_step3_netlist_study.rpt
  <BASE_DIR>/data/<TAG>_eco_step4_eco_applied.rpt
  <BASE_DIR>/data/<TAG>_eco_step4b_svf.rpt          <- omit if no new_logic
  <BASE_DIR>/data/<TAG>_eco_step5_fm_verify_round1.rpt
  <BASE_DIR>/data/<TAG>_eco_step5_fm_verify_round2.rpt  <- omit if single round
  ...
  <BASE_DIR>/data/<TAG>_eco_summary.rpt

================================================================================
```

### Step 7b — Write HTML Report

Write `data/<TAG>_eco_report.html` (and per-round `data/<TAG>_eco_report_round<N>.html` for fixer loop rounds) with sections:

1. **ECO Summary** — tile, ref_dir, tag, final FM result (PASS / FAIL / MAX_ROUNDS), total rounds run
2. **RTL Diff Summary** — files changed, change types, signals involved
3. **Net Analysis** — find_equivalent_nets results per net per stage
4. **PreEco Netlist Study** — confirmed cell/pin/context per stage
5. **ECO Actions Applied** — table per round:
   - Rewires: before/after per cell per stage (APPLIED / SKIPPED + reason)
   - new_logic inserts: cell type, instance name, source_net, inv_out per stage
   - SVF updates: entries added to EcoChange.svf
6. **Timing & LOL Impact** — based on structural comparison of old_net vs new_net driver in the Synthesize PreEco netlist:

   Render as a table with one row per change:
   ```html
   <h2>Timing &amp; LOL Impact</h2>
   <table>
     <tr>
       <th>Signal Change</th>
       <th>Old Net Driver</th>
       <th>New Net Driver</th>
       <th>Old Fanout</th>
       <th>New Fanout</th>
       <th>LOL Impact</th>
       <th>Timing Estimate</th>
     </tr>
     <tr>
       <td><code>old_net → new_net</code></td>
       <td><code>driver_cell (cell_type) pin=ZN</code></td>
       <td><code>driver_cell (cell_type) pin=Q</code></td>
       <td>N</td>
       <td>N</td>
       <td>Shallower / Deeper / Same</td>
       <td><span class="pass">BETTER</span>
           or <span class="fail">RISK</span>
           or <span class="warn">UNCERTAIN</span></td>
     </tr>
   </table>
   <p><b>Reasoning:</b> <plain English explanation from netlist study></p>
   ```

   **Timing estimate values and colors:**
   - `BETTER` / `LIKELY_BETTER` → green (`class="pass"`)
   - `NEUTRAL` → no color
   - `RISK` / `LOAD_RISK` → red (`class="fail"`)
   - `UNCERTAIN` → orange (`class="warn"`)

   **Source:** data comes from `timing_lol_analysis` field in `_eco_preeco_study.json` (written by eco_netlist_studier Step 4c) and confirmed/revised by eco_applier Step 6b.

7. **PostEco FM Verification** — per round: PASS/FAIL per target, failing points count and paths
8. **Fix Loop History** (if multiple rounds) — round-by-round: failure mode, strategy tried, result
9. **Final Status** — PASS / MANUAL FIX NEEDED with specific guidance
9. **Step Reports** — append this section at the bottom of the HTML, after Final Status. List only the file paths — no descriptions, no table headers, no details:

   ```html
   <h2>Step Reports</h2>
   <p><code><BASE_DIR>/data/<TAG>_eco_step1_rtl_diff.rpt</code></p>
   <p><code><BASE_DIR>/data/<TAG>_eco_step2_fenets.rpt</code></p>
   <p><code><BASE_DIR>/data/<fenets_tag>_find_equivalent_nets_raw.rpt</code></p>
   <!-- One line per retry tag if FM-036 retries occurred: -->
   <p><code><BASE_DIR>/data/<retry_tag>_find_equivalent_nets_raw.rpt</code></p>
   <p><code><BASE_DIR>/data/<TAG>_eco_step3_netlist_study.rpt</code></p>
   <p><code><BASE_DIR>/data/<TAG>_eco_step4_eco_applied.rpt</code></p>
   <!-- Include only if new_logic insertions exist: -->
   <p><code><BASE_DIR>/data/<TAG>_eco_step4b_svf.rpt</code></p>
   <p><code><BASE_DIR>/data/<TAG>_eco_svf_entries.tcl</code></p>
   <!-- One line per round: -->
   <p><code><BASE_DIR>/data/<TAG>_eco_step5_fm_verify_round1.rpt</code></p>
   <p><code><BASE_DIR>/data/<TAG>_eco_step5_fm_verify_round2.rpt</code></p>
   <p><code><BASE_DIR>/data/<TAG>_eco_summary.rpt</code></p>
   ```

   **Rules:**
   - Use the actual absolute `BASE_DIR` path — not a placeholder
   - Omit the step4b and svf_entries.tcl lines if no new_logic insertions in this run
   - For multi-round runs, add one step5 line per round
   - This is the last section in the HTML

**HTML style — MUST be email-safe (Outlook/Exchange compatible):**

Use ONLY these CSS properties — no `display:flex`, no `box-shadow`, no `rgba()`, no `border-radius` on layout elements. AMD email is Outlook which uses the Word rendering engine and ignores modern CSS.

Use this exact CSS template in `<head>`:

```html
<style>
body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; color: #333; }
h1 { color: #2c3e50; border-bottom: 2px solid #3498db; padding-bottom: 10px; }
h2 { color: #34495e; border-bottom: 1px solid #bdc3c7; padding-bottom: 6px; }
h3 { color: #555; margin-top: 16px; }
table { border-collapse: collapse; width: 100%; margin: 10px 0; background: white; }
th { background: #3498db; color: white; padding: 8px 12px; text-align: left; }
td { padding: 7px 12px; border-bottom: 1px solid #eee; }
tr:hover { background: #f0f7ff; }
.pass  { color: #27ae60; font-weight: bold; }
.fail  { color: #e74c3c; font-weight: bold; }
.warn  { color: #e67e22; font-weight: bold; }
.info  { color: #2980b9; }
.applied  { color: #27ae60; font-weight: bold; }
.skipped  { color: #e74c3c; font-weight: bold; }
.box   { background: white; border: 1px solid #ddd; padding: 15px; margin: 10px 0; }
.alert { background: #fef3cd; border: 1px solid #ffc107; padding: 12px; margin: 10px 0; }
.error { background: #f8d7da; border: 1px solid #f5c6cb; padding: 12px; margin: 10px 0; }
.success { background: #d4edda; border: 1px solid #c3e6cb; padding: 12px; margin: 10px 0; }
code { background: #f4f4f4; padding: 2px 5px; font-family: monospace; }
pre  { background: #f4f4f4; padding: 10px; font-family: monospace; font-size: 12px; }
</style>
```

**Color scheme:**
- Green `#27ae60` for PASS / APPLIED / INSERTED
- Red `#e74c3c` for FAIL / SKIPPED / VERIFY_FAILED
- Orange `#e67e22` for warnings / AMBIGUOUS / MANUAL_FIX
- Blue `#2980b9` for informational text

**Layout rules:**
- Use `<div class="box">` for card-like sections (border, no shadow)
- Use `<div class="alert">` for warnings, `<div class="error">` for failures, `<div class="success">` for pass
- Use `<table>` for ALL multi-column layouts including summary grids — never flex or grid
- Status words: wrap in `<span class="pass">PASS</span>`, `<span class="fail">FAIL</span>`, `<span class="warn">WARNING</span>`
- Code/signals: wrap in `<code>signal_name</code>`
- RTL diffs: use `<pre>` blocks

---

## STEP 8 — Send Email and Cleanup

```bash
cd <BASE_DIR>

# Final PASS
python3 script/genie_cli.py --send-eco-email <TAG> --eco-result PASS

# Final FAIL after max rounds
python3 script/genie_cli.py --send-eco-email <TAG> --eco-result MAX_ROUNDS_REACHED

# No changes applied
python3 script/genie_cli.py --send-eco-email <TAG>
```

**Cleanup after email:**

Remove the FM config file from REF_DIR — it's specific to this ECO run and would interfere if `post_eco_formality` is run again independently:
```bash
rm -f <REF_DIR>/data/eco_fm_config
```

The `--send-eco-email` command reads:
- `data/<TAG>_eco_analyze` — tile, ref_dir metadata
- `data/<TAG>_eco_report.html` — full HTML body
- `assignment.csv` — first debugger = **To**, rest = **CC**

---

## Output Files Summary

| File | Content |
|------|---------|
| `data/<TAG>_eco_analyze` | Metadata: tile, ref_dir, tag, jira (written in PRE-FLIGHT; read by --send-eco-email) |
| `data/<TAG>_eco_rtl_diff.json` | RTL diff analysis + nets to query |
| `data/<fenets_tag>_spec` | find_equivalent_nets results (fenets_tag ≠ TAG) |
| `data/<fenets_tag>_find_equivalent_nets_raw.rpt` | Raw FM output — all 3 targets concatenated into one file (fenets_tag ≠ TAG; one file per retry tag as well) |
| `data/<TAG>_eco_preeco_study.json` | PreEco netlist confirmation |
| `data/<TAG>_eco_applied.json` | ECO changes applied/inserted/skipped |
| `data/<TAG>_eco_svf_update.json` | SVF update results (new_logic only) |
| `data/<TAG>_eco_svf_entries.tcl` | Raw TCL eco_change entries to append after FmEcoSvfGen |
| `<REF_DIR>/data/eco_fm_config` | FM run config: targets + RUN_SVF_GEN + ECO_SVF_ENTRIES (fixed filename, not tag-based) |
| `data/<TAG>_eco_fm_verify.json` | PostEco FM verification results |
| `data/<TAG>_eco_fixer_state` | Round tracking JSON (fixer loop) |
| `data/<TAG>_eco_fm_analysis_round<N>.json` | FM failure analysis per round |
| `data/<TAG>_eco_report_round<N>.html` | Per-round HTML report |
| `data/<TAG>_eco_report.html` | Final HTML report (all rounds) |
| `data/<TAG>_eco_step1_rtl_diff.rpt` | Step 1 RPT — RTL diff results (written by rtl_diff_analyzer) |
| `data/<TAG>_eco_step2_fenets.rpt` | Step 2 RPT — find_equivalent_nets results (written by orchestrator) |
| `data/<TAG>_eco_step3_netlist_study.rpt` | Step 3 RPT — PreEco netlist study (written by eco_netlist_studier) |
| `data/<TAG>_eco_step4_eco_applied.rpt` | Step 4 RPT — ECO changes applied (written by eco_applier) |
| `data/<TAG>_eco_step4b_svf.rpt` | Step 4b RPT — SVF entries (written by eco_svf_updater, only if new_logic) |
| `data/<TAG>_eco_step5_fm_verify_round<N>.rpt` | Step 5 RPT — FM verification per round (written by orchestrator) |
| `data/<TAG>_eco_summary.rpt` | Summary RPT — index of all step RPTs + final status (written in Step 7a) |
