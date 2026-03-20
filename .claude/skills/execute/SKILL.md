# Execute Skill

Run RTL simulations, test suites, and individual testcases with automatic build verification and failure analysis.

## Trigger
`/execute`

## Workflow

When the user provides a prompt about running tests, Claude should:
1. **Auto-infer** the variant, suite, and/or testcase from the user's prompt
2. **No questions asked** - proceed automatically based on inference
3. Check build exists, compile if needed, then run tests
4. After run completes, triage and analyze failures

---

## Required Permissions

**IMPORTANT:** The following permissions must be configured in `~/.claude/settings.json` for test execution to work:

```json
{
  "permissions": {
    "allow": [
      "Bash(tcsh -c 'source /proj/verif_release_ro/cbwa_initscript/current/cbwa_init.csh*)",
      "Bash(tcsh:*)",
      "Bash(umc_triage:*)"
    ]
  }
}
```

These permissions allow:
- Sourcing the CBWA init scripts and running be_dj commands in tcsh
- Running umc_triage for test result analysis

**Note:** The `bootenv` command is an alias that doesn't work in non-interactive shells. Instead, we directly source the underlying script:
```
/proj/verif_release_ro/cbwa_bootcore/current/bin/_bootenv.csh -v <variant>
```

---

## Environment Initialization

**CRITICAL:** The `bootenv` command is an **alias** that only works in interactive shells. When using `tcsh -c` (non-interactive), aliases don't expand properly.

**SOLUTION:** Directly source BOTH underlying scripts that set up the environment:

```bash
source /proj/verif_release_ro/cbwa_initscript/current/cbwa_init.csh
source /proj/verif_release_ro/cbwa_bootcore/current/bin/_bootenv.csh -v <variant>
```

This bypasses the `bootenv` alias and works in non-interactive shells.

**NOTE:** Always use **single quotes** for `tcsh -c` commands, and use `'\''` to escape single quotes within the command.

---

## Workflow Overview

```
Infer Variant/Suite/Test → Check Build → Compile if Needed → Run Tests → Triage → Analyze Failures → Fix
```

---

## Temporary File Management

**IMPORTANT: All temporary files must be created in `$REPO_PATH/` only.**

**Cleanup Rules:**
- **After successful test run:** Remove all temporary files created during the workflow
- **After successful build:** Remove all temporary files created during compilation
- **Temporary files include:** Log files (unless explicitly needed for reference), intermediate scripts, debug outputs, etc.
- **Keep only:** Files that are needed for user reference or debugging (e.g., final run logs, triage outputs)

---

## Step 1: Infer from User Prompt

**Extract the following from user's message:**
- **Variant**: umc*, etc.
- **Suite**: Suite name (e.g., sdp_dfi_tb, beq_real_phy_tb, sanity)
- **Testcase**: Specific test name or "*" for all tests

**Inference Priority:**
1. Explicit mention in user prompt (e.g., "run sanity on umc9_3")
2. Context from previous conversation
3. Check `out/linux*/umc*/` directory structure

**Examples of inference:**
- "run sanity tests" → Suite: sanity, Test: "*", Variant: infer from out/ directory
- "run dfi_basic_test on umc9_3" → Suite: infer from test name, Test: dfi_basic_test, Variant: umc9_3
- "run all tests for umc13_1a" → Suite: all available, Test: "*", Variant: umc13_1a
- "run sdp_dfi_tb" → Suite: sdp_dfi_tb, Test: "*", Variant: infer from out/ directory

**DO NOT ask the user any questions. Infer everything from context.**

---

## Step 1.5: Find Correct Suite Name from DJ Files

**CRITICAL:** The suite name used in the `run_test -s <SUITE>` command must match the suite definition in the DJ files.

**NOTE:** Always try to use `grep` as the first choice of command for any searches.

### Suite Definition Files
Suites are defined in: **`$REPO_PATH/src/test/suites/umc/*.dj`**

