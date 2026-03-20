# Static Check Analysis Guide for Claude

This guide tells Claude how to analyze CDC, RDC, Lint, and SpgDFT reports when `--analyze` mode is enabled.

---

## Agent Teams Architecture

**To save context, use specialized agents for each check type.**

See `config/analyze_agents/ORCHESTRATOR.md` for the full orchestration guide.

### Directory Structure

```
config/analyze_agents/
├── ORCHESTRATOR.md              # Orchestration guide
├── cdc_rdc/                     # CDC/RDC specific agents
│   ├── precondition_agent.md    # Check inferred clks/rsts, unresolved modules
│   ├── violation_extractor.md   # Parse CDC/RDC violations
│   └── rtl_analyzer.md          # Analyze CDC crossings in RTL
├── lint/                        # Lint specific agents
│   ├── violation_extractor.md   # Parse lint violations
│   └── rtl_analyzer.md          # Analyze undriven ports
├── spgdft/                      # SpgDFT specific agents
│   ├── precondition_agent.md    # Check blackbox modules
│   ├── violation_extractor.md   # Parse DFT violations
│   └── rtl_analyzer.md          # Analyze TDR ports
└── shared/                      # Shared agents
    └── library_finder.md        # Find missing libraries
```

### Execution Flow by Check Type

**CDC/RDC:**
```
Precondition → Library Finder (if needed) → Violation Extractor → RTL Analyzers (parallel)
```

**Lint:**
```
Violation Extractor → RTL Analyzers (parallel)
```

**SpgDFT:**
```
Precondition → Library Finder (if needed) → Violation Extractor → RTL Analyzers (parallel)
```

**Full Static Check:**
```
CDC/RDC Flow → Lint Flow → SpgDFT Flow → Compile All Results
```

### Token Savings

| Flow | Est. Tokens | vs Single Agent |
|------|-------------|-----------------|
| CDC/RDC | ~22,000 | ~40% savings |
| Lint | ~18,000 | ~50% savings |
| SpgDFT | ~22,000 | ~40% savings |
| Full Static | ~62,000 | ~38% savings |

---

## CDC/RDC Analysis - Priority Order

**IMPORTANT:** Follow this exact priority order for CDC/RDC analysis.

### Priority 1: Check Inferred Clocks/Resets

**This is the FIRST thing to check.**

Look in Section 2 of cdc_report.rpt for:
```
Inferred Primary Clocks    : <count>
Inferred Primary Resets    : <count>
Inferred Blackbox Clocks   : <count>
Inferred Blackbox Resets   : <count>
```

**If inferred count > 0:**
1. Find the inferred signals in the report
2. Analyze WHY they are inferred:
   - Missing clock constraint in `project.0in_ctrl.v.tcl`
   - Missing reset constraint
   - Clock comes from blackbox module
3. Suggest fix:
   ```tcl
   # Add to src/meta/tools/cdc0in/variant/$ip/project.0in_ctrl.v.tcl
   netlist clock <signal_name> -group <CLOCK_GROUP>
   netlist reset <signal_name> -active_low
   ```

### Priority 2: Check Unresolved Modules

**This is the SECOND thing to check.**

Look for unresolved modules in the report. Unresolved modules are flagged because the **library is missing from the liblist**.

**Golden liblist path:**
```
<ref_dir>/out/linux_*//<ip>/config/*_drop2cad/pub/sim/publish/tiles/tile/*/publish_rtl/manifest/umc_top_lib.list
```

**Library search path (where to find missing modules):**
```
/proj/glkcmd1_lib/a0/library/lib_0.0.1_h110/*
```

**What Claude should do:**
1. Get the unresolved module name
2. Search in the library path:
   ```bash
   find /proj/glkcmd1_lib/a0/library/lib_0.0.1_h110/ -name "*<module_name>*" -type f
   ```
3. If found, suggest adding to liblist:
   ```
   # Add to umc_top_lib.list:
   /proj/glkcmd1_lib/a0/library/lib_0.0.1_h110/<lib_name>/<module>.v
   ```

### Priority 3: Check Blackbox Modules

Look for blackbox modules (modules with no RTL, just shell). These can cause false violations.

**In CDC report Section 2:**
```
Empty Blackbox Modules:
  dft_clk_marker
  <other_modules>
```

Same as unresolved - search in library path and suggest fix.

### Priority 4: Analyze Violations

**NOW you can look at violations.**

