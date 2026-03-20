# Analyze Skill

Analyze test failures and debug issues with intelligent failure analysis and automated rerun options.

## Trigger
`/analyze`

## Overview

This skill bridges the output from `umc_triage` (from execute.md) to intelligent failure analysis and automated rerun with appropriate verbosity options.

This workflow is **ITERATIVE** - it may loop between analysis and rerun until the root cause is found.

### Workflow Phases:

**PHASE 1: Initial Analysis (First Pass)**
1. Parse umc_triage output to identify failing tests
2. Initial analysis of run.log - understand error type and failing component
3. Identify related components
4. **Decision Point**: Is there enough debug info to understand root cause?

**PHASE 2: Rerun with Verbosity (If Needed)**
5. If NOT enough info → Discover verbosity options for each component
6. Build rerun command with -op flags
7. Display verbosity summary
8. **Invoke rerun.md** to execute the rerun
9. Wait for rerun to complete

**PHASE 3: Deep Analysis with ULTRATHINK (After Rerun)**
10. Return to analyze.md after rerun completes
11. **ULTRATHINK**: Deep analysis of verbose run.log
12. **ULTRATHINK**: Trace root cause through detailed debug output
13. **ULTRATHINK**: Identify the fix or determine if more verbosity needed

**PHASE 4: Iterate if Needed**
14. If still not enough info → Go back to Phase 2 with additional verbosity
15. If root cause found → Document findings and proceed with fix

### ⚠️ ULTRATHINK REQUIREMENT

**ULTRATHINK is used in PHASE 3 (after rerun completes), NOT in Phase 1.**

- **Phase 1 (Initial)**: Quick analysis to determine if rerun is needed
- **Phase 3 (After Rerun)**: ULTRATHINK for deep analysis of verbose logs

**ULTRATHINK is MANDATORY after rerun completes with verbose output.**

### Workflow Diagram:

```
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 1: INITIAL ANALYSIS                                       │
│ • Parse triage output                                           │
│ • Read run.log                                                  │
│ • Identify failing component                                    │
│ • Quick assessment: enough info?                                │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                    ┌─────────────────────┐
                    │ Enough debug info?  │
                    └─────────────────────┘
                     ↓ NO              ↓ YES
┌─────────────────────────────┐    ┌─────────────────────────────┐
│ PHASE 2: RERUN WITH         │    │ Proceed with fix            │
│ VERBOSITY                   │    │ (skip to Phase 3)           │
│ • Discover -op flags        │    └─────────────────────────────┘
│ • Display summary           │
│ • Invoke rerun.md           │
│ • Wait for completion       │
└─────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 3: DEEP ANALYSIS ⚠️ ULTRATHINK                            │
│ • Return to analyze.md                                          │
│ • Read new verbose run.log                                      │
│ • ULTRATHINK: Deep root cause analysis                          │
│ • ULTRATHINK: Trace through debug output                        │
│ • Determine fix or need more verbosity                          │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                    ┌─────────────────────┐
                    │ Root cause found?   │
                    └─────────────────────┘
                     ↓ NO              ↓ YES
            ┌───────────────┐    ┌─────────────────────────────┐
            │ Loop back to  │    │ Document findings           │
            │ Phase 2 with  │    │ Proceed with fix            │
            │ more verbosity│    └─────────────────────────────┘
            └───────────────┘
```

---

## RE-ANALYSIS MODE (After Fix Verification Fails)

### When to Use Re-Analysis Mode

**Use RE-ANALYSIS MODE when:**
- A fix was implemented and compiled (execute.md steps 8.5-8.7)
- The verification rerun (step 8.8) **FAILED**
- We need to analyze the NEW failure quickly

**RE-ANALYSIS MODE skips:**
- Phase 1 component discovery (we already know the components)
- Verbosity option discovery (reuse previous options)

**RE-ANALYSIS MODE goes directly to:**
- ULTRATHINK deep analysis of the new failure

