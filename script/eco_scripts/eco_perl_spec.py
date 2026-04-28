#!/usr/bin/env python3
"""
eco_perl_spec.py — Generate Perl ECO application script from study JSON.

Replaces eco_applier Phase A (agent reasoning) with deterministic code.
Handles: ALREADY_APPLIED detection, SKIPPED checks, wire_decls exclusion (SVR-9 prevention),
wire_removes, gate line building, and Perl script output.

Usage:
    python3 script/eco_perl_spec.py \
        --study    data/<TAG>_eco_preeco_study.json \
        --ref-dir  <REF_DIR> \
        --tag      <TAG> \
        --jira     <JIRA> \
        --stage    Synthesize|PrePlace|Route \
        --round    <ROUND> \
        [--prev-applied data/<TAG>_eco_applied_round<N-1>.json] \
        --output   runs/eco_apply_<TAG>_<Stage>.pl \
        --status   data/<TAG>_eco_perl_spec_<Stage>.json

Exit code: 0 = OK, 1 = error
"""

import argparse
import gzip
import json
import re
import subprocess
import sys
from pathlib import Path


# ── Helpers ──────────────────────────────────────────────────────────────────

def zgrep_count(pattern, gz_path, timeout=60):
    """grep -cw pattern in gzipped file. Returns int."""
    try:
        proc = subprocess.run(
            f'zcat {gz_path} | grep -cw {repr(pattern)}',
            shell=True, capture_output=True, text=True, timeout=timeout
        )
        return int(proc.stdout.strip() or '0')
    except Exception:
        return 0


def net_exists_in_posteco(net, gz_path, timeout=60):
    """True if net is referenced anywhere in PostEco stage file."""
    return zgrep_count(net, gz_path, timeout) > 0


def already_applied(inst_name, gz_path, prev_status=None, force_reapply=False):
    """Check if instance already inserted in PostEco. Returns True/False."""
    if force_reapply:
        return False
    if prev_status and prev_status == 'SKIPPED':
        return False  # SKIPPED in prior round → not applied
    count = zgrep_count(inst_name, gz_path)
    return count > 0


