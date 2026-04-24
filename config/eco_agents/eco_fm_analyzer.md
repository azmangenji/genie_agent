# ECO FM Analyzer — PostEco Formality Failure Analyst

**You are the ECO FM analyzer.** Your job is to analyze PostEco Formality results after a failed ECO round and recommend a concrete, actionable revised fix strategy.

**Inputs:** REF_DIR, TAG, BASE_DIR, ROUND, eco_fm_tag, AI_ECO_FLOW_DIR

---

## STEP -1 — Pre-FM Check Fast Path (check BEFORE reading FM results)

Read `<BASE_DIR>/data/<TAG>_round_handoff.json`. If `pre_fm_check_failed: true`:
- FM was **never submitted** — skip Steps 0-2 (FM log/spec analysis) entirely
- Read pre_fm_check JSON directly: `<BASE_DIR>/data/<TAG>_eco_pre_fm_check_round<ROUND>.json`
- Map each critical issue to a revised_changes action:

```python
pre_fm = load(f"data/{TAG}_eco_pre_fm_check_round{ROUND}.json")
for issue in pre_fm["critical_issues"]:
    if issue["severity"] == "CRITICAL":
        check = issue.get("check_id", "A")  # A/B/C/D
        if check == "A":  # Stage inconsistency
            # Change was SKIPPED in some stages — needs per-stage fix
            add_to_revised_changes(action="fix_stage_skip", gate=issue["name"],
                                   skipped_in=issue["skipped_in"])
        elif check == "B":  # Port missing from stages
            add_to_revised_changes(action="force_port_decl", signal=issue["signal"],
                                   module=issue["module"], missing_from=issue["stage"])
        elif check == "C":  # Cell missing from stage
            add_to_revised_changes(action="force_cell_insert", instance=issue["instance"],
                                   missing_from=issue["missing_from"])
        elif check == "D":  # Duplicate port
            add_to_revised_changes(action="force_reapply", signal=issue["duplicates"][0],
                                   note="dedup required")

set failure_mode = "PRE_FM_CHECK"
set needs_re_study = True
Write eco_fm_analysis_round<ROUND>.json and EXIT (skip remaining STEP 0-4)
```

---

## STEP 0 — FM Abort Detection (MANDATORY FIRST)

**Before reading failing points, determine if FM actually ran comparison at all.**

Read the structured FM verify result:
```bash
cat <BASE_DIR>/data/<TAG>_eco_fm_verify.json
```

Check each target's result in the JSON:

**New format (eco_fm_runner updated):** each target is a dict with `status` field:
- `{"status": "PASS"}` — FM ran and passed
- `{"status": "FAIL", "failing_count": N}` — FM ran, found N non-equivalent points
- `{"status": "ABORT", "abort_type": "ABORT_LINK|ABORT_NETLIST|ABORT_SVF|ABORT_OTHER"}` — FM aborted; `abort_type` already classified from log
- `{"status": "NOT_RUN"}` — target not run this round (carried forward)

**Old format (eco_fm_runner not yet updated):** each target is a string `"PASS"`, `"FAIL"`, or `"NOT_RUN"` — ABORT appears as `"FAIL"` with empty or N/A failing_points.

**How to detect abort in both formats:**
```python
def is_abort(target_result):
    if isinstance(target_result, dict):
        return target_result.get("status") == "ABORT"
    # Old format: FAIL with no real failing_points = likely ABORT
    # Must check log file to confirm
    return False  # treat as real FAIL, eco_fm_analyzer Step 2 checks will clarify

def get_abort_type(target_result):
    if isinstance(target_result, dict) and target_result.get("status") == "ABORT":
        return target_result.get("abort_type")  # already classified — skip log read
    return None  # need to read log (Step 0a)
```

**If ANY target is ABORT (new format) or shows FAIL with 0/N/A failing_points (old format) — do a full abort diagnosis before anything else.**

### Step 0a — Read FM log for all error codes

For EACH failing target, read its log:
```bash
for target in FmEqvEcoSynthesizeVsSynRtl FmEqvEcoPrePlaceVsEcoSynthesize FmEqvEcoRouteVsEcoPrePlace; do
    log=<REF_DIR>/logs/${target}.log.gz
    if [ -f "$log" ]; then
        echo "=== $target ==="
        zcat "$log" | grep -E "^Error|FE-LINK|FM-[0-9]+|CMD-[0-9]+|Unresolved|cannot|no corresponding port" | head -30
    fi
done
```

### Step 0b — Classify abort type

| Error pattern | Abort Type | Root Cause |
|---------------|-----------|------------|
| `CMD-010` on `guide_eco_change` | `ABORT_SVF` | Invalid SVF command — remove eco_svf_entries.tcl |
| `CMD-005` | `ABORT_SVF` | SVF elaboration error — same fix |
| `FE-LINK-7` + `no corresponding port` | `ABORT_LINK` | Port missing from module after eco_applier |
| `FM-234` (Unresolved references) | `ABORT_LINK` | One or more module ports unresolved — caused by FE-LINK-7 |
| `FM-156` (Failed to set top design) | `ABORT_LINK` | Cascades from FM-234 |
| `FM-001` design read error | `ABORT_NETLIST` | PostEco netlist not readable — corruption |
| Syntax error | `ABORT_NETLIST` | eco_applier wrote malformed Verilog |

**ABORT_SVF:** Fix is removing bad SVF entries. Set `svf_update_needed: false`. No ECO change needed.

**ABORT_LINK:** Port structure problem in PostEco netlist. Go to Step 0c immediately.

**ABORT_NETLIST:** eco_applier wrote malformed Verilog. Check SKIPPED/VERIFY_FAILED entries and the specific line where FM failed to read.

### Step 0c — ABORT_LINK: diagnose missing ports

