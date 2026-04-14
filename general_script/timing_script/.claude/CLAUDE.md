# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

DSO (Design Space Optimization) timing enhancement project for Synopsys Fusion Compiler. Creates custom permutons targeting timing optimization for UMCCMD (memory controller) and UMCDAT (security/encryption) designs in the ROSENHORN project.

**Goal**: Improve r2rWNS (register-to-register Worst Negative Slack) from -137ps baseline to < -90ps target through targeted permuton exploration.

**Tool Stack**:
- Synopsys Fusion Compiler V-2023.12-SP5-6
- DSO.ai W-2024.09-SP3

## Build & Verification Commands

```bash
# Environment setup
source setup_fc.sh    # bash
source setup_fc.csh   # csh

# Start Fusion Compiler shell
fc_shell

# In fc_shell - verify all proc files compile:
source verify_procs.tcl

# In fc_shell - verify app_options exist in FC:
source verify_appvars.tcl

# Check FC app_options documentation:
man <app_option_name>
report_app_options *timing*
report_app_options compile.*
```

## DSO Run Configuration

Set permuton file in `override.params`:
```
# For UMCCMD:
DSO_SLICE_PERMUTON_FILES = /proj/rtg_oss_er_feint2/abinbaba/ROSENHORN_DSO_v2/main/pd/tiles/dso_timing_enhancement/compile.permutons_umccmd_specific

# For UMCDAT:
DSO_SLICE_PERMUTON_FILES = .../compile.permutons_umcdat_specific
```

## Key File Locations

- **Permuton configs**: `compile.permutons_umccmd_specific`, `compile.permutons_umcdat_specific`
- **TCL procs**: `procs/*.tcl` (31 proc files implementing custom permutons)
- **Documentation**: `../documentation/` (detailed explanations, guides, analysis)
- **DSO runs**: `/proj/rtg_oss_er_feint2/abinbaba/ROSENHORN_DSO_v2/main/pd/tiles/umccmd_DSO_*`
- **DSO logs**: `<run>/logs/CrlFlow.log.gz`
- **Cached cmds**: `<run>/cmds/CrlFlow.cmd`

## Permuton Architecture

### Custom Permuton Structure
Each custom permuton requires:
1. `create_permuton` definition in permutons file with `-procedure_file` path
2. TCL proc file in `procs/` with `before_proc` and `after_proc` in `::DSO::PERMUTONS` namespace

```tcl
namespace eval ::DSO::PERMUTONS {
    proc umccmd_before_<name>_proc {permuton_name permuton_value} {
        # Apply optimization settings based on permuton_value
        set_app_options -name <option> -value <value>
    }
    proc umccmd_after_<name>_proc {} {
        # Cleanup - reset to defaults
        reset_app_options <option>
    }
}
```

### UMCCMD Permutons (9 total)
Target memory controller timing issues (high-fanout control signals, DCQ arbiter, timing counters):

| Permuton | Target | Coverage |
|----------|--------|----------|
| `umccmd_fanout_duplication` | MrDimmEn_reg, IdleBWCfg_reg | ~2.7% |
| `umccmd_control_buffering` | High-fanout control signals | ~2.7% |
| `umccmd_dcq_arbiter_pipeline` | DCQARB, DCQARB1 logic | ~49.8% |
| `umccmd_timing_counter_opt` | TwtrCtr, WrWrCtr, RdRdCtr | ~10.3% |
| `umccmd_arb_safe_reg_opt` | ArbSafeRegPc/Ph/Pm | ~2.0% |
| `umccmd_critical_path_groups` | All critical startpoints | overlaps |
| `umccmd_pgt_optimization` | PgtAlloc, PgtDeAlloc | ~11.7% |
| `umccmd_control_isolation` | Control-datapath separation | overlaps |
| `umccmd_umc_id_didt_opt` | UMC_ID_DIDT paths | ~24% |

### UMCDAT Permutons (4 total)
Target encryption pipeline timing (AES, ECC, XTS):
- `umcdat_ecc_read_procs`, `umcdat_aes_pipeline_procs`, `umcdat_key_retime_procs`, `umcdat_xts_pipeline_procs`

## FC App_Options (Dot Notation)

Fusion Compiler V-2023.12 uses dot notation:
```tcl
set_app_options -name opt.timing.effort -value <value>
reset_app_options opt.timing.effort
get_app_option_value -name opt.timing.effort
```

Key app_options used:
- `opt.timing.effort`, `opt.common.max_fanout`, `opt.common.advanced_logic_restructuring_mode`
- `compile.retiming.optimization_priority`, `compile.seqmap.register_replication_placement_effort`
- `compile.flow.high_effort_timing`, `compile.flow.areaResynthesis`

