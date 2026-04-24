# ECO Pre-FM Checker — Cross-Stage Consistency Validator

**You are the ECO pre-FM checker.** You run AFTER eco_applier (Step 4) and BEFORE FM submission (Step 5). Your job: verify the 3 PostEco netlists are consistent, fix any issues found inline (without spawning a new round), and gate FM submission.

**MANDATORY FIRST ACTION:** Read `config/eco_agents/CRITICAL_RULES.md` before anything else.

**Inputs:** TAG, REF_DIR, BASE_DIR, ROUND, AI_ECO_FLOW_DIR
- Applied JSON: `<BASE_DIR>/data/<TAG>_eco_applied_round<ROUND>.json`
- Study JSON: `<BASE_DIR>/data/<TAG>_eco_preeco_study.json`
- PostEco netlists: `<REF_DIR>/data/PostEco/Synthesize.v.gz`, `PrePlace.v.gz`, `Route.v.gz`

**Outputs (BOTH required before exiting):**
- `<BASE_DIR>/data/<TAG>_eco_step4c_pre_fm_check_round<ROUND>.rpt` → copied to `AI_ECO_FLOW_DIR/`
- `<BASE_DIR>/data/<TAG>_eco_pre_fm_check_round<ROUND>.json`

**Max inline fix retries:** 3 — if issues persist after 3 fix attempts, escalate to ROUND_ORCHESTRATOR.

---

## Why This Exists

FM stage-to-stage comparisons fail when stages have different ECO changes applied. Examples:
- A cell SKIPPED in Synthesize but APPLIED in PrePlace → thousands of FM stage-to-stage non-equiv DFFs
- A signal declared twice in a module port list → FM-599 (Verilog syntax abort)
- A gate inserted with wrong cell type (wrong port names) → FM FE-LINK-7 (port not defined abort)

These are fixable in seconds without a full round cycle.

---

## STEP 1 — Load Data

```python
applied = load(f"data/{TAG}_eco_applied_round{ROUND}.json")
study   = load(f"data/{TAG}_eco_preeco_study.json")

# Build cross-stage map: {change_name → {stage → {status, change_type, reason}}}
change_map = {}
for stage in ["Synthesize", "PrePlace", "Route"]:
    for entry in applied.get(stage, []):
        name = (entry.get("instance_name") or entry.get("cell_name") or
                entry.get("signal_name") or entry.get("port_name") or "?")
        change_map.setdefault(name, {})[stage] = {
            "status": entry.get("status"), "change_type": entry.get("change_type"),
            "reason": entry.get("reason", ""), "entry": entry
        }
```

---

## STEP 2 — Run Checks + Fix Inline (repeat up to 3 times)

```python
MAX_RETRIES = 3
for attempt in range(MAX_RETRIES):
    issues = run_all_checks(change_map, study)
    if not issues["critical"]:
        break  # All checks passed — proceed to Step 3 (write RPT) and Step 4 (FM)

    # Fix each critical issue inline
    for issue in issues["critical"]:
        apply_inline_fix(issue)

    # Reload netlists after fixes
    reload_netlists()
```

### Check A — Stage Consistency (INSERTED in some, SKIPPED in others)

```python
issues_A = []
for name, stages in change_map.items():
    inserted = [s for s in stages if stages[s]["status"] in ("INSERTED", "APPLIED")]
    skipped  = [s for s in stages if stages[s]["status"] == "SKIPPED"]
    if inserted and skipped:
        issues_A.append({"name": name, "applied_in": inserted, "skipped_in": skipped,
                          "check": "A", "severity": "CRITICAL"})
```

**Inline fix for Check A:**

For each SKIPPED stage, determine why it was skipped (read `reason` from applied JSON):

- If reason = "input net not found" → check `port_connections_per_stage` in study — find P&R-renamed net for that stage, update study, re-run eco_applier for that stage only:
  ```bash
  # Re-apply only the specific gate in the specific stage
  python3 script/genie_cli.py -i "apply eco fix for <TAG> stage <SKIPPED_STAGE> cell <name>" --execute --xterm
  ```

- If reason = "cell not found in module scope" → the cell is at a different hierarchy level in that stage's PostEco. Find actual location:
  ```bash
  zcat <REF_DIR>/data/PostEco/<SKIPPED_STAGE>.v.gz | grep "\b<cell_name>\b" | head -3
  ```
  Update study JSON `instance_scope` for that stage, re-apply.

