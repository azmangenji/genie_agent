#!/usr/bin/env python3
"""
eco_pre_fm_check.py — Deterministic Step 5 Pre-FM Quality Checker

Replaces agent judgment in eco_pre_fm_checker.md with a script that
reads the applied JSON + study JSON and validates all required conditions.
No agent decisions — every check is deterministic: PASS or FAIL.

Usage:
    python3 eco_pre_fm_check.py \
        --tag <TAG> \
        --round <N> \
        --base-dir <BASE_DIR> \
        --ref-dir <REF_DIR> \
        --jira <JIRA>

Exit 0 = all checks PASS (safe to submit FM)
Exit 1 = any check FAIL (do NOT submit FM)

Writes:
    <BASE_DIR>/data/<TAG>_eco_pre_fm_check_round<N>.json
    <BASE_DIR>/data/<TAG>_eco_step5_pre_fm_check_round<N>.rpt
    <BASE_DIR>/data/<TAG>_eco_step5_pre_fm_check_round<N>_marker.txt
"""

import argparse, json, os, re, subprocess, sys
from pathlib import Path


# ── Argument parsing ──────────────────────────────────────────────────────────

def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument('--tag',      required=True)
    p.add_argument('--round',    required=True, type=int)
    p.add_argument('--base-dir', required=True, dest='base_dir')
    p.add_argument('--ref-dir',  required=True, dest='ref_dir')
    p.add_argument('--jira',     required=True)
    return p.parse_args()


# ── Helpers ───────────────────────────────────────────────────────────────────

def load_json(path):
    try:
        return json.load(open(path))
    except Exception as e:
        return None


def zgrep_count(pattern, gz_path):
    try:
        r = subprocess.run(
            f'zcat {gz_path} | grep -c {re.escape(pattern)}',
            shell=True, capture_output=True, text=True, timeout=120
        )
        return int(r.stdout.strip()) if r.stdout.strip().isdigit() else 0
    except Exception:
        return 0


DEFERRED_REASONS = ('deferred', 'pending', 'round 2', 'application', 'defer')

def is_deferred(reason):
    r = (reason or '').lower()
    return any(k in r for k in DEFERRED_REASONS)


# ── Check implementations ─────────────────────────────────────────────────────

def check_no_deferred(applied):
    """
    FAIL if any port_declaration or port_connection entry is SKIPPED
    with a deferral reason. These cause FM ABORT.
    """
    failures = []
    for stage, entries in applied.items():
        if not isinstance(entries, list):
            continue
        for e in entries:
            ct = e.get('change_type', '')
            st = e.get('status', '')
            reason = e.get('reason', '')
            if ct in ('port_declaration', 'port_promotion', 'port_connection') \
               and st == 'SKIPPED' and is_deferred(reason):
                failures.append(f'{stage}: {ct} {e.get("name","?")} — {reason[:80]}')
    return failures


def check_stage_consistency(applied):
    """
    FAIL if an ECO gate is INSERTED in some stages but SKIPPED in others.
    Each new_logic_gate/dff must appear in all 3 stages.
    """
    gate_types = ('new_logic_gate', 'new_logic_dff', 'new_logic')
    per_stage = {}
    for stage, entries in applied.items():
        if not isinstance(entries, list):
            continue
        inserted = {e.get('name','') for e in entries
                    if e.get('change_type','') in gate_types
                    and e.get('status','') == 'INSERTED'}
        skipped  = {e.get('name','') for e in entries
                    if e.get('change_type','') in gate_types
                    and e.get('status','') == 'SKIPPED'}
        per_stage[stage] = {'inserted': inserted, 'skipped': skipped}

    stages = [s for s in per_stage if per_stage[s]['inserted'] or per_stage[s]['skipped']]
    if len(stages) < 2:
        return []

    all_gates = set()
    for s in stages:
        all_gates |= per_stage[s]['inserted'] | per_stage[s]['skipped']

    failures = []
    for gate in sorted(all_gates):
        stage_results = {}
        for s in stages:
            if gate in per_stage[s]['inserted']:
                stage_results[s] = 'INSERTED'
            elif gate in per_stage[s]['skipped']:
                stage_results[s] = 'SKIPPED'
            else:
                stage_results[s] = 'MISSING'
        if len(set(stage_results.values())) > 1:
            failures.append(f'{gate}: {stage_results}')
    return failures


def check_port_declarations_applied(applied):
    """
    FAIL if any port_declaration/port_connection is SKIPPED (for any reason).
    These are all mandatory — no deferral, no skipping.
    Exception: 'wire' type entries (implicitly created) and ALREADY_APPLIED.
    """
    failures = []
    for stage, entries in applied.items():
        if not isinstance(entries, list):
            continue
        for e in entries:
            ct = e.get('change_type', '')
            st = e.get('status', '')
            name = e.get('name', '?')
            reason = e.get('reason', '')
            if ct in ('port_declaration', 'port_promotion', 'port_connection') \
               and st == 'SKIPPED' \
               and 'wire' not in reason.lower() \
               and 'implicit' not in reason.lower():
                failures.append(f'{stage}: {ct} {name} SKIPPED — {reason[:80]}')
    return failures


def check_no_unhandled(applied):
    """
    FAIL if any entry has status UNHANDLED — indicates eco_perl_spec didn't
    recognize the change_type, so it was silently dropped.
    """
    failures = []
    for stage, entries in applied.items():
        if not isinstance(entries, list):
            continue
        for e in entries:
            if e.get('status','') == 'UNHANDLED':
                failures.append(
                    f'{stage}: {e.get("change_type","?")} {e.get("name","?")} UNHANDLED')
    return failures


def check_check8(check8_json_path):
    """
    Read pre-computed eco_check8 result. FAIL if any stage is not PASS.
    """
    d = load_json(check8_json_path)
    if d is None:
        return ['eco_check8 result not found — cannot validate Verilog syntax']
    failures = []
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        result = d.get(stage, 'MISSING')
        if result != 'PASS':
            failures.append(f'eco_check8 {stage}: {result}')
    return failures


