# ECO Netlist Studier — Collect Pass

**MANDATORY FIRST ACTION:** Read `config/eco_agents/CRITICAL_RULES.md` in full before doing anything else.

**MANDATORY SECOND ACTION:** Read **only** your scope-contract section in the parent orchestrator: `config/eco_agents/STUDY_ORCHESTRATOR.md` **§STEP 3 — Study PreEco Gate-Level Netlist** (initial Round 1 only). For per-round re-study fixes (Round 2+), use `eco_netlist_re_studier.md` instead. Do NOT read other STEP sections; they belong to other agents.

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
3. **Internal-wire fallback (when both above fail) — grep the host module body for the driver:** when a chain leaf references a signal that's a local internal wire (driven by a sync-flop INSIDE the host module), P&R may rename the driver's `.Q` net per stage. When the rename map missed it, grep the host module body in EACH stage's PostEco netlist for the original sync-flop's `.Q(<net>)` and use that per-stage value. Studier code:

```python
def find_driver_in_module(host_mod_text, original_signal, source_dff_inst):
    # Look for `.Q(<wire>)` on the source DFF instance — that's the per-stage net
    m = re.search(rf'\b{re.escape(source_dff_inst)}\b\s*\([^)]*?\.Q\s*\(\s*(\w+)\s*\)', host_mod_text, re.DOTALL)
    return m.group(1) if m else original_signal
```

NEVER force the Synthesize name across all stages — all three resolution paths produce per-stage values that match what FM expects. For SE/SI on new ECO DFFs: Synth = `1'b0` (RTL-clean), PP/Route = neighbor DFF's per-stage SE/SI (real scan-bridge wire — NOT `1'b0`).

**Note on Path 1 vs Path 3 equivalence:** the rename_map value is FM-anchored to a *combinational* path through CTS inverters. Path 3 (module-body grep) may legitimately resolve to a different topologically-equivalent net (e.g., a `.Qn` output of a multi-bit register replica that holds a registered version of the same logical signal). Both can be FM-equivalent for combinational compare-point checks; choose based on the consuming gate's needs. Do not treat any single path as universally correct — FM equivalence is the arbiter, not a static rule.

Log: `PR_ALIAS: <gate>.<pin> Syn=<net> PP=<alias> Route=<alias>` or `PR_ALIAS_SAME` if identical.

**Mode H Route fallback — condition gate chain inputs unavailable in Route:**

When Path 1 rename_map shows a Route value that is a Synth-only synthesis name (i.e., `zgrep -c "<route_value>" PreEco/Route.v.gz` returns 0), the signal genuinely doesn't exist in Route. Do NOT use the Synth fallback name — it will cause FM FAIL. Instead:

1. **Check ECO ports from the same run** — search `changes[]` for `new_port` or `port_promotion` entries whose signal is logically related to the unresolvable input (same module scope, same functional domain).
2. **If a substitute ECO port exists in Route** (grep confirms it exists in `PreEco/Route.v.gz`) — use it as the Route value for that gate input. Record `route_substituted_with_eco_port: true` and `original_signal: <unresolvable>` in the gate entry so the validator and Round 2 re_studier know this was a substitution.
3. **If no ECO port substitute found** — set `confirmed: false` for Route stage entries only. Applier skips Route gate chain. FM will FAIL on Route; ROUND_ORCHESTRATOR Round 2 handles with manual review.

**Do not apply this fallback to Synth or PP** — only Route is affected. PP is already resolved via the fix1 fenets retry (FxPrePlace_ZBUF_* values).

---

### 0b-UNCONNECTED — Auto-rename UNCONNECTED_* nets (MANDATORY)

FM cannot trace `UNCONNECTED_*` / `SYNOPSYS_UNCONNECTED_*` across hierarchy → globally unmatched → DFF non-equivalent. Any gate input matching `^(SYNOPSYS_)?UNCONNECTED_\d+$` must be renamed.

**MANDATORY format constraints for `named_net`:**

- MUST be a flat Verilog identifier: `^[A-Za-z_]\w*$` (letters, digits, underscores only — NO brackets, spaces, or special chars)
- MUST NOT contain `[`, `]`, `.`, `/`, or whitespace
- For bus-bit semantics (e.g. "bit N of bus X"), use **flat-net underscore-escape form**: `X_N_` — NEVER `X[N]`. Bracket form is only valid in port_connections / concatenations, NOT in wire declarations.
- The applier (`eco_perl_spec.py`) auto-sanitizes bracket form via `_sanitize_named_net()` as a safety net (logs `AUTO_SANITIZED` in apply report) but the studier should emit the correct form directly. Repeated AUTO_SANITIZED entries indicate this rule is being violated.

**Scope discipline (do NOT broadcast):**

Each `unconnected_rewires` entry targets exactly ONE `(module, instance, port_name, bus_bit)` tuple. The applier executes per-instance — but if the studier emits N entries for N different modules all sharing the same `original` UNCONNECTED name AND the same `named_net`, the result LOOKS like a broadcast even though each individual edit is scoped. This is a scope-leak symptom — STUDIER should emit only the entries actually needed for the ECO.

**Rule:** For each such net:
1. Generate: `named_net = "n_eco_<jira>_<rtl_hint>"` — sanitized from `new_token`, port name, or RTL context. **Same name used across all stages.** **Flat-net form only — see format constraints above.**
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
- `net_name`: `<port_name>[<bit>]` (self-loop to the OWN output port — Verilog auto-wires bus access in port_connections is legal). **CAUTION:** this bracket form is valid in a `.port_name(<port_name>[<bit>])` port_connection BUT illegal in a wire declaration. If this same value is also routed through `unconnected_rewires.named_net`, it will trigger the applier's AUTO_SANITIZE (rewriting to flat-net form) — that's the safety net, but the cleaner pattern is: keep bracket form ONLY in this port_connection's `net_name` field, and use the corresponding flat-net form (`<port_name>_<bit>_`) in `unconnected_rewires.named_net`.
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
  "skip_cell_instantiate": true,
  "inputs_per_stage": {
    "Synthesize": "<wire_synth_or_inv_self>",
    "PrePlace":   "<wire_pp>",
    "Route":      "<wire_route>"
  }
}
```
**Both `reuse_existing_wire: true` AND `skip_cell_instantiate: true` are MANDATORY** when reusing. The applier honors `skip_cell_instantiate=true` by NOT emitting the cell instance — instead it treats the chain entry's output_net (`n_eco_<jira>_d<seq>`) as a per-stage alias for `inputs_per_stage[stage]`. Downstream gates that consumed `n_eco_<jira>_d<seq>` get rewired to consume the per-stage wire directly.

