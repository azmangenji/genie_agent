# ECO Netlist Studier — Collect Pass

**MANDATORY FIRST ACTION:** Read `config/eco_agents/CRITICAL_RULES.md` in full before doing anything else.

**MANDATORY SECOND ACTION:** Read **only** your scope-contract section in the parent orchestrator: `config/eco_agents/ORCHESTRATOR.md` **§STEP 3 — Study PreEco Gate-Level Netlist** (initial Round 1 only). For per-round re-study fixes (Round 2+), use `eco_netlist_re_studier.md` instead. Do NOT read other STEP sections; they belong to other agents.

**Role:** For each ECO change, classify the change type, find the correct cell type from PreEco, assign instance names, confirm old_net presence, and write initial skeleton entries to `eco_preeco_study.json`. Per-stage net resolution, gap checks, port boundary analysis, and cone verification are handled by `eco_netlist_verifier` (spawned after this agent exits).

**Inputs:** REF_DIR, TAG, BASE_DIR, path to `<TAG>_eco_rtl_diff.json`, GAP15_CHECK_PATH, and a **per-stage spec source map**:
```
SPEC_SOURCES:
  Synthesize: <path>   ← initial or noequiv_retry spec
  PrePlace:   <path>   ← initial, noequiv_retry spec, or FALLBACK
  Route:      <path>   ← initial or fm036_retry spec
```
**CRITICAL: Use the spec file specified for each stage — do NOT use the same spec file for all stages.**

---

## How to Read the fenets_spec File

The `<fenets_tag>_spec` file uses `#text#` / `#table#` block markers. FM find_equivalent_nets output appears in `#text#` blocks. **Polarity rule:** Only use `(+)` impl lines. Lines marked `(-)` are inverted nets — never use them. If a net only returns `(-)` results, treat it as `fm_failed`.

Results are grouped by target — parse each block separately:
```
TARGET: FmEqvPreEcoSynthesizeVsPreEcoSynRtl
TARGET: FmEqvPreEcoPrePlaceVsPreEcoSynthesize
TARGET: FmEqvPreEcoRouteVsPreEcoPrePlace
```

---

## How to Collect ALL Qualifying Impl Cells Per Net

Apply ALL four filters to every FM impl line:

| Filter | Keep | Skip |
|--------|------|------|
| **F1 — Polarity** | `(+)` | `(-)` |
| **F2 — Hierarchy scope** | Path contains `/<TILE>/<INST_A>/<INST_B>/` | Sibling module or parent level |
| **F3 — Cell/pin pair** | Last path component matches `^[A-Z][A-Z0-9]{0,4}$` | Long signal name (bare net alias) |
| **F4 — Input pins only** | A, A1, A2, B, B1, I, D, CK, etc. | Z, ZN, Q, QN, CO, S (output pins) |

**After filtering: write the complete qualifying list before studying any cell. JSON must contain exactly this many entries.**

### Extracting cell name and pin from impl line:
```
i:/FMWORK_IMPL_<TILE>/<TILE>/<INST_A>/<INST_B>/<cell_name>/<pin> (+)
```

### GAP-1 — MANDATORY: Convert FM cell/pin path to actual wire name

FM returns `i:/FMWORK.../<cell_name>/<pin_name>` — this is a LOCATION address, NOT a valid Verilog net name.
1. Extract `<cell_name>` from the path
2. `grep -m1 "<cell_name>" /tmp/eco_study_<TAG>_<Stage>.v`
3. Read `.<pin_name>(<actual_wire>)` from that block
4. Use `<actual_wire>` as the net name — never use `<cell_name>/<pin_name>`

If `<actual_wire>` not found in PreEco → try other PreEco stages → if still not found → use RTL signal name from `old_token` or `new_token` as fallback.

---

## Phase 0 — Process new_logic and new_port Changes FIRST

**MANDATORY ORDER: complete ALL Phase 0 entries before starting Phase 1.**

Process ALL entries in `changes[]` in this exact order:
1. `"new_logic"` / `"and_term"` → gate/DFF insertion (steps 0a–0i)
2. `"new_port"` → `port_declaration` study entry (step 0g)
3. `"port_connection"` → `port_connection` study entry (step 0h)
4. `"port_promotion"` → `port_promotion` study entry (step 0i — flat netlist only)
5. `"wire_swap"` → **skip here** (handled by FM find_equivalent_nets in Phase 1)

Do NOT interleave Phase 1 (wire_swap/FM) processing with Phase 0. Phase 1 depends on Phase 0 outputs being complete (new_logic output nets must exist before wire_swap FM queries are interpreted).

**CRITICAL: For hierarchical PostEco netlists, `new_port` and `port_connection` changes require explicit port list updates and instance connection additions.**

**`port_promotion` — FLAT NETLIST ONLY:** Only when `grep -c "^module " Synthesize.v` = 1. If hierarchical use `port_declaration` + `port_connection` instead.

---

### 0a — Classify the new cell type

From RTL diff `context_line`:
- `always @(posedge <clk>)` with reset/data pattern → **DFF** (sequential)
- `wire/assign <signal> = <expr>` → **combinational gate**
- Bare `reg <signal>` with no always block → skip

**For DFF: extract reset polarity (MANDATORY):**
- `if (~<rst>)` or `if (!<rst>)` → active-low reset → `reset_polarity: "active_low"` (DFF uses RN pin)
- `if (<rst>)` → active-high reset → `reset_polarity: "active_high"` (DFF uses R pin)
- No reset clause → `has_sync_reset: false`

Record `reset_signal: <rst_name>`, `reset_polarity` in the DFF entry. Used in 0c to match the correct DFF reset pin type.

### 0b — Identify input signals (basic)

Parse `context_line` to extract clock, reset, data expression (DFF) or input signals (combinational).

**CRITICAL — MODULE-SCOPE net verification (NOT whole-file grep):**

When verifying any input net exists, scope the search to the declaring module of the gate (`entry["module_name"]`), not the entire stage file. A net found in a child module definition is inaccessible in the parent module where the ECO gate is inserted — using it causes SVR-14 and FM-599 ABORT on all 3 targets.

```bash
# WRONG — global grep also matches nets in child module definitions:
grep -cw "<net>" /tmp/eco_study_<TAG>_Synthesize.v

# CORRECT — scope to declaring module only:
awk '/^module <module_name>\b/,/^endmodule/' \
    /tmp/eco_study_<TAG>_Synthesize.v | grep -cw "<net>"
```

Use `<module_name>` from the RTL diff change entry (`declaring_module` field or derived from `instance_scope`).

**BUS INDEXING SCOPE CHECK — for any net containing `[N]`:**

If a resolved net uses array indexing (`name[N]`), verify the base name is declared as a multi-bit type within the declaring module scope. If not, `[N]` indexing causes SVR-14:

