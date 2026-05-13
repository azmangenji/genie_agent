# ECO 9899 — Fix Plan

**Goal:** Make the AI ECO flow handle DEUMCIPRTL-9899 (pure combinational, multi-module, cross-channel, asymmetric) cleanly in Round 1.  
**Based on:** Full audit of current MDs + scripts as of 2026-05-11.  
**Gaps addressed:** GAP-A, GAP-B, GAP-C, GAP-D, GAP-E (from `9899_gaps.md`).

---

## Execution Order

Fix in this priority order — each builds on the previous:

```
1. GAP-E  (port naming)   — smallest, unblocks all downstream naming
2. GAP-A  (no-DFF type)   — biggest, unblocks Step 1 classification
3. GAP-C  (instance scope)— needed before GAP-B hookup logic
4. GAP-D  (cone replace)  — new apply action, small
5. GAP-B  (cross-channel) — last, depends on GAP-C instance tracking
```

---

## GAP-E Fix — Literal Port Naming

**Files to change:** `rtl_diff_analyzer.md`, `eco_netlist_studier.md`, `eco_validate_step1.py`, `eco_validate_step3.py`

### 1. `rtl_diff_analyzer.md`

**Where:** §Step B classification table — `new_port` and `port_promotion` rows.

**Change:** Add `eco_naming_style` field to every `new_port` / `port_promotion` entry:
```json
{
  "change_type": "new_port",
  "port_name": "<exact name from RTL diff — do NOT prefix with ECO_<jira>_>",
  "eco_naming_style": "functional"   // or "prefixed" when RTL uses ECO_NNNN_ style
}
```

**Rule to add:** "Extract the literal port name from the RTL diff. Do NOT apply `ECO_<jira>_` prefix. Set `eco_naming_style: 'prefixed'` only when the RTL diff itself uses an `ECO_<jira>_` or `ECO_<nnnn>_` prefix on the new port name."

### 2. `eco_netlist_studier.md`

**Where:** Phase 2 — port_declaration emit section.

**Change:** When building port decl entry from an `eco_naming_style: "functional"` change, use `port_name` literally:
```python
# WRONG (current assumed behavior):
port_decl_name = f"ECO_{jira}_{signal_name}"

# CORRECT:
port_decl_name = change["port_name"]   # literal from RTL diff
```

**Add rule:** "For `eco_naming_style: 'functional'` entries, the port name in the study JSON MUST equal `change['port_name']` verbatim. Do not add any prefix."

### 3. `eco_validate_step1.py`

**Where:** After existing new_port hygiene check (currently checks `declaration_type` set + no duplicates).

**Add check — `[PORT_NAME_LITERAL]`:**
```python
# For every new_port / port_promotion change:
eco_style = c.get("eco_naming_style", "prefixed")
port_name = c.get("port_name", "")
if eco_style == "functional":
    # FAIL if port_name has ECO_\d+ prefix pattern
    if re.match(r'^ECO_\d+_', port_name):
        issues.append(
            f"[PORT_NAME_LITERAL] FAIL: change[{idx}] has eco_naming_style='functional' "
            f"but port_name='{port_name}' has an ECO_NNNN_ prefix — "
            f"extract the literal RTL name instead."
        )
```

### 4. `eco_validate_step3.py`

**Where:** After existing port_connection completeness check.

**Add check — `[PORT_LITERAL_MATCH]`:**
```python
# Cross-check: every new_port/port_promotion change with eco_naming_style='functional'
# must appear in the study with the exact literal port name — no prefix variation.
for idx, c in enumerate(rtl_diff.get('changes', [])):
    if c.get('change_type') not in ('new_port', 'port_promotion'):
        continue
    if c.get('eco_naming_style') != 'functional':
        continue
    expected = c.get('port_name', '')
    for stage in ['Synthesize', 'PrePlace', 'Route']:
        found = any(
            e.get('signal_name') == expected or e.get('port_name') == expected
            for e in study.get(stage, [])
            if e.get('change_type') in ('port_declaration', 'new_port')
        )
        if not found:
            issues.append(
                f"[PORT_LITERAL_MATCH] {stage}: port '{expected}' "
                f"(eco_naming_style=functional) not found in study — "
                f"studier may have auto-prefixed with ECO_JIRA_."
            )
```