**Why both fields:** `reuse_existing_wire: true` alone is ambiguous — applier could either (a) skip the cell entirely and alias, or (b) instantiate the cell with `inputs_per_stage[stage]` as its input pin. (b) is wrong for INV reuse: it would compute `~~X = X` in stages where the reused wire is already inverted (e.g., a `*_rstb` flat-net that is `~IReset`). `skip_cell_instantiate: true` eliminates the ambiguity — the applier never emits the cell.

This avoids widening the FM cone with a new INV AND preserves the polarity of the reused signal.

**GAP-14 — Wire declaration flag:** For each new gate whose output net does not exist in PreEco (`grep -cw "<output_net>" /tmp/eco_study_<TAG>_Synthesize.v` = 0), set `needs_explicit_wire_decl: true`. **Output net ONLY — never set for input nets.**

### 0b-CLOCK — Per-stage CP wire selection (MANDATORY root-token verification)

For every new DFF, when picking `port_connections_per_stage[<stage>].CP`, verify all 3 stages' wires trace to the **same root clock token** (e.g. `UCLK*`, `wrp_clk_*`, project-specific clock prefix). Procedure:

1. Extract the clock token from each stage's chosen CP wire name. CTS-introduced wires (`ant_fix_net_*`, `FxCts_*`, `*_clkbuf_*`, `FxOptCts_*`) embed the root token within their name — extract it.
2. If the Synth/PP/Route tokens disagree → re-pick. The new DFF must clock on the same logical clock across all 3 PostEco stages; mismatch = different clock domain in one stage = FM logical mismatch on the DFF.
3. When a Route candidate is a CTS-introduced wire, trace through the antenna/CTS chain to confirm root match with PP. If trace is ambiguous, pick a different neighbor whose CP is a flat clock root or has a single deterministic CTS hop.

Step 3 validator Check 27 (`HIGH/27-CLOCK-STAGE-MISMATCH`) HARD FAILs any new DFF whose per-stage CP wires do not share a common root clock token. The orchestrator's Step 3 gate blocks Phase A handoff on any HIGH issue.

### 0b-MODE-S — Scan stitching for new ECO DFFs in P&R

A new DFF in a scan-reachable clock domain (anything reachable from `tile_dfx/scan_cntl`) MUST integrate with the existing scan network. Tying SE/SI to `1'b0` in P&R isolates the DFF → FM "globally unmatched SE pin" → stage fails.

**Per-stage strategy table:**

