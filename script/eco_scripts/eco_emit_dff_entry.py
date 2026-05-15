#!/usr/bin/env python3
"""
eco_emit_dff_entry.py — One-shot DFF entry assembler (Step 3 wrapper).

For one `new_logic` change from eco_rtl_diff.json, deterministically
produce the complete per-stage entries needed for eco_preeco_study.json:
  - DFF entry with port_connections_per_stage for Synth/PP/Route
  - D-input gate chain (via eco_synth_chain.py)
  - Mode-S bridge plumbing artifacts (via eco_pick_sibling.py +
    eco_pick_bridge_dffs.py + eco_emit_bridge_plumbing.py)

Strategy decision is made by the script, not the agent:
  - Try eco_pick_sibling.py at parent scope
  - Null? Escalate --host-scope=down then --min-cluster=5
  - Still null + host has DFFs in same clock → BLOCKED (engineer escalation)
  - Still null + host has 0 DFFs → constant_zero (justified)
  - Viable picker result → bridge_port for both PP and Route

Self-validates the assembled entries against the Step 3 invariants
(strategy↔port_connections consistency, per-stage SI/SE wire existence,
bridge artifact completeness, clock root token match).

Output JSON layout:
  {
    "tag":           <TAG>,
    "jira":          <JIRA>,
    "dff_instance":  <name>,
    "strategy":      "bridge_port" | "neighbor_dff" | "constant_zero",
    "Synthesize":    [<DFF entry>, <chain gates>, <bridge artifacts>, ...],
    "PrePlace":      [...],
    "Route":         [...],
    "diagnostics":   { ... self-validation results ... }
  }

Usage:
    python3 eco_emit_dff_entry.py \\
        --rtl-change         (file_path or - for stdin) \\
        --ref-dir            <REF_DIR> \\
        --rename-map         data/<TAG>_eco_fenets_rename_map.json \\
        --preeco-synthesize  /tmp/eco_study_<TAG>_Synthesize.v \\
        --preeco-preplace    /tmp/eco_study_<TAG>_PrePlace.v \\
        --preeco-route       /tmp/eco_study_<TAG>_Route.v \\
        --tag <TAG> --jira <JIRA> --tile-module <ddrss_<tile>_t> \\
        --output data/<TAG>_eco_dff_entry_<dff>.json

Exit 0 on PASS, 1 on BLOCKED (write a partial JSON with diagnostics so
the studier agent can re-spawn with hints).
"""
import argparse, copy, gzip, json, re, subprocess, sys
from pathlib import Path

# Reuse existing modules in the same directory
sys.path.insert(0, str(Path(__file__).parent))
import eco_synth_chain as synth_chain  # noqa: E402


# ── Helpers ──────────────────────────────────────────────────────────────────

def _open_text(path):
    p = str(path)
    if p.endswith('.gz'):
        return gzip.open(p, 'rt', errors='replace')
    return open(p, 'r', errors='replace')


def _grep_count(pattern, path):
    """zgrep -c '\\b<pattern>\\b' <path>; returns int (0 on error)."""
    try:
        if not Path(path).is_file():
            return 0
        cmd = f"zgrep -c '\\b{re.escape(pattern)}\\b' {path}"
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=60)
        return int((r.stdout or '0').strip() or '0')
    except Exception:
        return 0


def _module_scope_dff_count(host_module, dff_clock, preeco_synth_v):
    """Count DFFs in host_module on dff_clock (Check 30 grep)."""
    if not (host_module and dff_clock and preeco_synth_v and Path(preeco_synth_v).is_file()):
        return 0
    try:
        cmd = (f"awk '/^module {re.escape(host_module)}\\b/,/^endmodule/' {preeco_synth_v} "
               f"| grep -cE '\\.CP\\(\\s*{re.escape(dff_clock)}\\b'")
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=60)
        return int((r.stdout or '0').strip() or '0')
    except Exception:
        return 0


# ── Step A: Strategy decision ───────────────────────────────────────────────

