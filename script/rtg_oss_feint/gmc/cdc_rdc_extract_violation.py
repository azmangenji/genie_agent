#!/usr/bin/env python
"""
Universal CDC/RDC violation extraction tool
Supports both Orion and Arcadia report formats
Filters out rsmu/dft/rdft-related violations
Dynamically categorizes violations by their ID type
Python 2/3 compatible

Usage:
  Orion:   python script.py <cdc_report.rpt> <rdc_report.rpt> <tile_name>
  Arcadia: python script.py <cdc_report.rpt> <rdc_report.rpt> <rdc_resetchecks.rpt> <tile_name>
"""

import sys
import re

def extract_blackbox_unresolved(filepath):
    """Extract blackbox and unresolved module information"""
    num_blackboxes = 0
    num_unresolved = 0
    blackbox_modules = []
    unresolved_modules = []
    in_blackbox_section = False
    in_unresolved_section = False
    
    with open(filepath, 'r') as f:
        lines = f.readlines()
        i = 0
        while i < len(lines):
            line = lines[i]
            
            match = re.search(r'Number\s+of\s+blackboxes\s*=\s*(\d+)', line)
            if match:
                num_blackboxes = int(match.group(1))
            
            match = re.search(r'Number\s+of\s+Unresolved\s+Modules\s*=\s*(\d+)', line)
            if match:
                num_unresolved = int(match.group(1))
            
            if re.match(r'^Empty Black Boxes:\s*$', line):
                in_blackbox_section = True
                i += 2
                continue
            
            if in_blackbox_section:
                match = re.match(r'^(\S+)\s+\d+\s+\/', line)
                if match:
                    blackbox_modules.append(match.group(1))
                if re.match(r'^\s*$', line) or 'Detail Design Information' in line:
                    in_blackbox_section = False
            
            if re.match(r'^Unresolved Modules:\s*$', line):
                in_unresolved_section = True
            
            if in_unresolved_section:
                match = re.match(r'^(\S+)\s+\d+\s+Unresolved Module', line)
                if match:
                    unresolved_modules.append(match.group(1))
                if re.search(r'^\s*Definition\s*:', line):
                    in_unresolved_section = False
            
            i += 1
    
    blackbox_list = " ".join(blackbox_modules) if blackbox_modules else "None"
    unresolved_list = " ".join(unresolved_modules) if unresolved_modules else "None"
    
    return (num_blackboxes, num_unresolved, blackbox_list, unresolved_list)

