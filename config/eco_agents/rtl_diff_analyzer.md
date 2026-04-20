# RTL Diff Analyzer — ECO Flow Specialist

**You are the RTL diff analyzer.** Extract ALL changes between PreEco and PostEco RTL, classify them, determine which gate-level nets to query, and build VERIFIED hierarchy paths.

**Inputs:** REF_DIR, TILE, TAG, BASE_DIR

---

## CRITICAL: Instance Names vs Module Names

**ALWAYS use instance names in hierarchy paths, NEVER module names.**

- Module name: what appears after `module` keyword in RTL (e.g., `module_b`)
- Instance name: what appears on instantiation line (e.g., `INST_B` in `module_b INST_B (...)`)
- Hierarchy path uses instance names: `<INST_A>/<INST_B>/signal_name` ✓
- WRONG: `<module_name_A>/<module_name_B>/signal_name` ✗

---

## Step A — Run RTL Diff

```bash
cd <REF_DIR>
diff -rq --exclude="*.vf" --exclude="*.vfe" --exclude="*.d" data/PreEco/SynRtl/ data/SynRtl/
```

For each file that differs, run full diff:
```bash
diff <REF_DIR>/data/PreEco/SynRtl/<file> <REF_DIR>/data/SynRtl/<file>
```

---

## Step B — Classify Each Change

For each diff hunk, classify as ONE of:

| Type | Description | Example |
|------|-------------|---------|
| `wire_swap` | Existing signal replaced by different signal | `old_sig` → `new_sig` in expression |
| `new_port` | New `input`/`output` port declaration added | `input new_port_name` |
| `new_logic` | New wire/always/assign/instance added | New always block |
| `port_connection` | Port connection changed on module instance | `.port(old_sig)` → `.port(new_sig)` |

For each change record:
```json
{
  "file": "<rtl_file.v>",
  "module_name": "<module_name_from_changed_file>",
  "change_type": "<wire_swap|new_port|new_logic|port_connection>",
  "old_token": "<old_signal_name>",
  "new_token": "<new_signal_name>",
  "context_line": "<full RTL line containing the change>",
  "target_register": "<register_name>",
  "target_bit": "<[N] or null>"
}
```

**`target_register` and `target_bit` extraction (MANDATORY for wire_swap):**

From `context_line`, extract the LHS register being assigned — this is the TARGET REGISTER that `eco_netlist_studier` uses for backward cone verification.

- Pattern: `<register_name>[<N>]  <=` or `<register_name>  <=`
- Example: `<TargetReg>[<N>]   <=` → `target_register: "<TargetReg>"`, `target_bit: "[<N>]"`
- Example: `<TargetReg>  <=` → `target_register: "<TargetReg>"`, `target_bit: null`
- If multiple always blocks changed (different bits of same register), record each separately with its own `target_bit`
- For `new_port`, `new_logic`, `port_connection` types: set both to `null`

**`module_name`** = the module that **declares** the changed signals as `reg` or `wire` — NOT necessarily the module in the changed file. The changed file's module is only the starting candidate. Step C will verify whether the signals are truly declared (`reg`/`wire`) in that module or merely passed through as input/output ports. If they are only ports, `module_name` must be updated to the parent module where the `reg`/`wire` declaration lives. Leave this field as the changed file's module initially — Step C is responsible for correcting it if needed.

---

## Step C — Hierarchy Tracing (MANDATORY)

**CRITICAL: Trace to the DECLARING module, not the usage module.**

The signal may pass through multiple ancestor modules as a port. The hierarchy path MUST start from the module that **declares** the signal as `reg` or `wire` — NOT from any ancestor that merely passes it through as a port connection. If you stop at the wrong level, the hierarchy will be too shallow and the scope filter in eco_netlist_studier will be too wide.

For EACH signal involved in a change, trace its full hierarchy:

**1. Find the DECLARING module (reg/wire only — not port passthrough):**

```bash
grep -rn "^\s*reg\b.*<signal>\|^\s*wire\b.*<signal>" <REF_DIR>/data/PreEco/SynRtl/
```

Use anchored patterns (`^\s*reg\b`, `^\s*wire\b`) to find only **declarations**, not usages or port connections. The file that contains the declaration is the declaring module.