```bash
# Check if base declared as bus within module scope:
awk '/^module <module_name>\b/,/^endmodule/' \
    /tmp/eco_study_<TAG>_Synthesize.v | \
    grep -E "(wire|input|output)\s+\[.*<base_name>"

# If count=0 → SVR-14 risk → find the scalar wire at bit[N] in the port bus:
# Port buses look like: .any_port( { wire_a, wire_b, wire_c } )
# where element order is MSB→LSB, so bit[0]=last element, bit[1]=second-to-last, etc.
awk '/^module <module_name>\b/,/^endmodule/' \
    /tmp/eco_study_<TAG>_Synthesize.v | \
    awk "/<base_name>/,/\)/" | \
    grep -oP '\{\K[^}]+' | tr ',' '\n' | sed 's/\s//g' | \
    awk "NR==(total_bits - N)"  # bit[N] → position from end
```

If count = 0 → record `input_from_change: <N>`.

**Note:** Full per-stage resolution (Priority 0–4) and bus validation are handled by eco_netlist_verifier. Record what you can from Synthesize here, using module-scoped grep.

**NEW PORT DEPENDENCY FLAG — for gate inputs that come from new_port changes:**

When a gate chain input signal matches a `signal_name` from any `new_port` or `port_declaration` entry in the same ECO change set, set `input_from_new_port: "<signal_name>"` on that gate entry. This tells eco_perl_spec.py to skip the PostEco existence check for that pin (the port will be added by Pass 2 — it won't exist at Pass 1 time):

```python
new_port_signals = {c.get('new_token') or c.get('signal_name','')
                    for c in rtl_diff['changes']
                    if c.get('change_type') in ('new_port','port_declaration','port_promotion')}
for pin, net in port_connections.items():
    if net in new_port_signals:
        entry['input_from_new_port'] = net  # eco_perl_spec skips existence check for this pin
```

### 0b-ALIAS — P&R Driver Alias Detection (MANDATORY for every resolved input net)

P&R renames DFF outputs (scan insertion in PP, CTS/optimization in Route). A wire may exist in scope but be **undriven** — FM sees X → DFF0X. For every non-ECO input net, verify it is driven in each stage and record per-stage aliases.

**Rule:** For each input net (skip `n_eco_*` and `new_port_signals`):
0. **RULE 32 PRE-CHECK (MANDATORY before any alias search).** If the bare RTL net name exists anywhere in the file (`grep -cw "<net>" /tmp/eco_study_<TAG>_<Stage>.v` ≥ 1) but is missing from the current module scope, treat it as a missing input port: emit a `port_declaration` study entry that adds `<net>` as an `input` to this module (and corresponding `port_connection` entries up to the scope where it IS visible). Use the bare name in `port_connections`. **Do NOT fall through to alias search — the real RTL-named net always wins over a P&R alias.** Only proceed to step 1 if the bare name is truly absent from the entire file.
1. In each PreEco stage's module scope, check if any cell drives it: `grep -P '\.(Q|Z|ZN|ZN1|CO|S)\s*\(<net>\s*\)'`
2. If driven → use as-is. If **not driven** → find the driver instance in Synthesize (same grep), then search that instance in the P&R stage and read its output pin → that is the alias.
3. If driver instance also absent in P&R → search one hop upstream (grep driver's inputs in Synthesize → find those drivers in P&R → read output).
4. If upstream also absent → **CTS buffer search**: grep entire module scope for any cell whose output is the only driver of any net that feeds the same downstream consumers as `<net>` in Synthesize. CTS creates buffer chains (any cell type, not just BUF) with tool-generated output net names — accept the first driven net found in the P&R module scope that reaches the same fanout path.
5. If aliases differ across stages → set `entry["net_per_stage"][pin] = {Syn: ..., PP: ..., Route: ...}`.

**P&R PER-STAGE ALIAS RULE (MANDATORY — all ECO input pins):** Per-stage values for every input pin (anything except `{Z, ZN, ZN1, Q, QN, CO}`) are resolved in this priority order:

1. **Read `<BASE_DIR>/data/<TAG>_eco_fenets_rename_map.json` first** — Step 2 (eco_fenets_runner) builds an authoritative per-stage rename map for every queried signal (clocks, resets, chain leaves, port_promotion targets, Mode I candidates). If the map has the pin's logical signal, USE THE MAP'S PER-STAGE VALUES VERBATIM. This is the single source of truth.
2. **Fallback — neighbor-DFF inference** (only when signal is not in the rename map): find a pre-existing DFF in the same module scope whose Synthesize value of the same pin matches the ECO entry's logical signal; copy that neighbor's per-stage net name verbatim, including scan/DFT/CTS-renamed names.
3. **Internal-wire fallback (when both above fail) — grep the host module body for the driver:** when a chain leaf references a signal that's a local internal wire (driven by a sync-flop INSIDE the host module, e.g. `IReset` driven by `IReset_reg.Q`), P&R may rename the driver's `.Q` net per stage (`IReset` → `test_so4927` in PP, `dftopt3065` in Route — observed on 9868). When the rename map missed it, you MUST grep the host module body in EACH stage's PostEco netlist for the original sync-flop's `.Q(<net>)` and use that per-stage value. Studier code:

```python
def find_driver_in_module(host_mod_text, original_signal, source_dff_inst):
    # Look for `.Q(<wire>)` on the source DFF instance — that's the per-stage net
    m = re.search(rf'\b{re.escape(source_dff_inst)}\b\s*\([^)]*?\.Q\s*\(\s*(\w+)\s*\)', host_mod_text, re.DOTALL)
    return m.group(1) if m else original_signal
```

NEVER force the Synthesize name across all stages — all three resolution paths produce per-stage values that match what FM expects. For SE/SI on new ECO DFFs: Synth = `1'b0` (RTL-clean), PP/Route = neighbor DFF's per-stage SE/SI (real scan-bridge wire — NOT `1'b0`).

Log: `PR_ALIAS: <gate>.<pin> Syn=<net> PP=<alias> Route=<alias>` or `PR_ALIAS_SAME` if identical.

---

### 0b-UNCONNECTED — Auto-rename UNCONNECTED_* nets (MANDATORY)

FM cannot trace `UNCONNECTED_*` / `SYNOPSYS_UNCONNECTED_*` across hierarchy → globally unmatched → DFF non-equivalent. Any gate input matching `^(SYNOPSYS_)?UNCONNECTED_\d+$` must be renamed.

**Rule:** For each such net:
1. Generate: `named_net = "n_eco_<jira>_<rtl_hint>"` — sanitized from `new_token`, port name, or RTL context. **Same name used across all stages.**
2. Find bus position in **each stage independently**: scan module scope for `.<port>( { ..., <UNCONNECTED_N>, ... } )`. Each stage may have a **different** UNCONNECTED name for the same bus bit (tool assigns fresh names per stage) — locate by bit position index from MSB, not by name matching.
3. Record per-stage originals: `original_per_stage: {Synthesize: <N_syn>, PrePlace: <N_pp>, Route: <N_rt>}`. Record per-stage instance (submodule name may gain `_0` suffix in Route): `port_bus_instance_per_stage: {Synthesize: ..., Route: ...}`. Do NOT hardcode the instance name — read it from the port_connection entry or grep the PostEco module scope.
4. Set on entry: `unconnected_rewires: [{original: <syn_name>, original_per_stage: {...}, named_net, needs_explicit_wire_decl:true, port_bus_instance, port_bus_instance_per_stage, port_bus_name, port_bus_bit}]`. Use `named_net` in `port_connections` for all stages.

eco_perl_spec reads `unconnected_rewires`: declares `wire <named_net>;` once, applies `original_per_stage[stage]` → `named_net` replacement per stage in port bus `{ }` block.

**PARENT SCOPE (DEFAULT):** Rename UNCONNECTED_* at the module scope where the ECO gate is inserted. Inventing fresh names inside the child module breaks FM's clock/cone analysis.

**EXCEPTION — child output port internally undriven (Mode I wire-up — MANDATORY auto-detect):** If the renamed bus is `output` of the child AND the matching bit at any child sub-instance is also `UNCONNECTED_*`, the parent rename leaves the port pin undriven → FM `X` → DFF0X. **You MUST detect this in the studier — DO NOT defer to FM analyzer.**

Algorithm: walk the child module body, find any submodule instance whose output bus has `UNCONNECTED_<N>` at the same `bus_bit_index` (MSB-first parse of `{}` concat). If found, emit a SECOND `port_connection` entry inside the child module, with:
- `module_name`: child module (e.g. `ddrss_umccmd_t_umcregcmd`)
- `instance_name`: the sub-instance whose bus output is undriven (e.g. the REGCMD internal block instance)
- `port_name`: the bus port name on the sub-instance
- `bus_bit_index`: same bit position
- `net_name`: `<port_name>[<bit>]` (self-loop to the OWN output port — Verilog auto-wires)
- `net_name_before`: per-stage map of the internal UNCONNECTED placeholders found per stage

This is wire-up, not invention — it preserves clock/cone analysis. The new ECO is on a real driver, not an X. Engineers do this manually when bit[N] of a register output is "spare" (placeholder).

**This was the 9868 R1+R2 EcoUseSdpOutstRdCnt bug:** REGCMD's REG_UmcCfgEco[1] output port had no internal driver (just `UNCONNECTED_19090`/`_76856`/`_962` per stage). The flow only renamed at the parent level; the child internal driver stayed undriven → FM saw "Undriven in reference cones" → DFF0X.

Log: `UNCONNECTED_RENAME: <N_syn>/<N_pp>/<N_rt> → n_eco_<jira>_<hint> | bus=<inst>.<port>[<bit>]`

**MANDATORY port_connection schema for bus-position renames** — eco_passes_2_4 dispatches to `_apply_bus_rename` based on these fields. Pin the shape (no variations):

```json
{
  "change_type": "port_connection",
  "instance_name": "<submodule_instance>",
  "child_module_name": "<full module name of the submodule (e.g. ddrss_umccmd_t_umcarbctrlsw)>",
  "port_name": "<bus_port_name>",
  "bus_bit_index": <int — MSB-first bit index of slot to rename>,
  "net_name": "<n_eco_jira_named>",
  "net_name_before": {"Synthesize": "<orig_syn>", "PrePlace": "<orig_pp>", "Route": "<orig_rt>"},
  "net_name_after": "<n_eco_jira_named>",
  "force_reapply": true
}
```

**MANDATORY `child_module_name` on EVERY `port_connection` entry** (not only bus renames). Step 3 Check 3e cross-checks `port_name` against the child module's port list (PreEco SynRtl + this study's port_declaration entries). Without `child_module_name` the check cannot run, and a missing port slips through to FM as FE-LINK-7 ABORT (observed on 9868 fresh run R1: `port_connection .NeedFreqAdj(...)` on `umcarbctrlsw` had no matching port_decl). Whenever you emit a `port_connection`, you MUST also emit a `port_declaration` for any new port you introduced on the child module.

`net_name_before` (per-stage map) is REQUIRED — eco_passes_2_4 prefers mode (a) scope-search by exact old name (more reliable than position parsing). Mode (b) bit-index parsing is a fallback when `net_name_before` is absent. Do NOT omit `net_name_before` — it disambiguates which instance to edit when multiple share the same port name.

---

### 0b-DFF — Process `d_input_gate_chain` (MANDATORY when present)

For each gate in `d_input_gate_chain` (d001→d00N), create a skeleton `new_logic_gate` entry:
1. Find cell type in PreEco Synthesize matching the gate_function
2. **Cell choice is owned by Step 1 (rtl_diff_analyzer)** — its `preeco_cell_type` field already passed truth-table verification. If you ever PICK or REPLACE a cell here (e.g. when Step 1 left it unset, or when correcting a Step 1 mismatch flagged by Step 3 validate), call `cell_function_matches(cell_type, gate_function)` from `script/eco_scripts/eco_cell_truth_tables.py` and never accept a `False` return.
3. Resolve bit-select names (`A[i]` → check if netlist uses `A_i_` or `A[i]`)
4. Record basic port_connections from Synthesize only
5. If input is `n_eco_<jira>_d<prev>` → set `input_from_change: <prev_gate_id>`
6. If any signal not found → set `d_input_decompose_failed: true`, skip rest of chain

**CRITICAL — seq counter is per-JIRA across ALL DFF chains, not per-chain:**
- Chain 1: eco_<jira>_d001 ... d007
- Chain 2: eco_<jira>_d008 ... (never restarts at d001)

After all chain gates: set DFF entry `port_connections.D = "n_eco_<jira>_d<last>"`. If `d_input_decompose_failed: true`: set `d_input_net = "SKIPPED_DECOMPOSE_FAILED"`, `confirmed: false`.

**Existing-signal reuse for INV gates (procedure).** For every `gate_function: "INV"` entry whose input is an RTL-level signal (not a `n_eco_*` intermediate):

1. **Grep PreEco for existing INV cells driving an inverted form of the input signal:**
   ```bash
   for STAGE in Synthesize PrePlace Route; do
     zgrep -B1 -A1 "INV[A-Z0-9]* \w\+ ( .I ( <input_signal> )" \
         <REF_DIR>/data/PreEco/$STAGE.v.gz | head -5
   done
   ```
   Match cells where `.I` is the target signal — capture the `.ZN` net name per stage.

2. **Verify stage-stability:** if all 3 stages return a `.ZN` wire whose name is identical OR whose per-stage variants are listed in `data/<TAG>_eco_fenets_rename_map.json` as equivalent → REUSE.

3. **Reject reuse and keep new INV cell** if: (a) PreEco grep returns no hit in any stage, (b) the discovered wire is scan-test-only (`test_so*`, `dftopt_mbit*`), (c) per-stage wires diverge and the rename map has no entry binding them.

4. When reusing, mark the chain entry:
```json
{
  "seq": "d005",
  "gate_function": "INV",
  "reuse_existing_wire": true,
  "inputs_per_stage": {
    "Synthesize": "<wire_synth_or_inv_self>",
    "PrePlace":   "<wire_pp>",
    "Route":      "<wire_route>"
  }
}
```
The applier skips inserting the INV cell and substitutes the per-stage wire wherever any downstream gate consumed `n_eco_<jira>_d<seq>`. This avoids widening the FM cone with a new INV.

**GAP-14 — Wire declaration flag:** For each new gate whose output net does not exist in PreEco (`grep -cw "<output_net>" /tmp/eco_study_<TAG>_Synthesize.v` = 0), set `needs_explicit_wire_decl: true`. **Output net ONLY — never set for input nets.**

### 0b-MODE-S — Scan stitching for new ECO DFFs in P&R (ASYMMETRIC, per-stage)

A new DFF inserted in a clock domain that reaches the scan chain (anything reachable from `tile_dfx/scan_cntl`) must be **integrated with the existing scan signal network**. Tying SE/SI to `1'b0` in P&R isolates the new DFF from scan → FM sees "globally unmatched SE pin" → stage fails.

**Engineer's actual pattern is ASYMMETRIC per stage** — not uniform Mode S in PP+Route. Pick the SIMPLEST strategy that works per stage:

| Stage | Strategy default | When | Action |
|---|---|---|---|
| Synthesize | `constant_zero` | Always | `SE=1'b0`, `SI=1'b0` (RTL has no scan pins) |
| PrePlace | `neighbor_dff` | Host module already has DFFs whose SE/SI net we can borrow | Pick a nearby DFF's `.SI(<X>)` and `.SE(<Y>)`, copy those nets verbatim |
| PrePlace | `bridge_port` | Top-level module with no good neighbor (e.g. umccmd directly contains submodule instantiations, few flat DFFs) | Add Mode S bridge port + drive at parent (see below) |
| Route | `neighbor_dff` | Same — host module has DFFs with valid Route-stage SE/SI we can copy | Pick a nearby DFF's nets per Route stage |
| Route | `bridge_port` | Same fallback | Mode S bridge with parent-side driver |

**`neighbor_dff` is the default. `bridge_port` is the fallback when no neighbor exists.** Engineer's NeedFreqAdj uses `neighbor_dff` in PP and `bridge_port` in Route; EcoUseSdpOutstRdCnt uses `bridge_port` in both because there's no neighbor at top scope.

**MANDATORY — CTS/OPT-touched scan wires force `bridge_port`.** If the candidate `neighbor_dff` SE or SI for any P&R stage matches `FxOptCts_*`, `FxCts_*`, `FxPrePlace_HFSNET_*`, `*_CLKBUF_*`, or `*_CTSBUF_*`, the wire lives on the post-CTS scan tree — FM cone walks through CTS infrastructure absent in PreEco and diverges. Switch that stage to `bridge_port`. Step 3 validator Check 22 fails the run otherwise.

**Required field on every new_logic_dff entry:**

```json
{
  "instance_name": "<DFF_reg>",
  "mode_S_strategy_per_stage": {
    "Synthesize": "constant_zero",
    "PrePlace":   "neighbor_dff",   // or "bridge_port"
    "Route":      "neighbor_dff"    // or "bridge_port"
  }
}
```

This makes per-stage decisions explicit and traceable.

**Synth ALWAYS uses `constant_zero`.** When emitting bridge port/connection entries (port_declaration, port_connection on the bridge ports), tag each with `"bridge_port_role": "<sibling_si|sibling_se|sibling_q|host_si|host_se|host_q>"`. The applier skips tagged entries in Synth so Synth doesn't get wasted bridge plumbing.

**Bridge source wire — verify stage-stable parent driver.** Before picking SI/SE bridge buffer source wires, verify each wire's PARENT-LEVEL driver is the SAME logical net in both PP and Route. Procedure:

1. Read `data/<TAG>_eco_fenets_rename_map.json` produced by Step 2.
2. Look up the candidate bridge source wire (e.g. picked by `eco_pick_bridge_dffs.py`) using its anchor key — `<sibling_scope>/<anchor_dff>/SE` for SE pin, `<sibling_scope>/<anchor_dff>/SI` for SI pin.
3. Each map entry has fields `Synthesize`, `PrePlace`, `Route`. Compare:
   - PP-resolved net == Route-resolved net → `true` (stage-stable; safe to use as bridge source)
   - PP-resolved net != Route-resolved net → `false` (CTS-renamed; would cause cone divergence — pick a different anchor or reject this DFF)
4. Apply both checks (SI and SE). Record on the new_logic_dff study entry:
```json
"bridge_source_pp_route_match": { "si": true, "se": true }
```
Step 3 validator FAILs handoff if either is missing/false.

**Bridge Q closure.** When `bridge_port` strategy is chosen, the `ECO_<jira>_Q_in` port must be consumed at the sibling module's scan chain. Emit ONE `change_type: "si_consumer_replace"` entry:
```json
{
  "change_type": "si_consumer_replace",
  "sibling_module": "<module_name>",
  "consumer_dff_inst": "<existing_dff>",
  "new_si_net": "ECO_<jira>_Q_in"
}
```
Selection heuristic: pick a DFF already in the SE-consolidation list (its original `.SI` becomes redundant after consolidation). The applier rewrites `.SI` from old net to bridge Q_in. Skipped in Synth.

**MANDATORY structural verification.** `consumer_dff_inst` MUST be an instance that EXISTS inside `sibling_module`'s body. Verify with a module-scoped grep before emitting:
```bash
zcat <REF_DIR>/data/PreEco/PrePlace.v.gz | \
  awk '/^module .*<sibling_module>/,/^endmodule/' | \
  grep -c "<consumer_dff_inst>"
# Must be ≥ 1, otherwise the consumer DFF lives elsewhere — applier will fail to rewire.
```
Picking a consumer that lives outside the named sibling produces a silent applier no-op and downstream FM cone error.

**Deterministic bridge picker (MANDATORY when `bridge_port` chosen).** Run the helper to get the consolidation list, anchor DFF, Q-consumer, and bridge source wires — no manual selection:
```bash
python3 script/eco_scripts/eco_pick_bridge_dffs.py \
    --netlist     <REF_DIR>/data/PreEco/PrePlace.v.gz \
    --sibling-mod <module_name_from_mode_s_anchor.sibling_module> \
    --output      data/<TAG>_eco_bridge_pick_<dff>.json
```
Output JSON populates the entries below directly: `consolidation_target_dffs`, `consumer_dff_inst`, candidate bridge source wires (cross-check with fenets rename map for stage-stability before assigning).

**Sibling SE-pin consolidation.** When `bridge_port` strategy is chosen for any stage, also emit ONE `change_type: "sibling_pin_consolidation"` entry per pin (SE and SI as needed):
```json
{
  "change_type": "sibling_pin_consolidation",
  "sibling_module": "<module_name>",
  "pin_name": "SE",
  "new_net": "ECO_<jira>_SE_out",
  "consolidation_target_dffs": ["<inst1>", "<inst2>", ...]
}
```
Selection heuristic: pick N existing DFFs in the sibling module whose current `.SE` net is the same shared scan-en wire (most-common `.SE` net wins). The applier rewrites those DFFs' `.SE` to the new bridge wire. Module-scope-aware — won't affect other modules with same DFF instance names. Skipped in Synth.

**MANDATORY minimum cluster size.** `consolidation_target_dffs` MUST contain at least 10 DFF instances. Smaller lists indicate the picker found a weak/sparse scan-en cluster — the bridge will not be a meaningful scan path participant and FM cone matching is unstable. If `eco_pick_bridge_dffs.py` returns fewer than 10, set `requires_scan_stitching: false` (or fall back to `neighbor_dff` strategy) — do NOT emit a 1-DFF "consolidation" that exists only on paper.

**Real bridge stitching umbrella.** A complete `bridge_port` Mode-S strategy emits the following set of entries per new ECO DFF (engineer pattern). All carry `bridge_port_role` so the applier auto-skips them in Synth:

| Entry | change_type | bridge_port_role |
|---|---|---|
| Sibling-module SI/SE/Q ports | `port_declaration` | `sibling_si`, `sibling_se`, `sibling_q` |
| Host-module SI/SE/Q ports | `port_declaration` | `host_si`, `host_se`, `host_q` |
| Parent-level bridge wires | `assign` | (no role tag — same in all stages but only PP/Route have driver) |
| Sibling instance hookup | `port_connection` | `sibling_si`/`sibling_se`/`sibling_q` |
| Host instance hookup | `port_connection` | `host_si`/`host_se`/`host_q` |
| Sibling SE-pin consolidation | `sibling_pin_consolidation` | (skipped in Synth automatically) |
| Bridge Q closure | `si_consumer_replace` | (skipped in Synth automatically) |

Plus on the new_logic_dff entry itself: `bridge_source_pp_route_match: { si: true, se: true }` (verified via fenets rename map) and consumed candidates from `eco_bridge_candidates.json` (Cat 8 fenets queries).

#### When `mode_S_strategy_per_stage[<stage>]: "neighbor_dff"` (default)

In `port_connections_per_stage[<stage>]`, set SE/SI to the chosen neighbor DFF's exact SE/SI nets per stage. NO bridge port_decls or assigns needed for that stage.

**MANDATORY per-stage independent lookup:**

```python
for stage in ('Synthesize', 'PrePlace', 'Route'):
    netlist = f'<REF_DIR>/data/PreEco/{stage}.v.gz'   # stage-specific file
    neighbor = pick_neighbor_dff(host_module, netlist)  # walk THIS stage's body
    se_wire, si_wire = neighbor.SE, neighbor.SI
    # MANDATORY post-pick verification: wire MUST exist in this stage's netlist
    assert grep_exists(se_wire, netlist) and grep_exists(si_wire, netlist)
    dff_entry["port_connections_per_stage"][stage]["SE"] = se_wire
    dff_entry["port_connections_per_stage"][stage]["SI"] = si_wire
```

**FORBIDDEN:**
- Reading `PreEco/PrePlace.v.gz` for the Route lookup (or vice versa) — stages have CTS-renamed wires that exist in one stage and not the other
- Copying the result of one stage's lookup to another — wire names that exist in PP often disappear in Route after CTS optimization
- Skipping the post-pick verification — silently writing a non-existent wire produces an undriven pin and FM cone divergence

**Mutual exclusion with bridge_port:** If ANY stage uses `neighbor_dff`, you MUST NOT emit `sibling_pin_consolidation` or `si_consumer_replace` entries — those belong to the `bridge_port` strategy only. Mixing strategies and bridge artifacts produces inconsistent study output that the applier handles incorrectly.

#### When `mode_S_strategy_per_stage[<stage>]: "bridge_port"` (fallback)

Emit the entries listed in the bridge stitching umbrella table below. Critical invariants:
- DFF entry's `port_connections_per_stage[<stage>]` must reference the bridge ports (`ECO_<jira>_SI_in`, `ECO_<jira>_SE_in`) and set `mode_S_applied: true` for the stage
- Bridge wire MUST be driven at parent scope via an `assign eco<jira>_<si|se>_bridge = <parent_neighbor_net>` (without this the wire dangles — the 9868 R1 bug class)
- Walk up the hierarchy from host module to umccmd, emitting `port_connection` entries at each level so the bridge wire propagates correctly

#### Per-stage strategy is INDEPENDENT — no consistency requirement

Each stage's `port_connections_per_stage[<stage>]` is decided per `mode_S_strategy_per_stage[<stage>]`. PP using `neighbor_dff` and Route using `bridge_port` (or vice-versa) is correct and matches engineer's pattern. The Step 3 validator allows asymmetry — no longer enforces "all 3 stages identical".

#### Bridge wire MUST be driven (when bridge_port strategy is chosen)

A declared `eco<jira>_si_bridge` / `se_bridge` wire that no `assign` / `_SI_out` / `_SE_out` source drives is a **flow bug** that produces undriven SE/SI at the new DFF → FM globally unmatched. Step 3 Check 3c verifies the driver assign exists; Step 5 Check 17 verifies the bridge wire is reachable from a real neighbor scan net at parent scope.

#### Opt-out (no scan stitching needed at all)

Set `requires_scan_stitching: false` + `scan_stitching_skipped_reason: "<auditable reason>"` on the entry. Valid only when `dff_clock` is a `wrp_clk_*` wrapper clock that doesn't propagate scan_enable.

### 0c — Find suitable cell type from PreEco netlist

**For DFF with `has_sync_reset: true` — try reset-pin cell FIRST (preferred):**

**Generic discovery — no hardcoded cell names or pin names.** The library's reset-capable DFF is found by searching for existing DFFs in the module that ALREADY connect to `reset_signal`:

```python
def find_reset_capable_dff(module_scope_lines, reset_signal):
    """
    Find a DFF in module scope that uses reset_signal on one of its pins.
    Returns (cell_type, reset_pin_name) — both discovered from the netlist,
    no hardcoded cell prefixes or pin names.
    """
    import re
    for i, line in enumerate(module_scope_lines):
        # Check if this line references reset_signal as a port connection
        if re.search(rf'\.\w+\s*\(\s*{re.escape(reset_signal)}\s*\)', line):
            # Find the start of this cell instance block (scan back to cell declaration line)
            inst_start = i
            while inst_start > 0:
                prev = module_scope_lines[inst_start - 1]
                if re.search(r';\s*$', prev) or re.match(r'^\s*$', prev):
                    break
                inst_start -= 1
            inst_block = ' '.join(module_scope_lines[inst_start : i + 10])
            # Verify this is a DFF (has a Q output pin — generic DFF signature)
            if re.search(r'\.Q\s*\(', inst_block):
                # Extract cell_type: first uppercase token on instance declaration line
                cell_line = module_scope_lines[inst_start].strip()
                m = re.match(r'^([A-Z]\S+)', cell_line)
                if m:
                    cell_type = m.group(1)
                    # Extract which pin connects to reset_signal — this IS the reset pin
                    pin_m = re.search(
                        rf'\.(\w+)\s*\(\s*{re.escape(reset_signal)}\s*\)', inst_block
                    )
                    if pin_m:
                        return cell_type, pin_m.group(1)   # e.g. ("SDFQD4...", "RN")
    return None, None  # No reset-capable DFF found in this scope
```

Run against module scope from PreEco Synthesize:
```bash
awk '/^module <declaring_module>/,/^endmodule/' \
    /tmp/eco_study_<TAG>_Synthesize.v > /tmp/eco_module_scope.v
```
Then call `find_reset_capable_dff(module_scope_lines, reset_signal)`.

**If `(cell_type, reset_pin_name)` found:**
1. Use `cell_type` as the DFF cell — same library cell as existing DFFs that use the reset signal
2. Set `reset_pin_used: true`, `reset_pin_name: <discovered_pin>`, `reset_signal: <from rtl_diff>`
3. Connect `reset_signal` to `<discovered_pin>` in `port_connections`
4. **Remove reset term from `d_input_gate_chain`** — functional gates only; no reset INV gate
5. DFF `port_connections.D` = last functional gate output (not the reset AND gate)

```json
{
  "dff_cell_type": "<discovered from PreEco>",
  "reset_pin_used": true,
  "reset_pin_name": "<discovered from PreEco — not hardcoded>",
  "reset_signal": "<rst_signal from rtl_diff>",
  "port_connections": {
    "<data_pin>":  "n_eco_<jira>_d<last_functional_gate>",
    "<clk_pin>":   "<clk_net>",
    "<reset_pin>": "<rst_signal>",
    "<q_pin>":     "<target_register>"
  }
}
```

**If `None` returned (no existing DFF in scope uses reset_signal):**
Fall back — bake reset into D-input gate chain. Set `reset_pin_used: false`. Log: `"RESET_PIN_FALLBACK: no DFF found in scope <module> using <reset_signal> — baking reset into D-input (GAP-CTS-2 risk in Route)"`.

**MANDATORY chain creation OR extension when `reset_pin_used: false`:** rtl_diff_analyzer Step E removes the reset term from `d_input_gate_chain` so it can be baked in here. The studier MUST guarantee the DFF .D is driven by reset-gated logic. Two cases:

- **Step 1 chain is non-empty** → append the reset-gating tail (steps below).
- **Step 1 chain is empty** (`d_input_gate_chain: []` with `d_input_resolved_net` set, e.g. for direct-wire D-inputs like `REG_X[i]`) → CREATE the chain from scratch using `d_input_resolved_net` as the source. Do NOT wire DFF `.D` to a placeholder net like `n_eco_<jira>_<reg>` with no driver — that produces an undriven D pin and FM fails. **Use `d_input_resolved_net` (Synthesize) and the per-stage UNCONNECTED variants directly as the AND2 source input — do NOT invent a fresh `n_eco_*` placeholder for it.**

1. Let `<chain_tail>` = current final gate output (`d_input_net` from Step 1, e.g. `n_eco_<jira>_d<N>`).
2. Append two new gates with the next available `eco_<jira>_d<seq>` indices:
   - `INV` of `<reset_signal>` → output `n_eco_<jira>_d<N+1>` (or reuse `<reset_signal>` directly via a NOR-style combiner — choose whichever cell type the library prefers; discover from PreEco like the rest of the chain).
   - Final combiner that produces `chain_tail & ~<reset_signal>` (active_high reset) or `chain_tail & <reset_signal>` (active_low). Use AND2 + INV, or NR2 with the un-inverted reset, or any equivalent — the choice depends on what cell types exist in PreEco for this module.
3. Update `d_input_net` to the final combiner's output net and connect that to the DFF `.D` pin.
4. The same two-gate tail is reused across all 3 stages (per-stage net resolution still applies for the reset signal and intermediate nets via 0b-ALIAS / RULE 32).

**Self-check (MANDATORY):** if `has_sync_reset == true` AND `reset_pin_used == false` AND no chain entry references `<reset_signal>` → the bake-in was NOT performed → fix the chain before writing the study JSON. The DFF must NEVER be left without a reset path.

**Why this is strongly preferred:** Reset signals are heavily replicated by CTS in Route. When baked into the D-input cone, FM cannot trace through CTS-merged BBNet drivers → DFF non-equivalent in Route (GAP-CTS-2) → MANUAL_ONLY. Using the DFF reset pin bypasses the combinational cone entirely — immune to CTS restructuring.

**For DFF without sync reset (or fallback) — also generic:**
```python
def find_neighbour_dff(module_scope_lines):
    """Find any DFF cell in scope — identified by .Q( pin, not by cell name prefix."""
    for i, line in enumerate(module_scope_lines):
        if re.search(r'\.Q\s*\(', line):
            inst_start = i
            while inst_start > 0:
                prev = module_scope_lines[inst_start - 1]
                if re.search(r';\s*$', prev) or re.match(r'^\s*$', prev):
                    break
                inst_start -= 1
            cell_line = module_scope_lines[inst_start].strip()
            m = re.match(r'^([A-Z]\S+)', cell_line)
            if m:
                return m.group(1)   # cell_type, e.g. "SDFQD4AMDBWP..."
    return None
```

**For combinational gate:** Determine function from RTL expression (`A & B` → AND2, `~A` → INV, etc.), then search PreEco for matching cell pattern.

**MANDATORY — extract actual pin names from PreEco instance (ALL pins):**
```bash
grep -m1 "<cell_type>" /tmp/eco_study_<TAG>_<Stage>.v
```
Parse every `.<PIN>(` — these are the ONLY valid pin names. Never assume pin names from the gate function name.

### CELL OUTPUT PIN TABLE — MANDATORY REFERENCE

| Gate Function | Output Pin | Notes |
|--------------|-----------|-------|
| AND2, AND3, AND4 | `Z` | Non-inverting |
| OR2, OR3, OR4 | `Z` | Non-inverting |
| MUX2, MUX4 | `Z` | NOT `ZN` |
| XOR2 | `Z` | Non-inverting |
| INV | `ZN` | Inverting |
| NAND2, NAND3, NAND4 | `ZN` | Inverting |
| NOR2, NOR3, NOR4 | `ZN` | Inverting |
| XNOR2 | `ZN` | Inverting |
| IND2, IND3 | `ZN` | AND-NOT (inverting) |
| DFF, SDFF | `Q` | Sequential |

Verify output pin by examining an actual instance from PreEco — always authoritative over this table.

**GATE POLARITY VALIDATION (MANDATORY after 0c):** For every combinational gate, verify the chosen gate_function's polarity matches the RTL expression:
- Expression uses `~(A & B)` → NAND2 (inverting, ZN output) — NOT NOR2
- Expression uses `~(A | B)` → NOR2 (inverting, ZN output) — NOT NAND2
- Expression uses `A & B` → AND2 (non-inverting, Z output)
- Expression uses `~(A[1] == 1 & A[0] == 0)` = `~(A[1] & ~A[0])` → NAND2 of (A[1], ~A[0])

Verify: `polarity_matches = (chosen_gate_function.output_is_inverting == rtl_expression_is_inverted)`. If mismatch → log `POLARITY_MISMATCH: chosen {gate_function} but RTL requires {correct_function}` and correct gate_function before writing study JSON.

### 0c-SCOPE — Use preferred_insertion_scope when set (MANDATORY check)

Before assigning `instance_scope` for any gate chain entry, check `preferred_insertion_scope` from the RTL diff change JSON:

```python
preferred_scope = change.get("preferred_insertion_scope")
if preferred_scope:
    # Gate chain goes INSIDE the child submodule, not at declaring module level
    # instance_scope = preferred_scope (child instance path)
    # The last gate's output net becomes a new OUTPUT PORT of the child module:
    #   → add port_declaration entry for n_eco_<jira>_d<last> from child module
    #   → add port_connection entry: child_instance.n_eco_<jira>_d<last> at parent level
    # The DFF stays at parent (declaring module) level, D-input = the new port
    instance_scope = preferred_scope
    log(f"PREFERRED_SCOPE: inserting gate chain inside {preferred_scope} "
        f"(submodule input — avoids FM black-box DFF0X in P&R stages)")
else:
    # Default: insert at declaring module level
    instance_scope = change.get("instance_scope", "")
```

**Why:** When `input_from_submodule: true`, the gate chain inputs are only accessible inside the child submodule. FM black-boxes the child in P&R → inputs appear undriven (DFF0X) if gates are at parent. Moving gates inside the child bypasses black-boxing.

### 0d — Assign instance and output net names

**For `new_logic_dff`:**
```
instance_name = <target_register>_reg
output_net    = <target_register>
```

**For `new_logic_gate` (including D-input chain gates):**
```
instance_name = eco_<jira>_<seq>   (e.g., eco_<jira>_d001)
output_net    = n_eco_<jira>_<seq>
```
Same seq across all 3 stages. Seq counter is global across all chains.

### 0e — Record skeleton entry

**`instance_scope` rules — MANDATORY:**
- Submodule: `instance_scope = "<INST_A>/<INST_B>"`
- Tile root: `instance_scope = ""` (empty string) AND `"scope_is_tile_root": true`
- NEVER leave `instance_scope` as null — use `""` explicitly for tile-root scope

**`instance_scope` for tile-root detection:**
```bash
# Match tile-root module — no hardcoded prefix; pattern: any module containing the tile name as a word
grep -m1 "^module [a-z0-9_]*<tile>[a-z0-9_]* " /tmp/eco_study_<TAG>_Synthesize.v
```
The tile-root module name is also available directly from `TILE_ROOT_MODULE` (provided in agent prompt or from `resolve_module_name()` fallback).

Record skeleton entry with: `change_type`, `instance_scope`, `scope_is_tile_root`, `cell_type`, `instance_name`, `output_net`, `port_connections` (Synthesize only), `confirmed: true/false`.

**MANDATORY context fields for every entry — used by eco_rpt_generator.py to produce a self-explanatory Step 3 RPT:**
- `reason` — one short line: WHY this change is needed (the role in the ECO). Example formats per change_type:
  - `new_logic_gate`: `"<role>: <boolean expression or gate-tree position>"` (e.g. `"SELFREF_match: BeqCtrlPeSrc==3'b000 (NOR3 of 3 bits)"`)
  - `new_logic_dff`: `"<RTL register> with <reset/clock-domain summary>"`
  - `rewire`: `"<old_net> → <new_net> on <pin>: <upstream-driver context>"`
  - `port_declaration`: `"<signal> as <direction> of <module> for <ECO purpose>"`
  - `port_connection`: `"<port>(<net>) wires <upstream> to <downstream> for <ECO purpose>"`
- `notes` — multi-line free text (2–8 lines). Include:
  - **Chain trace** (the upstream/downstream cells this entry sits in): `<driver>/<pin> → <wire> → <next_cell>/<pin> → ... → <DFF>.D`
  - **RULE references** that justified the choice (e.g., `RULE 32: <real RTL net> over <P&R alias>`, `Mode I exception: child output port wire-up`)
  - **Evidence** observed during the lookup (e.g., `Found in PreEco Synthesize line N`, `cell_function_matches() returned True for AOI21D1 vs gate_function AOI21`)
- `source` — short stable label of how the entry was determined: `"initial_run_<TAG>"` for first study, `"retry<N>_<TAG>"` for re-studier passes, `"FALLBACK_from_<stage>"` when copying from another stage's resolution.

These fields are NOT cosmetic — they are the audit trail for the engineer reviewing the Step 3 RPT and for the round-N re-studier when a Mode A/H/I/T fix is needed. Every confirmed entry must have all three. Empty `reason`/`notes`/`source` is a Step 3 validate failure.

eco_netlist_verifier will add `port_connections_per_stage`, GAP-15 correction, port boundary entries, and consumer cascade entries.

### 0f — Mark wire_swap entries that depend on new_logic outputs

For each `wire_swap` whose `new_token` matches a `new_logic` output net, add `"new_logic_dependency": [<seq>]`.

**MUX select polarity (when `mux_select_gate_function` is non-null in RTL diff):**
Read `mux_select_gate_function` directly → create `new_logic_gate` entry. If null → set `mux_select_gate_function: null` and record `mux_select_i0_net`, `mux_select_i1_net` for eco_netlist_verifier's Check 4c.

**WIRE_SWAP GATE DIRECTION RULE (MANDATORY):** Read `mux_select_gate_function` from the RTL diff change JSON and use EXACTLY that function — no analysis, no substitution, no De Morgan alternatives:
- `mux_select_gate_function: AND2` → gate must be AND2 (output pin `Z`) — NEVER NAND2 or OR2
- `mux_select_gate_function: NAND2` → gate must be NAND2 (output pin `ZN`) — NEVER AND2 or INV+INV+OR2
- The RTL diff analyzer already determined the correct function from MUX polarity analysis. Trust it. Using any De Morgan equivalent creates different LatCG cone structures that cause FM equivalence failures.

**WIRE_SWAP OUTPUT NET RULE — GAP-22 (MANDATORY):** Before using any existing net as the gate output, check its fanout in the declaring module scope:
```bash
fanout=$(awk '/^module <module>/,/^endmodule/' PreEco/Synthesize.v.gz | grep -c "\b<net_name>\b")
```
If `fanout > 10` → **NEVER use this net as gate output**. High-fanout nets have many consumers — driving them with a new gate creates structural FM mismatches across hundreds of DFFs. Use a NEW intermediate wire as the gate output instead, then rewire the old driver to the new wire. Log: `FANOUT_BLOCK: <net> has <N> consumers — using new output net n_eco_<jira>_<seq> instead`.

### 0g — Process `new_port` changes → `port_declaration` study entries

1. Identify `module_name`, `signal_name` (`new_token`), `declaration_type`, `instance_scope`
2. Detect netlist type: `grep -c "^module " /tmp/eco_study_<TAG>_Synthesize.v` — count > 1 = hierarchical
3. **Implicit wire check:** if `context_line` has only `wire` AND ≥ 2 `port_connection` changes reference it → skip port_declaration, set `no_wire_decl_needed: true` on those port_connection entries, note in entry.
4. If hierarchical: validate module name — `grep -c "^module <module_name>\b"`. If 0 → try `<module_name>_0`. Not found → `confirmed: false`.

### 0h — Process `port_connection` changes → `port_connection` study entries

1. Identify `parent_module`, `instance_name`, `port_name`, `net_name`, `submodule_type`
2. **MANDATORY — Validate `submodule_pattern`:** `grep -c "<submodule_type> <instance_name>" /tmp/eco_study_<TAG>_Synthesize.v`. If 0 → check PrePlace and Route; record per-stage `instance_confirmed` flags.

### 0i — Process `port_promotion` changes → `port_promotion` study entries

1. Check Synthesize: `grep -cw "<signal_name>" /tmp/eco_study_<TAG>_Synthesize.v`
   - If ≥ 1 → `flat_net_confirmed: true`, record with `declaration_type: "output"`.
2. If 0 (net absent in gate-level — synthesis merged it into cone): find the D-input net of `<signal_name>_reg` or `<signal_name>_d1_reg` in Synthesize module scope → that is the combinational driver net. Record `driver_net: <found_net>`, `needs_buffer_chain: true`, `flat_net_confirmed: false`.
   - eco_netlist_verifier Check 7 will auto-add a `new_logic_gate` INV+INV buffer chain entry: `INV(<driver_net>) → <tmp_net>`, `INV(<tmp_net>) → <signal_name>`, using cell types discovered from PreEco neighbours. This drives the new output port from the internal combinational value without modifying the DFF.
3. If `<signal_name>_reg` also absent → `flat_net_confirmed: false`, `reason: "net and reg both absent — port_promotion cannot be auto-applied"`. Log for engineer review.

---

## Phase 1 — Process Per Stage (wire_swap FM Results)

For each `wire_swap` change, process FM fenets results per stage.

**Multi-instance handling:** When `instances` is non-null, process each instance's FM results independently.

### 1. Read the PreEco netlist (once per stage, reuse across all cells)
```bash
zcat <REF_DIR>/data/PreEco/<Stage>.v.gz > /tmp/eco_study_<TAG>_<Stage>.v
```

### 2–3. Find and extract cell instantiation block

Read from the line with the cell name through the closing `);`. Extract all `.portname(netname)` entries.

### 4. Confirm old_net is present

**Step 1 — Try direct old_net name:** `grep -c "\.<pin>(<old_token>)" /tmp/eco_study_<TAG>_<Stage>.v`
- If ≥ 1 → `"old_net": "<old_token>"`, `"confirmed": true`

**Step 2 — If not found, check for HFS alias on that pin.** Read actual net on `<pin>`, verify alias via parent module port connection. If confirmed: set `"old_net_alias": true`, `"old_net_alias_reason"`.

If neither found: `"confirmed": false`. eco_netlist_verifier will run stage fallback (GAP-5).

### 4b. Basic new_net reachability

**Priority 1 — Direct name:** `grep -cw "<new_token>" /tmp/eco_study_<TAG>_<Stage>.v`. If ≥ 1 → `"new_net": "<new_token>"`.

**Priority 2 — HFS alias (only if direct absent):** Set `"new_net_alias": "<alias>"`, `"new_net_reachable": true`. If not found: `"new_net_reachable": false`.

Backward cone and forward trace verification are handled by eco_netlist_verifier Check 10.

### 4d. Timing estimate (Synthesize only)

Compare driver structure of `old_net` vs `new_net` in PreEco Synthesize. Record:
```json
"timing_lol_analysis": {
  "old_net_driver": "<cell> (<type>)",
  "new_net_driver": "<cell> (<type>)",
  "old_net_fanout": N, "new_net_fanout": N,
  "timing_estimate": "BETTER|LIKELY_BETTER|NEUTRAL|RISK|LOAD_RISK|UNCERTAIN"
}
```

### 5. Verify output count before moving to next stage
```
Qualifying list had: N cells
Output JSON has:     N entries  ← must match
```

### 6. Cleanup temp files (after all stages complete)
```bash
rm -f /tmp/eco_study_<TAG>_Synthesize.v /tmp/eco_study_<TAG>_PrePlace.v /tmp/eco_study_<TAG>_Route.v
```

---

## Output JSON

Write `<BASE_DIR>/data/<TAG>_eco_preeco_study.json`.

**`change_type` translation:** `wire_swap` → `rewire`; `new_logic` → `new_logic_dff` or `new_logic_gate`.

**Sort each stage array by PASS_ORDER before writing:**
```python
PASS_ORDER = {
    "new_logic": 1, "new_logic_dff": 1, "new_logic_gate": 1,
    "port_declaration": 2, "port_promotion": 2,
    "port_connection": 3,
    "rewire": 4,
}
for stage in ["Synthesize", "PrePlace", "Route"]:
    study[stage].sort(key=lambda e: PASS_ORDER.get(e.get("change_type", "rewire"), 4))
```

Verify output is non-empty with at least one confirmed entry.

**Write collect RPT** to `<BASE_DIR>/data/<TAG>_eco_step3_collect.rpt`:
```
ECO NETLIST STUDIER — COLLECT PASS
TAG=<TAG>  |  JIRA=<JIRA>  |  TILE=<TILE>
================================================================================
PHASE 0 — new_logic / port entries:
  new_logic_gate:   <N>  (confirmed: <N>  excluded: <N>)
  new_logic_dff:    <N>  (confirmed: <N>  excluded: <N>)
  port_declaration: <N>  (confirmed: <N>  excluded: <N>)
  port_connection:  <N>  (confirmed: <N>  excluded: <N>)
  d_input_chains:   <N> chains  <N> gates total  (<N> decompose_failed)

SYNC RESET HANDLING (per DFF with has_sync_reset=true):
  <target_register>:
    reset_signal:    <rst_signal>
    reset_polarity:  active_high | active_low
    reset_pin_used:  YES | NO (FALLBACK)
    [if YES]
      cell_type:     <discovered_cell_type>  (from find_reset_capable_dff)
      reset_pin:     <discovered_pin_name>   (from find_reset_capable_dff)
      d_input_gates: <N> gates (reset gate removed — functional gates only)
      GAP-CTS-2:     AVOIDED — reset signal not in combinational cone
    [if NO — FALLBACK]
      reason:        no DFF found in scope <module> using <rst_signal>
      d_input_gates: <N> gates (includes reset INV gate)
      GAP-CTS-2:     RISK — reset in D-input cone, may fail in Route FM
  <repeat per DFF>

PHASE 1 — wire_swap rewire entries:
  [Synthesize]  <N> qualifying cells  confirmed: <N>  excluded: <N>
  [PrePlace]    <N> qualifying cells  confirmed: <N>  excluded: <N>
  [Route]       <N> qualifying cells  confirmed: <N>  excluded: <N>

EXCLUDED entries (need verifier or manual fix):
  <cell/signal>: <reason>
  ...

NOTE: port_connections_per_stage not yet resolved — eco_netlist_verifier handles this.
================================================================================
```
Copy RPT to `AI_ECO_FLOW_DIR/`.

**After writing, exit immediately.** eco_netlist_verifier is spawned by ORCHESTRATOR next.

---

## Confirmed-false Notes

- Cell not found in PreEco: `"confirmed": false, "reason": "cell not found in PreEco netlist"`
- Old net not on expected pin: `"confirmed": false, "reason": "pin <pin> has net <actual_net> not expected <old_net>"`
- Multiple instances: `"confirmed": false, "reason": "AMBIGUOUS — multiple occurrences"`
- Name mangling: retry with `"<cell_name>_reg"` before marking confirmed: false
- All stages have no FM results: mark all confirmed: false for manual review
