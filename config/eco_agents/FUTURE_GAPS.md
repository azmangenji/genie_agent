# ECO Flow — Future Capability Gaps

Tracker for gaps observed in production runs that the AI flow does NOT yet handle correctly. Each gap: what we saw, where it lives, why it matters, suggested fix.

**Last consolidated:** 2026-05-12 (from run 20260512070625, 9868 trial)

---

## STEP 1 (rtl_diff_analyzer)

### G1.1 — `mux_select_i0_net` / `i1_net` populated with wrong CTS-renamed wires
**Severity:** HIGH (silent — same record carries correct answer in different field)
**Where:** `rtl_diff_analyzer.md` Step E mux_select branch; `eco_validate_step1.py`
**Symptom:** For wire_swap changes whose new MUX inputs are new_ports (don't yet exist as flat nets), the analyzer flat-net-resolves and grabs unrelated CTS-renamed wires. Same record's `new_select_inputs` array carries the correct symbolic names.
**Example (run 20260512070625, change[15]):** AI populated `mux_select_i0_net="ctmn_517750"`, `mux_select_i1_net="FEI0hi_debug_crashdump_comb_12_"` while `new_select_inputs=["EcoUseSdpOutstRdCnt","ARB_FEI_NeedFreqAdj"]` (correct, matched engineer).
**Why it matters:** A naive Step 3 studier reading `mux_select_i0_net` would build the wrong AND2 → FM logical mismatch on FEI_ARB_OutstRdDat. (Studier in this run consumed `new_select_inputs`, dodging the bug — but the field is a trap.)
**Fix:**
- Producer: when `new_select_inputs_from_change[k]==true`, populate `mux_select_i{0,1}_net` from `new_select_inputs[k]` directly (skip flat-net resolve).
- Validator: cross-check `mux_select_i0_net in new_select_inputs` and same for i1. Mismatch → hard FAIL.

### G1.2 — Clock domain not captured per-change for new DFFs
**Severity:** MEDIUM
**Where:** `rtl_diff_analyzer.md` Step C / DFF metadata extraction
**Symptom:** Step 1 doesn't emit a `dff_clock` field per new DFF. Engineer reference shows EcoUseSdpOutstRdCnt should clock on `wrp_clk_1`, NeedFreqAdj on `UCLK01`. AI flow has to guess in Step 3 (and got Route stage wrong — see G3.2).
**Fix:** Step 1 must extract the `posedge <clk>` or `clocked_on` clock signal from the RTL `always @` block enclosing each new DFF, write to `changes[i].dff_clock`. Fenets (Step 2) can then build clock-domain queries per DFF.

---

## STEP 2 (eco_fenets_runner)

### G2.1 — Sanitize step + Step 2 validator can be skipped silently
**Severity:** HIGH (FROZEN contract bypass — the diary's recurring panic-rewrite pattern)
**Where:** `eco_fenets_runner.md` STEP A (sanitize) + STEP F (validator); `STUDY_ORCHESTRATOR.md`
**Symptom (run 20260512070625):** Agent skipped both `eco_fenets_sanitize_queries.py` AND `eco_validate_step2.py`. Files missing: `_eco_fenets_queries.json` (sanitized), `_queries_sanitize_marker.txt` (marker), `_eco_validate_step2.json` (validator output). When run manually, validator FAILed with 6 issues (4 of them serious — Cat 8 anchor wires missing from rename_map).
**Why it matters:** Without the sanitize marker and validator gate, Step 3 starts with potentially incomplete fenets data. The C7 anchor-wire-missing issue meant studier had no per-stage data for SI/SE/Q anchor wires of NeedFreqAdj's scan stitching; studier had to grep netlist directly (worked this time, won't always).
**Fix:**
- STUDY_ORCHESTRATOR pre-flight before Step 3: assert `_eco_validate_step2.json` exists AND `overall_pass: true`. Otherwise HARD FAIL — block Step 3 spawn.
- APPLY_ORCHESTRATOR pre-flight: re-assert before Step 4 (defense in depth).

### G2.2 — Cat 8 Mode-S anchor data missing from `rename_map.json`
**Severity:** HIGH
**Where:** rename_map builder (collator after fenets); `eco_validate_step2.py` C7 check
**Symptom (run 20260512070625):** Step 2 RPT claims Cat 8 SI / Q anchor wires (`ARB/DCQARB/ArbCmd0MopWr_d2`, `ArbCmd0Ph_d2`) FOUND in all stages, but rename_map.json has zero `ARB/DCQARB/*` entries. Studier had no per-stage rename data for these wires.
**Why it matters:** When studier picks bridge source wires it relies on per-stage names (CTS renames PP names in Route → FM-036). Run 20260511201004 root cause was exactly this. Today studier did its own grep and got lucky.
**Fix:** rename_map collator must include Cat 8 anchor wires (not just Cat 1-4 leaf signals). Validator C7 already catches this; needs to actually run (see G2.1).

### G2.3 — Polarity inconsistency across stages not detected
**Severity:** MEDIUM (silent — applier may produce wrong logic)
**Where:** new check needed (`eco_validate_step2.py` C8)
**Symptom (run 20260512070625):** rename_map for `ARB/CTRLSW/IReset` has PP=`FxPrePlace_HFSINV_306/ZN` (= `~IReset`) and Route=`FxPlace_HFSINV_124/I` (= `IReset`). Mixed polarity across stages. Same for `ArbCtrlPeRdy`. Studier this time bypassed by direct netlist grep (engineer-tier reasoning); a less smart studier would silently feed inverter outputs into a new INV cell → `~~X = X` → FM mismatch.
**Fix:** Add C8 — POLARITY-STAGE-CONSISTENCY check. For each rename_map entry, verify all 3 stages reference the same polarity (all input pins, all output pins, or all wire names). Mixed → FAIL with explicit warning to studier.

### G2.4 — Echo-fallback waiver list incomplete
**Severity:** LOW (false positive in validator C6)
**Where:** `eco_validate_step2.py` `known_internal` set
**Symptom:** Validator C6 flags `ARB_FEI_NeedFreqAdj` as echo-fallback because rename_map has the same name in all 3 stages. But this is expected — it's a new_port created BY this ECO, doesn't exist in any pre-ECO netlist.
**Fix:** Either auto-detect new_port signals from RTL diff (`new_port` change_type) and skip them in C6, OR widen the `known_internal` waiver to cover all `*_NeedFreqAdj`, `*_FreqAdj`, etc. patterns. Better: derive from rtl_diff.json's new_port entries.

---

## STEP 3 (eco_netlist_studier)

### G3.1 — `reuse_existing_wire: true` semantics ambiguous
**Severity:** HIGH (depends on applier interpretation)
**Where:** study JSON schema; `eco_perl_spec.py` / applier
**Symptom (run 20260512070625):** Studier set `reuse_existing_wire: true` on `eco_9868_d006` (INV(IReset)) and pointed `inputs_per_stage` at `UMC_SSBDCICTL_rstb` (~IReset). The cell's `port_connections.I = "UMC_SSBDCICTL_rstb"` — but if applier instantiates the INV cell with this input, output becomes `~~IReset = IReset` → wrong logic. Intent is "skip the cell, alias d006's output to UMC_SSBDCICTL_rstb directly", but the JSON encoding doesn't make that explicit.
**Fix:**
- Schema: add `skip_cell_instantiate: true` field that explicitly tells applier to NOT emit the cell, treat output_net as alias for inputs_per_stage[stage].
- OR: `aliased_to_per_stage: {Synthesize: "n_eco_9868_d006_orig", PrePlace: "UMC_SSBDCICTL_rstb", ...}` — applier wires consumers directly.
- Validator (Step 3): if `reuse_existing_wire: true`, assert `inputs_per_stage[stage]` matches expected polarity given input pin name (I vs ZN).

### G3.2 — No clock-stage-stability check for new DFFs
**Severity:** HIGH (run-time FM failure)
**Where:** `eco_netlist_studier.md` clock pick logic; new validator check
**Symptom (run 20260512070625):** EcoUseSdpOutstRdCnt's CP picks across stages:
- Synth: UCLK01
- PP: wrp_clk_1
- Route: ant_fix_net_704_UCLK01_cts_1 (UCLK01-tree antenna fix)

Engineer used `wrp_clk_1` in PP AND Route (consistent). AI's PP picks wrp_clk_1 but Route picks UCLK01-tree → DFF on different clock domain in Route. FM may flag logical mismatch.
**Fix:** Studier must validate clock domain stability across stages. If PP picks wrp_clk_1, Route must also pick a wire driven by wrp_clk_1 (not UCLK01 tree). Cross-check via clock-tree trace OR by verifying CP wire's source register's CP.

### G3.3 — No Mode-S strategy decision log
**Severity:** MEDIUM
**Where:** `eco_netlist_studier.md`
**Symptom (run 20260512070625):** NeedFreqAdj in Route — studier picked `neighbor_dff` from `PeReqSR_reg_MB`. Engineer used `bridge_port` (ECO_905_*). Both are potentially valid; difference is engineer's bridge survives DFT scan, AI's neighbor-dff approach may not. Studier didn't record WHY it chose neighbor_dff over bridge_port.
**Fix:** Add `mode_s_strategy_decision_log` field per stage explaining the choice (e.g. "picked neighbor_dff because: candidate sibling DCQARB SE wire FxPrePlace_HFSNET_99954 returned FM-036 in Synth → bridge source unstable; PeReqSR_reg_MB neighbor SE is HFSNET-class, not CTS-touched → safe").

### G3.4 — Validator MEDIUM-only on constant_zero scan SI/SE for new DFFs
**Severity:** LOW (acceptable behavior most of the time)
**Where:** `eco_validate_step3.py`
**Symptom:** Validator emits 4 MEDIUM issues for EcoUseSdpOutstRdCnt scan SI/SE = 1'b0. Marked MEDIUM not FAIL because there's no viable peer to join. But if FM does flag, those MEDIUMs become real failures.
**Fix:** Either upgrade to HIGH when a viable peer EXISTS but studier still chose constant_zero (real escape), keep MEDIUM when picker returned null (legitimately no peer). Add the picker's `recommended_pick` outcome to the message.

---

## CROSS-CUTTING

### G-X.1 — Validator outputs not enforced as gates
**Severity:** HIGH (umbrella for G2.1)
**Where:** `STUDY_ORCHESTRATOR.md` and `APPLY_ORCHESTRATOR.md` pre-flight sections
**Symptom:** Step 1/2/3 validators write JSON with `overall_pass: bool`, but no orchestrator-level gate asserts `overall_pass: true` before advancing. Today's run has `validate_step1.json: overall_pass: true` (good), no `validate_step2.json` at all (skipped), `validate_step3.json: passed: false` (advanced anyway).
**Fix:** Each orchestrator step gate (between Step N and Step N+1) must:
1. Assert validator JSON file exists for Step N
2. Assert `overall_pass: true` (or `passed: true`)
3. Otherwise HARD FAIL with explicit re-run instructions

### G-X.2 — Cross-ECO awareness not in scope (but engineer uses it)
**Severity:** N/A (acknowledged limitation)
**Where:** N/A
**Symptom:** Engineer's 9868 solution shares bridge plumbing with ECO 906 (EcoUseSdpOutstRdCnt scan chain via `eco906_*` bridge) — saves 6 ports. AI cannot legitimately replicate (no awareness of in-flight ECOs in other tickets).
**Fix:** None planned — AI emits standalone solution (constant_zero scan on EcoUseSdpOutstRdCnt). FM should pass either way.

### G-X.3 — Engineer cell/port naming conventions divergent
**Severity:** COSMETIC
**Where:** various
**Symptom:** Engineer uses `eco9868_*` (no underscore between digits) for cells and `ECO_905_*` for ports. AI uses `eco_9868_*` for cells. Functionally identical, FM doesn't care.
**Fix:** Optional cosmetic alignment if engineer review prefers consistency. Low priority.

### G-X.4 — STUDY and APPLY orchestrators running in ONE agent context (split not enforced)
**Severity:** CRITICAL (defeats the architectural purpose of the orchestrator split)
**Where:** `STUDY_ORCHESTRATOR.md` "After Step 3" section; `.claude/CLAUDE.md` `APPLY_PHASE_READY` trigger; top-level Claude Code signal-detection mechanism
**Symptom (run 20260512070625):** The whole point of the STUDY/APPLY split was to run each phase in a fresh agent context to avoid the 3+ hour FM polling exhausting context. Observed: a single agent ran Steps 1-3 (STUDY) AND continued into Steps 4-6 (APPLY) without exiting. No new Agent spawn happened between Step 3 and Step 4. Defeats the entire purpose of the split — context pressure returns the moment FM polling kicks in at Step 6.
**Likely root causes (need to investigate):**
1. STUDY agent isn't HARD STOPping after writing `phase_a_handoff.json` — the "After Step 3" section may not be enforced strictly enough
2. The agent emits the `APPLY_PHASE_READY` signal block to SPEC_FILE but then continues executing instead of exiting
3. Top-level Claude Code's signal-detection only fires AFTER the agent fully exits — but the agent never exits, so no APPLY spawn happens
4. The agent's prompt may include APPLY instructions inline (CLAUDE.md ECO_ANALYZE_MODE_ENABLED block may be over-broad) so the agent thinks it's responsible for both phases
**Why it matters:** Single-agent flow defeats every reason we did the split:
- FM polling (30 min – 6+ hr) re-eats context
- ABORT recovery loop adds more context
- ROUND_ORCHESTRATOR / FINAL_ORCHESTRATOR also have to spawn from same context
- Eventually the agent gets context-truncated mid-FM-polling (the original failure mode that motivated the split)
**Fix:**
1. STUDY_ORCHESTRATOR.md must end with explicit HARD STOP language: "After writing `<TAG>_phase_a_handoff.json` and emitting `APPLY_PHASE_READY` to SPEC_FILE, EXIT IMMEDIATELY. Do NOT proceed to Step 4 — that is the responsibility of a separate APPLY_ORCHESTRATOR agent that top-level Claude will spawn after detecting the signal."
2. CLAUDE.md ECO_ANALYZE_MODE_ENABLED block must explicitly state "spawn STUDY agent ONLY — when STUDY completes and emits APPLY_PHASE_READY, spawn APPLY agent in NEW context, do not let STUDY continue."
3. Verify top-level Claude Code's signal-polling mechanism: how does it detect `APPLY_PHASE_READY` in SPEC_FILE? Is there a mid-execution polling, or only post-exit? If only post-exit, STUDY MUST exit for APPLY to spawn.
4. Add an enforcement check: STUDY_ORCHESTRATOR's last line should be a sentinel like `STUDY_ORCHESTRATOR_EXITED_AT_STEP_3_BOUNDARY` that top-level Claude verifies before spawning APPLY. If sentinel missing → orchestrator violated the split.
5. Consider runtime guardrail: emit `APPLY_PHASE_READY` and immediately `sys.exit(0)` from a deterministic script (not agent text), so the agent literally cannot continue.

### G-X.5 — Picker `_list_instantiations` heuristic may miss other wrapper patterns
**Severity:** LOW (cosmetic; no longer affects perf after b28e83e cache)
**Where:** `eco_pick_sibling.py` (already partially fixed b28e83e for `_wrap_<CELL>`)
**Symptom:** Picker reported 477 false peers from `<prefix>_wrap_<UPPERCASE_CELL>` synthesizer-emitted wrappers. Already filtered. Other naming conventions (e.g. `<prefix>_dft_*` test wrappers, generated module names from custom flows) may slip through.
**Fix:** As new wrapper patterns surface, extend the regex filter. Also consider a positive filter: real RTL submodules typically have `dff_count ≥ 10` AND module name doesn't contain library cell substrings (DFQ, INV, NAND, NOR, BUF, MUX, AOI, OAI).

---

## Priority order (to attack next)

1. **G-X.4** (STUDY/APPLY split not enforced) — CRITICAL; defeats architectural purpose; address before context exhaustion bites again on a long FM polling run
2. **G-X.1** (validator gates) — touches all 3 steps, prevents the "skipped validator" panic-rewrite class entirely
3. **G2.1** (specific instance of G-X.1 for Step 2)
4. **G3.2** (clock stage stability) — likely real FM failure source on tag 20260512070625
5. **G3.1** (reuse_existing_wire semantics) — depends on applier behavior, could bite anytime
6. **G1.1** (mux_select field bug) — paired producer + validator fix
7. **G2.3** (polarity stage consistency) — adds C8 check
8. **G2.2** (Cat 8 anchor in rename_map) — paired collator + C7 enforcement
9. **G1.2** (clock per change in Step 1) — supporting fix for G3.2
10. **G2.4, G3.3, G3.4, G-X.5** — polish, lower urgency
