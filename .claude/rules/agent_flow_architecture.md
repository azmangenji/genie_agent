---
paths:
  - "script/rtg_oss_feint/**"
  - "mail_centre/**"
  - "instruction.csv"
  - "keyword.csv"
  - "arguement.csv"
  - "patterns.csv"
---

# Agent Flow Architecture

## Two Operational Modes

| Mode | Location | Entry Point | Use Case |
|------|----------|-------------|----------|
| Email Flow | `mail_centre/` | `vtoHybridModel.py` | Remote access, automated |
| CLI Flow | `main_agent/` | `genie_cli.py` | Claude Code, faster |

Both share same scripts, configuration files, and logic.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                             AGENT FLOW                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────┐                    ┌─────────────────┐                 │
│  │   EMAIL FLOW    │                    │    CLI FLOW     │                 │
│  │ (vtoHybridModel)│                    │   (genie_cli)   │                 │
│  └────────┬────────┘                    └────────┬────────┘                 │
│           │                                      │                          │
│           └────────────────┬─────────────────────┘                          │
│                            ▼                                                │
│                   ┌─────────────────┐                                       │
│                   │  ONE-HOT ENCODE │ ◄── keyword.csv (252 keywords)        │
│                   └────────┬────────┘                                       │
│                            ▼                                                │
│                   ┌─────────────────┐                                       │
│                   │ INSTRUCTION     │ ◄── instruction.csv (60 patterns)     │
│                   │ MATCHING        │                                       │
│                   └────────┬────────┘                                       │
│                            ▼                                                │
│                   ┌─────────────────┐                                       │
│                   │ ARGUMENT PARSE  │ ◄── arguement.csv + patterns.csv      │
│                   └────────┬────────┘                                       │
│                            ▼                                                │
│                   ┌─────────────────┐                                       │
│                   │ CSH SCRIPT GEN  │ ◄── script/rtg_oss_feint/*.csh        │
│                   │ + EXECUTION     │                                       │
│                   └────────┬────────┘                                       │
│                            ▼                                                │
│                   ┌─────────────────┐                                       │
│                   │ EMAIL RESULTS   │ ◄── assignment.csv (debuggers)        │
│                   └─────────────────┘                                       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
rosenhorn_agent_flow/
├── main_agent/          # CLI agent (genie_cli.py)
├── mail_centre/         # Email-based agent (vtoHybridModel.py)
├── params_centre/       # TileBuilder params storage
├── tune_centre/         # Tune TCL files storage
└── log_centre/          # Centralized logs
```

## Script Categories

| Category | Scripts | Description |
|----------|---------|-------------|
| Static Checks | `static_check*.csh`, `run_*.csh` | CDC/RDC, lint, SPG_DFT |
| P4/Version Control | `sync_tree.csh`, `check_cl.csh` | Perforce operations |
| Waivers/Updates | `update_cdc.csh`, `update_lint.csh` | Add/update waivers |
| TileBuilder | `tb_branch.csh`, `*supra_regression*.csh` | Branching and regression |
| Timing/Reports | `synthesis_timing.csh`, `report_utilization.csh` | Reports |
| Monitoring | `check_status_supra_regression.csh` | Run monitoring |

## Script Execution Flow

### Immediate Results
For `summarize`, `report timing`, `check changelist`:
```
User Input → Parse → Execute Script → Capture Output → Display/Email
```

### Long-Running Tasks
For `run lint`, `run cdc_rdc`, `branch from`:
```
User Input → Parse → Generate Run Script → Submit to Queue → Monitor
                                              │
                                              ▼
                              On completion → Send Email
```

## Argument Variable Reference

| Variable | Source | Description |
|----------|--------|-------------|
| `$refDir` | Path detection | Reference/tree directory |
| `$ip` | arguement.csv | Project/IP code |
| `$tile` | arguement.csv | Tile name |
| `$target` | arguement.csv | TileBuilder target |
| `$tag` | Auto-generated | Unique timestamp |
| `$checkType` | Keyword match | `cdc_rdc`, `lint`, etc. |
| `$params` | Parsed params | Parameter specs |

## Extending the Agent

### Adding New Instruction

1. Add keyword to `keyword.csv`:
   ```csv
   newaction,synonym1,synonym2
   ```

2. Add instruction to `instruction.csv`:
   ```csv
   could you newaction at following directory,rtg_oss_feint/new_script.csh $refDir $ip $tag,xxx,start run
   ```

3. Create script in `script/rtg_oss_feint/`:
   ```tcsh
   #!/bin/csh -f
   set refDir = $1
   set ip = $2
   set tag = $3
   # ... implementation
   ```

### Adding New Argument Type

1. Add to `arguement.csv`:
   ```csv
   myarg,newtype
   ```

2. Add pattern to `patterns.csv` if needed:
   ```csv
   ^MY_.*,mypattern,I
   ```

## Email Flow (vtoHybridModel.py)

1. User sends email to VTO
2. Read tasksMail.csv
3. Filter by VTO name
4. Parse mail body
5. Encode and match
6. Extract arguments
7. Execute scripts
8. Send email reply

## Generated Run Script Structure

```tcsh
#!/bin/tcsh -f
cd /path/to/main_agent
source /tool/aticad/1.0/src/sysadmin/cpd.cshrc
set tag = <tag>

# Execute main script in subshell
( source script/rtg_oss_feint/... )
set script_status = $status

# Always send email
if (-f data/<tag>_email) then
    python3 genie_cli.py --send-completion-email <tag>
endif
```