## Common Issues & Fixes

**DSO-1552: Range cannot include 'disabled' value**
- DSO reserves "disabled" as internal keyword. Use "none", "off", or "false" instead.

**Cached permutons not updated**
- DSO caches permutons in `cmds/CrlFlow.cmd`. Rerun full DSO flow or edit cached file.

**App_options not found**
- Use FC dot notation (not underscore). Run `verify_appvars.tcl` to check.

**Custom permutons show "N/A" in comparison scripts**
- Custom permutons are in DSO database, not `app_option_details.json`. Use `view_all_permutons.sh` in `documentation/` to query DSO database directly.

## DSO Concepts

**Lineage**: A sequence of runs where each builds upon knowledge from previous runs. DSO uses ML to guide exploration.

**ADES Metric**: Aggregate Design Evaluation Score. Controls what DSO optimizes for:
```tcl
# Recommended for timing focus:
create_aggregate_metric \
  -name ADES_TIMING_FOCUS \
  -component TNS -weight 1.0 \
  -component R2R_TNS -weight 3.0 \
  -component R2R_WNS -weight 2.0 \
  -component STDCELL_AREA -target_multiplier 0.95 -weight 0.2 \
  -checkpoints {DSO_final}
```

**Permuton Types**:
- `app`: Built-in FC app_options (e.g., `compile.flow.high_effort_timing`)
- `custom`: User-defined with procedure files (e.g., `umccmd_fanout_duplication`)

## Timing Analysis Context

UMCCMD baseline (umccmd_Jan19145714): ~6,010 failing endpoints
- DCQARB paths: 49.8%, UMC_ID_DIDT: 24%, PGT: 11.7%, Timing counters: 10.3%

Expected improvements with timing permutons:
- r2rWNS: 45-65ps improvement (target < -90ps)
- Trade-offs: Area +7%, Power +12%, Runtime +26%

---

## Extracting DSO Timing Metrics

### Manual Extraction Commands

**Extract WNS/TNS from QoR report:**
```bash
# For a single lineage
qor_file="<run_dir>/data/CrlFlow/work/.run_<lineage>/dso_input_dir/rpts/FxSynthesize/FxSynthesize.pass_3.proc_qor.rpt.gz"
gunzip -c "$qor_file" | awk '/Timing Path Group.*UCLK/{found=1} found && /Critical Path Slack:/{print "WNS:", $NF; exit}'
gunzip -c "$qor_file" | awk '/Timing Path Group.*UCLK/{found=1} found && /Total Negative Slack:/{print "TNS:", $NF; exit}'
```

**Extract baseline (non-DSO) timing:**
```bash
baseline_qor="<baseline_dir>/rpts/FxSynthesize/FxSynthesize.pass_3.proc_qor.rpt.gz"
gunzip -c "$baseline_qor" | awk '/Timing Path Group.*UCLK/{found=1} found && /Critical Path Slack:/{print $NF; exit}'
```

**List all lineages with pass status:**
```bash
for run_dir in <dso_run>/data/CrlFlow/work/.run_*/; do
    lineage=$(basename "$run_dir" | sed 's/\.run_//')
    for pass in 1 2 3; do
        [ -f "${run_dir}dso_input_dir/rpts/FxSynthesize/FxSynthesize.pass_${pass}.proc_qor.rpt.gz" ] && echo "$lineage: pass_$pass complete"
    done
done
```

### Key File Paths

| File | Path |
|------|------|
| QoR Report | `<run>/data/CrlFlow/work/.run_<lineage>/dso_input_dir/rpts/FxSynthesize/FxSynthesize.pass_<N>.proc_qor.rpt.gz` |
| Baseline QoR | `<baseline>/rpts/FxSynthesize/FxSynthesize.pass_<N>.proc_qor.rpt.gz` |
| FxSynthesize Log | `<run>/data/CrlFlow/work/.run_<lineage>/FxSynthesize_*.log` |
| Lineage Permutons | `dso_timing_enhancement/LINEAGE_PERMUTONS.txt` |

---

## Extracting Permuton Values

### How Permutons are Logged

Permuton values are logged in the `FxSynthesize_*.log` file with DSO-6124 messages:

```
Information: The code for 'umccmd_control_buffering' is being evaluated before checkpoint 'compile_initial_map' (DSO-6124)
INFO: ::DSO::PERMUTONS::umccmd_before_control_buffer_proc 3 - Applying control signal buffering: 3.0
```

