---
paths:
  - "config/eco_agents/**"
  - "data/*_eco_*.json"
  - "data/*_round_handoff.json"
  - "data/*_phase_a_handoff.json"
  - "script/eco_scripts/**"
---

# ECO Analyze Mode - AI Auto-ECO Flow

## Overview

The ECO (Engineering Change Order) Analyze Mode runs AMD's AI Auto-ECO flow on a JIRA ECO ticket against a built tree. The flow performs gate-level netlist edits validated by Synopsys Formality (FM).

**Trigger phrases:**
- `"analyze eco at <refdir> for <tile>"`
- `"run eco analysis at <refdir> for <tile>"`

**Requires:** `JIRA=DEUMCIPRTL-NNNN` is parsed from the refdir path; the tile (e.g., `umccmd`, `umcdat`) is extracted from arguments.

## Flow Architecture - Two-Phase Split

The ECO flow runs across **two short-lived orchestrator agents** plus optional retry/finalize agents. The split exists to keep each agent's context well below the limit (3+ hour FM polling waits used to exhaust a single monolithic agent).

```
ECO_ANALYZE_MODE_ENABLED  ────────────────►  STUDY_ORCHESTRATOR  (Phase A: Steps 1-3)
                                                  │
                                                  ▼
                                             writes <TAG>_phase_a_handoff.json
                                             emits APPLY_PHASE_READY signal
                                             HARD STOP
                                                  │
APPLY_PHASE_READY  ───────────────────────►  APPLY_ORCHESTRATOR  (Phase B: Steps 4-6)
                                                  │
                              ┌───────────────────┼───────────────────┐
                              ▼                   ▼                   ▼
                         FM PASS              FM FAIL          ABORT (whitelisted)
                              │                   │                   │
                              ▼                   ▼                   ▼
                    FINAL_ORCHESTRATOR  ROUND_ORCHESTRATOR    abort_recovery_agent
                                                              (inline, max 10 iter)
```

## Step Map

| Step | Phase | Owner Sub-agent | Purpose |
|------|-------|-----------------|---------|
| 1 | A — STUDY | `rtl_diff_analyzer.md` | Parse RTL diff, classify ECO categories (1-9), pick siblings + scan anchors |
| 2 | A — STUDY | `eco_fenets_runner.md` | Submit Synopsys `find_equivalent_nets` queries, build PreEco→PostEco rename map |
| 3 | A — STUDY | `eco_netlist_studier.md` | Study PreEco gate-level netlist, emit `<TAG>_eco_preeco_study.json` |
| 4 | B — APPLY | `eco_applier.md` | Apply ECO edits to Synthesize/PrePlace/Route PostEco netlists |
| 5 | B — APPLY | `eco_pre_fm_checker.md` | Run 25+ pre-FM quality checks before submitting Formality |
| 6 | B — APPLY | `eco_fm_runner.md` | Submit FM (3 verification targets), poll until done |

## Signal Format

### Phase A trigger (from genie_cli.py)

```
ECO_ANALYZE_MODE_ENABLED
TAG=<tag>
REF_DIR=<ref_dir>
TILE=<tile>
JIRA=<jira>
LOG_FILE=<log_file>
SPEC_FILE=<spec_file>
```

### Phase B trigger (from STUDY_ORCHESTRATOR after Step 3)

```
APPLY_PHASE_READY
TAG=<tag>
REF_DIR=<ref_dir>
TILE=<tile>
JIRA=<jira>
HANDOFF_PATH=<BASE_DIR>/data/<TAG>_phase_a_handoff.json
```

## Top-level Claude Responsibilities

When `ECO_ANALYZE_MODE_ENABLED` is detected:
1. Spawn ONE general-purpose agent reading `config/eco_agents/STUDY_ORCHESTRATOR.md`
2. Pass TAG, REF_DIR, TILE, JIRA, LOG_FILE, SPEC_FILE, BASE_DIR
3. When agent completes, say only: `"ECO Phase A complete."`

When `APPLY_PHASE_READY` is detected:
1. Spawn ONE general-purpose agent reading `config/eco_agents/APPLY_ORCHESTRATOR.md`
2. Pass TAG, REF_DIR, TILE, JIRA, HANDOFF_PATH
3. When agent completes, say only: `"ECO analysis complete. Email sent."`

**Never** run any ECO step yourself — the orchestrators own all step execution and sub-agent spawning.

**Critical:** The `STUDY_ORCHESTRATOR` MUST read `config/eco_agents/CRITICAL_RULES.md` Top-10 + Rules Index before any other action. Same for `APPLY_ORCHESTRATOR`.

## Agent MD Map

