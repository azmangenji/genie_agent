# Compile Skill

Compile RTL and testbench for UMC variants. Auto-starts build process immediately upon invocation.

## Trigger
`/compile`

## Auto-Start Behavior

When this skill is invoked, **immediately start the build process**:

1. **First, try to understand variant and target from context:**
   - Review previous user messages in the conversation
   - Look for mentions of variant (umc9_3, umc14_2, umc9_6)
   - Look for mentions of target (e.g., umc9_3_sdp_dfi_tb, etc.)
   - If both variant and target are clear from context, proceed directly

2. **Only if you cannot determine from context:**
   - Use AskUserQuestion tool to ask which variant to build
   - Options: `umc9_3`, `umc14_2`, `umc9_6`
   - Present as selectable options, not text input

3. **Get $REPO_PATH (top of trunk):**
   ```bash
   tcsh -c 'source /proj/verif_release_ro/cbwa_initscript/current/cbwa_init.csh; source /proj/verif_release_ro/cbwa_bootcore/current/bin/_bootenv.csh -v <variant>; echo REPO_PATH=$REPO_PATH'
   ```
   - Capture the REPO_PATH from output
   - Use $REPO_PATH as base for all file paths

4. **If variant is known but target is not:**
   - Read `$REPO_PATH/src/verif/tb/etc/release_gate.yml` to find available targets
   - Use AskUserQuestion tool to present all targets as selectable options

5. Proceed with build process

**DO NOT wait for user to say "compile" - start immediately upon file invocation.**

## Command Execution Requirements

**CRITICAL**: The `bootenv` command is an **alias** that only works in interactive shells. When using `tcsh -c` (non-interactive), aliases don't expand.

**SOLUTION**: Directly source the underlying script:
```bash
source /proj/verif_release_ro/cbwa_bootcore/current/bin/_bootenv.csh -v <variant>
```

## Build Configuration Source

All build commands and configurations are defined in:
```
$REPO_PATH/src/verif/tb/etc/release_gate.yml
```

## Available Build Targets

### umc9_3 Targets
- `umc9_3_umc_dfi_tb` - DFI testbench
- `umc9_3_umc_rtl_only` - RTL only
- `umc9_3_umc_rhea_dc` - Rhea DC build
- `umc9_3_umc_tb` - umc testbench

### umc14_2 Targets
- `umc14_2_umc_dfi_tb` - DFI testbench
- `umc14_2_umc_rtl_only` - RTL only
- `umc14_2_umc_rhea_dc` - Rhea DC build
- `umc14_2_umc_tb` - umc testbench

### umc9_6 Targets
- `umc9_6_umc_dfi_tb` - DFI testbench
- `umc9_6_umc_rtl_only` - RTL only
- `umc9_6_umc_rhea_dc` - Rhea DC build
- `umc9_6_umc_tb` - umc testbench

## Build Command Template

Run the build command directly inline using `tee` to capture output:
```bash
tcsh -c 'source /proj/verif_release_ro/cbwa_initscript/current/cbwa_init.csh; source /proj/verif_release_ro/cbwa_bootcore/current/bin/_bootenv.csh -v <design>; dj -x <design> -J lsf -m 31 --gcf_opts '\''<gcf_options>'\'' <supplement> -e '\''<action>'\''' 2>&1 | tee build_<variant>_<target>.log
```

**Quote Escaping**: Use `'\''` to include single quotes within a single-quoted tcsh command.

## Extracting Components from release_gate.yml

For each target, extract:

1. **design** → `<design>`
2. **action** → `<action>`
3. **supplement** → `<supplement>` (if present)
4. **compile_only_bdji_lsf_args** → Parse to extract `<gcf_options>`:
   - Pattern: `--bdji_gcf_opts '<content>'`
   - Extract the `<content>` portion

### Field Mapping

| YAML Field | Maps To | Purpose |
|------------|---------|---------|
| `design` | `-x <design>` and `bootenv -v <design>` | Variant specification |
| `action` | `-e '<action>'` | Build action to execute |
| `supplement` | Direct arguments to dj | Compiler flags |
| `compile_only_bdji_lsf_args` | `--gcf_opts '<extracted>'` | LSF resource specifications |
| `sim_cmd` | **IGNORE** | Only for post-build simulation |

## Build Monitoring

- Monitor build progress every **5 minutes** by reading the log file
- **Execute `sleep 300` before each log check**
- Verify sleep completion via background tasks before reading log
- Use `tail -n 50 <logfile>` or Read tool to monitor progress
- **Stagnant log output is NORMAL** - keep monitoring until completion

### Monitoring Cycle
```
1. Execute build command (with run_in_background)
2. Execute: sleep 300 (in background)
3. Verify sleep completed via /tasks
4. Read log file to check progress
5. If build not complete: goto step 2
6. If build complete: analyze results
```

## Build Success/Failure Checking

### Determining Build Status

Check the **log file** for **failed_cmd_count**:

**Build PASSED:**
- `failed_cmd_count = 0` means success
- Report success to user
- Keep log file for reference

**Build FAILED:**
- `failed_cmd_count > 0` means errors
- Keep log file for error analysis
- Read DJ master log: `$REPO_PATH/out/linux*/logs/dj/current/dj_master.log`
- Analyze errors and identify files with syntax errors
- **AUTOMATIC FIX LOOP (no user confirmation needed):**
  1. Run `p4 edit <file_path>` for each file that needs fixing
  2. Apply the fixes
  3. Recompile using the same build command
  4. Monitor new build (sleep 300, check log)
  5. If failed_cmd_count > 0: repeat this loop
  6. If failed_cmd_count = 0: build passed

## Log File Retention

**Always keep the build log file regardless of build outcome.**

Log file naming: `build_<variant>_<target>.log`

## Example Build Command

For `umc9_3_umc_dfi_tb`:

```bash
tcsh -c 'source /proj/verif_release_ro/cbwa_initscript/current/cbwa_init.csh; source /proj/verif_release_ro/cbwa_bootcore/current/bin/_bootenv.csh -v umc9_3; dj -x umc9_3 -J lsf -m 32 --gcf_opts '\''queue:"regr_high", name:"dj", mem:4000, select:"type==$SIP_SIM_OS", lsf_native:"-P $LSF_PROJECT -G $LSF_PROJECT.user.stage -W 600"'\'' '\''buildflow::simulator(:umc_dfi_tb).sim_build'\''' 2>&1 | tee build_umc9_3_umc_dfi_tb.log
```

## Important Notes

- **NO TEMP FILES**: Run commands inline with `tcsh -c 'source ...; source ...; dj ...'`
- **Always get $REPO_PATH first** - it's the top of trunk
- **Use `tee` to capture build output** for monitoring
- **Run builds in background** using Claude's `run_in_background` parameter
- **ALWAYS use AskUserQuestion tool** for variant and target selection (as options)
- **NEVER edit files in `out/` directory** - these are generated files
- **ALWAYS run `p4 edit <file>` before modifying any file**
- Refer to perforce.md for p4 commands
