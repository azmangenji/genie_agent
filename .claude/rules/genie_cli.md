---
paths:
  - "script/genie_cli.py"
  - "script/read_csv.py"
  - "*.csv"
  - "runs/**"
  - "data/**"
---

# Genie CLI - Detailed Documentation

## CLI Options

| Option | Short | Description |
|--------|-------|-------------|
| `--help` | `-h` | Show help message |
| `--instruction` | `-i` | The instruction to parse and execute |
| `--execute` | `-e` | Execute command (default is dry-run) |
| `--xterm` | `-x` | Run in xterm popup window |
| `--email` | `-m` | Send results to debuggers from assignment.csv |
| `--to EMAIL` | | Override email recipients |
| `--list` | `-l` | List all available instructions |
| `--status` | `-s` | Check task status by tag |
| `--tasks` | `-t` | List tasks: `running`, `today`, `yesterday`, or `YYYY-MM-DD` |
| `--kill` | `-k` | Kill a running task by tag |
| `--analyze` | `-a` | Claude monitors and analyzes results (static checks) |
| `--setup-user` | | Setup user directory for multi-user environment |

## Execution Modes

### 1. Dry Run (Default)
Shows command without executing:
```bash
python3 genie_cli.py -i "run lint at /proj/xxx for umc9_3"
```

### 2. Background Execution (`--execute`)
```bash
python3 genie_cli.py -i "run lint at /proj/xxx for umc9_3" --execute --email
```
- Task runs in detached process
- Output: `runs/<tag>.log`
- PID saved: `data/<tag>_pid`

### 3. Xterm Popup Mode (`--xterm`)
```bash
python3 genie_cli.py -i "run full_static_check for umc9_3" --execute --xterm --email
```
- Opens xterm window with live output
- Closes automatically on completion

### 4. Analyze Mode (`--analyze`)
```bash
python3 genie_cli.py -i "run cdc_rdc at /proj/xxx for umc9_3" --execute --analyze --email
```
- Claude monitors task completion
- Spawns analysis agents
- Generates HTML report: `data/<tag>_analysis.html`
- Emails full analysis

## Configuration Files

### keyword.csv (252 entries)
Keywords and synonyms for one-hot encoding:
```csv
branch,TileBuilderBranch
run,execute,start,kick off
monitor,check status,watch
```

### instruction.csv (60 entries)
Maps patterns to scripts:
```csv
could you run cdc_rdc,rtg_oss_feint/static_check_unified.csh $refDir $ip $tile $integer $tag $p4File $checkType,134,start run
```

### arguement.csv
Argument types: `target`, `params`, `tune`, `checkType`, `tile`, `ip`, etc.

### patterns.csv
Regex patterns for special detection:
```csv
\d{4}-\d{2}-\d{2},date,
^(cdc|resetcheck)\s+report\s+(crossing|item).*,waiver,I
```

### assignment.csv
User configuration: `debugger`, `disk`, `project`, `tile`

## One-Hot Encoding

1. Each keyword = unique bit position in 252-dimension vector
2. Synonyms share same bit position
3. Input encoded, compared against instruction encodings
4. Best match (>50% coverage) selected

Example:
```
Input: "run lint at /proj/xxx"
Keywords: "run" (bit 55), "lint" (bit 123)
Matched: "could you run lint" → static_check_unified.csh
```

## Pattern Detection

| Pattern | Detection | Example |
|---------|-----------|---------|
| `refDir` | `os.path.isdir()` | `/proj/xxx/tree_dir` |
| `tune` | Starts with `tune/` | `tune/FxPlace/opt.tcl` |
| `p4File` | Starts with `//depot/` | `//depot/umc_ip/branches/...` |
| `integer` | `^[0-9]+$` | `12345678` |
| `params` | `PARAM = VALUE` | `NICKNAME = test_run` |

## Params Block Format

```
with params <: PARAM1 = value1
PARAM2 = value2 :>
```

Example:
```bash
python3 genie_cli.py -i "run supra regression for umcdat target FxSynthesize at /proj/xxx/tiles with params <: NICKNAME = my_run
SYN_VF_FILE = /proj/xxx/umc_top.vf :>" --execute --xterm --email
```

## Task Management

### Generated Files
- `runs/<tag>.csh` - Run script
- `runs/<tag>.log` - Execution log
- `data/<tag>_pid` - Process ID
- `data/<tag>_email` - Email flag
- `data/<tag>_spec` - Task output

### Email Subject Format
```
[Status] TASK_TYPE - tile @ directory (tag)
```
Status: `[Success]`, `[Failed]`, `[Completed]`

## Key Methods

- `encode_instruction()` - One-hot encode user input
- `find_best_match()` - Match against instruction patterns
- `build_command()` - Substitute variables into script
- `run_and_capture()` - Execute or generate run script
- `send_email()` - Send HTML-formatted results

## Multi-User Setup

```bash
cd /proj/rtg_oss_feint1/FEINT_AI_AGENT/genie_agent
python3 script/genie_cli.py --setup-user --user-email Your.Name@amd.com --user-disk /proj/rtg_oss_er_feint1/username
```

Creates: `users/$USER/` with assignment.csv, data/, runs/, symlinks to shared scripts.