---

## GAP-A Fix — No-DFF ECO Type (`new_logic_gate_only`)

**Files to change:** `rtl_diff_analyzer.md`, `eco_netlist_studier.md`, `eco_fenets_derive_queries.py`, `eco_passes_2_4.py`, `eco_validate_step1.py`, `eco_validate_step3.py`, `eco_pre_fm_check.py`

### 1. `rtl_diff_analyzer.md`

**Where:** §Step B change type classification table.

**Add new change type `new_logic_gate_only`:**

```
| new_logic_gate_only | New combinational cells inserted with NO new DFF.
|                     | Output drives an existing net or a new wire consumed by existing logic.
|                     | Has: output_net, replaces_net (optional), gate_chain[],
|                     |      consumer_cell_inst, consumer_cell_pin, instance_scope
|                     | Does NOT have: dff_clock, reset_signal, mode_s_anchor, d_input_gate_chain
```

**Classification trigger:** RTL diff shows new cell instantiations or assign statements with:
- No new `always @(posedge ...)` / flip-flop statement
- No new `reg` declaration
- Output signal is either (a) an existing signal with a new driver, or (b) a new wire consumed by an existing cell

**Required fields in emitted JSON entry:**
```json
{
  "change_type": "new_logic_gate_only",
  "instance_scope": "<instance hierarchy path to the module where cells are inserted>",
  "output_net": "<name of the final output wire of the new gate chain>",
  "replaces_net": "<existing net that the new chain's output replaces — null if purely additive>",
  "consumer_cell_inst": "<existing cell instance whose input pin is being rewired>",
  "consumer_cell_pin": "<pin name on consumer_cell_inst that changes>",
  "gate_chain": [
    { "seq": 0, "gate_function": "INV", "inputs": ["<leaf_signal>"], "output": "n_eco_<jira>_0" },
    { "seq": 1, "gate_function": "AND2", "inputs": ["n_eco_<jira>_0", "<leaf2>"], "output": "<output_net>" }
  ],
  "eco_naming_style": "prefixed"
}
```

**Add §E-GATE guidance:** "When the RTL diff shows a new combinational expression replacing an existing signal `X`, classify as `new_logic_gate_only` with `replaces_net: 'X'` and `consumer_cell_inst` = the existing gate instance that used to take `X` as input."

### 2. `eco_fenets_derive_queries.py`

**Where:** `derive()` function, after Cat 4 block (lines ~80-100).

**Add Cat 9 — `new_logic_gate_only` leaf queries:**
```python
# Cat 9: new_logic_gate_only — query replaces_net + all gate_chain leaf inputs
if ct == 'new_logic_gate_only':
    # 9a: the net being replaced (find its gate-level equivalent)
    rep = c.get('replaces_net')
    if rep:
        out.append({
            'net_path': _abs_path(tile, scope, rep),
            'signal':   rep,
            'category': 9,
            'source':   f'changes[{idx}].replaces_net',
        })
    # 9b: every leaf input in gate_chain (same skip rules as Cat 4)
    for g in (c.get('gate_chain') or []):
        for inp in (g.get('inputs') or []):
            if not isinstance(inp, str): continue
            base = inp.split('[')[0]
            if base.startswith(_SKIP_INPUT_PREFIXES): continue
            if not base: continue
            out.append({
                'net_path': _abs_path(tile, scope, base),
                'signal':   base,
                'category': 9,
                'source':   f'changes[{idx}].gate_chain[{g.get("seq","?")}]',
            })
    # 9c: consumer_cell_inst is an existing cell — no FM query needed
    # (it will be found by grep in the PostEco netlist directly)
```

### 3. `eco_netlist_studier.md`

**Where:** Phase 0 — DFF insertion section.

**Add `new_logic_gate_only` branch before Phase 0 DFF logic:**

