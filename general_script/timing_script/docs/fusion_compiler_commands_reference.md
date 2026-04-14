# Fusion Compiler Commands & App_Options Reference

**Project:** ROSENHORN DSO Timing Enhancement
**Generated:** 13 Mar 2026
**Sources:** DSO procs, FxSynthesize tune files

---

## Table of Contents

1. [Compilation Commands](#1-compilation-commands)
2. [Path Group Management](#2-path-group-management)
3. [Timing Constraint Commands](#3-timing-constraint-commands)
4. [Cell and Net Constraint Commands](#4-cell-and-net-constraint-commands)
5. [Timing Analysis Commands](#5-timing-analysis-commands)
6. [App_Options Reference](#6-app_options-reference)
7. [Block-Specific Optimization Strategies](#7-block-specific-optimization-strategies)
8. [Quick Reference Tables](#8-quick-reference-tables)

---

## 1. Compilation Commands

### compile_fusion

Initiates Fusion Compiler optimization from one stage to another.

```tcl
compile_fusion -from <stage> -to <stage>
```

**Stages:**
- `initial_place` - Initial placement stage
- `initial_drc` - Initial DRC fixing stage
- `initial_opto` - Initial optimization stage

**Examples:**
```tcl
compile_fusion -from initial_place -to initial_place
compile_fusion -from initial_drc -to initial_drc
compile_fusion -from initial_opto -to initial_opto
```

**Files:** `FxSynthesize.post_logic_opto.tcl`, `FxSynthesize.post_opt.tcl`

---

## 2. Path Group Management

### group_path

Create weighted path groups for optimization prioritization. Critical for R2R timing closure.

```tcl
group_path -name <group_name> \
    [-critical_range <value>] \
    [-weight <weight>] \
    [-priority <priority>] \
    [-from <cells>] \
    [-to <cells>] \
    [-through <cells>]
```

**Parameters:**
| Parameter | Description | Typical Values |
|-----------|-------------|----------------|
| `-name` | Path group identifier | `R2R_CRITICAL`, `umc_ARB_r2r` |
| `-critical_range` | Slack range for optimization (ps) | 50-700 |
| `-weight` | Optimization priority weight | 0.001-12 |
| `-priority` | Scheduling priority | 1-10 |
| `-from` | Starting point cells/registers | `$ff`, `[all_registers]` |
| `-to` | Ending point cells/registers | `$ff`, `[all_registers]` |

**Examples:**
```tcl
# Basic R2R path group
group_path -name R2R_CRITICAL -weight 2.0 \
    -from [all_registers -clock_pins] \
    -to [all_registers -data_pins]

# ARB/PGT critical path (highest priority)
group_path -name umc_ARB_PGT_r2r -critical_range 600 -weight 12 \
    -from $pgt_regs -to $pgt_regs

# Standard synthesis path groups
group_path -name SYN_R2R -critical_range 200 -weight 7 -priority 4 \
    -from $ff -to $ff

# Input to Output (lowest weight)
group_path -name SYN_I2O -critical_range 200 -weight 0.001 -priority 1 \
    -from $pi -to $po
```

**Weight Guidelines:**
| Weight Range | Priority Level | Use Case |
|--------------|----------------|----------|
| 10-12 | Critical | ARB, PGT worst paths |
| 7-9 | High | DCQARB, critical R2R |
| 4-6 | Medium | Standard R2R paths |
| 1-3 | Normal | Secondary paths |
| 0.001-0.5 | Low | I2O, non-critical |

### remove_path_group

Remove previously created path group.

```tcl
remove_path_group <group_name>
```

**Example:**
```tcl
remove_path_group R2R_CRITICAL
remove_path_group arb_safe_opt_group
```

### set_path_group

Modify or set specific path group constraints.

```tcl
set_path_group -name <group_name> [-from <cells>] [-through <cells>] [-to <cells>]
```

**Example:**
```tcl
set_path_group -name aes_mode_fanout_group -from $aes_mode_cells
```

---

## 3. Timing Constraint Commands

### set_max_transition

Set maximum transition time on nets or clock domains.

```tcl
set_max_transition <transition_value> [<net_collection>|<clock>]
```

**Typical Values:**
| Context | Value (ns) | Purpose |
|---------|------------|---------|
| Clock domains | 0.15 | General clock transition |
| DIDT nets | 0.06 | Aggressive control |
| Control nets | 0.08 | Medium control |
| Encryption | 0.12 | Datapath buffering |

**Examples:**
```tcl
set_max_transition 0.15 [get_clocks UCLK]
set_max_transition 0.06 $didt_nets
set_max_transition 0.08 $control_nets
```

### set_max_capacitance

Set maximum capacitance limits on nets.

```tcl
set_max_capacitance <capacitance_value> [<net_collection>]
```

**Typical Values:**
| Context | Value | Purpose |
|---------|-------|---------|
| Control nets | 0.4-0.5 | Standard limit |
| DIDT nets | 0.3 | Aggressive limit |

**Examples:**
```tcl
set_max_capacitance 0.5 $control_nets
set_max_capacitance 0.3 $didt_nets
```

### set_max_fanout

Set maximum fanout constraint for high-fanout net optimization.

```tcl
set_max_fanout <fanout_limit> [<cell_collection>]
```

**Typical Values:**
| Strategy | Value | Use Case |
|----------|-------|----------|
| Aggressive | 16 | PGT entry cells |
| High | 50 | Critical control |
| Medium | 100 | General design |
| Low | 150-200 | Non-critical |

**Examples:**
```tcl
set_max_fanout 16 $pgt_entry_cells
set_max_fanout 100 [current_design]
set_max_fanout [expr int(100.0 / $buffer_mult)] [current_design]
```

### set_critical_range

Define critical slack range for path optimization.

```tcl
set_critical_range <range_value> [<clock>] [-path_group <group_name>]
```

**Examples:**
```tcl
set_critical_range 0.4 [get_clocks UCLK] -path_group aes_mode_fanout_group
set_critical_range 0.3 [get_clocks UCLK] -path_group wrstor_fifo_group
```

### set_clock_gating_check

Set clock gating timing checks.

```tcl
set_clock_gating_check -setup <value> [<cell_collection>]
```

**Example:**
```tcl
set_clock_gating_check -setup 50 [get_cells -hier * -filter "ref_name=~CKOR*"]
```

### set_cost_priority

Prioritize optimization for delay vs. area.

```tcl
set_cost_priority -delay
set_cost_priority -area
```

---

## 4. Cell and Net Constraint Commands

### set_dont_touch

Prevent or allow optimization of specific cells.

```tcl
set_dont_touch <cell_collection> [true|false]
```

**Examples:**
```tcl
set_dont_touch $didt_cells false    # Allow optimization
set_dont_touch $xts_pipe false      # Remove constraint
set_dont_touch $arb_safe_regs false
```

### set_size_only

Allow only cell sizing optimization, no logic changes.

```tcl
set_size_only <cell_collection> [true|false]
```

**Examples:**
```tcl
set_size_only $critical_cells
set_size_only [get_cells -hier * -f "full_name=~/Array_reg_*"] true
```

### set_boundary_optimization

Enable optimization across module boundaries.

```tcl
set_boundary_optimization <hierarchical_cell_collection> [all|true]
```

**Examples:**
```tcl
set_boundary_optimization $matched_hier_cells all
set_boundary_optimization $arb_hier_cells true
```

### set_ideal_network

Force ideal net behavior (no delay propagation).

```tcl
set_ideal_network -no_propagate <net_collection>
```

### set_fix_multiple_port_nets

Insert buffers for multi-driven nets and constant connections.

```tcl
set_fix_multiple_port_nets -buffer_constants [-all] [<cell_collection>]
```

### size_cell

Apply sizing optimization to cell instances.

```tcl
size_cell -all_instances <cell_collection>
```

---

## 5. Timing Analysis Commands

### update_timing

Update all timing information.

```tcl
update_timing [-full]
```

### get_timing_paths

Retrieve timing paths matching specified criteria.

```tcl
get_timing_paths [-max_paths <N>] [-from <cells>] [-to <cells>] [-slack_lesser_than <value>]
```

**Example:**
```tcl
set all_paths [get_timing_paths -quiet -max_paths 1000 -slack_lesser_than 0]
```

### report_qor

Generate Quality of Results report.

```tcl
report_qor [-nosplit] [-scenarios <scenario_list>]
```

---

## 6. App_Options Reference

### 6.1 Compilation Flow Options

| App_Option | Values | Purpose |
|------------|--------|---------|
| `compile.flow.effort` | high, ultra | Overall compilation effort |
| `compile.flow.high_effort_timing` | true/false | High timing optimization effort |
| `compile.flow.high_effort_area` | true/false | High area optimization effort |
| `compile.flow.enable_retiming` | true/false | Enable register retiming |
| `compile.flow.enable_restructure` | true/false | Enable logic restructuring |
| `compile.flow.layer_aware_optimization` | true/false | Layer-aware placement |
| `compile.flow.enable_physical_multibit_banking` | true/false | Physical multibit banking |
| `compile.flow.enable_rtl_multibit_banking` | true/false | RTL multibit banking |
| `compile.flow.enable_multibit_debanking` | true/false | Multibit debanking |
| `compile.flow.propagate_constants_through_size_only_registers` | true/false | Constant propagation |
| `compile.flow.allow_duplication` | true/false | Allow cell duplication |
| `compile.flow.areaResynthesis` | true/false | Area resynthesis |

**Example:**
```tcl
set_app_options -name compile.flow.effort -value ultra
set_app_options -name compile.flow.high_effort_timing -value true
set_app_options -name compile.flow.enable_retiming -value true
```

### 6.2 Timing Optimization Options

| App_Option | Values | Purpose |
|------------|--------|---------|
| `compile.timing.effort` | high, ultra | Timing optimization effort |
| `compile.timing.area_recovery` | true/false | Area recovery trade-off |
| `compile.timing.buffer_replication` | true/false | Buffer insertion control |
| `compile.timing.buffer_insertion` | true/false | Enable buffer insertion |
| `compile.timing.size_only_mode` | true/false | Size-only mode |
| `compile.timing.critical_range` | numeric (ns) | Critical slack range |
| `compile.timing.prioritize_tns` | true/false | Prioritize TNS over WNS |
| `compile.timing.prioritize_wns` | true/false | Prioritize WNS |
| `compile.timing.power_optimization` | true/false | Power vs timing |

### 6.3 Retiming Options

| App_Option | Values | Purpose |
|------------|--------|---------|
| `compile.register_retiming.mode` | simple, full, none | Retiming strategy |
| `compile.retiming.optimization_priority` | timing, auto, area, setup_timing | Retiming focus |
| `compile.retiming.enable_forward_retiming` | true/false | Forward register movement |
| `compile.retiming.enable_backward_retiming` | true/false | Backward register movement |

**Example:**
```tcl
set_app_options -name compile.retiming.optimization_priority -value setup_timing
set_app_options -name compile.retiming.enable_forward_retiming -value true
set_app_options -name compile.retiming.enable_backward_retiming -value true
```

### 6.4 Sequential Mapping Options

| App_Option | Values | Purpose |
|------------|--------|---------|
| `compile.seqmap.register_replication_naming_style` | "%s_dup%d" | Naming for replicated registers |
| `compile.seqmap.register_replication_placement_effort` | high, medium | Placement effort for replicas |
| `compile.seqmap.remove_constant_registers` | true/false | Remove constant-tied registers |
| `compile.seqmap.remove_unloaded_registers` | true/false | Remove no-fanout registers |
| `compile.seqmap.identify_shift_registers` | true/false | Shift register identification |

### 6.5 Optimization (opt.*) Options

| App_Option | Values | Purpose |
|------------|--------|---------|
| `opt.common.max_fanout` | 16-200 | Maximum fanout for buffering |
| `opt.common.user_instance_name_prefix` | string | Prefix for created instances |
| `opt.common.advanced_logic_restructuring_mode` | timing, area, area_timing | Restructuring focus |
| `opt.common.allow_physical_feedthrough` | true/false | Allow feedthrough cells |
| `opt.common.buffer_area_effort` | high, ultra | Buffering area effort |
| `opt.common.group_path_delays` | true/false | Unified path group timing |
| `opt.timing.effort` | high, ultra | Timing optimization effort |
| `opt.timing.slack_based_tns_optimization` | true/false | TNS vs slack optimization |
| `opt.timing.tns_optimization_paths_per_endpoint` | numeric | Paths per endpoint |
| `opt.area.effort` | high, ultra | Area optimization effort |

**Example:**
```tcl
set_app_options -name opt.timing.effort -value ultra
set_app_options -name opt.common.max_fanout -value 100
set_app_options -name opt.common.advanced_logic_restructuring_mode -value timing
```

### 6.6 Placement Options

| App_Option | Values | Purpose |
|------------|--------|---------|
| `place.coarse.max_density` | 0.7-0.9 | Maximum density |
| `place.coarse.tns_driven_placement` | true/false | TNS-driven placement |
| `place.coarse.congestion_driven_max_util` | 0.8-0.95 | Congestion max util |
| `place_opt.congestion.max_util` | numeric | Place opt max util |
| `place_opt.place.congestion_effort` | high, ultra | Congestion effort |
| `place_opt.final_place.effort` | high, ultra | Final placement effort |
| `compile.initial_place.placement_congestion_effort` | medium, high | Initial placement congestion |
| `compile.initial_place.buffering_aware_placement_effort` | high, ultra | Buffering-aware placement |
| `compile.final_place.effort` | high, ultra | Final placement effort |

### 6.7 Routing Options

| App_Option | Values | Purpose |
|------------|--------|---------|
| `route.common.rc_driven_setup_effort_level` | high, ultra | RC-driven routing |
| `route.common.post_route_eco_timing_effort` | high, ultra | Post-route ECO effort |
| `route.common.post_detail_route_fix_setup_hold` | true/false | Post-detail timing fix |
| `route.global.effort_level` | high, ultra | Global routing effort |
| `route.detail.optimize_wire_via_effort_level` | high, ultra | Wire/via optimization |
| `clock_opt.place.congestion_effort` | high, ultra | Clock opt congestion |

### 6.8 CCD/Hold Options

| App_Option | Values | Purpose |
|------------|--------|---------|
| `ccd.hold_control_effort` | high, ultra | Hold time fixing effort |
| `ccd.max_prepone` | numeric (ns) | Maximum prepone value |

### 6.9 Timing Analysis Options

| App_Option | Values | Purpose |
|------------|--------|---------|
| `time.enable_cond_default_arcs` | true/false | Conditional timing arcs |

### 6.10 Multibit Options

| App_Option | Values | Purpose |
|------------|--------|---------|
| `multibit.banking.enable_tns_degradation_estimation` | true/false | TNS impact estimation |

---

## 7. Block-Specific Optimization Strategies

### ARB (Arbiter) - Highest Priority

**Challenge:** Contains worst WNS path (-82.17ps)

```tcl
# Path group setup
group_path -name umc_ARB_r2r -critical_range 600 -weight 12 \
    -from $arb_regs -to $arb_regs

# App options
set_app_options -name opt.timing.effort -value ultra
set_app_options -name compile.retiming.optimization_priority -value setup_timing

# Enable boundary optimization
set_boundary_optimization $arb_hier_cells all
```

### DCQARB - TNS Heavy

**Challenge:** 2,251 violations, -38,518ps TNS

```tcl
# Path groups
group_path -name umc_DCQARB_r2r -critical_range 200 -weight 9 -priority 10 \
    -from $dcqarb_regs -to $dcqarb_regs

# Restructuring
set_app_options -name opt.common.advanced_logic_restructuring_mode -value area_timing
```

### PGT (Page Table) - Critical Path

**Challenge:** Contains worst path endpoint

```tcl
# Aggressive path weight
group_path -name umc_ARB_PGT_r2r -critical_range 600 -weight 12 \
    -from $pgt_regs -to $pgt_regs

# Fanout reduction
set_max_fanout 16 $pgt_entry_cells

# Enable restructuring
set_app_options -name compile.flow.enable_restructure -value true
```

### Control Signals (MrDimmEn, AutoRefReq)

**Challenge:** High fanout control signals

```tcl
# Buffering
set_fix_multiple_port_nets -buffer_constants -all

# Constraints
set_max_transition 0.08 $control_nets
set_max_capacitance 0.4 $control_nets
set_app_options -name opt.common.max_fanout -value 100
```

### AES/Encryption Pipeline

**Challenge:** Deep pipeline timing balance

```tcl
# Path groups
group_path -name rdkey_pipe_group -weight 2.0 \
    -from $rdkey_cells -to $rdkey_cells

# Retiming
set_app_options -name compile.retiming.optimization_priority -value timing
set_app_options -name compile.seqmap.register_replication_placement_effort -value high

# Boundary optimization
set_boundary_optimization $aes_hier_cells true
```

---

## 8. Quick Reference Tables

### Path Group Weight Hierarchy

| Weight | Priority | Path Group Examples |
|--------|----------|---------------------|
| 12 | Critical | umc_ARB_PGT_r2r |
| 10 | Very High | umc_ARB_r2r_from, umc_ARB_r2r_to |
| 9-10 | High | umc_DCQARB_r2r, DCQARB_r2r_from |
| 7-8 | Medium-High | SYN_R2R, FEI_ADDR_r2r |
| 4-6 | Medium | Standard module R2R |
| 1-3 | Normal | Secondary paths |
| 0.001 | Low | SYN_I2O (input to output) |

### Critical Range Guidelines

| Range (ps) | Use Case |
|------------|----------|
| 600-700 | ARB, PGT critical |
| 400-500 | DCQARB, high priority |
| 200-300 | Standard R2R |
| 100-150 | Secondary paths |
| 50 | SPAZ, low priority |

### Effort Level Progression

| Level | Use Case |
|-------|----------|
| ultra | Final timing closure, critical paths |
| high | General optimization |
| medium | Initial passes, non-critical |

### DSO Permuton to App_Option Mapping

| Permuton | Primary App_Options |
|----------|---------------------|
| control_buffer | opt.common.max_fanout |
| dcq_arb | opt.common.advanced_logic_restructuring_mode |
| crit_groups | group_path weights |
| ctrl_iso | set_max_transition, set_max_capacitance |
| umc_id_didt | opt.common.advanced_logic_restructuring_mode, compile.retiming |
| fanout_dup | compile.seqmap.register_replication_placement_effort |
| timer_counter | compile.retiming.optimization_priority |
| arb_safe | opt.timing.effort, compile.flow.high_effort_timing |
| pgt | set_boundary_optimization, set_max_fanout |
| arb_r2r | group_path, compile.retiming.optimization_priority |
| r2r_tns_weight | opt.timing.slack_based_tns_optimization |

---

## File Reference

### DSO Procs Location
```
/proj/rtg_oss_er_feint2/abinbaba/ROSENHORN_DSO_v2/main/pd/tiles/dso_timing_enhancement/procs/
```

### Tune FxSynthesize Location
```
/proj/rtg_oss_feint1/FEINT_AI_AGENT/abinbaba/rosenhorn_agent_flow/tune_centre/umccmd/FxSynthesize/
```

### Key Files

| File | Purpose |
|------|---------|
| `FxSynthesize.r2r_optimization.tcl` | R2R timing optimization (weights, retiming) |
| `FxSynthesize.group_paths.tcl` | Standard path group definitions |
| `FxSynthesize.pre_opt.tcl` | Pre-optimization setup |
| `FxSynthesize.post_opt.tcl` | Post-optimization and reporting |
| `umccmd_*_procs.tcl` | UMCCMD-specific DSO procedures |
| `umcdat_*_procs.tcl` | UMCDAT-specific DSO procedures |
| `dso_*_procs.tcl` | General DSO optimization procedures |

---

**Document Version:** 1.0
**Last Updated:** 13 Mar 2026
**Maintainer:** DSO Timing Enhancement Team