### How to Find the Correct Suite Name

1. **If user provides a test name** (e.g., `unit_recbeq_test_dual_slot_wr_rd_*`):
   - Search for the test in the DJ files:
     ```bash
     grep -l "unit_recbeq_test_dual_slot" $REPO_PATH/src/test/suites/umc/*.dj
     ```
   - Read the file and find the `suite :SUITE_NAME do` declaration
   - The suite name is what follows `suite :` (e.g., `suite :unit_recbeq_tb` → suite name is `unit_recbeq_tb`)

2. **Look at the suite declaration** at the top of the file:
   ```ruby
   suite :unit_recbeq_tb do  # ← Suite name is "unit_recbeq_tb"
   ```

3. **Common suite naming patterns:**
   - File `unit_recbeq.dj` contains suite `unit_recbeq_tb`
   - File `beq.dj` contains suite `beq_dfi_tb`, `beq_real_phy_tb`, etc.
   - The `_tb` suffix is typically required

### Reference: ultrasmoke.yml and release_gate.yml

Check these YAML files for the correct `sim_cmd` configuration:

**Primary config files:**
- `$REPO_PATH/src/verif/tb/etc/ultrasmoke.yml`
- `$REPO_PATH/src/verif/tb/etc/release_gate.yml`

**Structure of these files:**
```yaml
umc9_3_umc_unit_recbeq_tb:
   design: umc9_3
   action: buildflow::simulator(:umc_unit_recbeq_tb).sim_build
   supplement: -DPPR_LINT_OFF -Dumc_UNIT_RECBEQ_TB
   sim_cmd: >-
      be_dj -Dumc_UNIT_RECBEQ_TB --bootenv_v umc9_3 -x umc9_3 ... run_test -s unit_recbeq_tb "unit_recbeq_test_*" ...
```

**Key fields to extract:**
- `sim_cmd` - The actual command to run tests (use this as template)
- `supplement` - DJ defines required (e.g., `-Dumc_UNIT_RECBEQ_TB`)
- `design` - The variant name

### Example: Finding Suite for unit_recbeq Tests

1. User wants to run: `unit_recbeq_test_dual_slot_wr_rd_*`
2. Search: `grep -l "unit_recbeq_test" src/test/suites/umc/*.dj` → finds `unit_recbeq.dj`
3. Read `unit_recbeq.dj`: `suite :unit_recbeq_tb do` → suite name is `unit_recbeq_tb`
4. Check `ultrasmoke.yml` for `umc9_3_umc_unit_recbeq_tb`:
   - Requires define: `-Dumc_UNIT_RECBEQ_TB`
   - Suite: `unit_recbeq_tb`
5. Use command: `be_dj -Dumc_UNIT_RECBEQ_TB ... run_test -s unit_recbeq_tb "unit_recbeq_test_dual_slot_wr_rd_*"`

---

## Step 2: Check Build Exists and Determine if Recompile Needed

Before running any tests, verify the build exists AND is up-to-date:

### Step 2.1: Check if Build Directory Exists

```bash
ls -la out/linux*/<variant>/
```

**If build directory does NOT exist or is empty** → Proceed to Step 3 (Compile First)

**If build directory exists** → Continue to Step 2.2

### Step 2.2: Check if Recompile is Needed

Even if a build exists, source code may have changed since the last compile. Compare timestamps to determine if recompile is needed.

**Find the compile timestamp (use the pub directory or build log):**
```bash
# Get the timestamp of the pub directory (build output) for the target testbench
# NOTE: simv may not exist in all build systems - use pub/ directory as reference
ls -la %Y out/linux*/<variant>/config/<tb_config>/pub 2>/dev/null
# Or check the compile log timestamp
ls -la %Y out/linux*/<variant>/config/<tb_config>/compile.log 2>/dev/null
```

