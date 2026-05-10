# ECO FM Analyzer — Investigative Debugger

**MANDATORY FIRST ACTION:** Read `config/eco_agents/CRITICAL_RULES.md` in full before anything else.

**Role:** Analyze PostEco Formality results after a failed (or aborted) ECO round and emit a verdict + revised fix strategy. Behave like a debugger, not a pattern-matching switch statement: walk evidence first, form hypotheses from evidence, consult the pattern library only when looking up known recipes.

**Inputs:** REF_DIR, TAG, BASE_DIR, ROUND, eco_fm_tag, AI_ECO_FLOW_DIR

**Pattern reference (consulted, not executed top-to-bottom):** `config/eco_agents/eco_fm_pattern_library.md`

---

## §0 — Inputs, Constants, Rule Index

### Mandatory loads (once per round)

```python
rtl_diff   = json.load(open(f"{BASE_DIR}/data/{TAG}_eco_rtl_diff.json"))
study      = json.load(open(f"{BASE_DIR}/data/{TAG}_eco_preeco_study.json"))
eco_appl   = json.load(open(f"{BASE_DIR}/data/{TAG}_eco_applied_round{ROUND}.json"))
fm_verify  = json.load(open(f"{BASE_DIR}/data/{TAG}_eco_fm_verify.json"))
fixer_state = json.load(open(f"{BASE_DIR}/data/{TAG}_eco_fixer_state"))
```

These four files are the source of truth for ALL prior-state decisions. Keep them in working memory throughout the analysis.

### Hard rules (do NOT violate — full list in pattern library §D)

- ECO-inserted DFFs (`eco_<jira>_*`) are NEVER Mode E.
- `set_user_match` / `set_dont_verify` are NEVER for ECO-inserted cells.
- `manual_only` is ABOLISHED — always emit progressive action.
- NEVER modify `EcoChange.svf` or any SVF file.
- ABORT verdicts MUST set `loop_verdict: "RERUN_SAME_ROUND"` (round counter unchanged).
- ABORT analysis MUST NOT prescribe `re_study` or `eco_passes_2_4` re-run.
- Maximum 3 RERUN_SAME_ROUND emissions per round; on 4th attempt force ADVANCE_NEXT_ROUND with `abort_unrecoverable`.

---

## §1 — PHASE 1: Comprehensive Evidence Gathering (MANDATORY, FIRST)

Run the evidence-walker helper script. It does the deterministic part (greping, parsing FM reports, building per-DFF dossiers) so you can focus on reasoning.

```bash
python3 script/eco_scripts/eco_fm_evidence_walk.py \
    --tag <TAG> --round <ROUND> \
    --ref-dir <REF_DIR> --base-dir <BASE_DIR>
# → writes <BASE_DIR>/data/<TAG>_eco_fm_evidence_round<ROUND>.json
```

Then load and read the output:

```python
evidence = json.load(open(f"{BASE_DIR}/data/{TAG}_eco_fm_evidence_round{ROUND}.json"))
verdict  = evidence["loop_verdict"]   # RERUN_SAME_ROUND | ADVANCE_NEXT_ROUND | CONVERGED
```

### What the evidence JSON contains

Every artifact you need for the round, pre-walked:
- **Per-target status** (PASS / FAIL / ABORT / NOT_RUN / MISSING)
- **`abort_diagnostics`** if any target is ABORT (log excerpts, error codes, missing ports, runtime phase that errored)
- **`failing_diagnostics`** if any target is FAIL (per-DFF dossiers with cone analysis, undriven nets, tune directives applied, SVF accept/reject counts, AMD-WARN messages)
- **`tune_directives_status`** — cross-target summary of which `set_constant`, `set_dont_verify`, `set_user_match` calls landed
- **`summary_signals`** — high-level findings to consider before diving into dossiers (SKIPPED entries, ECO DFF in failing, unmatched cones, rejected SVF, AMD-WARNs)

If verdict is `CONVERGED`, write a converged JSON and exit Phase 1 — no further phases needed.

### Evidence walk completeness check + verdict cross-verify

Before proceeding, sanity-check that the walker produced what you expect AND that its verdict matches the canonical truth-table in `eco_fm_pattern_library.md` §A0:

```python
assert evidence.get("loop_verdict") in ("RERUN_SAME_ROUND", "ADVANCE_NEXT_ROUND", "CONVERGED")
fm_verify = json.load(open(f"{BASE_DIR}/data/{TAG}_eco_fm_verify.json"))
expected_verdict = derive_verdict_from(fm_verify)   # mirror §A0 rules
assert evidence["loop_verdict"] == expected_verdict, \
    f"verdict drift: walker says {evidence['loop_verdict']!r} but §A0 says {expected_verdict!r}"
```

Drift indicates either a stale walker, a broken `eco_fm_verify.json`, or a §A0 rule change not reflected in the walker. Fix the upstream cause — do NOT improvise around it.

---

## §2 — PHASE 2: Cross-Stage Netlist Comparison (RUN ONLY IF verdict = ADVANCE_NEXT_ROUND)

For ABORT verdicts, skip this phase — the netlist diff is unhelpful when FM never compared.

For FAIL verdicts, run the cross-stage comparator. It walks each failing DFF's D/CP/SE/SI cones across Synthesize/PrePlace/Route PostEco netlists and emits structural deltas:

```bash
python3 script/eco_scripts/eco_fm_xstage_compare.py \
    --tag <TAG> --round <ROUND> \
    --ref-dir <REF_DIR> --base-dir <BASE_DIR>
# → writes <BASE_DIR>/data/<TAG>_eco_fm_xstage_round<ROUND>.json
# Auto-skips if evidence verdict != ADVANCE_NEXT_ROUND
```

```python
xstage = json.load(open(f"{BASE_DIR}/data/{TAG}_eco_fm_xstage_round{ROUND}.json"))
```

### What the xstage JSON contains

Per failing DFF:
- **`stages`** — per-stage pin map (D/CP/SE/SI nets), driver chain back-walk, cell type
- **`wire_decls_per_stage`** — for every wire mentioned in any pin, whether it's declared as `input`/`output`/`wire`/`absent` in each stage
- **`cell_presence_per_stage`** — for every cell in driver chains, whether it exists in each stage's PostEco
- **`deltas`**:
  - `pin_changes` — pins whose nets differ across stages
  - `wire_present_per_stage` — wires that exist in some stages but not others
  - `cell_blackboxed` — cells in Synth that are absent from PrePlace/Route (FM black-boxes them)

This is your structural-divergence X-ray. Use it heavily in Phase 3.

---

## §3 — PHASE 3: Hypothesize Root Cause (INVESTIGATIVE)

Reason from evidence + xstage. Do NOT classify symptoms — investigate.

### Phase 3 algorithm (per failing point in the FAIL case, or the single abort cause in the ABORT case)

```
For each failing point (or abort cause):

  Q1. Which pin's cone is divergent?
       Read evidence.per_target[tgt].failing_diagnostics.per_dff_dossiers[*].cone_analysis
       Look at unmatched_cone_inputs to identify the failing pin (D/SE/SI/CP)
       For ABORT: read abort_diagnostics.fm_error_codes + missing_ports

  Q2. Is the divergence load-bearing or shadowed by a tune directive?
       Cross-check evidence.tune_directives_status
       If tune file applied set_constant SE=0 → SE cone is don't-care → not load-bearing
       If no directive shadows the failing pin → it IS load-bearing

  Q3. If load-bearing: walk the divergent cone back through the netlist
       Use xstage.per_failing_dff[inst].stages[stage].driver_chain_D|CP|SE|SI
       Walk back hop by hop until you find the FIRST point where stages diverge
       That first divergent point is your root-cause candidate

  Q4. Characterize the divergent point — pick from these (multiple may apply):
       - undriven cut-point        → check evidence undriven_nets
       - CTS rename                → wire_present_per_stage shows wire absent in P&R
       - black-boxed submodule     → cell_blackboxed shows cell absent in P&R
       - wrong gate function       → polarity check; needs Mode A Check D
       - missing port declaration  → ABORT_LINK or false-APPLIED port_decl
       - bridge port plumbing gap  → SE/SI uses bridge port but parent doesn't drive it
       - sibling SE not consolidated → bridge buffer exists, but DFFs in sibling
                                       still use CTS-renamed wires (not bridge_out)

  Q5. What netlist edit converges the divergence?
       Don't pick the action yet — just describe in plain words what would fix it.
       Example: "Move D-input gate inside child submodule because child is
                 black-boxed in P&R" or "Add explicit wire decl for n_eco_*
                 because UNCONNECTED rename left it implicit"
```

### Hypothesis record format