def extract_violations(filepath, report_type):
    """Extract and filter violations from CDC/RDC report, categorized by ID type"""

    with open(filepath, 'r') as f:
        all_lines = f.readlines()

    # Extract summary information and violation type headers
    total_violations = 0
    total_inferred = 0
    in_summary = False
    type_headers = {}

    for line in all_lines:
        if report_type == 'CDC' and 'Clock Group Summary' in line:
            in_summary = True
        if report_type == 'RDC' and 'Reset Tree Summary' in line:
            in_summary = True

        match = re.match(r'^Violations?\s*\((\d+)\)', line)
        if match:
            total_violations = int(match.group(1))

        if in_summary:
            match = re.match(r'^\s*2\.\s*Inferred\s*[:\(]\s*\((\d+)\)', line)
            if match:
                total_inferred = int(match.group(1))
                in_summary = False

        # Extract violation type headers dynamically
        match = re.search(r'\(([a-z_]+)\)\s*$', line)
        if match:
            vtype = match.group(1)
            type_headers[vtype] = line.strip()

    # Find violation details section
    violation_count = 0
    caution_count = 0
    recording = False
    violation_lines = []

    for line in all_lines:
        if 'Violation' in line:
            violation_count += 1
            if violation_count == 2:
                recording = True
                continue

        if 'Caution' in line:
            caution_count += 1
            if caution_count == 2 and recording:
                break

        if recording:
            violation_lines.append(line)

    if not violation_lines:
        return ([], True, total_violations, total_inferred, 0)

    violations_by_type = {}
    total_filtered = [0]  # Use list for Python 2 compatibility (mutable)

    # Track which line indices have been processed (to avoid double counting)
    processed_indices = set()

    # Flexible format detection based on line structure:
    # - Header line: non-indented (starts with non-whitespace)
    # - Child line: indented (starts with tab/spaces)
    # Format A: Header has START (with or without ID), children have END with ID
    # Format B: Header has END without ID, children have START with ID

    header_line = [None]  # Use list for Python 2 compatibility
    header_has_filter = [False]
    children = []  # List of (index, line) tuples

    def process_violation_group():
        """Process the current header + children group"""
        if header_line[0] is None or not children:
            return

        # Extract violation type from first child's ID
        vtype = None
        for idx, child_line in children:
            id_match = re.search(r'ID:([a-z_]+)_', child_line)
            if id_match:
                vtype = id_match.group(1)
                break

        if vtype:
            if vtype not in violations_by_type:
                violations_by_type[vtype] = []

            if header_has_filter[0]:
                # All children are filtered
                total_filtered[0] += len(children)
                for idx, _ in children:
                    processed_indices.add(idx)
            else:
                # Check each child individually
                violation_block = [header_line[0]]
                for idx, child_line in children:
                    if re.search(r'rsmu|rdft|dft|tdr', child_line, re.I):
                        total_filtered[0] += 1
                        processed_indices.add(idx)
                    else:
                        violation_block.append(child_line)

                if len(violation_block) > 1:
                    violations_by_type[vtype].append(violation_block)

    for i, line in enumerate(violation_lines):
        # Detect header lines (non-indented lines with : start : or : end :)
        # Header with START (non-indented) - can be with or without ID
        if re.match(r'^\S.*: start :', line):
            # Process previous violation group
            process_violation_group()

            header_line[0] = line
            header_has_filter[0] = bool(re.search(r'rsmu|rdft|dft|tdr', line, re.I))
            del children[:]  # Clear list (Python 2 compatible)
            processed_indices.add(i)

        # Header with END but NO ID (non-indented)
        elif re.match(r'^\S.*: end :', line) and '(ID:' not in line:
            # Process previous violation group
            process_violation_group()

            header_line[0] = line
            header_has_filter[0] = bool(re.search(r'rsmu|rdft|dft|tdr', line, re.I))
            del children[:]  # Clear list (Python 2 compatible)
            processed_indices.add(i)

        # Child lines (indented) with ID - captures both formats
        elif re.match(r'^\s+.*: (start|end) :.*\(ID:', line):
            children.append((i, line))
            processed_indices.add(i)

        # Child lines with Synchronizer ID (alternate ID format)
        elif re.match(r'^\s+.*: (start|end) :.*\(Synchronizer ID:', line):
            children.append((i, line))
            processed_indices.add(i)

    # Process last violation group
    process_violation_group()

    # Convert back to integer
    total_filtered = total_filtered[0]

    # Second pass: handle simple list violations (RDC style)
    # Only process lines not already handled by start/end logic
    current_vtype = None
    current_header = None
    in_violation_section = False

    for i, line in enumerate(violation_lines):
        # Skip already processed lines
        if i in processed_indices:
            continue

        # Skip start/end lines
        if ': start :' in line or ': end :' in line:
            continue

        # Check for section headers (violation type)
        if re.match(r'^=+\s*$', line):
            in_violation_section = False
            continue

        # Check for violation type header line
        match = re.search(r'\(([a-z_]+)\)\s*$', line)
        if match:
            current_vtype = match.group(1)
            current_header = line.strip()
            in_violation_section = False
            continue

        # Check for separator line
        if re.match(r'^-+\s*$', line):
            if current_vtype:
                in_violation_section = True
                if current_vtype not in violations_by_type:
                    violations_by_type[current_vtype] = []
            continue

        # Process violation lines (with IDs)
        if in_violation_section and re.search(r'\(ID:\s*[a-z_]+_\d+\)', line, re.I):
            if re.search(r'rsmu|rdft|dft|tdr', line, re.I):
                total_filtered += 1
            else:
                violations_by_type[current_vtype].append([line])

    # Build output organized by violation type
    filtered_output = []
    first_section = True

    for vtype in sorted(violations_by_type.keys()):
        if violations_by_type[vtype]:
            # Add section header
            if first_section:
                filtered_output.append("=================================================================\n")
                first_section = False

            header_text = type_headers.get(vtype, vtype)
            filtered_output.append("{0}\n".format(header_text))
            filtered_output.append("-----------------------------------------------------------------\n")

            # Add violations
            for violation_block in violations_by_type[vtype]:
                for line in violation_block:
                    filtered_output.append(line)
                filtered_output.append("\n")

    has_none = (total_violations == 0)
    return (filtered_output, has_none, total_violations, total_inferred, total_filtered)

