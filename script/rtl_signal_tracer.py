#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
RTLSignalTracer — lightweight RTL context extractor for Agent Team RTL Analyst.

Given a tree directory and a signal (optionally with hierarchy path),
finds the RTL file(s) that define/drive the signal and returns code context.

Strategy:
  1. Find VF file in tree (most recently modified *.vf under publish_rtl/)
  2. Parse VF for the list of RTL source files
  3. From hierarchical signal path, extract module name (second-to-last part)
  4. Find file(s) defining that module (by filename match, then grep 'module <name>')
  5. Return context: module header + lines around the signal + driving always/assign block

No full Verilog parsing — returns raw text for LLM reasoning.
"""

import glob
import os
import re
import subprocess


class RTLSignalTracer:
    """Lightweight RTL context extractor for violation analysis."""

    MAX_RTL_FILES = 8000

    def __init__(self, ref_dir):
        self.ref_dir = ref_dir
        self._rtl_files = None   # lazy-loaded
        self._vf_file = None
        self._vf_loaded = False

    # ------------------------------------------------------------------
    # VF file discovery
    # ------------------------------------------------------------------

    def _find_vf_file(self):
        """Find the most recently modified *.vf file under publish_rtl/ in ref_dir.
        Falls back to any *.vf under ref_dir if none found in publish_rtl/.
        Returns path string or None."""
        if self._vf_loaded:
            return self._vf_file
        self._vf_loaded = True

        # Try publish_rtl first (the canonical published file list)
        pattern = os.path.join(self.ref_dir, '**/publish_rtl/*.vf')
        matches = glob.glob(pattern, recursive=True)
        if matches:
            self._vf_file = max(matches, key=os.path.getmtime)
            return self._vf_file

        # Fallback: any *.vf under the tree
        pattern2 = os.path.join(self.ref_dir, '**/*.vf')
        matches2 = glob.glob(pattern2, recursive=True)
        if matches2:
            self._vf_file = max(matches2, key=os.path.getmtime)
            return self._vf_file

        return None

    # ------------------------------------------------------------------
    # RTL file list loading
    # ------------------------------------------------------------------

    def _load_rtl_files(self):
        """Return list of RTL file paths. Uses VF file if available, else glob src/."""
        if self._rtl_files is not None:
            return self._rtl_files

        vf = self._find_vf_file()
        found = []

        if vf and os.path.isfile(vf):
            try:
                with open(vf, errors='replace') as fh:
                    for line in fh:
                        line = line.strip()
                        # Skip comments, include dirs, -v/-f flags
                        if (not line or line.startswith('//')
                                or line.startswith('+incdir')
                                or line.startswith('-v ')
                                or line.startswith('-f ')
                                or line.startswith('-y ')
                                or line.startswith('+define')):
                            continue
                        # Accept .v / .sv / .vg paths
                        if re.search(r'\.(sv|v|vg)$', line, re.IGNORECASE):
                            # May be relative or absolute
                            if not os.path.isabs(line):
                                line = os.path.join(os.path.dirname(vf), line)
                            if os.path.exists(line):
                                found.append(os.path.normpath(line))
                        if len(found) >= self.MAX_RTL_FILES:
                            break
            except Exception:
                pass

        if not found:
            # Fallback: glob src/ for RTL files
            for pattern in ('src/**/*.sv', 'src/**/*.v', 'src/**/*.vg'):
                full = os.path.join(self.ref_dir, pattern)
                found.extend(glob.glob(full, recursive=True))
                if len(found) >= self.MAX_RTL_FILES:
                    break
            found = found[:self.MAX_RTL_FILES]

        self._rtl_files = found
        return self._rtl_files

    # ------------------------------------------------------------------
    # Signal path decomposition
    # ------------------------------------------------------------------

    @staticmethod
    def _module_from_path(signal_path: str) -> str:
        """Extract module name from hierarchical signal path.
        Input:  umc0.umccmd.REGCMD.REG.uumccmdrb.oQ_PETCtrl_tECSint[0]
        Output: uumccmdrb  (second-to-last dot-separated part, strip [..])
        """
        # Strip bus index suffix like [0], [3:0]
        clean = re.sub(r'\[.*?\]', '', signal_path).rstrip('.')
        parts = [p for p in clean.split('.') if p]
        if len(parts) >= 2:
            return parts[-2]
        return ''

    @staticmethod
    def _signal_leaf(signal_path: str) -> str:
        """Extract signal leaf name from hierarchical path.
        Input:  umc0.umccmd.REGCMD.REG.uumccmdrb.oQ_PETCtrl_tECSint[0]
        Output: oQ_PETCtrl_tECSint
        """
        clean = re.sub(r'\[.*?\]', '', signal_path).rstrip('.')
        parts = [p for p in clean.split('.') if p]
        return parts[-1] if parts else ''

    # ------------------------------------------------------------------
    # Module file discovery
    # ------------------------------------------------------------------

    def find_module_files(self, module_name: str) -> list:
        """Find RTL files that define 'module_name'.

        Strategy:
          1. Basename match in loaded RTL file list (case-insensitive)
          2. Fallback: grep -rl 'module <name>' under ref_dir/src/
        Returns up to 3 file paths.
        """
        if not module_name:
            return []

        rtl_files = self._load_rtl_files()
        mn_lower = module_name.lower()

        # Step 1: filename match
        matched = []
        for f in rtl_files:
            base = os.path.splitext(os.path.basename(f))[0].lower()
            if base == mn_lower:
                matched.append(f)
                if len(matched) >= 3:
                    return matched

        if matched:
            return matched

        # Step 2: grep fallback
        src_dir = os.path.join(self.ref_dir, 'src')
        if not os.path.isdir(src_dir):
            src_dir = self.ref_dir
        try:
            result = subprocess.run(
                ['grep', '-rl', f'module {module_name}',
                 '--include=*.sv', '--include=*.v', src_dir],
                capture_output=True, text=True, timeout=15
            )
            if result.returncode == 0:
                lines = [l.strip() for l in result.stdout.strip().split('\n') if l.strip()]
                return lines[:3]
        except Exception:
            pass

        return []

    # ------------------------------------------------------------------
    # Driving block finder
    # ------------------------------------------------------------------

    def find_driving_always(self, lines: list, signal_name: str, hit_line: int):
        """Find the enclosing always/assign block that drives signal_name.

        Walks backwards from hit_line to find always/assign block start,
        then forward to find the matching 'end'.

        Returns (start_line, end_line) as 0-based line indices.
        Fallback: (max(0, hit_line-5), min(len(lines)-1, hit_line+20))
        """
        # Walk backward to find always/assign
        start = None
        for i in range(hit_line, max(-1, hit_line - 200), -1):
            stripped = lines[i].lstrip()
            if (stripped.startswith('always') or stripped.startswith('assign')
                    or stripped.startswith('always_ff') or stripped.startswith('always_comb')
                    or stripped.startswith('always_latch')):
                start = i
                break

        if start is None:
            # No block found — return small window
            return (max(0, hit_line - 5), min(len(lines) - 1, hit_line + 20))

        # Walk forward to find the matching 'end'
        depth = 0
        end = min(len(lines) - 1, start + 100)
        for i in range(start, min(len(lines), start + 200)):
            s = lines[i].strip()
            if re.search(r'\bbegin\b', s):
                depth += 1
            if re.search(r'\bend\b', s) and not re.search(r'\bendmodule\b', s):
                depth -= 1
                if depth <= 0:
                    end = i
                    break

        return (start, end)

    # ------------------------------------------------------------------
    # Primary context extractors
    # ------------------------------------------------------------------

    def get_signal_context(self, signal_path: str, context_lines: int = 50) -> str:
        """Get RTL code context for a hierarchical signal path.

        Extracts:
          - Module name and leaf signal from signal_path
          - Module header (first 15 lines of file)
          - Lines around the signal definition/usage
          - Driving always/assign block if found

        Returns formatted string, or 'RTL NOT FOUND: ...' if nothing found.
        """
        module_name = self._module_from_path(signal_path)
        signal_leaf = self._signal_leaf(signal_path)

        if not module_name and not signal_leaf:
            return f"RTL NOT FOUND: empty signal path '{signal_path}'"

        files = self.find_module_files(module_name) if module_name else []

        if not files:
            return (f"RTL NOT FOUND: could not locate module '{module_name}' "
                    f"or signal '{signal_leaf}' in tree")

        half = max(10, context_lines // 2)
        sections = []

        for filepath in files[:2]:
            try:
                with open(filepath, errors='replace') as fh:
                    file_lines = fh.readlines()
            except Exception as e:
                sections.append(f"// --- {os.path.basename(filepath)} --- ERROR: {e}\n")
                continue

            # Find all lines containing signal_leaf (whole-word)
            pattern = re.compile(r'\b' + re.escape(signal_leaf) + r'\b')
            hits = [i for i, l in enumerate(file_lines) if pattern.search(l)]

            if not hits:
                # Signal not found in this file — include just module header
                header_end = min(15, len(file_lines))
                content = ''.join(file_lines[:header_end])
                sections.append(
                    f"// --- {os.path.basename(filepath)} (header only — signal not found) ---\n"
                    + content
                )
                continue

            # Prioritize hits that look like declarations or drivers
            priority_hits = [i for i in hits
                             if re.search(r'\b(reg|wire|logic|assign|always|output|input|parameter)\b',
                                          file_lines[i])]
            best_hit = priority_hits[0] if priority_hits else hits[0]

            # Find driving always/assign block
            block_start, block_end = self.find_driving_always(file_lines, signal_leaf, best_hit)

            # Build context: module header + block
            module_header_end = min(15, len(file_lines))
            header_text = ''.join(file_lines[:module_header_end])

            # Context window around best_hit (capped)
            ctx_start = max(0, best_hit - half)
            ctx_end   = min(len(file_lines), best_hit + half)

            # Expand to include driving block
            ctx_start = min(ctx_start, block_start)
            ctx_end   = max(ctx_end,   block_end + 1)

            # Cap total context size
            if ctx_end - ctx_start > context_lines * 3:
                ctx_end = ctx_start + context_lines * 3

            snippet = ''.join(file_lines[ctx_start:ctx_end])

            sections.append(
                f"// --- {os.path.basename(filepath)} (lines {ctx_start+1}-{ctx_end}) ---\n"
                + header_text
                + "\n// ... context ...\n"
                + snippet
            )

        if not sections:
            return (f"RTL NOT FOUND: could not locate module '{module_name}' "
                    f"or signal '{signal_leaf}' in tree")

        return '\n'.join(sections)

    def get_port_context(self, filename: str, line_number, port_name: str,
                         context_lines: int = 60) -> str:
        """Get RTL context for a lint violation with exact filename + line number.

        Returns module header (first 15 lines) + window around line_number.
        Used for lint violations where the report gives an exact file + line.
        """
        if not filename or not os.path.isfile(filename):
            # Try resolving relative to ref_dir
            candidate = os.path.join(self.ref_dir, filename) if self.ref_dir else ''
            if candidate and os.path.isfile(candidate):
                filename = candidate
            else:
                return f"FILE NOT FOUND: {filename}"

        try:
            with open(filename, errors='replace') as fh:
                file_lines = fh.readlines()
        except Exception as e:
            return f"FILE NOT FOUND: {filename} ({e})"

        # Convert line_number to 0-based index
        try:
            ln = int(str(line_number)) - 1
        except (ValueError, TypeError):
            ln = 0
        ln = max(0, min(ln, len(file_lines) - 1))

        half = context_lines // 2
        header_end = min(15, len(file_lines))
        header_text = ''.join(file_lines[:header_end])

        ctx_start = max(0, ln - half)
        ctx_end   = min(len(file_lines), ln + half)

        snippet = ''.join(file_lines[ctx_start:ctx_end])

        return (
            f"// --- {os.path.basename(filename)} (lines {ctx_start+1}-{ctx_end}) ---\n"
            + header_text
            + "\n// ... context around line {ln+1} ...\n"
            + snippet
        )