def check_cells_in_netlist(applied, ref_dir):
    """
    FAIL if any gate marked INSERTED in applied JSON is physically absent
    from the PostEco netlist. eco_perl_spec can mark INSERTED but fail to
    actually inject the cell (e.g., module not found in large hierarchical netlist).
    eco_pre_fm_check reads JSON status — this check reads the actual netlist.
    """
    gate_types = ('new_logic_gate', 'new_logic_dff', 'new_logic')
    failures = []
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        entries = applied.get(stage, [])
        if not isinstance(entries, list):
            continue
        gz = os.path.join(ref_dir, 'data', 'PostEco', f'{stage}.v.gz')
        if not os.path.exists(gz):
            continue
        inserted = [e.get('name','') for e in entries
                    if e.get('change_type','') in gate_types
                    and e.get('status','') == 'INSERTED'
                    and e.get('name','')]
        if not inserted:
            continue
        # Grep PostEco for each inserted instance name
        for inst in inserted:
            if not inst:
                continue
            try:
                r = subprocess.run(
                    f'zcat {gz} | grep -cF " {inst} ("',
                    shell=True, capture_output=True, text=True, timeout=120
                )
                count = int(r.stdout.strip()) if r.stdout.strip().isdigit() else 0
                if count == 0:
                    failures.append(
                        f'[GHOST_INSERT] {stage}: {inst} marked INSERTED in JSON '
                        f'but NOT found in PostEco/{stage}.v.gz — Perl spec generated '
                        f'but module not found in netlist'
                    )
            except Exception:
                pass
    return failures


def check_port_edits_in_netlist(ref_dir, applied):
    """For every applied port_declaration / port_connection entry, verify the
    edit is physically in the netlist. Catches the silent-failure pattern where
    eco_passes_2_4.py reported APPLIED but the regex sub did nothing because
    the target line wasn't in inst_close / port list spanned multiple lines.

    Reads the entry's `reason` text to extract signal/port/net since the applied
    JSON entries are minimal (only ct/status/name/reason).
    """
    failures = []
    # Reason patterns:
    #   'added NeedFreqAdj to port list and output decl in ddrss_umccmd_t_umcarbctrlsw'
    #   'added .NeedFreqAdj(ARB_FEI_NeedFreqAdj) to CTRLSW'
    #   'rewired existing .X to (Y) in INST'
    #   'bus_rename: REGCMD.REG_UmcCfgEco[1] OLD→NEW'  (skipped — Check 9 covers)
    pdec_re   = re.compile(r'added\s+(\S+)\s+to\s+port\s+list\s+and\s+(input|output|inout|wire)\s+decl\s+in\s+(\S+)')
    pconn_add_re = re.compile(r'added\s+\.(\w+)\s*\(\s*(\S+?)\s*\)\s+to\s+(\w+)')
    pconn_rew_re = re.compile(r'rewired\s+existing\s+\.(\w+)\s+to\s+\(\s*(\S+?)\s*\)\s+in\s+(\w+)')
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        gz = os.path.join(ref_dir, 'data', 'PostEco', f'{stage}.v.gz')
        if not os.path.exists(gz):
            continue
        try:
            raw = subprocess.run(['zcat', gz], capture_output=True, text=True, timeout=240).stdout
        except Exception:
            continue
        text = strip_verilog_comments(raw)  # Option A: comments don't count
        for e in applied.get(stage, []):
            if e.get('status') != 'APPLIED':
                continue
            # Support both 'ct' (passes_2_4 JSON) and 'change_type' (study JSON)
            ct = e.get('ct') or e.get('change_type', '')
            reason = e.get('reason', '')
            if ct == 'port_declaration':
                m = pdec_re.search(reason)
                signal = m.group(1) if m else (e.get('signal_name') or e.get('name', ''))
                direction = m.group(2) if m else e.get('declaration_type', 'input')
                if direction == 'wire' or not signal:
                    continue
                if not re.search(rf'^\s*(input|output|inout)\s+{re.escape(signal)}\b', text, re.MULTILINE):
                    failures.append(f'[PORT_DECL_MISSING] {stage}: port_declaration APPLIED for {signal!r} ({direction}) but no input/output decl found in netlist')
            elif ct == 'port_connection':
                # Skip bus_bit_index entries (handled by Check 9 / bus_concat_intact)
                if e.get('bus_bit_index') is not None or 'bus_rename' in reason:
                    continue
                m = pconn_add_re.search(reason) or pconn_rew_re.search(reason)
                if m:
                    port, net, inst = m.group(1), m.group(2), m.group(3)
                else:
                    inst = e.get('instance_name') or e.get('submodule_instance')
                    port = e.get('port_name')   or e.get('new_token')
                    net  = e.get('net_name')    or e.get('flat_net_name')
                if not all([inst, port, net]):
                    continue
                pat = rf'\.\s*{re.escape(port)}\s*\(\s*{re.escape(net)}\s*\)'
                if not re.search(pat, text):
                    failures.append(f'[PORT_CONN_MISSING] {stage}: port_connection APPLIED .{port}({net}) on {inst} but not found in netlist')
    return failures


def check_semantic_verify(study_path, ref_dir):
    """Check 12 — Full semantic equivalence between Step 3 study JSON intent
    and PostEco netlist. Wraps eco_semantic_verify.NetlistView + per-entry-type
    verifiers. Catches what regex spot checks miss: comment-masked edits,
    bus-bit-position mismatches, wrong-instance matches, port-direction
    inconsistencies. Comprehensive — covers every confirmed study entry.
    """
    failures = []
    if not os.path.exists(study_path):
        return [f'[SEMANTIC] study JSON not found: {study_path}']
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    try:
        import eco_semantic_verify as esv
    except Exception as e:
        return [f'[SEMANTIC] cannot import eco_semantic_verify: {e}']
    try:
        with open(study_path) as f:
            study = json.load(f)
    except Exception as e:
        return [f'[SEMANTIC] cannot read study JSON: {e}']
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        gz = os.path.join(ref_dir, 'data', 'PostEco', f'{stage}.v.gz')
        if not os.path.exists(gz):
            continue
        try:
            raw = subprocess.run(['zcat', gz], capture_output=True, text=True, timeout=300).stdout
        except Exception as e:
            failures.append(f'[SEMANTIC] {stage} netlist read err: {e}')
            continue
        view = esv.NetlistView(raw)
        for entry in study.get(stage, []):
            if not entry.get('confirmed', True):
                continue
            ct = entry.get('change_type', '')
            verifier = esv.VERIFIERS.get(ct)
            if verifier is None:
                continue
            err = verifier(entry, view, stage)
            if err:
                failures.append(f'[SEMANTIC_{ct.upper()}] {stage}: {err}')
    return failures


