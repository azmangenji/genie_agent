#!/usr/bin/env python3
"""
eco_emit_bridge_plumbing.py — Deterministic Mode-S bridge_port artifact emitter.

When eco_netlist_studier picks `bridge_port` strategy for a new ECO DFF, the
study MUST contain ~17 distinct entries spanning host module port declarations,
sibling module port declarations, buffer cells, parent wire declarations, two
sets of instance hookups, sibling SE-pin consolidation, and Q-closure. Under
context pressure the agent emits 2-3 of these and skips the rest — leaving FM
to ABORT on undeclared bridge wires at parent scope.

This script reads the bridge picker output (eco_bridge_pick_<DFF>.json) and
emits the COMPLETE per-stage artifact set as a JSON dict { Synthesize: [...],
PrePlace: [...], Route: [...] } ready to splice into preeco_study.

Synthesize stage carries port_declarations only (RTL has no scan plumbing and
the buffer cells / consolidation / Q-closure are P&R-specific). PrePlace and
Route get the full set.

Engineer naming conventions (from REFERENCE_9868.md):
  - Bridge ports: ECO_<jira>_SI_in / SE_in / Q_out (host) and SI_out / SE_out /
    Q_in (sibling).
  - Bridge wires (parent scope): eco<jira>_si_bridge / se_bridge / q_bridge.
  - Buffer cell types: BUFFSKFD4AMDBWP136P5M156H3P48CPDLVT (SI driver),
    BUFFLLKGD3AMDBWP136P5M156H3P48CPDLVT (SE driver) — pluggable via flags.

Usage:
    python3 eco_emit_bridge_plumbing.py \\
        --bridge-pick    data/<TAG>_eco_bridge_pick_<DFF>.json \\
        --jira           9868 \\
        --host-module    ddrss_umccmd_t_umcarbctrlsw \\
        --sibling-module ddrss_umccmd_t_umcdcqarb_0 \\
        --parent-module  ddrss_umccmd_t_umcarb \\
        --host-inst      CTRLSW \\
        --sibling-inst   DCQARB \\
        --new-dff-instance NeedFreqAdj_reg \\
        --output         data/<TAG>_eco_bridge_plumbing_<DFF>.json
"""
import argparse, json, sys
from pathlib import Path

# Default buffer cell types — engineer 9868 used these specific cells. Override
# via flags if a different library mandates different cell families. The applier
# does not care about cell type as long as the cell exists in the library; FM
# elaboration also does not care.
DEFAULT_SI_BUFFER_CELL = "BUFFSKFD4AMDBWP136P5M156H3P48CPDLVT"
DEFAULT_SE_BUFFER_CELL = "BUFFLLKGD3AMDBWP136P5M156H3P48CPDLVT"


def _ctx(reason, source):
    """Standard context tags every entry carries (Step 3 Check 15 requires them)."""
    return {
        'confirmed': True,
        'reason':    reason,
        'notes':     'auto-emitted by eco_emit_bridge_plumbing.py — DO NOT manually edit',
        'source':    source,
    }


