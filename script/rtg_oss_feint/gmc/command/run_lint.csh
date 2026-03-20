#!/bin/tcsh
# GMC Lint static check command
# Command: be_dj --bootenv_v gmc13_1a -J lsf -e 'releaseflow::dropflow(:gmc_leda).build(:rhea_lint, :rhea_drop)' -DDROP_TOPS="gmc_gmcctrl_t+gmc_gmcch_t" -DLINT_TILE -l sg_lint_tile_run.log -DRHEA_LINT_OPTS='-keep_db -gui'

# Get RHEL version for LSF resource selection
set uname_result = `uname -r`
if ("$uname_result" =~ *el8*) then
    set RHEL_TYPE = "RHEL8_64"
else
    set RHEL_TYPE = "RHEL7_64"
endif

echo "GMC Lint execution started at `date`"
echo "Using RHEL type: $RHEL_TYPE"

# GMC uses be_dj with bootenv_v and gmc_leda dropflow
# -J lsf handles LSF submission internally
# Tiles: gmc_gmcctrl_t, gmc_gmcch_t
be_dj --bootenv_v gmc13_1a -J lsf -e 'releaseflow::dropflow(:gmc_leda).build(:rhea_lint, :rhea_drop)' -DDROP_TOPS="gmc_gmcctrl_t+gmc_gmcch_t" -DLINT_TILE -l logs/sg_lint_tile_run.log -DRHEA_LINT_OPTS='-keep_db'

echo "GMC Lint execution completed at `date`"
