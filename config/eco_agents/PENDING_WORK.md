# ECO Flow — Pending Work

Living document of known gaps, deferred features, and tech debt in the ECO
flow. Items here are NOT in the current scope of the AI flow's automatic
behavior — each requires explicit follow-up to address.

Last updated: 2026-05-08 after the 9868 deep-dive session.

---

## P0 — Blocks 100% FM coverage on existing JIRAs

### Mode S — Scan Stitching for new ECO DFFs in P&R

**Symptom:** New ECO DFFs in P&R stages with `SE/SI=1'b0` and `CP=UCLK01`
(or any clock that traverses scan_cntl logic) fail FM with "globally unmatched
SE pin" + "LatCG cone exists in ref but not impl". Confirmed on 9868
NeedFreqAdj_reg in Route stage.

**Engineer's pattern:** Adds 3 new module ports to host module:
```verilog
input  ECO_<jira>_SI_in ;
output ECO_<jira>_Q_out ;
input  ECO_<jira>_SE_in ;
assign ECO_<jira>_Q_out = <DFF Q> ;
SDFQD1 <DFF_reg> ( .SI(ECO_<jira>_SI_in), .SE(ECO_<jira>_SE_in), .CP(<clock>), .Q(<DFF Q>) ) ;
```
Then wires those ports through parent hierarchy to the actual scan-chain
upstream/downstream neighbors.

**Why pending:** Substantially new functionality:
- Detect insertion need (any new DFF in P&R needs scan stitching unless its
  clock cone is shallow enough to avoid scan_cntl, like `wrp_clk_*`)
- Find chain insertion point (scan upstream DFF whose Q can drive our SI)
- Generate 3 port_decls + 1 assign + per-hierarchy port_connections through
  N parent modules
- Add Mode S routing in ROUND_ORCHESTRATOR

**Architecture (3 places):**
| Step | Action |
|------|--------|
| Step 1 (rtl_diff_analyzer) | Mark new_logic_dff entries with `requires_scan_stitching: true` |
| Step 3 (eco_netlist_studier) | Per stage: scan host module for scan-active DFFs, pick insertion point, emit 3 port_decl + per-hierarchy port_connection entries, update DFF's port_connections_per_stage SE/SI |
| Step 4 (eco_passes_2_4 + eco_perl_spec) | No new code — reuses port_decl/port_conn paths. Only need to add `assign` change_type support. |
| Step 5 (eco_pre_fm_check) | New Check 14: verify the 3 stitching ports + assign exist in netlist |

**Insertion-point heuristic options (pick one for default):**
- (a) First scan-active DFF in host module — chain ours after it
- (b) Tile-root scan_en + tied SI=1'b0 — simplest, may not always pass FM
- (c) Reuse existing scan-bridge ports if found (`*_si_bridge`, `ECO_*_SI_in`)

**Estimated effort:** ~200 lines (across 4 files) + ~1.5–2 hours focused work.

**When to do:** When we want 100% AI-flow FM pass on JIRAs that need new
DFFs in main clock domains. Until then, Route stage may have 1-DFF FM
failures that an engineer must hand-stitch.

---

## P1 — Catches future bugs proactively

### Liberty extractor (production version)

**Why pending:** POC validated (`/tmp/poc_liberty_extractor.py`) — extracts
11,624 cells from TSMC bwp136 in 8 min. But not productionized into the
flow.

**Critical finding from POC:** the bundled `cell_libraries/tsmc_bwp136.json`
has WRONG truth tables for I-prefix compound cells:
| Cell | Bundled (wrong) | Liberty (real) |
|------|-----------------|----------------|
| INR3 | `~(A1 \| (B1 & B2))` | `A1 & ~B1 & ~B2` |
| IAOI21 | `~(A1 \| (A2 & B))` | `~((A1 & ~A2) \| B)` |

The validator gives correct CONCLUSIONS for 9868 by coincidence (mismatch
detected anyway), but for future cells the bundled JSON would be unreliable.

**Architecture:**
| Component | Action |
|-----------|--------|
| New `script/eco_scripts/eco_liberty_extractor.py` | Scan `<REF_DIR>/tech/synopsys/ccs/*.lib.gz`, extract cell→function map, write `<REF_DIR>/data/eco_cell_library.json` |
| Update `eco_cell_truth_tables.py` | Lookup priority: (1) per-tile cache, (2) bundled fallback |
| Hook in ORCHESTRATOR.md | Run extractor at Step 1 init if cache doesn't exist |