**Find the most recent source file modification:**
```bash
# Check key source directories for files modified after the compile
# IMPORTANT: Include all source file extensions: .sv, .v, .svh, .vh, .plsv, .plsvh, .plv
find src/rtl src/verif -type f \( -name "*.sv" -o -name "*.v" -o -name "*.svh" -o -name "*.vh" -o -name "*.plsv" -o -name "*.plsvh" -o -name "*.plv" \) -newer out/linux*/<variant>/config/<tb_config>/pub 2>/dev/null | head -5
```

**Decision Logic:**

| Condition | Action |
|-----------|--------|
| Build directory missing | Compile (Step 3) |
| pub/ directory missing | Compile (Step 3) |
| Source files newer than pub/ | Recompile (Step 3) |
| pub/ is newer than all source files | Proceed to Run Tests (Step 4) |

**Source file extensions to check:** `.sv`, `.v`, `.svh`, `.vh`, `.plsv`, `.plsvh`, `.plv`

**Quick check command (returns count of files needing recompile):**
```bash
# If this returns > 0, recompile is needed
find src/rtl src/verif -type f \( -name "*.sv" -o -name "*.v" -o -name "*.svh" -o -name "*.vh" -o -name "*.plsv" -o -name "*.plsvh" -o -name "*.plv" \) -newer out/linux*/<variant>/config/<tb_config>/pub 2>/dev/null | wc -l
```

**If recompile is needed, inform the user:**
```
Build exists but source files have been modified since last compile.
Modified files detected: <count> files
Example: <first few modified files>
Recompiling...
```

---

## Step 3: Compile if Needed (Using compile.md)

If build doesn't exist or source files are newer than the build, compile the variant first.

**IMPORTANT: Always use `_md/compile.md` for compilation.**

### Compilation Workflow

1. **Read and follow `_md/compile.md`** for the complete compilation process
2. The compile.md guide will:
   - Infer variant and target from context (or ask if unclear)
   - Get $REPO_PATH
   - Read release_gate.yml for correct build configuration
   - Construct and execute the proper build command
   - Monitor build progress
   - Handle errors and recompile if needed

3. **Wait for compile to complete before proceeding to run tests**
4. Verify build success by checking `failed_cmd_count = 0` in the build log

### Quick Reference (for context only - use compile.md for actual compilation)

The compile.md will construct commands based on release_gate.yml, similar to:
```bash
tcsh -c 'source .../cbwa_init.csh; source .../_bootenv.csh -v <variant>; dj -x <design> -J lsf -m 31 --gcf_opts '\''<gcf_options>'\'' <supplement> -e '\''<action>'\''' 2>&1 | tee build_<variant>_<target>.log
```

**DO NOT manually construct compile commands - always use compile.md.**

---

## Step 4: Run Tests

### Command Source
Run commands are defined in these YAML files (check both for your target):
- **`$REPO_PATH/src/verif/tb/etc/ultrasmoke.yml`** - Primary smoke test configurations
- **`$REPO_PATH/src/verif/tb/etc/release_gate.yml`** - Release gate configurations

Read these files to get the correct `sim_cmd` configuration for the variant and suite.

### Command Template

**Basic template (for most suites):**
```bash
tcsh -c 'source /proj/verif_release_ro/cbwa_initscript/current/cbwa_init.csh; source /proj/verif_release_ro/cbwa_bootcore/current/bin/_bootenv.csh -v <VARIANT>; be_dj --bootenv_v <VARIANT> -x <VARIANT> --abort_on_error 0 -J lsf -m 100 --gcf_opts '\''queue:"regr_high", name:"dj", mem:10000, select:"type==RHEL8_64", lsf_native:"-P rtg-mcip-ver -G rtg-mcip-ver.ultrasmoke.user -W 1000"'\'' run_test -s <SUITE> "<TEST>" -a run_only' 2>&1 | tee run_<VARIANT>_<SUITE>.log
```