def strip_verilog_comments(text):
    """Remove // line comments and /* */ block comments. Critical for any
    semantic check on netlist content — Verilog comments don't count toward
    signal references, port concat positions, or driver declarations.
    """
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
    text = re.sub(r'//[^\n]*', '', text)
    return text


def parse_bus_concat_at_instance(text_no_comments, instance_name, port_name):
    """Find .port_name({...}) on instance_name; return parsed list of nets.
    Returns None if not found or not a {} concat. text_no_comments must already
    be comment-stripped — caller's responsibility.
    """
    inst_m = re.search(rf'\b{re.escape(instance_name)}\s*\(', text_no_comments)
    if not inst_m:
        return None
    block = text_no_comments[inst_m.start():inst_m.start() + 200000]
    port_m = re.search(rf'\.\s*{re.escape(port_name)}\s*\(\s*\{{([^{{}}]*)\}}', block, re.DOTALL)
    if not port_m:
        return None
    return [e.strip() for e in port_m.group(1).split(',')]


def check_rewires_in_netlist(ref_dir, applied):
    """For every applied rewire entry, verify the netlist's cell.pin actually
    points to new_net (not old_net). Catches silent-rewire-no-op pattern where
    apply_rewire's regex matched something but didn't change the right line.
    """
    failures = []
    # Reason format from apply_rewire: '{cell}.{pin}: {old} → {new}' (Unicode arrow)
    rew_re = re.compile(r'(\S+)\.(\w+):\s+(\S+)\s*(?:→|->|—>)\s*(\S+)')
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        gz = os.path.join(ref_dir, 'data', 'PostEco', f'{stage}.v.gz')
        if not os.path.exists(gz):
            continue
        try:
            raw = subprocess.run(['zcat', gz], capture_output=True, text=True, timeout=240).stdout
        except Exception:
            continue
        text = strip_verilog_comments(raw)  # Option A: comments don't count
        for e in applied.get(stage, []):
            if e.get('status') != 'APPLIED':
                continue
            ct = e.get('ct') or e.get('change_type', '')
            if ct != 'rewire':
                continue
            m = rew_re.search(e.get('reason', ''))
            if not m:
                continue
            cell, pin, old_net, new_net = m.groups()
            # Find the cell instance in the netlist (best-effort by name)
            inst_m = re.search(rf'\b{re.escape(cell)}\s*\(', text)
            if not inst_m:
                failures.append(f'[REWIRE_CELL_MISSING] {stage}: rewire APPLIED on {cell}.{pin} but cell not found in netlist')
                continue
            cell_block = text[inst_m.start():inst_m.start() + 50000]
            if not re.search(rf'\.\s*{re.escape(pin)}\s*\(\s*{re.escape(new_net)}\s*\)', cell_block):
                failures.append(f'[REWIRE_MISSING] {stage}: rewire APPLIED {cell}.{pin}: {old_net}→{new_net} but .{pin}({new_net}) not in cell block')
    return failures


def check_bus_concat_intact(ref_dir, applied):
    """SEMANTIC bus-concat verification (Option B): comment-strip the netlist,
    parse the {...} content, and verify the renamed net is at the correct
    bus_bit_index position. Catches:
      - Bus collapsed to single net (Check 9 v1 pattern)
      - Rename text inside a comment (today's failure mode)
      - Rename applied to wrong bit position
      - Rename applied to wrong instance (multi-match)
    """
    failures = []
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        gz = os.path.join(ref_dir, 'data', 'PostEco', f'{stage}.v.gz')
        if not os.path.exists(gz):
            continue
        # Both 'change_type' (study schema) and 'ct' (passes_2_4 schema) supported
        bus_entries = [e for e in applied.get(stage, [])
                       if (e.get('change_type') == 'port_connection' or e.get('ct') == 'port_connection')
                       and e.get('bus_bit_index') is not None]
        if not bus_entries:
            continue
        try:
            raw = subprocess.run(['zcat', gz], capture_output=True, text=True, timeout=240).stdout
        except Exception:
            continue
        text = strip_verilog_comments(raw)
        for e in bus_entries:
            inst = e.get('instance_name') or e.get('submodule_instance', '')
            port = e.get('port_name', '')
            new_net = e.get('net_name') or e.get('net_name_after', '')
            bbi  = e.get('bus_bit_index')
            if not all([inst, port, new_net]) or bbi is None:
                continue
            elements = parse_bus_concat_at_instance(text, inst, port)
            if elements is None:
                failures.append(f'[BUS_CONCAT_MISSING] {stage}: {inst}.{port} no {{}} concat found in active code (possibly collapsed or in comment)')
                continue
            width = len(elements)
            pos = width - 1 - bbi  # MSB-first
            if pos < 0 or pos >= width:
                failures.append(f'[BUS_BIT_RANGE] {stage}: {inst}.{port} bus_bit_index={bbi} out of range (width={width})')
                continue
            actual = elements[pos]
            if actual != new_net:
                failures.append(f'[BUS_BIT_WRONG_NET] {stage}: {inst}.{port}[{bbi}] = {actual!r} but expected {new_net!r} — rename did not take effect at bit position')
    return failures


def check_undriven_eco_nets(ref_dir):
    """
    FAIL if any n_eco_* net in PostEco netlist has < 2 occurrences in ACTIVE
    code (comments stripped). A driven net has at least one driver reference
    (cell output / wire decl / port concat slot) AND at least one consumer
    reference. Fewer than 2 in active code → likely no driver.
    """
    failures = []
    NET_RE = re.compile(r'\b(n_eco_[A-Za-z0-9_]+)\b')
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        gz = os.path.join(ref_dir, 'data', 'PostEco', f'{stage}.v.gz')
        if not os.path.exists(gz):
            continue
        try:
            text = subprocess.run(['zcat', gz], capture_output=True, text=True, timeout=240).stdout
        except Exception:
            continue
        text = strip_verilog_comments(text)  # Option A: comments don't count
        from collections import Counter
        counts = Counter(NET_RE.findall(text))
        for net, c in sorted(counts.items()):
            if c < 2:
                failures.append(f'[UNDRIVEN_NET] {stage}: {net} appears only {c} time(s) in active code — no driver (bus-rename or driver insertion likely failed)')
    return failures