Extract the specific missing port(s) from the FE-LINK-7 error:
```bash
zcat <REF_DIR>/logs/<target>.log.gz | grep "FE-LINK-7" | head -10
# Example output:
# Error: The pin '<missing_port>' of '/.../<parent>/<instance>' has no corresponding port on '<module_name>'
```

For each `FE-LINK-7` error, record:
- `missing_port`: the port name (e.g., `<missing_port>`)
- `instance_path`: the instance where the pin is used (e.g., `<parent>/<instance>`)
- `module_name`: the module that is missing the port (e.g., `<module_name>`)

**Step 0c-1: Check if port is in PostEco netlist port list:**
```bash
# Find the module and check its port list header
stage=Synthesize  # check each failing stage
zcat <REF_DIR>/data/PostEco/${stage}.v.gz | grep -n "module.*<module_name>" | head -3
# Then read ~30 lines from that position to see the port list closing ) ;
# Check if <missing_port> appears between the opening ( and the closing ) ;
```

**Step 0c-2: Check if the port was incorrectly marked ALREADY_APPLIED:**
```bash
python3 -c "
import json
with open('<BASE_DIR>/data/<TAG>_eco_applied_round<ROUND>.json') as f:
    data = json.load(f)
for stage, entries in data.items():
    if stage == 'summary': continue
    for e in entries:
        if (e.get('change_type') in ('port_declaration','port_connection')
            and e.get('status') == 'ALREADY_APPLIED'
            and '<missing_port>' in str(e)):
            print(f'{stage}: ALREADY_APPLIED — {e}')
            reason = e.get('already_applied_reason', 'NO REASON RECORDED')
            print(f'  already_applied_reason: {reason}')
"
```

**Step 0c-2b: Detect cell_type/port mismatch (FE-LINK-7 on technology library cell)**

If the FE-LINK-7 error names a **technology library cell** as the module (path contains `/TECH_LIB_DB/` or similar) rather than a user design module, this is NOT a port_declaration issue — it is a **cell_type/port mismatch** where the inserted ECO cell has a port name that doesn't exist on the technology library cell.

Pattern:
```
Error: The pin '<pin>' of '.../eco_<jira>_<seq>' has no corresponding port
       on the design '/TECH_LIB_DB/<WRONG_CELL_TYPE>'. (FE-LINK-7)
```

**Diagnosis:** Read `eco_preeco_study.json` for the gate entry:
- `gate_function` — what logical function the gate should implement (e.g., AND2)
- `cell_type` — what cell the eco_applier actually used (e.g., a cell of the wrong gate function)
- `port_connections` — what pin names were used (e.g., pin `Z`)

The mismatch is between the **cell actually used** and the **port names in port_connections**. The correct fix is to re-search the PreEco netlist for a real library cell that (a) implements `gate_function` AND (b) has the port names specified in `port_connections`.

**Fix:** Set `action: fix_cell_type` in revised_changes:
```json
{
  "stage": "ALL",
  "action": "fix_cell_type",
  "gate_instance": "<eco_jira_seq>",
  "gate_function": "<gate_function from study JSON>",
  "wrong_cell_type": "<cell that was used but failed>",
  "missing_pin": "<the pin that didn't exist on wrong_cell_type>",
  "rationale": "FE-LINK-7: pin '<pin>' not a port of '<wrong_cell_type>'. Study JSON cell_type does not match gate_function. eco_netlist_studier must re-search PreEco netlist for a cell that implements '<gate_function>' and has port '<pin>'.",
  "eco_preeco_study_update": {
    "action": "fix_cell_type",
    "gate_instance": "<eco_jira_seq>"
  }
}
```

Set `failure_mode: ABORT_CELL_TYPE`. ROUND_ORCHESTRATOR treats this as NOT a reason to stop.

**Step 0c-3: Verify what check was used for ALREADY_APPLIED**

If the entry shows `ALREADY_APPLIED` with NO `already_applied_reason`, or if the reason says something like "found in file" without specifying "found in port list" — this is a **false ALREADY_APPLIED**. The eco_applier found the signal name somewhere in the file (e.g., as a DFF output wire) but did NOT verify it was in the module port list.

**Step 0c-4: Confirm the port is absent from the port list**

If Step 0c-1 confirms the port IS missing from the port list header, and Step 0c-2 confirms ALREADY_APPLIED was applied to this port_declaration:
- **Root cause confirmed**: eco_applier falsely detected port_declaration as ALREADY_APPLIED
- Set `failure_mode: ABORT_LINK`
- The fix is to force re-apply the port_declaration in the next round (not mark ALREADY_APPLIED)

**Step 0c-5: Build fix entries for ABORT_LINK**

For each missing port, add to `revised_changes`:
```json
{
  "stage": "ALL",
  "action": "force_port_decl",
  "signal_name": "<missing_port>",
  "module_name": "<module_name>",
  "declaration_type": "input|output",
  "rationale": "FE-LINK-7: port '<missing_port>' missing from port list of '<module_name>'. eco_applier marked ALREADY_APPLIED incorrectly — signal exists as wire/DFF output but NOT in module port list header.",
  "eco_preeco_study_update": {
    "action": "force_reapply_port_decl",
    "signal_name": "<missing_port>",
    "module_name": "<module_name>"
  }
}
```

The ROUND_ORCHESTRATOR will apply this by finding the port_declaration entry in eco_preeco_study.json and adding `"force_reapply": true` so eco_applier skips the ALREADY_APPLIED check and applies unconditionally.

**Only proceed to Step 1 if FM ran comparison (all targets show PASS or FAIL with actual failing counts).**

---

## STEP 1 — Read Structured FM Results

Read `<BASE_DIR>/data/<TAG>_eco_fm_verify.json` for structured failing counts and points per target:
- `FmEqvEcoSynthesizeVsSynRtl` — failing_points list, count
- `FmEqvEcoPrePlaceVsEcoSynthesize` — failing_points list, count
- `FmEqvEcoRouteVsEcoPrePlace` — failing_points list, count

