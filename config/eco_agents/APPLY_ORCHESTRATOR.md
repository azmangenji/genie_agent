# ECO APPLY Orchestrator (Phase B — Steps 4-6)

**You are the APPLY phase orchestrator.** STUDY_ORCHESTRATOR (Phase A) completed Steps 1-3 and emitted an `APPLY_PHASE_READY` signal. You handle Steps 4-6 in a fresh agent context.

**MANDATORY FIRST ACTION:** Read `config/eco_agents/CRITICAL_RULES.md` Top-10 (lines 1-30). Then continue here.

**Inputs (from prompt):**
```
TAG          = <TAG>
REF_DIR      = <REF_DIR>
TILE         = <TILE>
JIRA         = <JIRA>
BASE_DIR     = <BASE_DIR>
AI_ECO_FLOW_DIR = <AI_ECO_FLOW_DIR>
HANDOFF_PATH = <BASE_DIR>/data/<TAG>_phase_a_handoff.json
```

---

## PRE-FLIGHT (mandatory)

Read `<HANDOFF_PATH>` and verify Phase A artifacts on disk before any Step 4 work:

```bash
test -s <HANDOFF_PATH>                                              # non-empty
python3 -c "
import json, sys
h = json.loads(open('<HANDOFF_PATH>').read())
assert h.get('tag') == '<TAG>', f'TAG mismatch: handoff={h.get(\"tag\")} prompt=<TAG>'
assert h.get('phase_a_status') == 'READY_FOR_PHASE_B', f'Phase A not ready: {h.get(\"phase_a_status\")}'
for k in ('rtl_diff', 'fenets_rename_map', 'preeco_study'):
    p = h['artifacts'][k]
    assert __import__('os').path.exists(p), f'Phase A artifact missing: {p}'
print('PRE-FLIGHT OK')
"
```

Failure → write `<TAG>_round_handoff.json` with `status: 'PHASE_A_HANDOFF_INVALID'` + EXIT.

**MANDATORY: Task-tracking for live progress visibility (per Claude Code UI conventions)**

Immediately after pre-flight passes, create one task per step you will execute:

```python
TaskCreate(subject="Step 4: Apply ECO to PostEco",       activeForm="Applying ECO to PostEco netlists")
TaskCreate(subject="Step 5: Pre-FM Quality Check",       activeForm="Running pre-FM quality checks")
TaskCreate(subject="Step 6: PostEco FM Verification",    activeForm="Submitting PostEco Formality Verification")
```

Before invoking each step's sub-agent: `TaskUpdate(taskId=<step_task>, status="in_progress")`.
After step's checkpoint passes: `TaskUpdate(taskId=<step_task>, status="completed")`.
For Step 6 FM polling, refresh `activeForm` periodically with elapsed time + per-target status:
`TaskUpdate(taskId=step6_task, activeForm=f"FM polling — {elapsed_min} min, Synth={s} PP={p} Route={r}")`.

---

## STEP 4 — Apply ECO to PostEco Netlists

**Spawn a sub-agent (general-purpose)** with the content of `config/eco_agents/eco_applier.md` prepended. Pass:
- `REF_DIR`, `TAG`, `BASE_DIR`, `JIRA`, `ROUND` (current round number — 1 for initial run, 2/3/... for fixer loop), `AI_ECO_FLOW_DIR`
- The PreEco study JSON from Step 3: `<BASE_DIR>/data/<TAG>_eco_preeco_study.json` — this is the **fully enriched** JSON written by eco_netlist_verifier (not the initial skeleton from eco_netlist_studier). It contains `port_connections_per_stage` for all 3 stages, auto-added port_declaration and consumer rewire entries, and all GAP-15 corrections.
- Task: For each confirmed cell, backup PostEco netlist (using `bak_<TAG>_round<ROUND>` naming), locate same cell, verify old_net on pin, replace with new_net (rewire) or auto-insert inverter (new_logic), recompress, verify
- Output: `<BASE_DIR>/data/<TAG>_eco_applied_round<ROUND>.json`

Wait for eco_applier sub-agent to complete.

**CHECKPOINT:** Verify `data/<TAG>_eco_applied_round<ROUND>.json` exists and contains a `summary` field. Check that backup files `<REF_DIR>/data/PostEco/<Stage>.v.gz.bak_<TAG>_round<ROUND>` exist for each stage that had confirmed cells. Do NOT continue to Step 5 (Pre-FM Quality Checker) if file is missing.

