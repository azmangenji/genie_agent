# ECO Flow — Future Capability Gaps

Tracker for capabilities the AI ECO flow does NOT yet support but engineer ECO solutions use. Add new gaps as discovered. Each entry: what's missing, why it matters, where to fix.

---

## GAP-1: Real Scan-Chain Bridge Stitching (`bridge_port` strategy)

**Status:** Not implemented. Current `bridge_port` strategy in `eco_netlist_studier` is a stub that ties bridge wires to constants (`1'b0`), which only passes FM but breaks DFT scan testability.

**Discovered in:** DEUMCIPRTL-9868 Round 1 (Route FM failure on `NeedFreqAdj_reg` SE/SI cone divergence).

### What the engineer does

For a Mode S DFF that needs scan stitching across PP/Route stages where CTS renames make `neighbor_dff` strategy fail:

```
DCQARB (sibling of CTRLSW, inside ARB)
├── Existing scan chain: ... → flop_X → FxOptCts_ZBUF_601_289 → flop_Y → ...
│                                       ↑ engineer adds buffer:
│                                       BUF .I(FxOptCts_ZBUF_601_289) .Z(ECO_905_SI_out)
├── Existing scan_en:    FxPlace_HFSNET_27681
│                                       ↑ engineer adds buffer:
│                                       BUF .I(FxPlace_HFSNET_27681) .Z(ECO_905_SE_out)
├── New ports: ECO_905_SI_out (output), ECO_905_SE_out (output), ECO_905_Q_in (input)
└── Splices NeedFreqAdj.Q (via ECO_905_Q_in) as .SI of a downstream flop in DCQARB scan chain

ARB module:
  wire eco905_si_bridge, eco905_se_bridge, eco905_q_bridge ;
  DCQARB inst:    .ECO_905_SI_out(eco905_si_bridge), .ECO_905_SE_out(eco905_se_bridge), .ECO_905_Q_in(eco905_q_bridge)
  CTRLSW inst:    .ECO_905_SI_in(eco905_si_bridge),  .ECO_905_SE_in(eco905_se_bridge),  .ECO_905_Q_out(eco905_q_bridge)

CTRLSW module:
  NeedFreqAdj_reg ( .SI(ECO_905_SI_in), .SE(ECO_905_SE_in), .Q(NeedFreqAdj) )
  assign ECO_905_Q_out = NeedFreqAdj ;
```

### Why it matters

- **FM equivalence**: bridge wires + buffers are NEW post-CTS additions whose names are stable across PP/Route, so REF and IMPL cones match trivially.
- **DFT scan**: NeedFreqAdj_reg stays inside the scan chain — ATPG can scan-test it. Constant-tie shortcut removes the flop from scan permanently.

### Capability gap matrix