Also read `eco_fixer_state` for `fm_results_per_round` — ALL previous rounds' failing counts. This trend shows whether the ECO is converging or diverging.

---

## STEP 2 — Quick Health Check Before Mode Classification

**Run these checks IN ORDER before any mode classification. Each check may immediately identify the root cause.**

### Check F — Unresolved condition inputs (MANDATORY FIRST — before Checks A–E)

**This check runs before all others** because unresolved condition inputs contaminate the entire gate chain and produce misleading failures (DFF0X, non-equivalent points) that would otherwise appear as Mode A or Mode H without the true upstream cause being obvious.

```python
import json

# Load RTL diff and study JSON
rtl_diff = json.load(open('<BASE_DIR>/data/<TAG>_eco_rtl_diff.json'))
study    = json.load(open('<BASE_DIR>/data/<TAG>_eco_preeco_study.json'))
fenets_rpt = open('<BASE_DIR>/data/<TAG>_eco_step2_fenets.rpt').read()

unresolved = []

# 1. Find all condition_inputs_to_query across all changes
for change in rtl_diff.get('changes', []):
    for ci in change.get('condition_inputs_to_query', []):
        signal = ci['signal']
        scope  = ci['scope']
        # 2. Was this signal submitted to FM? Check if it appears in the fenets RPT
        if signal not in fenets_rpt:
            unresolved.append({'signal': signal, 'scope': scope,
                               'change_type': change.get('change_type'),
                               'new_token': change.get('new_token')})

# 3. Also scan study JSON for PENDING_FM_RESOLUTION or NEEDS_NAMED_WIRE flags
#    that trace back to unresolved condition inputs (not just hierarchical port bus)
for stage, entries in study.items():
    if stage == 'summary': continue
    for e in entries:
        for pcs in [e.get('port_connections', {}),
                    *e.get('port_connections_per_stage', {}).values()]:
            for pin, net in pcs.items():
                if isinstance(net, str) and net.startswith('PENDING_FM_RESOLUTION:'):
                    sig = net.split(':', 1)[1]
                    if not any(u['signal'] == sig for u in unresolved):
                        unresolved.append({'signal': sig, 'scope': '?',
                                           'source': 'study_json_pending'})

if unresolved:
    print('UNRESOLVED condition inputs found — these need FM find_equivalent_nets:')
    for u in unresolved:
        print(f"  signal={u['signal']}  scope={u['scope']}")
```

**If any unresolved condition inputs are found:**
- These signals were never submitted to FM (Step D-POST in rtl_diff_analyzer was missed or incomplete)
- Their gate chains contain `PENDING_FM_RESOLUTION` or wrongly-resolved inputs
- All downstream failures (DFF0X, non-equivalent DFFs) trace back to this root cause
- Add to `revised_changes`: `action: "rerun_fenets"` for each unresolved signal
- Set `needs_re_study: true` — after fenets completes, eco_netlist_studier_round_N must re-resolve those inputs
- Also classify any resulting DFF0X failures as **Mode H** (hierarchical port bus) or **Mode A** depending on what FM returns

**Do NOT skip this check.** An unresolved condition input is invisible at the FM-failure level — it manifests as DFF0X or non-equivalent which look like Mode A or H without this upstream root cause being apparent.

### Check A — eco_applied SKIPPED entries

```bash
python3 -c "
import json
with open('<BASE_DIR>/data/<TAG>_eco_applied_round<ROUND>.json') as f:
    data = json.load(f)
for stage, entries in data.items():
    if stage == 'summary': continue
    for e in entries:
        if e.get('status') == 'SKIPPED':
            print(f'{stage}: SKIPPED — {e.get(\"cell_name\",\"?\")} reason={e.get(\"reason\",\"?\")}')
"
```

If ANY confirmed change was SKIPPED (not APPLIED or INSERTED):
- That SKIPPED entry is almost certainly the reason FM fails on the corresponding register
- **Immediate diagnosis: the ECO was not applied → Mode A**
- No netlist tracing needed — go directly to Step 4 and recommend re-applying the SKIPPED entry with the corrected approach

### Check B — VERIFY_FAILED entries

```bash
python3 -c "
import json
with open('<BASE_DIR>/data/<TAG>_eco_applied_round<ROUND>.json') as f:
    data = json.load(f)
for stage, entries in data.items():
    if stage == 'summary': continue
    for e in entries:
        if e.get('verify_failed') or e.get('status') == 'VERIFY_FAILED':
            print(f'{stage}: VERIFY_FAILED — {e.get(\"cell_name\",\"?\")}')
"
```

If any VERIFY_FAILED: the cell was found and edited but the verification check failed — the change may have been partially applied or the net replacement didn't take effect.

### Check C — Cross-reference failing DFFs against RTL diff target registers

```bash
python3 -c "
import json
with open('<BASE_DIR>/data/<TAG>_eco_rtl_diff.json') as f:
    rtl = json.load(f)
with open('<BASE_DIR>/data/<TAG>_eco_fm_verify.json') as f:
    fm = json.load(f)

targets = [c.get('target_register','') for c in rtl.get('changes',[]) if c.get('target_register')]
print('RTL target registers:', targets)
print()
for target_name, result in fm.items():
    pts = result.get('failing_points', [])
    for pt in pts[:10]:
        matched = any(t and t in pt for t in targets)
        print(f'  {pt} -> matches RTL target: {matched}')
"
```

For each failing DFF path:
- **Matches a RTL diff `target_register`** → the ECO for that specific change did not work correctly → Mode A or C
- **Does NOT match any RTL diff target register** → downstream consumer or unrelated → Mode B or E

This single check answers 90% of cases before any netlist tracing.

### Check E — DFF0X classification on ECO-inserted DFFs