```
config/eco_agents/
├── CRITICAL_RULES.md              # Top-10 MUST KNOW + 39-rule index — read first
├── STUDY_ORCHESTRATOR.md          # Phase A coordinator (Steps 1-3)
├── APPLY_ORCHESTRATOR.md          # Phase B coordinator (Steps 4-6)
├── ROUND_ORCHESTRATOR.md          # Re-study + retry on FM FAIL (rounds 2..N)
├── FINAL_ORCHESTRATOR.md          # Final reporting on FM PASS
├── abort_recovery_agent.md        # Inline mechanical patcher for whitelisted ABORTs
├── rtl_diff_analyzer.md           # Step 1
├── eco_fenets_runner.md           # Step 2
├── eco_netlist_studier.md         # Step 3
├── eco_netlist_re_studier.md      # Re-study on FM FAIL
├── eco_applier.md                 # Step 4
├── eco_pre_fm_checker.md          # Step 5
├── eco_fm_runner.md               # Step 6
├── eco_fm_analyzer.md             # Step 6d analyzer pipeline (post-FAIL)
├── eco_fm_pattern_library.md      # FM error pattern reference
├── eco_re_studier_evidence_contract.md
├── eco_netlist_verifier.md
└── eco_svf_updater.md
```

## ABORT Recovery Whitelist

When FM returns ABORT (elaboration error, NOT logical mismatch), `APPLY_ORCHESTRATOR` Step 6 spawns the lightweight `abort_recovery_agent` for **mechanical patches** that bypass the heavy ROUND_ORCHESTRATOR analyzer pipeline.

| primary_abort_type | pattern_kind | Patch action |
|---|---|---|
| `ABORT_LINK` | `cell_type_not_in_library` (FE-LINK-2) | sed wrong→correct cell type in study + 3 PostEco netlists (e.g. NOR3D1→NR3D1) |
| `ABORT_NETLIST` | `duplicate_wire_decl` (FM-599 SVR-9) | Delete duplicate `wire <name> ;` line |
| `ABORT_NETLIST` | `verilog_parse_error` | Often co-occurs with above; same fix |
| `ABORT_NETLIST` | `implicit_wire_conflict` | Delete explicit `wire X;` when `.PORT(X)` use precedes it |

**Loop logic:** Up to 10 inline iterations of `recovery_agent → resubmit FM`. Non-whitelisted patterns or 10-iteration cap → escalate to `ROUND_ORCHESTRATOR`.

**Time savings vs full pipeline:** ~30 min per ABORT cycle (skip evidence_walk + xstage_compare + analyzer + applier re-run).

## Key Artifacts (per-tag)

| Path | Producer | Consumer |
|---|---|---|
| `data/<TAG>_eco_rtl_diff.json` | Step 1 | Step 3, Step 4 |
| `data/<TAG>_eco_fenets_rename_map.json` | Step 2 | Step 3, Step 4 |
| `data/<TAG>_eco_preeco_study.json` | Step 3 | Step 4 |
| `data/<TAG>_phase_a_handoff.json` | STUDY_ORCHESTRATOR (post-Step 3) | APPLY_ORCHESTRATOR pre-flight |
| `data/<TAG>_eco_fm_verify.json` | Step 6 (post-FM) | APPLY_ORCHESTRATOR Step 6 branching |
| `data/<TAG>_eco_fm_abort_classification.json` | `eco_extract_fm_abort_cause.py` (auto, post-FM) | `abort_recovery_agent` |
| `data/<TAG>_round_handoff.json` | APPLY_ORCHESTRATOR | ROUND/FINAL_ORCHESTRATOR |

## Output Flow

| Content | Email | Conversation |
|---------|-------|--------------|
| Step-by-step progress (TaskCreate UI) | NO | YES (live) |
| FM verification results (PASS/FAIL/ABORT) | YES | NO |
| Round handoff JSON | NO | YES (one-line summary) |
| HTML analysis report | YES | NO |
| "ECO analysis complete. Email sent." | YES | YES |

## Live Progress (TaskCreate/TaskUpdate)

Both orchestrators MUST emit a TaskCreate per step at start and TaskUpdate when each step completes. This makes the long FM polling visible to the user as e.g.:

```
✽ Step 6: Submitting PostEco Formality Verification — 1h 7m,
  FM polling — Synth=PASS PP=PASS Route=RUNNING
```

instead of opaque `✽ ECO orchestrator running… (4h 12m)`.

## Common Failure Modes

| Symptom | Likely cause | Fix path |
|---|---|---|
| FM-036 Unknown name (Cat 8) | Picker emitted module-type instead of instance | Re-run `eco_pick_sibling.py` with `--tile-module` |
| FE-LINK-2 (cell type missing) | Studier used logical name (NOR3) not TSMC short (NR3) | Auto-fixed by `abort_recovery_agent` |
| FM-599 SVR-9 (duplicate wire) | Applier inserted duplicate `wire X;` | Auto-fixed by `abort_recovery_agent` (keep first decl) |
| FM logical mismatch (Mode A-H) | Real ECO bug; needs re-study | Escalates to `ROUND_ORCHESTRATOR` |

## SKIP_MONITORING Signal

When `SKIP_MONITORING=true` is in the signal (e.g., `--analyze-only` or analyze instructions), the upstream task already completed — go directly to spawning the orchestrator without monitoring.

## Reference Files

- **Detailed orchestration:** `config/eco_agents/STUDY_ORCHESTRATOR.md`, `APPLY_ORCHESTRATOR.md`
- **Hard rules (39):** `config/eco_agents/CRITICAL_RULES.md`
- **FM error patterns:** `config/eco_agents/eco_fm_pattern_library.md`
- **Project CLAUDE.md ECO section:** `.claude/CLAUDE.md` → "ECO Analyze Mode"