| Stage | Strategy | Notes |
|---|---|---|
| Synthesize | `constant_zero` | Always — RTL has no scan pins |
| PrePlace | `bridge_port` (default) | `neighbor_dff` ONLY when Route also = `neighbor_dff` |
| Route | `bridge_port` (MANDATORY) | CTS rebalances scan wires → `neighbor_dff` non-deterministic |

Validator HARD FAILs (gate Step 4): **Check 28** (Route≠bridge_port), **Check 29** (PP=neighbor_dff while Route=bridge_port), **Check 30** (constant_zero with neighboring DFFs in same clock domain), **Check 32** (strategy↔connection inconsistency — see below).

**STRATEGY ↔ CONNECTION INVARIANT (Check 32 HARD FAIL).** Strategy field and `port_connections_per_stage[<stage>].SE/SI` MUST agree per stage:
- `constant_zero` ⇔ `SE=SI='1'b0'`
- `neighbor_dff` ⇔ `SE/SI` are real neighbor wires
- `bridge_port` ⇔ `SE/SI` are `ECO_<jira>_*_in` bridge ports

Plugging real wires while declaring `constant_zero` is FORBIDDEN — the metadata lies about what the netlist will actually do.

**SIBLING ESCALATION (MANDATORY before falling to constant_zero).** When `eco_pick_sibling.py` returns null at parent-of-host scope:
1. If host is tile-top (no parent above), re-invoke with `--host-scope=down` to search host's CHILDREN for a viable bridge target.
2. If still null, re-invoke with `--min-cluster=5` (relaxed from default 10).
3. Only if BOTH escalations return null may you fall back to `constant_zero`.

Record the escalation chain in `scan_stitching_skipped_reason`.

**`host_module_dff_count_same_clock` MUST be computed by grep, not asserted.** Validator Check 30 re-verifies — lying triggers HARD FAIL.
```bash
awk '/^module <host>\b/,/^endmodule/' /tmp/eco_study_<TAG>_Synthesize.v | grep -cE '\.CP\(\s*<dff_clock>\b'
```

**Required field on every new_logic_dff entry:**
```json
"mode_S_strategy_per_stage": {"Synthesize": "constant_zero", "PrePlace": "bridge_port", "Route": "bridge_port"}
```
Bridge plumbing entries (port_declaration, port_connection, etc.) MUST carry `"bridge_port_role": "<sibling_si|sibling_se|sibling_q|host_si|host_se|host_q>"` so the applier skips them in Synth.

**Bridge source wire stage-stability (MANDATORY).** Before picking SI/SE bridge source wires, verify each wire's parent-level driver is the same logical net in PP and Route via `data/<TAG>_eco_fenets_rename_map.json` lookup keyed `<sibling_scope>/<anchor_dff>/<SE|SI>`. Compare PP and Route values:
- Match → record `bridge_source_pp_route_match: {si: true, se: true}` on the new_logic_dff entry
- Mismatch → CTS-renamed; reject this anchor and pick another

**HARD RULE — no rename_map fallback.** If the candidate anchor has NO entry in the rename map, set `mode_S_strategy_per_stage[<stage>]: "BLOCKED_NO_RENAME_MAP"` and let Check 23 fail the round. DO NOT scan PP/Route netlists directly to "guess" — that bypasses FM and produces silently wrong stage hookups.

**Deterministic picker + emitter (BOTH MANDATORY when `bridge_port` chosen).** Manual derivation of bridge artifacts is FORBIDDEN — Check 24 (BRIDGE-ARTIFACT-SET-COMPLETE) fails on missing items. Invoke both helpers and SPLICE their JSON output verbatim into `eco_preeco_study.json`:
```bash
python3 script/eco_scripts/eco_pick_bridge_dffs.py \
    --netlist <REF_DIR>/data/PreEco/PrePlace.v.gz \
    --sibling-mod <sibling_module> --output data/<TAG>_eco_bridge_pick_<dff>.json

python3 script/eco_scripts/eco_emit_bridge_plumbing.py \
    --bridge-pick data/<TAG>_eco_bridge_pick_<dff>.json \
    --jira <jira> --host-module <host> --sibling-module <sib> \
    --parent-module <parent> --host-inst <inst> --sibling-inst <inst> \
    --new-dff-instance <DFF> --output data/<TAG>_eco_bridge_plumbing_<dff>.json
```

