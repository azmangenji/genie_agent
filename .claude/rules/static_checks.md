---
paths:
  - "script/rtg_oss_feint/static_check*.csh"
  - "script/rtg_oss_feint/umc/**"
  - "script/rtg_oss_feint/oss/**"
  - "script/rtg_oss_feint/gmc/**"
  - "**/cdc/**"
  - "**/lint/**"
  - "**/spg_dft/**"
  - "**/rhea_cdc/**"
  - "**/rhea_lint/**"
---

# Static Checks Documentation

## Check Types

| Type | Description | Script |
|------|-------------|--------|
| `cdc_rdc` | Clock/Reset Domain Crossing | `static_check_unified.csh` |
| `lint` | Lint checks (LEDA) | `static_check_unified.csh` |
| `spg_dft` | SpyGlass DFT | `static_check_unified.csh` |
| `full_static_check` | All three above | `static_check_unified.csh` |

## Project-Specific Scripts

| Project | Directory | IP Prefix | Codeline |
|---------|-----------|-----------|----------|
| UMC | `script/rtg_oss_feint/umc/` | `umc*` | `umc_ip` |
| OSS | `script/rtg_oss_feint/oss/` | `oss*` | `oss_ip` |
| GMC | `script/rtg_oss_feint/gmc/` | `gmc*` | `umc4` |

## GMC Project Specifics

| Feature | GMC | UMC/OSS |
|---------|-----|---------|
| Codeline | `umc4` | `umc_ip` / `oss_ip` |
| Bootenv | `bootenv -v gmc13_1a` | `bootenv -x <ip>` |
| Tiles | Both tiles via `DROP_TOPS` | Single tile per run |
| SPG_DFT Output | Single `gmc_w_phy` | Per-tile output |

GMC Tiles: `gmc_gmcctrl_t`, `gmc_gmcch_t`

## RHEL Version Detection

Script: `script/rtg_oss_feint/get_rhel_version.csh`

| Kernel | RHEL | LSF Type | Output Dir |
|--------|------|----------|------------|
| `el7` | RHEL 7 | `RHEL7_64` | `out/linux_3.10.0_64.VCS/` |
| `el8` | RHEL 8 | `RHEL8_64` | `out/linux_4.18.0_64.VCS/` |

## Dual RHEL Path Handling

When both RHEL7 and RHEL8 output directories exist, use newest:

```tcsh
# Sort by modification time, take newest
set report = `ls -t out/linux_*.VCS/.../report.rpt | head -1`
```

## Auto-Workspace Creation

If no directory specified, system automatically:
1. Creates workspace using disk path from `assignment.csv`
2. Runs `p4_mkwa` to sync codebase
3. Runs requested static checks

Workspace naming: `umc_<project>_<timestamp>`

## Output Paths

| Check | Output Path |
|-------|-------------|
| CDC | `.../rhea_cdc/cdc_*_output/cdc_report.rpt` |
| RDC | `.../rhea_cdc/rdc_*_output/rdc_report.rpt` |
| Lint | `.../rhea_lint/leda_waiver.log` |
| SpgDFT | `.../spg_dft/*/moresimple.rpt` |

## SpyGlass SaveRestoreDB Cleanup

SpyGlass creates large `.SG_SaveRestoreDB` directories (50-150GB). Auto-cleaned after analysis:

```tcsh
find "$refdir_name" -name ".SG_SaveRestoreDB" -type d -exec rm -rf {} \;
```

## Waiver/Constraint Updates

### CDC/RDC Waiver
```tcl
cdc report crossing -id <id> -severity waived -message "<reason>"
```

### CDC/RDC Constraint
```tcl
netlist clock <path> -group <group>
netlist reset <path> -group <group>
netlist constant <path> -value <0|1>
```

### Lint Waiver
```
error: <code>
filename: */module.sv
msg: *signal_name*
reason: <justification>
author: <username>
```

## Config File Locations

| Check | Config Path |
|-------|-------------|
| CDC/RDC | `src/meta/tools/cdc0in/variant/<ip>/project.0in_ctrl.v.tcl` |
| SpgDFT | `src/meta/tools/spgdft/variant/<ip>/project.params` |
| Lint | `src/meta/tools/lint/variant/<ip>/...` |