**Template with DJ defines (when required by ultrasmoke.yml/release_gate.yml):**
```bash
tcsh -c 'source /proj/verif_release_ro/cbwa_initscript/current/cbwa_init.csh; source /proj/verif_release_ro/cbwa_bootcore/current/bin/_bootenv.csh -v <VARIANT>; be_dj <DJ_DEFINES> --bootenv_v <VARIANT> -x <VARIANT> --abort_on_error 0 -J lsf -m 100 --gcf_opts '\''queue:"regr_high", name:"dj", mem:10000, select:"type==RHEL8_64", lsf_native:"-P rtg-mcip-ver -G rtg-mcip-ver.ultrasmoke.user -W 1000"'\'' run_test -s <SUITE> "<TEST>" -a run_only' 2>&1 | tee run_<VARIANT>_<SUITE>.log
```

**Note on quote escaping:** Use `'\''` to include single quotes within a single-quoted tcsh command.

### When DJ Defines Are Required

Check the `supplement` field in ultrasmoke.yml/release_gate.yml for your target. If it contains defines like `-Dumc_UNIT_RECBEQ_TB`, add them to the be_dj command.

**Example:** For `unit_recbeq_tb` suite:
```yaml
# From ultrasmoke.yml:
umc9_3_umc_unit_recbeq_tb:
   supplement: -DPPR_LINT_OFF -Dumc_UNIT_RECBEQ_TB  # ← These defines are needed
   sim_cmd: be_dj -Dumc_UNIT_RECBEQ_TB ...          # ← Define added to be_dj
```

Add `-Dumc_UNIT_RECBEQ_TB` to your be_dj command:
```bash
be_dj -Dumc_UNIT_RECBEQ_TB --bootenv_v umc9_3 -x umc9_3 ... run_test -s unit_recbeq_tb "unit_recbeq_test_*"
```

**Output Capture with tee:**
- The run output is captured to `run_<VARIANT>_<SUITE>.log` using `tee`
- Run command in background using Claude's `run_in_background` parameter
- Monitor the log file to track test progress
- Keep log file after task completion for reference

### Parameters
- `<VARIANT>` - Auto-inferred design variant
- `<SUITE>` - Auto-inferred suite name
- `<TEST>` - Auto-inferred test name or "*" for all tests
- `-m 100` - Maximum parallel jobs (always use 100)
- `-a run_only` - Run only mode

### Run in Background
Execute the command in background using Claude's `run_in_background` parameter (NOT shell `&`).

### Run Monitoring

Monitor run progress every **5 minutes** by reading the log file.

**CRITICAL: Strict 5-Minute Wait Requirement**
- **MUST wait exactly 300 seconds (5 minutes) between each log check**
- Execute: `sleep 300` in background before checking the log
- **VERIFY that sleep 300 has completed** before reading the log file:
  - Check your background tasks to confirm sleep has finished
  - Use `/tasks` command or check task status
  - **DO NOT** read the log until you verify sleep is complete
- **DO NOT** check the log before the full 5 minutes have elapsed
- This is a **STRICT** requirement - no exceptions
- After sleep completes, THEN check the log file
- Repeat: sleep 300 → verify completion → check log → sleep 300 → verify completion → check log (until run completes)

**Monitoring Cycle:**
```
1. Execute run command (with tee to log file)
2. Execute: sleep 300 (in background)
3. Check background tasks to verify sleep 300 has completed
4. ONLY after verification: Read log file to check progress
5. If run not complete: goto step 2
6. If run complete: proceed to triage
```

**IMPORTANT: Handling Stagnant Log Output**
- **There may be instances where the log output doesn't change for a while**
- **DO NOT try to debug this** - this is normal behavior
- Tests are still running in the background on LSF
- **Keep monitoring** the log file every 5 minutes (after sleep 300)
- **Continue until you see the end of the run** (completion message or all jobs finished)
- Do NOT assume the run has hung or failed just because output is stagnant