def check_eco_input_drivers(study_path, ref_dir):
    """Check 13 — for every confirmed new_logic_gate / new_logic_dff entry in the
    study JSON, verify each input pin's per-stage net actually has a driver
    IN THE SAME HOST MODULE in the PostEco netlist.

    SCOPE-AWARE: previous version used a global driven set, which let
    `IReset` pass even when umcarbctrlsw's local wire was renamed by P&R
    to `test_so4927` and the chain still referenced bare `IReset` (just
    because some OTHER module wired up `.<port>(IReset)`). Now we build
    the driven set per host module so this class of bug fails fast.

    Constants like 1'b0/1'b1 are skipped."""
    failures = []
    OUT_PINS = {'Z', 'ZN', 'ZN1', 'Q', 'QN', 'CO'}
    try:
        study = json.loads(Path(study_path).read_text())
    except Exception as e:
        return [f'[INPUT_DRIVER_READ_ERR] {e}']

    def _drivers_in_module(mod_text):
        """Build the set of nets that have a driver inside mod_text."""
        driven = set()
        # Strip comments first so a commented-out previous-ECO `.Q(net)`
        # doesn't fake-drive the net.
        body = strip_verilog_comments(mod_text)
        for m in re.finditer(r'\.\s*(?:Z|ZN|ZN1|Q|QN|CO|Q1|Q2|Q3|Q4|Q5|Q6|Q7|Q8)\s*\(\s*(\w+)', body):
            driven.add(m.group(1))
        for m in re.finditer(r'^\s*wire\s+(?:\[[^\]]+\]\s+)?(\w+)\s*[;,]', body, re.MULTILINE):
            driven.add(m.group(1))
        for m in re.finditer(r'^\s*(?:input|inout)\s+(?:\[[^\]]+\]\s+)?(\w+)\s*[;,]', body, re.MULTILINE):
            driven.add(m.group(1))
        # Submodule INSTANCE output ports — bare net or bus concat
        for m in re.finditer(r'\.\s*\w+\s*\(\s*([A-Za-z_][\w]*)\s*\)', body):
            driven.add(m.group(1))
        for m in re.finditer(r'\.\s*\w+\s*\(\s*\{([^{}]+)\}\s*\)', body):
            for w in re.findall(r'[A-Za-z_]\w*', m.group(1)):
                driven.add(w)
        return driven

    for stage in ('Synthesize', 'PrePlace', 'Route'):
        gz = os.path.join(ref_dir, 'data', 'PostEco', f'{stage}.v.gz')
        if not os.path.exists(gz):
            continue
        try:
            text = subprocess.run(['zcat', gz], capture_output=True, text=True, timeout=240).stdout
        except Exception:
            continue
        # Cache per-module driven sets — built lazily on first lookup.
        per_mod_cache = {}
        def _drivers_for(mod):
            if mod in per_mod_cache:
                return per_mod_cache[mod]
            for cand in (mod, mod + '_0'):
                m = re.search(rf'^module\s+{re.escape(cand)}\b.*?^endmodule\b',
                              text, re.MULTILINE | re.DOTALL)
                if m:
                    per_mod_cache[mod] = _drivers_in_module(m.group(0))
                    return per_mod_cache[mod]
            per_mod_cache[mod] = set()
            return per_mod_cache[mod]

        for entry in study.get(stage, []):
            if entry.get('change_type') not in ('new_logic_gate', 'new_logic_dff', 'new_logic'):
                continue
            if not entry.get('confirmed', True):
                continue
            inst = entry.get('instance_name', '?')
            host = entry.get('module_name', '')
            if not host:
                # Fall back to global scan if host module unknown — old behavior
                continue
            local_driven = _drivers_for(host)
            pcs = (entry.get('port_connections_per_stage') or {}).get(stage) or entry.get('port_connections') or {}
            for pin, val in pcs.items():
                if pin in OUT_PINS or not isinstance(val, str):
                    continue
                base = re.sub(r'\[[^\]]*\]', '', val).strip()
                if not base or base.startswith(("1'b", "0'b", "1'h", "0'h")):
                    continue
                if base not in local_driven:
                    failures.append(
                        f'[INPUT_UNDRIVEN] {stage}: {inst}.{pin}={val!r} in host '
                        f'module {host!r} — net has no driver in this module body. '
                        f'Likely per-stage rename was missed (e.g. P&R renamed the '
                        f'driver from {val} to a stage-specific name).')
    return failures


def check_duplicate_ports(ref_dir):
    """Check D — no duplicate port names in any module port list header.
    Duplicate ports cause Verilog compile errors that block FM elaboration.
    Returns list of failure strings."""
    failures = []
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        gz = os.path.join(ref_dir, 'data', 'PostEco', f'{stage}.v.gz')
        if not os.path.exists(gz):
            continue
        try:
            text = subprocess.run(['zcat', gz], capture_output=True, text=True, timeout=240).stdout
        except Exception:
            continue
        text = strip_verilog_comments(text)
        for mod_m in re.finditer(r'^module\s+(\w+)\s*\(([^)]+)\)', text, re.MULTILINE):
            mod_name = mod_m.group(1)
            port_list = mod_m.group(2)
            ports = re.findall(r'\b([A-Za-z_]\w*)\b', port_list)
            kw = {'input', 'output', 'inout', 'wire', 'reg', 'logic', 'integer'}
            seen, dups = {}, []
            for p in ports:
                if p in kw:
                    continue
                seen[p] = seen.get(p, 0) + 1
                if seen[p] == 2:
                    dups.append(p)
            if dups:
                failures.append(f'[DUPLICATE_PORT] {stage}: module {mod_name!r} has duplicate port(s): {dups}')
    return failures


