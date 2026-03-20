#!/usr/bin/env python3
"""
RTL Clock and Reset Email Report Generator

Generates email-friendly reports showing clock/reset structure and relationships.

Usage:
    python3 rtl_email_report_generator.py <vf_file> [options]

Example:
    python3 rtl_email_report_generator.py umc_top.vf --email report.txt
    python3 rtl_email_report_generator.py umc_top.vf --html report.html
"""

import os
import re
import sys
import argparse
from collections import defaultdict
from pathlib import Path
from datetime import datetime


class EmailReportGenerator:
    """Generates email-friendly RTL analysis reports"""

    def __init__(self, top_module="umc_top"):
        self.top_module = top_module
        self.rtl_files = []
        self.rtl_dir = None

        # Analysis results
        self.primary_clocks = []
        self.primary_resets = []
        self.cdc_sync_summary = defaultdict(int)
        self.key_modules = {
            'clock': [],
            'reset': [],
            'cdc': []
        }

    def parse_vf_file(self, vf_file):
        """Parse .vf file to get RTL files"""
        with open(vf_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line.startswith('//') or line.startswith('+'):
                    continue
                if line.endswith('.v') or line.endswith('.sv'):
                    self.rtl_files.append(line)
                    if not self.rtl_dir:
                        self.rtl_dir = str(Path(line).parent)

    def analyze_design(self):
        """Quick analysis of design"""
        # Find top module file - must match exactly <top_module>.v
        top_file = None

        # Look for exact match: <top_module>.v
        for f in self.rtl_files:
            if f.endswith(f'/{self.top_module}.v') or f.endswith(f'\\{self.top_module}.v'):
                top_file = f
                print(f"[INFO] Found top module: {top_file}")
                break

        # Fallback: search for file with top_module in name
        if not top_file:
            for f in self.rtl_files:
                if self.top_module in os.path.basename(f) and f.endswith('.v'):
                    top_file = f
                    print(f"[INFO] Found top module (fallback): {top_file}")
                    break

        if top_file:
            self._analyze_top_ports(top_file)
        else:
            print(f"[WARNING] Could not find {self.top_module}.v file")

        self._find_key_modules()
        self._count_cdc_synchronizers()
        self._trace_signal_paths()

    def _analyze_top_ports(self, top_file):
        """Extract primary clocks and resets"""
        print(f"[INFO] Parsing top module: {top_file}")

        with open(top_file, 'r') as f:
            lines = f.readlines()

        # Find module declaration and port list
        in_port_list = False
        ports = []

        for i, line in enumerate(lines):
            # Start of module
            if re.match(rf'module\s+{self.top_module}\s*\(', line):
                in_port_list = True
                continue

            # End of port list (closing parenthesis followed by semicolon)
            if in_port_list and re.search(r'\)\s*;', line):
                break

            # Extract port names from port list
            if in_port_list:
                # Remove comments and whitespace
                cleaned = re.sub(r'//.*', '', line).strip()
                # Extract identifiers (skip commas and whitespace)
                if cleaned and not cleaned.startswith('//'):
                    # Get port name (remove leading comma)
                    port_match = re.match(r'[,\s]*(\w+)', cleaned)
                    if port_match:
                        port_name = port_match.group(1)
                        if port_name and port_name not in ['input', 'output', 'inout']:
                            ports.append(port_name)

        print(f"[DEBUG] Found {len(ports)} ports in module declaration")

        # Classify ports as clocks or resets
        clock_keywords = ['CLK', 'clk', 'REFCLK', 'Clk']
        reset_keywords = ['RESET', 'reset', 'PWROK', 'resetb', 'RESETn', 'zpr']

        for port in ports:
            # Check for clocks
            if any(kw in port for kw in clock_keywords):
                # Exclude non-clock signals
                if 'SYNC' not in port and 'Trigger' not in port and port not in self.primary_clocks:
                    self.primary_clocks.append(port)
                    print(f"[CLOCK] {port}")
            # Check for resets
            elif any(kw in port for kw in reset_keywords):
                if port not in self.primary_resets:
                    self.primary_resets.append(port)
                    print(f"[RESET] {port}")

    def _trace_signal_paths(self):
        """Trace clock and reset signal paths through the design"""
        self.clock_traces = {}
        self.reset_traces = {}

        # Build module hierarchy map first
        self._build_module_map()

        print("[INFO] Tracing signal paths...")

        # Trace each primary clock
        for clk in self.primary_clocks:
            trace = self._trace_signal(clk, 'clock')
            if trace['connections']:
                self.clock_traces[clk] = trace
                print(f"[TRACE] Clock {clk}: {len(trace['connections'])} connections, {len(trace['port_chain'])} levels")

        # Trace each primary reset
        for rst in self.primary_resets:
            trace = self._trace_signal(rst, 'reset')
            if trace['connections']:
                self.reset_traces[rst] = trace
                print(f"[TRACE] Reset {rst}: {len(trace['connections'])} connections, {len(trace['port_chain'])} levels")

    def _build_module_map(self):
        """Build a map of module definitions, ports, and instance port connections"""
        self.module_map = {}  # module_name -> {file, ports: {port_name: direction}, content: str}
        self.instance_map = {}  # (parent_module, instance_name) -> instance_type
        self.instance_ports = {}  # (parent_module, instance_name) -> {port_name: connected_signal}

        for rtl_file in self.rtl_files:
            try:
                with open(rtl_file, 'r') as f:
                    content = f.read()

                # Find module name
                module_match = re.search(r'module\s+(\w+)\s*[\(#]', content)
                if not module_match:
                    continue
                module_name = module_match.group(1)

                # Extract ports with directions
                ports = {}
                for match in re.finditer(r'\b(input|output|inout)\s+(?:wire\s+|reg\s+)?(?:\[[^\]]+\]\s+)?(\w+)', content):
                    direction = match.group(1)
                    port_name = match.group(2)
                    ports[port_name] = direction

                self.module_map[module_name] = {
                    'file': rtl_file,
                    'ports': ports,
                    'content': content
                }

                # Find all instantiations and their port connections
                # Pattern: module_type instance_name ( ... );
                inst_pattern = r'(\w+)\s+(\w+)\s*\(([^;]+)\);'
                for inst_match in re.finditer(inst_pattern, content, re.DOTALL):
                    inst_type = inst_match.group(1)
                    inst_name = inst_match.group(2)
                    port_list = inst_match.group(3)

                    # Skip keywords
                    if inst_type in ['module', 'input', 'output', 'inout', 'wire', 'reg', 'assign',
                                     'always', 'if', 'else', 'case', 'for', 'while', 'begin', 'end',
                                     'function', 'task', 'generate', 'endgenerate']:
                        continue

                    self.instance_map[(module_name, inst_name)] = inst_type

                    # Parse port connections: .port_name(signal_name)
                    port_conns = {}
                    for port_match in re.finditer(r'\.(\w+)\s*\(\s*(\w+)(?:\s*\[[^\]]*\])?\s*\)', port_list):
                        port_name = port_match.group(1)
                        signal_name = port_match.group(2)
                        port_conns[port_name] = signal_name

                    self.instance_ports[(module_name, inst_name)] = port_conns

            except:
                continue

        print(f"[INFO] Built module map: {len(self.module_map)} modules, {len(self.instance_map)} instances")

    def _trace_signal(self, signal_name, signal_type):
        """Trace a single signal through the design hierarchy"""
        trace = {
            'signal': signal_name,
            'type': signal_type,
            'connections': [],  # List of connection details
            'modules': set(),   # Set of modules this signal reaches
            'gating': [],       # Clock gating cells it goes through
            'cdc': [],          # CDC synchronizers it goes through
            'outputs': [],      # Output ports driven by this signal
            'hierarchy': [],    # Old-style hierarchy
            'port_chain': []    # NEW: Hierarchical port-to-port chain
        }

        # Track port connections for building hierarchy
        # Format: [(level, parent_module, signal_in_parent, instance, instance_type, port_on_instance), ...]
        port_connections = []

        # Search through all RTL files for this signal
        for rtl_file in self.rtl_files:
            try:
                with open(rtl_file, 'r') as f:
                    content = f.read()

                filename = os.path.basename(rtl_file)

                # Skip if signal not mentioned in file
                if signal_name not in content:
                    continue

                # Find module name in file
                module_match = re.search(r'module\s+(\w+)\s*[\(#]', content)
                module_name = module_match.group(1) if module_match else filename.replace('.v', '')

                # Find direct connections (assignments)
                assign_pattern = rf'(?:assign\s+)?(\w+)\s*=.*\b{re.escape(signal_name)}\b'
                for match in re.finditer(assign_pattern, content):
                    dest = match.group(1)
                    if dest != signal_name:
                        trace['connections'].append({
                            'source': signal_name,
                            'dest': dest,
                            'module': module_name,
                            'type': 'assign',
                            'file': filename
                        })
                        trace['modules'].add(module_name)

                # Find port connections in instantiations
                # Pattern: .port_name(signal_name) or .port_name(signal_name[...])
                port_pattern = rf'\.(\w+)\s*\(\s*{re.escape(signal_name)}(?:\s*\[[^\]]*\])?\s*\)'
                for match in re.finditer(port_pattern, content):
                    port_name = match.group(1)
                    # Find instance name (look backwards for instance)
                    pos = match.start()
                    # Search backwards for instance pattern
                    before = content[:pos]
                    inst_match = re.search(r'(\w+)\s+(\w+)\s*\([^;]*$', before)
                    if inst_match:
                        inst_type = inst_match.group(1)
                        inst_name = inst_match.group(2)

                        # Record port connection for hierarchy building
                        port_connections.append({
                            'parent_module': module_name,
                            'signal_in_parent': signal_name,
                            'instance_name': inst_name,
                            'instance_type': inst_type,
                            'port_on_instance': port_name
                        })

                        trace['connections'].append({
                            'source': signal_name,
                            'dest': f"{inst_name}.{port_name}",
                            'module': module_name,
                            'instance': inst_name,
                            'instance_type': inst_type,
                            'port_name': port_name,
                            'type': 'port',
                            'file': filename
                        })
                        trace['modules'].add(module_name)
                        trace['modules'].add(inst_type)

                        # Check if it's a clock gating cell
                        if any(g in inst_type.lower() for g in ['clock_gate', 'clkgate', 'gater']):
                            trace['gating'].append({
                                'cell': inst_type,
                                'instance': inst_name,
                                'port': port_name,
                                'module': module_name
                            })

                        # Check if it's a CDC synchronizer
                        if any(c in inst_type.lower() for c in ['sync', 'cdc', 'techind']):
                            trace['cdc'].append({
                                'cell': inst_type,
                                'instance': inst_name,
                                'port': port_name,
                                'module': module_name
                            })

                # Find output port assignments
                output_pattern = rf'output\s+(?:reg\s+)?(?:\[[^\]]+\]\s+)?(\w*{re.escape(signal_name)}\w*)'
                for match in re.finditer(output_pattern, content):
                    out_port = match.group(1)
                    trace['outputs'].append({
                        'port': out_port,
                        'module': module_name
                    })

                # Find wire declarations with this signal
                wire_pattern = rf'wire\s+(?:\[[^\]]+\]\s+)?(\w+)\s*=.*\b{re.escape(signal_name)}\b'
                for match in re.finditer(wire_pattern, content):
                    wire_name = match.group(1)
                    if wire_name != signal_name:
                        trace['connections'].append({
                            'source': signal_name,
                            'dest': wire_name,
                            'module': module_name,
                            'type': 'wire',
                            'file': filename
                        })

            except Exception as e:
                continue

        # Build old-style hierarchy from connections
        trace['hierarchy'] = self._build_hierarchy(trace)

        # Build port-to-port chain hierarchy
        trace['port_chain'] = self._build_port_chain(signal_name, port_connections)

        return trace

    def _build_port_chain(self, top_signal, port_connections):
        """Build hierarchical port-to-port chain by recursively following port names"""
        chain = []
        visited = set()  # Track visited (module, signal) pairs to avoid loops

        # Start from top module
        chain.append({
            'level': 0,
            'module': self.top_module,
            'instance': self.top_module,
            'port': top_signal,
            'direction': 'input',
            'hierarchy_path': f"{self.top_module}.{top_signal}"
        })

        def trace_recursive(current_module, signal_name, level, hier_path, parent_instance=""):
            """Recursively trace signal through module hierarchy following port name changes"""
            results = []

            # Avoid infinite loops
            visit_key = (current_module, signal_name)
            if visit_key in visited or level > 8:
                return results
            visited.add(visit_key)

            # Find all instances in current_module that use this signal
            for (parent_mod, inst_name), inst_type in self.instance_map.items():
                if parent_mod != current_module:
                    continue

                # Get port connections for this instance
                port_conns = self.instance_ports.get((parent_mod, inst_name), {})

                # Find which port connects to our signal
                for port_name, connected_signal in port_conns.items():
                    if connected_signal == signal_name:
                        new_hier = f"{hier_path}/{inst_name}.{port_name}"

                        entry = {
                            'level': level,
                            'module': inst_type,
                            'instance': inst_name,
                            'port': port_name,
                            'parent_module': current_module,
                            'parent_signal': signal_name,
                            'hierarchy_path': new_hier
                        }
                        results.append(entry)

                        # Check for clock gating or CDC
                        if any(g in inst_type.lower() for g in ['clock_gate', 'clkgate', 'gater', 'ati_clock']):
                            entry['is_gating'] = True
                        if any(c in inst_type.lower() for c in ['sync', 'cdc', 'techind']):
                            entry['is_cdc'] = True

                        # RECURSIVE: Now trace into the instantiated module
                        # The signal inside inst_type module is named "port_name" (not signal_name)
                        if inst_type in self.module_map:
                            sub_results = trace_recursive(inst_type, port_name, level + 1, new_hier, inst_name)
                            results.extend(sub_results)

            return results

        # Start tracing from top module
        chain.extend(trace_recursive(self.top_module, top_signal, 1, f"{self.top_module}.{top_signal}"))

        return chain

    def _build_hierarchy(self, trace):
        """Build hierarchical path from trace connections"""
        hierarchy = []

        # Group connections by module
        module_connections = {}
        for conn in trace['connections']:
            mod = conn['module']
            if mod not in module_connections:
                module_connections[mod] = []
            module_connections[mod].append(conn)

        # Create hierarchy entries
        for mod, conns in module_connections.items():
            entry = {
                'module': mod,
                'connections': len(conns),
                'instances': list(set(c.get('instance', '') for c in conns if c.get('instance'))),
                'types': list(set(c['type'] for c in conns))
            }
            hierarchy.append(entry)

        return hierarchy

    def _find_key_modules(self):
        """Find important clock/reset modules"""
        key_patterns = {
            'clock': [r'clock.*gate', r'clk.*arb', r'clk.*ctrl', r'clkgater', r'ati_clock'],
            'reset': [r'reset.*gen', r'rsmu', r'zpr.*control', r'reset_gen', r'remote_smu'],
            'cdc': [r'techind_sync', r'sync.*pulse', r'cdc', r'async_fifo']
        }

        for rtl_file in self.rtl_files:
            filename = os.path.basename(rtl_file)

            for category, patterns in key_patterns.items():
                if any(re.search(p, filename, re.I) for p in patterns):
                    if filename not in [m['name'] for m in self.key_modules[category]]:
                        self.key_modules[category].append({
                            'name': filename,
                            'file': rtl_file
                        })

        # Also extract detailed module info
        self._extract_detailed_module_info()

    def _extract_detailed_module_info(self):
        """Extract detailed information from key modules"""
        self.clock_gating_cells = []
        self.reset_sync_modules = []
        self.cdc_instances = []
        self.functional_modules = []

        for rtl_file in self.rtl_files:
            try:
                with open(rtl_file, 'r') as f:
                    content = f.read()

                filename = os.path.basename(rtl_file)

                # Find clock gating cell instantiations
                gating_patterns = [
                    (r'ati_clock_gate\s+(\w+)\s*\(', 'ati_clock_gate'),
                    (r'umcclkgater\s+(\w+)\s*\(', 'umcclkgater'),
                    (r'oss_clock_gate\s+(\w+)\s*\(', 'oss_clock_gate'),
                    (r'CKLNQD\w*\s+(\w+)\s*\(', 'CKLNQD'),  # Standard cell
                ]
                for pattern, cell_type in gating_patterns:
                    matches = re.findall(pattern, content)
                    for inst_name in matches:
                        self.clock_gating_cells.append({
                            'type': cell_type,
                            'instance': inst_name,
                            'file': filename
                        })

                # Find CDC synchronizer instantiations
                cdc_patterns = [
                    (r'techind_sync_icd\s+#\([^)]*\)\s*(\w+)\s*\(', 'techind_sync_icd (3-stage)'),
                    (r'techind_sync\s+#\([^)]*\)\s*(\w+)\s*\(', 'techind_sync'),
                    (r'rsmu_techind_sync_v2\s+(\w+)\s*\(', 'rsmu_techind_sync_v2'),
                    (r'sync\d+_pulse\s+(\w+)\s*\(', 'sync_pulse'),
                ]
                for pattern, sync_type in cdc_patterns:
                    matches = re.findall(pattern, content)
                    for inst_name in matches:
                        self.cdc_instances.append({
                            'type': sync_type,
                            'instance': inst_name,
                            'file': filename
                        })

                # Find reset generation modules
                reset_patterns = [
                    (r'rsmu_reset_gen\w*\s+(\w+)\s*\(', 'rsmu_reset_gen'),
                    (r'iso_and2\s+(\w+)\s*\(', 'iso_and2 (isolation)'),
                    (r'rsmu_buf_asn\s+(\w+)\s*\(', 'rsmu_buf_asn'),
                ]
                for pattern, mod_type in reset_patterns:
                    matches = re.findall(pattern, content)
                    for inst_name in matches:
                        self.reset_sync_modules.append({
                            'type': mod_type,
                            'instance': inst_name,
                            'file': filename
                        })

                # Find functional modules (major blocks)
                func_patterns = [
                    (r'UMC\w+\s+(\w+)\s*\(', 'UMC Block'),
                    (r'remote_smu\w*\s+(\w+)\s*\(', 'RSMU'),
                    (r'(\w+arb)\s+\w+\s*\(', 'Arbitration'),
                ]
                for pattern, mod_type in func_patterns:
                    matches = re.findall(pattern, content)
                    for inst_name in matches[:3]:  # Limit
                        if len(inst_name) > 3:  # Filter short names
                            self.functional_modules.append({
                                'type': mod_type,
                                'instance': inst_name,
                                'file': filename
                            })

            except:
                continue

    def _count_cdc_synchronizers(self):
        """Count CDC synchronizers by type"""
        cdc_patterns = {
            '3-stage Sync': r'techind_sync.*\(.*depth.*3',
            '2-stage Sync': r'techind_sync.*\(.*depth.*2',
            'Pulse Sync': r'sync\d+_pulse',
            'CDC Buffer': r'techind_cdc',
            'Async Buffer': r'rsmu_buf_asn'
        }

        for rtl_file in self.rtl_files:
            try:
                with open(rtl_file, 'r') as f:
                    content = f.read()

                for sync_type, pattern in cdc_patterns.items():
                    count = len(re.findall(pattern, content, re.I))
                    if count > 0:
                        self.cdc_sync_summary[sync_type] += count
            except:
                continue

    def generate_text_report(self, output_file):
        """Generate plain text email report"""
        report = []
        report.append("=" * 80)
        report.append("RTL CLOCK AND RESET STRUCTURE ANALYSIS")
        report.append("=" * 80)
        report.append(f"Design: {self.top_module}")
        report.append(f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        report.append(f"Total RTL Files: {len(self.rtl_files)}")
        report.append("=" * 80)
        report.append("")

        # === CLOCK STRUCTURE ===
        report.append("┌─────────────────────────────────────────────────────────────────────────────┐")
        report.append("│ CLOCK STRUCTURE                                                             │")
        report.append("└─────────────────────────────────────────────────────────────────────────────┘")
        report.append("")

        if self.primary_clocks:
            report.append("PRIMARY CLOCK INPUTS:")
            report.append("")
            for i, clk in enumerate(self.primary_clocks, 1):
                # Guess purpose from name
                purpose = self._guess_clock_purpose(clk)
                report.append(f"  {i}. {clk:30s} → {purpose}")
            report.append("")

            # Clock relationships (all async in typical UMC design)
            report.append("CLOCK DOMAIN RELATIONSHIPS:")
            report.append("")
            report.append("  All clocks are ASYNCHRONOUS to each other")
            report.append("  (Independent clock sources, no phase relationship)")
            report.append("")
        else:
            report.append("  No primary clocks identified")
            report.append("")

        # Clock modules
        if self.key_modules['clock']:
            report.append("KEY CLOCK MODULES:")
            report.append("")
            for mod in self.key_modules['clock'][:5]:  # Top 5
                report.append(f"  • {mod['name']}")
            report.append("")

        # === RESET STRUCTURE ===
        report.append("┌─────────────────────────────────────────────────────────────────────────────┐")
        report.append("│ RESET STRUCTURE                                                             │")
        report.append("└─────────────────────────────────────────────────────────────────────────────┘")
        report.append("")

        if self.primary_resets:
            report.append("PRIMARY RESET INPUTS:")
            report.append("")
            for i, rst in enumerate(self.primary_resets, 1):
                purpose = self._guess_reset_purpose(rst)
                polarity = self._guess_polarity(rst)
                report.append(f"  {i}. {rst:30s} → {purpose:30s} ({polarity})")
            report.append("")

            # Reset hierarchy
            report.append("RESET HIERARCHY:")
            report.append("")
            report.append("  External Async Resets")
            report.append("         ↓")
            report.append("  3-Stage CDC Synchronizers")
            report.append("         ↓")
            report.append("  Reset Generation Logic")
            report.append("         ↓")
            report.append("  ┌──────────────┬──────────────┬──────────────┐")
            report.append("  │              │              │              │")
            report.append("  Cold Reset   Hard Reset   Soft Reset   Special Resets")
            report.append("  (Deepest)    (Normal)     (SW Control) (SMS Fuse, ZPR)")
            report.append("")
        else:
            report.append("  No primary resets identified")
            report.append("")

        # Reset modules
        if self.key_modules['reset']:
            report.append("KEY RESET MODULES:")
            report.append("")
            for mod in self.key_modules['reset'][:8]:  # Top 8
                report.append(f"  • {mod['name']}")
            report.append("")

        # === CDC SYNCHRONIZERS ===
        report.append("┌─────────────────────────────────────────────────────────────────────────────┐")
        report.append("│ CDC SYNCHRONIZERS                                                           │")
        report.append("└─────────────────────────────────────────────────────────────────────────────┘")
        report.append("")

        if self.cdc_sync_summary:
            total_cdc = sum(self.cdc_sync_summary.values())
            report.append(f"TOTAL CDC SYNCHRONIZERS: {total_cdc}")
            report.append("")
            report.append("BREAKDOWN BY TYPE:")
            report.append("")
            for sync_type, count in sorted(self.cdc_sync_summary.items(), key=lambda x: -x[1]):
                bar = "█" * min(count // 2, 40)
                report.append(f"  {sync_type:20s} : {count:3d}  {bar}")
            report.append("")
        else:
            report.append("  No CDC synchronizers found")
            report.append("")

        # === CLOCK-RESET RELATIONSHIPS ===
        report.append("┌─────────────────────────────────────────────────────────────────────────────┐")
        report.append("│ CLOCK-RESET RELATIONSHIPS                                                   │")
        report.append("└─────────────────────────────────────────────────────────────────────────────┘")
        report.append("")
        report.append("Each async reset is synchronized to multiple clock domains:")
        report.append("")

        if self.primary_resets and self.primary_clocks:
            for rst in self.primary_resets[:3]:  # Show first 3
                report.append(f"  {rst}")
                for clk in self.primary_clocks:
                    report.append(f"     └─> Synchronized to {clk} domain (3-stage)")
                report.append("")

        # === CLOCK TRACING DETAILS ===
        if hasattr(self, 'clock_traces') and self.clock_traces:
            report.append("┌─────────────────────────────────────────────────────────────────────────────┐")
            report.append("│ CLOCK TRACING DETAILS                                                       │")
            report.append("└─────────────────────────────────────────────────────────────────────────────┘")
            report.append("")

            for clk, trace in list(self.clock_traces.items())[:6]:  # Top 6 clocks
                report.append(f"  ◆ {clk}")
                report.append(f"    Purpose: {self._guess_clock_purpose(clk)}")
                report.append(f"    Connections: {len(trace['connections'])}")
                report.append(f"    Hierarchy Levels: {len(trace.get('port_chain', []))}")

                # Show port-to-port hierarchy chain
                if trace.get('port_chain'):
                    report.append(f"    Port Hierarchy:")
                    for entry in trace['port_chain'][:8]:
                        level = entry.get('level', 0)
                        indent = "    " + "  " * level
                        module = entry.get('module', '')
                        port = entry.get('port', '')
                        instance = entry.get('instance', '')

                        if level == 0:
                            report.append(f"{indent}{module}.{port} (top input)")
                        else:
                            report.append(f"{indent}└─→ {instance} ({module}).{port}")

                    if len(trace['port_chain']) > 8:
                        report.append(f"        ... and {len(trace['port_chain']) - 8} more levels")

                if trace['gating']:
                    report.append(f"    Clock Gating Cells:")
                    for g in trace['gating'][:3]:
                        port = g.get('port', '')
                        report.append(f"      └─ {g['cell']} ({g['instance']}).{port} in {g['module']}")

                report.append("")

        # === RESET TRACING DETAILS ===
        if hasattr(self, 'reset_traces') and self.reset_traces:
            report.append("┌─────────────────────────────────────────────────────────────────────────────┐")
            report.append("│ RESET TRACING DETAILS                                                       │")
            report.append("└─────────────────────────────────────────────────────────────────────────────┘")
            report.append("")

            for rst, trace in list(self.reset_traces.items())[:6]:  # Top 6 resets
                report.append(f"  ◆ {rst}")
                report.append(f"    Purpose: {self._guess_reset_purpose(rst)}")
                report.append(f"    Polarity: {self._guess_polarity(rst)}")
                report.append(f"    Connections: {len(trace['connections'])}")
                report.append(f"    Hierarchy Levels: {len(trace.get('port_chain', []))}")

                # Show port-to-port hierarchy chain
                if trace.get('port_chain'):
                    report.append(f"    Port Hierarchy:")
                    for entry in trace['port_chain'][:8]:
                        level = entry.get('level', 0)
                        indent = "    " + "  " * level
                        module = entry.get('module', '')
                        port = entry.get('port', '')
                        instance = entry.get('instance', '')

                        if level == 0:
                            report.append(f"{indent}{module}.{port} (top input)")
                        else:
                            report.append(f"{indent}└─→ {instance} ({module}).{port}")

                    if len(trace['port_chain']) > 8:
                        report.append(f"        ... and {len(trace['port_chain']) - 8} more levels")

                if trace['cdc']:
                    report.append(f"    CDC Synchronizers:")
                    for c in trace['cdc'][:3]:
                        port = c.get('port', '')
                        report.append(f"      └─ {c['cell']} ({c['instance']}).{port} in {c['module']}")

                report.append("")

        # === SUMMARY ===
        report.append("┌─────────────────────────────────────────────────────────────────────────────┐")
        report.append("│ SUMMARY                                                                     │")
        report.append("└─────────────────────────────────────────────────────────────────────────────┘")
        report.append("")
        report.append(f"  ✓ {len(self.primary_clocks):2d} Primary Clock Domains")
        report.append(f"  ✓ {len(self.primary_resets):2d} Primary Async Reset Inputs")
        report.append(f"  ✓ {len(self.key_modules['clock']):2d} Clock Infrastructure Modules")
        report.append(f"  ✓ {len(self.key_modules['reset']):2d} Reset Infrastructure Modules")
        report.append(f"  ✓ {sum(self.cdc_sync_summary.values()):2d} CDC Synchronizer Instances")
        if hasattr(self, 'clock_traces'):
            total_clk_conn = sum(len(t['connections']) for t in self.clock_traces.values())
            report.append(f"  ✓ {total_clk_conn:2d} Clock Path Connections Traced")
        if hasattr(self, 'reset_traces'):
            total_rst_conn = sum(len(t['connections']) for t in self.reset_traces.values())
            report.append(f"  ✓ {total_rst_conn:2d} Reset Path Connections Traced")
        report.append("")
        report.append("=" * 80)

        # Write to file
        with open(output_file, 'w') as f:
            f.write('\n'.join(report))

        return '\n'.join(report)

    def generate_html_report(self, output_file):
        """Generate HTML email report"""
        html = []
        html.append("<!DOCTYPE html>")
        html.append("<html>")
        html.append("<head>")
        html.append("<style>")
        html.append("body { font-family: 'Courier New', monospace; background: #f5f5f5; padding: 20px; }")
        html.append(".container { background: white; padding: 30px; max-width: 900px; margin: 0 auto; box-shadow: 0 0 10px rgba(0,0,0,0.1); }")
        html.append("h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }")
        html.append("h2 { color: #34495e; margin-top: 30px; border-left: 4px solid #3498db; padding-left: 10px; }")
        html.append(".info-box { background: #ecf0f1; padding: 15px; margin: 10px 0; border-radius: 5px; }")
        html.append(".clock { color: #2980b9; font-weight: bold; }")
        html.append(".reset { color: #c0392b; font-weight: bold; }")
        html.append(".hierarchy { background: #fff; border-left: 3px solid #95a5a6; padding-left: 15px; margin: 10px 0; }")
        html.append("table { border-collapse: collapse; width: 100%; margin: 10px 0; }")
        html.append("th { background: #34495e; color: white; padding: 10px; text-align: left; }")
        html.append("td { padding: 8px; border-bottom: 1px solid #ddd; }")
        html.append("tr:hover { background: #f8f9fa; }")
        html.append(".bar { background: #3498db; height: 20px; display: inline-block; }")
        html.append(".summary { background: #d5f4e6; padding: 20px; border-radius: 5px; margin-top: 20px; }")
        html.append("</style>")
        html.append("</head>")
        html.append("<body>")
        html.append("<div class='container'>")

        # Header
        html.append(f"<h1>RTL Clock and Reset Structure Analysis</h1>")
        html.append("<div class='info-box'>")
        html.append(f"<strong>Design:</strong> {self.top_module}<br>")
        html.append(f"<strong>Date:</strong> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}<br>")
        html.append(f"<strong>Total RTL Files:</strong> {len(self.rtl_files)}")
        html.append("</div>")

        # Clocks
        html.append("<h2>Clock Structure</h2>")
        if self.primary_clocks:
            html.append("<table>")
            html.append("<tr><th>#</th><th>Clock Signal</th><th>Purpose</th></tr>")
            for i, clk in enumerate(self.primary_clocks, 1):
                purpose = self._guess_clock_purpose(clk)
                html.append(f"<tr><td>{i}</td><td class='clock'>{clk}</td><td>{purpose}</td></tr>")
            html.append("</table>")

            html.append("<div class='info-box'>")
            html.append("<strong>Clock Relationships:</strong> All clocks are <strong>ASYNCHRONOUS</strong> to each other (independent sources)")
            html.append("</div>")

        # Resets
        html.append("<h2>Reset Structure</h2>")
        if self.primary_resets:
            html.append("<table>")
            html.append("<tr><th>#</th><th>Reset Signal</th><th>Purpose</th><th>Polarity</th></tr>")
            for i, rst in enumerate(self.primary_resets, 1):
                purpose = self._guess_reset_purpose(rst)
                polarity = self._guess_polarity(rst)
                html.append(f"<tr><td>{i}</td><td class='reset'>{rst}</td><td>{purpose}</td><td>{polarity}</td></tr>")
            html.append("</table>")

            html.append("<div class='hierarchy'>")
            html.append("<strong>Reset Hierarchy:</strong><br>")
            html.append("External Async Resets → 3-Stage CDC Sync → Reset Logic → Cold/Hard/Soft/Special Resets")
            html.append("</div>")

        # CDC
        html.append("<h2>CDC Synchronizers</h2>")
        if self.cdc_sync_summary:
            total = sum(self.cdc_sync_summary.values())
            html.append(f"<p><strong>Total:</strong> {total} CDC synchronizer instances</p>")
            html.append("<table>")
            html.append("<tr><th>Type</th><th>Count</th><th>Distribution</th></tr>")
            for sync_type, count in sorted(self.cdc_sync_summary.items(), key=lambda x: -x[1]):
                pct = (count / total * 100) if total > 0 else 0
                bar_width = int(pct * 3)
                html.append(f"<tr><td>{sync_type}</td><td>{count}</td><td><div class='bar' style='width:{bar_width}px'></div> {pct:.1f}%</td></tr>")
            html.append("</table>")

        # Clock Tracing Details
        if hasattr(self, 'clock_traces') and self.clock_traces:
            html.append("<h2>Clock Tracing Details</h2>")
            html.append("<p>Signal path tracing from primary clock inputs through the design hierarchy:</p>")

            for clk, trace in list(self.clock_traces.items())[:8]:
                purpose = self._guess_clock_purpose(clk)
                html.append(f"<div class='info-box'>")
                html.append(f"<strong class='clock'>{clk}</strong> - {purpose}<br>")
                html.append(f"<small>Connections: {len(trace['connections'])} | Hierarchy Levels: {len(trace.get('port_chain', []))}</small>")

                # Show port-to-port hierarchy chain
                if trace.get('port_chain'):
                    html.append("<br><strong>Port Hierarchy:</strong>")
                    html.append("<div style='font-family: monospace; background: #f8f8f8; padding: 10px; margin: 5px 0; border-left: 3px solid #2980b9; overflow-x: auto;'>")

                    for entry in trace['port_chain'][:10]:
                        level = entry.get('level', 0)
                        indent = "&nbsp;" * (level * 4)
                        module = entry.get('module', '')
                        port = entry.get('port', '')
                        instance = entry.get('instance', '')

                        if level == 0:
                            html.append(f"<span style='color:#2980b9;'><b>{module}</b>.{port}</span> (top input)<br>")
                        else:
                            arrow = "└─→" if level > 0 else ""
                            html.append(f"{indent}{arrow} <b>{instance}</b> (<span style='color:#666;'>{module}</span>).<span style='color:#2980b9;'>{port}</span><br>")

                    if len(trace['port_chain']) > 10:
                        html.append(f"<span style='color:#999;'>... and {len(trace['port_chain']) - 10} more levels</span><br>")

                    html.append("</div>")

                if trace.get('gating'):
                    html.append("<strong>Clock Gating Cells:</strong>")
                    html.append("<ul style='margin: 5px 0;'>")
                    for g in trace['gating'][:3]:
                        port = g.get('port', '')
                        html.append(f"<li>{g['cell']} (<code>{g['instance']}</code>) port: {port} in {g['module']}</li>")
                    html.append("</ul>")

                html.append("</div>")

        # Reset Tracing Details
        if hasattr(self, 'reset_traces') and self.reset_traces:
            html.append("<h2>Reset Tracing Details</h2>")
            html.append("<p>Signal path tracing from primary reset inputs through the design hierarchy:</p>")

            for rst, trace in list(self.reset_traces.items())[:8]:
                purpose = self._guess_reset_purpose(rst)
                polarity = self._guess_polarity(rst)
                html.append(f"<div class='info-box'>")
                html.append(f"<strong class='reset'>{rst}</strong> - {purpose} ({polarity})<br>")
                html.append(f"<small>Connections: {len(trace['connections'])} | Hierarchy Levels: {len(trace.get('port_chain', []))}</small>")

                # Show port-to-port hierarchy chain
                if trace.get('port_chain'):
                    html.append("<br><strong>Port Hierarchy:</strong>")
                    html.append("<div style='font-family: monospace; background: #fff0f0; padding: 10px; margin: 5px 0; border-left: 3px solid #c0392b; overflow-x: auto;'>")

                    for entry in trace['port_chain'][:10]:
                        level = entry.get('level', 0)
                        indent = "&nbsp;" * (level * 4)
                        module = entry.get('module', '')
                        port = entry.get('port', '')
                        instance = entry.get('instance', '')

                        if level == 0:
                            html.append(f"<span style='color:#c0392b;'><b>{module}</b>.{port}</span> (top input)<br>")
                        else:
                            arrow = "└─→" if level > 0 else ""
                            html.append(f"{indent}{arrow} <b>{instance}</b> (<span style='color:#666;'>{module}</span>).<span style='color:#c0392b;'>{port}</span><br>")

                    if len(trace['port_chain']) > 10:
                        html.append(f"<span style='color:#999;'>... and {len(trace['port_chain']) - 10} more levels</span><br>")

                    html.append("</div>")

                if trace.get('cdc'):
                    html.append("<strong>CDC Synchronizers:</strong>")
                    html.append("<ul style='margin: 5px 0;'>")
                    for c in trace['cdc'][:3]:
                        port = c.get('port', '')
                        html.append(f"<li>{c['cell']} (<code>{c['instance']}</code>) port: {port} in {c['module']}</li>")
                    html.append("</ul>")

                html.append("</div>")

        # Summary
        html.append("<div class='summary'>")
        html.append("<h2>Summary</h2>")
        html.append("<ul>")
        html.append(f"<li>✓ <strong>{len(self.primary_clocks)}</strong> Primary Clock Domains</li>")
        html.append(f"<li>✓ <strong>{len(self.primary_resets)}</strong> Primary Async Reset Inputs</li>")
        html.append(f"<li>✓ <strong>{len(self.key_modules['clock'])}</strong> Clock Infrastructure Modules</li>")
        html.append(f"<li>✓ <strong>{len(self.key_modules['reset'])}</strong> Reset Infrastructure Modules</li>")
        html.append(f"<li>✓ <strong>{sum(self.cdc_sync_summary.values())}</strong> CDC Synchronizer Instances</li>")
        if hasattr(self, 'clock_traces'):
            total_clk_conn = sum(len(t['connections']) for t in self.clock_traces.values())
            html.append(f"<li>✓ <strong>{total_clk_conn}</strong> Clock Path Connections Traced</li>")
        if hasattr(self, 'reset_traces'):
            total_rst_conn = sum(len(t['connections']) for t in self.reset_traces.values())
            html.append(f"<li>✓ <strong>{total_rst_conn}</strong> Reset Path Connections Traced</li>")
        html.append("</ul>")
        html.append("</div>")

        html.append("</div>")
        html.append("</body>")
        html.append("</html>")

        with open(output_file, 'w') as f:
            f.write('\n'.join(html))

    def generate_dot_files(self, output_prefix):
        """Generate separate DOT files for clock and reset structures"""
        # Generate clock-only DOT
        clock_dot_file = f"{output_prefix}_clock.dot"
        self._generate_clock_dot(clock_dot_file)
        print(f"[SUCCESS] Clock DOT file: {clock_dot_file}")

        # Generate reset-only DOT
        reset_dot_file = f"{output_prefix}_reset.dot"
        self._generate_reset_dot(reset_dot_file)
        print(f"[SUCCESS] Reset DOT file: {reset_dot_file}")

        return clock_dot_file, reset_dot_file

    def _group_signals_by_pattern(self, signals):
        """Dynamically group signals by detecting common patterns in names"""
        groups = {}
        ungrouped = []

        # Common clock/reset domain patterns to detect
        # IMPORTANT: Order matters - more specific patterns first, use word boundaries to avoid false matches
        patterns = [
            # Clock domains - check GPUCLK before UCLK (gpuclk contains "uclk")
            (r'gpuclk|GPUCLK|GPU.*CLK', 'GPUCLK Domain'),
            (r'(?<![a-zA-Z])UCLK|^UCLK|UCLKin', 'UCLK Domain'),  # Word boundary to avoid matching gpUCLK
            (r'DFICLK|DFICLKin', 'DFICLK Domain'),
            (r'SOCCLK|SocClk|SOC.*CLK', 'SOCCLK Domain'),
            (r'REFCLK|RefClk|REF.*CLK', 'REFCLK Domain'),
            (r'DBUS|daisychain', 'DBUS/Daisychain'),
            (r'GAP.*CLK|GAP.*REFCLK', 'GAP Clocks'),
            (r'TEST.*CLK|test.*clk|SCAN.*CLK', 'Test/Scan Clocks'),
            # Reset types
            (r'cold.*reset|pwrok|PWROK', 'Cold Reset'),
            (r'hard.*reset|RCU.*reset', 'Hard Reset'),
            (r'soft.*reset|SRBM.*reset', 'Soft Reset'),
            (r'PGFSM|PFH.*reset', 'PGFSM Reset'),
        ]

        for sig in signals:
            matched = False
            for pattern, group_name in patterns:
                if re.search(pattern, sig, re.IGNORECASE):
                    if group_name not in groups:
                        groups[group_name] = []
                    groups[group_name].append(sig)
                    matched = True
                    break

            if not matched:
                ungrouped.append(sig)

        # Add ungrouped signals to "Other" category
        if ungrouped:
            groups['Other'] = ungrouped

        return groups

    def _classify_module(self, module_name):
        """Classify a module based on naming patterns"""
        name_lower = module_name.lower()

        # Detect module type from name
        if 'dat' in name_lower and ('cmd' not in name_lower):
            return 'Data Path', '#FFE0B0', '#FF8C00'
        elif 'cmd' in name_lower and ('dat' not in name_lower):
            return 'Command Path', '#B0FFB0', '#00AA00'
        elif 'ctrl' in name_lower or 'arb' in name_lower or 'control' in name_lower:
            return 'Control', '#FFE0FF', '#9370DB'
        elif 'clk' in name_lower or 'clock' in name_lower or 'gate' in name_lower:
            return 'Clock', '#E0F0FF', '#1E90FF'
        elif 'rst' in name_lower or 'reset' in name_lower:
            return 'Reset', '#FFE0E0', '#DC143C'
        elif 'dft' in name_lower or 'scan' in name_lower or 'marker' in name_lower:
            return 'DFT', '#F0F0F0', '#808080'
        elif 'rsmu' in name_lower or 'smu' in name_lower:
            return 'SMU Interface', '#E0FFE0', '#008000'
        elif 'sec' in name_lower or 'crypto' in name_lower:
            return 'Security', '#FFE0E0', '#AA0000'
        elif 'reg' in name_lower:
            return 'Registers', '#FFFACD', '#B8860B'
        else:
            return 'Core', '#E8F0FF', '#0000AA'

    def _generate_clock_dot(self, output_file):
        """Generate clock DOT file with more blocks and fewer arrows - generic for any design"""
        dot = []

        # Header
        dot.append(f"// {self.top_module} Clock Structure")
        dot.append(f"// Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        dot.append("")
        dot.append(f"digraph {self.top_module.replace('-', '_')}_Clock {{")
        dot.append("    rankdir=LR;")
        dot.append("    compound=true;")
        dot.append("    splines=ortho;")
        dot.append("    nodesep=0.8;")
        dot.append("    ranksep=1.5;")
        dot.append("")
        dot.append('    node [shape=box, fontname="Arial", fontsize=18, height=0.8, width=3.0];')
        dot.append('    edge [fontname="Arial", fontsize=14, penwidth=2];')
        dot.append("")
        dot.append(f'    label="{self.top_module} Clock Structure Diagram";')
        dot.append("    labelloc=t;")
        dot.append("    fontsize=28;")
        dot.append('    fontname="Arial Bold";')
        dot.append("")

        # ===== DYNAMIC CLOCK GROUPING =====
        # Group clocks by detecting common patterns in signal names
        clock_groups = self._group_signals_by_pattern(self.primary_clocks)

        dot.append("    // Clock Inputs")
        dot.append("    subgraph cluster_clk_inputs {")
        dot.append('        label="Primary Clock Inputs";')
        dot.append("        style=filled;")
        dot.append('        fillcolor="#E0E8FF";')
        dot.append('        color="#0000AA";')
        dot.append("        penwidth=3;")
        dot.append("        margin=20;")
        dot.append("        fontsize=20;")
        dot.append('        fontname="Arial Bold";')
        dot.append("")

        # Color palette for groups
        colors = ["#B0C4FF", "#90EE90", "#FFD0B0", "#FFFACD", "#FFB0B0", "#E0B0FF", "#B0FFE0"]

        for i, (group_name, signals) in enumerate(clock_groups.items()):
            if signals:
                color = colors[i % len(colors)]
                signal_names = "\\n".join(signals)  # Show ALL signals
                safe_name = group_name.replace(' ', '_').replace('/', '_')
                dot.append(f'        {safe_name}_group [label="{group_name}\\n\\n{signal_names}", style=filled, fillcolor="{color}", height=1.5];')

        dot.append("    }")
        dot.append("")

        # ===== BUILD HIERARCHY FROM INSTANCE MAP =====
        # Find child instances of top module
        top_children = {}
        for (parent, inst_name), inst_type in self.instance_map.items():
            if parent == self.top_module:
                top_children[inst_name] = inst_type

        # Find grandchildren (children of children)
        grandchildren = {}
        for inst_name, inst_type in top_children.items():
            grandchildren[inst_type] = {}
            for (parent, child_inst), child_type in self.instance_map.items():
                if parent == inst_type:
                    grandchildren[inst_type][child_inst] = child_type

        # ===== TOP MODULE CLUSTER =====
        dot.append(f"    // {self.top_module}")
        dot.append(f"    subgraph cluster_{self.top_module.replace('-', '_')} {{")
        dot.append(f'        label="{self.top_module}";')
        dot.append("        style=bold;")
        dot.append("        color=black;")
        dot.append("        penwidth=4;")
        dot.append("        margin=30;")
        dot.append("        fontsize=24;")
        dot.append('        fontname="Arial Bold";')
        dot.append("")

        # ===== FULLY GENERIC HIERARCHY GENERATION =====
        # Find the main core instance (largest child with grandchildren)
        main_core_inst = None
        main_core_type = None
        max_grandchildren = 0

        for inst_name, inst_type in top_children.items():
            # Skip DFT/marker modules
            if 'dft' in inst_type.lower() or 'marker' in inst_type.lower():
                continue
            gc_count = len(grandchildren.get(inst_type, {}))
            if gc_count > max_grandchildren:
                max_grandchildren = gc_count
                main_core_inst = inst_name
                main_core_type = inst_type

        if main_core_inst and main_core_type and max_grandchildren > 0:
            # Main core cluster
            mod_class, fill_color, border_color = self._classify_module(main_core_type)
            dot.append(f"        // {main_core_type} (instance: {main_core_inst})")
            dot.append(f"        subgraph cluster_{main_core_type.replace('-', '_')} {{")
            dot.append(f'            label="{main_core_type}\\n({mod_class})";')
            dot.append("            style=filled;")
            dot.append(f'            fillcolor="{fill_color}";')
            dot.append(f'            color="{border_color}";')
            dot.append("            penwidth=3;")
            dot.append("            margin=20;")
            dot.append("            fontsize=20;")
            dot.append('            fontname="Arial Bold";')
            dot.append("")

            # Show grandchildren dynamically classified
            core_grandchildren = grandchildren.get(main_core_type, {})
            shown_types = set()

            for child_inst, child_type in core_grandchildren.items():
                if child_type in shown_types:
                    continue
                shown_types.add(child_type)

                child_class, child_fill, child_border = self._classify_module(child_type)
                safe_name = child_type.replace('-', '_').replace('.', '_')

                dot.append(f"            // {child_type}")
                dot.append(f"            subgraph cluster_{safe_name} {{")
                dot.append(f'                label="{child_type}\\n({child_class})";')
                dot.append("                style=filled;")
                dot.append(f'                fillcolor="{child_fill}";')
                dot.append(f'                color="{child_border}";')
                dot.append("                penwidth=2;")
                dot.append("                margin=15;")
                dot.append("                fontsize=16;")
                dot.append('                fontname="Arial Bold";')
                dot.append(f'                {safe_name}_node [label="{child_type.upper()}", style=filled, fillcolor="{child_fill}", height=1.0, width=2.5];')
                dot.append("            }")
                dot.append("")

            dot.append("        }")  # End main core cluster
            dot.append("")

        # Show other top-level children grouped by classification
        other_children = [(n, t) for n, t in top_children.items()
                          if t != main_core_type and 'dft' not in t.lower() and 'marker' not in t.lower()]

        if other_children:
            # Group by classification
            classified_groups = {}
            for inst_name, inst_type in other_children:
                mod_class, fill_color, border_color = self._classify_module(inst_type)
                if mod_class not in classified_groups:
                    classified_groups[mod_class] = {'modules': [], 'fill': fill_color, 'border': border_color}
                classified_groups[mod_class]['modules'].append(inst_type)

            for group_name, group_info in classified_groups.items():
                modules = list(set(group_info['modules']))  # Unique types
                safe_group = group_name.replace(' ', '_').replace('/', '_')
                mod_list = "\\n".join(modules)

                dot.append(f"        // {group_name} Modules")
                dot.append(f"        subgraph cluster_{safe_group} {{")
                dot.append(f'            label="{group_name}";')
                dot.append("            style=filled;")
                dot.append(f'            fillcolor="{group_info["fill"]}";')
                dot.append(f'            color="{group_info["border"]}";')
                dot.append("            penwidth=2;")
                dot.append("            margin=15;")
                dot.append("            fontsize=16;")
                dot.append('            fontname="Arial Bold";')
                dot.append(f'            {safe_group}_node [label="{group_name}\\n\\n{mod_list}", style=filled, fillcolor="{group_info["fill"]}", height=1.5, width=2.5];')
                dot.append("        }")
                dot.append("")

        # DFT modules
        dft_modules = [(n, t) for n, t in top_children.items() if 'dft' in t.lower() or 'marker' in t.lower()]
        if dft_modules:
            dft_list = "\\n".join(list(set([t for _, t in dft_modules])))
            dot.append("        // DFT Infrastructure")
            dot.append("        subgraph cluster_dft {")
            dot.append('            label="DFT";')
            dot.append("            style=filled;")
            dot.append('            fillcolor="#F0F0F0";')
            dot.append('            color="#808080";')
            dot.append("            penwidth=2;")
            dot.append("            margin=15;")
            dot.append("            fontsize=14;")
            dot.append(f'            dft_node [label="DFT\\n\\n{dft_list}", style=filled, fillcolor="#E0E0E0", height=1.2, width=2.5];')
            dot.append("        }")
            dot.append("")

        dot.append("    }")  # End top module cluster
        dot.append("")

        # ===== GENERIC CONNECTIONS =====
        dot.append("    // Clock Flow (auto-detected)")

        # Connect clock input groups to main core
        group_names = list(clock_groups.keys())
        edge_colors = ["#0000FF", "#00AA00", "#FF8C00", "#800080", "#008080", "#AA00AA"]

        if main_core_type:
            core_grandchildren = grandchildren.get(main_core_type, {})
            target_nodes = list(set(core_grandchildren.values()))

            for i, group_name in enumerate(group_names[:3]):  # Connect first 3 groups
                safe_group = group_name.replace(' ', '_').replace('/', '_')
                color = edge_colors[i % len(edge_colors)]

                if target_nodes:
                    # Connect to first grandchild
                    target = target_nodes[0].replace('-', '_').replace('.', '_')
                    dot.append(f'    {safe_group}_group -> {target}_node [label="{group_name}", color="{color}", penwidth=3];')
                elif main_core_type:
                    # Connect to main core if no grandchildren
                    safe_core = main_core_type.replace('-', '_').replace('.', '_')
                    dot.append(f'    {safe_group}_group -> cluster_{safe_core} [label="{group_name}", color="{color}", penwidth=3];')

        # ===== LEGEND =====
        dot.append("")
        dot.append("    // Legend")
        dot.append("    subgraph cluster_legend {")
        dot.append('        label="Legend";')
        dot.append("        style=filled;")
        dot.append('        fillcolor="#FFFFF0";')
        dot.append("        fontsize=16;")

        # Generate legend based on detected clock groups
        legend_colors = ["Blue", "Green", "Orange", "Yellow", "Red", "Purple"]
        for i, group_name in enumerate(list(clock_groups.keys())[:4]):
            color = legend_colors[i % len(legend_colors)]
            dot.append(f'        leg{i+1} [label="{color} = {group_name}", shape=plaintext, fontsize=14];')

        dot.append('        leg_ctrl [label="Purple = Gating Control", shape=plaintext, fontsize=14];')
        dot.append('        leg_dash [label="Dashed = Gated Clock", shape=plaintext, fontsize=14];')
        dot.append("    }")

        dot.append("}")

        with open(output_file, 'w') as f:
            f.write('\n'.join(dot))

    def _generate_reset_dot(self, output_file):
        """Generate reset DOT file with more blocks and fewer arrows - generic for any design"""
        dot = []

        # Header
        dot.append(f"// {self.top_module} Reset Structure")
        dot.append(f"// Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        dot.append("")
        dot.append(f"digraph {self.top_module.replace('-', '_')}_Reset {{")
        dot.append("    rankdir=LR;")
        dot.append("    compound=true;")
        dot.append("    splines=ortho;")
        dot.append("    nodesep=0.8;")
        dot.append("    ranksep=1.5;")
        dot.append("")
        dot.append('    node [shape=box, fontname="Arial", fontsize=18, height=0.8, width=3.0];')
        dot.append('    edge [fontname="Arial", fontsize=14, penwidth=2];')
        dot.append("")
        dot.append(f'    label="{self.top_module} Reset Structure Diagram";')
        dot.append("    labelloc=t;")
        dot.append("    fontsize=28;")
        dot.append('    fontname="Arial Bold";')
        dot.append("")

        # ===== DYNAMIC RESET GROUPING =====
        # Group resets by detecting common patterns in names
        reset_groups = self._group_signals_by_pattern(self.primary_resets)

        dot.append("    // Reset Inputs")
        dot.append("    subgraph cluster_rst_inputs {")
        dot.append('        label="Primary Reset Inputs";')
        dot.append("        style=filled;")
        dot.append('        fillcolor="#FFE0E0";')
        dot.append('        color="#AA0000";')
        dot.append("        penwidth=3;")
        dot.append("        margin=20;")
        dot.append("        fontsize=20;")
        dot.append('        fontname="Arial Bold";')
        dot.append("")

        # Color palette for reset groups
        reset_colors = ["#FF8080", "#FF9090", "#FFA0A0", "#FFCC99", "#FFB0B0", "#FFD0D0"]

        for i, (group_name, signals) in enumerate(reset_groups.items()):
            if signals:
                color = reset_colors[i % len(reset_colors)]
                signal_names = "\\n".join(signals)  # Show ALL signals
                safe_name = group_name.replace(' ', '_').replace('/', '_')
                dot.append(f'        {safe_name}_rst_group [label="{group_name}\\n\\n{signal_names}", style=filled, fillcolor="{color}", height=1.5];')

        dot.append("    }")
        dot.append("")

        # ===== BUILD HIERARCHY FROM INSTANCE MAP =====
        # Find child instances of top module
        top_children = {}
        for (parent, inst_name), inst_type in self.instance_map.items():
            if parent == self.top_module:
                top_children[inst_name] = inst_type

        # Find grandchildren (children of children)
        grandchildren = {}
        for inst_name, inst_type in top_children.items():
            grandchildren[inst_type] = {}
            for (parent, child_inst), child_type in self.instance_map.items():
                if parent == inst_type:
                    grandchildren[inst_type][child_inst] = child_type

        # ===== TOP MODULE CLUSTER =====
        dot.append(f"    // {self.top_module}")
        dot.append(f"    subgraph cluster_{self.top_module.replace('-', '_')} {{")
        dot.append(f'        label="{self.top_module}";')
        dot.append("        style=bold;")
        dot.append("        color=black;")
        dot.append("        penwidth=4;")
        dot.append("        margin=30;")
        dot.append("        fontsize=24;")
        dot.append('        fontname="Arial Bold";')
        dot.append("")

        # ===== RESET GENERATION CLUSTER =====
        dot.append("        // Reset Generation & CDC")
        dot.append("        subgraph cluster_reset_gen {")
        dot.append('            label="Reset Generation & CDC";')
        dot.append("            style=filled;")
        dot.append('            fillcolor="#FFE8E8";')
        dot.append('            color="#FF8C00";')
        dot.append("            penwidth=3;")
        dot.append("            margin=20;")
        dot.append("            fontsize=18;")
        dot.append('            fontname="Arial Bold";')
        dot.append("")

        # CDC Synchronizers block
        cdc_types = set()
        for cdc in self.cdc_instances[:6]:
            cdc_types.add(cdc.get('type', 'sync'))
        cdc_list = "\\n".join(list(cdc_types)[:3]) if cdc_types else "sync_3stage"

        dot.append(f'            cdc_sync [label="CDC Sync\\n\\n{cdc_list}", style=filled, fillcolor="#FFC0C0", height=1.5, width=2.5];')
        dot.append("        }")
        dot.append("")

        # ===== FULLY GENERIC HIERARCHY GENERATION =====
        # Find the main core instance (largest child with grandchildren)
        main_core_inst = None
        main_core_type = None
        max_grandchildren = 0

        for inst_name, inst_type in top_children.items():
            # Skip DFT/marker modules
            if 'dft' in inst_type.lower() or 'marker' in inst_type.lower():
                continue
            gc_count = len(grandchildren.get(inst_type, {}))
            if gc_count > max_grandchildren:
                max_grandchildren = gc_count
                main_core_inst = inst_name
                main_core_type = inst_type

        if main_core_inst and main_core_type and max_grandchildren > 0:
            # Main core cluster
            mod_class, fill_color, border_color = self._classify_module(main_core_type)
            dot.append(f"        // {main_core_type} (instance: {main_core_inst})")
            dot.append(f"        subgraph cluster_{main_core_type.replace('-', '_')}_rst {{")
            dot.append(f'            label="{main_core_type}\\n({mod_class})";')
            dot.append("            style=filled;")
            dot.append(f'            fillcolor="{fill_color}";')
            dot.append(f'            color="{border_color}";')
            dot.append("            penwidth=3;")
            dot.append("            margin=20;")
            dot.append("            fontsize=20;")
            dot.append('            fontname="Arial Bold";')
            dot.append("")

            # Show grandchildren dynamically classified
            core_grandchildren = grandchildren.get(main_core_type, {})
            shown_types = set()

            for child_inst, child_type in core_grandchildren.items():
                if child_type in shown_types:
                    continue
                shown_types.add(child_type)

                child_class, child_fill, child_border = self._classify_module(child_type)
                safe_name = child_type.replace('-', '_').replace('.', '_')

                dot.append(f"            // {child_type}")
                dot.append(f"            subgraph cluster_{safe_name}_rst {{")
                dot.append(f'                label="{child_type}\\n({child_class})";')
                dot.append("                style=filled;")
                dot.append(f'                fillcolor="{child_fill}";')
                dot.append(f'                color="{child_border}";')
                dot.append("                penwidth=2;")
                dot.append("                margin=15;")
                dot.append("                fontsize=16;")
                dot.append('                fontname="Arial Bold";')
                dot.append(f'                {safe_name}_rst_node [label="{child_type.upper()}", style=filled, fillcolor="{child_fill}", height=1.0, width=2.5];')
                dot.append("            }")
                dot.append("")

            dot.append("        }")  # End main core cluster
            dot.append("")

        # Show other top-level children grouped by classification
        other_children = [(n, t) for n, t in top_children.items()
                          if t != main_core_type and 'dft' not in t.lower() and 'marker' not in t.lower()]

        if other_children:
            # Group by classification
            classified_groups = {}
            for inst_name, inst_type in other_children:
                mod_class, fill_color, border_color = self._classify_module(inst_type)
                if mod_class not in classified_groups:
                    classified_groups[mod_class] = {'modules': [], 'fill': fill_color, 'border': border_color}
                classified_groups[mod_class]['modules'].append(inst_type)

            for group_name, group_info in classified_groups.items():
                modules = list(set(group_info['modules']))  # Unique types
                safe_group = group_name.replace(' ', '_').replace('/', '_')
                mod_list = "\\n".join(modules)

                dot.append(f"        // {group_name} Modules")
                dot.append(f"        subgraph cluster_{safe_group}_rst {{")
                dot.append(f'            label="{group_name}";')
                dot.append("            style=filled;")
                dot.append(f'            fillcolor="{group_info["fill"]}";')
                dot.append(f'            color="{group_info["border"]}";')
                dot.append("            penwidth=2;")
                dot.append("            margin=15;")
                dot.append("            fontsize=16;")
                dot.append('            fontname="Arial Bold";')
                dot.append(f'            {safe_group}_rst_node [label="{group_name}\\n\\n{mod_list}", style=filled, fillcolor="{group_info["fill"]}", height=1.5, width=2.5];')
                dot.append("        }")
                dot.append("")

        dot.append("    }")  # End top module cluster
        dot.append("")

        # ===== GENERIC CONNECTIONS =====
        dot.append("    // Reset Flow (auto-detected)")

        # Connect reset input groups to CDC/main core
        group_names = list(reset_groups.keys())
        edge_colors = ["#FF0000", "#CC0000", "#AA0000", "#8B4513", "#800000", "#990000"]

        if main_core_type:
            core_grandchildren = grandchildren.get(main_core_type, {})
            target_nodes = list(set(core_grandchildren.values()))

            for i, group_name in enumerate(group_names[:3]):  # Connect first 3 groups
                safe_group = group_name.replace(' ', '_').replace('/', '_')
                color = edge_colors[i % len(edge_colors)]

                # Connect to CDC first
                dot.append(f'    {safe_group}_rst_group -> cdc_sync [lhead=cluster_reset_gen, label="{group_name}", color="{color}", penwidth=3];')

            # Connect CDC to target modules
            if target_nodes:
                target = target_nodes[0].replace('-', '_').replace('.', '_')
                dot.append(f'    cdc_sync -> {target}_rst_node [label="Synced", color="#CC0000", penwidth=2, style=dashed];')

        # ===== RESET HIERARCHY NOTE =====
        dot.append("")
        dot.append("    // Reset Hierarchy")
        dot.append('    Reset_hierarchy [label="Reset Hierarchy\\n\\n1. Cold Reset (Deepest)\\n   • Power-on reset\\n\\n2. Hard Reset (Normal)\\n   • Primary reset path\\n\\n3. Soft Reset (SW)\\n   • Software controlled\\n\\n4. PGFSM Reset\\n   • Power gating", shape=note, style=filled, fillcolor="#FFFACD", fontsize=14, height=2.0, width=2.5];')

        # ===== LEGEND =====
        dot.append("")
        dot.append("    // Legend")
        dot.append("    subgraph cluster_legend {")
        dot.append('        label="Legend";')
        dot.append("        style=filled;")
        dot.append('        fillcolor="#FFFFF0";')
        dot.append("        fontsize=16;")
        dot.append('        leg1 [label="Red Solid = Reset CDC Path", shape=plaintext, fontsize=14];')
        dot.append('        leg2 [label="Dashed = SW/Register Control", shape=plaintext, fontsize=14];')
        dot.append('        leg3 [label="Dotted = Reset Distribution", shape=plaintext, fontsize=14];')
        dot.append("    }")

        dot.append("}")

        with open(output_file, 'w') as f:
            f.write('\n'.join(dot))

    def generate_dot_file(self, output_file):
        """Generate DOT file for Graphviz visualization (combined clock and reset)"""
        dot = []

        # Header
        dot.append(f"// {self.top_module} Clock and Reset Structure")
        dot.append(f"// Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        dot.append("")
        dot.append(f"digraph {self.top_module.replace('-', '_')}_ClockReset {{")
        dot.append("    // Graph settings")
        dot.append("    rankdir=TB;")
        dot.append("    compound=true;")
        dot.append("    splines=ortho;")
        dot.append("    nodesep=0.5;")
        dot.append("    ranksep=0.8;")
        dot.append("")
        dot.append("    // Global node style")
        dot.append('    node [shape=box, fontname="Arial", fontsize=12, height=0.5, width=2];')
        dot.append('    edge [fontname="Arial", fontsize=10];')
        dot.append("")
        dot.append(f'    label="{self.top_module} Clock and Reset Structure";')
        dot.append("    labelloc=t;")
        dot.append("    fontsize=16;")
        dot.append('    fontname="Arial Bold";')
        dot.append("")

        # Clock inputs cluster
        dot.append("    // Primary Clock Inputs")
        dot.append("    subgraph cluster_clocks {")
        dot.append('        label="Primary Clocks";')
        dot.append("        style=filled;")
        dot.append('        fillcolor="#E0F0FF";')
        dot.append('        color="#1E90FF";')
        dot.append("        penwidth=2;")
        dot.append("")

        for clk in self.primary_clocks[:10]:  # Limit to 10
            purpose = self._guess_clock_purpose(clk)
            safe_name = re.sub(r'[^a-zA-Z0-9_]', '_', clk)
            dot.append(f'        clk_{safe_name} [label="{clk}\\n({purpose})", style=filled, fillcolor="#B0E0FF"];')
        dot.append("    }")
        dot.append("")

        # Reset inputs cluster
        dot.append("    // Primary Reset Inputs")
        dot.append("    subgraph cluster_resets {")
        dot.append('        label="Primary Resets";')
        dot.append("        style=filled;")
        dot.append('        fillcolor="#FFE0E0";')
        dot.append('        color="#DC143C";')
        dot.append("        penwidth=2;")
        dot.append("")

        for rst in self.primary_resets[:10]:  # Limit to 10
            polarity = self._guess_polarity(rst)
            safe_name = re.sub(r'[^a-zA-Z0-9_]', '_', rst)
            dot.append(f'        rst_{safe_name} [label="{rst}\\n({polarity})", style=filled, fillcolor="#FFB0B0"];')
        dot.append("    }")
        dot.append("")

        # Top module
        dot.append("    // Top Module")
        dot.append(f"    subgraph cluster_top {{")
        dot.append(f'        label="{self.top_module}";')
        dot.append("        style=bold;")
        dot.append("        color=black;")
        dot.append("        penwidth=3;")
        dot.append("")

        # Clock infrastructure
        if self.key_modules['clock']:
            dot.append("        // Clock Infrastructure")
            dot.append("        subgraph cluster_clk_infra {")
            dot.append('            label="Clock Infrastructure";')
            dot.append("            style=filled;")
            dot.append('            fillcolor="#E0FFE0";')
            dot.append("")
            for mod in self.key_modules['clock'][:5]:
                mod_name = mod['name'] if isinstance(mod, dict) else mod
                safe_name = re.sub(r'[^a-zA-Z0-9_]', '_', mod_name)
                dot.append(f'            mod_clk_{safe_name} [label="{mod_name}", style=filled, fillcolor="#90EE90"];')
            dot.append("        }")

        # Reset infrastructure
        if self.key_modules['reset']:
            dot.append("        // Reset Infrastructure")
            dot.append("        subgraph cluster_rst_infra {")
            dot.append('            label="Reset Infrastructure";')
            dot.append("            style=filled;")
            dot.append('            fillcolor="#FFE0B0";')
            dot.append("")
            for mod in self.key_modules['reset'][:5]:
                mod_name = mod['name'] if isinstance(mod, dict) else mod
                safe_name = re.sub(r'[^a-zA-Z0-9_]', '_', mod_name)
                dot.append(f'            mod_rst_{safe_name} [label="{mod_name}", style=filled, fillcolor="#FFD080"];')
            dot.append("        }")

        # CDC infrastructure
        if self.key_modules['cdc']:
            dot.append("        // CDC Synchronizers")
            dot.append("        subgraph cluster_cdc {")
            dot.append('            label="CDC Synchronizers";')
            dot.append("            style=filled;")
            dot.append('            fillcolor="#E0E0FF";')
            dot.append("")
            for mod in self.key_modules['cdc'][:5]:
                mod_name = mod['name'] if isinstance(mod, dict) else mod
                safe_name = re.sub(r'[^a-zA-Z0-9_]', '_', mod_name)
                dot.append(f'            mod_cdc_{safe_name} [label="{mod_name}", style=filled, fillcolor="#C0C0FF"];')
            dot.append("        }")

        dot.append("    }")
        dot.append("")

        # Edges - connect clocks to clock infrastructure
        dot.append("    // Clock connections")
        if self.key_modules['clock'] and self.primary_clocks:
            first_mod = self.key_modules['clock'][0]
            first_clk_mod_name = first_mod['name'] if isinstance(first_mod, dict) else first_mod
            first_clk_mod = re.sub(r'[^a-zA-Z0-9_]', '_', first_clk_mod_name)
            for clk in self.primary_clocks[:5]:
                safe_clk = re.sub(r'[^a-zA-Z0-9_]', '_', clk)
                dot.append(f'    clk_{safe_clk} -> mod_clk_{first_clk_mod} [color="#0000FF", penwidth=2];')

        # Edges - connect resets to reset infrastructure
        dot.append("    // Reset connections")
        if self.key_modules['reset'] and self.primary_resets:
            first_mod = self.key_modules['reset'][0]
            first_rst_mod_name = first_mod['name'] if isinstance(first_mod, dict) else first_mod
            first_rst_mod = re.sub(r'[^a-zA-Z0-9_]', '_', first_rst_mod_name)
            for rst in self.primary_resets[:5]:
                safe_rst = re.sub(r'[^a-zA-Z0-9_]', '_', rst)
                dot.append(f'    rst_{safe_rst} -> mod_rst_{first_rst_mod} [color="#DC143C", penwidth=2];')

        # Legend
        dot.append("")
        dot.append("    // Legend")
        dot.append("    subgraph cluster_legend {")
        dot.append('        label="Legend";')
        dot.append("        style=filled;")
        dot.append('        fillcolor="#FFFFF0";')
        dot.append('        fontsize=10;')
        dot.append('        leg1 [label="Blue = Clock Domain", shape=plaintext, fontsize=10];')
        dot.append('        leg2 [label="Red = Reset Domain", shape=plaintext, fontsize=10];')
        dot.append('        leg3 [label="Green = Clock Infra", shape=plaintext, fontsize=10];')
        dot.append('        leg4 [label="Purple = CDC Sync", shape=plaintext, fontsize=10];')
        dot.append("    }")

        dot.append("}")

        with open(output_file, 'w') as f:
            f.write('\n'.join(dot))

    def _guess_clock_purpose(self, clk_name):
        """Guess clock purpose from name"""
        if 'UCLK' in clk_name or 'UCLKin' in clk_name:
            return "Main UMC Clock"
        elif 'DFI' in clk_name:
            return "DDR PHY Interface Clock"
        elif 'REFCLK' in clk_name and 'GAP' not in clk_name:
            return "Reference Clock (Always-On)"
        elif 'GAP' in clk_name and 'REFCLK' in clk_name:
            return "GAP Reference Clock (Timestamp)"
        else:
            return "Functional Clock"

    def _guess_reset_purpose(self, rst_name):
        """Guess reset purpose from name"""
        if 'PWROK' in rst_name and 'GAP' not in rst_name:
            return "Power OK Signal"
        elif 'GAP_PWROK' in rst_name:
            return "GAP Power OK Signal"
        elif 'RESETn' in rst_name or 'RESET' in rst_name:
            return "Root/Cold Reset"
        elif 'zpr' in rst_name.lower():
            return "ZPR Override (Test/Debug)"
        else:
            return "Reset Signal"

    def _guess_polarity(self, signal):
        """Guess signal polarity"""
        if signal.endswith('n') or signal.endswith('N') or 'resetb' in signal.lower():
            return "Active-Low"
        else:
            return "Active-High"


def main():
    parser = argparse.ArgumentParser(description='RTL Clock and Reset Structure Analyzer')
    parser.add_argument('input', help='.vf file path')
    parser.add_argument('--top', default='umc_top', help='Top module name')
    parser.add_argument('--output', '-o', help='Output text report file (.rpt)')
    parser.add_argument('--html', help='Output HTML file')
    parser.add_argument('--dot', help='Output DOT file prefix (generates _clock.dot and _reset.dot)')
    parser.add_argument('--both', help='Prefix for both outputs (generates .rpt and .html)')

    args = parser.parse_args()

    # Create generator
    gen = EmailReportGenerator(top_module=args.top)

    print(f"[INFO] Analyzing design: {args.top}")
    gen.parse_vf_file(args.input)
    print(f"[INFO] Found {len(gen.rtl_files)} RTL files")

    gen.analyze_design()
    print(f"[INFO] Analysis complete")
    print(f"       - {len(gen.primary_clocks)} clocks")
    print(f"       - {len(gen.primary_resets)} resets")
    print(f"       - {sum(gen.cdc_sync_summary.values())} CDC synchronizers")

    # Generate outputs
    if args.both:
        text_file = f"{args.both}.rpt"
        html_file = f"{args.both}.html"
        gen.generate_text_report(text_file)
        gen.generate_html_report(html_file)
        print(f"\n[SUCCESS] Reports generated:")
        print(f"  Text: {text_file}")
        print(f"  HTML: {html_file}")
    else:
        if args.output:
            gen.generate_text_report(args.output)
            print(f"\n[SUCCESS] Text report: {args.output}")

        if args.html:
            gen.generate_html_report(args.html)
            print(f"\n[SUCCESS] HTML report: {args.html}")

        if args.dot:
            clock_dot, reset_dot = gen.generate_dot_files(args.dot)
            print(f"\n[SUCCESS] Clock DOT: {clock_dot}")
            print(f"[SUCCESS] Reset DOT: {reset_dot}")

    # Also print to stdout for preview
    if args.output and not args.both:
        print("\n" + "="*80)
        print("PREVIEW (first 30 lines):")
        print("="*80)
        with open(args.output, 'r') as f:
            lines = f.readlines()
            for line in lines[:30]:
                print(line.rstrip())
        if len(lines) > 30:
            print(f"\n... ({len(lines) - 30} more lines)")


if __name__ == '__main__':
    main()