**Skip LOW priority (RSMU/DFT):**
- Any signal containing: `rsmu`, `RSMU`, `rdft`, `RDFT`, `dft_`, `DFT_`, `jtag`, `JTAG`, `scan_`, `SCAN_`, `bist_`, `BIST_`, `test_mode`, `sms_fuse`
- Report count but don't analyze in detail

**Focus on other violations:**
1. Read the violation details (ID, type, signal path)
2. Find the RTL source file for the signal
3. Analyze WHY the violation exists:
   - Is there a synchronizer?
   - Is it a real CDC issue?
   - Is it a static configuration signal?
4. Provide recommendation:
   - Fix RTL (add synchronizer)
   - Add waiver (with justification)
   - Add constraint

---

## SpgDFT Analysis - Priority Order

### Priority 1: Check Blackbox Modules FIRST

**Always check blackbox modules first in moresimple.rpt.**

Look for blackbox-related errors:
```
[ID]  Rule                   Error  Message
001   BlackboxModule         Error  Module 'xyz' is a blackbox
```

Same fix as CDC - find library and add to liblist.

### Priority 2: Check Unfiltered Errors

After blackbox issues, look at unfiltered errors in the spec:
- `Unfiltered_rsmu_dft` count from spec file
- Read moresimple.rpt for actual error lines

**Skip RSMU/DFT errors** - same patterns as CDC.

**Focus on real issues:**
- Undriven ports in functional logic
- SGDC configuration mismatches
- Clock/reset connectivity

### Priority 3: Analyze Undriven Ports in RTL

**For undriven port errors, always check RTL to understand WHY:**

1. **Get the signal/port name** from error:
   ```
   UndrivenOutPort-ML  Error  Output port 'Tdr_tdr_mc_umcsmn_clk_bypass_Tdo' is not driven
   ```

2. **Find the RTL file:**
   ```bash
   grep -r "Tdr_tdr_mc_umcsmn_clk_bypass_Tdo" <ref_dir>/src --include="*.sv" --include="*.v"
   ```

3. **Read the RTL and analyze:**
   - Is it intentionally undriven (stub port for future use)?
   - Is it a DFT port that should be tied off?
   - Is it a real connectivity bug?
   - Is the driver inside a generate block that's disabled?

4. **Provide recommendation:**
   - **If intentional stub:** Add to filter file or tie to constant
   - **If DFT port:** Verify with DFT team, may need tie-off
   - **If real bug:** Flag for RTL fix - need to drive the port
   - **If generate disabled:** Check generate condition

**Example RTL analysis:**
```verilog
// Found in rtl_umcsmn.v:226
output wire Tdr_tdr_mc_umcsmn_clk_bypass_Tdo;  // Line 226

// Search for driver:
// assign Tdr_tdr_mc_umcsmn_clk_bypass_Tdo = ???  // NOT FOUND

// Analysis: Port declared but never assigned
// Recommendation: Check if this is debug port - if yes, tie to 0
//                 If functional, RTL fix needed
```

---

## File Locations

### Report Paths

From `data/<tag>_analyze` file:
- `ref_dir` = tree path
- `ip` = IP name
- `check_type` = cdc_rdc, lint, spg_dft, full_static_check

**CDC/RDC reports:**
```
<ref_dir>/out/linux_*/<ip>/config/*_drop2cad/pub/sim/publish/tiles/tile/*/cad/rhea_cdc/
├── cdc_*_output/cdc_report.rpt
└── rdc_*_output/rdc_report.rpt
```

**Lint report:**
```
<ref_dir>/out/linux_*/<ip>/config/*_drop2cad/pub/sim/publish/tiles/tile/*/cad/rhea_lint/leda_waiver.log
```

**SpgDFT report:**
```
<ref_dir>/out/linux_*/<ip>/config/*_drop2cad/pub/sim/publish/tiles/tile/*/cad/spg_dft/*/moresimple.rpt
```

**Golden liblist:**
```
<ref_dir>/out/linux_*/<ip>/config/*_drop2cad/pub/sim/publish/tiles/tile/*/publish_rtl/manifest/umc_top_lib.list
```

**Library search path:**
```
/proj/glkcmd1_lib/a0/library/lib_0.0.1_h110/
```

---

## CDC Report Structure

### Section 2: CDC Check Specification (Pre-conditions)