def main():
    if len(sys.argv) not in [4, 5]:
        print("Usage: python script.py <cdc_report.rpt> <rdc_report.rpt> [<rdc_resetchecks.rpt>] <tile_name>")
        sys.exit(1)
    
    is_arcadia = (len(sys.argv) == 5)
    
    if is_arcadia:
        cdc_file = sys.argv[1]
        rdc_file = sys.argv[2]
        rdc_checks_file = sys.argv[3]
        tile_name = sys.argv[4]
    else:
        cdc_file = sys.argv[1]
        rdc_file = sys.argv[2]
        tile_name = sys.argv[3]
        rdc_checks_file = rdc_file
    
    # Extract CDC violations
    cdc_lines, cdc_has_none, cdc_violations, cdc_inferred, cdc_filtered = extract_violations(cdc_file, 'CDC')
    cdc_blackboxes, cdc_unresolved, cdc_bb_list, cdc_unres_list = extract_blackbox_unresolved(cdc_file)
    
    # Extract RDC violations
    rdc_lines, rdc_has_none, rdc_violations, rdc_inferred, rdc_filtered = extract_violations(rdc_file, 'RDC')
    
    # Calculate unfiltered counts
    cdc_unfiltered = cdc_violations - cdc_filtered
    rdc_unfiltered = rdc_violations - rdc_filtered
    
    # Print summary table
    print("#table#")
    print("Types,Tiles,Inferred,Total_Violations,Filtered_rsmu_dft,Unfiltered_rsmu_dft,Blackboxes,Unresolved,Logfile")
    print("CDC,{0},{1},{2},{3},{4},{5},{6},{7}".format(tile_name, cdc_inferred, cdc_violations, cdc_filtered, cdc_unfiltered, cdc_blackboxes, cdc_unresolved, cdc_file))
    print("RDC,{0},{1},{2},{3},{4},N/A,N/A,{5}".format(tile_name, rdc_inferred, rdc_violations, rdc_filtered, rdc_unfiltered, rdc_file))
    print("#table end#")
    print("")
    print("#text#")
    print("Blackbox Modules: {0}".format(cdc_bb_list))
    print("Unresolved Modules: {0}".format(cdc_unres_list))
    print("")
    
    # Print CDC violation details
    if not cdc_has_none and cdc_lines and cdc_unfiltered > 0:
        print("=" * 70)
        print("CDC {0} Violation Details (Unfiltered):".format(tile_name))
        print("=" * 70)
        for line in cdc_lines:
            sys.stdout.write(line)
        print("")
    
    # Print RDC violation details
    if not rdc_has_none and rdc_lines and rdc_unfiltered > 0:
        print("=" * 70)
        print("RDC {0} Violation Details (Unfiltered):".format(tile_name))
        print("=" * 70)
        for line in rdc_lines:
            sys.stdout.write(line)
    
    # Exit with error if violations found
    sys.exit(1 if (cdc_lines or rdc_lines) else 0)

if __name__ == '__main__':
    main()