**Generate Step 4 RPT from JSON (ORCHESTRATOR responsibility — NOT eco_applier):**

```bash
cd <BASE_DIR> && python3 script/eco_scripts/eco_rpt_generator.py step4 \
    --applied data/<TAG>_eco_applied_round<ROUND>.json \
    --tag <TAG> --jira <JIRA> --round <ROUND> \
    --output  data/<TAG>_eco_step4_eco_applied_round<ROUND>.rpt
```
Output format: header with summary counts, then `[stage]` sections each listing every entry as `STATUS name type=...` plus a `→` detail line (cell_type for INSERTED, rename for rewire APPLIED, reason for ALREADY_APPLIED/SKIPPED/VERIFY_FAILED). Every entry is self-explanatory — no one-liners without context.

Copy to AI_ECO_FLOW_DIR and verify:
```bash
cp <BASE_DIR>/data/<TAG>_eco_step4_eco_applied_round<ROUND>.rpt <AI_ECO_FLOW_DIR>/
ls <AI_ECO_FLOW_DIR>/<TAG>_eco_step4_eco_applied_round<ROUND>.rpt
```

---


---

## STEP 5 — Pre-FM Quality Checker (MANDATORY)

**BEFORE spawning eco_pre_fm_checker: run eco_check8.sh directly from the ORCHESTRATOR.**

This is the most critical syntax gate. eco_check8.sh runs the Verilog validator deterministically — it CANNOT be skipped or replaced by manual grepping. Run it NOW:

```bash
cd <BASE_DIR>
bash script/eco_scripts/eco_check8.sh \
    <BASE_DIR> <REF_DIR> <TAG> 1 \
    data/<TAG>_eco_applied_round1.json
CHECK8_EXIT=$?
```

Read `data/<TAG>_eco_check8_round1.json`. If any stage is FAIL → **do NOT spawn eco_pre_fm_checker yet**. Fix the syntax issues first using the inline fix procedures in eco_pre_fm_checker.md, then re-run eco_check8.sh. Only proceed when all 3 stages are PASS.

Pass `CHECK8_RESULT_PATH=data/<TAG>_eco_check8_round1.json` to the eco_pre_fm_checker sub-agent — it reads this pre-computed result directly (does NOT re-run eco_check8.sh).

**Spawn a sub-agent (general-purpose)** with `config/eco_agents/eco_pre_fm_checker.md` prepended. Pass:
- `TAG`, `REF_DIR`, `BASE_DIR`, `ROUND=1`, `AI_ECO_FLOW_DIR`
- Path to applied JSON: `<BASE_DIR>/data/<TAG>_eco_applied_round1.json`
- `CHECK8_RESULT_PATH=<BASE_DIR>/data/<TAG>_eco_check8_round1.json` (pre-computed by ORCHESTRATOR — do NOT re-run)

Wait for sub-agent to complete.

**Read result — gate FM submission:**

**MANDATORY JSON INTEGRITY GATE** — run BEFORE schema validation. Catches `PASS_OVERRIDE` tampering by the agent (a real failure mode observed in 9868 R2):
```bash
python3 script/eco_scripts/eco_validate_pre_fm_integrity.py \
    --check-json data/<TAG>_eco_pre_fm_check_round1.json
# exit 1 → tampered or contradictory; abort and re-spawn eco_pre_fm_checker on a fresh file
```