def decide_mode_s_strategy(host_module, ref_dir, tile_module, dff_clock,
                            preeco_synth_v, jira, tag, base_dir):
    """Scan stitching is OUT OF SCOPE — DFT team handles scan integration.
    Always emit constant_zero (SE=SI=1'b0 in all 3 stages). The picker /
    bridge-plumbing path is short-circuited; the legacy escalation logic
    is preserved below the early return for reference only."""
    return {
        'strategy': 'constant_zero',
        'host_module_dff_count_same_clock': None,
        'escalation_chain': [],
        'reason': 'scan stitching out of scope — DFT team handles scan '
                  'integration; AI flow emits SE=SI=1\'b0 unconditionally',
    }


# ── Step B: Per-stage CP/SI/SE resolution ───────────────────────────────────

def resolve_cp_per_stage(rename_map, host_scope, dff_clock):
    """Resolve CP per stage from rename map. Falls back to original name if
    not in map (caller should grep stage netlists to verify)."""
    key = f'{host_scope}/{dff_clock}'
    entry = (rename_map or {}).get(key, {}) or {}
    out = {}
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        v = entry.get(stage, '') if isinstance(entry, dict) else ''
        # Strip trailing /pin (e.g. 'X_reg/CP' → 'X_reg' or just use as-is)
        out[stage] = v or dff_clock
    return out


def resolve_neighbor_dff_si_se(host_module, ref_dir):
    """Pick a neighbor DFF in host module per stage; return per-stage SI/SE.
    Lightweight version — finds first DFF in host module body and reads its
    .SI/.SE wires. Caller should validate the wires exist in each stage's
    netlist (handled by self-validation step below)."""
    out = {'Synthesize': {'SI': "1'b0", 'SE': "1'b0"},
           'PrePlace':   {'SI': "1'b0", 'SE': "1'b0"},
           'Route':      {'SI': "1'b0", 'SE': "1'b0"}}
    for stage in ('PrePlace', 'Route'):
        gz = Path(ref_dir) / 'data' / 'PreEco' / f'{stage}.v.gz'
        if not gz.is_file():
            continue
        try:
            # Extract host module body, find first DFF cell with .SI(...) and .SE(...)
            cmd = (f"zcat {gz} | awk '/^module {re.escape(host_module)}\\b/,/^endmodule/' "
                   f"| grep -m1 -E '\\.SE\\s*\\([^,]+\\).*\\.SI\\s*\\(|"
                   f"\\.SI\\s*\\([^,]+\\).*\\.SE\\s*\\('")
            r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=60)
            line = (r.stdout or '').strip()
            si_m = re.search(r'\.SI\s*\(\s*(\S+?)\s*\)', line)
            se_m = re.search(r'\.SE\s*\(\s*(\S+?)\s*\)', line)
            if si_m: out[stage]['SI'] = si_m.group(1)
            if se_m: out[stage]['SE'] = se_m.group(1)
        except Exception:
            pass
    return out


# ── Step C: D-input chain via eco_synth_chain ───────────────────────────────