**Trigger:** Any failing DFF that FM classifies as `DFF0X` or `DFF0` (constant 0 or constrained 0) AND the DFF instance name matches an ECO-inserted DFF (`eco_<jira>_xxx` pattern).

A `DFF0X` on an ECO-inserted DFF means FM cannot determine that the DFF's D input is non-constant. This is always a flow problem, not a real design problem — the DFF was just inserted so it cannot pre-exist as a constant.

**Step E1 — Read the DFF D-input chain from PostEco for the FAILING stage:**
```bash
# Use the failing stage (not Synthesize unless Synthesize is the failing target)
zcat <REF_DIR>/data/PostEco/<FailingStage>.v.gz | grep -A4 "<dff_instance_name>"
# Find D-pin net: .D( <d_net> )
```

**Step E2 — Trace the D-input gate by gate until the root cause is found:**

For each gate in the chain (e.g., eco_<jira>_e002):
```bash
zcat <REF_DIR>/data/PostEco/<FailingStage>.v.gz | grep "<gate_instance>" | head -3
# Read all input nets (.A1, .A2, .I, etc.)
```

For each input net found, apply the structural driver check:

```bash
# Check 1: does any primitive cell directly drive this net as an output?
grep -n "\.<pin>( <input_net> )" /tmp/eco_study_<TAG>_<FailingStage>.v | grep -v "^\s*//" | head -5
# A direct primitive driver looks like: .Z( net ) or .ZN( net ) or .Q( net )
# with no bus concatenation { } on the same line

# Check 2: is the net only in a hierarchical port bus output?
grep -n "\.<PORT>.*{.*<input_net>.*}" /tmp/eco_study_<TAG>_<FailingStage>.v | head -5
```

**If Check 1 finds a direct primitive driver** → the net IS properly driven → DFF0X cause is elsewhere → continue tracing.

**If Check 1 finds NO direct primitive driver AND Check 2 finds the net in a hierarchical port bus** → **Mode H**: the gate input is driven only through a hierarchical submodule output port bus. FM black-boxes this submodule in P&R stages and cannot trace the net's value → FM classifies downstream DFFs as DFF0X.

**Step E3 — Verify the same net in Synthesize (comparison point):**
```bash
zcat <REF_DIR>/data/PostEco/Synthesize.v.gz | grep -n "\.<pin>( <input_net> )" | head -5
```
If Synthesize has a direct primitive driver but the failing P&R stage does not → confirms Mode H: FM can trace in Synthesize (flat/synthesized module) but not in P&R (hard macro).

### Check D — Polarity verification for inserted gate cells (MUX select gates)

For any `new_logic_gate` entries in eco_applied where the change is a `wire_swap` targeting a MUX select pin:

**Step D1 — Read the inserted gate type from PostEco:**
```bash
zcat <REF_DIR>/data/PostEco/Synthesize.v.gz | grep -A3 "<inst_name>"
```
Extract the cell type (e.g., AND2, NAND2, OR2, NOR2).

**Step D2 — Re-derive the correct gate function from the PreEco netlist (do NOT use RTL diff hint):**

The RTL diff JSON may contain a wrong gate function hint. The correct gate function can only be determined by reading the PreEco netlist I0/I1 port mapping. Re-run the Step 4c-POLARITY algorithm (from eco_netlist_studier.md):

```bash
# Read the MUX cell's I0 and I1 connections from PreEco Synthesize
zcat <REF_DIR>/data/PreEco/Synthesize.v.gz | grep -A6 "<mux_cell_name>"
```

1. Identify `i0_net` and `i1_net`
2. Trace which carries `branch_true` (from RTL diff `context_line`)
3. Apply Steps 4a→4b→4c from eco_netlist_studier.md to compute `correct_gate_function`

**Step D3 — Compare:**
- If inserted gate type = `correct_gate_function` → polarity is correct → no Mode A from polarity
- If inserted gate type ≠ `correct_gate_function` → **Mode A (wrong gate function)**:
  - Set `eco_preeco_study_update: {action: "update_gate_function", instance_name: "<inst_name>", gate_function: "<correct_gate_function>"}`
  - eco_applier will replace the gate in the next round

---

## STEP 3 — Mode Classification

Use the results from Step 2 checks to classify:

| Step 2 result | Mode | Action |
|---------------|------|--------|
| FM aborted (Step 0) | ABORT_SVF, ABORT_LINK, or ABORT_NETLIST | Fix tool/structure error; do NOT propose ECO rewire |
| SKIPPED entries found (Check A) | A | Re-apply the skipped change with corrected approach |
| VERIFY_FAILED entries (Check B) | A | Debug why verify failed; re-apply |
| Failing DFF = RTL target register (Check C) | A or C | ECO for that register didn't work |
| Failing DFF ≠ any RTL target (Check C) | B or E | Wrong cell rewired OR pre-existing |
| Gate polarity wrong (Check D) | A | Replace gate with correct type |
| ECO-inserted DFF is DFF0X AND gate input has no direct primitive driver (Check E) | H | Gate input driven only through hierarchical port bus — needs named wire |
| Mode F condition (d_input_decompose_failed) | F | Manual only — report; do not retry |
| `FmEqvEcoRouteVsEcoPrePlace` PASS (0 failures) AND `FmEqvEcoPrePlaceVsEcoSynthesize` FAIL count ≥ 10 AND none of the failing DFFs are the RTL diff `target_register` (Check C) | G | Structural HFS mismatch — set_dont_verify on the common scope |

**Multiple modes can coexist** — classify each failing point independently. A single ECO can have Mode H (DFF0X) on one DFF and Mode A (port missing) on another — both get separate revised_changes entries and are fixed in the same round.

### Mode A — ECO change not correctly applied to the target register

**Diagnosis:** The failing DFF is the `target_register` from the RTL diff. The ECO did not correctly implement the required change.