```
## Phase 0a — Pure Combinational Gate Insertion (new_logic_gate_only)

For every `new_logic_gate_only` change in rtl_diff:

1. Resolve `replaces_net` per stage using fenets rename map (same as wire_swap Cat 1).
   If `replaces_net` is null, the chain output is a NEW wire consumed by `consumer_cell_inst`.

2. Resolve each `gate_chain[].inputs` leaf per stage from fenets rename map.

3. Build study JSON entry per stage with:
   - `change_type: "cone_replacement"`
   - `instance_scope`: exact module scope from rtl_diff
   - `output_net`: name of final chain output (stage-resolved)
   - `replaces_net_per_stage`: { Synthesize: <net>, PrePlace: <net>, Route: <net> }
   - `consumer_cell_inst`: as-is from rtl_diff (instance name is stable across stages)
   - `consumer_cell_pin`: as-is from rtl_diff
   - `gate_chain`: resolved per-stage inputs substituted
   - `strategy: "cone_replacement"`

4. Do NOT attempt Mode S triage on new_logic_gate_only entries — no DFF, no scan.

5. Do NOT enter Phase 0 DFF logic for new_logic_gate_only entries.
```

### 4. `eco_passes_2_4.py`

**Where:** After existing `apply_port_connection()` function.

**Add new function `apply_cone_replacement()`:**
```python
def apply_cone_replacement(lines, entry, stage):
    """
    Insert new gate cells from gate_chain[] before endmodule in the target module.
    Then rewrite consumer_cell_inst's consumer_cell_pin from replaces_net to output_net.
    
    Steps:
    1. Find the module boundary for entry['instance_scope']
    2. Insert wire declarations for all intermediate n_eco_* nets + output_net
    3. Insert each gate cell instantiation before endmodule
    4. Find consumer_cell_inst and rewrite .consumer_cell_pin(replaces_net) 
       -> .consumer_cell_pin(output_net)
    5. Return modified lines + status
    """
    # Implementation follows same pattern as existing apply_new_cell():
    # - find_module_body() using instance_scope
    # - insert_before_endmodule() for wire decls + cell insts
    # - targeted pin_rewire() for consumer_cell_pin
    pass  # implement
```

**Add call site in main apply loop:** When `entry['change_type'] == 'cone_replacement'`, call `apply_cone_replacement()` instead of `apply_new_cell()`.

### 5. `eco_validate_step1.py`

**Where:** After existing cell truth-table check.

**Add check `[GATE_ONLY_FIELDS]`:**
```python
for idx, c in enumerate(rtl_diff.get('changes', [])):
    if c.get('change_type') != 'new_logic_gate_only':
        continue
    missing = []
    if not c.get('gate_chain'):
        missing.append('gate_chain')
    if not c.get('instance_scope'):
        missing.append('instance_scope')
    if not c.get('output_net'):
        missing.append('output_net')
    if not c.get('consumer_cell_inst') and not c.get('replaces_net'):
        missing.append('consumer_cell_inst or replaces_net (at least one required)')
    # FAIL if has dff_clock or reset_signal (those belong to new_logic_dff only)
    if c.get('dff_clock'):
        issues.append(f"[GATE_ONLY_FIELDS] FAIL changes[{idx}]: new_logic_gate_only must not have dff_clock")
    if missing:
        issues.append(f"[GATE_ONLY_FIELDS] FAIL changes[{idx}]: missing required fields: {missing}")
```

### 6. `eco_validate_step3.py`

**Where:** After existing DFF chain expansion check.

**Add check `[CONE_REPLACEMENT_ENTRIES]`:**
```python
for idx, c in enumerate(rtl_diff.get('changes', [])):
    if c.get('change_type') != 'new_logic_gate_only':
        continue
    output_net = c.get('output_net', '?')
    for stage in ['Synthesize', 'PrePlace', 'Route']:
        found = any(
            e.get('change_type') == 'cone_replacement' and
            e.get('output_net') == output_net
            for e in study.get(stage, [])
        )
        if not found:
            issues.append(
                f"CRITICAL: {stage} has no cone_replacement entry for output_net='{output_net}' "
                f"(from changes[{idx}] new_logic_gate_only) — studier skipped it"
            )
```