def check_eco_output_pin_names(applied, ref_dir):
    """Check H — ECO cell output pin names must match the cell's actual output pin.
    Wrong output pin causes FE-LINK-7 ABORT_LINK (FM cannot build verification model).
    The most common mistake: MUX2 output is Z not ZN; IND2 is ZN not Z.
    Returns list of failure strings."""
    GATE_OUTPUT_PIN = {
        'AND2': 'Z', 'AND3': 'Z', 'AND4': 'Z',
        'OR2':  'Z', 'OR3':  'Z', 'OR4':  'Z',
        'XOR2': 'Z', 'XOR3': 'Z',
        'MUX2': 'Z', 'MUX4': 'Z',
        'INV':  'ZN',
        'NAND2': 'ZN', 'NAND3': 'ZN', 'NAND4': 'ZN',
        'NOR2':  'ZN', 'NOR3':  'ZN', 'NOR4':  'ZN',
        'XNOR2': 'ZN', 'IND2': 'ZN', 'IND3': 'ZN',
        'DFF': 'Q', 'SDFF': 'Q', 'SDFQ': 'Q',
        'AOI21': 'ZN', 'AOI22': 'ZN', 'OAI21': 'ZN', 'OAI22': 'ZN',
        'AO21': 'Z',  'AO22': 'Z',  'OA21': 'Z',  'OA22': 'Z',
        'INR3': 'ZN', 'IND3': 'ZN', 'IAOI21': 'ZN',
    }
    import sys as _sys
    _sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    try:
        import eco_cell_truth_tables as _ett
        _have_ett = True
    except ImportError:
        _have_ett = False

    failures = []
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        for entry in applied.get(stage, []):
            if entry.get('change_type') not in ('new_logic_gate', 'new_logic', 'new_logic_dff'):
                continue
            if entry.get('status') not in ('INSERTED', 'ALREADY_APPLIED'):
                continue
            cell = entry.get('cell_type', '')
            fn   = entry.get('gate_function', '')
            inst = entry.get('instance_name', '?')
            out_net = entry.get('output_net', '')
            pcs  = entry.get('port_connections', {})
            if not cell or not pcs:
                continue
            # Determine expected output pin: prefer Liberty lookup, then gate_function table, then GATE_OUTPUT_PIN
            expected_pin = None
            if _have_ett:
                tt = _ett.truth_table_of(cell)
                if tt:
                    expected_pin = next(iter(tt.keys()))  # first (usually only) output pin
            if not expected_pin and fn:
                family = fn.replace('2','').replace('3','').replace('4','').rstrip('0123456789')
                expected_pin = GATE_OUTPUT_PIN.get(fn) or GATE_OUTPUT_PIN.get(family)
            if not expected_pin:
                continue  # cannot determine — skip
            # Find which pin in port_connections has the output_net
            actual_out_pins = [p for p, n in pcs.items() if n == out_net]
            if not actual_out_pins:
                continue  # output_net not in port_connections — skip
            for actual in actual_out_pins:
                if actual != expected_pin:
                    failures.append(
                        f'[WRONG_OUTPUT_PIN] {stage}: {inst} output_pin={actual!r} '
                        f'but cell {cell!r} (fn={fn!r}) expects {expected_pin!r}. '
                        f'Rename .{actual}({out_net}) → .{expected_pin}({out_net}) in PostEco.')
    return failures


def check_missing_output_port_decls(applied, ref_dir):
    """Check B2 — if an ECO cell's output net is referenced OUTSIDE its declaring module
    (i.e., used as an argument to a parent-level port connection), a port_declaration
    entry must have been applied for that net. Missing causes FE-LINK-7 ABORT_LINK.
    Returns list of failure strings."""
    failures = []
    OUT_TYPES = ('new_logic_gate', 'new_logic_dff', 'new_logic')
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        entries = applied.get(stage, [])
        if not isinstance(entries, list):
            continue
        # Build set of ECO output nets with their declaring module
        eco_outputs = {}  # output_net → (inst, module_name)
        for e in entries:
            if e.get('change_type') not in OUT_TYPES or e.get('status') not in ('INSERTED', 'ALREADY_APPLIED'):
                continue
            out_net = e.get('output_net', '')
            mod     = e.get('module_name', '')
            inst    = e.get('instance_name', '?')
            if out_net and mod:
                eco_outputs[out_net] = (inst, mod)
        if not eco_outputs:
            continue
        # Build set of port_declaration entries that were APPLIED for this stage
        declared = set()
        for e in entries:
            if e.get('change_type') == 'port_declaration' and e.get('status') in ('APPLIED', 'ALREADY_APPLIED'):
                declared.add(e.get('signal_name', ''))
        gz = os.path.join(ref_dir, 'data', 'PostEco', f'{stage}.v.gz')
        if not os.path.exists(gz):
            continue
        try:
            text = subprocess.run(['zcat', gz], capture_output=True, text=True, timeout=240).stdout
        except Exception:
            continue
        text = strip_verilog_comments(text)
        for out_net, (inst, mod) in eco_outputs.items():
            # Count occurrences in full netlist vs inside declaring module
            total = len(re.findall(rf'\b{re.escape(out_net)}\b', text))
            mod_m = re.search(rf'^module\s+{re.escape(mod)}(?:_0)?\b.*?^endmodule\b', text, re.DOTALL | re.MULTILINE)
            local = len(re.findall(rf'\b{re.escape(out_net)}\b', mod_m.group(0))) if mod_m else 0
            if total > local and out_net not in declared:
                failures.append(
                    f'[MISSING_OUTPUT_PORT] {stage}: ECO net {out_net!r} (from {inst} in {mod}) '
                    f'referenced {total - local} time(s) outside its module but no port_declaration applied.')
    return failures