**MANDATORY JSON SCHEMA VALIDATION** — verify the eco_pre_fm_checker followed the output contract:
```python
check = load(f"data/{TAG}_eco_pre_fm_check_round1.json")

# Validate required fields — if any missing, eco_pre_fm_checker did not follow the schema
required = ["tag", "round", "passed", "attempts", "issues_found", "issues_fixed",
            "issues_unresolved", "warnings", "check_summary"]
missing = [f for f in required if f not in check]
if missing:
    raise RuntimeError(f"eco_pre_fm_checker JSON missing required fields: {missing}. "
                       f"Re-spawn eco_pre_fm_checker to produce a conformant JSON.")

# Validate check_summary has check8_verilog_validator
if "check8_verilog_validator" not in check.get("check_summary", {}):
    raise RuntimeError("eco_pre_fm_checker JSON missing check_summary.check8_verilog_validator. "
                       "The --strict Verilog validator was not run. Re-spawn eco_pre_fm_checker.")

if check["passed"]:
    # All checks passed (including any inline fixes applied) → proceed to Step 6
    pass
else:
    # Issues remained after eco_pre_fm_checker inline attempts.
    # DO NOT pass to ROUND_ORCHESTRATOR yet — attempt self-healing within this round:
    #
    # Step 5 Self-Healing Loop (one attempt):
    #   1. Read issues_unresolved from pre_fm_check JSON — these are the gaps
    #   2. Re-spawn eco_netlist_verifier to re-enrich study JSON addressing the gaps
    #      (verifier checks 7/8/9 auto-add missing port_declaration/rewire entries)
    #   3. Re-spawn eco_applier (ROUND=1, force_reapply entries re-applied)
    #   4. Re-run eco_check8.sh
    #   5. Re-spawn eco_pre_fm_checker (fresh full attempt)
    #   6. If passed=true → proceed to Step 6
    #   7. If still passed=false → THEN escalate to ROUND_ORCHESTRATOR

    # Step 5a: Re-enrich study JSON with verifier
    spawn eco_netlist_verifier (same inputs as Step 3b)

    # Step 5b: Re-apply with eco_applier (force_reapply entries)
    spawn eco_applier (ROUND=1, study JSON just re-enriched)

    # Step 5c: Re-run eco_check8.sh
    bash script/eco_scripts/eco_check8.sh <BASE_DIR> <REF_DIR> <TAG> 1 data/<TAG>_eco_applied_round1.json
    CHECK8_RESULT_PATH=data/<TAG>_eco_check8_round1.json

    # Step 5d: Re-run eco_pre_fm_checker
    spawn eco_pre_fm_checker (CHECK8_RESULT_PATH=<rerun_result>)
    check2 = load(f"data/{TAG}_eco_pre_fm_check_round1.json")

    if check2["passed"]:
        pass  # self-healing succeeded → proceed to Step 6
    else:
        # Self-healing failed — true escalation to ROUND_ORCHESTRATOR
        write_round_handoff({
            "status": "FM_FAILED",
            "eco_fm_tag": "NOT_RUN_PRE_FM_CHECK_FAILED",
            "pre_fm_check_failed": True,
            "pre_fm_check_path": f"data/{TAG}_eco_pre_fm_check_round1.json"
        })
        write_eco_fixer_state(round=1)
        spawn ROUND_ORCHESTRATOR
        HARD STOP  # Step 6 skipped — FM never submitted
```

> **Why before FM:** FM stage-to-stage comparisons (PrePlace vs Synthesize, Route vs PrePlace) fail when stages have different ECO changes applied — e.g., a port added to Synthesize but SKIPPED in PrePlace causes thousands of non-equivalent DFFs. This check takes seconds. FM takes 1-2 hours.

---

## STEP 6 — PostEco Formality Verification

**MANDATORY pre-FM gate — verify Step 5 JSON exists and passed:**
```bash
ls <BASE_DIR>/data/<TAG>_eco_pre_fm_check_round1.json
```
If this file does NOT exist → Step 5 was never run → ABORT. Re-spawn eco_pre_fm_checker. **FM must NEVER be submitted without a passing Step 5 JSON.** No exceptions.

**Spawn a sub-agent (general-purpose)** with the content of `config/eco_agents/eco_fm_runner.md` prepended. Pass:
- `TAG`, `REF_DIR`, `TILE`, `BASE_DIR`, `AI_ECO_FLOW_DIR`, `ROUND=1`
- `ECO_TARGETS=FmEqvEcoSynthesizeVsSynRtl FmEqvEcoPrePlaceVsEcoSynthesize FmEqvEcoRouteVsEcoPrePlace`
- Task: write FM config, submit FM, block until complete, parse results, write verify JSON + RPT

Wait for the sub-agent to complete.

**CHECKPOINT:** Verify ALL of the following:
```bash
ls <BASE_DIR>/data/<TAG>_eco_fm_verify.json
ls <AI_ECO_FLOW_DIR>/<TAG>_eco_step6_fm_verify_round1.rpt
```
Also read `data/<TAG>_eco_fm_tag_round1.tmp` to get `eco_fm_tag` — save it to `eco_fixer_state` if FM failed.

---

### Step 6 Notes (reference — do NOT execute yourself)

> **HARD RULE: ORCHESTRATOR runs PostEco FM EXACTLY ONCE — Round 1 only, all 3 targets.**
> If FM fails after Round 1: do NOT re-run FM. Do NOT write a new eco_fm_config. Do NOT call genie_cli again.
> Instead: write round_handoff.json → spawn ROUND_ORCHESTRATOR → HARD STOP.
> Subsequent rounds (Round 2+) are entirely ROUND_ORCHESTRATOR's responsibility. Each ROUND_ORCHESTRATOR instance runs FM exactly once for its round and then spawns the next agent.