### Log File Retention
**IMPORTANT: Always keep the run log file regardless of run outcome.**

**Log file:** `run_<variant>_<suite>.log`

**Retention rules:**
1. **Keep the log file** for reference after run completes
2. Log file will be used for triage analysis

---

## Step 5: Triage Results

**CRITICAL: ALWAYS run umc_triage after tests complete, even for a single test.**

After the run completes, execute the triage command:

```bash
tcsh -c 'source /proj/verif_release_ro/cbwa_initscript/current/cbwa_init.csh; source /proj/verif_release_ro/cbwa_bootcore/current/bin/_bootenv.csh -v <VARIANT>; umc_triage $REPO_PATH/out/ -running'
```

**Note:** The `umc_triage` command must be run within the bootenv environment. Replace `<VARIANT>` with the variant being tested.

**NEVER skip running umc_triage - even when running a single test.**

### Triage Output Analysis
The triage command outputs:
- **PASS** - Number of passing tests
- **FAIL** - Number of failing tests
- **RUNNING** - Tests still in progress
- **PASS_RATE** - Overall pass percentage
- **Fail signatures** - Grouped by signature type with:
  - Percentage contribution of each signature
  - List of failing tests with **runtime in seconds**
- **Running tests** - Tests still in progress

### Calculate Pass Rate
```
Pass Rate = (Tests Passed / Total Tests) * 100
```

### Identify Top Signatures
From the triage output:
1. Group failures by signature
2. Count occurrences of each signature
3. Rank signatures by frequency (highest first)
4. Calculate how many signatures need to be fixed to reach 75% pass rate

---

## Step 6: Report to User and Ask About Fixing

Present the following to the user:

```
**Triage Summary:**
- Total Tests: X
- Passed: Y (Z%)
- Failed: W

**Top Failing Signatures:**
1. <signature_1> - N failures
2. <signature_2> - M failures
3. <signature_3> - K failures
...

**To reach 75% pass rate:**
- Current pass rate: Z%
- Need to fix: <list of top signatures>
- Estimated tests to fix: <count>
```

**CRITICAL: Use AskUserQuestion to ask:**

```
Would you like me to analyze and attempt to fix these failing tests?
- Yes: I will analyze failures using rerun.md, make fixes using perforce.md, recompile, and verify
- No: I will return control to you
```

**This is the ONLY question asked to the user in this workflow.**

---

## Step 7: If User Says No

Return control to the user. End the workflow.

---

## Step 8: If User Says Yes - Analyze and Fix Workflow

**CRITICAL WORKFLOW ORDER:**
```
Select Test → Deep Analysis (analyze.md) → Rerun with Debug (rerun.md) →
Develop Fix → Edit Files (perforce.md) → Recompile (compile.md) →
Rerun to Verify → Repeat for Next Signature
```

### 8.1 Select Representative Test
- Pick **one test per signature** that had the **least run time**
- Shorter tests are faster to debug and rerun

### 8.2 Navigate to Failing Directory
Each failing test has a directory structure:
```
out/linux*/<variant>/<suite>/<test_name>/
```

### 8.3 Deep Analysis Using analyze.md

**IMPORTANT: FIRST use `_md/analyze.md` to deeply analyze the failure BEFORE rerunning.**

The analyze.md guide performs comprehensive failure analysis:

1. **Read and follow `$REPO_PATH/_md/analyze.md`** for the complete analysis process
2. The analyze.md guide will:
   - Read the run.log and identify the exact failure point
   - Parse UVM_ERROR/UVM_FATAL messages and stack traces
   - Identify the failing component, file, and line number
   - Navigate to and read all relevant source files:
     - The checker/monitor that flagged the error
     - The RTL component being tested
     - The sequence/test that drove the stimulus
     - Related configuration files
   - Understand what the component is supposed to do
   - Determine the **root cause** of the failure
   - Identify what **verbosity/debug options** are needed for more info
   - Output a structured analysis report with:
     - Failure summary
     - Root cause hypothesis
     - Recommended debug options for rerun
     - Files to investigate further

