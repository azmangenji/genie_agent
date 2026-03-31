# Questa CDC/RDC Complete Reference Guide

**Tool:** Siemens Questa CDC and RDC (Version 2025.2)
**Date:** 2026-02-10
**Source:** Official Questa Documentation

---

## Table of Contents

1. [Overview](#overview)
2. [Constraint Commands](#constraint-commands)
   - netlist clock, netlist reset, netlist constant, netlist blackbox, cdc custom sync, cdc scheme on, cdc clock attribute, cdc signal
3. [CDC Analysis Commands](#cdc-analysis-commands)
   - qverify, cdc run, cdc setup, CDC output files, cdc report commands
4. [RDC Analysis Commands](#rdc-analysis-commands)
   - rdc run, rdc report commands, RDC output files, RDC methodology concepts
5. [Violation Types](#violation-types)
   - CDC violations/cautions/evaluations, RDC domain crossing schemes, Reset Tree checks, Isolation strategies
6. [Common Errors and Warnings](#common-errors-and-warnings)
7. [Result Categories](#result-categories)
8. [Best Practices](#best-practices)
9. [Quick Reference Tables](#quick-reference-tables)
10. [CDC Waiver Format](#cdc-waiver-format)
11. [Appendix: Complete Example](#appendix-complete-example)

---

## Overview

### What is Questa CDC/RDC?

**Questa CDC** - Clock Domain Crossing analysis tool that:
- Identifies clock structures and clock domains
- Detects signals crossing clock domain boundaries
- Identifies synchronization schemes
- Checks synchronization structures

**Questa RDC** - Reset Domain Crossing analysis tool for:
- Reset domain crossing verification
- Static and functional reset analysis
- Reset tree detection and validation

---

## Constraint Commands

### 1. netlist port domain

**Purpose:** Specify clock domain for primary ports or netlist cut points

**Syntax:**
```tcl
netlist port domain <port_pattern>
    [-input | -output | -inout] [-input | -output | -inout]
    [-clock <clock_id> [-add | -async | -ignore] [-posedge] [-negedge]]
    [-module <module_pattern>] [-inout_clock_in <clock>] [-inout_clock_out <clock>]
```

**Arguments:**

| Argument | Description | Example |
|----------|-------------|---------|
| `port_pattern` | Port name (wildcards allowed) | `UMC_ID`, `data_*` |
| `-input`, `-output`, `-inout` | Port direction (CDC only) | `-input` |
| `-clock <clock_id>` | Assign to specific clock domain | `-clock UCLK0` |
| `-add` | Add to existing clock group | `-clock c2 -add` |
| `-async` | Mark as asynchronous to all clocks | `-async` |
| `-ignore` | Ignore for CDC structural analysis | `-ignore` |
| `-posedge`, `-negedge` | Clock edge specification | `-posedge` |
| `-module <module_pattern>` | Apply to module instances | `-module umc_*` |

**Examples:**

```tcl
# Assign port to clock domain
netlist port domain data_bus -clock UCLK0

# Mark as asynchronous
netlist port domain async_signal -async

# Ignore stable configuration signals
netlist port domain UMC_ID -ignore
netlist port domain DIE_ID -ignore

# Create clock group
netlist port domain portA -clock c1
netlist port domain portB -clock c2 -add
netlist port domain portC -clock c3 -add
```

**Key Notes:**
- Use `-async` for signals that are asynchronous to all clock domains
- Use `-ignore` for stable signals that don't require CDC analysis
- **NEVER use `-stable` or `-quasi_static`** (not supported in Questa CDC)

---

### 2. netlist constant

**Purpose:** Specify constant value for signals (for stable/static signals)

**Syntax:**
```tcl
netlist constant <signal_pattern> <constant>
    [-module <module_pattern>] [-match_local_scope] [-regexp]
```

**Arguments:**

| Argument | Description | Example |
|----------|-------------|---------|
| `signal_pattern` | Signal name pattern | `DIE_ID`, `config_*` |
| `constant` | Verilog/VHDL value | `2'b01`, `4'b1010`, `'1` |
| `-module <module_pattern>` | Restrict to specific modules | `-module top` |

**Examples:**

```tcl
# Single-bit constant
netlist constant reset_n 1'b1

# Multi-bit bus
netlist constant config_reg[3:0] 4'b1010

# All 1's
netlist constant enable_mask '1

# Pattern matching
netlist constant {cfg_*} 1'b0
```

**When to Use:**

| Your Situation | Use This | Example |
|----------------|----------|---------|
| **Know exact constant value** | `netlist constant` | `netlist constant DIE_ID 2'b01` |
| **Stable but value varies** | `netlist port domain -ignore` | `netlist port domain UMC_ID -ignore` |
| **Don't know the value** | `netlist port domain -ignore` | `netlist port domain UMC_ID_DIDT -ignore` |

**⚠️ CRITICAL WARNING:**

> `netlist constant` is processed **BEFORE** `netlist port domain`. If both are specified for the same port, the constant takes precedence and the port domain directive has **NO EFFECT**.

---

### 3. netlist constant propagation

**Purpose:** Propagate constants through sequential logic

**Syntax:**
```tcl
netlist constant propagation [-reset] [-enable] [-remove <reset | enable>]
```

**Arguments:**

| Argument | Description |
|----------|-------------|
| `-reset` | Propagate through registers even if reset value differs |
| `-enable` | Propagate through logic with non-constant enables |

**Example:**
```tcl
netlist constant config_bit 1'b0
netlist constant propagation -reset
```

---

### 4. netlist blackbox

**Purpose:** Treat module as black box for CDC analysis

**Syntax:**
```tcl
netlist blackbox <module_pattern>
```

**Use Cases:**
- Unsynthesizable RTL (behavioral memory models)
- Modules you don't want CDC to analyze internally
- Third-party IP blocks

**Example:**
```tcl
netlist blackbox memory_controller
netlist blackbox *_ram
```

**Note:** Ports of black box must be assigned domains using `netlist port domain`

---

### 5. netlist clock

**Purpose:** Define or redefine clock domains and set clock period for CDC analysis

**Syntax:**
```tcl
netlist clock <clock_pattern>
    [-period <value>]
    [-posedge | -negedge]
    [-module <module_pattern>]
    [-add | -remove]
```

**Arguments:**

| Argument | Description | Example |
|----------|-------------|---------|
| `clock_pattern` | Clock signal name (wildcards allowed) | `cpu_clk_in`, `clk*` |
| `-period <value>` | Clock period in time units (for protocol assertions) | `-period 50` |
| `-posedge` / `-negedge` | Clock edge | `-posedge` |
| `-module <module_pattern>` | Restrict to module instances | `-module top` |
| `-add` | Add to existing clock group | `-add` |
| `-remove` | Remove from clock group | `-remove` |

**Key Behaviors:**
- Conflicting `netlist clock` directives obey the **last-one-wins** rule
- CDC analysis automatically infers clock domains; `netlist clock` overrides or supplements inference
- Use to group indirectly synchronous clocks in the same clock domain
- The `-period` value is used to calculate parameters for promoted protocol assertions

**Examples:**
```tcl
# Define three asynchronous clock domains
netlist clock cpu_clk_in -period 50
netlist clock core_clk_in -period 60
netlist clock mac_clk_in -period 50

# Group clocks that are related (synchronous to each other)
netlist clock clk_a
netlist clock clk_b -add   # clk_b in same group as clk_a

# Remove unintended clock from group
cdc clock attribute -group <clk_group> -remove
```

**Use Cases:**

| Situation | Action |
|-----------|--------|
| Clock not detected | Add `netlist clock <signal>` |
| Clocks incorrectly in same group | Use `cdc clock attribute` to remove |
| Clocks missing from same group | Use `netlist clock <clk> -add` |
| Need protocol assertions | Add `-period <value>` |

---

### 6. netlist reset

**Purpose:** Specify user-defined reset signals (overrides inferred resets)

**Syntax:**
```tcl
netlist reset <reset_pattern>
    [-active_high | -active_low]
    [-synchronous | -asynchronous]
    [-module <module_pattern>]
```

**Arguments:**

| Argument | Description | Example |
|----------|-------------|---------|
| `reset_pattern` | Reset signal name | `rst_n`, `reset_*` |
| `-active_high` / `-active_low` | Reset polarity | `-active_low` |
| `-synchronous` / `-asynchronous` | Reset type | `-asynchronous` |
| `-module <module_pattern>` | Restrict to module | `-module top` |

**When to Use:**
- When CDC infers incorrect reset (hdl-238 warning: "Inferred reset present")
- To explicitly identify user-defined resets in the design
- When internal resets are not driven by primary ports

**Example:**
```tcl
# Specify active-low asynchronous reset
netlist reset rst_n -active_low -asynchronous

# Override inferred reset
netlist reset my_reset_signal
```

**Note:** If not specified, CDC automatically infers the reset tree. Use `netlist reset` when you see warning hdl-238.

---

### 7. cdc custom sync

**Purpose:** Identify custom synchronizer circuit model

**Syntax:**
```tcl
cdc custom sync <module_name>
```

**Use Cases:**
- Custom synchronizer cells not auto-recognized by CDC
- Proprietary synchronizer implementations

**Example:**
```tcl
cdc custom sync my_custom_synchronizer
```

---

### 8. cdc scheme on

**Purpose:** Enable detection of specific synchronization schemes

**Syntax:**
```tcl
cdc scheme on -<scheme_type> [-<scheme_type> ...]
```

**Supported Schemes:**

| Scheme | Description |
|--------|-------------|
| `-fifo` | FIFO-based synchronization |
| `-dmux` | Data multiplexer schemes |
| `-pulse` | Pulse synchronization |
| `-handshake` | Handshake (req/ack) synchronization |

**Example:**
```tcl
# Enable FIFO and handshake detection
cdc scheme on -fifo -handshake

# Enable only FIFO
cdc scheme on -fifo
```

---

### 9. cdc clock attribute

**Purpose:** Modify clock group attributes — remove unintended clocks

**Syntax:**
```tcl
cdc clock attribute -group <clk_group_name> -remove
```

**Use Case:** When clock analysis detects a clock that should not be in the analysis (e.g., scan clock, test clock, unintended gated clock)

**Example:**
```tcl
# Remove scan clock from CDC analysis
cdc clock attribute -group scan_clk_group -remove
```

---

### 10. cdc signal

**Purpose:** Override inferred signal types for CDC analysis

**Syntax:**
```tcl
cdc signal <signal_pattern> -type {<signal_type>}
    [-module <module_pattern>]
```

**Signal Types:**

| Type | Description |
|------|-------------|
| `stable` | Signal is stable during normal operation (not a CDC crossing) |
| `async` | Treat as asynchronous signal |
| `ignore` | Ignore this signal for CDC analysis |

**Use Case:** When CDC incorrectly classifies a signal (e.g., identifies a stable configuration bit as a CDC crossing)

**Example:**
```tcl
# Mark signal as stable (no CDC analysis needed)
cdc signal cfg_mode -type {stable}

# Mark port as stable (alternative to netlist port domain -ignore)
cdc signal scan_mode -type {stable}
```

---

### 11. CDC Preference Commands

```tcl
# Enable reconvergence analysis
cdc preference reconvergence -on
# OR (alternate syntax)
cdc reconvergence on

# Set reconvergence depth and divergence depth
cdc preference reconvergence -depth <cycles> -divergence_depth <cycles>
# -depth: max sequential reconvergence depth (default 0 = combinational only)
# -divergence_depth: enables single-source reconvergence reporting

# Enable clock enable checking
cdc preference clockenable -on

# Enable internal reset handling
cdc preference -internal_sync_resets_on
```

---

## CDC Analysis Commands

### qverify Command (Shell)

**Purpose:** Run Questa CDC/RDC analysis sessions from the Linux shell

**Syntax:**
```bash
qverify [[-do <script-file>] | [-do "<commands>"]]
        [-od <output-directory>]
        [-c]
        [-l <log-file-name>]
        [<db-name>]
```

**Key Options:**

| Option | Description | Example |
|--------|-------------|---------|
| `-c` | Command line (batch) mode | `qverify -c` |
| `-do <script>` | Execute Tcl script or commands | `-do "cdc run; exit"` |
| `-od <dir>` | Output directory | `-od Output_Results` |
| `-l <log>` | Log file | `-l session.log` |
| `<db-name>` | Open existing database in GUI | `qverify Output_Results/cdc.db` |

**Examples:**
```bash
# Batch mode CDC run
qverify -od Output_Results -c -do "
  do scripts/directives.tcl;
  cdc run -d demo_top;
  cdc generate report cdc_detail.rpt;
  exit"

# Open GUI with existing database
qverify Output_Results/cdc.db &

# RDC batch run
qverify -od Output_Results -c -do "
  do scripts/directives.tcl;
  rdc run -d demo_top;
  rdc generate report rdc.rpt;
  exit"
```

---

### Running CDC Analysis

```tcl
# Compile design (shell utilities)
vlib work
vmap work work
vlog -f scripts/filelist.vl   # Verilog
# OR
vcom -f scripts/filelist.vh   # VHDL

# Setup and run clock report only (truncated CDC run)
cdc setup -report cdc.rpt
cdc run -d <top_module>

# Full CDC analysis run
cdc run -d <top_module>

# Generate detailed report
cdc generate report cdc_detail.rpt

# Generate crossing report
cdc generate crossings
```

**`cdc run` Options:**

| Option | Description |
|--------|-------------|
| `-d <module>` | Specify top-level design unit to analyze |
| (no option) | Analyze previously compiled top |

**`cdc setup` Options:**

| Option | Description |
|--------|-------------|
| `-report <file>` | Report file for clock/setup info |

---

### CDC Output Files

All CDC analysis runs produce these files in the output directory:

| File | Description |
|------|-------------|
| `cdc.db` | CDC database (pass to `qverify` for GUI debug) |
| `cdc.rpt` | Clock domain crossing report (clock summary + crossings) |
| `cdc_detail.rpt` | Detailed clock domain crossing report |
| `cdc_design.rpt` | CDC design report (design statistics) |
| `cdc_setting.rpt` | Settings report (preferences + directive processing results) |
| `cdc_run.log` | Transcript of the session (standard output copy) |
| `qverify.log` | CDC analysis run log |
| `qverify_cmds.tcl` | Sequence of executed Questa Formal Technology Tcl commands |

**Note:** Clock report generation (`cdc setup -report`) produces files with **less** information than full CDC runs. Full `cdc run` is required for complete results.

---

### CDC Report Commands

```tcl
# Report violations by type
cdc report item -type no_sync
cdc report item -type multi_bits
cdc report item -type combinational_logic

# Report scheme usage
cdc report scheme

# Report crossings
cdc generate crossings

# Generate tree report
cdc generate tree -clock
```

---

## RDC Analysis Commands

### Running RDC Analysis

```tcl
# Full RDC analysis
rdc run -d <top_module>

# Generate RDC report
rdc generate report rdc.rpt

# Generate RDC tree report
rdc generate tree
```

### RDC Report Commands

```tcl
# Report reset tree checks
rdc report item -type reset_tree

# Report isolation checks
rdc report item -type isolation

# Report areset checks
rdc report item -type areset

# Report all RDC scheme violations
rdc report scheme

# Report domain crossings
rdc generate crossings
```

### RDC Output Files

| File | Description |
|------|-------------|
| `rdc.db` | RDC database |
| `rdc.rpt` | Main RDC report |
| `rdc_setting.rpt` | RDC settings and preferences |
| `rdc_run.log` | Session transcript |
| `hrdc.rpt` | Hierarchical RDC report (bottom-up analysis) |

### RDC Methodology Concepts

**Pathname Softening:**
- RDC applies "pathname softening" to match signal paths across hierarchy
- Allows waiver/status from block-level analysis to propagate to top-level
- Important for hierarchical (bottom-up/top-down) analysis flows

**Reset Ordering:**
- When multiple resets exist, the order of assertion/deassertion matters
- Improper ordering can cause data corruption at reset release
- Use `rdc order assert` to specify required reset ordering

**Static Reset Analysis:**
- Analyzes reset tree topology without simulation
- Checks reset domain crossings, tree integrity, isolation requirements

**RDC Waiver Guidelines** (from rdc_user.pdf):
1. Review crossing in schematic viewer before waiving
2. Verify isolation is not required before waiving isolation violations
3. Document reset ordering assumptions in waiver comments
4. Use `rdc report item -status waived` to track waived items
5. Periodically re-review waivers when RTL changes

---

## Violation Types

### CDC Violation Categories

#### 1. Violations (Must-Fix)

**Severity:** VIOLATION
**Action Required:** Fix immediately

| Violation Type | Description | Fix |
|----------------|-------------|-----|
| **no_sync** | Signal crosses clock domain without proper synchronization | Add 2-DFF or 3-stage synchronizer |
| **multi_bits** | Multi-bit signal crosses without proper scheme | Use Gray code, FIFO, or handshake |
| **combinational_logic** | Combinational logic before synchronizer | Relocate logic or add valid strobe |

**Example Violations:**

```
Violations (6)
----------------------------------------------------------------
Single-bit signal does not have proper synchronizer.      (3)
Combinational logic before synchronizer.                  (2)
Multiple-bit signal across clock domain boundary.         (1)
```

---

#### 2. Cautions (Review Required)

**Severity:** CAUTION
**Action Required:** Review and validate

| Caution Type | Description | Action |
|--------------|-------------|--------|
| **DMUX synchronization** | Complex synchronization requiring review | Verify proper implementation |
| **reconvergence** | Signal reconverges after CDC | Check for data stability |

**Example Cautions:**

```
Cautions (2)
----------------------------------------------------------------
DMUX synchronization.                                      (2)
```

---

#### 3. Evaluations (Properly Synchronized)

**Severity:** EVALUATION
**Action Required:** None (informational)

| Evaluation Type | Description |
|-----------------|-------------|
| **DFF synchronizer** | Single-bit synchronized by 2-DFF |
| **multi-bit DFF** | Multi-bit with DFF synchronization |
| **FIFO** | FIFO-based synchronization detected |

**Example Evaluations:**

```
Evaluations (8)
----------------------------------------------------------------
Single-bit signal synchronized by DFF synchronizer.        (2)
Multiple-bit signal synchronized by DFF synchronizer.      (4)
FIFO synchronization.                                      (2)
```

---

#### 4. Proven (Formally Verified)

**Severity:** PROVEN
**Action Required:** None

Crossings for which protocol assertions are proven.

---

#### 5. Waived (User Reviewed)

**Severity:** WAIVED
**Action Required:** None

Crossings marked as reviewed and approved by user.

---

### RDC Violation Categories

#### RDC Domain Crossing Schemes

These schemes describe how resets cross domain boundaries:

| Scheme | Description | Severity |
|--------|-------------|----------|
| **rdc_areset** | Asynchronous reset crosses clock domain | VIOLATION |
| **rdc_areset_nrr** | Async reset without recommended reset removal | VIOLATION |
| **rdc_dff** | DFF synchronizer on reset crossing | EVALUATION |
| **rdc_combo_logic** | Combinational logic in reset path | CAUTION |
| **rdc_isolation_clockgate** | Clock gating isolation required | VIOLATION |
| **rdc_isolation_data** | Data isolation required on reset | VIOLATION |
| **rdc_ordered** | Reset ordering issue (release order) | VIOLATION |
| **rdc_pulse** | Pulse-based reset crossing | CAUTION |
| **rdc_safe_fanout** | Reset fanout considered safe | EVALUATION |
| **rdc_shift_reg** | Shift register on reset path | CAUTION |
| **rdc_sync_module** | Synchronizer module on reset path | EVALUATION |
| **rdc_tx_at_reset_value** | Transmit side at reset value | EVALUATION |
| **rdc_cdc_areset** | Combined CDC+RDC async reset issue | VIOLATION |
| **rdc_inferred_stable** | Reset inferred as stable | CAUTION |
| **rdc_blackbox** | Reset enters/exits black box | WARNING |

#### Reset Tree Checks (Reset Domain Violations)

These checks analyze the reset tree topology:

| Check | Description | Severity |
|-------|-------------|----------|
| **nrr_on_reset_path** | Non-resettable register on reset path | VIOLATION |
| **reset_areset_always_active** | Async reset that is always active | VIOLATION |
| **reset_as_data** | Reset signal used as data | VIOLATION |
| **reset_combo_glitch** | Combinational glitch in reset path | CAUTION |
| **reset_convergence** | Reset reconvergence (reset from multiple sources) | CAUTION |
| **reset_data_loop** | Data loop through reset logic | VIOLATION |
| **reset_dual_areset_sreset** | Register with both async and sync reset | CAUTION |
| **reset_dual_polarity** | Reset with inconsistent polarity | VIOLATION |
| **reset_enable_async** | Enable used as async reset | VIOLATION |
| **reset_polarity_areset_mismatch** | Async reset polarity mismatch | VIOLATION |
| **reset_polarity_sreset_mismatch** | Sync reset polarity mismatch | VIOLATION |
| **reset_pragma_mismatch** | Reset pragma mismatch | VIOLATION |
| **reset_set_reset_cascade** | Set/reset cascade issue | CAUTION |
| **reset_set_reset_priority** | Set/reset priority issue | CAUTION |
| **reset_sync_deassert_loads_constant** | Sync deassertion loads constant | CAUTION |
| **reset_unexpected_gate** | Unexpected gate in reset tree | VIOLATION |
| **reset_unexpected_latch** | Unexpected latch in reset tree | VIOLATION |
| **reset_unexpected_tri** | Unexpected tristate in reset tree | VIOLATION |
| **reset_unresettable_register** | Register that cannot be reset | VIOLATION |
| **reset_unused** | Reset signal that is unused | WARNING |

#### Legacy RDC Check Categories

| Violation Type | Description | Severity |
|----------------|-------------|----------|
| **reset_tree** | Issues with reset tree structure | VIOLATION |
| **areset** | Asynchronous reset issues | VIOLATION |
| **isolation** | Clock/data isolation problems | VIOLATION |
| **reset_convergence** | Reset reconvergence issues | CAUTION |
| **reset_combo_logic** | Combinational logic in reset path | CAUTION |

#### RDC Isolation Strategies

When a clock domain is reset while another is not, isolation may be required:

**Clock Gating Isolation** (`rdc_isolation_clockgate`):
- Clock is gated when associated reset is asserted
- Prevents glitches from propagating to other domains
- Required when: data from resetting domain fans out to non-resetting domain

**Data Isolation** (`rdc_isolation_data`):
- Data path is isolated (muxed to safe value) when reset asserted
- Required when: data crosses from resetting domain into non-resetting domain
- Common implementations: AND gate with reset_n, MUX with constant, isolation cell

```tcl
# RDC identifies isolation requirement:
# rdc_isolation_clockgate or rdc_isolation_data violation reported
# Fix: Add isolation cell or annotate with waiver + isolation attribute
```

---

## Common Errors and Warnings

### CDC Errors

#### Error hdl-41: Primary port connects to multiple clock domains

**Message:**
```
Error: Primary port connects to multiple clock domains.
Pin 'rst'. [hdl-41]
Pin 'clr'. [hdl-41]
```

**Cause:** Port drives logic in multiple clock domains without domain assignment

**Fix:**
```tcl
# Assign single-clock domain
netlist port domain rst -clock U1.clk_a

# OR mark as asynchronous
netlist port domain rst -async
```

---

### CDC Warnings

#### Warning hdl-238: Inferred reset present

**Message:**
```
Warning: Inferred reset present.
```

**Cause:** CDC inferred signal as root of reset tree

**Fix:**
```tcl
# Use netlist reset to identify user-specified reset
netlist reset reset_signal_name
```

---

#### Warning hdl-271: Reconvergence is not enabled

**Message:**
```
Warning: Reconvergence is not enabled.
```

**Cause:** Reconvergence analysis turned off by default (performance)

**Fix:**
```tcl
# Enable reconvergence analysis
cdc reconvergence on
cdc preference reconvergence
```

---

#### Warning hdl-289: Missing clock domain for reset port

**Message:**
```
Warning: Missing clock domain for reset port.
```

**Cause:** Reset port not associated with clock domain

**Fix:**
```tcl
# Assign clock domain to reset port
netlist port domain reset_port -clock clk_domain
```

---

#### Warning hdl-51: Missing port domain assignment for bits of port

**Message:**
```
Warning: Missing port domain assignment for bits of port.
```

**Cause:** Primary port with no netlist port domain assignment

**Fix:**
```tcl
# Assign port domain
netlist port domain signal -async

# OR ignore
netlist port domain signal -ignore
```

---

#### Warning netlist-82: Found internal reset signals

**Message:**
```
Warning: Found internal reset signals.
```

**Cause:** Internal instance resets not driven by primary port

**Fix:**
```tcl
# Force CDC to consider internal resets as proper
cdc preference -internal_sync_resets_on
```

---

## Result Categories

### CDC Summary Categories

```
CDC Results
================================================================
Violations (6)
----------------------------------------------------------------
Single-bit signal does not have proper synchronizer.      (3)
Combinational logic before synchronizer.                  (2)
Multiple-bit signal across clock domain boundary.         (1)

Cautions (2)
----------------------------------------------------------------
DMUX synchronization.                                      (2)

Evaluations (8)
----------------------------------------------------------------
Single-bit signal synchronized by DFF synchronizer.        (2)
Multiple-bit signal synchronized by DFF synchronizer.      (4)
FIFO synchronization.                                      (2)

Resolved - Waived or Verified Status (0)
----------------------------------------------------------------
<None>

Proven (4)
----------------------------------------------------------------
Single-bit signal synchronized by DFF synchronizer.        (3)
Pulse Synchronization.                                     (1)

Filtered (0)
----------------------------------------------------------------
<None>
```

### Interpretation

| Category | Meaning | Action |
|----------|---------|--------|
| **Violations** | Must-fix issues | Add synchronizers or fix RTL |
| **Cautions** | Review required | Verify implementation is correct |
| **Evaluations** | Properly synchronized | Informational only |
| **Proven** | Formally verified | No action needed |
| **Waived** | User-approved | No action needed |
| **Filtered** | Hidden by filters | Manage display |

---

## Best Practices

### 1. Constraint Development Workflow

```tcl
# Step 1: Generate clock report
cdc generate clock report

# Step 2: Assign primary port domains
netlist port domain <primary_inputs> -async
netlist port domain <config_signals> -ignore

# Step 3: Mark stable constants
netlist constant <stable_signal> <value>

# Step 4: Run CDC analysis
cdc run

# Step 5: Review violations
cdc report item -type no_sync
cdc report item -type multi_bits

# Step 6: Add constraints iteratively
# ... repeat steps 2-5 until clean
```

---

### 2. Handling Stable Signals

**Option A: Use `-ignore` (preferred for chip ID, fuses)**

```tcl
netlist port domain UMC_ID -ignore
netlist port domain DIE_ID -ignore
```

**Option B: Use `netlist constant` (if value known)**

```tcl
netlist constant UMC_ID 4'b0011
netlist constant DIE_ID 2'b01
```

**Recommendation:** Use `-ignore` for signals that vary between chips

---

### 3. Handling Asynchronous Signals

**Verify RTL has synchronizers:**

```tcl
# Mark as async
netlist port domain async_signal -async

# Verify synchronizer exists in RTL
grep -r "techind_sync_icd.*async_signal" <rtl_path>
```

**For multi-bit buses, verify synchronization scheme:**
- Gray code conversion (counters/addresses)
- Dual-rank synchronizers + valid strobe
- FIFO or async FIFO
- Handshake protocol (req/ack)

---

### 4. Custom Synchronizers

If CDC doesn't auto-recognize your synchronizer:

```tcl
# Identify as custom synchronizer
cdc custom sync my_sync_module

# Assign port domains to synchronizer ports
netlist port domain my_sync_module.async_in -async
```

---

### 5. Black Boxing Modules

For modules you don't want to analyze:

```tcl
# Mark as black box
netlist blackbox memory_model

# Must assign port domains
netlist port domain memory_model.data -async
netlist port domain memory_model.addr -clock UCLK0
```

---

## Quick Reference Tables

### Constraint Command Summary

| Command | Purpose | When to Use |
|---------|---------|-------------|
| `netlist clock` | Define/redefine clock domain | Define clocks, group related clocks |
| `netlist reset` | Specify user-defined reset | Override inferred reset (hdl-238) |
| `netlist port domain -ignore` | Ignore signal for CDC | Stable config signals (chip ID, fuses) |
| `netlist port domain -async` | Mark as asynchronous | Signals crossing domains with sync in RTL |
| `netlist port domain -clock` | Assign to clock domain | Single clock domain signals |
| `netlist constant` | Set constant value | Stable signals with known values |
| `netlist constant propagation` | Propagate constants through sequential logic | After netlist constant for stable regs |
| `netlist blackbox` | Treat as black box | Third-party IP, memory models |
| `cdc custom sync` | Identify custom sync | Non-standard synchronizers |
| `cdc scheme on -fifo` | Enable FIFO detection | Designs using FIFO crossings |
| `cdc scheme on -handshake` | Enable handshake detection | Designs using req/ack protocol |
| `cdc clock attribute` | Remove unintended clocks | Scan clocks, test clocks |
| `cdc signal` | Override inferred signal type | Stable signals misidentified as CDC |

---

### Violation Type Summary

| Violation | Severity | Meaning | Fix |
|-----------|----------|---------|-----|
| **no_sync** | VIOLATION | Missing synchronizer | Add 2-DFF/3-stage sync |
| **multi_bits** | VIOLATION | Multi-bit without sync | Gray code, FIFO, handshake |
| **combinational_logic** | VIOLATION | Logic before sync | Relocate or add strobe |
| **DMUX** | CAUTION | Complex sync scheme | Review implementation |
| **reconvergence** | CAUTION | Signal reconverges | Check data stability |
| **DFF synchronizer** | EVALUATION | Properly synchronized | None |
| **FIFO** | EVALUATION | FIFO detected | None |

---

### Common Error Messages

| Message ID | Description | Fix |
|------------|-------------|-----|
| **hdl-41** | Port connects to multiple clocks | Assign domain or use `-async` |
| **hdl-238** | Inferred reset present | Use `netlist reset` |
| **hdl-271** | Reconvergence not enabled | Use `cdc reconvergence on` |
| **hdl-289** | Missing clock for reset | Use `netlist port domain -clock` |
| **hdl-51** | Missing port domain | Assign domain or `-ignore` |
| **netlist-82** | Internal reset signals | Use `cdc preference -internal_sync_resets_on` |

---

### Synchronization Schemes

| Scheme | Type | Use Case | CDC Detection |
|--------|------|----------|---------------|
| **2-DFF** | Single-bit | Control signals | Auto-detected |
| **3-stage** | Single-bit | High reliability | Auto-detected |
| **Gray code** | Multi-bit | Counters, addresses | Manual constraint |
| **FIFO** | Multi-bit | Data buses | Auto-detected (with `-fifo`) |
| **Handshake** | Multi-bit | Req/Ack protocol | Manual review |
| **DMUX** | Multi-bit | Data multiplexing | Auto-detected (caution) |
| **Pulse sync** | Single-bit | Pulse generation | Auto-detected |

---

### RDC Check Types Quick Reference

| Check Type | Description | Severity |
|------------|-------------|----------|
| **rdc_areset** | Async reset crosses clock domain | VIOLATION |
| **rdc_areset_nrr** | Async reset without NRR | VIOLATION |
| **rdc_isolation_clockgate** | Clock gating isolation required | VIOLATION |
| **rdc_isolation_data** | Data isolation required | VIOLATION |
| **rdc_ordered** | Reset ordering issue | VIOLATION |
| **rdc_combo_logic** | Combinational logic in reset path | CAUTION |
| **rdc_dff** | DFF synchronizer on reset | EVALUATION |
| **rdc_safe_fanout** | Safe reset fanout | EVALUATION |
| **reset_as_data** | Reset signal used as data | VIOLATION |
| **reset_areset_always_active** | Async reset always active | VIOLATION |
| **reset_combo_glitch** | Combinational glitches | CAUTION |
| **reset_convergence** | Reset reconvergence | CAUTION |
| **reset_dual_polarity** | Inconsistent reset polarity | VIOLATION |
| **reset_unexpected_gate** | Unexpected gate in reset tree | VIOLATION |
| **reset_unexpected_latch** | Unexpected latch in reset tree | VIOLATION |
| **reset_unresettable_register** | Register cannot be reset | VIOLATION |
| **reset_unused** | Unused reset signal | WARNING |
| **nrr_on_reset_path** | Non-resettable register on path | VIOLATION |

---

### File Locations and Structure

```
Design Files:
├── design.v              # RTL source files
├── constraints.tcl       # CDC/RDC constraints
└── compile.do            # Compilation script

CDC/RDC Output:
├── work/                 # Compiled library
├── cdc.db                # CDC database
├── rdc.db                # RDC database
├── cdc.rpt               # CDC report
├── rdc.rpt               # RDC report
└── cdc_crossings.rpt     # Crossing details
```

---

### Command Line Flow

```bash
# 1. Compile design
qverify -c -do "qrun design.v -compile"

# 2. Run CDC analysis
qverify -c -do "cdc run; cdc generate report cdc.rpt; exit"

# 3. Run RDC analysis
qverify -c -do "rdc run; rdc generate report rdc.rpt; exit"

# 4. GUI Debug
qverify Output_Results/cdc.db &
```

---

## Appendix: Complete Example

### Example Design Constraints

```tcl
################################################################################
# CDC Constraint File
# Design: UMC Memory Controller
################################################################################

#===============================================================================
# 1. STABLE CONFIGURATION SIGNALS
#===============================================================================

# Chip identification - stable after boot
netlist port domain UMC_ID -ignore
netlist port domain DIE_ID -ignore
netlist port domain CHIP_CONFIG -ignore

#===============================================================================
# 2. ASYNCHRONOUS DEBUG INTERFACES
#===============================================================================

netlist port domain CrossTrigger_AsyncIn -async

#===============================================================================
# 3. ASYNCHRONOUS DATA BUSES
#===============================================================================

# PHY interface - async from DDR PHY domain
netlist port domain PHY_DataBus -async
netlist port domain PHY_ControlBus -async

# Inter-UMC communication
netlist port domain UMC_InterComRx -async

#===============================================================================
# 4. CLOCK DOMAIN ASSIGNMENTS
#===============================================================================

# Main UMC clock domain
netlist port domain data_valid -clock UCLK0
netlist port domain addr_bus -clock UCLK0

# DDR PHY clock domain
netlist port domain dfi_data -clock DFICLKin0

#===============================================================================
# 5. CUSTOM SYNCHRONIZERS
#===============================================================================

cdc custom sync techind_sync_icd

#===============================================================================
# 6. BLACK BOX MODULES
#===============================================================================

netlist blackbox ddr_phy_model
netlist port domain ddr_phy_model.* -async

#===============================================================================
# 7. SCHEME ENABLEMENT
#===============================================================================

cdc scheme on -fifo

#===============================================================================
# 8. PREFERENCES
#===============================================================================

cdc preference reconvergence -on
cdc preference -internal_sync_resets_on

################################################################################
# END OF CONSTRAINTS
################################################################################
```

---

---

## CDC Waiver Format

### Waiver Command Syntax

```tcl
cdc report item -scheme <violation_type> -from {<tx_signal>} -to {<rx_signal>} -tx_clock {<tx_clock>} -rx_clock {<rx_clock>} -module {<module>} -status waived -owner {<owner>} -comment {<reason>} -creator {<creator>} -timestamp {<date>}
```

### Waiver Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `-scheme` | Violation type | `no_sync`, `series_redundant`, `combo_logic` |
| `-from` | TX signal path | `{DIE_ID}`, `{umc0.umcdat.signal_name}` |
| `-to` | RX signal path | `{umc0.umccmd.REGCMD.REG.uumccmdrb.oQ_UMC_CONFIG}` |
| `-tx_clock` | Transmit clock domain | `{Async}`, `{UCLK}`, `{REFCLK}` |
| `-rx_clock` | Receive clock domain | `{UCLK}`, `{REFCLK}` |
| `-module` | Top module name | `{umc_top}` |
| `-status` | Waiver status | `waived` |
| `-owner` | Owner username | `{abinbaba}` |
| `-comment` | Justification reason | `{Static signal, no sync required}` |
| `-creator` | Creator username | `{abinbaba}` |
| `-timestamp` | Date/time | `{11 March 2026 , 10:00:00}` |

### Common Violation Schemes

| Scheme | Description |
|--------|-------------|
| `no_sync` | Single-bit signal does not have proper synchronizer |
| `series_redundant` | Series redundant synchronization |
| `combo_logic` | Combinational logic before synchronizer |
| `multi_bit` | Multi-bit signal crossing without proper sync |
| `reconvergence` | Reconvergent CDC paths |

### Waiver Examples

```tcl
# Static fuse input - no sync needed
cdc report item -scheme no_sync -from {DIE_ID} -to {umc0.umccmd.REGCMD.REG.uumccmdrb.oQ_UMC_CONFIG_UmcToChA} -tx_clock {Async} -rx_clock {UCLK} -module {umc_top} -status waived -owner {abinbaba} -comment {DIE_ID is a static fuse input that remains stable after power-on. No synchronizer required.} -creator {abinbaba} -timestamp {11 March 2026 , 10:00:00}

# Series redundant - intentional double sync
cdc report item -scheme series_redundant -from {umc0.umcdat.umcsmn.CplPwrOkDficlkTx_Shft[6]} -to {umc0.umcdat.umcsmn.UCLKGEN.uclk_ag_mux.gen_reset_fpm.uBUF_reset_CLKA.A} -tx_clock {UCLK} -rx_clock {UCLK} -module {umc_top} -status waived -owner {abinbaba} -comment {Violation has been reviewed by the designer and it is okay to waive} -creator {abinbaba} -timestamp {12 January 2026 , 05:56:15}

# Combinational logic waiver
cdc report item -scheme combo_logic -from {ctrl_signal} -to {sync_reg} -tx_clock {CLK_A} -rx_clock {CLK_B} -module {umc_top} -status waived -owner {abinbaba} -comment {Delay within acceptable range. Verified by timing analysis.} -creator {abinbaba} -timestamp {11 March 2026 , 10:00:00}
```

### Waiver File Location (UMC Project)

```
src/meta/tools/cdc0in/variant/<ip>/umc.0in_waiver
```

### Adding Waivers via Genie CLI

```bash
# Add CDC waiver
python3 script/genie_cli.py -i "add cdc_rdc waiver at /proj/xxx/tree_dir for umc9_3
cdc report item -scheme no_sync -from {DIE_ID} -to {umc0.umccmd.REGCMD.REG.uumccmdrb.oQ_UMC_CONFIG_UmcToChA} -tx_clock {Async} -rx_clock {UCLK} -module {umc_top} -status waived -owner {abinbaba} -comment {Static fuse input, no sync required.} -creator {abinbaba} -timestamp {11 March 2026 , 10:00:00}" --execute --xterm --email
```

### Waiver Best Practices

1. **Always include justification** in `-comment` field
2. **Use full hierarchical paths** for `-from` and `-to` signals
3. **Specify correct clock domains** for `-tx_clock` and `-rx_clock`
4. **Include timestamp** for audit trail
5. **Review waivers periodically** - designs change, waivers may become invalid

### Common Waiver Justifications

| Signal Type | Example Justification |
|-------------|----------------------|
| Static fuse/ID | "Static fuse input that remains stable after power-on. No synchronizer required." |
| Configuration | "Configuration signal stable before clock starts. Verified by design spec." |
| Series redundant | "Intentional double synchronization for reliability. Verified by designer." |
| Combo logic | "Delay within acceptable range. Verified by timing analysis." |
| Test mode | "Test mode signal only active during scan. Not functional path." |

---

## Document Information

**Version:** 1.2
**Last Updated:** 2026-03-31
**Based On:**
- Questa CDC and RDC Tutorials Guide (Version 2025.2)
- Questa OneSpin Static and Formal Command Reference (Version 2025.2)
- Questa RDC User Guide (Version 2025.2)

**v1.2 Additions:**
- `netlist clock` command (clock domain definition, -period option)
- `netlist reset` command (user-specified resets)
- `cdc clock attribute` (remove unintended clocks from groups)
- `cdc signal` (override inferred signal types)
- `cdc scheme on -handshake` (handshake synchronization detection)
- `cdc setup` and full `cdc run -d <DUT>` syntax
- `qverify` shell command reference
- Complete CDC output files list
- Complete RDC domain crossing schemes (rdc_areset, rdc_dff, rdc_isolation_*, etc.)
- Complete Reset Tree checks (20+ checks from rdc_user.pdf)
- RDC isolation strategies (clock gating, data isolation)
- RDC methodology concepts (pathname softening, reset ordering)
- RDC waiver guidelines

**Support:**
- Documentation: support.sw.siemens.com
- Feedback: support.sw.siemens.com/doc_feedback_form

---

**END OF DOCUMENT**
