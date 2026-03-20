---
paths:
  - "script/rtg_oss_feint/supra/**"
  - "**/tiles/**"
  - "**/FxSynthesize/**"
  - "**/FxPlace/**"
  - "**/FxRoute/**"
  - "tune/**"
  - "params_centre/**"
  - "tune_centre/**"
---

# TileBuilder / Supra Documentation

## TileBuilder Commands

| Command | Description |
|---------|-------------|
| `branch from` | Create TileBuilder branch |
| `run supra regression` | Run TileBuilder target |
| `monitor supra run` | Monitor running target |
| `rerun <target>` | Rerun failed target |
| `stop run` | Stop running target |
| `report timing and area` | Extract timing report |
| `report utilization` | Extract utilization report |
| `report formality` | Extract FM verification |

## Supra Regression with Params

```bash
python3 genie_cli.py -i "run supra regression for umcdat target FxSynthesize at /proj/xxx/tiles with params <: NICKNAME = my_run
SYN_VF_FILE = /proj/xxx/umc_top.vf :>" --execute --xterm --email
```

### Common Params
| Param | Description |
|-------|-------------|
| `NICKNAME` | Custom run name suffix |
| `SYN_VF_FILE` | RTL verilog filelist path |
| `TILES_TO_RUN` | Override tile to run |
| `DSO_USE` | Enable/disable DSO (0/1) |

## TileBuilder Environment

**Problem:** cbwa environment conflicts with TileBuilder.

**Solution:** TileBuilder scripts use `lsf_tilebuilder.csh` (not `lsf.csh`):
- `env -i` for clean environment
- `tcsh -f` to skip `.cshrc`
- Sources `cpd.cshrc` instead of `env.csh`

Scripts using `lsf_tilebuilder.csh`:
- `make_tilebuilder_run.csh`
- `monitor_tilebuilder.csh`
- `extract_utilization.csh`

## Monitor Task Runtime Limits

| Limit | Duration | Behavior |
|-------|----------|----------|
| Session Timeout | 23 hours | Attempts relaunch |
| Max Total Runtime | 60 hours (2.5 days) | Graceful exit + email |

When max runtime reached:
1. Monitoring stops gracefully
2. Email sent with current status
3. Instructions to check/restart manually

## Timing Report Features

`synthesis_timing.csh` extracts:

| Section | Description |
|---------|-------------|
| Summary Metrics | WNS, TNS, NVP, StdCell Area, RAM Area, ULVTLL% |
| Primary Timing Groups | R2R path groups |
| Other Path Groups | I2R, R2O, I2C, C2O, clock_gating |
| Vt Cell Usage | UltraLow_Vt_LL, UltraLow_Vt, Low_Vt_LL, Low_Vt |
| Pass Progression | Multi-pass optimization tracking |
| LOL Report | Flop2flop timing violations ≥27 levels |

## Formality Report Features

`report_formality.csh` extracts:

| Section | Description |
|---------|-------------|
| Overall Status | PASS/FAIL based on LEC result |
| LEC Result | SUCCEEDED/FAILED |
| Equivalent Points | Matched compare points |
| Non-Equivalent Points | Mismatched points |
| Failing Points | Count and report path |
| Unmatched Points | Reference/Implementation |
| Blackbox Summary | Tech macros, interface-only, user set |

### FM Status Handling
| Status | Action |
|--------|--------|
| `NOTRUN` | Starts FM target and monitors |
| `RUNNING` | Monitors every 15 min (max 3 hours) |
| `PASSED`/`WARNING` | Extracts reports |
| `FAILED` | Reports failure with log path |

## Directory Structure

```
params_centre/
├── umcdat/
│   ├── override.params
│   └── override.controls
└── umccmd/override.params

tune_centre/
└── umcdat/
    └── FxSynthesize/
        ├── FxSynthesize.post_initial_map.tcl
        ├── FxSynthesize.post_opt.tcl
        └── Syn.Constraints.sdc
```

## Inline Params Support

```bash
python3 genie_cli.py -i "run supra regression for umcdat target FxSynthesize \
  at /proj/xxx/tiles \
  with NICKNAME = my_run_name \
  and SYN_VF_FILE = /proj/xxx/umc_top.vf" --execute
```

Separators: `with`, `and`, newlines, commas
