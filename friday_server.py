#!/usr/bin/env python3
"""FRIDAY Server — Flask backend for the FRIDAY EDA Intelligence HUD.

Run from anywhere:
    python3 /proj/rtg_oss_feint1/FEINT_AI_AGENT/genie_agent/friday_server.py
Then open: http://localhost:5100
"""

import json
import os
import re
import subprocess
import glob
import requests as http_requests
from pathlib import Path
from datetime import datetime
from flask import Flask, request, jsonify, send_file

GENIE_ROOT = Path('/proj/rtg_oss_feint1/FEINT_AI_AGENT/genie_agent')
BASE_DIR   = GENIE_ROOT / 'users' / 'abinbaba'
HUD_FILE   = GENIE_ROOT / 'friday_hud.html'
CLI        = BASE_DIR / 'script' / 'genie_cli.py'
DATA_DIR   = BASE_DIR / 'data'
RUNS_DIR   = BASE_DIR / 'runs'

app = Flask(__name__)
app.config['JSON_SORT_KEYS'] = False

# ── TASK TYPE DISPLAY MAPPING ────────────────────────────────────────────────
TYPE_MAP = {
    'cdc_rdc':          'CDC/RDC',
    'lint':             'LINT',
    'spg_dft':          'SPG_DFT',
    'full_static_check':'FULL_CHK',
    'eco_analyze':      'ECO',
    'run_eco':          'ECO',
    'find_equivalent':  'FORMALITY',
    'synthesis':        'SYNTH',
    'analyze_eco':      'ECO',
    'monitor':          'MONITOR',
}

# ── HELPERS ──────────────────────────────────────────────────────────────────
def run_cli(args, timeout=20):
    cmd = ['python3', str(CLI)] + args
    try:
        r = subprocess.run(
            cmd, capture_output=True, text=True,
            cwd=str(BASE_DIR), timeout=timeout
        )
        return r.stdout, r.stderr, r.returncode
    except subprocess.TimeoutExpired:
        return '', 'Command timed out', 1
    except Exception as e:
        return '', str(e), 1


def parse_cli_output(stdout):
    result = {}
    for line in stdout.splitlines():
        l = line.strip()
        if l.startswith('Tag:'):
            result['tag'] = l.split(':', 1)[1].strip()
        elif l.startswith('Matched:'):
            result['matched'] = l.split(':', 1)[1].strip()
        elif l.startswith('Command:'):
            result['command'] = l.split(':', 1)[1].strip()
        elif '[DRY RUN]' in l:
            result['dry_run'] = True
        elif 'No matching instruction' in l or 'No instruction matched' in l:
            result['no_match'] = True
    return result


def read_metadata(tag):
    f = DATA_DIR / f'{tag}_metadata'
    meta = {}
    if f.exists():
        for line in f.read_text(errors='ignore').splitlines():
            if '=' in line:
                k, v = line.split('=', 1)
                meta[k.strip()] = v.strip()
    return meta


def is_pid_running(tag):
    pid_file = DATA_DIR / f'{tag}_pid'
    if not pid_file.exists():
        return False, None
    try:
        pid = int(pid_file.read_text().strip())
        os.kill(pid, 0)
        return True, pid
    except (ValueError, ProcessLookupError, PermissionError):
        return False, None


def tag_to_elapsed(tag):
    try:
        dt = datetime.strptime(str(tag)[:14], '%Y%m%d%H%M%S')
        return max(0, int((datetime.now() - dt).total_seconds()))
    except Exception:
        return 0


def estimate_pct(task_type, elapsed, status):
    if status == 'complete':
        return 100
    if status == 'failed':
        return 0
    durations = {
        'cdc_rdc': 2400, 'lint': 1800, 'spg_dft': 3600,
        'full_static_check': 5400, 'eco_analyze': 7200,
        'run_eco': 7200, 'find_equivalent': 900, 'synthesis': 5400,
    }
    total = durations.get(task_type, 2000)
    return min(95, int(elapsed / total * 100))


def infer_job_status(tag, meta):
    running, pid = is_pid_running(tag)
    if running:
        return 'running', pid

    spec = DATA_DIR / f'{tag}_spec'
    log  = RUNS_DIR / f'{tag}.log'

    if spec.exists():
        try:
            head = spec.read_text(errors='ignore')[:600].upper()
            if 'ERROR:' in head or 'FAILED' in head:
                return 'failed', None
        except Exception:
            pass
        return 'complete', None

    if log.exists():
        try:
            tail = log.read_text(errors='ignore')[-300:].upper()
            if 'ERROR' in tail or 'FAIL' in tail:
                return 'failed', None
        except Exception:
            pass
        return 'complete', None

    return 'unknown', None