```
==============================================
Section 2: CDC Check Specification
==============================================

Clock Domain Summary:
  Primary Clocks          : 5
  Inferred Primary Clocks : 2    ← CHECK THIS

Reset Domain Summary:
  Primary Resets          : 3
  Inferred Primary Resets : 1    ← CHECK THIS

Module Summary:
  Unresolved Modules      : 3    ← CHECK THIS
  Empty Blackbox Modules  : 1    ← CHECK THIS
```

### Section 3: CDC Results (Violations)

```
==============================================
Section 3: CDC Results
==============================================

Violations
==========
  Type                 : no_sync
  Specification Failed : Receiver outside sync module
  Severity             : Error
            : start : umc0.module.signal_name
            : end   : umc0.module.dest_signal (ID:no_sync_1)
```

---

## Lint Analysis

### Priority Order

1. **Check unwaived errors count** - if 0, lint is clean
2. **Check unresolved modules** - usually standard cells (OK to ignore)
3. **Analyze unwaived violations** - focus on functional logic issues

### Lint Report Sections

```
Waived
------
(already waived - skip)

Unwaived                    ← FOCUS HERE
--------
code | error | filename | line | msg

Unused Waivers
--------------
(informational)
```

---

## Output Format

Return analysis in this format:

```markdown
## Static Check Analysis Report

**Tag:** <tag>
**IP:** <ip>
**Tree:** <ref_dir>

---

### Pre-condition Check (CRITICAL)

#### Inferred Clocks/Resets
| Type | Count | Signals | Suggested Fix |
|------|-------|---------|---------------|
| Inferred Clocks | 2 | clk_a, clk_b | Add netlist clock constraint |
| Inferred Resets | 1 | rst_n | Add netlist reset constraint |

#### Unresolved/Blackbox Modules
| Module | Found In Library | Suggested Fix |
|--------|------------------|---------------|
| xyz_cell | /proj/glkcmd1_lib/.../xyz.v | Add to umc_top_lib.list |
| abc_mod | NOT FOUND | Investigate |

---

### Violations Summary

| Check | Total | RSMU/DFT (skip) | Focus | Action |
|-------|-------|-----------------|-------|--------|
| CDC   | 156   | 120             | 36    | Review |
| RDC   | 2     | 0               | 2     | Review |

---

### Violations Requiring RTL Review

| ID | Type | Signal | RTL Location | Analysis | Recommendation |
|----|------|--------|--------------|----------|----------------|
| no_sync_15 | no_sync | ctrl_sig | module.sv:45 | Missing synchronizer | Add 2-flop sync |
| ... | ... | ... | ... | ... | ... |

---

### Suggested Fixes

#### 1. Add to project.0in_ctrl.v.tcl:
```tcl
netlist clock <signal> -group <GROUP>
netlist reset <signal> -active_low
```

#### 2. Add to umc_top_lib.list:
```
/proj/glkcmd1_lib/a0/library/lib_0.0.1_h110/<lib>/<module>.v
```

#### 3. CDC Waivers (if justified):
```tcl
cdc report crossing -id <id> -comment "<reason>" -status waived
```
```

---

## LOW_RISK Patterns (Skip These)

These signal patterns are test/debug paths - report count but don't analyze:

| Pattern | Description |
|---------|-------------|
| `rsmu`, `RSMU` | Reset Scan MUX |
| `rdft`, `RDFT` | DFT related |
| `dft_`, `DFT_` | DFT prefix |
| `jtag`, `JTAG` | JTAG debug |
| `scan_`, `SCAN_` | Scan chain |
| `bist_`, `BIST_` | Built-in self test |
| `test_mode`, `TEST_MODE` | Test mode |
| `sms_fuse` | Fuse signals |
| `tdr_`, `TDR_` | Test Data Register |

---

## RTL Analysis

When analyzing violations, find RTL source:

1. **Get signal path** from violation: `umc0.umcdat.module.signal`
2. **Find RTL file:**
   ```bash
   find <ref_dir>/src -name "*module*.sv" -o -name "*module*.v"
   ```
3. **Read relevant lines** and understand:
   - What clock domain is the source?
   - What clock domain is the destination?
   - Is there a synchronizer in the path?
   - Is this a static signal (written once)?
4. **Provide recommendation:**
   - RTL fix needed (add synchronizer)
   - Waiver OK (with justification)
   - Constraint needed

---

## Version History

- v2.0 (2026-03-17): Added Agent Teams architecture for context-efficient analysis
- v1.1 (2026-03-17): Updated priority order per user guidance
- v1.0 (2026-03-17): Initial guide