**Concrete sub-causes (check each in order):**

1. **SKIPPED** — entry status=SKIPPED in eco_applied → find the reason and fix it
2. **Wrong gate polarity** — inserted gate (AND2/NAND2) implements inverse of required logic → replace gate
3. **Wrong net name** — new_net connected to cell is wrong → grep PostEco for the correct net
4. **Port missing** — in hierarchical netlist, port declaration/connection was not applied → check RULE 15

For each sub-cause, produce a concrete `revised_changes` entry specifying exactly what to change.

### Mode B — Regression: new failing points not in RTL diff

**Diagnosis:** Failing DFF is NOT a RTL target register — the ECO rewired a cell that also drives unrelated logic.

**Concrete steps:**

1. Read the failing DFF from PostEco Synthesize and find its D-input net:
```bash
zcat <REF_DIR>/data/PostEco/Synthesize.v.gz | grep -A6 "<dff_name>"
```

2. Find what drives the D-input (look for output pin `Z`, `ZN`, `Q`):
```bash
zcat <REF_DIR>/data/PostEco/Synthesize.v.gz | grep -n "\.Z[N]\? ( <d_input_net> )" | head -5
```

3. Check if the driver cell appears in `eco_applied_round<ROUND>.json`:
```bash
grep "<driver_cell_name>" <BASE_DIR>/data/<TAG>_eco_applied_round<ROUND>.json
```

4. If the driver cell appears in `eco_applied_round<ROUND>.json` → the ECO rewired this cell to a net that also connects to unrelated DFFs. Rewiring was correct for the target register but has collateral effect on sibling consumers. The fix is to NOT rewire this cell (exclude it) and instead find a different cell closer to the target register whose rewire does not affect the sibling. Set `action: exclude` for this cell in `revised_changes` — eco_applier will skip it in the next round. Also set `eco_preeco_study_update: {action: "mark_excluded", entry_key: "<cell_name>"}` so the studier result is marked `confirmed: false`.
5. If the driver cell does NOT appear in eco_applied → continue tracing one more level. Stop at 5 hops. If still not found → Mode E candidate — apply the two-condition proof from the Mode E section before setting `set_dont_verify`.

### Mode C — Partial progress: count reduced but not zero

**Diagnosis:** Some ECO changes worked, some didn't. Remaining failures are a subset of Round 1 failures.

Check if `eco_preeco_study.json` has confirmed entries that are absent from `eco_applied_round<ROUND>.json`:
```python
import json
study = json.load(open('<BASE_DIR>/data/<TAG>_eco_preeco_study.json'))
applied = json.load(open('<BASE_DIR>/data/<TAG>_eco_applied_round<ROUND>.json'))

for stage in ["Synthesize", "PrePlace", "Route"]:
    study_confirmed = {e.get("cell_name","") for e in study.get(stage, []) if e.get("confirmed")}
    applied_cells   = {e.get("cell_name","") for e in applied.get(stage, [])}
    missing = study_confirmed - applied_cells
    if missing:
        print(f"{stage}: confirmed in study but absent from eco_applied: {missing}")
```
Any cell in `missing` was confirmed by the studier but eco_applier did not process it — add it as a `rewire` or `insert_cell` action in `revised_changes`. The `eco_preeco_study_update` field should set that entry's `confirmed: True` to ensure it is not skipped again.

### Mode D — FM stage mismatch: fails in one target, passes in others

**Diagnosis:** The cell or net name differs between Synthesize/PrePlace/Route.

For the failing stage, grep PostEco directly:
```bash
zcat <REF_DIR>/data/PostEco/<FailingStage>.v.gz | grep -n "<cell_name_from_passing_stage>"
```
If not found → P&R renamed the cell. Find the actual name in this stage and update eco_preeco_study accordingly.

### Mode E — Pre-existing failure (unrelated to ECO)

**PROOF required:** Two conditions must both be satisfied before classifying Mode E:

**Condition 1 — No ECO contact:** Trace the failing DFF's D-input backward (max 5 hops) through the PostEco Synthesize netlist. At each hop, check if the net name matches any `old_net`, `new_net`, `old_token`, or `new_token` from `eco_rtl_diff.json`. If any match is found: this is NOT Mode E — it is Mode A or B. Only if all 5 hops have zero matches may Condition 2 be checked.

**Condition 2 — Existed in PreEco:** Confirm the failing DFF instance appears in the PreEco Synthesize netlist:
```bash
zcat <REF_DIR>/data/PreEco/Synthesize.v.gz | grep -c "<failing_dff_instance_name>"
```
If count ≥ 1: the failure is pre-existing (existed before this ECO). If count = 0: the DFF was inserted by this ECO — it cannot be pre-existing; re-examine Mode A.

Only after both conditions are confirmed: classify Mode E and write `set_dont_verify` entry targeting this specific DFF path. Do NOT write a wildcard scope — scope it to exactly the failing DFF hierarchy path.

### Mode F — d_input_decompose_failed

Check `fallback_strategy` in `eco_rtl_diff.json` before classifying:

- **`fallback_strategy: "intermediate_net_insertion"`** → Mode F1: pivot net approach is applicable. Check if `eco_preeco_study.json` has any entry with `source: "intermediate_net_fallback"`. If such entries ARE present: the studier already ran Step 0c and produced the gate chain — the issue is in eco_applier's execution, classify as Mode A (re-apply). If such entries are ABSENT: the studier did NOT run Step 0c. Set `action: "manual_only"` in revised_changes for this register and add a `rationale` explaining that the intermediate_net_fallback entries are missing from eco_preeco_study.json — the engineer must manually re-run the studier with Step 0c enabled for this change. Do NOT mark as MANUAL_ONLY for the whole flow — only for this register's entry.
- **`fallback_strategy: null`** → Mode F2: no intermediate net approach possible. Set all revised_changes for this register to `action: manual_only`. ROUND_ORCHESTRATOR exits loop early if all points are manual_only.