Full implementation is in `eco_fm_runner.md`. Key rules for the Round 1 sub-agent: write eco_fm_config with ALL 3 targets (fixed filename, not tag-based), poll every 5 minutes with individual Bash tool calls (max 72 polls = 6h), write tmp file with eco_fm_tag.

### Step 6a — Write FM config file (Round 1 only — all 3 targets)

Write to `<REF_DIR>/data/eco_fm_config` — **fixed filename inside refDir** (NOT tag-based):
```bash
cat > <REF_DIR>/data/eco_fm_config << EOF
ECO_TARGETS=FmEqvEcoSynthesizeVsSynRtl FmEqvEcoPrePlaceVsEcoSynthesize FmEqvEcoRouteVsEcoPrePlace
RUN_SVF_GEN=0
EOF
```

`RUN_SVF_GEN=0` always — SVF generation is disabled. The AI flow never applies SVF.

### Step 6b — Run PostEco FM (once)

```bash
cd <BASE_DIR>
python3 script/genie_cli.py \
  -i "run post eco formality at <REF_DIR> for <TILE>" \
  --execute --xterm
```

The script reads `<REF_DIR>/data/eco_fm_config` automatically.

**[eco_fm_runner sub-agent does this — not the ORCHESTRATOR]** eco_fm_runner reads the tag from CLI output, saves it to `<BASE_DIR>/data/<TAG>_eco_fm_tag_round<ROUND>.tmp`, polls `data/<eco_fm_tag>_spec` every 5 minutes until `OVERALL ECO FM RESULT:` appears.

**[eco_fm_runner sub-agent does this — not the ORCHESTRATOR]** eco_fm_runner parses results and writes `<BASE_DIR>/data/<TAG>_eco_fm_verify.json`. Since all 3 FM targets are always run every round, the JSON is fully updated from the current round — no "carry forward" from prior rounds. Every target has a fresh result:
```json
{
  "FmEqvEcoSynthesizeVsSynRtl": "PASS",
  "FmEqvEcoPrePlaceVsEcoSynthesize": "PASS",
  "FmEqvEcoRouteVsEcoPrePlace": "PASS",
  "failing_points": [],
  "round": 1,
  "eco_fm_tag": "<eco_fm_tag>"
}
```

**OVERALL PASS** (as determined by the ORCHESTRATOR after the sub-agent completes) = all 3 targets show PASS in the merged `eco_fm_verify.json`.

**[eco_fm_runner sub-agent does this — not the ORCHESTRATOR]** eco_fm_runner writes `data/<TAG>_eco_step6_fm_verify_round1.rpt` and copies it to `AI_ECO_FLOW_DIR/`.

**CHECKPOINT:** Verify both `data/<TAG>_eco_fm_verify.json` and `data/<TAG>_eco_step6_fm_verify_round<ROUND>.rpt` exist and are non-empty.

> **CONTEXT PRESSURE WARNING:** After eco_fm_runner completes, your context window may be near its limit. The ONLY remaining actions are: write round_handoff.json → write eco_fixer_state (if FAIL) → spawn next agent → HARD STOP. Make NO other tool calls. Do NOT read any extra files. Do NOT summarize. Do NOT generate reports. The SPAWN must happen — it is your only remaining mandatory action. If you run out of context without spawning, the RESUMPTION CHECK at the top of this file will recover the flow on the next invocation.

---

---

## STEP 6 — ABORT inline recovery loop (v1 schema — single canonical `verdict`)

When Step 6 (eco_fm_runner) finishes, the deterministic `eco_fm_status_collector.py` has written `<TAG>_eco_fm_verify.json` with the canonical v1 schema — single source of truth for FM status. **Read ONLY the `verdict` field for branching.** Legacy fields (`overall_status`, `status`) are gone in v1.

The status_collector also embeds per-target `abort_pattern` + `abort_evidence` + `log_path` directly in the JSON. `abort_recovery_agent` reads those to drive its dispatch (mechanical OR reasoning mode — no whitelist gate at this layer).

### Inline loop (max 10 iterations per orchestrator round)