The pattern to extract is:
```
INFO: ::DSO::PERMUTONS::umccmd_before_<name>_proc <value>
```

### Extract Lineage Permutons Script

**Location:** `scripts/extract_lineage_permutons.py`

**Usage:**
```bash
# Single DSO run
./scripts/extract_lineage_permutons.py /path/to/umccmd_DSO_28Jan_40p

# With custom output file
./scripts/extract_lineage_permutons.py /path/to/umccmd_DSO_28Jan_40p LINEAGE_PERMUTONS.txt
```

**What it does:**
1. Scans `<run>/data/CrlFlow/work/.run_*` directories for lineages
2. Finds `FxSynthesize_*.log` file in each lineage directory
3. Extracts permuton values from `INFO: ::DSO::PERMUTONS::` lines
4. Outputs to `LINEAGE_PERMUTONS.txt` in structured format

**Manual extraction (one lineage):**
```bash
grep "INFO: ::DSO::PERMUTONS::umccmd_before" <run>/data/CrlFlow/work/.run_<lineage>/FxSynthesize_*.log
```

**Output format in LINEAGE_PERMUTONS.txt:**
```
--- lineage_31e1993a ---
  control_buffer: 1.5
  dcq_arb: restructure
  crit_groups: none
  ctrl_iso: buffers
  umc_id_didt: buffer
  fanout_dup: medium
  timer_counter: none
```

---

## Permuton Settings Reference

### UMCCMD Custom Permutons

| Permuton | Settings | Description |
|----------|----------|-------------|
| `control_buffer` | 1, 1.5, 2, 3 | Buffering multiplier for high-fanout control signals. Higher = more aggressive (lower max_fanout) |
| `crit_groups` | none, standard, aggressive | Path grouping for critical startpoints. standard=top 2, aggressive=top 5 with higher weight |
| `ctrl_iso` | none, buffers, spatial, both | Control-datapath isolation method |
| `dcq_arb` | none, restructure, balance, both | DCQ arbiter optimization. restructure=logic restructuring, balance=path balancing |
| `fanout_dup` | none, low, medium, high | Register duplication threshold. low=>200, medium=>150, high=>100 fanout |
| `timer_counter` | none, pipeline, restructure, both | Timing counter optimization. pipeline=retiming, restructure=logic changes |
| `umc_id_didt` | none, restructure, retime, buffer, aggressive | UMC_ID_DIDT path optimization |

### Winning Combinations (from DSO runs)

**Best pass_3 performers:**
- `dcq_arb=restructure` + `umc_id_didt=aggressive` (common pattern)
- `ctrl_iso=spatial` or `buffers`
- `fanout_dup=medium`
- `control_buffer=1.5` to `2`

**Combinations to avoid (cause timing outliers ~-3000ps):**
- `dcq_arb=balance` or `dcq_arb=both` - **100% of outliers use these values**
- Root cause: `group_path -through` causes path explosion (see "dcq_arb Outlier Analysis" section below)

---

## DSO Timing Report Script

### Location
```
scripts/dso_timing_report.sh
```

### Usage
```bash
./dso_timing_report.sh <dso_run_dir> <baseline_dir> [pass_number] [output_file] [email]
```

### Arguments

| Argument | Required | Default | Description |
|----------|----------|---------|-------------|
| dso_run_dir | Yes | - | Path to DSO run (e.g., umccmd_DSO_28Jan_40p) |
| baseline_dir | Yes | - | Path to non-DSO baseline run |
| pass_number | No | 3 | Pass to extract (1, 2, or 3) |
| output_file | No | /tmp/dso_timing_report_<timestamp>.html | Output HTML file |
| email | No | - | Email address (@amd.com only) |

### Examples

```bash
# Generate pass_3 report
./dso_timing_report.sh \
  /proj/.../umccmd_DSO_28Jan_40p \
  /proj/.../umccmd_Jan26162737 \
  3

# Generate and email report
./dso_timing_report.sh \
  /proj/.../umccmd_DSO_28Jan_40p \
  /proj/.../umccmd_Jan26162737 \
  3 \
  /tmp/report.html \
  user@amd.com
```

### Output

The script generates a beautiful HTML report with:
- Summary cards (Best WNS, progress, best lineage)
- Baseline comparison
- Tables for better/worse/outlier lineages with permutons
- Color-coded rows (green=better, red=worse, yellow=outlier)
- Winning permuton combination box

---

## DSO Error Monitoring