- Start with the changed file's module as the candidate. Confirm that `reg` or `wire` declaration of the signal exists in that file:
```bash
grep -n "^\s*reg\b.*<signal>\|^\s*wire\b.*<signal>" <REF_DIR>/data/PreEco/SynRtl/rtl_<module_X>.v
```
- **If FOUND** → declaring module = changed file's module → `module_name` in JSON stays as `<module_X>` ✓
- **If NOT found** → the signal is only an `input`/`output` port in the changed file. The declaring module is a **PARENT** module (one that instantiates the changed file's module and drives this signal as a `reg`/`wire`). Search all RTL files for the declaration:
```bash
grep -rn "^\s*reg\b.*<signal>\|^\s*wire\b.*<signal>" <REF_DIR>/data/PreEco/SynRtl/
```
The file containing the `reg`/`wire` declaration is the declaring module. **Update `module_name` in the JSON to this declaring module** — NOT the changed file's module. The hierarchy path and scope filter in Steps 2–4 will be based on this declaring module's instance, not the changed file's instance.

**Example:** diff found in `rtl_umctim.v` (module `umctim`), but `SendWckSyncOffCs0` is `reg` in `rtl_umcarb.v` (module `umcarb`). → `module_name = umcarb`, hierarchy starts at `ARB` (umcarb's instance in the tile), NOT at `ARB/TIM` (umctim's instance).

**2. Find that module's INSTANCE NAME in its parent:**
```bash
grep -n "<module_name>" <REF_DIR>/data/PreEco/SynRtl/rtl_<parent_module>.v
```
Extract the instance name from the instantiation line:
```
<module_b> <INST_B> (   ← module_name=<module_b>, instance_name=<INST_B>
```

**3. Repeat up the hierarchy until you reach the tile module — stop at the tile's DIRECT CHILDREN:**

Keep tracing upward until the parent module IS the tile module (its name matches `<TILE>`). Stop there — do NOT include the tile itself in the path. The tile is the boundary.

```bash
grep -n "<parent_module_name>" <REF_DIR>/data/PreEco/SynRtl/rtl_<grandparent>.v
```

**4. Build full path using INSTANCE NAMES — from declaring module's instance up to (but NOT including) the tile:**

- If tile=`<TILE>` and hierarchy is: `<TILE>` → `<INST_A>` (instance of `<module_A>`) → `<INST_B>` (instance of `<module_B>`) and signal is DECLARED in `<module_B>`
- Path = `<INST_A>/<INST_B>/signal_name`   ← does NOT start with `<TILE>`
- The `hierarchy` array contains only levels BELOW the tile: `["<INST_A>", "<INST_B>"]`

**CRITICAL — Do NOT include the tile name in the path:**
FM scopes all queries under the tile automatically. If `<TILE>=umccmd` and the path is `umccmd/ARB/signal`, FM constructs the internal path as `.../umccmd/umccmd/ARB/signal` (double prefix) → FM-036 error for all nets. The correct path is `ARB/signal`.

Rule: `net_path[0]` must NEVER equal `<TILE>`.

**5. Self-verify (MANDATORY before writing output):**
```bash
# Confirm reg/wire declaration exists in the declaring module file
grep -n "^\s*reg\b.*<signal>\|^\s*wire\b.*<signal>" <REF_DIR>/data/PreEco/SynRtl/rtl_<declaring_module>.v

# Confirm instance name is correct at each level
grep -n "<module_name> <instance_name>" <REF_DIR>/data/PreEco/SynRtl/rtl_<parent_module>.v

# Confirm net_path does NOT start with tile name
# WRONG: net_path = "<TILE>/<INST_A>/signal"  → FM-036
# RIGHT: net_path = "<INST_A>/signal"
```

If the `reg`/`wire` declaration is NOT found in the module you identified → you stopped too high — go one level deeper.
If `net_path` starts with `<TILE>` → you went one level too far up — remove the first component.

**6. Update `module_name` in JSON and RPT if declaring module differs from changed file:**

If Step C found that the declaring module is different from the changed file's module (i.e., the signals are only ports in the changed file), you MUST:
- Update `"module_name"` in `<TAG>_eco_rtl_diff.json` to the declaring module
- Update the `Module :` line in `<TAG>_eco_step1_rtl_diff.rpt` to the declaring module
- Add a `Notes:` section in the RPT explaining: "diff found in `<changed_file>` (module `<changed_module>`), but `<signal>` is declared as `reg`/`wire` in `<declaring_module>` — `module_name` set to declaring module `<declaring_module>`"

**This is the root cause of Run B's Step 1 error:** diff was in `rtl_umctim.v` → candidate module = `umctim`. But `SendWckSyncOffCs0`/`SendWckSyncOffCs2` are `reg` in `rtl_umcarb.v`. Correct `module_name` = `umcarb`, hierarchy starts at `ARB`, not `ARB/TIM`.

---

## Step D — Net Selection

For EACH change, determine which gate-level nets will reveal WHERE to make the ECO and HOW to rewire. The goal is to find which gate-level net connects to the target pin.

**General principles:**
- For `wire_swap`: query both old_token and new_token — find current driver of old_token and confirm new_token exists in gate level
- For `new_port`: query the new port signal and the register/logic it gates
- For `new_logic`: query the enable signal and the D-input of the affected register
- For `port_connection`: query both old and new connection signals
- **Avoid querying flip-flop Q outputs** — focus on driving nets and inputs

**Bus signals:** If `old_token` or `new_token` is declared as `reg [N:0] SignalName`, generate BOTH variants for that signal:
- `<INST_A>/<INST_B>/SignalName` (may work in some FM targets)
- `<INST_A>/<INST_B>/SignalName_0_` (gate-level bit-indexed form for bit 0)

Pass BOTH to find_equivalent_nets — FM-036 on one, the other may succeed.

**CRITICAL — `target_register` is NEVER queried via find_equivalent_nets.** `target_register` (the LHS register of the changed assignment, e.g., `ArbBypassWckIsInSync`) is only recorded in the JSON for Step 3 backward cone verification. Do NOT add it or any bus variant of it to `nets_to_query`. Only `old_token` and `new_token` (and their bus variants if applicable) go into `nets_to_query`.

---

## Output JSON

Write to `<BASE_DIR>/data/<TAG>_eco_rtl_diff.json` (always use the full absolute path — the agent may be cd'd to REF_DIR for diffs, but output always goes to BASE_DIR/data/):

```json
{
  "changes": [
    {
      "file": "<rtl_file.v>",
      "module_name": "<declaring_module>",
      "change_type": "<wire_swap|new_port|new_logic|port_connection>",
      "old_token": "<old_signal_name>",
      "new_token": "<new_signal_name>",
      "context_line": "<full RTL line containing the change>",
      "target_register": "<register_name from LHS of context_line>",
      "target_bit": "<[0] or null>"
    }
  ],
  "nets_to_query": [
    {
      "net_path": "<INST_A>/<INST_B>/<old_signal_name>",
      "hierarchy": ["<INST_A>", "<INST_B>"],
      "reason": "wire_swap: find current gate-level driver of old signal",
      "is_bus_variant": false
    },
    {
      "net_path": "<INST_A>/<INST_B>/<old_signal_name>_0_",
      "hierarchy": ["<INST_A>", "<INST_B>"],
      "reason": "wire_swap: bus variant of <old_signal_name> (bit 0)",
      "is_bus_variant": true
    },
    {
      "net_path": "<INST_A>/<INST_B>/<new_signal_name>",
      "hierarchy": ["<INST_A>", "<INST_B>"],
      "reason": "wire_swap: confirm new signal exists at gate level",
      "is_bus_variant": false
    }
  ]
}
```

All `net_path` values must be verified hierarchy paths using instance names. Do NOT include unverified paths.

---

## Output RPT

After writing the JSON, write `<BASE_DIR>/data/<TAG>_eco_step1_rtl_diff.rpt` then copy to `AI_ECO_FLOW_DIR`:
```bash
cp <BASE_DIR>/data/<TAG>_eco_step1_rtl_diff.rpt <AI_ECO_FLOW_DIR>/
```

```
================================================================================
STEP 1 — RTL DIFF ANALYSIS
Tag: <TAG>  |  Tile: <TILE>  |  JIRA: DEUMCIPRTL-<JIRA>
================================================================================

<For each entry in changes[]:>
Source File     : <file>
Module          : <module_name>
Change Type     : <change_type>
  Old Signal    : <old_token>
  New Signal    : <new_token>
  Target Reg    : <target_register><target_bit>
  Context       :
    <context_line>

<Repeat block if more than one change>

--------------------------------------------------------------------------------
Nets to Query (<N> nets):
--------------------------------------------------------------------------------
  [<n>] <net_path>
        Reason   : <reason>
        Bus Var  : <YES / NO>

<Repeat for each net>

================================================================================
```
