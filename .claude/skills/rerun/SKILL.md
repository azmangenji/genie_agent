# Rerun Skill

Rerun failed tests with enhanced verbosity options for deeper debugging.

## Trigger
`/rerun`

## Overview

This skill handles rerunning failed tests with verbosity options provided by `analyze.md` (via `execute.md`).

**Workflow:**
```
execute.md → analyze.md (analysis) → rerun.md (execution)
```

- **analyze.md** does: failure analysis, component mapping, verbosity option discovery
- **rerun.md** does: navigate to test directory, execute rerun with provided options

## Prerequisites

**Before starting any rerun**, set up the environment:

```bash
bootenv && echo $REPO_PATH
```

Use the displayed $REPO_PATH as your working directory.

---

## Inputs from execute.md / analyze.md

rerun.md expects the following inputs (provided by analyze.md via execute.md):

1. **Test Path**: Full path to failing test directory
   ```
   $REPO_PATH/out/linux*/umc*/config/<config>/run/umc/<suite>/<test>/test_dir
   ```

2. **Variant**: The umc variant (e.g., umc9_3, umc14_2)

3. **Verbosity Options**: List of -op flags to add
   ```
   -op "umc_DFI_DEBUG_ALL=1"
   -op "umc_UVC_VERBOSITY=4"
   -op "umc_TOP_ENV_DEBUG_ALL=1"
   ...
   ```

---

## Step 1: Navigate to Test Directory

Navigate to the failing test directory:

```bash
tcsh -c "cd <test_path> && pwd"
```

Example:
```bash
tcsh -c "cd $REPO_PATH/out/linux*/umc9_3/config/umc_dfi_tb/run/umc/sanity/test_basic/test_dir && pwd"
```

---

## Step 2: Read rerun_command

Read the existing rerun_command to extract the base run_job command:

```bash
tcsh -c "cd <test_path> && cat rerun_command"
```

**Extract the run_job command and its arguments** - do NOT execute the script directly.

---

## Step 3: Execute Rerun with Provided Options

Build and execute the complete rerun command using the verbosity options from analyze.md:

```bash
tcsh -c "source /proj/verif_release_ro/cbwa_initscript/current/cbwa_init.bash && \
bootenv -v <VARIANT> -o \$REPO_PATH && \
run_job [... copy all run_job args from rerun_command ...] \
  <ALL -op FLAGS FROM ANALYZE.MD> \
  -fsdb \
  -r \"select[(type==RHEL8_64) && swp>20 && tmp>2048 && (csbatch || tmpshortrr || gb16 || gb32)] rusage[mem=20000]\" \
  -lsf" | tee <test_name>_rerun.log &
```

### MANDATORY Flags

Every rerun command MUST include:
- **`-fsdb`**: Enable waveform capture
- **`-r "select[...]"`**: LSF resource requirements
- **`-lsf`**: Submit to LSF

---

## Step 4: Submit Multiple Tests in Parallel

If multiple tests need rerunning, submit ALL at once:

```bash
# Test 1
tcsh -c "source ... && bootenv ... && run_job [test1] <-op flags> -fsdb -r \"...\" -lsf" | tee test1_rerun.log &

# Test 2
tcsh -c "source ... && bootenv ... && run_job [test2] <-op flags> -fsdb -r \"...\" -lsf" | tee test2_rerun.log &

# Test 3
tcsh -c "source ... && bootenv ... && run_job [test3] <-op flags> -fsdb -r \"...\" -lsf" | tee test3_rerun.log &
```

**NEVER wait for each test to complete before submitting the next one.**

---

## Step 5: Monitor Every 5 Minutes

Monitor all submitted jobs together:

```bash
# Check all LSF jobs status
tcsh -c "bjobs"

# Wait 5 minutes between checks
sleep 300
```

**Single monitoring loop for ALL tests** - do not monitor each test separately.

---

## Critical Rules

### Command Execution

1. **Always use `tcsh -c` wrapper** - The test environment requires tcsh
2. **Never execute `./rerun_command` directly** - Read it, extract run_job args, execute with tcsh
3. **Never use bash `cd` separately** - Chain all commands in single `tcsh -c`
4. **Use `tee` for output capture** - Never use `>` redirection

### Flags

5. **Never change `+UVM_VERBOSITY`** - Leave global UVM flag unchanged from original command
6. **Unlimited -op flags** - Add all flags provided by analyze.md
7. **Always include -fsdb, -r, -lsf** - These are mandatory

### Execution

8. **Submit all tests at once** - Don't wait for completion
9. **Run in background with `&`** - Non-blocking execution
10. **Monitor every 5 minutes** - Use `bjobs` for all tests together

---

## Example: Complete Rerun

**Inputs from analyze.md:**
```
Test: $REPO_PATH/out/linux*/umc9_3/config/umc_dfi_tb/run/umc/sanity/test_basic/test_dir
Variant: umc9_3
Options:
  -op "umc_DFI_DEBUG_ALL=1"
  -op "umc_DFI_DISPLAY_CMD_DCD_ALL=1"
  -op "umc_UVC_DEBUG_ALL=1"
  -op "umc_UVC_VERBOSITY=4"
  -op "umc_TOP_ENV_DEBUG_ALL=1"
```

**Step 1: Navigate and read rerun_command**
```bash
tcsh -c "cd $REPO_PATH/out/linux*/umc9_3/config/umc_dfi_tb/run/umc/sanity/test_basic/test_dir && cat rerun_command"
```

**Step 2: Execute with all options**
```bash
tcsh -c "source /proj/verif_release_ro/cbwa_initscript/current/cbwa_init.bash && \
bootenv -v umc9_3 -o \$REPO_PATH && \
run_job -design umc9_3 -config umc_dfi_tb [...all args from rerun_command...] \
  -op \"umc_DFI_DEBUG_ALL=1\" \
  -op \"umc_DFI_DISPLAY_CMD_DCD_ALL=1\" \
  -op \"umc_UVC_DEBUG_ALL=1\" \
  -op \"umc_UVC_VERBOSITY=4\" \
  -op \"umc_TOP_ENV_DEBUG_ALL=1\" \
  -fsdb \
  -r \"select[(type==RHEL8_64) && swp>20 && tmp>2048 && (csbatch || tmpshortrr || gb16 || gb32)] rusage[mem=20000]\" \
  -lsf" | tee test_basic_rerun.log &
```

**Step 3: Monitor**
```bash
tcsh -c "bjobs"
sleep 300
# Repeat until complete
```

---

## Workflow Summary

```
┌─────────────────────────────────────────────────────────────────┐
│ INPUT FROM ANALYZE.MD (via execute.md)                          │
│ • Test path                                                     │
│ • Variant                                                       │
│ • List of -op verbosity flags                                   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 1: NAVIGATE TO TEST DIRECTORY                              │
│ tcsh -c "cd <test_path> && pwd"                                 │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 2: READ RERUN_COMMAND                                      │
│ tcsh -c "cd <test_path> && cat rerun_command"                   │
│ Extract run_job command and arguments                           │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 3: EXECUTE WITH PROVIDED OPTIONS                           │
│ tcsh -c "source ... && bootenv ... && run_job [...] \           │
│   <all -op flags from analyze.md> \                             │
│   -fsdb -r \"...\" -lsf" | tee rerun.log &                      │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 4: SUBMIT ALL TESTS IN PARALLEL                            │
│ Don't wait - submit all at once                                 │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 5: MONITOR EVERY 5 MINUTES                                 │
│ bjobs → sleep 300 → bjobs → ...                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

**Version:** 2.0
**Last Updated:** 2026-01-19