3. **Key files analyzed by analyze.md:**

   **run.log** - Contains the actual failure message and stack trace
   ```bash
   Read: out/linux*/<variant>/<suite>/<test_name>/run.log
   ```

   **rerun_command** - Contains the command to rerun this specific test
   ```bash
   Read: out/linux*/<variant>/<suite>/<test_name>/rerun_command
   ```

   **Source files** - The failing component's source code
   ```bash
   Read: src/verif/... (path from run.log error message)
   Read: src/rtl/... (related RTL if applicable)
   ```

4. **analyze.md Output:**
   After analysis, analyze.md provides:
   - **Failure Type:** RTL bug, TB bug, checker bug, config issue, etc.
   - **Root Cause:** Explanation of what's wrong
   - **Debug Options:** Specific verbosity/debug flags to add for rerun
   - **Files to Fix:** List of source files that likely need changes

**DO NOT skip analyze.md - it provides the critical context for rerun.md.**

### 8.4 Rerun with Debug Using rerun.md

**AFTER analyze.md completes, use `_md/rerun.md` to rerun with the recommended options.**

The rerun.md guide executes the test with debug options:

1. **Read and follow `$REPO_PATH/_md/rerun.md`** for the rerun process
2. The rerun.md guide will:
   - Take the debug options recommended by analyze.md
   - Construct the rerun command with those options
   - Execute the rerun (with `-lsf`, `-fsdb`, verbosity flags as needed)
   - Capture the debug output
   - Return the enhanced log for further analysis

3. **Common debug options (determined by analyze.md):**
   - `+UVM_VERBOSITY=UVM_HIGH` or `+UVM_VERBOSITY=UVM_DEBUG`
   - `+define+DEBUG_<component>`
   - `-fsdb` for waveform generation
   - Component-specific debug switches
   - Protocol-specific debug flags

4. **After rerun completes:**
   - Read the new run.log with enhanced debug info
   - Correlate the debug output with the failure
   - Confirm or refine the root cause from analyze.md
   - Proceed to develop the fix

**rerun.md is a simple executor - analyze.md does the thinking.**

### 8.5 Develop Fix

Based on analysis from analyze.md and debug output from rerun.md:
1. **Confirm the bug type:** RTL issue, testbench issue, configuration issue, checker issue
2. **Determine the fix:** What code changes are needed
3. **Locate source files:** Files are in `$REPO_PATH/src/` (NEVER in `out/`)

### 8.6 Implement Fix Using perforce.md

**CRITICAL: Always use `_md/perforce.md` for ALL file operations.**

**NEVER edit files directly. ALWAYS use Perforce commands first.**

1. **Read and follow `$REPO_PATH/_md/perforce.md`** for proper p4 workflow
2. The perforce.md guide covers:
   - Opening files for edit (`p4 edit`)
   - Adding new files (`p4 add`)
   - Checking opened files (`p4 opened`)
   - Creating changelists
   - Reverting changes if needed

### Perforce Fix Workflow

**Step 1: Open file for edit**
```bash
p4 edit <source_file_path>
```

**Step 2: Make code changes**
Use Claude's Edit tool to modify the file

**Step 3: Verify file is opened**
```bash
p4 opened
```

**Step 4: Check the diff**
```bash
p4 diff <source_file_path>
```

### Valid Directories for Editing

**ONLY edit files in source directories:**
- `$REPO_PATH/src/`
- `$REPO_PATH/import/`
- `$REPO_PATH/umclib/`
- `$REPO_PATH/setup/`

**NEVER edit files in:**
- `$REPO_PATH/out/` - This contains build artifacts, NOT source code

### 8.7 Recompile Using compile.md