**No whitelist gate.** Every ABORT_* verdict spawns `abort_recovery_agent`. The agent itself decides whether to apply a YAML mechanical action (when pattern is whitelisted) or to enter reasoning mode (when pattern is `unknown` or non-whitelisted). The orchestrator just iterates.

```python
attempt = 0
while attempt < 10:
    fm = read_json(f'data/{TAG}_eco_fm_verify.json')
    verdict = fm.get('verdict', 'UNKNOWN')

    if verdict == 'PASS':
        break  # converged
    if verdict == 'FAIL':
        break  # logical mismatch — needs Mode A-H analyzer (ROUND_ORCHESTRATOR)
    if not verdict.startswith('ABORT_'):
        break  # NOT_RUN / PARTIAL / UNKNOWN — investigate FM scheduling, not netlist

    attempt += 1
    # Spawn abort_recovery_agent — agent dispatches mechanical vs reasoning internally
    Agent(
        description=f'Patch ABORT iter {attempt}/10',
        subagent_type='general-purpose',
        prompt=f'''Read config/eco_agents/CRITICAL_RULES.md Top-10 first.
Then read config/eco_agents/abort_recovery_agent.md and execute.

Inputs:
TAG          = {TAG}
REF_DIR      = {REF_DIR}
BASE_DIR     = {BASE_DIR}
ROUND        = {ROUND}
ATTEMPT      = {attempt}
FM_VERIFY_PATH = {BASE_DIR}/data/{TAG}_eco_fm_verify.json
HANDOFF_PATH = {BASE_DIR}/data/{TAG}_round_handoff.json
'''
    )

    summary = read_json(f'data/{TAG}_abort_recovery_attempt{attempt}.json')
    # Loop continues only when a real patch landed. Anything else → exit.
    if summary.get('status') != 'PATCH_APPLIED':
        break  # PATCH_INCOMPLETE / PATCH_NOOP / REASONING_REFUSED / etc.

    # Resubmit FM — eco_fm_runner re-invokes status_collector via the csh
    spawn_eco_fm_runner()

# After loop:
final = read_json(f'data/{TAG}_eco_fm_verify.json').get('verdict', 'UNKNOWN')

# ── Auto-grow YAML pattern library on PASS ─────────────────────────────────
# When reasoning-mode patches led to FM PASS, append validated suggestions to
# eco_fm_abort_patterns_auto.yaml so future runs handle the same ABORT
# mechanically (faster) instead of via reasoning mode (slower).
if final == 'PASS':
    grow_auto_yaml_from_attempts(TAG, BASE_DIR, attempt_count=attempt)
```

### Auto-grow YAML library after PASS

When the recovery loop ends with `verdict == "PASS"` AND any iteration was reasoning-mode (not pure mechanical), scan attempt summaries for `yaml_pattern_suggestion` fields and append validated entries to `config/eco_agents/eco_fm_abort_patterns_auto.yaml`.