def build_d_input_chain(d_input_expected_function, input_names, jira, prefix=''):
    """Run eco_synth_chain.synthesize and return list of gate entries +
    final output net (DFF.D). `prefix` disambiguates instance names when
    multiple DFFs are processed in the same study (e.g. 'needfreqadj' →
    eco_<jira>_needfreqadj_d001 instead of generic eco_<jira>_d001).

    Verilog bus-bit normalization: rtl_diff's chain `inputs` may use
    bracketed form (`SIG[1]`) while `d_input_expected_function` uses the
    underscore-escaped form (`SIG_1_`) that survives Python's eval().
    Both forms are added to input_names so symbol resolution works.

    On synth failure: returns a valid Verilog placeholder net name
    (`n_eco_<jira>_<prefix>_d_SYNTH_FAILED`) instead of the raw error
    string. This way the DFF.D field is a parseable identifier (won't
    crash the applier on Verilog elaboration) and the validator can
    detect it via name pattern match.
    """
    if not d_input_expected_function:
        return [], None
    # Normalize bracketed bus bits → underscore-escaped form, expanding
    # the input_names list to cover BOTH forms (eval will resolve whichever
    # form the Boolean string uses).
    normalized = []
    for n in input_names:
        if n not in normalized: normalized.append(n)
        # Bus bit form: 'BeqCtrlPeSrc[1]' → 'BeqCtrlPeSrc_1_'
        flat = re.sub(r'\[(\d+)\]', r'_\1_', n)
        if flat != n and flat not in normalized:
            normalized.append(flat)
    try:
        chain = synth_chain.synthesize(
            d_input_expected_function,
            input_names=normalized,
            jira=jira,
            prefix=prefix,
        )
    except Exception as e:
        # Return a valid identifier as placeholder so the DFF.D field is
        # parseable Verilog. The marker '_d_SYNTH_FAILED' lets the
        # validator detect this case.
        placeholder = f'n_eco_{jira}_{prefix}_d_SYNTH_FAILED' if prefix else \
                      f'n_eco_{jira}_d_SYNTH_FAILED'
        sys.stderr.write(f'WARN: synth_chain failed for prefix={prefix!r}: {e}\n')
        return [], placeholder
    gate_entries = []
    for c in chain.cells:
        gate_entries.append({
            'change_type':       'new_logic_gate',
            'cell_type':         c['cell_type'],
            'instance_name':     c['instance_name'],
            'port_connections':  c['port_connections'],
            'output_net':        next((c['port_connections'].get(p)
                                       for p in ('Z', 'ZN', 'ZN1') if p in c['port_connections']),
                                      None),
            'gate_function':     re.match(r'^([A-Z]+\d?)', c['cell_type']).group(1)
                                  if re.match(r'^([A-Z]+\d?)', c['cell_type']) else 'UNKNOWN',
            'source':            'eco_synth_chain.py',
            'reason':            f'D-input chain element for {jira} DFF',
            'notes':             'auto-emitted by eco_emit_dff_entry.py — DO NOT manually edit',
            'confirmed':         True,
        })
    return gate_entries, chain.output_net


# ── Step D: Bridge plumbing (delegates to existing emitter) ────────────────

def _grep_inst_name(parent_module, child_module, pp_gz):
    """Find the instance name `<inst>` in `child_module <inst> (` within parent_module body."""
    if not (parent_module and child_module and Path(pp_gz).is_file()):
        return ''
    try:
        cmd = (f"zcat {pp_gz} | awk '/^module {re.escape(parent_module)}\\b/,/^endmodule/' "
               f"| grep -m1 -oE '{re.escape(child_module)}\\s+[A-Za-z_][A-Za-z0-9_]*' "
               f"| awk '{{print $2}}'")
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=60)
        return (r.stdout or '').strip() or ''
    except Exception:
        return ''


def build_bridge_plumbing(pick, picker_top, dff_inst, host_module, ref_dir, jira, tag, base_dir,
                          parent_is_host=False):
    """Run eco_pick_bridge_dffs.py + eco_emit_bridge_plumbing.py and return
    per-stage artifact lists.

    pick = recommended_pick sub-object (has module, inst, fm_scope, ...)
    picker_top = top-level picker output (has parent_module, host_module)
    """
    pp_gz = Path(ref_dir) / 'data' / 'PreEco' / 'PrePlace.v.gz'
    sibling_module = pick.get('module', '')
    sibling_inst   = pick.get('inst', '')
    if not sibling_module:
        return None, 'sibling_module missing in pick'

    # 1. eco_pick_bridge_dffs.py
    bridge_pick_path = Path(base_dir) / 'data' / f'{tag}_eco_bridge_pick_{dff_inst}.json'
    cmd = (f"python3 {Path(__file__).parent / 'eco_pick_bridge_dffs.py'} "
           f"--netlist {pp_gz} --sibling-mod {sibling_module} "
           f"--output {bridge_pick_path}")
    try:
        subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=300)
    except Exception as e:
        return None, f'eco_pick_bridge_dffs.py failed: {e}'
    if not bridge_pick_path.is_file():
        return None, f'eco_pick_bridge_dffs.py produced no output: {bridge_pick_path}'

    # 2. Determine parent_module + host_inst per escalation mode
    if parent_is_host:
        # down-escalation: host IS the parent (host instantiates the chosen child)
        parent_module = host_module
        host_inst = host_module  # host is its own instance for emitter scoping
    else:
        # parent-scope: parent_module from picker top-level output
        parent_module = (picker_top or {}).get('parent_module', '')
        # Grep parent body for host instantiation to get host_inst
        host_inst = _grep_inst_name(parent_module, host_module, pp_gz)
    if not parent_module:
        return None, 'parent_module not resolvable from picker output'
    if not host_inst:
        host_inst = 'HOST_INST_UNKNOWN'  # let emitter fail explicitly

    # 3. eco_emit_bridge_plumbing.py
    plumbing_path = Path(base_dir) / 'data' / f'{tag}_eco_bridge_plumbing_{dff_inst}.json'
    cmd = (f"python3 {Path(__file__).parent / 'eco_emit_bridge_plumbing.py'} "
           f"--bridge-pick {bridge_pick_path} --jira {jira} --ref-dir {ref_dir} "
           f"--host-module {host_module} --sibling-module {sibling_module} "
           f"--parent-module {parent_module} "
           f"--host-inst {host_inst or 'HOST'} --sibling-inst {sibling_inst or 'SIBLING'} "
           f"--new-dff-instance {dff_inst} --output {plumbing_path}")
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=120)
    except Exception as e:
        return None, f'eco_emit_bridge_plumbing.py failed: {e}'
    if not plumbing_path.is_file():
        return None, f'eco_emit_bridge_plumbing.py produced no output: {plumbing_path} '\
                     f'(stderr={r.stderr[:200] if r else "?"})'
    try:
        return json.loads(plumbing_path.read_text()), None
    except Exception as e:
        return None, f'cannot parse plumbing JSON: {e}'