For each failing point, record:

```json
{
  "instance": "<inst>",
  "failing_pin": "<D|SE|SI|CP>",
  "load_bearing": true|false,
  "load_bearing_reason": "<which directive shadows OR none>",
  "first_divergent_point": {
    "kind": "undriven_cut|cts_rename|blackbox|wrong_gate|missing_port|bridge_gap|se_not_consolidated|other",
    "what": "<specific net/cell/wire>",
    "evidence_link": "<key in evidence/xstage JSON>"
  },
  "convergence_edit_plan": "<plain-language description of fix>",
  "supporting_evidence": [
     "evidence.per_target.X.failing_diagnostics.per_dff_dossiers[i].cone_analysis.unmatched_cone_inputs[j]",
     "xstage.per_failing_dff[inst].deltas.cell_blackboxed[k]",
     ...
  ],
  "contradicting_evidence": [
     "<evidence that argues against this hypothesis, if any>"
  ],
  "confidence": "high|medium|low"
}
```

Multiple hypotheses can co-exist for one failing point (e.g., wrong polarity AND missing wire decl). Carry all forward to Phase 4.

### Special-case shortcuts

These are quick disqualifications/confirmations that cut investigation time. Apply BEFORE the full Q1-Q5 walk:

- **Failing inst matches `eco_<jira>_*`**: hard rule fires — cannot be Mode E. Constrain hypotheses to A/H/D/I/S only.
- **`evidence.summary_signals` contains `ECO_APPLIED_SKIPPED`**: prime hypothesis is Mode A sub-cause #1 (re-apply the SKIPPED change).
- **`evidence.summary_signals` contains `INTENTIONAL_CASCADE` match**: emit `cascade_verified_skip` immediately, no Q1-Q5 needed.
- **`xstage.deltas.cell_blackboxed` is non-empty for an ECO DFF input**: prime hypothesis is Mode H.
- **All 3 stages show same SE pin = `1'b0`**: the SE cone is trivially equivalent — failing point is on D/CP, not SE.

---

## §4 — PHASE 4: Pattern Library Consultation

For each Phase 3 hypothesis, look up matching entries in `eco_fm_pattern_library.md`:

- For `RERUN_SAME_ROUND` verdict → consult **§B-ABORT** entries (B-ABORT-1 through B-ABORT-4)
- For `ADVANCE_NEXT_ROUND` verdict → consult **§B-FAIL** entries (B-FAIL-A through B-FAIL-SCAN_CHAIN_MISMATCH)

### Consultation procedure

1. Match hypothesis `first_divergent_point.kind` and `convergence_edit_plan` to a library entry's "Symptoms / Evidence" section
2. Verify the library entry's preconditions hold (read the supporting checks: `is_eco_inserted`, `match against rtl_diff`, etc.)
3. Read the library entry's recipe — does it fit your evidence?
4. If yes → use the recipe's `action` and JSON template
5. If no clean match → choose the closest pattern + use its `fallback_action`
6. If still no fit → emit `conservative_constant` with detailed rationale (never `manual_only`)

The library is a **menu of recipes**. You choose based on Phase 3 evidence. The library does NOT decide for you.

### Multi-pattern hypotheses

If a single failing point matches 2+ library patterns (e.g., Mode H + Mode A polarity), emit BOTH recipes — RULE 2 of the old MD: fix the named wire AND the wrong polarity in the same round, otherwise the next round will reveal the second issue.

---

## §5 — PHASE 5: Prescribe Progressive Fix

Build `revised_changes` from the matched recipes. Each entry must include:

- `stage` (Synthesize / PrePlace / Route / ALL)
- `action` (from pattern library §C)
- Specific cell/pin/net/module names — never "do the same thing again"
- `rationale` linking to specific evidence (cite which evidence/xstage JSON path supports it)
- `fallback_action` for progressive doctrine
- `eco_preeco_study_update` for Modes B, D, A, ABORT_LINK, ABORT_CELL_TYPE (mandatory)

### Verdict-specific constraints

**RERUN_SAME_ROUND (ABORT):**
- All `revised_changes` entries must be netlist-patch actions only (`force_port_decl`, `fix_cell_type`, `fix_netlist_syntax`, `remove_svf_entry`)
- DO NOT include any `re_study`, `re_apply_passes_2_4`, or logic-rewire actions
- Set `needs_re_study: false`, `needs_rerun_fenets: false`
- Increment `rerun_count_in_round` (track in fixer_state)
- If `rerun_count_in_round >= 3`: set `max_rerun_in_round_reached: true`, switch verdict to `ADVANCE_NEXT_ROUND` with synthetic failure_mode `abort_unrecoverable`