def output_pin_key(port_connections):
    """Find the output pin (Z, ZN, Q, QN) from port_connections dict."""
    for pin in ('ZN', 'Z', 'Q', 'QN', 'CO', 'S'):
        if pin in port_connections:
            return pin
    # Fallback: last key is usually output
    return list(port_connections.keys())[-1] if port_connections else None


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--study',        required=True)
    p.add_argument('--ref-dir',      required=True)
    p.add_argument('--tag',          required=True)
    p.add_argument('--jira',         required=True)
    p.add_argument('--stage',        required=True, choices=['Synthesize','PrePlace','Route'])
    p.add_argument('--round',        required=True, type=int)
    p.add_argument('--prev-applied', default=None)
    p.add_argument('--output',       required=True)
    p.add_argument('--status',       required=True)
    args = p.parse_args()

    study    = json.loads(Path(args.study).read_text())
    posteco  = f"{args.ref_dir}/data/PostEco/{args.stage}.v.gz"
    preeco   = f"{args.ref_dir}/data/PreEco/{args.stage}.v.gz"

    prev_applied = {}
    if args.prev_applied and Path(args.prev_applied).exists():
        pa = json.loads(Path(args.prev_applied).read_text())
        for e in pa.get(args.stage, []):
            inst = e.get('instance_name') or e.get('cell_name') or e.get('signal_name','')
            if inst:
                prev_applied[inst] = e.get('status','')

    entries  = study.get(args.stage, [])
    # {module_name: {wire_decls, wire_removes, gates}}
    changes  = {}
    statuses = []  # list of {instance_name, status, reason}

    for e in entries:
        if not e.get('confirmed', True):
            statuses.append({'name': e.get('instance_name','?'), 'status':'EXCLUDED',
                             'reason': e.get('reason','unconfirmed')})
            continue

        ct   = e.get('change_type','')
        inst = e.get('instance_name') or e.get('cell_name') or e.get('signal_name','')
        mod  = e.get('module_name','')
        force = e.get('force_reapply', False)

        # ── new_logic_gate / new_logic_dff ───────────────────────────────────
        if ct in ('new_logic_gate', 'new_logic_dff', 'new_logic'):
            if mod not in changes:
                changes[mod] = {'wire_decls': [], 'wire_removes': [], 'gates': []}

            prev_st = prev_applied.get(inst, '')
            if already_applied(inst, posteco, prev_st, force):
                statuses.append({'name': inst, 'status':'ALREADY_APPLIED',
                                 'reason': f'grep found {inst} in PostEco {args.stage}'})
                continue

            # Per-stage port connections
            pcs = e.get('port_connections_per_stage', {}).get(args.stage) \
                  or e.get('port_connections', {})

            # Check all input nets exist in PostEco
            out_pin = output_pin_key(pcs)
            skip_reason = None
            for pin, net in pcs.items():
                if pin == out_pin:
                    continue
                if net in ("1'b0", "1'b1") or str(net).startswith('NEEDS_NAMED_WIRE:'):
                    continue
                if str(net).startswith('UNRESOLVABLE_IN_'):
                    continue
                if not net_exists_in_posteco(net, posteco):
                    skip_reason = f"input net '{net}' absent in {args.stage}"
                    break

            if skip_reason:
                statuses.append({'name': inst, 'status':'SKIPPED', 'reason': skip_reason})
                continue

            # wire_decls: output net only, and only if NOT already in PostEco
            out_net = pcs.get(out_pin, '') if out_pin else ''
            if e.get('needs_explicit_wire_decl') and out_net:
                existing = zgrep_count(out_net, posteco)
                if existing == 0:
                    changes[mod]['wire_decls'].append(out_net)
                else:
                    statuses.append({'name': inst, 'status':'INFO',
                                     'reason': f'wire_decl SKIPPED for {out_net}: already referenced ({existing}x) — SVR-9 prevention'})

            # Build gate line
            cell_type = e.get('cell_type','')
            pins_str  = ', '.join(f'.{pin}({net})' for pin, net in pcs.items())
            gate_line = f'  // ECO {args.jira} TAG={args.tag} Round={args.round}'
            changes[mod]['gates'].append(gate_line)
            changes[mod]['gates'].append(f'  {cell_type} {inst} ( {pins_str} ) ;')
            statuses.append({'name': inst, 'status':'INSERTED',
                             'reason': f'Added to Perl spec for module {mod}'})

        # ── remove_wire_decl ─────────────────────────────────────────────────
        elif ct == 'remove_wire_decl':
            sig = e.get('signal_name','')
            if mod not in changes:
                changes[mod] = {'wire_decls': [], 'wire_removes': [], 'gates': []}
            changes[mod]['wire_removes'].append(sig)
            statuses.append({'name': sig, 'status':'APPLIED',
                             'reason': f'remove_wire_decl added to Perl wire_removes'})

        # ── rewire / port_declaration / port_connection → handled by Passes 2-4 ─
        else:
            statuses.append({'name': inst, 'status':'PASS_2_4',
                             'reason': f'{ct} — handled by eco_applier Passes 2-4, not Perl'})

    # ── Write Perl script ─────────────────────────────────────────────────────
    perl_lines = [
        '#!/usr/bin/perl',
        f'# ECO Apply — JIRA {args.jira} — {args.stage} stage',
        f'# TAG={args.tag}  Round={args.round}',
        '# Auto-generated by eco_perl_spec.py — do NOT edit manually',
        'use strict; use warnings;',
        '',
        'my %changes = (',
    ]

    for mod, spec in changes.items():
        wd_str   = ', '.join(f"'{w}'" for w in spec['wire_decls'])
        wrm_str  = ', '.join(f"'{w}'" for w in spec['wire_removes'])
        gate_str = '\n'.join(f"    {repr(g)}," for g in spec['gates'])
        perl_lines.append(f"  '{mod}' => {{")
        perl_lines.append(f"    wire_decls   => [{wd_str}],")
        perl_lines.append(f"    wire_removes => [{wrm_str}],")
        perl_lines.append(f"    gates        => [")
        perl_lines.append(gate_str)
        perl_lines.append(f"    ],")
        perl_lines.append(f"  }},")

    perl_lines += [
        ');',
        '',
        "my $in_module = ''; my @buf; my %processed;",
        "while (my $line = <STDIN>) {",
        "    if ($line =~ /^module\\s+(\\S+?)[\\s(;]/) {",
        "        my $mod = $1;",
        "        if (exists $changes{$mod}) { $in_module=$mod; @buf=($line); next; }",
        "    }",
        "    if ($in_module) {",
        "        if ($line =~ /^endmodule\\b/) {",
        "            my $spec = $changes{$in_module};",
        "            my %rm = map { $_ => 1 } @{ $spec->{wire_removes} };",
        "            my @filtered;",
        "            for my $bl (@buf) {",
        "                if (%rm && $bl =~ /^\\s*wire\\s+(\\w+)\\s*;/ && $rm{$1})",
        "                    { print STDERR \"REMOVED wire $1\\n\"; next; }",
        "                push @filtered, $bl;",
        "            }",
        "            # Add wire decls — skip if net already in buffer (SVR-9 prevention)",
        "            my $buf_text = join('', @filtered);",
        "            for my $net (@{ $spec->{wire_decls} }) {",
        "                if ($buf_text =~ /\\b\\Q$net\\E\\b/)",
        "                    { print STDERR \"SVR9_PREVENT: SKIP wire $net\\n\"; }",
        "                else { push @filtered, \"  wire $net ;\\n\"; }",
        "            }",
        "            push @filtered, \"$_\\n\" for @{ $spec->{gates} };",
        "            print join('', @filtered); print $line;",
        "            $processed{$in_module}++;",
        "            $in_module=''; @buf=();",
        "        } else { push @buf, $line; }",
        "    } else { print $line; }",
        "}",
        "print STDERR \"\\n=== ECO PERL SPEC SUMMARY: " + args.tag + " " + args.stage + " ===\\n\";",
        "for my $mod (sort keys %changes) {",
        "    if ($processed{$mod}) { print STDERR \"OK  $mod\\n\"; }",
        "    else { print STDERR \"MISSING  $mod\\n\"; }",
        "}",
        "print STDERR \"=== DONE ===\\n\";",
    ]

    Path(args.output).write_text('\n'.join(perl_lines) + '\n')
    Path(args.output).chmod(0o755)

    # Write status JSON
    Path(args.status).write_text(json.dumps({
        'tag': args.tag, 'stage': args.stage, 'round': args.round,
        'modules': list(changes.keys()),
        'entries': statuses
    }, indent=2))

    inserted = sum(1 for s in statuses if s['status'] == 'INSERTED')
    skipped  = sum(1 for s in statuses if s['status'] == 'SKIPPED')
    already  = sum(1 for s in statuses if s['status'] == 'ALREADY_APPLIED')
    print(f"eco_perl_spec.py: {args.stage} — {inserted} INSERTED, {skipped} SKIPPED, {already} ALREADY_APPLIED")
    print(f"Perl script: {args.output}")
    print(f"Status JSON: {args.status}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
