#!/usr/bin/env python3
"""
extract_lineage_permutons.py
Extract permuton values from DSO lineage FxSynthesize log files.

Usage:
    ./extract_lineage_permutons.py <dso_run_dir> [output_file]
    ./extract_lineage_permutons.py /path/to/umccmd_DSO_28Jan_40p
    ./extract_lineage_permutons.py /path/to/umccmd_DSO_28Jan_40p LINEAGE_PERMUTONS.txt

The script extracts permuton values from the DSO-6124 messages in FxSynthesize logs:
    INFO: ::DSO::PERMUTONS::umccmd_before_<name>_proc <value>

Author: DSO Timing Enhancement
Date: 2026-03-01
"""

import os
import re
import sys
import glob
import datetime


def extract_permutons(log_file, max_lines=150000):
    """
    Extract permutons from FxSynthesize log file.

    Searches for lines matching:
        INFO: ::DSO::PERMUTONS::umccmd_before_<name>_proc <value>

    Args:
        log_file: Path to FxSynthesize_*.log file
        max_lines: Maximum lines to read (some permutons like pgt appear around line 100K)

    Returns:
        dict: {permuton_name: permuton_value}
    """
    pattern = r"INFO: ::DSO::PERMUTONS::umccmd_before_(\w+)_proc (\S+)"
    permutons = {}

    try:
        with open(log_file, 'r', errors='ignore') as f:
            for i, line in enumerate(f):
                if i > max_lines:
                    break
                match = re.search(pattern, line)
                if match:
                    name = match.group(1)
                    value = match.group(2)
                    permutons[name] = value
    except Exception as e:
        print(f"  Error reading {log_file}: {e}", file=sys.stderr)

    return permutons


def process_run(run_dir):
    """
    Process all lineages in a DSO run directory.

    Args:
        run_dir: Path to DSO run (e.g., /path/to/umccmd_DSO_28Jan_40p)

    Returns:
        list: [(lineage_id, permutons_dict), ...]
    """
    work_dir = os.path.join(run_dir, "data/CrlFlow/work")
    results = []

    if not os.path.isdir(work_dir):
        print(f"Error: Work directory not found: {work_dir}", file=sys.stderr)
        return results

    # Find all lineage directories (.run_*)
    lineage_dirs = glob.glob(os.path.join(work_dir, ".run_*"))

    for lineage_dir in sorted(lineage_dirs):
        lineage = os.path.basename(lineage_dir).replace(".run_", "")

        # Find FxSynthesize log file (exclude dso_pre/post scripts)
        log_files = glob.glob(os.path.join(lineage_dir, "FxSynthesize_*.log"))
        log_files = [f for f in log_files if "dso_" not in os.path.basename(f)]

        if log_files:
            permutons = extract_permutons(log_files[0])
            results.append((lineage, permutons))
            print(f"  {lineage}: {len(permutons)} permutons")
        else:
            print(f"  {lineage}: no log file found", file=sys.stderr)

    return results


def generate_permutons_file(runs, output_file):
    """
    Generate LINEAGE_PERMUTONS.txt file.

    Args:
        runs: list of (run_dir, run_name) tuples
        output_file: Output file path
    """
    # Permuton order for consistent output (12 UMCCMD permutons)
    # Note: arb_safe and pgt fire at compile_initial_opto (~line 106-114K)
    #       io_path fires at compile_initial_map alongside other permutons
    permuton_order = [
        'control_buffer', 'dcq_arb', 'crit_groups', 'ctrl_iso',
        'umc_id_didt', 'fanout_dup', 'timer_counter', 'arb_safe', 'pgt',
        'arb_r2r', 'r2r_tns_weight', 'io_path',
        # V5 new permutons
        'dcqarb_boundary_opt', 'clkgate_opt', 'dcqarb_fanout'
    ]

    with open(output_file, 'w') as f:
        f.write("# LINEAGE_PERMUTONS.txt\n")
        f.write(f"# Generated: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M')}\n")
        f.write("# Extracted from FxSynthesize log files (DSO-6124 messages)\n")
        f.write("#" + "=" * 70 + "\n\n")

        for run_dir, run_name in runs:
            f.write(f"#{'=' * 70}\n")
            f.write(f"# RUN: {run_name} ({os.path.basename(run_dir)})\n")
            f.write(f"#{'=' * 70}\n\n")

            print(f"Processing {run_name}...")
            results = process_run(run_dir)
            print(f"  Total: {len(results)} lineages\n")

            for lineage, permutons in results:
                f.write(f"--- lineage_{lineage} ---\n")
                if permutons:
                    for name in permuton_order:
                        if name in permutons:
                            f.write(f"  {name}: {permutons[name]}\n")
                else:
                    f.write("  (no permutons found - baseline/seed lineage)\n")
                f.write("\n")

    print(f"Output written to: {output_file}")


def main():
    if len(sys.argv) < 2:
        print("Usage: ./extract_lineage_permutons.py <dso_run_dir> [output_file]")
        print("")
        print("Examples:")
        print("  ./extract_lineage_permutons.py /path/to/umccmd_DSO_28Jan_40p")
        print("  ./extract_lineage_permutons.py /path/to/umccmd_DSO_28Jan_40p permutons.txt")
        print("")
        print("For multiple runs:")
        print("  Edit the script and modify the 'runs' list in main()")
        sys.exit(1)

    run_dir = sys.argv[1]

    if not os.path.isdir(run_dir):
        print(f"Error: Directory not found: {run_dir}", file=sys.stderr)
        sys.exit(1)

    # Output file
    if len(sys.argv) >= 3:
        output_file = sys.argv[2]
    else:
        output_file = "LINEAGE_PERMUTONS.txt"

    # Single run mode
    run_name = os.path.basename(run_dir)
    runs = [(run_dir, run_name)]

    generate_permutons_file(runs, output_file)


if __name__ == "__main__":
    main()