def emit(pick, jira, host_mod, sib_mod, parent_mod, host_inst, sib_inst, new_dff_inst,
         si_buffer_cell=DEFAULT_SI_BUFFER_CELL, se_buffer_cell=DEFAULT_SE_BUFFER_CELL):
    si_in   = f"ECO_{jira}_SI_in"
    se_in   = f"ECO_{jira}_SE_in"
    q_out   = f"ECO_{jira}_Q_out"
    si_out  = f"ECO_{jira}_SI_out"
    se_out  = f"ECO_{jira}_SE_out"
    q_in    = f"ECO_{jira}_Q_in"
    w_si    = f"eco{jira}_si_bridge"
    w_se    = f"eco{jira}_se_bridge"
    w_q     = f"eco{jira}_q_bridge"

    # ── 1. Host module port declarations (SI/SE inputs, Q output) ──────────
    host_port_decls = [
        {
            'change_type':       'port_declaration',
            'module_name':       host_mod,
            'port_name':         si_in,
            'port_direction':    'input',
            'net_name':          si_in,
            'signal_name':       si_in,
            'declaration_type':  'input',
            'is_mode_s_stitch':  True,
            'bridge_port_role':  'host_si',
            'for_dff':           new_dff_inst,
            **_ctx(f'Mode-S host-side SI bridge port for {new_dff_inst}',
                   'eco_emit_bridge_plumbing.py'),
        },
        {
            'change_type':       'port_declaration',
            'module_name':       host_mod,
            'port_name':         se_in,
            'port_direction':    'input',
            'net_name':          se_in,
            'signal_name':       se_in,
            'declaration_type':  'input',
            'is_mode_s_stitch':  True,
            'bridge_port_role':  'host_se',
            'for_dff':           new_dff_inst,
            **_ctx(f'Mode-S host-side SE bridge port for {new_dff_inst}',
                   'eco_emit_bridge_plumbing.py'),
        },
        {
            'change_type':       'port_declaration',
            'module_name':       host_mod,
            'port_name':         q_out,
            'port_direction':    'output',
            'net_name':          q_out,
            'signal_name':       q_out,
            'declaration_type':  'output',
            'is_mode_s_stitch':  True,
            'bridge_port_role':  'host_q',
            'for_dff':           new_dff_inst,
            **_ctx(f'Mode-S host-side Q bridge port for {new_dff_inst}',
                   'eco_emit_bridge_plumbing.py'),
        },
    ]

    # ── 2. Sibling module port declarations (SI/SE outputs, Q input) ───────
    sib_port_decls = [
        {
            'change_type':       'port_declaration',
            'module_name':       sib_mod,
            'port_name':         si_out,
            'port_direction':    'output',
            'net_name':          si_out,
            'signal_name':       si_out,
            'declaration_type':  'output',
            'is_mode_s_stitch':  True,
            'bridge_port_role':  'sibling_si',
            'for_dff':           new_dff_inst,
            **_ctx(f'Mode-S sibling-side SI driver for {new_dff_inst} bridge',
                   'eco_emit_bridge_plumbing.py'),
        },
        {
            'change_type':       'port_declaration',
            'module_name':       sib_mod,
            'port_name':         se_out,
            'port_direction':    'output',
            'net_name':          se_out,
            'signal_name':       se_out,
            'declaration_type':  'output',
            'is_mode_s_stitch':  True,
            'bridge_port_role':  'sibling_se',
            'for_dff':           new_dff_inst,
            **_ctx(f'Mode-S sibling-side SE driver for {new_dff_inst} bridge',
                   'eco_emit_bridge_plumbing.py'),
        },
        {
            'change_type':       'port_declaration',
            'module_name':       sib_mod,
            'port_name':         q_in,
            'port_direction':    'input',
            'net_name':          q_in,
            'signal_name':       q_in,
            'declaration_type':  'input',
            'is_mode_s_stitch':  True,
            'bridge_port_role':  'sibling_q',
            'for_dff':           new_dff_inst,
            **_ctx(f'Mode-S sibling-side Q consumer for {new_dff_inst} bridge',
                   'eco_emit_bridge_plumbing.py'),
        },
    ]

    # ── 3. Parent-level bridge wire declarations (3 wires) ─────────────────
    bridge_wires = []
    for w in (w_si, w_se, w_q):
        bridge_wires.append({
            'change_type':       'wire_declaration',
            'module_name':       parent_mod,
            'signal_name':       w,
            'net_name':          w,
            'declaration_type':  'wire',
            'is_mode_s_stitch':  True,
            'bridge_port_role':  'parent_wire',
            'for_dff':           new_dff_inst,
            **_ctx(f'Parent-scope bridge wire carrying {new_dff_inst} Mode-S signal',
                   'eco_emit_bridge_plumbing.py'),
        })

    # ── 4. Parent instance hookups for host module (3 connections) ─────────
    host_hookups = [
        ('host_si', host_inst, host_mod, si_in, w_si),
        ('host_se', host_inst, host_mod, se_in, w_se),
        ('host_q',  host_inst, host_mod, q_out, w_q),
    ]
    sib_hookups = [
        ('sibling_si', sib_inst, sib_mod, si_out, w_si),
        ('sibling_se', sib_inst, sib_mod, se_out, w_se),
        ('sibling_q',  sib_inst, sib_mod, q_in,  w_q),
    ]
    instance_hookups = []
    for role, inst, child_mod, port, wire in (host_hookups + sib_hookups):
        instance_hookups.append({
            'change_type':       'port_connection',
            'module_name':       parent_mod,
            'instance_name':     inst,
            'child_module_name': child_mod,
            'port_name':         port,
            'net_name':          wire,
            'is_mode_s_stitch':  True,
            'bridge_port_role':  role,
            'for_dff':           new_dff_inst,
            **_ctx(f'Parent-scope hookup: {inst}.{port} ← {wire}',
                   'eco_emit_bridge_plumbing.py'),
        })

    # ── 5. Sibling SE-pin consolidation (Route stage only) ─────────────────
    consolidation = {
        'change_type':              'sibling_pin_consolidation',
        'sibling_module':           sib_mod,
        'pin_name':                 'SE',
        'new_net':                  se_out,
        'consolidation_target_dffs': pick.get('consolidation_target_dffs', []),
        'is_mode_s_stitch':         True,
        'bridge_port_role':         'sibling_se',
        'for_dff':                  new_dff_inst,
        **_ctx(f'Consolidate {len(pick.get("consolidation_target_dffs", []))} sibling DFFs onto {se_out} (cluster prefix={pick.get("dominant_se_cluster_prefix")})',
               f'eco_pick_bridge_dffs.py:{Path(pick.get("netlist","?")).name}'),
    }

    # ── 6. Q-closure: rewire one DFF's .SI to bridge Q_in ──────────────────
    q_closure = {
        'change_type':       'si_consumer_replace',
        'sibling_module':    sib_mod,
        'consumer_dff_inst': pick.get('q_consumer_dff'),
        'new_si_net':        q_in,
        'old_si_net':        pick.get('q_consumer_original_si'),
        'is_mode_s_stitch':  True,
        'bridge_port_role':  'sibling_q',
        'for_dff':           new_dff_inst,
        **_ctx(f'Q-closure: rewire {pick.get("q_consumer_dff")}.SI from {pick.get("q_consumer_original_si")!r} to {q_in}',
               'eco_pick_bridge_dffs.py'),
    }

    # ── 7. Buffer cells in sibling module (Route stage only) ───────────────
    si_buffer = {
        'change_type':      'new_logic',
        'module_name':      sib_mod,
        'cell_type':        si_buffer_cell,
        'gate_function':    'BUF',
        'instance_name':    f'eco{jira}_si_buffer',
        'output_net':       si_out,
        'port_connections': {'I': pick.get('candidate_bridge_source_si'), 'Z': si_out},
        'needs_explicit_wire_decl': False,
        'is_mode_s_stitch': True,
        'bridge_port_role': 'sibling_si_driver',
        'for_dff':          new_dff_inst,
        **_ctx(f'Buffer driving {si_out} from {pick.get("candidate_bridge_source_si")} (Route only)',
               'eco_emit_bridge_plumbing.py'),
    }
    se_buffer = {
        'change_type':      'new_logic',
        'module_name':      sib_mod,
        'cell_type':        se_buffer_cell,
        'gate_function':    'BUF',
        'instance_name':    f'eco{jira}_se_buffer',
        'output_net':       se_out,
        'port_connections': {'I': pick.get('candidate_bridge_source_se'), 'Z': se_out},
        'needs_explicit_wire_decl': False,
        'is_mode_s_stitch': True,
        'bridge_port_role': 'sibling_se_driver',
        'for_dff':          new_dff_inst,
        **_ctx(f'Buffer driving {se_out} from {pick.get("candidate_bridge_source_se")} (Route only)',
               'eco_emit_bridge_plumbing.py'),
    }

    # ── Stage routing ───────────────────────────────────────────────────────
    # Synthesize: port_declarations on host AND sibling (so RTL elaborates with
    # the new ports). Synth has NO scan-en network — buffers, consolidation, and
    # Q-closure are P&R-only artifacts (the applier strips bridge_port_role
    # tagged entries from Synth automatically per studier MD §314).
    synth_entries = host_port_decls + sib_port_decls + bridge_wires + instance_hookups
    pp_entries    = host_port_decls + sib_port_decls + bridge_wires + instance_hookups + [consolidation, q_closure]
    route_entries = host_port_decls + sib_port_decls + bridge_wires + instance_hookups + [consolidation, q_closure, si_buffer, se_buffer]
    return {'Synthesize': synth_entries, 'PrePlace': pp_entries, 'Route': route_entries}


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('--bridge-pick',     required=True,
                   help='eco_bridge_pick_<DFF>.json from eco_pick_bridge_dffs.py')
    p.add_argument('--jira',            required=True,
                   help='JIRA number (e.g. 9868) — used in port and wire names')
    p.add_argument('--host-module',     required=True,
                   help='Host module type (e.g. ddrss_umccmd_t_umcarbctrlsw)')
    p.add_argument('--sibling-module',  required=True,
                   help='Sibling module type (e.g. ddrss_umccmd_t_umcdcqarb_0)')
    p.add_argument('--parent-module',   required=True,
                   help='Parent module that instantiates BOTH host and sibling '
                        '(e.g. ddrss_umccmd_t_umcarb) — bridge wires + instance '
                        'hookups live in this scope.')
    p.add_argument('--host-inst',       required=True,
                   help='Instance name of host module under parent (e.g. CTRLSW)')
    p.add_argument('--sibling-inst',    required=True,
                   help='Instance name of sibling module under parent (e.g. DCQARB)')
    p.add_argument('--new-dff-instance', required=True,
                   help='Name of the new ECO DFF (e.g. NeedFreqAdj_reg) — tags '
                        'every emitted entry with for_dff so multiple bridges can '
                        'coexist without collision.')
    p.add_argument('--si-buffer-cell',   default=DEFAULT_SI_BUFFER_CELL,
                   help='Cell type for SI bridge buffer (default: %(default)s)')
    p.add_argument('--se-buffer-cell',   default=DEFAULT_SE_BUFFER_CELL,
                   help='Cell type for SE bridge buffer (default: %(default)s)')
    p.add_argument('--output',          required=True,
                   help='Output JSON path (per-stage artifact lists).')
    args = p.parse_args()

    try:
        pick = json.loads(Path(args.bridge_pick).read_text())
    except Exception as e:
        print(f'FAIL: cannot read bridge_pick JSON: {e}', file=sys.stderr)
        return 1

    # Sanity gates — picker output must satisfy hard preconditions; otherwise
    # bridge_port strategy is unsafe and the studier should fall back to
    # neighbor_dff or constant_zero.
    issues = []
    if len(pick.get('consolidation_target_dffs') or []) < 10:
        issues.append(
            f"consolidation_target_dffs has {len(pick.get('consolidation_target_dffs') or [])} "
            f"DFFs (<10) — bridge_port strategy requires ≥10-DFF cluster per studier "
            f"MD §374. Re-run picker with a larger sibling or fall back to neighbor_dff.")
    if not pick.get('q_consumer_dff'):
        issues.append('q_consumer_dff missing — Q-closure cannot be emitted.')
    if not pick.get('candidate_bridge_source_si'):
        issues.append('candidate_bridge_source_si missing — SI bridge buffer has no source.')
    if not pick.get('candidate_bridge_source_se'):
        issues.append('candidate_bridge_source_se missing — SE bridge buffer has no source.')
    if issues:
        print('FAIL: bridge picker output insufficient for bridge_port strategy:',
              file=sys.stderr)
        for i in issues:
            print(f'  - {i}', file=sys.stderr)
        return 1

    out = emit(pick, args.jira, args.host_module, args.sibling_module,
               args.parent_module, args.host_inst, args.sibling_inst,
               args.new_dff_instance,
               si_buffer_cell=args.si_buffer_cell,
               se_buffer_cell=args.se_buffer_cell)
    Path(args.output).write_text(json.dumps(out, indent=2))

    # Marker for the validator to confirm this script ran (per the C4-marker
    # pattern used elsewhere in the flow)
    Path(args.output.replace('.json', '_marker.txt')).write_text(
        f'ECO_SCRIPT_LAUNCHED: eco_emit_bridge_plumbing.py\n'
        f'  bridge_pick:      {args.bridge_pick}\n'
        f'  for_dff:          {args.new_dff_instance}\n'
        f'  output:           {args.output}\n'
        f'  Synthesize:       {len(out["Synthesize"])} entries\n'
        f'  PrePlace:         {len(out["PrePlace"])} entries\n'
        f'  Route:            {len(out["Route"])} entries\n')

    print(f'ECO_RPT_GENERATED: bridge plumbing → {args.output}')
    print(f'  for_dff:    {args.new_dff_instance}')
    print(f'  Synthesize: {len(out["Synthesize"])} entries (port decls + parent wires + hookups)')
    print(f'  PrePlace:   {len(out["PrePlace"])} entries (+ consolidation + Q-closure)')
    print(f'  Route:      {len(out["Route"])} entries (+ SI/SE buffers)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