### Monitor Script
```bash
# Start background monitor (checks every N minutes)
nohup scripts/dso_error_monitor.sh <dso_run_dir> <interval_minutes> > /tmp/dso_monitor.log 2>&1 &

# Check running monitors
ps aux | grep dso_error_monitor

# Kill monitors
kill <pid>
```

### Common Errors

| Error | Root Cause | Fix |
|-------|------------|-----|
| CMD-012 "extra positional option" | set_max_area or set_boundary_optimization on large cell collections | Remove set_max_area; filter hierarchical cells only for set_boundary_optimization |
| DSO-6804 "Failure in flow change" | Underlying proc error (usually CMD-012) | Fix the proc error |
| MSG-2117 "Boundary optimization on leaf cells" | set_boundary_optimization on non-hierarchical cells | Filter: `set hier_cells [filter_collection $cells "is_hierarchical == true"]` |

### Error Documentation
See `DSO_ERRORS.txt` for comprehensive error reference and fix patterns.

---

## DSO Run Paths

| Run | Path |
|-----|------|
| 40p DSO | `/proj/rtg_oss_er_feint2/abinbaba/ROSENHORN_DSO_v2/main/pd/tiles/umccmd_DSO_28Jan_40p` |
| 5p DSO | `/proj/rtg_oss_er_feint2/abinbaba/ROSENHORN_DSO_v2/main/pd/tiles/umccmd_DSO_28Jan_5p` |
| Baseline | `/proj/rtg_oss_er_feint2/abinbaba/ROSENHORN_DSO_v2/main/pd/tiles/umccmd_Jan26162737` |
| Scripts | `/proj/rtg_oss_er_feint2/abinbaba/ROSENHORN_DSO_v2/main/pd/tiles/dso_timing_enhancement/scripts/` |
| Procs | `/proj/rtg_oss_er_feint2/abinbaba/ROSENHORN_DSO_v2/main/pd/tiles/dso_timing_enhancement/procs/` |

---

## CRITICAL: dcq_arb Outlier Analysis (26 Feb 2026)

### Summary

**100% of timing outliers** (WNS > -3000ps) are caused by `dcq_arb='balance'` or `dcq_arb='both'`.

| dcq_arb Value | Better than Baseline | Worse than Baseline | Outliers | Status |
|---------------|---------------------|---------------------|----------|--------|
| `restructure` | 7 (50%) | 3 | **0** | SAFE - BEST |
| `none` | 7 (50%) | 4 | **0** | SAFE |
| `balance` | 0 | 0 | **9 (53%)** | BROKEN - AVOID |
| `both` | 0 | 0 | **8 (47%)** | BROKEN - AVOID |

### Root Cause

The issue is in `procs/umccmd_dcq_arbiter_procs.tcl` line 84:

```tcl
# BROKEN CODE:
if {$do_balance} {
    group_path -name dcqarb_group -through $dcqarb_cells -weight 2.0
    #                             ^^^^^^^^
    #                             THIS IS THE PROBLEM
}
```

**Why it breaks:**

| Issue | Explanation |
|-------|-------------|
| `-through` | Captures **ALL paths** that pass through DCQ arbiter cells. DCQARB is a central arbiter with thousands of paths flowing through it. |
| Path Explosion | Creates a **massive path group** with potentially millions of timing paths, overwhelming the optimizer. |
| `weight 2.0` | Forces the tool to prioritize ALL these paths with 2x weight, causing resource starvation for other timing paths. |
| Result | Optimizer cannot converge → **WNS collapses to -3000+ ps** |

### Proposed Fix

Change `-through` to `-to` in the balance mode:

```tcl
# BEFORE (broken):
group_path -name dcqarb_group -through $dcqarb_cells -weight 2.0

# AFTER (fixed):
group_path -name dcqarb_group -to $dcqarb_cells -weight 2.0
```

**Alternative:** Remove `balance` and `both` options entirely from the permuton search space.

### Recommended Permuton Configuration

| Permuton | Safe Values | Best Value |
|----------|-------------|------------|
| `dcq_arb` | `restructure`, `none` | `restructure` |
| `umc_id_didt` | `aggressive`, `retime`, `restructure` | `aggressive` |
| `arb_safe` | `ultra`, `high` | `ultra` |
| `timer_counter` | `both`, `none` | `both` |

### Analysis Reports

- **Outlier Analysis HTML**: `rpt/dso_outlier_analysis.html`
- **Timing Reports**: `rpt/dso_40p_timing_report_<date>.html`, `rpt/dso_5p_timing_report_<date>.html`
- **TNS Tradeoff Analysis**: `rpt/dso_tns_tradeoff_analysis.html`