| Capability | Current flow | Engineer pattern |
|---|---|---|
| Identify failing DFF needs bridge | ✓ Mode S triage in studier | ✓ |
| Add bridge ports to host module (CTRLSW) | ✓ `eco_passes_2_4 apply_port_decl` | ✓ |
| Declare bridge wires at parent (ARB) | ✓ `apply_assign` | ✓ |
| Drive bridge from constant (1'b0) | ✓ (stub) | ✗ engineer never does this |
| **Pick sibling module to source from** | ✗ | ✓ |
| **Add output ports to sibling** | ✗ | ✓ |
| **Insert buffer cells inside sibling** | ✗ | ✓ |
| **Wire Q back into sibling's scan chain** | ✗ | ✓ |
| **Validate buffer source-wire name stability across stages** | ✗ | n/a (hand-picked) |

### Implementation plan

1. **`eco_netlist_studier`** — when triaging a Mode S DFF that needs `bridge_port` strategy, emit a sibling-bridge triple in the study JSON:
   ```json
   {
     "strategy": "bridge_port",
     "bridge_sibling": {
       "sibling_module": "ddrss_umccmd_t_umcdcqarb_0_0",
       "sibling_inst": "DCQARB",
       "src_si_wire": "test_so1027",
       "src_se_wire": "FxPrePlace_HFSNET_61327",
       "consumer_flop": "<inst_name>",
       "buf_si_name": "eco<jira>_buf_si",
       "buf_se_name": "eco<jira>_buf_se"
     }
   }
   ```
   Heuristic for sibling pick: same parent module, sibling has scan-chain DFFs sharing the same scan_en domain as the host, source wires must exist with identical names in all stage netlists.

2. **`eco_passes_2_4.py`** — new apply functions:
   - `apply_sibling_port_decl(sibling_mod, ports)` — extend sibling module port list + add input/output decls
   - `apply_sibling_buffer(sibling_mod, buf_name, src_wire, dst_port)` — insert buffer cell before endmodule
   - `apply_sibling_scan_splice(sibling_mod, target_flop, new_si)` — rewrite a flop's `.SI` to consume our Q
   - `apply_inst_hookup(parent_mod, inst, port_map)` — append port hookups to existing instance call

3. **`eco_pre_fm_check.py`** — new checks:
   - `[BRIDGE_BUF_NAMING]` — source wires named identically across all stage netlists
   - `[BRIDGE_SCAN_CONSUMED]` — Q output is wired into a downstream flop (no dangling)
   - `[BRIDGE_PORT_INSTANCE_HOOKUP]` — parent instance hookup matches new sibling ports

4. **`eco_validate_step3`** — when study selects `bridge_port`, REQUIRE bridge_sibling triple to be populated.

5. **`eco_fm_analyzer`** — Mode S decision tree extended: if `bridge_port` chosen but FM still failing on same DFF, flag mismatched sibling buffer source.

### Effort

Medium-large. Steps 1–2 are the core implementation; 3–5 are validation/recovery. Biggest risk is sibling selection — needs a robust heuristic to pick wires that survive CTS naming.

### Workaround until implemented

Manual netlist patch (what we did for DEUMCIPRTL-9868 Round 1): hand-author the buffers + bridge wires + instance hookups. Persist the patch script in `data/<tag>_manual_bridge_patch.py` so the next round can replay it.

---

## GAP-2: Mode I Bus Rename Cleanup + Explicit Wire Declaration

**Status:** Bug. Current `_apply_bus_rename` in `eco_passes_2_4.py` half-renames: replaces the wire name in the OUTPUT port concat but (a) leaves the orphan `wire UNCONNECTED_NNNN ;` declaration, and (b) does NOT add an explicit declaration for the new wire (relies on Verilog implicit auto-declare).

**Discovered in:** DEUMCIPRTL-9868 Round 1 (Synth FM failure on `EcoUseSdpOutstRdCnt_reg`, `REG_UmcCfgEco[1]` reported as `Und` (undriven) by FM analyze_points).

### What goes wrong

PreEco netlist (Fusion Compiler output) contains placeholder wires for unused bus bits:
```verilog
wire UNCONNECTED_3287 ;
wire UNCONNECTED_3288 ;   // bit[1] of REG_UmcCfgEco — needed by ECO
wire UNCONNECTED_3289 ;
.REG_UmcCfgEco ( { ..., UNCONNECTED_3287, UNCONNECTED_3288, UNCONNECTED_3289 } )
```

**Engineer's clean rename:**
```verilog
- wire UNCONNECTED_3288 ;
+ wire eco9868_UmcCfgEco_1 ;     // (was UNCONNECTED_3288 = REG_UmcCfgEco[1])
- .REG_UmcCfgEco ( { ..., UNCONNECTED_3287, UNCONNECTED_3288, UNCONNECTED_3289 } )
+ .REG_UmcCfgEco ( { ..., UNCONNECTED_3287, eco9868_UmcCfgEco_1, SplitActCtrPhaseDis } )
INV eco9868_inv_cfg1 ( .I(eco9868_UmcCfgEco_1), ... ) ;
```
ONE wire declared, used twice. Self-contained. No orphans.

**Our flow's broken rename:**
```verilog
  wire UNCONNECTED_3288 ;   ← STILL HERE, no longer used (orphan)
- .REG_UmcCfgEco ( { ..., UNCONNECTED_3287, UNCONNECTED_3288, ... } )
+ .REG_UmcCfgEco ( { ..., UNCONNECTED_3287, n_eco_9868_umccmd_REG_bit1, SplitActCtrPhaseDis } )
AN2 eco_9868_umccmd_d002 ( .A2(n_eco_9868_umccmd_REG_bit1), ... ) ;
//   ↑ n_eco_9868_umccmd_REG_bit1 is NEVER explicitly declared — implicit auto-declare
```

TWO wires for the same conceptual signal: orphan UNCONNECTED + auto-declared new. FM elaboration cannot reliably resolve the connection between umcregcmd output port `REG_UmcCfgEco[1]` and the new ECO logic input → reports `REG_UmcCfgEco[1]` as undriven → cone mismatch with REF → FM fails.

### Implementation plan

1. **`eco_passes_2_4.py` `_apply_bus_rename`** — extend to:
   - DELETE the orphan `wire UNCONNECTED_NNNN ;` line after replacing its usage
   - INSERT explicit `wire <new_name> ;  // ECO <jira> (was UNCONNECTED_NNNN = <bus>[<bit>])` next to other ECO wire declarations
2. **`eco_pre_fm_check.py`** — new check `[MODE_I_RENAME_HYGIENE]`:
   - For each Mode I rename in the study, verify (a) no orphan `wire UNCONNECTED_NNNN ;` remains, (b) renamed wire has explicit `wire ... ;` declaration, (c) renamed wire has at least 2 references (port concat + ECO logic input)
3. **`eco_validate_step3`** — when study has Mode I bus rename targets, REQUIRE both `wire_decl_to_remove` (the UNCONNECTED) and `wire_decl_to_add` (the new name) be tracked.

### Effort

Small (1-2 hours). Pure cleanup of existing apply functions. Low risk.

### Workaround until implemented

Manual netlist patch: delete orphan + insert explicit decl after running `eco_passes_2_4`.

---

## GAP-3: Stage-Aware Bridge Port Plumbing (Mode S `bridge_port` Strategy)

**Status:** Bug. `eco_passes_2_4.py` applies Mode S `bridge_port` plumbing (port additions + parent instance hookups) UNIFORMLY to all 3 stages (Synth/PP/Route). Synth doesn't need bridges (SE/SI are pre-DFT constants), so the plumbing is wasted and creates dangling ports/wires.

**Discovered in:** DEUMCIPRTL-9868 Round 1 (Synth FM failure on `EcoUseSdpOutstRdCnt_reg` — bridge ports added to umccmd + CTRLSW modules but EcoUseSdp_reg/NeedFreqAdj_reg use `.SE(1'b0), .SI(1'b0)` directly, bridge ports left dangling).

### What goes wrong

Engineer's Synth pattern for both ECO DFFs:
```verilog
SDFQD1 EcoUseSdpOutstRdCnt_reg ( ..., .SI(1'b0), .SE(1'b0), .CP(UCLK01) ) ;
SDFQD1 NeedFreqAdj_reg ( ..., .SI(1'b0), .SE(1'b0), .CP(UCLK01) ) ;
```
NO bridge ports added to host modules. NO bridge wires at parent. Direct constant ties.

Our Synth pattern:
```verilog
// CTRLSW module — adds 3 ports for NeedFreqAdj_reg
input ECO_9868_SE_in ;
output ECO_9868_Q_out ;
input ECO_9868_SI_in ;
SDFQD1 NeedFreqAdj_reg ( ..., .SI(1'b0), .SE(1'b0) ) ;     ← bridges UNUSED
assign ECO_9868_Q_out = NeedFreqAdj ;

// umccmd module — adds 3 ports for EcoUseSdpOutstRdCnt_reg
input ECO_9868_umccmd_SE_in ;
output ECO_9868_umccmd_Q_out ;
input ECO_9868_umccmd_SI_in ;
SDFQD1 EcoUseSdpOutstRdCnt_reg ( ..., .SI(1'b0), .SE(1'b0) ) ;   ← bridges UNUSED
assign ECO_9868_umccmd_Q_out = EcoUseSdpOutstRdCnt ;

// ARB module instance hookup
ddrss_umccmd_t_umcarbctrlsw CTRLSW ( ..., .ECO_9868_SI_in(eco9868_si_bridge), ... )
//                                          ↑ eco9868_si_bridge wire NEVER DECLARED in Synth ARB
```

These dangling ports + undeclared bridge wires alter the netlist's elaboration shape enough that FM resolves bus connections (REG_UmcCfgEco[1]) differently than engineer's IMPL.

### Implementation plan

1. **`eco_netlist_studier`** — record `mode_S_strategy_per_stage` with explicit invariant: **Synth = `constant_zero` ALWAYS** (mirror engineer's pattern). PP/Route can choose any of constant_zero/neighbor_dff/bridge_port.
2. **`eco_passes_2_4.py`** — gate bridge plumbing functions (`apply_port_decl` for `ECO_<jira>_*_in/out`, `apply_inst_hookup` at parent, bridge wire declarations) on `if stage in ("PrePlace", "Route"): ...`. SKIP entirely for Synth.
3. **`eco_pre_fm_check.py`** — extend `[MODE_S_BRIDGE_DANGLING]` check:
   - For Synth stage: FAIL if any `ECO_<jira>_*_in` ports were added to any module
   - For PP/Route: existing check (bridge wire must be declared and driven)
4. **`eco_validate_step3`** — when study has any Mode S DFF, verify Synth strategy is `constant_zero` (not bridge_port).
5. **New check `[BRIDGE_PORT_USAGE]`** in `eco_pre_fm_check.py`:
   - For every `ECO_<jira>_*_in` port added to a module, verify at least one DFF in that module references it (`.SE(ECO_<jira>_SE_in)` or `.SI(ECO_<jira>_SI_in)`). FAIL if dangling.

### Effort

Medium (half day). Touches studier strategy resolver + apply functions + 2 pre-FM checks. Low risk (pure subtraction of unnecessary work).

### Workaround until implemented

Manual netlist patch: strip the bridge ports from Synth.v.gz after running `eco_passes_2_4`.

---

## GAP-4: Bridge Port Must Include Sibling SE-Pin Consolidation

**Status:** Bug. Our `bridge_port` strategy in `eco_passes_2_4.py` adds the bridge plumbing (port + buffer + parent hookup) but does NOT REPLACE existing DFF .SE pins in the sibling module to consume the new bridge wire. Engineer always replaces N existing DFFs' .SE pin to use the new bridge — that scan-domain consolidation is a load-bearing part of the pattern.

**Discovered in:** DEUMCIPRTL-9868 Round 1 (Route FM still failing on `NeedFreqAdj_reg` after we implemented bridge buffer + bridge port pattern in DCQARB; engineer's pattern adds buffer AND rewrites 10 DCQARB DFFs to use the bridge).

### What goes wrong

Engineer's bridge in Route DCQARB:
```verilog
// 1. Add buffer (we do this)
GBUFFD1 eco905_buf_se ( .I(FxPlace_HFSNET_27681), .Z(ECO_905_SE_out) ) ;

// 2. Add output port for the bridge (we do this)
output ECO_905_SE_out ;

// 3. REPLACE existing DFFs' .SE pin to use the bridge (WE DON'T DO THIS)
//    Engineer rewrites 10 DCQARB DFFs:
DcqPc_reg_63__MB_..._reg_56_ ( ..., .SE ( ECO_905_SE_out ), ... ) ;     // was: .SE(<CTS-renamed-wire>)
ArbDcq_Winner1_reg_63__MB_..._56_ ( ..., .SE ( ECO_905_SE_out ), ... ) ; // was: .SE(<CTS-renamed-wire>)
DcqInsWr_p2_reg ( ..., .SE ( ECO_905_SE_out ), ... ) ;
DcqInsVld_p2_reg ( ..., .SE ( ECO_905_SE_out ), ... ) ;
TempPmArbWinner_d1_reg_79__MB_..._reg_72_ ( ..., .SE ( ECO_905_SE_out ), ... ) ;
TempPmArbWinner_d1_reg_71__MB_..._reg_64_ ( ..., .SE ( ECO_905_SE_out ), ... ) ;
PcArbWinner_d1_reg_79__MB_..._reg_72_ ( ..., .SE ( ECO_905_SE_out ), ... ) ;
PcArbWinner_d1_reg_71__MB_..._reg_64_ ( ..., .SE ( ECO_905_SE_out ), ... ) ;
PmPcPhArbMskDcqEntryTillCasDone_reg_63__MB_..._reg_56_ ( ..., .SE ( ECO_905_SE_out ), ... ) ;
DcqWrSnp_reg_56__MB_..._reg_63_ ( ..., .SE ( ECO_905_SE_out ), ... ) ;
```

### Why it matters

The SE-pin replacement consolidates a scan domain — many DCQARB DFFs that previously each used a different CTS-cloned scan_en wire now share ONE buffered scan_en wire (`ECO_905_SE_out`). This:
1. **Stabilizes the cone** between PP and Route stages — PP and Route both compare against this consolidated wire, so the SE cone collapses to a single source on both sides
2. **Helps FM's reverse clock-gating analysis** — the LatCG cone trace becomes consistent across REF/IMPL because the SE source is the same
3. **Simplifies post-CTS clean-up** — engineering ECO often consolidates scan paths after CTS optimization spreads them across many cloned wires

Without this step, our bridge buffer is just a passive observer — it captures one signal but doesn't change other DFFs' behavior, so the cone still diverges.

### Implementation plan

1. **`eco_netlist_studier`** — when picking `bridge_port` strategy, additionally identify a list of "consolidation-target DFFs" (DFFs in the bridge's sibling module whose .SE should be rewritten to the new bridge wire). Selection heuristic:
   - DFFs in same scan domain (same scan_en source)
   - Currently using a CTS-renamed wire (e.g., starts with `FxOptCts_*`, `FxPlace_*`, `dftopt*`)
   - Add to study JSON: `bridge_se_consolidation_targets: [{ inst_name, current_se_wire, new_se_wire (= ECO_<jira>_SE_out) }, ...]`
2. **`eco_passes_2_4.py`** — new `apply_se_pin_replace(stage, sibling_mod, target_inst, new_se_wire)` action that rewrites `.SE(<old>)` → `.SE(<new>)` for each consolidation target.
3. **`eco_pre_fm_check.py`** — new check `[BRIDGE_SE_CONSOLIDATION]`:
   - For every `bridge_port` strategy DFF, verify at least N (e.g., 5) sibling DFFs have been rewritten to consume the bridge wire
   - FAIL if bridge buffer exists but no DFFs use its output (dead bridge)
4. **`eco_validate_step3`** — when study contains `bridge_port` strategy, REQUIRE `bridge_se_consolidation_targets` to have entries.

### Effort

Medium-large. Hardest part is the consolidation-target selection heuristic — needs scan-domain analysis (group DFFs by their scan_en source, pick the group containing the bridge buffer's source wire). Alternatively, accept user-specified target list as input.

### Workaround until implemented

Manual netlist patch: identify N sibling DFFs in the bridge's module that share a scan_en source, rewrite their .SE pins to use the new bridge wire output. Persist as `data/<tag>_manual_se_consolidation.py`.

### Risk note

Replacing `.SE` pins changes scan-chain topology — must verify post-replacement DFT still scans correctly. Engineer probably had a separate validation step to confirm scan path remained intact.

### GAP-4 Addendum (DEUMCIPRTL-9868 Round 1, 2026-05-10)

**Critical regression**: First attempt at SE-pin consolidation (manual workaround for GAP-4) was NOT module-scope-aware. Instance names like `DcqPc_reg_63__MB_DcqPc_reg_62__MB...` exist in **multiple module types** (`umcdcqarb_0_0` AND `umcdcqarb_1_0`) because they're generic DCQARB DFF naming. A naïve substring-find-and-replace across the entire netlist text rewired DFFs in BOTH module types — but the bridge port `ECO_9868_SE_out` was only declared/driven inside `umcdcqarb_0_0`. Result: 8 DFFs in DCQARB1 referenced an undeclared/undriven wire → mass DFF0X → **58 failing points** (vs the original 1).

**Lesson (must be enforced when implementing GAP-4 in `eco_passes_2_4.py`):**
1. SE-pin replacement MUST scope to the module body where the bridge port is declared
2. Module boundary detection: locate `^module <target_mod_name>(` then walk to the next `^endmodule` — operate only on that slice
3. Validation check `[BRIDGE_SE_CONSOLIDATION_SCOPE]`: after applying replacements, verify `grep -c "ECO_<jira>_SE_out" <other_module_types>` returns 0

**Workaround now uses:** `script/eco_scripts` Python helper that extracts module body by `^module ... endmodule` boundaries before substituting.

---

## GAP-4b: Bridge Source Wire Must Have Stage-Stable Parent Driver

**Status:** Bug. Our bridge buffer source-wire selection picks an internal name that matches across stages, but does NOT verify the wire's PARENT-LEVEL driver (the net hooked to that port at the parent module's instance call) is stable across PP→Route. CTS often renames the parent driver while keeping the port-internal name → bridge wire effectively traces to different sources in PP vs Route → SE/SI cone STILL diverges across stages even with the bridge in place.

**Discovered in:** DEUMCIPRTL-9868 Round 1 (2026-05-10) — after fixing GAP-4 module-scope (Addendum), Route FM still expected to fail because we chose `FxPrePlace_HFSNET_61327` as buffer SE source. That wire IS an input port to DCQARB module in both PP and Route (so it exists with same name internally), BUT the ARB-level instance hookup is different per stage:

```
PP ARB hookup:    .FxPrePlace_HFSNET_61327( FxPrePlace_HFSNET_33188 )
Route ARB hookup: .FxPrePlace_HFSNET_61327( FxPlace_HFSNET_30406 )       ← CTS renamed
```

Engineer picked `FxPlace_HFSNET_27681` instead — almost certainly because that wire's ARB hookup IS the same wire in both PP and Route.

### What goes wrong

`ECO_<jira>_SE_out` is buffered from a wire that ENTERS DCQARB via a port. FM elaborates the cone:
- REF (PP):  `ECO_9868_SE_out` ← buffer ← DCQARB.in_port `FxPrePlace_HFSNET_61327` ← parent ARB drives `FxPrePlace_HFSNET_33188`
- IMPL (Route): `ECO_9868_SE_out` ← buffer ← DCQARB.in_port `FxPrePlace_HFSNET_61327` ← parent ARB drives `FxPlace_HFSNET_30406`

The DCQARB internal portion looks identical across stages, but the parent-level drivers are different wires. FM's cone trace can't reconcile them → "globally unmatched" cone for any DFF whose SE was rewired to use this bridge.

### Implementation plan

1. **`eco_netlist_studier`** — when picking a `bridge_port` source wire, REQUIRE that wire to satisfy:
   - (a) Internal name must exist with the same name in target_module across all 3 stages
   - (b) **PARENT-LEVEL hookup** at the module's instance call (in the parent module body) must reference the SAME wire-name in PP and Route stages
   - Add `bridge_source_wire_validation` field to study JSON with: `internal_name`, `pp_parent_driver`, `route_parent_driver`, `pp_route_match: true|false`
   - If no candidate satisfies both, fall back to: walk top-level umccmd input port hierarchy looking for a port that propagates unchanged through CTS

2. **`eco_passes_2_4.py`** — REJECT bridge source wires with `pp_route_match: false`. Emit error rather than silently producing a divergent bridge.

3. **`eco_pre_fm_check.py`** — new check `[BRIDGE_SOURCE_PARENT_STABILITY]`:
   - For each `bridge_port` strategy, look up the buffer's input wire in the parent module's instance hookup
   - Compare PP vs Route hookup; FAIL if drivers differ

4. **Helper script** `script/eco_scripts/eco_find_stable_scan_en_wire.py`:
   - Inputs: tile, sibling module name, parent module name
   - Output: list of candidate wires (name, pp_parent_driver, route_parent_driver, scan_en_usage_count) — analyzer / studier picks the best

### Effort

Medium. The candidate-search logic is the only non-trivial part; the validation checks are mechanical.

### Workaround until implemented

Manual: for each ECO bridge buffer, hand-grep the parent's instance hookup for the source wire in BOTH PP and Route netlists; pick wires whose right-hand-side matches. If none match, fall back to a top-level umccmd input port that's known stable through CTS.

---

## GAP-4c: Bridge Q Output Must Close Scan Chain at Sibling Module

**Status:** Bug. Our `ECO_<jira>_Q_in` (the bridge port that returns NeedFreqAdj.Q to the sibling module) is left as a DANGLING input port inside the sibling module. Engineer wires that returned Q into a sibling DFF's `.SI` pin to close the scan chain — keeping the new ECO DFF as a real participant in DFT scan, AND giving FM a unified scan-chain cone shape.

**Discovered in:** DEUMCIPRTL-9868 Round 1 (2026-05-10) — diff between our Route and engineer's Route showed:

```
Engineer DCQARB consumer of ECO_905_Q_in:
   .SI ( ECO_905_Q_in ) , .SE ( ECO_905_SE_out ) , .CP ( FxCts_ZCTSNET_78 ) , …
   (one DCQARB DFF takes NeedFreqAdj.Q via the bridge as its scan-input)

Our DCQARB consumer of ECO_9868_Q_in:
   (none — port is dangling)
```

### What goes wrong

1. **DFT scan break**: NeedFreqAdj_reg has its `.SI` driven by the bridge (good — picks up scan data from sibling), but its `.Q` doesn't go anywhere in the scan chain. The scan chain is broken at NeedFreqAdj. Post-silicon ATPG cannot scan-test downstream of NeedFreqAdj_reg properly.

2. **FM elaboration**: A dangling input port may cause FM to emit warnings or treat the port as an `Und` cut-point. While not always fatal, it adds noise to analyze_points and may interact badly with set_constant SE=0 cone collapsing.

### Implementation plan

1. **`eco_netlist_studier`** — when emitting `bridge_port` strategy, also emit a `bridge_q_consumer` field:
   - `consumer_dff_inst`: an existing DFF instance in the sibling module whose `.SI` will be replaced
   - `consumer_dff_original_si`: the original `.SI` net for safekeeping
   - Selection heuristic: pick a DFF whose `.SE` is already (or about to be) consolidated to use the bridge `.SE` (so the new SI source is consistent with the SE cone)

2. **`eco_passes_2_4.py`** — new apply action `apply_si_consumer_replace`:
   - Within sibling module body, find the chosen DFF instance, rewrite its `.SI` from the original net to `ECO_<jira>_Q_in`

3. **`eco_pre_fm_check.py`** — new check `[BRIDGE_Q_CONSUMED]`:
   - For each declared `ECO_<jira>_Q_in` port, verify at least one DFF in that module references it (`.SI(ECO_<jira>_Q_in)`)
   - FAIL if dangling

### Effort

Small (1-2 hours). The consumer selection is constrained by GAP-4 (consolidation list) — pick any DFF from that list whose original `.SI` is a CTS-renamed wire (since we're going to rewire it anyway).

### Workaround until implemented

Manual: pick one DFF in the sibling module that's already in the SE-consolidation list, replace its `.SI` with `ECO_<jira>_Q_in`. Persist as `data/<tag>_manual_q_consumer.py`.

### Risk note

Changing a DFF's `.SI` rerouts the scan chain — must verify the original chain doesn't break elsewhere. Engineer presumably picked a DFF whose original SI source is now redundant after the consolidation. Need to think through chain integrity before generalizing this.