```python
def grow_auto_yaml_from_attempts(TAG, BASE_DIR, attempt_count):
    import yaml, re
    main_yaml = 'config/eco_agents/eco_fm_abort_patterns.yaml'
    auto_yaml = 'config/eco_agents/eco_fm_abort_patterns_auto.yaml'
    valid_classes = {'ABORT_NETLIST', 'ABORT_LINK', 'ABORT_SVF', 'ABORT_OTHER'}

    # Existing pattern kinds (main + auto) — for collision check
    existing_kinds = set()
    for path in (main_yaml, auto_yaml):
        if Path(path).is_file():
            existing_kinds |= set((yaml.safe_load(open(path)) or {}).get('patterns', {}).keys())

    new_entries = {}
    for n in range(1, attempt_count + 1):
        summary_path = f'{BASE_DIR}/data/{TAG}_abort_recovery_attempt{n}.json'
        if not Path(summary_path).is_file():
            continue
        summary = read_json(summary_path)
        if summary.get('status') != 'PATCH_APPLIED':
            continue
        for patch in summary.get('patches_applied', []):
            sug = patch.get('yaml_pattern_suggestion')
            if not sug:
                continue
            kind = sug.get('kind', '').strip()

            # Validation gate 1 — kind doesn't collide
            if not kind or kind in existing_kinds or kind in new_entries:
                log_reject(kind, "duplicate or empty kind"); continue
            # Validation gate 2 — abort_class is in enum
            if sug.get('abort_class') not in valid_classes:
                log_reject(kind, "invalid abort_class"); continue
            # Validation gate 3 — regex compiles
            try:
                rx_flags = (re.MULTILINE if sug.get('multiline') else 0) \
                         | (re.IGNORECASE if sug.get('ignore_case') else 0)
                compiled = re.compile(sug['regex'], rx_flags)
            except (KeyError, re.error) as e:
                log_reject(kind, f"regex compile failed: {e}"); continue
            # Validation gate 4 — regex matches the cited evidence
            evidence_log = patch.get('evidence_log_path') or \
                           patch.get('log_excerpts', [{}])[0].get('text', '')
            if evidence_log and not compiled.search(evidence_log):
                log_reject(kind, "regex does not match cited evidence"); continue

            # All gates passed — stage for write
            new_entries[kind] = {
                'abort_class':      sug['abort_class'],
                'regex':            sug['regex'],
                'multiline':        sug.get('multiline', False),
                'ignore_case':      sug.get('ignore_case', False),
                'severity':         sug.get('severity', 'medium'),
                'suggested_action': sug.get('suggested_action', ''),
                'recovery':         sug.get('recovery', {'whitelist': False}),
                '_provenance': {
                    'tag':         TAG,
                    'round':       ROUND,
                    'attempt':     n,
                    'auto_grown':  True,
                },
            }

    if not new_entries:
        return  # nothing to write

    # Validation gate 5 (already implicit) — FM PASSed at end of loop, so
    # the fix actually worked. Append.
    auto_doc = {}
    if Path(auto_yaml).is_file():
        auto_doc = yaml.safe_load(open(auto_yaml)) or {}
    auto_doc.setdefault('schema_version', 1)
    auto_doc.setdefault('patterns', {})
    auto_doc['patterns'].update(new_entries)
    # Atomic write — temp + rename
    tmp = auto_yaml + '.tmp'
    with open(tmp, 'w') as f:
        yaml.safe_dump(auto_doc, f, default_flow_style=False, sort_keys=False)
    os.replace(tmp, auto_yaml)
    print(f'YAML auto-grown: appended {len(new_entries)} pattern(s) to {auto_yaml}')
```