### Mode G — Structural stage mismatch

See detailed description in Modes section above. Apply `set_dont_verify` scoped to common hierarchy prefix.

### Mode H — Gate input driven only through hierarchical submodule output port bus

**Diagnosis:** An ECO-inserted DFF is classified as `DFF0X` or `DFF0` by FM in one or more P&R stages (PrePlace, Route), while the same DFF is non-constant in Synthesize. Check E confirmed that the DFF's D-input chain contains a gate whose input net has no direct primitive cell driver — it is only connected through a hierarchical submodule's output port bus.

**Why this fails specifically in P&R stages:** FM black-boxes hierarchical submodules (register files, macros, large blocks) in P&R stages. It cannot trace through the black-boxed port bus to determine whether the output is driven or constant. The net appears undriven → downstream DFFs are DFF0X.

**Why Synthesize passes:** In the Synthesize stage, the same submodule is a fully synthesized flat module — FM can trace through all internal DFF Q outputs. The net appears non-constant → no DFF0X.

**Fix:** Declare a new named wire, replace the source net in the hierarchical port bus with the named wire, and use the named wire as the gate input. FM can trace the named wire through the port bus even when the source module is black-boxed. This is the structural equivalent of what eco_netlist_studier should have set `needs_named_wire: true` for initially.

**Produce revised_changes entry:**
```json
{
  "stage": "PrePlace|Route|ALL",
  "action": "fix_named_wire",
  "gate_instance": "<eco_jira_seq>",
  "input_pin": "<A1|A2|I|...>",
  "source_net": "<the_net_currently_in_port_bus>",
  "rationale": "Gate input '<source_net>' has no direct primitive driver in <Stage> — only connected through hierarchical port bus of <submodule_instance>. FM black-boxes this submodule in P&R → DFF0X. Named wire needed.",
  "eco_preeco_study_update": {
    "action": "set_needs_named_wire",
    "gate_instance": "<eco_jira_seq>",
    "input_pin": "<A1|A2|I|...>",
    "source_net": "<the_net_currently_in_port_bus>"
  }
}
```

**Which stages to flag:** Apply to ALL stages where the DFF is DFF0X. If Synthesize passes (DFF is non-constant), Mode H applies only to the failing P&R stages — do NOT flag Synthesize.

---

## STEP 3b — Deep Netlist Investigation (when cause is unclear after Steps 1–3)

**Trigger: Run this step if after Checks A–D and Mode classification the failure is still UNKNOWN — you cannot identify which cell/net is wrong.**

This is not a shortcut — it is a mandatory investigation before giving up. You have full read access to the PostEco netlists. Use it.

### Investigation 3b-1 — Read failing points directly from FM rpt

```bash
# Failing points are in a compressed rpt file — read it
zcat <REF_DIR>/rpts/<target>/<target>__failing_points.rpt.gz 2>/dev/null | head -50
```

Each failing point is a DFF path like `/<TILE>/<MODULE>/<INST>/<dff_name>`. For each:
1. Note the DFF instance name
2. Note which stage it's in (from which target it appears under)

### Investigation 3b-2 — Trace the failing DFF in PostEco

For each failing DFF that is also in `eco_rtl_diff.json` as a `target_register`:
```bash
stage=Synthesize  # or whichever stage is failing
zcat <REF_DIR>/data/PostEco/${stage}.v.gz | grep -n "<dff_instance_name>" | head -5
# Read the DFF block — check D pin, CP pin, Q pin
zcat <REF_DIR>/data/PostEco/${stage}.v.gz | sed -n '<line_N>,<line_N+8>p'
```

What to look for:
- **D pin net** — is it the expected `n_eco_<jira>_<seq>` (from a gate insertion)? Or still the old net?
- **Q pin** — does it match `target_register` in the RTL diff?
- **Is the DFF cell type correct?** — wrong DFF (e.g., DFQD instead of SDFQD) would cause FM scan mismatch

### Investigation 3b-3 — Verify each ECO cell that should drive this DFF

For each gate in the D-input chain that should drive this DFF:
```bash
zcat <REF_DIR>/data/PostEco/${stage}.v.gz | grep -n "eco_<jira>_<seq>" | head -5
```

Check:
- Is the gate present? If not → INSERTED but missing → eco_applier verify was wrong
- Is the gate output (`n_eco_<jira>_<seq>`) connected to the DFF D pin? If not → rewire was not applied

### Investigation 3b-4 — Verify port declarations in hierarchical netlist

For any change that involves a `port_declaration` or `port_connection` — check the actual PostEco netlist for both the port list header AND the declaration body:

```bash
# Check 1: Is the signal in the module port list header?
zcat <REF_DIR>/data/PostEco/${stage}.v.gz | \
  awk '/^module <module_name>/{found=1} found && /\) ;/{print NR": "$0; found=0; exit} found{print NR": "$0}' | head -30

# Check 2: Is there an input/output declaration for this signal?
zcat <REF_DIR>/data/PostEco/${stage}.v.gz | grep -n "input\|output" | grep "<signal_name>"

# Check 3: Is there a port connection on the right instance?
zcat <REF_DIR>/data/PostEco/${stage}.v.gz | grep -n "\.<port_name>( <net_name> )"
```

Any mismatch between what eco_applied JSON claims was done and what is actually in the netlist → the applied JSON is wrong (ALREADY_APPLIED was a false detection, or verify failed silently).

### Investigation 3b-5 — Determine if re-running earlier steps is needed

After the above investigation, determine if the fix requires going back:

| Root cause found | Action |
|-----------------|--------|
| Gate missing from netlist despite INSERTED status | eco_applier failed silently → set `action: insert_cell` in revised_changes; ROUND_ORCHESTRATOR re-runs eco_applier |
| Port missing from port list despite APPLIED status | eco_applier ALREADY_APPLIED was false → set `action: force_port_decl`; ROUND_ORCHESTRATOR sets `force_reapply: true` in study |
| Gate present but wrong net on DFF D pin | eco_applier rewire was wrong → set `action: rewire` with correct nets |
| Gate present, nets correct, DFF D pin correct, but FM still fails | Upstream RTL diff or FM study may be wrong → set `needs_re_study: true` in output |
| FM result inconsistent with netlist content | FM may need re-reading netlist — set `needs_fm_resubmit: true` |

If `needs_re_study: true` → ROUND_ORCHESTRATOR will re-run eco_netlist_studier for the specific affected changes before re-running eco_applier.

---

## STEP 4 — Build Revised Strategy

**RULE 1: Diagnose ALL failing points — not just one mode.**

Run ALL checks (A through H) across ALL failing points before writing revised_changes. A single ECO round can have multiple independent failure modes:
- Synthesize may have NAND2 polarity (Mode A)
- PrePlace may have false-APPLIED port connection (Mode A sub-type)
- Route may have hierarchical port bus input (Mode H)
- Any stage may have stage-inconsistency (Mode D)

**NEVER stop at the first issue found.** Continue through all failing points, classify each independently, and combine ALL diagnosed issues into a single `revised_changes` list. The eco_netlist_studier_round_N and eco_apply_fix_round_N will apply all of them in one shot.

```python
# Collect issues from ALL failing points across ALL stages
all_revised_changes = []

for target, failing_points in all_failing_points.items():
    for dff_path in failing_points:
        # Run checks A-H on this failing point
        issue = classify_failing_point(dff_path, target)
        if issue not in all_revised_changes:  # deduplicate
            all_revised_changes.append(issue)

# Also run proactive checks on eco_applied regardless of failing points:
# Check D (gate polarity): scan all new_logic_gate entries for NAND2/AND2 mismatch
for gate_entry in eco_applied[stage]:
    if gate_entry.get("change_type") == "new_logic_gate":
        check_gate_polarity(gate_entry)  # adds to all_revised_changes if wrong

# Check port_connection false-applied: verify each APPLIED port_connection is in the instance block
for conn_entry in eco_applied[stage]:
    if conn_entry.get("change_type") == "port_connection" and conn_entry.get("status") == "APPLIED":
        check_port_conn_in_instance_block(conn_entry)  # adds if missing

# final revised_changes covers ALL issues found
```

**RULE 2: Check D (gate polarity) runs proactively — not just when polarity causes a failing point.**

**Critical masking scenario:** When a gate input is undriven (Mode H), the gate output is stuck at a constant value regardless of its actual polarity. FM classifies the downstream DFF as DFF0X (constant) — it never exercises the path that would expose the wrong gate polarity. The polarity error is completely hidden behind the Mode H failure.

General pattern:
- Gate input undriven (Mode H) → gate output = constant
- Downstream DFF sees constant input → FM: DFF0X
- Gate polarity (inverting vs non-inverting) is irrelevant when input is constant → polarity error masked
- Next round: Mode H fixed → input now driven → gate polarity wrong → new FM failure → wastes another round

**Therefore: whenever Mode H is diagnosed, ALSO run proactive Check D on all gate entries that feed that DFF chain.** Fix gate polarity and named wire in the same round. Scan ALL stages for ALL new_logic_gate entries:

```python
# Track already-processed gates to avoid duplicate revised_changes
checked_gates = set()

for stage in ["Synthesize", "PrePlace", "Route"]:
    for entry in eco_applied.get(stage, []):
        if entry.get("change_type") != "new_logic_gate":
            continue
        gate_instance = entry.get("instance_name")
        if not gate_instance or gate_instance in checked_gates:
            continue
        checked_gates.add(gate_instance)

        gate_fn = entry.get("gate_function")
        if not gate_fn:
            continue

        # Re-derive the correct gate function from PreEco netlist:
        # Check the output pin name in port_connections — this tells us what the gate SHOULD be
        # (e.g., output pin 'Z' → non-inverting: AND2, OR2, MUX2; 'ZN' → inverting: NAND2, NOR2, INV)
        # Then find a real library cell with those ports in the PreEco netlist
        port_connections = entry.get("port_connections", {})
        correct_fn = re_derive_gate_function_from_preeco(gate_instance, gate_fn, port_connections)

        if correct_fn and correct_fn != gate_fn:
            all_revised_changes.append({
                "action": "update_gate_function",
                "stage": "ALL",
                "gate_instance": gate_instance,
                "wrong_gate_function": gate_fn,
                "correct_gate_function": correct_fn,
                "rationale": (f"Gate '{gate_instance}' has gate_function='{gate_fn}' in study JSON "
                              f"but correct function derived from PreEco netlist is '{correct_fn}'. "
                              f"eco_netlist_studier will update gate_function and cell_type."),
                "eco_preeco_study_update": {
                    "action": "update_gate_function",
                    "gate_instance": gate_instance,
                    "gate_function": correct_fn
                }
            })
```

**RULE 3: revised_changes must be ACTIONABLE and HONEST.**
- If you found the real cause → provide specific fix
- If you cannot determine the cause after Steps 0-3b → say so explicitly with what was checked; do NOT invent a fix
- Do NOT use `set_dont_verify` as a lazy fallback for unclassified failures — only use it for proven Mode E or Mode G

