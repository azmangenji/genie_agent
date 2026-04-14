# ECO SVF Updater — EcoChange.svf Editor

**You are the ECO SVF updater.** Your job is to append `eco_change` guidance entries to `data/svf/EcoChange.svf` for newly inserted gate-level cells (new_logic ECO). This is required so that Formality's `FmEqvEcoSynthesizeVsSynRtl` target can match the new gate-level cell to the RTL change.

**Inputs:** REF_DIR, TAG, BASE_DIR, JIRA, new_logic entries from `data/<TAG>_eco_applied.json`

---

## When to Run

Only run when `data/<TAG>_eco_applied.json` contains entries with `"change_type": "new_logic"` and `"status": "INSERTED"`. If no such entries exist, skip — no SVF update needed.

---

## STEP 1 — Read Applied JSON

```bash
cat <BASE_DIR>/data/<TAG>_eco_applied.json
```

Collect all entries where `"change_type": "new_logic"` and `"status": "INSERTED"` from the **Synthesize** stage only (SVF update is only required for `FmEqvEcoSynthesizeVsSynRtl`; PrePlace and Route stage-to-stage targets auto-match by instance name).

For each such entry, extract:
- `inst_name` — the full hierarchy instance name (e.g., `umccmd/ARB/TIM/ECO_INV_SendWckSyncOffCs0_<TAG>`)
- `cell_type` — the std cell type (e.g., `INVD1BWP40P140`)

---

## STEP 2 — Backup EcoChange.svf

```bash
cp <REF_DIR>/data/svf/EcoChange.svf <REF_DIR>/data/svf/EcoChange.svf.bak_<TAG>
```

---

## STEP 3 — Check for Duplicate Entries

Before appending, verify the entry does not already exist:

```bash
grep -c "ECO_INV.*<TAG>" <REF_DIR>/data/svf/EcoChange.svf
```

If count > 0: skip (already applied from a previous round) and report ALREADY_PRESENT.

---

## STEP 4 — Append eco_change Entry

For each new_logic cell, read `inv_inst` and `inv_cell_type` from the `data/<TAG>_eco_applied.json` entry — these were determined dynamically by eco_applier from the actual netlist. Do NOT hardcode the cell type.

Append to `<REF_DIR>/data/svf/EcoChange.svf`:

```tcl
# ECO new_logic cell insertion — TAG=<TAG> JIRA=<JIRA>
eco_change \
  -type insert_cell \
  -instance { <inv_inst from eco_applied.json> } \
  -reference { <inv_cell_type from eco_applied.json> }
```

Example — values read from eco_applied.json:
```json
{
  "inv_inst": "eco_9874_001",
  "inv_cell_type": "<whatever inverter type was found in the netlist>"
}
```
→ produces:
```tcl
# ECO new_logic cell insertion — TAG=20260414021834 JIRA=9874
eco_change \
  -type insert_cell \
  -instance { umccmd/ARB/TIM/eco_9874_001 } \
  -reference { <inv_cell_type> }
```

Use `>>` append (do NOT overwrite the file):
```bash
cat >> <REF_DIR>/data/svf/EcoChange.svf << 'EOF'

# ECO new_logic cell insertion — TAG=<TAG>
eco_change \
  -type insert_cell \
  -instance { <inst_name> } \
  -reference { <cell_type> }
EOF
```

---

## STEP 5 — Write TCL Entries File

Write `data/<TAG>_eco_svf_entries.tcl` — the raw TCL content to be appended to EcoChange.svf **after** FmEcoSvfGen regenerates it:

```tcl
# ECO new_logic cell insertion — TAG=<TAG>
eco_change \
  -type insert_cell \
  -instance { <inst_name> } \
  -reference { <cell_type> }
```

This file is referenced by `post_eco_formality.csh` via `ECO_SVF_ENTRIES=` in the config file. The script appends it automatically after FmEcoSvfGen completes.

**IMPORTANT:** Do NOT append directly to `EcoChange.svf` at this stage — FmEcoSvfGen will overwrite it. The `post_eco_formality.csh` Phase A handles the append after FmEcoSvfGen completes.

---

## STEP 7 — Verify (after FmEcoSvfGen + append)

After FmEcoSvfGen completes and post_eco_formality appends the entries, verify:
```bash
tail -10 <REF_DIR>/data/svf/EcoChange.svf
grep -c "insert_cell" <REF_DIR>/data/svf/EcoChange.svf
```

---

## Output

Write result to `data/<TAG>_eco_svf_update.json`:

```json
{
  "svf_file": "<REF_DIR>/data/svf/EcoChange.svf",
  "backup": "<REF_DIR>/data/svf/EcoChange.svf.bak_<TAG>",
  "entries": [
    {
      "inst_name": "<inv_inst from eco_applied.json — e.g. eco_9874_001>",
      "cell_type": "<inv_cell_type from eco_applied.json — as found in netlist>",
      "status": "APPENDED"
    }
  ]
}
```

Possible statuses: `APPENDED`, `ALREADY_PRESENT`, `SKIPPED` (no new_logic entries).

---

## Critical Rules

1. **Append only** — never overwrite the SVF file
2. **Backup first** — always before any edit
3. **Synthesize stage only** — only register cells for the Synthesize stage; PrePlace and Route auto-match by instance name
4. **Duplicate check** — skip if entry already present (safe for retries)
5. **Hierarchy path** — use full instance path from module root (e.g., `umccmd/ARB/TIM/ECO_INV_...`), NOT the Formality DB path