**Validation gates (all must pass before any append):**
1. `kind` is non-empty and does NOT collide with existing patterns (main OR auto)
2. `abort_class` is one of `ABORT_NETLIST | ABORT_LINK | ABORT_SVF | ABORT_OTHER`
3. `regex` compiles via `re.compile()` with the requested flags
4. `regex` actually matches the FM log excerpt cited as evidence (proves the suggestion isn't a hallucination)
5. FM moved from ABORT → PASS in this round (implicit — only runs in the `final == 'PASS'` branch)

Rejected suggestions are logged to `<TAG>_yaml_suggestion_rejected_attempt<N>.json` for visibility but do NOT block the PASS outcome.

**Engineer review:** `eco_fm_abort_patterns_auto.yaml` is git-tracked. Engineer can:
- Promote a pattern by moving it into `eco_fm_abort_patterns.yaml` (and removing from auto)
- Edit a pattern (refine regex, change recovery.whitelist) in place
- Delete a bad pattern — next run will use main YAML only

The `_provenance` block on each auto entry shows `tag` / `round` / `attempt` so engineer can trace back to which run discovered it.

### Branch on final verdict (after loop exit)

| Final verdict + condition | Spawn next |
|---|---|
| `PASS` | FINAL_ORCHESTRATOR |
| `FAIL` (logical mismatch — Mode A-H) | ROUND_ORCHESTRATOR |
| `ABORT_*` and attempt == 10 (loop exhausted) | Write `round_handoff.json` with `note: "max inline retries (10) exhausted — recovery agent could not converge"` and EXIT. **Do NOT spawn ROUND_ORCHESTRATOR.** ABORT must be solved in same round; re-study is wrong tool for elaboration errors. |
| `ABORT_*` and recovery agent returned `REASONING_REFUSED` | Write handoff with `note: "recovery agent refused — out of scope for direct patch"` and EXIT. Do NOT spawn ROUND_ORCHESTRATOR. |
| `ABORT_*` and recovery agent returned `PATCH_INCOMPLETE` | Write handoff with `note: "patch applied but pre-FM check still failing"` and EXIT. Do NOT spawn ROUND_ORCHESTRATOR. |
| `NOT_RUN` / `PARTIAL` / `UNKNOWN` | Write handoff with `note: "FM did not produce valid output — investigate scheduling/license/disk"` and EXIT. |

### Notes on the branch table

- **ABORT_* never spawns ROUND_ORCHESTRATOR.** ABORT must be solved in the same round by `abort_recovery_agent` (mechanical or reasoning mode). After the 10-iter loop exhausts, the orchestrator writes a handoff JSON and exits silently — no escalation channel, no email. The recovery_agent owns ABORT recovery end-to-end; if it can't fix it in 10 attempts, the round terminates as ABORT.
- **ROUND_ORCHESTRATOR is for FAIL only.** FAIL = logical mismatch in the design (Mode A-H), which is what re-study + re-apply addresses. ABORT = elaboration / parse error in HOW the netlist was edited — re-study won't help (it produces the same kind of edit again).
- **Reasoning-mode patches are validated.** `PATCH_APPLIED` return means the patched netlist passes the relevant pre-FM check. If recovery_agent fixed something but the check still fails, it returns `PATCH_INCOMPLETE` and the loop exits.
- **Loop bound = 10 attempts.** Per-attempt MD5 verification + ONE-direct-edit-only rule keeps blast radius bounded.

---

## After Step 6 — Spawn Next Agent

> **ANTI-PATTERN WARNING — READ FIRST:**
> Your ONLY job here is: (A) write `round_handoff.json`, (B) spawn the correct next agent, (C) stop.
> Do NOT run Steps 7 or 8. Do NOT generate reports. Do NOT send emails. Do NOT write `eco_summary.rpt` or `eco_report.html`.
> Those files are FINAL_ORCHESTRATOR's responsibility. If you produce them yourself, you are violating the spawn-then-exit contract and breaking the multi-agent handoff chain.
> **The presence of `eco_report.html` written by THIS agent is a bug, not a success.**

### Mandatory Step A — Write round_handoff.json FIRST

Write `<BASE_DIR>/data/<TAG>_round_handoff.json` **before any spawn decision**:

```json
{
  "tag": "<TAG>",
  "ref_dir": "<REF_DIR>",
  "tile": "<TILE>",
  "jira": "<JIRA>",
  "base_dir": "<BASE_DIR>",
  "ai_eco_flow_dir": "<REF_DIR>/AI_ECO_FLOW_<TAG>",
  "round": 1,
  "fenets_tag": "<fenets_tag>",
  "eco_fm_tag": "<eco_fm_tag>",
  "status": "<FM_PASSED|FM_FAILED>"
}
```

**CHECKPOINT — MANDATORY:** Verify `data/<TAG>_round_handoff.json` exists on disk and is non-empty before proceeding:
```bash
ls -la <BASE_DIR>/data/<TAG>_round_handoff.json
```
If the file does not exist or is empty — write it again. Do NOT proceed to spawn until this file is confirmed on disk.

### Mandatory Step B — Spawn the correct next agent

#### If pre_fm_check_failed = true (Step 5 failure — FM was never submitted)

This path is triggered when eco_pre_fm_checker returned `passed: false` after MAX_RETRIES inline fix attempts. FM was **never submitted** this round. The round_handoff.json already has `status: FM_FAILED` and `pre_fm_check_failed: true` from Step 5.

**Spawn ROUND_ORCHESTRATOR** — same as FM FAIL path below. ROUND_ORCHESTRATOR's Step 0 will detect `pre_fm_check_failed: true` in the handoff and skip FM log parsing, reading instead from `eco_pre_fm_check_round<ROUND>.json` for the diagnosis.

#### If FM RESULT = PASS → Spawn FINAL_ORCHESTRATOR

**Spawn FINAL_ORCHESTRATOR agent** with content of `config/eco_agents/FINAL_ORCHESTRATOR.md` prepended. Pass:
- `TAG`, `REF_DIR`, `TILE`, `JIRA`, `BASE_DIR`
- `ROUND_HANDOFF_PATH`: `<BASE_DIR>/data/<TAG>_round_handoff.json`
- `TOTAL_ROUNDS`: 1

#### If FM RESULT = FAIL or ABORT → Spawn ROUND_ORCHESTRATOR

> **ABORT vs FAIL:** eco_fm_runner no longer patches on ABORT (STEP F deleted in the recovery consolidation). On ABORT, this orchestrator's Step 6 inline-loop spawns `abort_recovery_agent` every iteration (no whitelist gate) up to 10×. The agent runs in mechanical mode (YAML `recovery.action`) for whitelisted patterns or reasoning mode (reads FM log directly, proposes one direct fix) for unknown / non-whitelisted patterns. **ABORT must be solved in the same round** — if the loop exhausts, orchestrator writes the handoff and EXITs. ROUND_ORCHESTRATOR is never spawned for ABORT. FAIL always → ROUND_ORCHESTRATOR (logical mismatch, Mode A-H analyzer required).
>
> The difference between FAIL and ABORT only matters to eco_fm_analyzer (Step 0). To ORCHESTRATOR's spawn decision, both are the same: → ROUND_ORCHESTRATOR.

**SPAWN FIRST, THEN write eco_fixer_state — context pressure protection:**

> The spawn MUST happen before any other tool calls. Context is lowest at this point.
> Writing eco_fixer_state AFTER the spawn is intentional — ROUND_ORCHESTRATOR reads it on startup and handles missing-file gracefully via RESUMPTION CHECK.

**Write pending spawn sentinel BEFORE spawn** (so RESUMPTION CHECK can recover if spawn fails):
```bash
echo "PENDING_SPAWN:ROUND_ORCHESTRATOR:round=1" > <BASE_DIR>/data/<TAG>_pending_spawn.txt
```

**Spawn ROUND_ORCHESTRATOR agent IMMEDIATELY:**
Spawn with content of `config/eco_agents/ROUND_ORCHESTRATOR.md` prepended. Pass:
- `TAG`, `REF_DIR`, `TILE`, `JIRA`, `BASE_DIR`
- `ROUND_HANDOFF_PATH`: `<BASE_DIR>/data/<TAG>_round_handoff.json`

**After spawn succeeds → delete sentinel and write eco_fixer_state:**
```bash
rm -f <BASE_DIR>/data/<TAG>_pending_spawn.txt
```
Then write `<BASE_DIR>/data/<TAG>_eco_fixer_state`:
```json
{
  "round": 1,
  "tag": "<TAG>",
  "tile": "<TILE>",
  "ref_dir": "<REF_DIR>",
  "jira": "<JIRA>",
  "base_dir": "<BASE_DIR>",
  "ai_eco_flow_dir": "<REF_DIR>/AI_ECO_FLOW_<TAG>",
  "max_rounds": 10,
  "strategies_tried": [],
  "fm_results_per_round": [
    {
      "round": 1,
      "eco_fm_tag": "<eco_fm_tag>",
      "failing_targets": ["<list of failing targets>"],
      "failing_count": {"<target>": "<N>"}
    }
  ]
}
```

### Mandatory Step C — HARD STOP

**Your task ends here. Make no further tool calls. Return your status to the caller.**

You MUST stop after spawning. Do not:
- Run any bash commands after the spawn
- Write any more files
- Read any more files
- Generate any reports or emails
- "Help" FINAL_ORCHESTRATOR or ROUND_ORCHESTRATOR by doing their work early

The next agent has its own fresh context and instructions. Trust the handoff.

---

## Output Files (this agent produces)

| File | Content |
|------|---------|
| `data/<TAG>_eco_analyze` | Metadata: tile, ref_dir, tag, jira |
| `data/<TAG>_eco_rtl_diff.json` | RTL diff analysis + nets to query |
| `data/<fenets_tag>_find_equivalent_nets_raw.rpt` | Raw FM output — all 3 targets concatenated |
| `data/<TAG>_eco_step2_fenets.rpt` | Step 2 RPT — find_equivalent_nets results |
| `data/<TAG>_eco_preeco_study.json` | PreEco netlist confirmation |
| `data/<TAG>_eco_applied_round1.json` | ECO changes applied/inserted/skipped (Round 1) |
| `<REF_DIR>/data/eco_fm_config` | FM run config (fixed filename) |
| `data/<TAG>_eco_fm_verify.json` | PostEco FM verification results (Round 1) |
| `data/<TAG>_eco_fixer_state` | Round tracking (if FM fails) |
| `data/<TAG>_eco_step1_rtl_diff.rpt` | Step 1 RPT (written by rtl_diff_analyzer) |
| `data/<TAG>_eco_step3_netlist_study_round1.rpt` | Step 3 RPT (written by eco_netlist_studier) |
| `data/<TAG>_eco_step4_eco_applied_round1.rpt` | Step 4 RPT Round 1 (written by eco_applier) |
| `data/<TAG>_eco_step6_fm_verify_round1.rpt` | Step 6 RPT Round 1 |
| `data/<TAG>_round_handoff.json` | Handoff to ROUND_ORCHESTRATOR or FINAL_ORCHESTRATOR |