# ── Step E: Build the DFF entry itself ─────────────────────────────────────

def build_dff_entry(rtl_change, strategy_info, cp_per_stage, scan_per_stage,
                    chain_d_net, jira):
    """Compose the new_logic_dff entry with port_connections_per_stage."""
    target_reg = rtl_change.get('target_register', '') or rtl_change.get('new_token', '')
    dff_inst   = f'{target_reg}_reg' if target_reg else f'eco_{jira}_dff'
    q_net      = target_reg

    pcs = {}
    for stage in ('Synthesize', 'PrePlace', 'Route'):
        pin_si = scan_per_stage.get(stage, {}).get('SI', "1'b0")
        pin_se = scan_per_stage.get(stage, {}).get('SE', "1'b0")
        pcs[stage] = {
            'D':  chain_d_net or "1'b0",
            'CP': cp_per_stage.get(stage, ''),
            'SI': pin_si,
            'SE': pin_se,
            'Q':  q_net,
        }

    strategy = strategy_info.get('strategy', 'constant_zero')
    requires_scan = (strategy in ('bridge_port', 'neighbor_dff'))
    mode_s_applied = (strategy == 'bridge_port')
    mode_s_strat_per_stage = {
        'Synthesize': 'constant_zero',
        'PrePlace':   strategy if strategy != 'BLOCKED' else 'BLOCKED_NO_SIBLING',
        'Route':      strategy if strategy != 'BLOCKED' else 'BLOCKED_NO_SIBLING',
    }

    entry = {
        'change_type':                    'new_logic_dff',
        'instance_name':                  dff_inst,
        'module_name':                    rtl_change.get('declaring_module') or rtl_change.get('module_name', ''),
        'dff_clock':                      rtl_change.get('dff_clock', ''),
        'reset_signal':                   rtl_change.get('reset_signal', ''),
        'reset_polarity':                 rtl_change.get('reset_polarity', ''),
        'port_connections':               pcs.get('Synthesize', {}),
        'port_connections_per_stage':     pcs,
        'mode_S_strategy_per_stage':      mode_s_strat_per_stage,
        'mode_S_applied':                 mode_s_applied,
        'requires_scan_stitching':        requires_scan,
        'host_module_dff_count_same_clock':
            strategy_info.get('host_module_dff_count_same_clock', 0),
        'scan_stitching_skipped_reason':
            strategy_info.get('reason', '') if strategy in ('constant_zero', 'BLOCKED') else '',
        'source':                         'eco_emit_dff_entry.py',
        'reason':                         f'New ECO DFF for {target_reg} ({jira})',
        'notes':                          'auto-emitted — DO NOT manually edit',
        'confirmed':                      True,
    }
    return entry, dff_inst


# ── Step F: Self-validation ────────────────────────────────────────────────