**Estimated effort:** ~150 lines + ~2 hours (including parallelization to
reduce 8 min → ~1 min, and Liberty function syntax translator).

**Quick win alternative (10 min):** Just fix the bundled JSON's I-prefix
entries to match Liberty truth tables — covers 9868-style cases until the
production extractor is built.

---

### Bundled cell library JSON I-prefix entries are wrong

**Subset of above** — the 10-min fix. Replace bundled INR3, IAOI21, IND3,
IOAI21 entries in `script/eco_scripts/cell_libraries/tsmc_bwp136.json` with
Liberty-extracted values:
```json
"INR3":   {"ZN": "A1 & ~B1 & ~B2"},               // was: ~(A1 | (B1 & B2))
"IAOI21": {"ZN": "~((A1 & ~A2) | B)"},            // was: ~(A1 | (A2 & B))
// IND3 + IOAI21 — extract from Liberty before patching (not yet verified)
```

**Why pending:** Discovered late in the session; fix is trivial but should
be verified against Liberty for IND3 + IOAI21 before patching.

---

## P2 — Operational hygiene

### JIRA regression harness

**Why pending:** With 8 more JIRAs ahead, every new rule risks breaking past
JIRAs (we already saw 5 misdiagnoses this session). Need an automated
"re-run all known-good JIRAs after every rule change" check.

**Spec:**
- `script/eco_scripts/eco_jira_regression.py` (NEW)
- For each known-good JIRA in a config file:
  - Run AI flow end-to-end against its tile dir (or use cached study/applied JSONs)
  - Compare result to baseline (FM PASS counts per stage)
  - Flag if any baseline regresses
- Run as part of CI / post-commit check

**Estimated effort:** ~100 lines + 1 hour. Configurable list of JIRAs +
their expected baselines.

**When to do:** Before tackling JIRA #3. Without this, every rule change
across the next 8 JIRAs is a roulette wheel.

---

### `eco_pre_fm_checker.md` slim (1052 → ~400 lines)

**Why pending:** Most of the MD duplicates per-check spec text that's
already implemented in `eco_pre_fm_check.py`. Could shrink by ~600 lines if
we replace per-check prose with "run the script + parse the JSON output".

**Risk:** Some rules may live ONLY in the MD (not yet in the script). Need
careful spec/script reconciliation pass first.

**Estimated effort:** ~2 hours of careful diff-reconciliation work.

---

## P3 — Pre-existing inconsistencies (not from this session)

### CRITICAL_RULES.md:355 vs RULE 35 contradiction

**File:** `config/eco_agents/CRITICAL_RULES.md` line 355.

**Issue:** Says "If ALL revised_changes are `action: manual_only` (Mode F2 only)
→ spawn FINAL_ORCHESTRATOR with `status: MANUAL_LIMIT`" — but RULE 35
(line 594) says "MAX_ROUNDS is the ONLY exit (manual_only ABOLISHED)".

**Resolution options:**
- (a) Delete the line 355 clause — fully embrace RULE 35
- (b) Replace MANUAL_LIMIT with progressive strategy (move to next round
      with conservative_constant or try_alternative_pivot)

**Estimated effort:** 5-min edit.

---

### Test scripts cluttering production area

**Files:** `test_pre_fm_checker.py` (266) + `test_step4_step5.py` (744) live
in `script/eco_scripts/` alongside production scripts.

**Resolution:** Move to `script/eco_scripts/tests/` subdirectory.

**Estimated effort:** 2-min move + grep for any references that need
updating.

---

## Summary table

| Priority | Item | Effort | Blocks what |
|----------|------|--------|-------------|
| P0 | Mode S — scan stitching | 1.5–2 hr | 100% FM pass on JIRAs needing new DFFs in main clock domain |
| P1 | Liberty extractor (production) | 2 hr | Auto-adapt to any process node + correct compound-cell truth tables |
| P1 | Fix bundled JSON I-prefix entries | 10 min | Quick win — covers 9868-style cells correctly |
| P2 | JIRA regression harness | 1 hr | Catching regressions across the 8 remaining JIRAs |
| P2 | eco_pre_fm_checker.md slim | 2 hr | MD bloat reduction |
| P3 | CRITICAL_RULES.md:355 cleanup | 5 min | Pre-existing rule contradiction |
| P3 | Move test scripts to subdirectory | 2 min | Production area cleanup |

**Total recommended next-session work for production-ready 8-JIRA campaign:**
~5 hours (P0 Mode S + P1 Liberty extractor + P2 regression harness).

If only one item, do **P1 quick-win bundled JSON I-prefix fix** (10 min).