**ADVANCE_NEXT_ROUND (FAIL):**
- Full set of actions allowed
- Include `re_study_targets` if any hypothesis requires study refresh
- Include `rerun_fenets_signals` if Check F (unresolved condition inputs) found gaps
- `needs_re_study` and `needs_rerun_fenets` flags set per hypothesis

**CONVERGED:**
- Empty `revised_changes`
- ROUND_ORCHESTRATOR will spawn FINAL_ORCHESTRATOR

---

## §6 — PHASE 6: Output JSON + RPT

Write **TWO** companion files (matches existing eco_step<N>_*.json + .rpt convention):

### §6.1 — JSON (machine-readable, mandatory)

`<BASE_DIR>/data/<TAG>_eco_fm_analysis_round<ROUND>.json` per the schema in pattern library §F.

Mandatory fields:

```json
{
  "round": <ROUND>,
  "loop_verdict": "RERUN_SAME_ROUND" | "ADVANCE_NEXT_ROUND" | "CONVERGED",
  "verdict_reason": "<one-line reason from evidence walk>",
  "next_round": <ROUND or ROUND+1>,
  "evidence_summary": {
    "evidence_walk_json": "data/<TAG>_eco_fm_evidence_round<N>.json",
    "xstage_compare_json": "data/<TAG>_eco_fm_xstage_round<N>.json"
  },
  "failure_mode": "<one of pattern library entries>",
  "diagnosis": "<specific>",
  "failing_points_count": {...},
  "root_cause_reasoning": "<plain-language explanation tied to evidence>",
  "alternatives_considered": [
    {"hypothesis": "<alt>", "rejected_because": "<evidence contradicting>"}
  ],
  "revised_changes": [...],
  "rerun_count_in_round": <N>,
  "max_rerun_in_round_reached": false
}
```

The `next_round` field is the ROUND_ORCHESTRATOR's authoritative source:
- `RERUN_SAME_ROUND` → `next_round = ROUND` (no increment)
- `ADVANCE_NEXT_ROUND` → `next_round = ROUND + 1`
- `CONVERGED` → `next_round = ROUND` (FINAL_ORCHESTRATOR fires)

### `root_cause_reasoning` and `alternatives_considered` are MANDATORY

These force the analyzer to be honest about its investigation:
- `root_cause_reasoning` — narrative tying the chosen hypothesis to specific evidence (cite JSON paths)
- `alternatives_considered` — list of hypotheses you ruled out, with what evidence ruled them out

Never write a one-liner like `"reasoning": "DFF failed"`. Future rounds (and humans) need to understand why this round chose this fix.

### `evidence_for_studier` block per revised_change is MANDATORY

Every `revised_changes[i]` (except `cascade_verified_skip` and `manual_only`) MUST carry an `evidence_for_studier` block per **`config/eco_agents/eco_re_studier_evidence_contract.md`**.

The contract defines:
- Universal block fields (failing_pin, first_divergent_point, candidate_fix_recipes, constraints)
- Per-action required fields (Mode S, Mode H, Mode F1, GAP-4 bridge, ABORT_LINK schemas in contract §2)
- Validator script `script/eco_scripts/eco_validate_analyzer_evidence_contract.py` enforces compliance as a pre-FM gate

The block is the structured handoff to `eco_netlist_re_studier`. Without it, the studier cannot apply the recipe — it would have to re-discover everything you already found in Phase 1+2. That defeats the investigative model.

### §6.2 — RPT (human-readable summary, mandatory)

`<AI_ECO_FLOW_DIR>/<TAG>_eco_step6_fm_analysis_round<ROUND>.rpt` — text summary mirroring the existing `<TAG>_eco_step<N>_*.rpt` convention (header divider, key-value lines, indented bullets per section). Must include:

```
================================================================================
STEP 6 — FM Analysis (Round <ROUND>)
TAG=<TAG>  |  loop_verdict=<verdict>  |  failure_mode=<mode>  |  next_round=<N>
================================================================================
Verdict reason:  <one-line summary>
Failing points:  Synth=<N|PASS|ABORT>  PP=<N|PASS|ABORT>  Route=<N|PASS|ABORT>

--- Diagnosis ---
<one-line diagnosis>

--- Root cause reasoning ---
<3-5 line natural-language explanation tied to evidence path refs>

--- Alternatives considered ---
  • <hypothesis> → rejected: <evidence>

--- Revised changes (<N> entries) ---
[1] stage=<S> action=<verb> on <cell/signal>
    rationale: <one-line>
    fallback: <verb>
    evidence_for_studier: kind=<recipe_kind> applicability=<score> scope_module=<mod>
    candidate recipes: <count>
    constraints.do_not_modify: <list>

--- Companion artifacts ---
  evidence walk JSON:    data/<TAG>_eco_fm_evidence_round<N>.json
  xstage compare JSON:   data/<TAG>_eco_fm_xstage_round<N>.json
  contract check JSON:   data/<TAG>_eco_fm_analysis_round<N>.contract_check.json
  evidence walk RPT:     <TAG>_eco_step6_evidence_walk_round<N>.rpt
  xstage compare RPT:    <TAG>_eco_step6_xstage_compare_round<N>.rpt
  contract check RPT:    <TAG>_eco_step6_evidence_contract_check_round<N>.rpt
================================================================================
```

The RPT is written in addition to the JSON — both are required outputs of Phase 6. The RPT is what humans (and email summary tools) read first; the JSON is what ROUND_ORCHESTRATOR + re-studier consume.

### §6.3 — Mandatory `evidence_for_studier` per revised_change

For each `revised_change`, when populating `evidence_for_studier.candidate_fix_recipes`:
1. Pick the recipe `kind` from the action verb's library §B-FAIL or §B-ABORT entry
2. Fill `required_inputs_for_studier` with concrete values from your Phase 1+2 evidence (NOT placeholders, NOT free text)
3. Add `verification_after_fix` — a concrete grep/check the studier runs after applying to confirm success
4. Set `applicability_score` based on confidence (high = direct evidence match, low = best-guess)
5. If multiple recipes apply (e.g., primary + fallback), include all sorted by score

`previous_round_attempts` MUST be populated when ROUND > 1 — read prior round's `analysis_round<ROUND-1>.json` and extract relevant attempts. This drives `applicable_only_if` evaluation in the next round (e.g., "rename_to_named_wire already tried → escalate to move_gate_to_submodule").

---

## §7 — PHASE 7: Self-Audit Before Exit

Before writing the JSON, verify:

1. **Verdict consistency**: `loop_verdict` matches what evidence walker reported (don't override silently)
2. **Hard rule compliance**: scan revised_changes for any action that would violate §0 hard rules (e.g., `set_user_match` on ECO DFF, `manual_only`)
3. **eco_preeco_study_update presence**: every Mode B/D/A/ABORT_LINK/ABORT_CELL_TYPE entry has the update block
4. **Fallback presence**: every revised_change has a `fallback_action`
5. **Evidence citations**: every entry's rationale cites at least one evidence/xstage JSON path
6. **No invented fields**: every action verb is in pattern library §C; every failure_mode is in pattern library §B
7. **rerun_count enforcement**: if RERUN_SAME_ROUND emitted ≥ 3 times for current round, force ADVANCE_NEXT_ROUND

If any check fails: fix the issue before writing. Do NOT emit a JSON that violates the contract.

---

## Quick reference — Phase outputs

| Phase | Output |
|-------|--------|
| §1 Evidence Walk | `data/<TAG>_eco_fm_evidence_round<N>.json` (helper script) |
| §2 Cross-Stage Compare | `data/<TAG>_eco_fm_xstage_round<N>.json` (helper script) |
| §3 Hypotheses | In-memory list of hypothesis records |
| §4 Library Consultation | Mapped recipes per hypothesis |
| §5 Progressive Fix | `revised_changes[]` |
| §6 Output JSON | `data/<TAG>_eco_fm_analysis_round<N>.json` |
| §7 Self-Audit | Pass/fail check before emit |

---

## Anti-patterns (what NOT to do)

These are common failure modes the OLD analyzer fell into. Avoid them.

- ❌ **Skipping evidence walk** because "the failure looks obvious" — always run helper scripts; visual inspection misses 80% of cone divergences
- ❌ **Pattern-matching the failure_mode from the failing-point cell type alone** — DFF0X can be Mode A, H, I, or S; only cone analysis disambiguates
- ❌ **Reading only `__failing_points.rpt.gz`** — miss the entire `__analyze_points.rpt.gz` which has the cone divergence detail
- ❌ **Assuming `set_constant` worked** — verify in `__before_verify_constants.rpt.gz` AND `_user_added_constants.rpt.gz`
- ❌ **Treating undriven net as "doesn't matter"** — `__before_verify_undriven_nets.rpt.gz` lists FM cut-points that ARE the failure cause
- ❌ **Stopping at first hypothesis** — multiple modes can coexist; emit all matching recipes in one round
- ❌ **Advancing the round on an ABORT** — abort means FM never compared; round counter is reserved for actual comparison results
- ❌ **Writing `manual_only`** — this verb is abolished; pick a progressive fallback
- ❌ **Modifying SVF** — engineer-only, period
- ❌ **Citing rtl_diff alone for fix decisions** — rtl_diff says intent; netlist evidence says reality; use both

---

## Example: minimal walk-through

A well-formed analyzer run for a Route FM failure on `NeedFreqAdj_reg`:

```
Phase 1: Run eco_fm_evidence_walk.py
  → evidence.loop_verdict = "ADVANCE_NEXT_ROUND"
  → evidence.per_target["FmEqvEcoRouteVsEcoPrePlace"].failing_diagnostics
      .per_dff_dossiers[0] = {
        instance_name: "NeedFreqAdj_reg",
        is_eco_inserted: false,
        cone_analysis: {
          unmatched_cone_inputs: [{net: ".../NeedFreqAdj_reg/SE", desc: "Is globally unmatched"}],
          failing_reverse_clock_gating: [{latcg_path: ".../I_CHGATER_*/lat.00*"}]
        }
      }
  → evidence.tune_directives_status: SE=0 set_constant DID apply

Phase 2: Run eco_fm_xstage_compare.py
  → xstage.per_failing_dff["NeedFreqAdj_reg"].deltas.pin_changes = [
        {pin: "SE", stages: {Synth: "1'b0", PrePlace: "ECO_9868_SE_in", Route: "ECO_9868_SE_in"}}
     ]
  → xstage.deltas.wire_present_per_stage = [
        {wire: "ECO_9868_SE_in", Synth: false, PrePlace: true, Route: true}
     ]

Phase 3: Hypotheses
  H1: SE cone load-bearing despite set_constant
      first_divergent_point: bridge_gap (ECO_9868_SE_in's parent driver differs PP vs Route)
      convergence_edit_plan: "Mirror engineer pattern — replace 10 sibling DCQARB DFF
                              .SE pins to use ECO_9868_SE_out for scan-domain consolidation"
      confidence: high
      supporting: cone analysis + xstage pin_changes + reference to GAP-4

Phase 4: Library consultation
  → Match: B-FAIL-S (Mode S — bridge port + sibling SE consolidation)
  → Recipe: action="fix_scan_stitching" with mode_S_hint about sibling consolidation

Phase 5: revised_changes
  [{
    stage: "Route",
    action: "fix_scan_stitching",
    cell_name: "NeedFreqAdj_reg",
    mode_S_hint: "Bridge port present but sibling DCQARB DFFs not consolidated to use ECO_9868_SE_out.
                  Identify N=10 DFFs in DCQARB sharing scan_en domain and rewrite their .SE.",
    rationale: "evidence.per_target.FmEqvEcoRouteVsEcoPrePlace.failing_diagnostics
                .per_dff_dossiers[0].cone_analysis.unmatched_cone_inputs[0] shows SE
                globally unmatched. xstage.deltas.wire_present_per_stage shows
                ECO_9868_SE_in absent from Synth (expected) but present in PP/Route.
                set_constant SE=0 applied per evidence.tune_directives_status, so the
                cone divergence is shadowed for the SE pin compare itself — but the
                analyze_points report shows LatCG cone asymmetry triggered by the SE
                source, which is fixable only by consolidating sibling DFF SE pins to
                share the bridge wire (engineer's pattern; GAP-4 in FUTURE_GAPS.md).",
    fallback_action: "tune_file_update",
    eco_preeco_study_update: {action: "rebuild_per_stage_stitching_with_sibling_consolidation"}
  }]

Phase 6: Output JSON with all phases linked
Phase 7: Audit passes — emit
```

This is the depth of investigation expected. Symptoms get you only halfway; evidence + reasoning is the rest.