def check_port_conn_target_exists(study_path, ref_dir):
    """Check B3 — for every `port_connection` entry in the study, verify that
    the target port_name actually appears in the target module's port list in
    the PostEco netlist. Catches the FE-LINK-7 ABORT class (observed on 9868
    fresh run R1: port_connection .NeedFreqAdj on CTRLSW had no matching port
    on umcarbctrlsw → FM aborted before any verify).

    Mirrors Step 3 Check 3e but checks the LIVE netlist instead of the study,
    giving defense-in-depth: even if the studier emits the right port_decl
    entry, a Pass 2 failure would still be caught here before FM runs.
    """
    failures = []
    try:
        study = json.loads(Path(study_path).read_text())
    except Exception as e:
        return [f'[PORT_CONN_TARGET_READ_ERR] {e}']
    pc_entries = []
    for e in study.get('Synthesize', []):
        if e.get('change_type') == 'port_connection':
            pc_entries.append(e)
    if not pc_entries:
        return failures
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        gz = os.path.join(ref_dir, 'data', 'PostEco', f'{stage}.v.gz')
        if not os.path.exists(gz):
            continue
        try:
            text = subprocess.run(['zcat', gz], capture_output=True,
                                  text=True, timeout=240).stdout
        except Exception:
            continue
        text = strip_verilog_comments(text)
        # Cache: child_module → set of declared port names
        port_cache = {}
        def _ports_of(mod):
            if mod in port_cache:
                return port_cache[mod]
            ports = set()
            for cand in (mod, mod + '_0'):
                m = re.search(
                    rf'^module\s+{re.escape(cand)}\b.*?^endmodule\b',
                    text, re.MULTILINE | re.DOTALL)
                if not m:
                    continue
                body = m.group(0)
                for pm in re.finditer(
                        r'^\s*(?:input|output|inout)\s+(?:\[[^\]]+\]\s*)?'
                        r'([A-Za-z_]\w*)\s*[;,]', body, re.MULTILINE):
                    ports.add(pm.group(1))
                # Also pick up ports from the header port list (some files only
                # name them in the header and declare direction inline)
                hdr = re.search(rf'^module\s+{re.escape(cand)}\s*\(([^)]*)\)',
                                body, re.MULTILINE | re.DOTALL)
                if hdr:
                    for tok in re.findall(r'[A-Za-z_]\w*', hdr.group(1)):
                        ports.add(tok)
                break
            port_cache[mod] = ports
            return ports
        for e in pc_entries:
            child_mod = e.get('child_module_name') or ''
            if not child_mod:
                continue  # Step 3 Check 3e already flags this
            port = e.get('port_name', '')
            if not port:
                continue
            ports = _ports_of(child_mod)
            if not ports:
                continue  # module not found in netlist — separate concern
            if port not in ports:
                failures.append(
                    f'[PORT_CONN_TARGET_MISSING] {stage}: port_connection '
                    f'{e.get("instance_name","?")}.{port} → {child_mod}: '
                    f'port {port!r} NOT in module port list. FE-LINK-7 ABORT risk.')
    return failures


def check_mode_s_stitching(study_path, ref_dir):
    """Check 14 — for every new_logic_dff with mode_S_applied=true (or
    requires_scan_stitching=true) in the study JSON, verify the host module
    has the 3 stitching ports (SI_in, SE_in, Q_out) declared in the netlist
    AND the assign statement is present AND the DFF's per-stage SE/SI use
    those ports (NOT 1'b0) in PrePlace and Route stages.
    """
    failures = []
    try:
        study = json.loads(Path(study_path).read_text())
    except Exception as e:
        return [f'[MODE_S_READ_ERR] {e}']
    for stage in ('PrePlace', 'Route'):
        gz = os.path.join(ref_dir, 'data', 'PostEco', f'{stage}.v.gz')
        if not os.path.exists(gz):
            continue
        try:
            text = subprocess.run(['zcat', gz], capture_output=True, text=True, timeout=240).stdout
        except Exception:
            continue
        text = strip_verilog_comments(text)
        for entry in study.get(stage, []):
            if entry.get('change_type') not in ('new_logic_dff', 'new_logic'):
                continue
            if not entry.get('confirmed', True):
                continue
            if not (entry.get('mode_S_applied') or entry.get('requires_scan_stitching')):
                continue
            # Per-stage strategy: only check bridge wiring when this stage uses
            # `bridge_port`. `neighbor_dff` strategy in this stage means the DFF's
            # SE/SI point at a neighbor-DFF net (no bridge needed in this stage).
            strat_per_stage = entry.get('mode_S_strategy_per_stage') or {}
            this_stage_strat = strat_per_stage.get(stage)
            if this_stage_strat == 'neighbor_dff':
                continue
            inst = entry.get('instance_name', '?')
            host = entry.get('module_name', '')
            if not host:
                continue
            # Find host module (with possible _0 suffix in Route)
            mod_m = re.search(rf'^module\s+{re.escape(host)}(?:_0)?\b.*?^endmodule\b',
                              text, re.MULTILINE | re.DOTALL)
            if not mod_m:
                failures.append(f'[MODE_S_MODULE_MISSING] {stage}: host module {host!r} not found for {inst}')
                continue
            body = mod_m.group(0)
            # Look for the 3 stitching port declarations (any ECO_*_SI_in / SE_in / Q_out)
            si = re.search(r'^\s*input\s+(ECO_\w*_SI_in|eco\w*_si_bridge_in)\s*;', body, re.MULTILINE)
            se = re.search(r'^\s*input\s+(ECO_\w*_SE_in|eco\w*_se_bridge_in)\s*;', body, re.MULTILINE)
            qo = re.search(r'^\s*output\s+(ECO_\w*_Q_out|eco\w*_q_bridge_out)\s*;', body, re.MULTILINE)
            missing_ports = [p for p, m in (('SI_in', si), ('SE_in', se), ('Q_out', qo)) if not m]
            if missing_ports:
                failures.append(f'[MODE_S_PORT_MISSING] {stage}: {inst} requires Mode S but host {host!r} missing port(s) {missing_ports}')
                continue
            # NEW: bridge wire driver check at parent scope. The bridge port is
            # an input to the host module — at the parent module, the wire that
            # feeds the bridge (e.g. eco<jira>_si_bridge) MUST be driven by an
            # `assign` or by another module's output port_connection. A dangling
            # bridge wire produces undriven SE/SI at the new DFF → FM globally
            # unmatched (the failure mode that broke 9868 R1).
            #
            # Find the parent of host: look for `<host_mod>(_0)? <inst_name> (` in netlist
            # and check that inst_name's port_connections for ECO_*_SI_in / SE_in
            # reference wires that are driven somewhere in the parent module.
            si_port = si.group(1)
            se_port = se.group(1)
            for bridge_port in (si_port, se_port):
                # Find any instance that wires up this port — look for ".<bridge_port>(<wire>)"
                pc = re.search(rf'\.\s*{re.escape(bridge_port)}\s*\(\s*([A-Za-z_]\w*)\s*\)', text)
                if not pc:
                    failures.append(
                        f'[MODE_S_BRIDGE_NOT_WIRED] {stage}: host {host!r} declares port '
                        f'{bridge_port!r} but no parent instance wires it up — port is '
                        f'unused → DFF {inst} SE/SI undriven at upper scope.')
                    continue
                wire = pc.group(1)
                # Verify the wire has a driver: scan for `assign <wire> = ...` or
                # `.<some_out_port>(<wire>)` (output port_connection).
                drv_assign = re.search(rf'^\s*assign\s+{re.escape(wire)}\s*=\s*\S+', text, re.MULTILINE)
                drv_out_conn = re.search(rf'\.\s*\w*(?:_out|_OUT)\s*\(\s*{re.escape(wire)}\s*\)', text)
                if not (drv_assign or drv_out_conn):
                    failures.append(
                        f'[MODE_S_BRIDGE_DANGLING] {stage}: bridge wire {wire!r} feeding '
                        f'{host}.{bridge_port} for {inst} has NO driver in the netlist '
                        f'(no `assign {wire} = ...` and no `_out` port connection). FM '
                        f'will see DFF.SE/SI undriven → globally unmatched compare points.')
            # Verify the assign exists
            assn = re.search(rf'^\s*assign\s+{re.escape(qo.group(1))}\s*=\s*\w+\s*;', body, re.MULTILINE)
            if not assn:
                failures.append(f'[MODE_S_ASSIGN_MISSING] {stage}: {inst} requires Mode S but assign for {qo.group(1)} not found in {host!r}')
                continue
            # Verify DFF's SE/SI in netlist match the declared Mode S port names
            # exactly — not merely "≠ 1'b0". A neighbor-DFF net that bypasses
            # the bridge ports (e.g. test_so629, FxPrePlace_HFSNET_*) would pass
            # the old non-1'b0 check but break FM because the bridge wires don't
            # connect to the existing scan chain.
            dff_re = re.search(rf'\b\S+\s+{re.escape(inst)}\s*\(\s*([^;]+?)\)\s*;', body, re.DOTALL)
            if dff_re:
                pcs = dff_re.group(1)
                se_m = re.search(r'\.SE\s*\(\s*([^)]+?)\s*\)', pcs)
                si_m = re.search(r'\.SI\s*\(\s*([^)]+?)\s*\)', pcs)
                se_actual = se_m.group(1).strip() if se_m else ''
                si_actual = si_m.group(1).strip() if si_m else ''
                se_expected = se.group(1)  # ECO_*_SE_in name from port decl
                si_expected = si.group(1)
                if se_actual != se_expected:
                    failures.append(
                        f"[MODE_S_SE_MISMATCH] {stage}: {inst}.SE = {se_actual!r} "
                        f"but Mode S declared {se_expected!r} — DFF SE/SI must use "
                        f"the bridge ports, not a neighbor-DFF net")
                if si_actual != si_expected:
                    failures.append(
                        f"[MODE_S_SI_MISMATCH] {stage}: {inst}.SI = {si_actual!r} "
                        f"but Mode S declared {si_expected!r} — DFF SE/SI must use "
                        f"the bridge ports, not a neighbor-DFF net")
    return failures