### Re-Analysis Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│ RE-ANALYSIS MODE ENTRY POINT                                    │
│ (Triggered when fix verification fails in execute.md 8.8)       │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP R1: READ NEW run.log                                       │
│ • Navigate to same test directory                               │
│ • Read the new run.log after fix attempt                        │
│ • Note: Verbosity options from previous run still apply         │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP R2: QUICK COMPARISON                                       │
│ • Is this the SAME failure as before? → Fix didn't work         │
│ • Is this a DIFFERENT failure? → Fix broke something else       │
│ • Is test now PASSING? → Fix worked! (shouldn't be here)        │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                    ┌─────────────────────┐
                    │ Same or Different?  │
                    └─────────────────────┘
                     ↓ SAME           ↓ DIFFERENT
                     ↓                ↓
┌─────────────────────────────┐  ┌─────────────────────────────┐
│ STEP R3a: ULTRATHINK        │  │ STEP R3b: NEW COMPONENT?    │
│ Why didn't fix work?        │  │ • Check if new component    │
│ • Review the fix applied    │  │   is involved               │
│ • Trace through debug logs  │  │ • If yes → add verbosity    │
│ • Identify what was missed  │  │   for new component         │
│ • Refine the fix            │  │ • If no → ULTRATHINK on     │
└─────────────────────────────┘  │   new failure               │
                                 └─────────────────────────────┘
                              ↓
                    ┌─────────────────────┐
                    │ Need more verbosity │
                    │ for new component?  │
                    └─────────────────────┘
                     ↓ NO              ↓ YES
                     ↓                 ↓
┌─────────────────────────────┐  ┌─────────────────────────────┐
│ Proceed with revised fix    │  │ Go to Phase 2 (Step 4)      │
│ → Back to execute.md 8.5    │  │ Add verbosity for new       │
└─────────────────────────────┘  │ component, then rerun       │
                                 └─────────────────────────────┘
```

### Re-Analysis Steps

#### Step R1: Read New run.log

```bash
# Navigate to the same test directory used before
tcsh -c "cd <test_dir> && cat run.log"
```

#### Step R2: Compare Failures

**Check if this is the same failure:**
```bash
# Compare error signatures
tcsh -c "cd <test_dir> && grep -E 'UVM_ERROR|UVM_FATAL' run.log"
```

**Classification:**

| Scenario | Meaning | Action |
|----------|---------|--------|
| Same error, same location | Fix didn't address root cause | ULTRATHINK: Why didn't fix work? |
| Same error, different location | Partial fix, multiple instances | ULTRATHINK: Find remaining instances |
| Different error, same component | Fix broke something in component | ULTRATHINK: Analyze side effects |
| Different error, different component | Fix exposed new issue | Check if new component needs verbosity |
| No error (PASS) | Fix worked! | Should not be in re-analysis mode |

#### Step R3a: ULTRATHINK - Same Failure

If the failure is the same:

```
⚠️ ULTRATHINK: Why Didn't the Fix Work?

1. Review the fix that was applied:
   - What file was changed?
   - What was the intended effect?

2. Compare expected vs actual behavior:
   - What should have changed in the log?
   - What actually changed (or didn't)?

3. Identify the gap:
   - Was the wrong code path fixed?
   - Was the fix incomplete?
   - Is there another instance of the same bug?

4. Refine the fix:
   - What additional changes are needed?
   - Are there related files to check?
```

#### Step R3b: Different Failure - New Component Check

If the failure is different:

```bash
# Check if new component is involved
tcsh -c "cd <test_dir> && grep -oE 'umc_[a-z_]+' run.log | sort -u"

# Compare with previous component list
# If new component appears → need to add verbosity for it
```

**If new component needs verbosity:**
- Go back to Phase 2 (Step 4)
- Add verbosity options for the new component
- Rerun with additional -op flags

**If no new component:**
- Proceed with ULTRATHINK on the new failure
- Analyze what the fix broke
- Develop a revised fix

### Re-Analysis Output Format

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     RE-ANALYSIS REPORT                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│ Test: <suite>/<test>                                                        │
│ Fix Attempt: #<N>                                                           │
│ Previous Fix: <description of fix applied>                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│ FAILURE COMPARISON:                                                         │
│ • Previous error: <previous error signature>                                │
│ • Current error:  <current error signature>                                 │
│ • Status: [SAME | DIFFERENT | NEW_COMPONENT]                                │
├─────────────────────────────────────────────────────────────────────────────┤
│ ULTRATHINK FINDINGS:                                                        │
│ • Why fix didn't work: <explanation>                                        │
│ • Root cause refinement: <updated understanding>                            │
│ • Additional changes needed: <list>                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│ NEXT STEPS:                                                                 │
│ [ ] Apply revised fix → execute.md 8.5                                      │
│ [ ] Add verbosity for new component → Phase 2 Step 4                        │
│ [ ] Need waveform analysis → open FSDB                                      │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites - MUST DO FIRST

**Before starting any analysis**, set up the environment:

```bash
bootenv && echo $REPO_PATH
```

Use the displayed $REPO_PATH as your working directory for all subsequent commands.

---

## Step 1: Parse umc_triage Output

### Input: umc_triage Results

The `umc_triage` command (from execute.md) produces output showing test results:

```bash
umc_triage out/ -running
```

**Expected Output Format:**
```
Suite: <suite_name>
  PASS: <count>
  FAIL: <count>

Failed Tests:
  - <test_name_1> (signature: <error_signature>)
  - <test_name_2> (signature: <error_signature>)
```

### Extract Failing Tests

For each failing test from triage output:
1. Note the suite name
2. Note the test name
3. Note the error signature (if available)
4. Construct the test directory path:
   ```
   $REPO_PATH/out/linux*/umc*/config/<config>/run/umc/<suite>/<test>/test_dir
   ```

### Claude Code Action

**Parse the triage output and create a list of all failing tests:**

```bash
# Example: Navigate to a failing test directory
tcsh -c "cd $REPO_PATH/out/linux*/umc*/config/<config>/run/umc/<suite>/<test>/test_dir && pwd"
```

---

## Step 2: Initial Analysis of run.log (Phase 1)

### Purpose: Quick Assessment

This is the **initial analysis** to determine:
- What type of error occurred
- Which component is failing
- Whether there's enough debug info to understand the root cause
- Whether a rerun with more verbosity is needed

**Note**: ULTRATHINK is NOT used here. Save ULTRATHINK for Phase 3 (after rerun with verbosity).

### Read and Analyze run.log

For each failing test, thoroughly examine the `run.log` file:

```bash
tcsh -c "cd $REPO_PATH/out/linux*/umc*/config/<config>/run/umc/<suite>/<test>/test_dir && cat run.log"
```

### Error Pattern Identification

Search for specific error patterns:

```bash
# Search for all error types
tcsh -c "cd <test_dir> && grep -i 'UVM_ERROR\|UVM_FATAL\|assertion\|mismatch\|failed\|error' run.log"

# Search for warnings that might indicate root cause
tcsh -c "cd <test_dir> && grep -i 'UVM_WARNING\|warning' run.log"

# Get context around errors (5 lines before and after)
tcsh -c "cd <test_dir> && grep -B5 -A5 'UVM_ERROR\|UVM_FATAL' run.log"
```

### Error Classification

Categorize the failure type:

| Error Type | Pattern | Typical Components |
|------------|---------|-------------------|
| UVM_ERROR | `UVM_ERROR @` | Checker, Monitor, Scoreboard |
| UVM_FATAL | `UVM_FATAL @` | Critical component failure |
| Assertion | `Assertion.*failed` | RTL assertion, SVA |
| Mismatch | `mismatch\|expected.*actual` | Scoreboard, Checker |
| Timeout | `timeout\|watchdog` | Sequence, Driver |
| Protocol | `protocol.*violation` | UVC, Interface checker |

### Extract Failing Component Information

From the error messages, identify:

1. **Component Name**: The UVM component reporting the error
   - Example: `uvm_test_top.env.umc_dfi_agent.monitor` → Component: `umc_dfi`

2. **Checker Name**: The specific checker or assertion
   - Example: `umc_dfi_checker::check_cmd_decode` → Checker: `umc_dfi_checker`

3. **File Name**: The source file where error originates
   - Example: `umc_dfi_checker.sv:1234` → File: `umc_dfi_checker.sv`

4. **Error Severity**: UVM_ERROR, UVM_FATAL, assertion, etc.

**Claude Code Action - Document the following for each failure:**
```
Failing Test: <test_name>
Error Type: <UVM_ERROR|UVM_FATAL|assertion|etc>
Component: <component_name>
Checker: <checker_name>
File: <file_name:line_number>
Error Message: <full_error_message>
```

---

## Step 3: Identify Related Components (Phase 1)

### Purpose: Map Components for Verbosity

Identify components related to the failure so we can enable verbosity for them.

**Note**: This is a quick mapping for Phase 1. Deep component analysis with ULTRATHINK happens in Phase 3.

### Component Dependency Mapping

Once the primary failing component is identified, map ALL related/communicating components.

**Common Component Relationships:**

```
umc_dfi
├── umc_uvc (transaction source)
├── umc_ddr_bus (memory interface)
├── umc_top_env (top-level scoreboard)
└── umc_ecc (if ECC-related)

umc_beq / umc_client_beq
├── umc_rec_env (record environment)
├── umc_sbx_item (transaction items)
├── umc_cmd_sep (command separation)
└── umc_top_env (integration)

umc_data_scramble / umc_data_g7scramble
├── umc_encrypt (encryption block)
├── umc_dfi (data interface)
└── umc_ecc (error correction)

umc_hbm_training / umc_hbm_ppt
├── umc_dfi (DFI interface)
├── umc_hbm_* (HBM-specific blocks)
└── umc_top_env (integration)
```

### Find Related Components from Error Context

**Search for component mentions in run.log:**

```bash
# Find all component names mentioned in errors
tcsh -c "cd <test_dir> && grep -oE 'umc_[a-z_]+' run.log | sort -u"

# Look for hierarchy paths to understand component relationships
tcsh -c "cd <test_dir> && grep -E 'uvm_test_top\.[a-z_\.]+' run.log | head -20"
```

### Build Component List

**Create a complete list of components to enable verbosity for:**

1. **Primary Component**: The component reporting the error
2. **Upstream Components**: Components that send data/transactions to primary
3. **Downstream Components**: Components that receive data from primary
4. **Integration Component**: Usually `umc_top_env` for scoreboard/integration errors
5. **Interface Components**: UVCs and interface checkers

**Example Component List:**
```
Primary: umc_dfi
Related: umc_uvc, umc_ddr_bus, umc_ecc, umc_top_env
```

---

## Decision Point: Is Rerun Needed?

### Evaluate Current Debug Information

After initial analysis, determine if there's enough information to understand the root cause:

**Enough Info (NO rerun needed) if:**
- Error message clearly indicates the bug
- You can see the exact mismatch (expected vs actual)
- The failing code path is obvious from the log
- You can identify which RTL or TB code needs fixing

**NOT Enough Info (rerun WITH verbosity needed) if:**
- Error message is vague or generic
- Cannot see the transaction flow leading to error
- Multiple components involved but unclear which caused the issue
- Need to see internal state or debug prints

### Decision Action

```
IF enough_info:
    → Skip to Phase 3 (ULTRATHINK analysis)
    → Proceed with identifying the fix

ELSE (not enough info):
    → Continue to Step 4 (Discover Verbosity Options)
    → Prepare for rerun with verbosity
    → Invoke rerun.md
```

---

## Step 4: Discover Verbosity Options (Phase 2 - If Rerun Needed)

### Locate _env.plsvh Files

For EACH component in the list, find its environment file:

```bash
# Find all _env.plsvh files for identified components
find $REPO_PATH/src/verif/export -name "*_env.plsvh" | grep -E "umc_dfi|umc_uvc|umc_ecc"
```

**Common Block Locations:**

| Block | _env.plsvh Location |
|-------|---------------------|
| umc_dfi | `$REPO_PATH/src/verif/export/umc_dfi/umc_dfi_env.plsvh` |
| umc_uvc | `$REPO_PATH/src/verif/export/umc_uvc/umc_uvc_env.plsvh` |
| umc_ecc | `$REPO_PATH/src/verif/export/umc_ecc/umc_ecc_env.plsvh` |
| umc_beq | `$REPO_PATH/src/verif/export/umc_beq/umc_beq_env.plsvh` |
| umc_client_beq | `$REPO_PATH/src/verif/export/umc_client_beq/umc_client_beq_env.plsvh` |
| umc_ddr_bus | `$REPO_PATH/src/verif/export/umc_ddr_bus/umc_ddr_bus_env.plsvh` |
| umc_top_env | `$REPO_PATH/src/verif/export/umc_top_env/umc_top_env.plsvh` |
| umc_rec_env | `$REPO_PATH/src/verif/export/umc_rec_env/umc_rec_env.plsvh` |
| umc_sbx | `$REPO_PATH/src/verif/export/umc_sbx/umc_sbx_env.plsvh` |
| umc_data_scramble | `$REPO_PATH/src/verif/export/umc_data_scramble/umc_data_scramble_env.plsvh` |
| umc_hw_ppt | `$REPO_PATH/src/verif/export/umc_hw_ppt/umc_hw_ppt_agent.plsvh` |

### Search for Verbosity Switches

For EACH component's _env.plsvh file, find ALL verbosity-related switches:

```bash
# Search for DEBUG, DISPLAY, and VERBOSITY options
grep -E "int\s+\w*(DEBUG|DISPLAY|VERBOSITY)\w*\s*=" $REPO_PATH/src/verif/export/<block>/<block>_env.plsvh
```

### Verbosity Switch Types

**1. Boolean Switches (value: 0 or 1)**
```
umc_DFI_DEBUG_ALL = 0        → Use: -op "umc_DFI_DEBUG_ALL=1"
umc_DFI_DISPLAY_CMD_DCD = 0  → Use: -op "umc_DFI_DISPLAY_CMD_DCD=1"
```

**2. Level-Based Switches (value: 0 to N)**
```
umc_BEQ_ENV_VERBOSITY = 0    → Use: -op "umc_BEQ_ENV_VERBOSITY=<MAX_LEVEL>"
```

### CRITICAL: Find Maximum Level for Level-Based Switches

For ANY level-based switch, you MUST find the maximum valid level:

```bash
# Step 1: Search in the _env.plsvh file for case statements or mappings
grep -n "<FLAG_NAME>" $REPO_PATH/src/verif/export/<block>/<block>_env.plsvh

# Step 2: If not found, search entire block directory
grep -r "<FLAG_NAME>" $REPO_PATH/src/verif/export/<block>/ --include="*.sv" --include="*.svh" --include="*.plsvh"

# Look for patterns like:
#   case(<FLAG_NAME>) 'd0: UVM_NONE; 'd1: UVM_LOW; ... 'd4: UVM_FULL;
#   if(<FLAG_NAME> >= 3) ...
```

**Common Level Mappings:**
```
Level 0 → UVM_NONE (no output)
Level 1 → UVM_LOW (minimal output)
Level 2 → UVM_MEDIUM (moderate output)
Level 3 → UVM_HIGH (detailed output)
Level 4 → UVM_FULL (maximum output)
```

**ALWAYS use the MAXIMUM level found for comprehensive debugging.**

### **CRITICAL STEP - DETERMINE MAXIMUM VALUES FOR LEVEL-BASED FLAGS:**

**Why this is critical**: Using verbosity level "1" when maximum is "4" will give minimal debug output. Always find and use the maximum level for comprehensive debugging.

### WARNING: Never Change +UVM_VERBOSITY Flag

**NEVER EVER EVER** change the main `+UVM_VERBOSITY` flag in the rerun command.

- The `+UVM_VERBOSITY=UVM_NONE` or `+UVM_VERBOSITY=UVM_LOW` in the original command must remain unchanged
- This is a global UVM setting that affects ALL components and can flood logs with useless output
- Use block-specific `-op` flags (like `umc_SPAZ_CHECKER_VERBOSITY`, `umc_DFI_DEBUG_ALL`) for targeted debug
- Changing `+UVM_VERBOSITY` globally will make debug output unreadable and slow down simulation significantly

**DO NOT modify this flag - leave it exactly as it appears in the original rerun_command.**

**Remember**: There is NO LIMIT on the number of -op flags you can use. Add one for each block and component involved in the failure. Use the ACTUAL option names from the env files.

### Document All Verbosity Options

**Create a comprehensive table for each component:**

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ COMPONENT: umc_dfi                                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│ Switch Name                    │ Type    │ Max Level │ -op Flag             │
├─────────────────────────────────────────────────────────────────────────────┤
│ umc_DFI_DEBUG_ALL              │ Boolean │ 1         │ -op "umc_DFI_DEBUG_ALL=1" │
│ umc_DFI_DISPLAY_CMD_DCD_ALL    │ Boolean │ 1         │ -op "umc_DFI_DISPLAY_CMD_DCD_ALL=1" │
│ umc_DFI_DEBUG_RDDATA_MONITOR   │ Boolean │ 1         │ -op "umc_DFI_DEBUG_RDDATA_MONITOR=1" │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ COMPONENT: umc_beq                                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│ Switch Name                    │ Type    │ Max Level │ -op Flag             │
├─────────────────────────────────────────────────────────────────────────────┤
│ umc_BEQ_ENV_VERBOSITY          │ Level   │ 4         │ -op "umc_BEQ_ENV_VERBOSITY=4" │
│ umc_BEQ_DEBUG_ALL              │ Boolean │ 1         │ -op "umc_BEQ_DEBUG_ALL=1" │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Step 5: Build Rerun Command with Verbosity

### Read Existing rerun_command

First, get the base command from the test directory:

```bash
tcsh -c "cd $REPO_PATH/out/linux*/umc*/config/<config>/run/umc/<suite>/<test>/test_dir && cat rerun_command"
```

### Construct Complete Rerun Command

Build the command with ALL identified verbosity options:

```bash
tcsh -c "source /proj/verif_release_ro/cbwa_initscript/current/cbwa_init.bash && \
bootenv -v <VARIANT> -o \$REPO_PATH && \
run_job [... copy all run_job args from rerun_command ...] \
  -op \"<COMPONENT1_DEBUG_ALL>=1\" \
  -op \"<COMPONENT1_SPECIFIC_OPTION>=1\" \
  -op \"<COMPONENT2_DEBUG_ALL>=1\" \
  -op \"<COMPONENT2_VERBOSITY>=<MAX_LEVEL>\" \
  -op \"<COMPONENT3_DEBUG_ALL>=1\" \
  ... \
  -fsdb \
  -r \"select[(type==RHEL8_64) && swp>20 && tmp>2048 && (csbatch || tmpshortrr || gb16 || gb32)] rusage[mem=20000]\" \
  -lsf"
```

### MANDATORY Flags

Every rerun command MUST include:
- **`-fsdb`**: Enable waveform capture
- **`-r "select[...]"`**: LSF resource requirements
- **`-lsf`**: Submit to LSF

---

## Step 6: Display Verbosity Options Summary

### MANDATORY: Display Before Execution

**Before executing any rerun, Claude MUST display a summary of verbosity options being added:**

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     VERBOSITY OPTIONS SUMMARY                                │
├─────────────────────────────────────────────────────────────────────────────┤
│ Test: <suite>/<test>                                                        │
│ Primary Failure: <component> - <error_type>                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│ COMPONENT           │ VERBOSITY FLAGS ADDED                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│ umc_dfi (primary)   │ -op "umc_DFI_DEBUG_ALL=1"                            │
│                     │ -op "umc_DFI_DISPLAY_CMD_DCD_ALL=1"                   │
├─────────────────────────────────────────────────────────────────────────────┤
│ umc_uvc (upstream)  │ -op "umc_UVC_DEBUG_ALL=1"                            │
│                     │ -op "umc_UVC_VERBOSITY=4"                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ umc_top_env (integ) │ -op "umc_TOP_ENV_DEBUG_ALL=1"                        │
├─────────────────────────────────────────────────────────────────────────────┤
│ TOTAL -op FLAGS: 5                                                          │
└─────────────────────────────────────────────────────────────────────────────┘

Additional Flags:
  -fsdb     : Waveform capture enabled
  -lsf      : LSF job submission
  -r "..."  : Resource requirements
```

**This display is MANDATORY before every rerun command execution.**

---

## Step 7: Invoke rerun.md for Execution

### Hand Off to rerun.md

After displaying the verbosity summary, **invoke rerun.md** to execute the rerun.

**Pass the following to rerun.md:**
1. Test path(s)
2. Variant
3. All -op flags identified in Steps 4-5

**rerun.md will:**
- Navigate to test directory
- Read rerun_command
- Execute with provided -op flags
- Submit tests in parallel
- Monitor every 5 minutes

### Wait for Rerun to Complete

After invoking rerun.md, wait for all tests to complete before proceeding to Phase 3.

---

## Step 8: Deep Analysis with ULTRATHINK (Phase 3)

### ⚠️ ULTRATHINK IS MANDATORY FOR THIS STEP

**After rerun completes, return to analyze.md and use ULTRATHINK for deep analysis.**

This is where the real debugging happens. With verbose output now available:

### Read New Verbose run.log

```bash
tcsh -c "cd <test_dir> && cat run.log"
```

### ULTRATHINK: Deep Root Cause Analysis

**Claude MUST use extended thinking (ultrathink) to:**

1. **Trace the Transaction Flow**
   - Follow transactions from source to destination
   - Identify where the error was introduced
   - Understand the sequence of events leading to failure

2. **Analyze Debug Output**
   - Read through the verbose debug prints
   - Correlate timestamps across components
   - Identify unexpected state or data

3. **Identify Root Cause**
   - Determine the exact source of the bug
   - Identify whether it's RTL or TB issue
   - Pinpoint the file and line number if possible

4. **Determine Fix or Next Steps**
   - If root cause found → Document and proceed with fix
   - If still unclear → Identify what additional verbosity is needed
   - If more verbosity needed → Loop back to Step 4

### ULTRATHINK Output Format

After ULTRATHINK analysis, document:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     ROOT CAUSE ANALYSIS (ULTRATHINK)                         │
├─────────────────────────────────────────────────────────────────────────────┤
│ Test: <suite>/<test>                                                        │
│ Analysis Iteration: <1st, 2nd, etc>                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│ FINDINGS:                                                                   │
│ • Transaction flow: <description>                                           │
│ • Error introduced at: <component/time>                                     │
│ • Root cause: <description>                                                 │
│ • Failing code: <file:line>                                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│ NEXT STEPS:                                                                 │
│ [ ] Root cause identified - proceed with fix                                │
│ [ ] Need more verbosity - loop back to Phase 2                              │
│ [ ] Need waveform analysis - open FSDB                                      │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Decision: Iterate or Fix

```
IF root_cause_found:
    → Document the bug
    → Identify the fix
    → Proceed with code changes

ELSE (need more info):
    → Identify additional components to enable verbosity
    → Loop back to Step 4 (Phase 2)
    → Rerun with more verbosity
    → Return here for another ULTRATHINK iteration
```

---

## Complete Workflow Summary

```
                      ANALYZE.MD ITERATIVE WORKFLOW
                      ═════════════════════════════

╔═════════════════════════════════════════════════════════════════════════════╗
║                           PHASE 1: INITIAL ANALYSIS                         ║
╚═════════════════════════════════════════════════════════════════════════════╝

┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 1: PARSE TRIAGE OUTPUT                                                 │
│ ─────────────────────────────────────────────────────────────────────────── │
│ Input: umc_triage out/ -running                                             │
│ Output: List of failing tests with signatures                               │
└─────────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 2: INITIAL ANALYSIS OF run.log                                         │
│ ─────────────────────────────────────────────────────────────────────────── │
│ • Read run.log from test_dir                                                │
│ • Identify error type (UVM_ERROR, UVM_FATAL, assertion, etc.)               │
│ • Extract failing component name                                            │
│ • Quick assessment - NO ULTRATHINK yet                                      │
└─────────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 3: MAP RELATED COMPONENTS                                              │
│ ─────────────────────────────────────────────────────────────────────────── │
│ • Primary: Component reporting the error                                    │
│ • Upstream/Downstream: Related components                                   │
│ • Quick mapping for verbosity selection                                     │
└─────────────────────────────────────────────────────────────────────────────┘
                                    ↓
                    ┌─────────────────────────────┐
                    │   DECISION: Enough Info?   │
                    └─────────────────────────────┘
                      ↓ NO                    ↓ YES
                      ↓                       └──────→ Skip to PHASE 3
                      ↓

╔═════════════════════════════════════════════════════════════════════════════╗
║                    PHASE 2: RERUN WITH VERBOSITY                            ║
╚═════════════════════════════════════════════════════════════════════════════╝

┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 4: DISCOVER VERBOSITY OPTIONS                                          │
│ ─────────────────────────────────────────────────────────────────────────── │
│ For EACH component:                                                         │
│ • Find <block>_env.plsvh file                                               │
│ • grep for DEBUG, DISPLAY, VERBOSITY switches                               │
│ • For level-based: Find MAXIMUM level                                       │
│ • Document all -op flags to add                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 5: BUILD RERUN COMMAND                                                 │
│ ─────────────────────────────────────────────────────────────────────────── │
│ • Append ALL -op flags                                                      │
│ • Append -fsdb, -r "select[...]", -lsf (MANDATORY)                          │
└─────────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 6: DISPLAY VERBOSITY SUMMARY (MANDATORY)                               │
│ ─────────────────────────────────────────────────────────────────────────── │
│ • Show all -op flags being added                                            │
│ • Display before execution                                                  │
└─────────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 7: INVOKE rerun.md                                                     │
│ ─────────────────────────────────────────────────────────────────────────── │
│ • Hand off to rerun.md with test paths and -op flags                        │
│ • rerun.md executes and monitors                                            │
│ • Wait for tests to complete                                                │
└─────────────────────────────────────────────────────────────────────────────┘
                                    ↓

╔═════════════════════════════════════════════════════════════════════════════╗
║              PHASE 3: DEEP ANALYSIS ⚠️ ULTRATHINK                           ║
╚═════════════════════════════════════════════════════════════════════════════╝

┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 8: ULTRATHINK DEEP ANALYSIS                                            │
│ ─────────────────────────────────────────────────────────────────────────── │
│ • Return to analyze.md after rerun completes                                │
│ • Read new verbose run.log                                                  │
│ • ⚠️ ULTRATHINK: Trace transaction flow                                     │
│ • ⚠️ ULTRATHINK: Analyze debug output                                       │
│ • ⚠️ ULTRATHINK: Identify root cause                                        │
│ • Document findings                                                         │
└─────────────────────────────────────────────────────────────────────────────┘
                                    ↓
                    ┌─────────────────────────────┐
                    │  Root Cause Found?         │
                    └─────────────────────────────┘
                      ↓ NO                    ↓ YES
                      ↓                       ↓
            ┌─────────────────┐      ┌─────────────────────────┐
            │ Loop back to    │      │ Document bug            │
            │ PHASE 2 with    │      │ Proceed with fix        │
            │ more verbosity  │      │ END                     │
            └─────────────────┘      └─────────────────────────┘
```

---

## Example: Complete Analysis Flow

### Scenario: DFI Command Decode Error

**Step 1: Parse Triage Output**
```
umc_triage output shows:
  FAIL: test_dfi_write_basic (signature: CMD_DECODE_MISMATCH)
```

**Step 2: Analyze run.log**
```bash
tcsh -c "cd $REPO_PATH/out/linux*/umc9_3/config/umc_dfi_tb/run/umc/sanity/test_dfi_write_basic/test_dir && grep -B5 -A5 'UVM_ERROR' run.log"
```

**Error Found:**
```
UVM_ERROR @ 1234567ns: uvm_test_top.env.umc_dfi_agent.checker [umc_DFI_CHECKER]
Command decode mismatch: expected=WRITE, actual=READ
  File: umc_dfi_checker.sv:456
```

**Step 3: Map Related Components**
```
Primary: umc_dfi (command decode error)
Related: umc_uvc (transaction source), umc_top_env (integration)
```

**Step 4: Discover Verbosity Options**

```bash
# umc_dfi
grep -E "int\s+\w*(DEBUG|DISPLAY|VERBOSITY)\w*\s*=" $REPO_PATH/src/verif/export/umc_dfi/umc_dfi_env.plsvh
# Found: umc_DFI_DEBUG_ALL, umc_DFI_DISPLAY_CMD_DCD_ALL, umc_DFI_DEBUG_CMD_MONITOR

# umc_uvc
grep -E "int\s+\w*(DEBUG|DISPLAY|VERBOSITY)\w*\s*=" $REPO_PATH/src/verif/export/umc_uvc/umc_uvc_env.plsvh
# Found: umc_UVC_DEBUG_ALL, umc_UVC_VERBOSITY (level-based, max=4)

# umc_top_env
grep -E "int\s+\w*(DEBUG|DISPLAY|VERBOSITY)\w*\s*=" $REPO_PATH/src/verif/export/umc_top_env/umc_top_env.plsvh
# Found: umc_TOP_ENV_DEBUG_ALL
```

**Step 5: Build Rerun Command**

Read base command:
```bash
tcsh -c "cd <test_dir> && cat rerun_command"
```

**Step 6: Display Verbosity Summary**

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     VERBOSITY OPTIONS SUMMARY                                │
├─────────────────────────────────────────────────────────────────────────────┤
│ Test: sanity/test_dfi_write_basic                                           │
│ Primary Failure: umc_dfi - CMD_DECODE_MISMATCH                              │
├─────────────────────────────────────────────────────────────────────────────┤
│ COMPONENT           │ VERBOSITY FLAGS ADDED                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│ umc_dfi (primary)   │ -op "umc_DFI_DEBUG_ALL=1"                            │
│                     │ -op "umc_DFI_DISPLAY_CMD_DCD_ALL=1"                   │
│                     │ -op "umc_DFI_DEBUG_CMD_MONITOR=1"                     │
├─────────────────────────────────────────────────────────────────────────────┤
│ umc_uvc (upstream)  │ -op "umc_UVC_DEBUG_ALL=1"                            │
│                     │ -op "umc_UVC_VERBOSITY=4"                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ umc_top_env (integ) │ -op "umc_TOP_ENV_DEBUG_ALL=1"                        │
├─────────────────────────────────────────────────────────────────────────────┤
│ TOTAL -op FLAGS: 6                                                          │
└─────────────────────────────────────────────────────────────────────────────┘

Additional Flags:
  -fsdb     : Waveform capture enabled
  -lsf      : LSF job submission
  -r "..."  : Resource requirements
```

**Step 7: Execute Rerun**

```bash
tcsh -c "source /proj/verif_release_ro/cbwa_initscript/current/cbwa_init.bash && \
bootenv -v umc9_3 -o \$REPO_PATH && \
run_job -design umc9_3 -config umc_dfi_tb [...all args from rerun_command...] \
  -op \"umc_DFI_DEBUG_ALL=1\" \
  -op \"umc_DFI_DISPLAY_CMD_DCD_ALL=1\" \
  -op \"umc_DFI_DEBUG_CMD_MONITOR=1\" \
  -op \"umc_UVC_DEBUG_ALL=1\" \
  -op \"umc_UVC_VERBOSITY=4\" \
  -op \"umc_TOP_ENV_DEBUG_ALL=1\" \
  -fsdb \
  -r \"select[(type==RHEL8_64) && swp>20 && tmp>2048 && (csbatch || tmpshortrr || gb16 || gb32)] rusage[mem=20000]\" \
  -lsf" | tee test_dfi_write_basic_rerun.log &
```

---

## Integration with execute.md

This guide (analyze.md) is designed to be invoked from execute.md after the triage step.

**In execute.md workflow:**
1. Execute tests → umc_triage → identify failures
2. For failures that need deep analysis, invoke analyze.md
3. analyze.md performs: failure analysis → component mapping → verbosity discovery → rerun

**Transition Point:**
```
execute.md Step 5 (triage) → analyze.md (if failures need debugging)
```

---

## Critical Notes

1. **ALWAYS display verbosity summary before execution** - This is mandatory
2. **Use maximum verbosity levels** - Search for and use the highest valid level for level-based flags
3. **Map ALL related components** - Don't stop at the first error; trace the entire failure path
4. **Use tcsh -c for all commands** - The test environment requires tcsh
5. **Include -fsdb, -r, and -lsf flags** - These are mandatory for every rerun
6. **Submit multiple tests in parallel** - Don't wait for each test to complete
7. **Monitor every 5 minutes** - Use bjobs to check all jobs together
8. **Unlimited -op flags** - Add as many as needed for comprehensive debug coverage

---

## Quick Reference: Common Component Verbosity Patterns

| Component | Primary Debug Flag | Additional Flags |
|-----------|-------------------|------------------|
| umc_dfi | umc_DFI_DEBUG_ALL | umc_DFI_DISPLAY_CMD_DCD_ALL, umc_DFI_DEBUG_*_MONITOR |
| umc_uvc | umc_UVC_DEBUG_ALL | umc_UVC_VERBOSITY (level-based) |
| umc_beq | umc_BEQ_DEBUG_ALL | umc_BEQ_ENV_VERBOSITY (level-based) |
| umc_ecc | umc_ECC_DEBUG_ALL | umc_ECC_DISPLAY_* |
| umc_ddr_bus | umc_DDR_BUS_DEBUG_ALL | Protocol-specific options |
| umc_top_env | umc_TOP_ENV_DEBUG_ALL | Scoreboard-specific options |
| umc_client_beq | umc_CLIENT_BEQ_DEBUG_ALL | umc_CLIENT_BEQ_VERBOSITY |
| umc_rec_env | umc_REC_ENV_DEBUG_ALL | umc_REC_ENV_VERBOSITY |

**Note**: Always verify actual switch names by reading the _env.plsvh file - these are common patterns, not guarantees.

---

**Version:** 1.3
**Last Updated:** 2026-01-19

**Change Log:**
- v1.3: Added RE-ANALYSIS MODE for when fix verification fails - skips component discovery, goes directly to ULTRATHINK
- v1.2: Initial iterative workflow with ULTRATHINK phases