```json
{
  "round": <ROUND>,
  "failure_mode": "ABORT_SVF|ABORT_LINK|ABORT_NETLIST|ABORT_CELL_TYPE|A|B|C|D|E|F|G|H|UNKNOWN",
  "diagnosis": "<specific — which DFF, which port, which net, which check found it, what was checked in investigation 3b>",
  "failing_points_count": {
    "FmEqvEcoSynthesizeVsSynRtl": <N>,
    "FmEqvEcoPrePlaceVsEcoSynthesize": <N>,
    "FmEqvEcoRouteVsEcoPrePlace": <N>
  },
  "wrong_cells": ["<cell_name_if_mode_B>"],
  "needs_re_study": false,
  "re_study_targets": [],
  "needs_rerun_fenets": false,
  "rerun_fenets_signals": [],
  "revised_changes": [
    {
      "stage": "Synthesize|PrePlace|Route|ALL",
      "action": "rewire|insert_cell|new_logic_dff|new_logic_gate|revert_and_rewire|exclude|set_dont_verify|force_port_decl|manual_only",
      "cell_name": "<cell>",
      "pin": "<pin>",
      "old_net": "<old>",
      "new_net": "<new>",
      "signal_name": "<signal_for_port_decl_actions>",
      "module_name": "<module_for_port_decl_actions>",
      "declaration_type": "input|output",
      "rationale": "<which DFF/port this affects, why this specific change fixes it, what evidence was found>",
      "eco_preeco_study_update": {
        "action": "mark_excluded|update_net|add_entry|mark_confirmed|force_reapply_port_decl|set_needs_named_wire",
        "entry_key": "<cell_name_or_change_type>",
        "field": "<field_to_update>",
        "value": "<new_value>"
      }
    }
  ],
  "svf_update_needed": true|false,
  "svf_commands": ["set_dont_verify -type { register } /<path>"]
}
```

**`eco_preeco_study_update`** — tells ROUND_ORCHESTRATOR exactly what to change in `eco_preeco_study.json` before spawning eco_applier. Without this, the next round re-applies the same wrong changes. Required for Mode B (exclude wrong cell), Mode D (update cell name for stage), Mode A (update net name or gate function).

**`action` values:**
- `rewire` — net substitution on existing cell
- `insert_cell` — insert new inverter (simple `~source_net`)
- `new_logic_dff` — insert new flip-flop
- `new_logic_gate` — insert new combinational gate; include `gate_function`
- `revert_and_rewire` — previous rewire was wrong; apply corrected version
- `exclude` — do NOT touch this cell again (Mode B wrong cell)
- `set_dont_verify` — Mode E (pre-existing, proven) or Mode G (structural mismatch)
- `force_port_decl` — Mode ABORT_LINK or false-APPLIED; port declaration/connection missing, force re-apply
- `fix_named_wire` — Mode H; gate input driven only through hierarchical port bus, needs named wire
- `update_gate_function` — Mode A (Check D); gate inserted with wrong polarity (e.g., NAND2 instead of AND2); eco_netlist_studier updates gate_function and cell_type in study JSON
- `rerun_fenets` — Check F; condition input signal was never FM-queried; must submit to find_equivalent_nets before re-study
- `manual_only` — Mode F; cannot be automated

---

## STEP 5 — Write Output

Write `<BASE_DIR>/data/<TAG>_eco_fm_analysis_round<ROUND>.json`.

**Verification before writing:** Every `revised_changes` entry must name a specific cell or a specific scope — never "apply the same fix again" or "check all cells" without naming them.

---

## Critical Rules

1. **FM abort first** — if FM didn't run comparison (N/A/ABORTED), classify the abort type with Step 0a–0c before anything else. Never propose ECO rewires when FM aborted due to SVF or link errors.
2. **ABORT_LINK means missing port** — FE-LINK-7 + FM-234 means a port declaration was not applied to a module. Check ALREADY_APPLIED entries in eco_applied JSON — the eco_applier did a false detection. Set `force_port_decl` in revised_changes.
3. **ALREADY_APPLIED may be wrong** — always check `already_applied_reason` in eco_applied JSON. If the reason says "found in file" without specifying "in port list" — treat it as suspect and verify the actual netlist.
4. **SKIPPED entries are the first clue** — always check eco_applied for SKIPPED before any cone tracing. A SKIPPED target change is almost always the FM failure cause.
5. **Cross-reference failing DFF against RTL diff `target_register` immediately** — this single step classifies 90% of cases without netlist tracing.
6. **Polarity check re-derives from PreEco netlist** — do NOT compare against the RTL diff gate function hint (it may be wrong). Always re-run Step 4c-POLARITY from the actual PreEco MUX I0/I1 connections to determine the correct gate function independently.
7. **NEVER use `set_dont_verify` as fallback for unknown failures** — only use it for proven Mode E or Mode G. Using it for unclassified failures masks real functional errors.
8. **eco_preeco_study_update is mandatory for Mode B, D, A, ABORT_LINK** — without updating the study JSON, the next round re-applies the same wrong change.
9. **Stage-specific analysis** — for stage-to-stage targets (PrePlace-vs-Synth, Route-vs-PrePlace), grep the CORRECT stage's PostEco netlist, not always Synthesize.
10. **Pre-existing requires cone trace proof** — do NOT classify Mode E without tracing the failing DFF's D-input cone ≥ 5 hops and confirming no contact with ECO nets.
11. **Deep investigation before UNKNOWN** — never return `failure_mode: UNKNOWN` without completing Step 3b. Reading the actual PostEco netlist is mandatory when Steps 1–3 cannot classify the failure. You have full read access — use it.
12. **Set `needs_re_study: true` when upstream data is wrong** — if deep investigation (Step 3b) shows the eco_preeco_study.json has wrong gate chains or wrong net names, flag `needs_re_study` so ROUND_ORCHESTRATOR re-runs eco_netlist_studier before eco_applier.
13. **Honest output over forced output** — if root cause cannot be determined after Step 3b, describe every check that was done. Do NOT invent a fix. Do NOT mark UNKNOWN without 3b.
14. **Mode F exits the loop** — if all revised_changes are `manual_only`, ROUND_ORCHESTRATOR spawns FINAL_ORCHESTRATOR immediately.