**MANDATORY minimum cluster size: `consolidation_target_dffs` ≥ 10 DFFs** (use SIBLING ESCALATION above when picker can't reach 10). Smaller clusters mean the bridge isn't a meaningful scan path participant → FM cone matching unstable.

**Bridge artifact umbrella** (per new ECO DFF — all carry `bridge_port_role`, Synth-skipped):

| Entry | change_type | role tag |
|---|---|---|
| Sibling-module SI/SE/Q ports | `port_declaration` | `sibling_<si\|se\|q>` |
| Host-module SI/SE/Q ports | `port_declaration` | `host_<si\|se\|q>` |
| Parent-level bridge wires | `assign` | (no tag — driven only in PP/Route) |
| Sibling/Host instance hookups | `port_connection` | `sibling_*` / `host_*` |
| Sibling SE-pin consolidation (≥10 DFFs) | `sibling_pin_consolidation` | (auto-skipped) |
| Bridge Q closure (one DFF SI rewrite) | `si_consumer_replace` | (auto-skipped) |

Sibling SE-pin consolidation: pick N existing DFFs in `sibling_module` sharing the most-common `.SE` net; applier rewrites their `.SE` to `ECO_<jira>_SE_out`. Q-closure: pick a DFF already in the SE-consolidation list (its original `.SI` is now redundant); applier rewrites its `.SI` to `ECO_<jira>_Q_in`. **Verify `consumer_dff_inst` exists inside `sibling_module` body via module-scoped grep** — picking a consumer outside the named sibling produces silent applier no-op + FM failure.

**Bridge wire MUST be driven** at parent scope (`assign eco<jira>_<si|se>_bridge = <parent_neighbor_net>`); undriven wire dangles → FM globally unmatched. Step 3 Check 3c + Step 5 Check 17 enforce.

#### When `mode_S_strategy_per_stage[<stage>]: "neighbor_dff"`

Per-stage independent lookup — read THIS stage's PreEco netlist, pick a neighbor DFF in the host module, post-verify the wire exists in the same stage:
```python
for stage in ('Synthesize', 'PrePlace', 'Route'):
    netlist = f'<REF_DIR>/data/PreEco/{stage}.v.gz'
    neighbor = pick_neighbor_dff(host_module, netlist)
    assert grep_exists(neighbor.SE, netlist) and grep_exists(neighbor.SI, netlist)
    pcs[stage]["SE"], pcs[stage]["SI"] = neighbor.SE, neighbor.SI
```

**FORBIDDEN:** reading PP netlist for Route lookup (or vice versa); copying one stage's result to another; skipping post-verification. **Mutually exclusive with bridge_port:** if ANY stage uses `neighbor_dff`, do NOT emit `sibling_pin_consolidation` or `si_consumer_replace` entries.

#### Opt-out (no scan stitching at all)

Set `requires_scan_stitching: false` + `scan_stitching_skipped_reason: "<auditable reason>"`. Valid ONLY when `dff_clock` is a `wrp_clk_*` wrapper clock that doesn't propagate scan_enable.

### 0c-SYNTH — Derive d_input_gate_chain via eco_synth_chain.py (MANDATORY)

For any new DFF with combinational D-input, do NOT hand-decompose the RTL Boolean. Invoke the synthesizer and splice its output verbatim:

```bash
python3 script/eco_scripts/eco_synth_chain.py synthesize \
    --boolean "<RTL_BOOLEAN>" --inputs "<comma-separated names>" --jira <JIRA>
```

If the synthesizer raises an error, the Boolean doesn't match any known pattern — extend `eco_synth_chain.py` with a new pattern (engineer-evidence required). Falling back to literal decomposition is FORBIDDEN.

Validator Check 31 (`SYNTH-STYLE-TOPOLOGY`) hard-fails any chain whose cell-type multiset differs from the synthesizer's output, even when the Boolean is equivalent.

---

### 0c — Find suitable cell type from PreEco netlist

**Generic discovery — no hardcoded cell names or pin names.** Read module scope from PreEco Synthesize:
```bash
awk '/^module <declaring_module>/,/^endmodule/' /tmp/eco_study_<TAG>_Synthesize.v > /tmp/eco_module_scope.v
```

#### DFF with `has_sync_reset: true` — try reset-pin cell FIRST (preferred)

**Algorithm — `find_reset_capable_dff(scope_lines, reset_signal)`:**
1. Scan `scope_lines` for any line `\.<pin>\(\s*<reset_signal>\s*\)` — this is a cell pin connected to the reset.
2. Walk back to the start of the cell instance block (until previous line ends with `;` or is blank).
3. If the block contains `\.Q\(` → it's a DFF.
4. Extract `cell_type` = first uppercase token on the instance declaration line; `reset_pin_name` = the pin in step 1.
5. Return `(cell_type, reset_pin_name)`, e.g. `("SDFQD4...", "RN")`. None on no match.

**If found:** use `cell_type` as the DFF, set `reset_pin_used: true`, `reset_pin_name: <discovered>`, connect `reset_signal` to that pin, **remove the reset term from `d_input_gate_chain`** (DFF `.D` = last functional gate output, no reset gate).

```json
{"dff_cell_type": "<discovered>", "reset_pin_used": true,
 "reset_pin_name": "<discovered>", "reset_signal": "<rst>",
 "port_connections": {"<data>": "n_eco_<jira>_d<last>", "<clk>": "<clk_net>",
                      "<reset>": "<rst>", "<q>": "<target_register>"}}
```

**If None — bake reset into D-input chain.** Set `reset_pin_used: false`; log `RESET_PIN_FALLBACK: no DFF in scope <mod> using <reset> — baking into D-input (GAP-CTS-2 risk in Route)`.

**MANDATORY chain extension when `reset_pin_used: false`:** rtl_diff_analyzer Step E strips the reset term so it can be baked in here. Two cases:
- **Chain non-empty** → append reset-gating tail to existing chain.
- **Chain empty** (`d_input_resolved_net` set, e.g. direct-wire `REG_X[i]`) → CREATE chain from scratch using `d_input_resolved_net` (and per-stage UNCONNECTED variants) as the AND2 source. NEVER invent an undriven `n_eco_*` placeholder.

Tail gates: `INV(<reset>)` → output `n_eco_<jira>_d<N+1>`; final combiner producing `chain_tail & ~<reset>` (active_high) or `chain_tail & <reset>` (active_low) using AND2+INV / NR2 / equivalent (cell type from PreEco, not hardcoded). Update `d_input_net` to the combiner's output, wire to DFF `.D`. Same tail across all 3 stages; per-stage resolution via 0b-ALIAS / RULE 32.

**Self-check:** `has_sync_reset && !reset_pin_used && no chain references <reset>` → bake-in was skipped → fix before writing JSON. DFF must NEVER be left without a reset path.

**Why reset-pin is preferred:** CTS heavily replicates reset signals in Route; baked into the D-cone, FM cannot trace through CTS-merged BBNet drivers → DFF non-equivalent (GAP-CTS-2). Using the DFF reset pin bypasses the combinational cone entirely.

#### DFF without sync reset (or fallback) — find any DFF in scope

`find_neighbour_dff(scope_lines)`: scan for a line containing `\.Q\(`, walk back to instance start (prev line ends with `;` or blank), return first uppercase token from the declaration line as `cell_type` (e.g. `SDFQD4AMDBWP...`).

#### Combinational gate

Determine function from RTL expression (`A & B` → AND2, `~A` → INV, …), then search PreEco for matching cell pattern.

**MANDATORY — extract actual pin names from PreEco instance (ALL pins):** `grep -m1 "<cell_type>" /tmp/eco_study_<TAG>_<Stage>.v`. Parse every `.<PIN>(` — these are the ONLY valid pin names. Never assume pin names from the gate function name.

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

**CHAIN-LEVEL POLARITY (MANDATORY when chain has ≥2 cells):** Picking each cell with the right local polarity is necessary but NOT sufficient — the COMPOSED Boolean across the whole chain must equal `d_input_expected_function` from the RTL diff. Two failure modes the per-cell rule cannot catch:

1. A downstream inverting cell (NR/NAND) flips the polarity of an upstream input — choosing the un-inverted form for that input makes the cumulative function carry the wrong polarity, even when each individual cell is correct.
2. The RTL Boolean has an input in inverted form (`~SIG`); picking `SIG` directly into a non-inverting cell silently drops the inversion.

**Rule:** Do NOT hand-decompose multi-cell chains. Invoke `eco_synth_chain.py` (per §0c-SYNTH) — it derives cell types AND input polarities from `d_input_expected_function` so the composed function is correct by construction. Step 3 validator Check 31 hard-fails any topology mismatch between the emitted chain and what `eco_synth_chain` produces from the same Boolean.

When an input must enter a non-inverting cell as `~SIG`, search the host module for an existing INV whose output is `~SIG` and use its output net as the input wire — do NOT instantiate a redundant INV.

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

**Per-instance expansion:** When the rtl_diff entry has `flat_net_name_per_instance`, emit one separate `port_connection` study entry per instance, each with its own `instance_name` and `net_name` from the dict. When absent, emit a single entry using `flat_net_name` as normal. This is backward-compatible — single-instance ECOs produce one entry, multi-instance cross-channel ECOs produce one entry per instance with the correct hookup net.

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