**CRITICAL: After ANY source file changes, you MUST recompile before rerunning tests.**

1. **Read and follow `$REPO_PATH/_md/compile.md`** for the complete compilation process
2. The compile.md guide will:
   - Clean pub and svrndcfg directories (Step 2.3)
   - Construct the proper build command
   - Execute compilation on LSF
   - Monitor progress and handle errors

3. **Wait for compile to complete:**
   - Check for `passed_cmd_count: X failed_cmd_count: 0`
   - If compile fails, analyze and fix compile errors before proceeding

**DO NOT skip recompilation - tests will use old code without it.**

### 8.8 Rerun Test to Verify Fix

After successful recompilation:

1. **Rerun the representative test using rerun.md**
   - Use `_md/rerun.md` to rerun the test
   - No debug options needed for verification (just run normally)
   - rerun.md will execute the rerun_command from the test directory

2. **Check the result:**
   - If PASSED: Fix is verified, proceed to next signature
   - If FAILED: Use analyze.md **RE-ANALYSIS MODE** (see below)

3. **If verification FAILED - Use RE-ANALYSIS MODE:**
   - Go back to `_md/analyze.md` but use **RE-ANALYSIS MODE**
   - RE-ANALYSIS MODE skips Phase 1 (component discovery already done)
   - RE-ANALYSIS MODE compares: same failure vs different failure
   - RE-ANALYSIS MODE uses ULTRATHINK to analyze why fix didn't work
   - See analyze.md "RE-ANALYSIS MODE" section for full workflow

4. **Next Steps after verification:**
   - If fix is verified (PASSED): Proceed to next signature or complete
   - If fix failed (same error): Refine fix based on RE-ANALYSIS findings
   - If fix failed (different error): Check if new component needs verbosity
   - Inform user of Perforce options:
     - `p4 shelve -c <CL>` to shelve changes for review
     - `p4 submit -c <CL>` to submit changes
     - `p4 revert <file>` to discard changes if fix didn't work

---

## Step 9: Repeat for All Top Signatures

Repeat Steps 8.1 - 8.8 for each signature needed to reach 75% pass rate.

**Reminder of the fix loop:**
```
8.1 Select shortest-runtime test
8.2 Navigate to failing directory
8.3 Deep analysis (analyze.md) → outputs root cause + debug options
8.4 Rerun with debug (rerun.md) → uses options from analyze.md
8.5 Develop fix based on analysis
8.6 Implement fix (perforce.md)
8.7 Recompile (compile.md)
8.8 Rerun to verify fix (rerun.md) → if FAILED, go back to 8.3
```

Track progress:
```
**Debug Progress:**
- Signature 1: [Analyzed/Fixed/Verified]
- Signature 2: [Analyzing...]
- Signature 3: [Pending]
...
```

---

## Quick Reference

### Key Files and Locations

| Item | Path |
|------|------|
| Run commands config (primary) | `$REPO_PATH/src/verif/tb/etc/ultrasmoke.yml` |
| Run commands config (alternate) | `$REPO_PATH/src/verif/tb/etc/release_gate.yml` |
| Suite definitions | `$REPO_PATH/src/test/suites/umc/*.dj` |
| Build output | `out/linux*/<variant>/` |
| Test results | `out/linux*/<variant>/<suite>/<test_name>/` |
| Failure log | `out/linux*/<variant>/<suite>/<test_name>/run.log` |
| Rerun command | `out/linux*/<variant>/<suite>/<test_name>/rerun_command` |

### Environment Init Scripts
```bash
source /proj/verif_release_ro/cbwa_initscript/current/cbwa_init.csh
source /proj/verif_release_ro/cbwa_bootcore/current/bin/_bootenv.csh -v <variant>
```

**Both scripts must be sourced in the same shell. The `bootenv` alias does NOT work in non-interactive shells.**