def scan_jobs(limit=25):
    jobs = []
    seen = set()
    meta_files = sorted(DATA_DIR.glob('*_metadata'), reverse=True)

    for mf in meta_files:
        tag = mf.name.replace('_metadata', '')
        if tag in seen:
            continue
        seen.add(tag)

        meta      = read_metadata(tag)
        task_type = meta.get('task_type', 'unknown')
        ip        = meta.get('ip') or meta.get('tile') or '—'
        ref_dir   = meta.get('ref_dir', '')
        display   = TYPE_MAP.get(task_type, task_type.upper()[:10])

        status, pid = infer_job_status(tag, meta)
        if status == 'unknown':
            continue

        elapsed = tag_to_elapsed(tag)
        pct     = estimate_pct(task_type, elapsed, status)

        jobs.append({
            'tag':      tag,
            'type':     display,
            'ip':       ip,
            'status':   status,
            'elapsed':  elapsed,
            'pct':      pct,
            'ref_dir':  ref_dir,
            'pid':      pid,
        })

        if len(jobs) >= limit:
            break

    return jobs


# ── ROUTES ───────────────────────────────────────────────────────────────────
@app.route('/')
def index():
    return send_file(HUD_FILE)


@app.route('/api/health')
def health():
    return jsonify({'status': 'ok', 'base_dir': str(BASE_DIR), 'cli': str(CLI)})


@app.route('/api/chat', methods=['POST'])
def chat():
    body        = request.json or {}
    instruction = body.get('instruction', '').strip()
    execute     = body.get('execute', False)

    if not instruction:
        return jsonify({'error': 'empty instruction'}), 400

    args = ['-i', instruction]
    if execute:
        args.append('--execute')

    stdout, stderr, rc = run_cli(args, timeout=15)
    parsed = parse_cli_output(stdout)

    return jsonify({
        'instruction': instruction,
        'execute':     execute,
        'stdout':      stdout,
        'tag':         parsed.get('tag'),
        'matched':     parsed.get('matched'),
        'command':     parsed.get('command'),
        'dry_run':     parsed.get('dry_run', not execute),
        'no_match':    parsed.get('no_match', False),
        'error':       stderr.strip() if rc != 0 else None,
    })


@app.route('/api/jobs')
def get_jobs():
    limit = int(request.args.get('limit', 25))
    return jsonify(scan_jobs(limit=limit))


@app.route('/api/jobs/<tag>/kill', methods=['POST'])
def kill_job(tag):
    stdout, stderr, rc = run_cli(['--kill', tag], timeout=10)
    return jsonify({'stdout': stdout, 'returncode': rc})


@app.route('/api/jobs/<tag>/status')
def job_status(tag):
    stdout, _, rc = run_cli(['--status', tag], timeout=10)
    return jsonify({'output': stdout, 'returncode': rc})


@app.route('/api/jobs/<tag>/log')
def job_log(tag):
    lines_n = int(request.args.get('lines', 60))
    log_file = RUNS_DIR / f'{tag}.log'
    if not log_file.exists():
        return jsonify({'error': 'Log not found', 'lines': []}), 404
    try:
        content = log_file.read_text(errors='ignore').splitlines()
        return jsonify({'tag': tag, 'lines': content[-lines_n:]})
    except Exception as e:
        return jsonify({'error': str(e), 'lines': []}), 500


@app.route('/api/tasks')
def list_tasks():
    period = request.args.get('period', 'today')
    stdout, _, rc = run_cli(['--tasks', period], timeout=10)
    return jsonify({'output': stdout, 'returncode': rc})


# ── CLAUDE AI ENDPOINT ───────────────────────────────────────────────────────
CLAUDE_API_URL = 'https://api.anthropic.com/v1/messages'
CLAUDE_MODEL   = 'claude-haiku-4-5'

FRIDAY_SYSTEM = """You are FRIDAY, an AI assistant for chip design engineers at AMD. \
You help run EDA checks: CDC/RDC, Lint, SPG_DFT, ECO, and full static checks via Genie CLI. \
Rules: (1) Keep every response under 2 sentences — it is spoken aloud via text-to-speech. \
(2) Be concise, confident, and slightly robotic like the Iron Man AI. \
(3) Never use markdown, bullet points, or special characters. \
(4) For action requests, confirm what you are doing, not what you could do."""