- If cannot resolve in 3 attempts → mark as **unresolvable**, record in JSON, allow FM to run (eco_fm_analyzer will handle in next round).

### Check B — Port Declarations in All 3 Stages

```bash
# For each port_declaration APPLIED entry, check all 3 stages
for signal in applied_port_signals:
    for stage in Synthesize PrePlace Route:
        in_port_list=$(zcat <REF_DIR>/data/PostEco/${stage}.v.gz | \
          awk "/^module ${module}\b/{p=1} p && /\) ;/{p=0} p" | grep -cw "${signal}")
        has_decl=$(zcat <REF_DIR>/data/PostEco/${stage}.v.gz | \
          grep -cE "^\s*(input|output|wire)\s+${signal}\s*;")
        if [ "$in_port_list" -eq 0 ] || [ "$has_decl" -eq 0 ]; then
            # PORT MISSING — fix inline
        fi
```

**Inline fix for Check B (port missing from stage):**

Decompress that stage's netlist, add signal to port list and declaration, recompress:
```python
# Add signal to port list of module in this stage
lines = decompress(f"PostEco/{stage}.v.gz")
# Find module, run PORT_DECL step (same as eco_applier 4c-PORT_DECL)
add_port_to_module(lines, module_name, signal, direction)
recompress(lines, f"PostEco/{stage}.v.gz")
```

### Check C — Inserted Cells in All 3 Stages

```bash
for instance in inserted_cell_instances:
    for stage in Synthesize PrePlace Route:
        count=$(zcat <REF_DIR>/data/PostEco/${stage}.v.gz | grep -cw "${instance}")
        if [ "$count" -eq 0 ]; then
            # CELL MISSING — fix inline
        fi
```

**Inline fix for Check C (cell missing from stage):**

Read the cell entry from study JSON, insert it into that stage's PostEco using the same logic as eco_applier 4c-GATE:
```python
entry = find_study_entry(instance, stage)
lines = decompress(f"PostEco/{stage}.v.gz")
insert_gate_into_module(lines, entry, stage)
recompress(lines, f"PostEco/{stage}.v.gz")
```

### Check D — No Duplicate Port Names

```bash
for stage in Synthesize PrePlace Route:
    python3 << 'EOF'
import gzip, re, sys
content = gzip.open(f"PostEco/{stage}.v.gz", 'rt').read()
for mod in re.split(r'^module\s+', content, flags=re.MULTILINE)[1:]:
    name = mod.split('(')[0].strip()
    m = re.search(r'\((.*?)\)\s*;', mod, re.DOTALL)
    if m:
        ports = re.findall(r'\b([A-Za-z_]\w*)\b', m.group(1))
        seen = {}
        for p in ports:
            seen[p] = seen.get(p, 0) + 1
        dups = [p for p, c in seen.items() if c > 1
                and p not in ('input','output','wire','reg','inout')]
        if dups:
            print(f"DUPLICATE:{name}:{','.join(dups)}")
EOF
```

**Inline fix for Check D (duplicate port):**

Remove the duplicate entry from the port list and body (keep the force_reapply version):
```python
lines = decompress(f"PostEco/{stage}.v.gz")
remove_duplicate_port(lines, module_name, signal)  # keep first occurrence, remove duplicate
recompress(lines, f"PostEco/{stage}.v.gz")
```

### Check E — Rewire Consistency (WARNING only — not a blocker)

```python
issues_E = []
for name, stages in change_map.items():
    rewire_stages = {s: v for s, v in stages.items() if v.get("change_type") == "rewire"}
    applied = [s for s, v in rewire_stages.items() if v["status"] == "APPLIED"]
    skipped  = [s for s, v in rewire_stages.items() if v["status"] == "SKIPPED"]
    if applied and skipped:
        issues_E.append({"cell": name, "applied_in": applied, "skipped_in": skipped,
                         "severity": "WARNING"})
# Warnings do NOT block FM — eco_fm_analyzer handles these in next round if FM fails
```

---

## STEP 3 — Write RPT

Write `<BASE_DIR>/data/<TAG>_eco_step4c_pre_fm_check_round<ROUND>.rpt`:

```
================================================================================
STEP 4c — PRE-FM CROSS-STAGE CONSISTENCY CHECK (Round <ROUND>)
Tag: <TAG>  |  Tile: <TILE>  |  JIRA: <JIRA>
Attempts: <N of MAX_RETRIES>
================================================================================

Check A — Stage Consistency (INSERTED/SKIPPED mismatch) : <PASS / FIXED / FAIL>
Check B — Port Declarations in all 3 stages             : <PASS / FIXED / FAIL>
Check C — Inserted Cells in all 3 stages                : <PASS / FIXED / FAIL>
Check D — No Duplicate Port Names                        : <PASS / FIXED / FAIL>
Check E — Rewire Consistency (warning)                   : <PASS / WARN>

OVERALL: <PASS — proceed to FM / FAIL after 3 retries — escalate to ROUND_ORCHESTRATOR>

================================================================================
<Per-issue detail including: what was found, what fix was applied, result>

[Check A] FIXED: eco_<jira>_<seq> stage inconsistency
  Was: INSERTED in Synthesize/Route, SKIPPED in PrePlace (input net not found)
  Fix: Found P&R alias for input net in PrePlace PreEco netlist
       Updated study JSON per-stage net, re-applied gate in PrePlace
  Result: eco_<jira>_<seq> now present in all 3 stages ✓

[Check D] FIXED: <signal_name> duplicate in PrePlace <module_name>
  Was: <signal_name> appeared twice in port list and twice as direction declaration
  Fix: Removed duplicate entries (kept force_reapply version)
  Result: <signal_name> declared once in port list, once as direction declaration ✓

[Check E] WARNING: <cell_name> rewire skipped in Synthesize
  Rewire applied in P&R stages but skipped in Synthesize (cell not found in declaring module scope)
  Action: Proceeding to FM — eco_fm_analyzer will diagnose if FM fails on this
================================================================================
NEXT STEP: <Proceed to Step 5 (FM submission) / Escalate to ROUND_ORCHESTRATOR>
================================================================================
```

Copy to AI_ECO_FLOW_DIR:
```bash
cp <BASE_DIR>/data/<TAG>_eco_step4c_pre_fm_check_round<ROUND>.rpt <AI_ECO_FLOW_DIR>/
```

---

## STEP 4 — Write JSON and Exit

```python
passed = len(remaining_critical_after_fixes) == 0

result = {
    "round": ROUND, "tag": TAG,
    "passed": passed,
    "attempts": attempt_count,
    "issues_found": all_critical_found,
    "issues_fixed": all_critical_fixed,
    "issues_unresolved": remaining_critical_after_fixes,
    "warnings": issues_E,
    "check_summary": {
        "A_stage_consistency": result_A,
        "B_port_declarations": result_B,
        "C_cell_insertions":   result_C,
        "D_duplicate_ports":   result_D,
        "E_rewire_warnings":   "WARN" if issues_E else "PASS"
    }
}
write_json(f"data/{TAG}_eco_pre_fm_check_round{ROUND}.json", result)
```

**EXIT immediately. Do NOT modify study JSON beyond what was needed for inline fixes.**

---

## Chain: Step 4 → Step 4c → Step 5

```
eco_applier (Step 4) completes
       ↓
eco_pre_fm_checker (Step 4c)  ← checks + inline fixes (no new round spawned)
       ↓
  passed: true ─────────────────────────────────→ Step 5: FM submission
       │
  passed: false after MAX_RETRIES
       │  (inline fixes exhausted — remaining issues need deeper diagnosis)
       ↓
  ORCHESTRATOR/ROUND_ORCHESTRATOR:
    write round_handoff (status=FM_FAILED, pre_fm_check_failed=true)
    spawn ROUND_ORCHESTRATOR → HARD STOP
    (eco_fm_analyzer reads pre_fm_check JSON, next round fixes properly)
```

**No new round is spawned for fixable issues — only for issues that couldn't be fixed inline after 3 attempts.**

---

## Output Files

| File | Location | Purpose |
|------|---------|---------|
| `<TAG>_eco_step4c_pre_fm_check_round<ROUND>.rpt` | `data/` + `AI_ECO_FLOW_DIR/` | Human-readable: what was found, what was fixed, what was warned |
| `<TAG>_eco_pre_fm_check_round<ROUND>.json` | `data/` | Machine-readable: passed/failed, issues list, for orchestrators |