### Triage Command
```bash
tcsh -c 'source /proj/verif_release_ro/cbwa_initscript/current/cbwa_init.csh; source /proj/verif_release_ro/cbwa_bootcore/current/bin/_bootenv.csh -v <VARIANT>; umc_triage $REPO_PATH/out/ -running'
```

### Rerun Options
| Option | Description |
|--------|-------------|
| `-lsf` | Run on LSF cluster |
| `-fsdb` | Generate FSDB waveform |
| `+UVM_VERBOSITY=UVM_HIGH` | Increase UVM verbosity |
| `+UVM_VERBOSITY=UVM_DEBUG` | Maximum UVM verbosity |

---

## Execution Flow Summary

```
1. User provides prompt (e.g., "run sanity on umc9_3")
           ↓
2. Infer variant, suite, test from prompt (NO QUESTIONS)
           ↓
3. Check if build exists in out/linux*/<variant>/config/<tb_config>/pub
           ↓
   [No build] → Compile using compile.md → Wait for completion
   [Build exists] → Check if source files (*.sv, *.v, *.svh, *.vh, *.plsv, *.plsvh, *.plv) are newer than pub/
           ↓
   [Source newer] → Recompile using compile.md (inform user of modified files) → Wait for completion
   [Build up-to-date] → Continue
           ↓
4. Run tests using command template (with tee to log file: run_<variant>_<suite>.log)
           ↓
5. Monitor run progress every 5 minutes (sleep 300 → verify → check log)
           ↓
6. When run completes: umc_triage out/ -running (ALWAYS - even for single test)
           ↓
7. Analyze results, identify top signatures for 75% pass rate
           ↓
8. Ask user: "Want me to analyze and fix top signatures?"
           ↓
   [No] → Return control to user
   [Yes] → Continue
           ↓
9. For each top signature:
   a. Pick shortest-runtime failing test
   b. Navigate to failing directory
   c. Deep analysis using analyze.md:
      - Read run.log, source files, related components
      - Identify root cause
      - Determine verbosity/debug options needed
      - Output: failure type, root cause, debug options, files to fix
   d. Rerun with debug using rerun.md:
      - Takes options from analyze.md
      - Executes rerun with -lsf, -fsdb, verbosity flags
      - Returns enhanced debug log
   e. Develop fix based on analysis
   f. Implement fix (p4 edit → make changes → p4 opened)
   g. Recompile using compile.md (REQUIRED after any source changes)
   h. Rerun test to verify fix (rerun.md) → if FAILED, go back to step c
           ↓
10. Report progress and results to user
           ↓
11. Cleanup: Remove temporary files created during workflow
    - If tests passed or build passed: delete temp files
    - Keep only files needed for user reference (final logs, triage outputs)
```

---

## Final Cleanup

**IMPORTANT: After successful completion of tests or builds:**
1. Remove all temporary files created in `$REPO_PATH/` during the workflow
2. Keep only essential files for user reference:
   - Final run logs (e.g., `run_<variant>_<suite>.log`)
   - Triage outputs
   - Any explicitly requested debug files
3. Delete intermediate files:
   - Temporary scripts
   - Intermediate log files
   - Debug outputs not needed for analysis

---

**Version:** 5.5
**Last Updated:** 2026-01-19

**Change Log:**
- v5.5: Step 8.8 now references analyze.md RE-ANALYSIS MODE for failed verifications (skips component discovery)
- v5.4: Step 8.8 now explicitly uses rerun.md for verification rerun; if verification fails, loop back to analyze.md
- v5.3: Split analysis and rerun into separate steps - analyze.md (deep analysis, root cause, debug options) runs BEFORE rerun.md (simple executor)
- v5.2: Added requirement to ALWAYS run umc_triage after tests (even single test), updated triage command to use bootenv environment
- v5.1: Removed Step 2.3 (clean build directory with rm -rf) - no longer needed before recompilation
- v5.0: Removed all summary file creation/tracking - simplified workflow