ACTION_RE = re.compile(
    r'\b(run|launch|start|kill|stop|analyze|submit)\b', re.IGNORECASE
)

def build_job_context():
    jobs = scan_jobs(limit=10)
    if not jobs:
        return 'No jobs recorded today.'
    running = [j for j in jobs if j['status'] == 'running']
    failed  = [j for j in jobs if j['status'] == 'failed']
    lines   = []
    if running:
        lines.append('Running: ' + ', '.join(f"{j['type']} {j['ip']}" for j in running))
    if failed:
        lines.append('Failed:  ' + ', '.join(f"{j['type']} {j['ip']}" for j in failed))
    done = len([j for j in jobs if j['status'] == 'complete'])
    lines.append(f'Complete today: {done}')
    return ' | '.join(lines)


def call_claude(user_text, job_ctx):
    api_key = os.environ.get('ANTHROPIC_API_KEY', '')
    if not api_key:
        return None, 'ANTHROPIC_API_KEY not set'

    system_with_ctx = f"{FRIDAY_SYSTEM}\n\nCurrent job status: {job_ctx}"

    payload = {
        'model':      CLAUDE_MODEL,
        'max_tokens': 256,
        'system': [
            {
                'type': 'text',
                'text': system_with_ctx,
                'cache_control': {'type': 'ephemeral'},
            }
        ],
        'messages': [{'role': 'user', 'content': user_text}],
    }

    headers = {
        'x-api-key':         api_key,
        'anthropic-version': '2023-06-01',
        'anthropic-beta':    'prompt-caching-2024-07-31',
        'content-type':      'application/json',
    }

    try:
        resp = http_requests.post(
            CLAUDE_API_URL, json=payload, headers=headers, timeout=15
        )
        resp.raise_for_status()
        data = resp.json()
        text = data['content'][0]['text'].strip()
        return text, None
    except http_requests.exceptions.Timeout:
        return None, 'Claude API timed out'
    except Exception as e:
        return None, str(e)


def genie_fallback(text):
    """Fall back to Genie CLI when no API key is set."""
    execute = bool(ACTION_RE.search(text))
    args = ['-i', text]
    if execute:
        args.append('--execute')

    stdout, stderr, rc = run_cli(args, timeout=15)
    parsed = parse_cli_output(stdout)

    tag     = parsed.get('tag')
    matched = parsed.get('matched', '')

    if parsed.get('no_match') or (not matched and not tag):
        return 'I did not recognize that command. Try saying run followed by the check type and IP name.', None

    if tag and execute:
        return f'Launching {matched.replace("could you ", "")}. Tag {tag[-6:]}. Job running.', tag

    return f'Confirmed. {matched.replace("could you ", "")}.', None


@app.route('/api/ai', methods=['POST'])
def ai_chat():
    body = request.json or {}
    text = body.get('text', '').strip()
    if not text:
        return jsonify({'error': 'empty text'}), 400

    api_key = os.environ.get('ANTHROPIC_API_KEY', '')

    # ── No API key → fall back to Genie CLI ──────────────────────────────────
    if not api_key:
        reply, tag = genie_fallback(text)
        return jsonify({'reply': reply, 'tag': tag, 'mode': 'genie'})

    # ── Claude AI path ────────────────────────────────────────────────────────
    job_ctx = build_job_context()
    reply, err = call_claude(text, job_ctx)

    if err:
        # Claude failed — fall back to Genie CLI silently
        reply, tag = genie_fallback(text)
        return jsonify({'reply': reply, 'tag': tag, 'mode': 'genie'})

    # If action implied, also fire genie_cli --execute
    action_tag = None
    if ACTION_RE.search(text):
        if any(w in text.lower() for w in ['run', 'launch', 'start', 'kill', 'stop']):
            stdout, _, rc = run_cli(['-i', text, '--execute'], timeout=15)
            parsed = parse_cli_output(stdout)
            action_tag = parsed.get('tag')
            if action_tag:
                reply += f' Tag {action_tag[-6:]}.'

    return jsonify({'reply': reply, 'tag': action_tag, 'mode': 'claude'})


# ── MAIN ─────────────────────────────────────────────────────────────────────
if __name__ == '__main__':
    print('=' * 60)
    print('  FRIDAY SERVER  — EDA Intelligence System')
    print('=' * 60)
    print(f'  Base : {BASE_DIR}')
    print(f'  CLI  : {CLI}')
    print(f'  URL  : http://localhost:5000')
    print('=' * 60)
    app.run(host='0.0.0.0', port=5100, debug=False, threaded=True)