def check_eco_cell_counts(applied):
    """
    WARN (not FAIL) if ECO cell counts differ significantly across stages.
    Route may legitimately have fewer (module renamed in P&R).
    Returns (warnings, failures) — failures are hard FAIL conditions.
    """
    gate_types = ('new_logic_gate', 'new_logic_dff', 'new_logic')
    counts = {}
    for stage, entries in applied.items():
        if not isinstance(entries, list):
            continue
        counts[stage] = sum(
            1 for e in entries
            if e.get('change_type','') in gate_types
            and e.get('status','') in ('INSERTED', 'ALREADY_APPLIED')
        )

    if not counts:
        return [], []

    max_count = max(counts.values())
    warnings = []
    failures = []
    for stage, count in counts.items():
        if count == 0 and max_count > 0:
            failures.append(f'Stage {stage}: 0 ECO cells applied but other stages have {max_count}')
        elif count < max_count * 0.5:
            warnings.append(f'Stage {stage}: {count} cells vs max {max_count} — possible partial application')
    return warnings, failures


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    args = parse_args()
    base  = args.base_dir
    tag   = args.tag
    rnd   = args.round
    jira  = args.jira

    applied_path  = f'{base}/data/{tag}_eco_applied_round{rnd}.json'
    check8_path   = f'{base}/data/{tag}_eco_check8_round{rnd}.json'
    out_json_path = f'{base}/data/{tag}_eco_pre_fm_check_round{rnd}.json'
    out_rpt_path  = f'{base}/data/{tag}_eco_step5_pre_fm_check_round{rnd}.rpt'
    marker_path   = f'{base}/data/{tag}_eco_step5_pre_fm_check_round{rnd}_marker.txt'

    applied = load_json(applied_path) or {}

    results   = {}
    all_fails = []
    warnings  = []

    # Check 1 — No deferred port declarations
    fails = check_no_deferred(applied)
    results['no_deferred_ports'] = 'PASS' if not fails else 'FAIL'
    all_fails.extend([f'[DEFERRED] {f}' for f in fails])

    # Check 2 — Port declarations all applied
    fails = check_port_declarations_applied(applied)
    results['port_declarations_applied'] = 'PASS' if not fails else 'FAIL'
    all_fails.extend([f'[PORT_SKIP] {f}' for f in fails])

    # Check 3 — Stage consistency (gates inserted in all stages)
    fails = check_stage_consistency(applied)
    results['stage_consistency'] = 'PASS' if not fails else 'FAIL'
    all_fails.extend([f'[STAGE_MISMATCH] {f}' for f in fails])

    # Check 4 — No UNHANDLED entries
    fails = check_no_unhandled(applied)
    results['no_unhandled'] = 'PASS' if not fails else 'FAIL'
    all_fails.extend([f'[UNHANDLED] {f}' for f in fails])

    # Check 5 — eco_check8 Verilog validator (runs eco_check8.sh externally)
    fails = check_check8(check8_path)
    # Build nested per-stage structure as required by mandatory output contract
    chk8_json = load_json(check8_path) or {}
    results['check8_verilog_validator'] = {
        'Synthesize': chk8_json.get('Synthesize', 'MISSING'),
        'PrePlace':   chk8_json.get('PrePlace',   'MISSING'),
        'Route':      chk8_json.get('Route',      'MISSING'),
        'errors':     fails,
    }
    results['check8_verilog'] = 'PASS' if not fails else 'FAIL'
    all_fails.extend([f'[SVR4_SVR9] {f}' for f in fails])

    # Check 6 — ECO cell counts (warnings only for partial, hard fail for zero)
    w, fails = check_eco_cell_counts(applied)
    results['eco_cell_counts'] = 'PASS' if not fails else 'FAIL'
    warnings.extend(w)
    all_fails.extend([f'[ZERO_CELLS] {f}' for f in fails])

    # Check 7 — Verify INSERTED gates actually exist in PostEco netlist
    # Catches: eco_perl_spec marks INSERTED but Perl fails to find module (ghost insert)
    fails = check_cells_in_netlist(applied, args.ref_dir)
    results['cells_in_netlist'] = 'PASS' if not fails else 'FAIL'
    all_fails.extend(fails)

    # Check 8 — Every n_eco_* net in PostEco netlist must have ≥ 2 references.
    # Catches bus-rename failures where the rename was specified in study JSON
    # but eco_passes_2_4.py didn't apply it to the netlist (driver missing).
    fails = check_undriven_eco_nets(args.ref_dir)
    results['undriven_eco_nets'] = 'PASS' if not fails else 'FAIL'
    all_fails.extend(fails)

    # Check 9 — bus-concat integrity. For port_connection entries with
    # bus_bit_index, the netlist must still have .port({...}) — not collapsed
    # to a single net (catches broad-regex rewire corruption).
    fails = check_bus_concat_intact(args.ref_dir, applied)
    results['bus_concat_intact'] = 'PASS' if not fails else 'FAIL'
    all_fails.extend(fails)

    # Check 10 — every APPLIED port_declaration / port_connection entry must
    # have its edit physically present in the netlist. Catches the silent
    # APPLIED-but-no-edit failure mode.
    fails = check_port_edits_in_netlist(args.ref_dir, applied)
    results['port_edits_in_netlist'] = 'PASS' if not fails else 'FAIL'
    all_fails.extend(fails)

    # Check 11 — every APPLIED rewire entry must have cell.pin → new_net
    # physically in the netlist (closes the last "JSON trust" gap).
    fails = check_rewires_in_netlist(args.ref_dir, applied)
    results['rewires_in_netlist'] = 'PASS' if not fails else 'FAIL'
    all_fails.extend(fails)

    # Check 12 — Full semantic equivalence between Step 3 study JSON and
    # PostEco netlist (Option B). Comment-aware Verilog-semantic parser
    # verifies every confirmed study entry's intent is physically present.
    # Catches comment-masked edits, bit-position errors, wrong-instance
    # matches that regex spot checks (Checks 8/9/10/11) can miss.
    study_path = f'{base}/data/{tag}_eco_preeco_study.json'
    fails = check_semantic_verify(study_path, args.ref_dir)
    results['semantic_verify'] = 'PASS' if not fails else 'FAIL'
    all_fails.extend(fails)

    # Check 13 — every ECO cell's per-stage input pin must have a real driver
    # in the PostEco netlist (cell output / port / wire decl). Catches the
    # "agent recorded a stale or non-existent per-stage net name" class of bug.
    fails = check_eco_input_drivers(study_path, args.ref_dir)
    results['eco_input_drivers'] = 'PASS' if not fails else 'FAIL'
    all_fails.extend(fails)

    # Check 14 — Duplicate port names in any module port list header.
    # Duplicate ports cause Verilog compile errors that block FM elaboration.
    fails = check_duplicate_ports(args.ref_dir)
    results['duplicate_ports'] = 'PASS' if not fails else 'FAIL'
    all_fails.extend(fails)

    # Check 15 — ECO cell output pin names must match the cell's actual output pin.
    # Wrong pin causes FE-LINK-7 ABORT_LINK (FM cannot build verification model).
    # Example: MUX2 output is .Z not .ZN; IND2 is .ZN not .Z.
    fails = check_eco_output_pin_names(applied, args.ref_dir)
    results['eco_output_pin_names'] = 'PASS' if not fails else 'FAIL'
    all_fails.extend(fails)

    # Check 16 — ECO cell output nets referenced outside declaring module must have
    # a port_declaration entry applied. Missing causes FE-LINK-7 ABORT_LINK.
    fails = check_missing_output_port_decls(applied, args.ref_dir)
    results['missing_output_port_decls'] = 'PASS' if not fails else 'FAIL'
    all_fails.extend(fails)

    # Check 18 — defense-in-depth: every port_connection in study must reference
    # a port that exists in the target child module's PostEco port list. Mirrors
    # Step 3 Check 3e but on the live netlist — catches Pass 2 silent skips.
    fails = check_port_conn_target_exists(study_path, args.ref_dir)
    results['port_conn_target_exists'] = 'PASS' if not fails else 'FAIL'
    all_fails.extend(fails)

    # Check 17 — Mode S (scan-stitching) stitching landed correctly in netlist.
    # For every new_logic_dff entry flagged with mode_S_applied / requires_scan_stitching,
    # verify the host module declares the 3 stitching ports (SI_in / SE_in / Q_out),
    # the assign for Q_out is present, and the DFF's per-stage SE/SI are bridged
    # (NOT tied to 1'b0). Catches missing stitching that breaks Route FM.
    fails = check_mode_s_stitching(study_path, args.ref_dir)
    results['mode_s_stitching'] = 'PASS' if not fails else 'FAIL'
    all_fails.extend(fails)

    passed = len(all_fails) == 0

    # ── Write JSON ────────────────────────────────────────────────────────────
    out = {
        'tag':           tag,
        'round':         rnd,
        'jira':          jira,
        'passed':        passed,
        'failures':      all_fails,
        'warnings':      warnings,
        'check_summary': results,
    }
    with open(out_json_path, 'w') as f:
        json.dump(out, f, indent=2)

    # ── Write RPT ─────────────────────────────────────────────────────────────
    status_str = 'PASS' if passed else 'FAIL'
    lines = [
        '=' * 72,
        f'STEP 5 — PRE-FM QUALITY CHECK (Round {rnd})',
        f'Tag: {tag}  |  JIRA: {jira}',
        '=' * 72,
        f'RESULT: {status_str}',
        '',
    ]
    for check, result in results.items():
        lines.append(f'  {check:<35}: {result}')
    if all_fails:
        lines += ['', 'FAILURES:']
        lines += [f'  {f}' for f in all_fails]
    if warnings:
        lines += ['', 'WARNINGS (non-blocking):']
        lines += [f'  {w}' for w in warnings]
    lines += ['', '=' * 72]
    rpt_text = '\n'.join(lines) + '\n'
    with open(out_rpt_path, 'w') as f:
        f.write(rpt_text)

    # ── Write marker ──────────────────────────────────────────────────────────
    marker = f'ECO_SCRIPT_LAUNCHED: eco_pre_fm_check.py\n  result: {status_str}\n  output: {out_json_path}\n'
    with open(marker_path, 'w') as f:
        f.write(marker)

    print(rpt_text)
    sys.exit(0 if passed else 1)


if __name__ == '__main__':
    main()