### 7. `eco_pre_fm_check.py`

**Where:** After existing GAP-3 bridge checks.

**Add check `[CONE_REPLACEMENT_COMPLETENESS]`:**
```python
# For every cone_replacement entry in study, verify:
# (a) new gate cells exist in PostEco
# (b) consumer_cell_inst no longer takes replaces_net on consumer_cell_pin
# (c) consumer_cell_inst now takes output_net on consumer_cell_pin
for stage in ['Synthesize', 'PrePlace', 'Route']:
    gz = f"{ref_dir}/data/PostEco/{stage}.v.gz"
    for e in study.get(stage, []):
        if e.get('change_type') != 'cone_replacement': continue
        output_net   = e.get('output_net', '')
        replaces_net = e.get('replaces_net_per_stage', {}).get(stage, '')
        consumer     = e.get('consumer_cell_inst', '')
        pin          = e.get('consumer_cell_pin', '')
        # (a) output_net wire exists in netlist
        if output_net and zgrep_count(output_net, gz) == 0:
            issues.append(f"[CONE_REPLACEMENT_COMPLETENESS] {stage}: output_net '{output_net}' not found in PostEco")
        # (b) consumer_cell_inst no longer uses replaces_net on that pin
        if consumer and replaces_net and pin:
            old_pattern = rf'\.{pin}\s*\(\s*{re.escape(replaces_net)}\s*\)'
            if zgrep_count(old_pattern, gz) > 0:
                issues.append(f"[CONE_REPLACEMENT_COMPLETENESS] {stage}: consumer {consumer}.{pin} still wired to old net '{replaces_net}'")
        # (c) consumer_cell_inst now uses output_net on that pin
        if consumer and output_net and pin:
            new_pattern = rf'\.{pin}\s*\(\s*{re.escape(output_net)}\s*\)'
            if zgrep_count(new_pattern, gz) == 0:
                issues.append(f"[CONE_REPLACEMENT_COMPLETENESS] {stage}: consumer {consumer}.{pin} not wired to new net '{output_net}'")
```

---

## GAP-C Fix — Instance Scope Tracking

**Files to change:** `rtl_diff_analyzer.md`, `eco_netlist_studier.md`, `eco_passes_2_4.py`, `eco_validate_step1.py`, `eco_validate_step3.py`

### 1. `rtl_diff_analyzer.md`

**Where:** §Step B — ALL change types table.

**Add `instance_scope` field rule:** "Every change entry MUST carry `instance_scope` — the instance hierarchy path (instance names only, not module names) to the module where the change applies. For changes that apply to ALL instances of a module, set `applies_to_all_instances: true`. For changes that apply to ONLY ONE specific instance, set `applies_to_all_instances: false`."

**Add `asymmetric_instance_changes` detection guidance:**
"When two instances of the same module type receive DIFFERENT changes (e.g., dcqarb_0 gets OR2 but dcqarb_1 does not), emit SEPARATE change entries — one per instance — each with its own `instance_scope` and `applies_to_all_instances: false`. Do NOT merge them into a single entry."

### 2. `eco_netlist_studier.md`

**Where:** Phase 2 (module body edits).

**Add instance-scope rule:** "When applying changes from study JSON, ALWAYS locate the module body by the `instance_scope` path — not by module type. If two instances of the same module type have different study entries, apply them independently to their respective module bodies."

**Add asymmetry detection note:** "If the rtl_diff has entries for the same port/cell in two different `instance_scope` values, emit two separate study entries — one per scope. Do NOT collapse them."

### 3. `eco_passes_2_4.py`

**Where:** `apply_new_cell()` and `apply_port_connection()` functions.

**Add `instance_scope` parameter support:**