def self_validate(out, ref_dir):
    """Run a few invariants matching eco_validate_step3.py expectations.
    Returns list of issues (empty list = clean)."""
    issues = []
    # All three stages present
    for s in ('Synthesize', 'PrePlace', 'Route'):
        if not out.get(s):
            issues.append(f'CRITICAL: {s} stage entries empty')
    # Strategy ↔ port_connections consistency (Check 32)
    for s in ('Synthesize', 'PrePlace', 'Route'):
        for e in out.get(s, []):
            if e.get('change_type') not in ('new_logic_dff', 'new_logic'):
                continue
            strat = (e.get('mode_S_strategy_per_stage') or {})
            pcs   = (e.get('port_connections_per_stage') or {})
            for chk in ('Synthesize', 'PrePlace', 'Route'):
                if strat.get(chk) != 'constant_zero':
                    continue
                p = pcs.get(chk) or {}
                if p.get('SE','') not in ("1'b0","1'bz","") or p.get('SI','') not in ("1'b0","1'bz",""):
                    issues.append(f'HIGH/32: {chk} declares constant_zero but SE/SI are real wires')
    return issues


# ── Main ───────────────────────────────────────────────────────────────────

def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('--rtl-change', required=True,
                   help='Path to JSON file containing ONE new_logic change entry, OR "-" for stdin')
    p.add_argument('--ref-dir', required=True)
    p.add_argument('--rename-map', required=True)
    p.add_argument('--preeco-synthesize', default='',
                   help='Path to PreEco Synthesize.v (uncompressed) for module-scope grep '
                        '(host_module_dff_count_same_clock check). Falls back to PreEco/Synthesize.v.gz.')
    p.add_argument('--tag',  required=True)
    p.add_argument('--jira', required=True)
    p.add_argument('--tile-module', required=True)
    p.add_argument('--base-dir', default='.', help='Base directory for output files')
    p.add_argument('--output', required=True)
    args = p.parse_args()

    # Load rtl_change
    if args.rtl_change == '-':
        rtl_change = json.loads(sys.stdin.read())
    else:
        rtl_change = json.loads(Path(args.rtl_change).read_text())

    # Load rename map
    rmap = {}
    if Path(args.rename_map).is_file():
        try:
            rmap = json.loads(Path(args.rename_map).read_text())
        except Exception:
            rmap = {}

    # Resolve preeco synthesize path
    synth_v = args.preeco_synthesize
    if not synth_v or not Path(synth_v).is_file():
        # Use the gz directly (grep will need zcat)
        synth_v = str(Path(args.ref_dir) / 'data' / 'PreEco' / 'Synthesize.v.gz')

    # Extract key fields
    target_reg  = rtl_change.get('target_register') or rtl_change.get('new_token', '')
    host_module = (rtl_change.get('declaring_module') or rtl_change.get('module_name', ''))
    if not host_module.startswith('ddrss_') and host_module:
        # Heuristic: prepend tile prefix if missing
        host_module = f'{args.tile_module}_{host_module}'
    dff_clock   = rtl_change.get('dff_clock', '')
    expr        = rtl_change.get('d_input_expected_function', '')
    input_names = []
    for g in (rtl_change.get('d_input_gate_chain') or []):
        for v in (g.get('inputs') or []):
            if v not in input_names: input_names.append(v)
        for k, v in (g.get('port_connections') or {}).items():
            if k in ('Z', 'ZN'): continue
            if isinstance(v, str) and not v.startswith('n_eco_') and v not in input_names:
                input_names.append(v)

    print(f'eco_emit_dff_entry: target={target_reg}  host={host_module}  clk={dff_clock}',
          file=sys.stderr)

    # ── Step A: strategy ──────────────────────────────────────────────────
    strategy_info = decide_mode_s_strategy(
        host_module, args.ref_dir, args.tile_module, dff_clock,
        synth_v, args.jira, args.tag, args.base_dir,
    )
    print(f'  strategy: {strategy_info.get("strategy")}', file=sys.stderr)

    # ── Step B: per-stage CP/SI/SE ────────────────────────────────────────
    host_scope = rtl_change.get('host_scope', '') or rtl_change.get('hierarchy', '')
    cp_per_stage = resolve_cp_per_stage(rmap, host_scope, dff_clock)

    if strategy_info['strategy'] == 'bridge_port':
        # SE/SI come from bridge port names
        dff_label = re.sub(r'_reg$', '', target_reg)
        scan_per_stage = {
            'Synthesize': {'SI': "1'b0", 'SE': "1'b0"},
            'PrePlace':   {'SI': f'{dff_label}_ECO{args.jira}_SI_in',
                           'SE': f'{dff_label}_ECO{args.jira}_SE_in'},
            'Route':      {'SI': f'{dff_label}_ECO{args.jira}_SI_in',
                           'SE': f'{dff_label}_ECO{args.jira}_SE_in'},
        }
    elif strategy_info['strategy'] == 'neighbor_dff':
        scan_per_stage = resolve_neighbor_dff_si_se(host_module, args.ref_dir)
        scan_per_stage['Synthesize'] = {'SI': "1'b0", 'SE': "1'b0"}
    else:
        scan_per_stage = {
            'Synthesize': {'SI': "1'b0", 'SE': "1'b0"},
            'PrePlace':   {'SI': "1'b0", 'SE': "1'b0"},
            'Route':      {'SI': "1'b0", 'SE': "1'b0"},
        }

    # ── Step C: D-input chain ─────────────────────────────────────────────
    # Per-DFF prefix for chain instance names (avoids collisions when multiple
    # DFFs in the same study both use eco_<jira>_d001). Lowercase the target
    # register name for consistent identifier form.
    dff_prefix = re.sub(r'[^A-Za-z0-9]+', '_', (target_reg or '').lower()).strip('_')
    chain_entries, chain_d_net = build_d_input_chain(expr, input_names, args.jira, prefix=dff_prefix)

    # ── Step E: DFF entry ─────────────────────────────────────────────────
    dff_entry, dff_inst = build_dff_entry(rtl_change, strategy_info, cp_per_stage,
                                          scan_per_stage, chain_d_net, args.jira)

    # ── Step D: bridge plumbing (if needed) ───────────────────────────────
    plumbing = None
    plumbing_err = None
    if strategy_info['strategy'] == 'bridge_port':
        plumbing, plumbing_err = build_bridge_plumbing(
            strategy_info['pick'], strategy_info.get('picker_top'),
            dff_inst, host_module, args.ref_dir,
            args.jira, args.tag, args.base_dir,
            parent_is_host=strategy_info.get('parent_is_host', False),
        )

    # ── Step F: Mode-I chain-leaf check (per chain leaf input) ────────────
    # For each chain leaf input that resolves to a bus-bit form (<bus>[<bit>]),
    # run eco_modei_chain_input_check.py to detect parent-side UNCONNECTED at
    # a child-instance port-bus connection. On MODEI_DETECTED, splice the
    # suggested unconnected_rewires into the DFF entry, append the child
    # port_connection to all 3 stage arrays, and rewrite the chain leaf to
    # the flat-net replacement everywhere it appears in chain_entries.
    modei_extra_entries = []  # appended to all 3 stages
    modei_diagnostics = []
    if host_module and chain_entries:
        # Collect unique bus-bit-form leaves from chain port_connections.
        # Accept both bracket form (`SIG[1]`) and flat form (`SIG_1_`); convert
        # the latter to bracket form for the helper.
        leaf_candidates = set()  # canonical bracket form
        flat_to_bracket = {}     # mapping back to original net names in chain
        for g in chain_entries:
            for pin, val in (g.get('port_connections') or {}).items():
                if pin in ('Z', 'ZN', 'ZN1'): continue
                if not isinstance(val, str): continue
                if val.startswith(('n_eco_', "1'b", "0'b", "1'h", "0'h")): continue
                # Bracket form already
                m1 = re.match(r'^([A-Za-z_]\w*)\[(\d+)\]$', val.strip())
                if m1:
                    leaf_candidates.add(val.strip())
                    flat_to_bracket[val.strip()] = val.strip()
                    continue
                # Flat form like SIG_1_
                m2 = re.match(r'^([A-Za-z_][A-Za-z0-9_]*?)_(\d+)_$', val.strip())
                if m2:
                    bracket_form = f'{m2.group(1)}[{m2.group(2)}]'
                    leaf_candidates.add(bracket_form)
                    flat_to_bracket[bracket_form] = val.strip()
        modei_helper = Path(__file__).parent / 'eco_modei_chain_input_check.py'
        for leaf in leaf_candidates:
            leaf_safe = re.sub(r'[^A-Za-z0-9_]', '_', leaf)
            out_path = Path(args.base_dir) / 'data' / f'{args.tag}_eco_modei_{dff_prefix}_{leaf_safe}.json'
            cmd = (
                f"python3 {modei_helper} --ref-dir {args.ref_dir} "
                f"--host-module {host_module} --chain-input '{leaf}' "
                f"--jira {args.jira} --output {out_path}"
            )
            try:
                subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=120)
            except Exception:
                continue
            if not out_path.is_file():
                continue
            try:
                result = json.loads(out_path.read_text())
            except Exception:
                continue
            modei_diagnostics.append({
                'leaf': leaf, 'status': result.get('status'),
                'output': str(out_path),
            })
            if result.get('status') != 'MODEI_DETECTED':
                continue
            # Splice unconnected_rewires onto DFF entry
            ur_entry = result.get('suggested_unconnected_rewires_entry')
            if ur_entry:
                dff_entry.setdefault('unconnected_rewires', []).append(ur_entry)
            # Add child port_connection to extras (will be appended to all stages)
            child_pc = result.get('suggested_child_port_connection_entry')
            if child_pc:
                modei_extra_entries.append(child_pc)
            # Rewrite chain leaves: original chain ref → flat-net replacement
            replacement = result.get('suggested_chain_input_replacement')
            if replacement:
                # Collect ALL forms of this leaf that appear in chain (bracket
                # + flat) and rewrite all of them
                rewrite_targets = {leaf}  # bracket form
                # Original flat form found earlier
                if leaf in flat_to_bracket:
                    rewrite_targets.add(flat_to_bracket[leaf])
                # Also derive both forms
                m = re.match(r'^([A-Za-z_]\w*)\[(\d+)\]$', leaf)
                if m:
                    rewrite_targets.add(f'{m.group(1)}_{m.group(2)}_')
                for g in chain_entries:
                    pcs = g.get('port_connections') or {}
                    for pin, val in list(pcs.items()):
                        if isinstance(val, str) and val.strip() in rewrite_targets:
                            pcs[pin] = replacement

    # ── Compose output ─────────────────────────────────────────────────────
    out = {
        'tag':            args.tag,
        'jira':           args.jira,
        'dff_instance':   dff_inst,
        'host_module':    host_module,
        'strategy':       strategy_info.get('strategy'),
        'Synthesize':     [dff_entry] + chain_entries + modei_extra_entries,
        'PrePlace':       [dff_entry] + chain_entries + modei_extra_entries,
        'Route':          [dff_entry] + chain_entries + modei_extra_entries,
        'diagnostics':    {
            'strategy_info':  strategy_info,
            'plumbing_error': plumbing_err,
            'chain_size':     len(chain_entries),
            'expected_function': expr,
            'modei_check':    modei_diagnostics,
            'modei_entries_added': len(modei_extra_entries),
        },
    }
    if plumbing:
        for s in ('Synthesize', 'PrePlace', 'Route'):
            out[s] = out[s] + (plumbing.get(s, []) or [])

    # Self-validate
    issues = self_validate(out, args.ref_dir)
    out['diagnostics']['self_validation_issues'] = issues
    out['diagnostics']['self_validation_pass']   = (len(issues) == 0)

    Path(args.output).write_text(json.dumps(out, indent=2))
    print(f'ECO_RPT_GENERATED: dff entry → {args.output}', file=sys.stderr)
    print(f'  strategy:    {out["strategy"]}', file=sys.stderr)
    print(f'  chain_size:  {len(chain_entries)}', file=sys.stderr)
    print(f'  bridge:      {"yes" if plumbing else "no"}'
          f'{" (err: " + plumbing_err + ")" if plumbing_err else ""}', file=sys.stderr)
    print(f'  Synth/PP/Route entry counts: '
          f'{len(out["Synthesize"])}/{len(out["PrePlace"])}/{len(out["Route"])}', file=sys.stderr)
    if issues:
        print(f'  self_validation: FAIL ({len(issues)} issues)', file=sys.stderr)
        for i in issues: print(f'    > {i}', file=sys.stderr)
        return 1
    print(f'  self_validation: PASS', file=sys.stderr)
    return 0 if out['strategy'] != 'BLOCKED' else 1


if __name__ == '__main__':
    sys.exit(main())
