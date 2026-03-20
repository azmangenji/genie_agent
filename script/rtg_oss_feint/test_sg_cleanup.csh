#!/bin/tcsh
# Test script for .SG_SaveRestoreDB cleanup
# Usage: tcsh -f test_sg_cleanup.csh <refdir> [--dry-run]

set refdir_name = "$1"
set dry_run = 0

if ("$2" == "--dry-run") then
    set dry_run = 1
endif

if ("$refdir_name" == "") then
    echo "Usage: tcsh -f test_sg_cleanup.csh <refdir> [--dry-run]"
    echo "Example: tcsh -f test_sg_cleanup.csh /proj/xxx/umc_konark_Feb14110834"
    echo "         tcsh -f test_sg_cleanup.csh /proj/xxx/umc_konark_Feb14110834 --dry-run"
    exit 1
endif

if (! -d "$refdir_name") then
    echo "ERROR: Directory not found: $refdir_name"
    exit 1
endif

echo "========================================="
echo "SpyGlass SaveRestoreDB Cleanup Test"
echo "========================================="
echo "Target directory: $refdir_name"
if ($dry_run == 1) then
    echo "Mode: DRY RUN (no files will be deleted)"
else
    echo "Mode: LIVE (files will be deleted)"
endif
echo "========================================="
echo ""

echo "Searching for .SG_SaveRestoreDB directories..."
echo ""

# Use a temp file to store results
set tmpfile = /tmp/sg_cleanup_$$.txt
find "$refdir_name" -name ".SG_SaveRestoreDB" -type d > $tmpfile

set dir_count = `wc -l < $tmpfile`

if ($dir_count == 0) then
    echo "No .SG_SaveRestoreDB directories found."
    rm -f $tmpfile
    exit 0
endif

echo "Found $dir_count directory(ies):"
echo "-----------------------------------------"

foreach sg_dir (`cat $tmpfile`)
    if (-d "$sg_dir") then
        set sg_size = `du -sh "$sg_dir" | awk '{print $1}'`

        if ($dry_run == 1) then
            echo "  [DRY RUN] Would remove: $sg_dir ($sg_size)"
        else
            echo "  Removing: $sg_dir ($sg_size)"
            rm -rf "$sg_dir"
            if ($status == 0) then
                echo "    -> Removed successfully"
            else
                echo "    -> ERROR: Failed to remove"
            endif
        endif
    endif
end

rm -f $tmpfile

echo "-----------------------------------------"
echo ""
echo "========================================="
if ($dry_run == 1) then
    echo "DRY RUN complete. Run without --dry-run to delete."
else
    echo "Cleanup complete!"
endif
echo "========================================="