Current `find_module_body()` uses the module type name. Extend to also accept an `instance_scope` path:
```python
def find_module_body_by_instance(lines, instance_scope):
    """
    Locate the module body for a SPECIFIC instance identified by instance_scope.
    
    Strategy:
    1. Walk instance_scope path (e.g. 'ARB/DCQARB0') from outer to inner.
    2. At each level, find the instantiation line to extract the MODULE TYPE.
    3. Then find that module type's `module <type>(` declaration.
    4. Return (start_line, end_line) of that module's body.
    
    This handles cases where two instances of the same module type need
    different edits — each instance_scope resolves to the same module type,
    but callers disambiguate by applying edits sequentially.
    
    NOTE: If two instances share the same module type AND need different edits,
    the module must be duplicated first (raise NotImplementedError — flag for
    manual review; this is an edge case not yet automated).
    """
    pass  # implement
```

**Add guard in apply loop:**
```python
# When entry has applies_to_all_instances: false, verify we're only editing
# the correct module — not broadcasting to all instances of same type.
if not entry.get('applies_to_all_instances', True):
    scope = entry.get('instance_scope', '')
    # resolve module type from instance_scope before editing
    mod_type = resolve_module_type(lines, scope)
    # warn if mod_type appears >1 time in the netlist (multiple instances)
    if netlist_module_instance_count(lines, mod_type) > 1:
        log_warning(f"Module '{mod_type}' has multiple instances but change is instance-specific — verify correct scope: {scope}")
```

### 4. `eco_validate_step1.py`

**Where:** After existing port hygiene check.

**Add check `[INSTANCE_SCOPE_PRESENT]`:**
```python
for idx, c in enumerate(rtl_diff.get('changes', [])):
    if c.get('change_type') in ('new_port', 'port_promotion', 'new_logic_gate_only',
                                 'port_connection', 'wire_swap', 'and_term'):
        if not c.get('instance_scope') and not c.get('scope'):
            issues.append(
                f"[INSTANCE_SCOPE_PRESENT] WARN changes[{idx}] ({c.get('change_type')}): "
                f"no instance_scope or scope field — applier cannot locate target module"
            )
```

### 5. `eco_validate_step3.py`

**Where:** After cone_replacement check (from GAP-A).

**Add check `[ASYMMETRIC_INSTANCE_SCOPE]`:**
```python
# Detect asymmetric instance changes: same port/cell in two different instance_scopes
from collections import defaultdict
port_to_scopes = defaultdict(list)
for idx, c in enumerate(rtl_diff.get('changes', [])):
    if c.get('change_type') in ('new_port', 'port_connection', 'new_logic_gate_only'):
        sig = c.get('port_name') or c.get('signal_name') or c.get('output_net', '')
        sc  = c.get('instance_scope', '')
        if sig and sc:
            port_to_scopes[sig].append(sc)

for sig, scopes in port_to_scopes.items():
    if len(set(scopes)) > 1:
        # Multiple scopes for same signal — verify study has separate entries per scope
        for scope in set(scopes):
            for stage in ['Synthesize', 'PrePlace', 'Route']:
                found = any(
                    (e.get('signal_name') == sig or e.get('port_name') == sig) and
                    e.get('instance_scope') == scope
                    for e in study.get(stage, [])
                )
                if not found:
                    issues.append(
                        f"[ASYMMETRIC_INSTANCE_SCOPE] {stage}: signal '{sig}' has "
                        f"instance_scope='{scope}' in rtl_diff but no matching study entry — "
                        f"studier merged asymmetric changes"
                    )
```

---

## GAP-D Fix — Consumer Cell Pin Rewire

**Files to change:** `eco_passes_2_4.py`, `eco_validate_step4.py`, `eco_pre_fm_check.py`

### 1. `eco_passes_2_4.py`

**Where:** After `apply_cone_replacement()` (added in GAP-A).

**Add `apply_consumer_rewire()` function:**
```python
def apply_consumer_rewire(lines, consumer_inst, consumer_pin, old_net, new_net, module_scope):
    """
    Find consumer_inst in the module body for module_scope.
    Rewrite .consumer_pin(old_net) -> .consumer_pin(new_net).
    
    Rules:
    - Scope the search to the module body only (between `module <type>(` and `endmodule`)
    - Do NOT do a global replace — only target consumer_inst
    - If old_net appears on this pin 0 times: report ALREADY_APPLIED or NOT_FOUND
    - If old_net appears on this pin >1 time: report AMBIGUOUS (single-occurrence rule)
    - Return: (modified_lines, status)  where status in (APPLIED, ALREADY_APPLIED, AMBIGUOUS, NOT_FOUND)
    """
    # Implementation: grep within module body for the instance, then do targeted
    # substitution on the exact pin line
    pass  # implement
```

**Call site:** In `apply_cone_replacement()`, after inserting new gate cells, call `apply_consumer_rewire()`.

### 2. `eco_validate_step4.py`

**Where:** After existing GAP-2 bus_rename check.

**Add check `[CONSUMER_REWIRE_APPLIED]`:**
```python
# For every cone_replacement APPLIED entry, verify consumer_cell rewire happened
for stage in ['Synthesize', 'PrePlace', 'Route']:
    for e in applied.get(stage, []):
        if e.get('change_type') != 'cone_replacement': continue
        if e.get('status') != 'APPLIED': continue
        consumer = e.get('consumer_cell_inst', '')
        pin      = e.get('consumer_cell_pin', '')
        new_net  = e.get('output_net', '')
        if not (consumer and pin and new_net): continue
        # Check that the applied JSON records the consumer rewire
        rewire_done = e.get('consumer_rewired', False)
        if not rewire_done:
            issues.append(
                f"HIGH: {stage} cone_replacement for '{e.get('output_net','?')}' "
                f"has no consumer_rewired=true — consumer {consumer}.{pin} may still use old net"
            )
```

### 3. `eco_pre_fm_check.py`

The `[CONE_REPLACEMENT_COMPLETENESS]` check added in GAP-A already covers this:
- Check (b): consumer_cell_inst no longer takes replaces_net on consumer_cell_pin ✓
- Check (c): consumer_cell_inst now takes output_net on consumer_cell_pin ✓

No additional pre_fm_check change needed.

---

## GAP-B Fix — Cross-Channel Wiring

**Files to change:** `rtl_diff_analyzer.md`, `eco_fenets_derive_queries.py`, `eco_passes_2_4.py`, `eco_validate_step3.py`, `eco_pre_fm_check.py`

### 1. `rtl_diff_analyzer.md`

**Where:** §Step B — `port_connection` change type.

**Add `cross_channel` detection rule:**
"When the same port is added to two instances of the same module type but with DIFFERENT driving signals (e.g., DCQARB0.SplitActInProgOthDcq ← Cmd1, DCQARB1.SplitActInProgOthDcq ← Cmd0), emit a `port_connection` entry for EACH instance separately with:
- `instance_scope`: the specific instance path
- `hookup_net`: the specific wire driving THIS instance's new port
- `applies_to_all_instances: false`
- `cross_channel: true` (flag for fenets and applier awareness)"

**Example:**
```json
[
  { "change_type": "port_connection", "port_name": "SplitActInProgOthDcq",
    "instance_scope": "ARB/DCQARB0", "hookup_net": "SplitActInProgCmd1",
    "cross_channel": true, "applies_to_all_instances": false },
  { "change_type": "port_connection", "port_name": "SplitActInProgOthDcq",
    "instance_scope": "ARB/DCQARB1", "hookup_net": "SplitActInProgCmd0",
    "cross_channel": true, "applies_to_all_instances": false }
]
```

### 2. `eco_fenets_derive_queries.py`

**Where:** Cat 7 block (hookup hints).

**Add Cat 10 — cross_channel hookup wire queries:**
```python
# Cat 10: port_connection with cross_channel=true — query the hookup_net
# at PARENT scope (the wire lives at parent, not inside the child module)
if ct == 'port_connection' and c.get('cross_channel'):
    hw = c.get('hookup_net')
    # hookup_net lives at the parent scope — strip one level from instance_scope
    parent_scope = '/'.join(scope.split('/')[:-1]) if '/' in scope else ''
    if hw:
        out.append({
            'net_path': _abs_path(tile, parent_scope, hw),
            'signal':   hw,
            'category': 10,
            'cross_channel': True,
            'source':   f'changes[{idx}].cross_channel_hookup',
        })
```

### 3. `eco_passes_2_4.py`

**Where:** `apply_port_connection()` function.

**Extend to handle `cross_channel` + per-instance hookup:**
```python
def apply_port_connection(lines, entry, stage):
    """
    Existing: add .port(net) to a module's instance block in the parent.
    
    Extension for cross_channel=True:
    - Look up the specific instance named by entry['instance_scope']
    - Apply entry['hookup_net'] to THAT specific instance only
    - Do NOT apply to other instances of the same module type
    """
    if entry.get('cross_channel'):
        # Resolve: which parent instance call to edit?
        instance_path = entry.get('instance_scope', '').split('/')
        inst_name = instance_path[-1]  # e.g. 'DCQARB0'
        hookup_net = entry.get('hookup_net', '')
        port_name  = entry.get('port_name', '')
        # Find the parent module body, then find only the specific inst_name call
        # and append .port_name(hookup_net) to it
        return _apply_single_instance_port(lines, inst_name, port_name, hookup_net)
    else:
        # existing logic
        ...
```

### 4. `eco_validate_step3.py`

**Where:** After asymmetric instance scope check (from GAP-C).

**Add check `[CROSS_CHANNEL_HOOKUP]`:**
```python
# For every cross_channel port_connection in rtl_diff, verify study has
# two separate entries — one per instance — with DIFFERENT hookup_net values
cross_ports = [c for c in rtl_diff.get('changes', [])
               if c.get('change_type') == 'port_connection' and c.get('cross_channel')]
port_groups = {}
for c in cross_ports:
    pn = c.get('port_name', '')
    port_groups.setdefault(pn, []).append(c)

for port_name, entries in port_groups.items():
    hookup_nets = {e.get('hookup_net') for e in entries}
    if len(hookup_nets) < 2:
        issues.append(
            f"[CROSS_CHANNEL_HOOKUP] cross_channel port '{port_name}' has only "
            f"1 unique hookup_net value — cross-channel wiring requires 2 different hookup wires"
        )
    # Verify study has separate entries per instance with different hookup_net
    for e in entries:
        scope    = e.get('instance_scope', '')
        expected = e.get('hookup_net', '')
        for stage in ['Synthesize', 'PrePlace', 'Route']:
            found = any(
                se.get('port_name') == port_name and
                se.get('instance_scope') == scope and
                se.get('hookup_net') == expected
                for se in study.get(stage, [])
            )
            if not found:
                issues.append(
                    f"[CROSS_CHANNEL_HOOKUP] {stage}: no study entry for "
                    f"port '{port_name}' scope='{scope}' hookup='{expected}'"
                )
```

### 5. `eco_pre_fm_check.py`

**Where:** After `[CONE_REPLACEMENT_COMPLETENESS]` check (added in GAP-A).

**Add check `[CROSS_CHANNEL_HOOKUP_APPLIED]`:**
```python
# For each cross_channel port_connection in study, verify the CORRECT hookup_net
# appears in the correct instance call in PostEco (not the wrong one)
for stage in ['Synthesize', 'PrePlace', 'Route']:
    gz = f"{ref_dir}/data/PostEco/{stage}.v.gz"
    for e in study.get(stage, []):
        if e.get('change_type') != 'port_connection': continue
        if not e.get('cross_channel'): continue
        inst      = e.get('instance_scope', '').split('/')[-1]
        port      = e.get('port_name', '')
        hookup    = e.get('hookup_net', '')
        if not (inst and port and hookup): continue
        # The correct pattern: .port(hookup) must appear near the instance name
        # Rough check: both inst and .port(hookup) appear in netlist
        if zgrep_count(rf'\.{port}\s*\(\s*{re.escape(hookup)}\s*\)', gz) == 0:
            issues.append(
                f"[CROSS_CHANNEL_HOOKUP_APPLIED] {stage}: .{port}({hookup}) "
                f"not found in PostEco for instance '{inst}' — cross-channel hookup missing"
            )
```

---

## Summary — All Changes Per File

| File | Changes | Gaps |
|------|---------|------|
| `rtl_diff_analyzer.md` | Add `new_logic_gate_only` type + fields; `eco_naming_style`; `instance_scope` rule; `cross_channel` port_connection; `applies_to_all_instances` | A, B, C, E |
| `eco_netlist_studier.md` | Phase 0a branch for gate-only; literal port naming; instance-scope per-module editing | A, C, E |
| `eco_fenets_derive_queries.py` | Add Cat 9 (gate_only leaves); Cat 10 (cross_channel hookup) | A, B |
| `eco_passes_2_4.py` | `apply_cone_replacement()`; `apply_consumer_rewire()`; `apply_single_instance_port()` for cross-channel; `find_module_body_by_instance()` | A, B, C, D |
| `eco_validate_step1.py` | `[GATE_ONLY_FIELDS]`; `[PORT_NAME_LITERAL]`; `[INSTANCE_SCOPE_PRESENT]` | A, C, E |
| `eco_validate_step3.py` | `[CONE_REPLACEMENT_ENTRIES]`; `[PORT_LITERAL_MATCH]`; `[ASYMMETRIC_INSTANCE_SCOPE]`; `[CROSS_CHANNEL_HOOKUP]` | A, B, C, E |
| `eco_validate_step4.py` | `[CONSUMER_REWIRE_APPLIED]` | D |
| `eco_pre_fm_check.py` | `[CONE_REPLACEMENT_COMPLETENESS]`; `[CROSS_CHANNEL_HOOKUP_APPLIED]` | A, B, D |

---

## Effort Estimate

| Gap | MD changes | Script changes | Total |
|-----|-----------|---------------|-------|
| GAP-E | 2 MDs (small) | 2 validators (small) | ~2h |
| GAP-A | 2 MDs (medium) | 4 scripts (medium-large) | ~6h |
| GAP-C | 2 MDs (small) | 3 scripts (medium) | ~3h |
| GAP-D | 0 MDs | 2 scripts (small) | ~1h |
| GAP-B | 1 MD (small) | 3 scripts (small-medium) | ~3h |
| **Total** | | | **~15h** |

---

## Testing Strategy

After implementing, validate against DEUMCIPRTL-9899 reference:

1. Run `eco_validate_step1.py` on hand-authored `9899_rtl_diff.json` → all new checks PASS
2. Run `eco_fenets_derive_queries.py` → verify Cat 9 + Cat 10 entries present; no Cat 2/3 for gate-only changes
3. Run `eco_netlist_studier` → verify `cone_replacement` entries for all 3 stages; no DFF anchor attempt
4. Run `eco_validate_step3.py` → `[CONE_REPLACEMENT_ENTRIES]`, `[CROSS_CHANNEL_HOOKUP]`, `[ASYMMETRIC_INSTANCE_SCOPE]` all PASS
5. Run `eco_passes_2_4.py` → zdiff PostEco shows correct cells in dcqarb_0/1 asymmetrically; consumer rewired
6. Run `eco_pre_fm_check.py` → `[CONE_REPLACEMENT_COMPLETENESS]`, `[CROSS_CHANNEL_HOOKUP_APPLIED]` PASS
7. Submit FM → expect PASS (9899 has no Mode S / bridge complexity)

---

## What Is NOT Changing

These existing capabilities are **sufficient as-is** for 9899:

- `eco_fenets_rename_map.py` — handles Cat 9/10 queries the same as Cat 1 (just adds more entries)
- `eco_fm_analyzer.md` — Mode S analysis simply finds nothing to do (no new DFFs) → correct behavior
- `ROUND_ORCHESTRATOR.md` — round handoff logic unchanged; same FM abort → next round flow
- `eco_validate_step2.py` — Cat 8 Mode-S anchor check: skipped naturally (no `potential_mode_s_targets` from Step 1 when no DFF)
- `eco_pre_fm_check.py` GAP-3/4 checks — no bridge plumbing in 9899, so `[NO_DEAD_BRIDGE_PLUMBING]` trivially passes
