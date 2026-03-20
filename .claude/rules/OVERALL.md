---
paths:
  - ".claude/CLAUDE.md"
  - ".claude/rules/**"
  - "CLAUDE.md.backup*"
---

# UVM RTL Testbench - Full Documentation Reference

This is the complete documentation backup. Loads when working on CLAUDE.md or rules files.

---

# UVM RTL Testbench - Claude Code Instructions

This directory provides Claude Code with skills, agents, and templates for UVM-based RTL verification work.

---

## External References

For detailed information on specific topics, read these reference files:

| Topic | Reference File |
|-------|----------------|
| **CDC/RDC Issues** | `/home/abinbaba/Questa_CDC_RDC_Complete_Reference.md` |
| **CDC/RDC Tutorial (PDF)** | `/home/abinbaba/Desktop/Questa_Cdc_Rdc_Tutorial.pdf` |
| **CDC/RDC Command Reference (PDF)** | `/home/abinbaba/Desktop/command_ref.pdf` |
| **RDC User Guide (PDF)** | `/home/abinbaba/Desktop/rdc_user.pdf` |
| **DSO.ai, Timing Comparison, Permutons** | `/proj/rtg_oss_er_feint2/abinbaba/ROSENHORN_DSO_v2/main/pd/tiles/.claude/CLAUDE.md` |
| **DSO.ai Official Guide (PDF)** | `/home/abinbaba/dso_guide.pdf` |

---

## IMPORTANT: Directory Sync Requirement

**This is the PRIMARY agent directory.** There is a secondary Genie-only directory that must be kept in sync.

| Directory | Purpose | Path |
|-----------|---------|------|
| **Primary (this)** | Main agent with email + CLI support | `/proj/rtg_oss_feint1/FEINT_AI_AGENT/abinbaba/rosenhorn_agent_flow/main_agent` |
| **Secondary (genie)** | CLI-only agent, **multi-user setup** | `/proj/rtg_oss_feint1/FEINT_AI_AGENT/genie_agent` |

### Secondary Directory: Multi-User Setup

The genie_agent directory supports **multiple users** with shared scripts but isolated data:

```
/proj/rtg_oss_feint1/FEINT_AI_AGENT/genie_agent/
├── script/                 # SHARED - all users use same scripts
├── csh/                    # SHARED
├── *.csv                   # SHARED configs
└── users/                  # USER-SPECIFIC directories
    ├── abinbaba/
    │   ├── assignment.csv  # User's settings (debuggers, disk, paths)
    │   ├── data/           # User's task data
    │   ├── runs/           # User's run logs
    │   ├── params_centre/  # User's params repository
    │   ├── log_centre/     # User's centralized logs
    │   ├── tune_centre/    # User's tune files
    │   └── script -> ...   # Symlink to shared scripts
    ├── warwang/
    └── ramkver/
```

**New users must run setup once (email and disk path are required):**
```bash
cd /proj/rtg_oss_feint1/FEINT_AI_AGENT/genie_agent

# Option 1: Provide email and disk path on command line
python3 script/genie_cli.py --setup-user --user-email Your.Name@amd.com --user-disk /proj/rtg_oss_er_feint1/your_username

# Option 2: Will prompt for email and disk path interactively
python3 script/genie_cli.py --setup-user
```

**Setup prompts:**
1. **Email address** (required): Your AMD email for notifications (e.g., `Firstname.Lastname@amd.com`)
2. **Disk path** (required): Your working disk for storing runs and outputs (e.g., `/proj/rtg_oss_er_feint1/your_username`)

**What --setup-user creates:**
```
users/$USER/
├── assignment.csv       # User's settings (with email and disk pre-configured)
├── data/               # User's task data
├── runs/               # User's run logs
├── params_centre/      # User's params repository
├── log_centre/         # User's centralized logs
├── tune_centre/        # User's tune files
├── script -> ...       # Symlink to shared scripts
├── csh -> ...          # Symlink to shared csh
├── py -> ...           # Symlink to shared py
├── instruction.csv -> ... # Symlink to shared CSV
├── keyword.csv -> ...  # Symlink to shared CSV
├── arguement.csv -> ...# Symlink to shared CSV
└── patterns.csv -> ... # Symlink to shared CSV
```

**Then run from their user directory:**
```bash
cd /proj/rtg_oss_feint1/FEINT_AI_AGENT/genie_agent/users/$USER
python3 script/genie_cli.py -i "run lint at /proj/xxx for umc9_3" --execute --email
```

**Configure assignment.csv (optional):**

The assignment.csv is pre-configured with your email and disk path. You can customize:
```csv
project,your_project
debugger,another.colleague@amd.com
```

### Auto-Sync Rule

**When updating any of these files in the primary directory, ALWAYS copy to the secondary directory:**

| File Type | Primary Location | Secondary Location |
|-----------|------------------|-------------------|
| `genie_cli.py` | `script/genie_cli.py` | `/proj/rtg_oss_feint1/FEINT_AI_AGENT/genie_agent/script/genie_cli.py` |
| `read_csv.py` | `script/read_csv.py` | `/proj/rtg_oss_feint1/FEINT_AI_AGENT/genie_agent/script/read_csv.py` |
| CSV configs | `*.csv` (keyword, instruction, arguement, patterns) | `/proj/rtg_oss_feint1/FEINT_AI_AGENT/genie_agent/*.csv` |
| RTG scripts | `script/rtg_oss_feint/**/*.csh` | `/proj/rtg_oss_feint1/FEINT_AI_AGENT/genie_agent/script/rtg_oss_feint/**/*.csh` |
| Perl scripts | `script/rtg_oss_feint/**/*.pl` | `/proj/rtg_oss_feint1/FEINT_AI_AGENT/genie_agent/script/rtg_oss_feint/**/*.pl` |
| Environment | `csh/env.csh` | `/proj/rtg_oss_feint1/FEINT_AI_AGENT/genie_agent/csh/env.csh` |

**Quick sync command after updates:**
```bash
# Sync genie_cli.py
cp script/genie_cli.py /proj/rtg_oss_feint1/FEINT_AI_AGENT/genie_agent/script/

# Sync all RTG scripts
cp -r script/rtg_oss_feint/* /proj/rtg_oss_feint1/FEINT_AI_AGENT/genie_agent/script/rtg_oss_feint/

# Sync CSV configs
cp *.csv /proj/rtg_oss_feint1/FEINT_AI_AGENT/genie_agent/
```

---

## Quick Start

When you start Claude Code in this project, you can use these slash commands:

### UVM Component Generation
- `/uvm-driver` - Generate a UVM driver component
- `/uvm-monitor` - Generate a UVM monitor component
- `/uvm-scoreboard` - Generate a UVM scoreboard component
- `/uvm-agent` - Generate a complete UVM agent
- `/uvm-env` - Generate a UVM environment
- `/uvm-sequence` - Generate a UVM sequence
- `/uvm-test` - Generate a UVM test class

### RTL Analysis & Debug
- `/rtl-analyze` - Analyze RTL code for issues, lint, and best practices
- `/rtl-debug` - Help debug RTL simulation failures
- `/waveform-debug` - Analyze waveform issues and suggest fixes

### Simulation & Coverage
- `/compile` - Compile RTL and testbench
- `/simulate` - Run simulation with options
- `/coverage` - Analyze coverage reports and suggest improvements
- `/regress` - Run regression suite

### Code Review & Quality
- `/review-sv` - Review SystemVerilog code for best practices
- `/review-uvm` - Review UVM testbench for methodology compliance

### PD Agent (Genie CLI)
- `/agent` - Send instructions to the Agent Flow

---

## Genie CLI - PD Agent Interface (Alternative to Email)

The Agent Flow supports **two methods** for sending instructions:

| Method | Entry Point | Description |
|--------|-------------|-------------|
| **Email (Original)** | `mail_centre/vtoHybridModel.py` | Send email to VTO → Agent processes and responds via email |
| **Genie CLI (Alternative)** | `main_agent/script/genie_cli.py` | Direct CLI bypass → Faster, no email required |

The Genie CLI was created as a **faster alternative** that bypasses the email system entirely. Both methods execute the same underlying scripts and share the same configuration files.

### Usage

**Ask naturally (via Claude Code):**
```
Summarize static check at /proj/xxx/tree_dir
Run CDC/RDC at /proj/xxx/tree_dir for umc9_3
Report timing and area for /proj/xxx/tile_dir
Monitor supra run at /proj/xxx/tile_dir for target FxSynthesize
```

**Or use the `/agent` skill:**
```
/agent run lint at /proj/xxx for umc9_3
/agent report timing and area for /proj/xxx/tile_dir
```

**Or use the CLI directly (run from main_agent directory):**
```bash
python3 script/genie_cli.py -i "<instruction>" --execute --email
```

### Available Commands

| Category | Commands |
|----------|----------|
| **Static Checks** | `run cdc_rdc`, `run lint`, `run spg_dft`, `run full_static_check`, `summarize static check` |
| **TileBuilder** | `branch from`, `run supra regression`, `monitor supra run`, `rerun <target>`, `stop run`, `report timing and area`, `report utilization`, `report formality`, `list tilebuilder directories` |
| **Params/Tune** | `update params`, `add params`, `update params to/from params center`, `add command to <tune>` |
| **Waivers** | `add cdc_rdc waiver`, `add lint waiver`, `update cdc_rdc constraint` |
| **P4** | `sync up new tree`, `check changelist number`, `submit files` |
| **RTL Analysis** | `analyze clock reset structure` |

### Email Notification

Add `--email` flag to send results to debuggers (from assignment.csv):
- **Immediate results**: Email sent right away (summarize, report timing, list, check changelist)
- **Long-running tasks**: Email sent when task completes (run cdc_rdc, run lint, branch, etc.)

### Examples

```bash
# Summarize static check (immediate result + email)
python3 script/genie_cli.py -i "summarize static check at /proj/xxx/tree_dir" --execute --email

# Run lint in background (long-running, email on completion)
python3 script/genie_cli.py -i "run lint at /proj/xxx/tree_dir for umc9_3" --execute --email

# Run timing report in xterm popup with email
python3 script/genie_cli.py -i "report timing and area for /proj/xxx/tile_dir" --execute --xterm --email

# Run full static check in xterm (auto-creates workspace)
python3 script/genie_cli.py -i "run full_static_check for umc9_3" --execute --xterm --email

# Run supra regression with params (in xterm mode)
python3 script/genie_cli.py -i "run supra regression for umcdat target FxSynthesize at /proj/xxx/tiles with params <: NICKNAME = my_run_name
SYN_VF_FILE = /proj/xxx/umc_top.vf :>" --execute --xterm --email

# List available commands
python3 script/genie_cli.py --list

# Check task status
python3 script/genie_cli.py --status <tag>

# Kill a running task
python3 script/genie_cli.py --kill <tag>
```

### Supra Regression with Params

To run supra regression (TileBuilder run) with custom parameters, use the `<: ... :>` block syntax:

**Command Format:**
```
run supra regression for <tile> target <target> at <tiles_directory> with params <: PARAM1 = value1
PARAM2 = value2 :>
```

**Required Arguments:**
| Argument | Description | Example |
|----------|-------------|---------|
| `tile` | Tile name (from arguement.csv) | `umcdat`, `umccmd`, `osssys` |
| `target` | TileBuilder target | `FxSynthesize`, `FxPlace`, `FxRoute` |
| `tiles_directory` | Path to tiles directory | `/proj/xxx/main/pd/tiles` |

**Common Params:**
| Param | Description | Example |
|-------|-------------|---------|
| `NICKNAME` | Custom run name suffix | `umcdat_NO_DSO_23Feb` |
| `SYN_VF_FILE` | RTL verilog filelist path | `/proj/xxx/umc_top.vf` |
| `TILES_TO_RUN` | Override tile to run | `umcdat` |
| `DSO_USE` | Enable/disable DSO | `0` or `1` |

**Examples:**
```bash
# Run synthesis for umcdat with custom NICKNAME and SYN_VF_FILE
python3 script/genie_cli.py -i "run supra regression for umcdat target FxSynthesize at /proj/rtg_oss_er_feint2/abinbaba/ROSENHORN_DSO_v2/main/pd/tiles with params <: NICKNAME = umcdat_NO_DSO_23Feb
SYN_VF_FILE = /proj/rtg_oss_er_feint1/abinbaba/umc_rosenhorn_Feb23074235/out/linux_4.18.0_64.VCS/umc9_3/config/umc_top_drop2cad/pub/sim/publish/tiles/tile/umc_top/publish_rtl/umc_top.vf :>" --execute --xterm --email

# Run place for umccmd
python3 script/genie_cli.py -i "run supra regression for umccmd target FxPlace at /proj/xxx/tiles with params <: NICKNAME = umccmd_test :>" --execute --xterm --email
```

**Script Used:** `make_tilebuilder_run.csh`

**Instruction Matched:** `could you run supra regression for target at following directory`

**Output:**
- Creates tile directory: `<tiles_dir>/<tile>_<NICKNAME>` (e.g., `umcdat_NO_DSO_23Feb`)
- Params file: `data/<tag>.params`
- Run log: `runs/<tag>.log`

---

## Directory Structure

```
.claude/
├── CLAUDE.md          # This file - project instructions
├── settings.json      # Permissions and environment settings
├── agents/            # Specialized AI agents
│   ├── uvm-expert.md      # UVM methodology expert
│   ├── rtl-debugger.md    # RTL debug specialist
│   └── coverage-analyzer.md # Coverage analysis expert
├── skills/            # Slash command definitions
│   ├── uvm-driver.md
│   ├── uvm-monitor.md
│   ├── uvm-scoreboard.md
│   ├── uvm-agent.md
│   ├── uvm-env.md
│   ├── uvm-sequence.md
│   ├── uvm-test.md
│   ├── rtl-analyze.md
│   ├── rtl-debug.md
│   ├── compile.md
│   ├── simulate.md
│   ├── coverage.md
│   └── review-sv.md
└── templates/         # Code templates
    ├── driver.sv.template
    ├── monitor.sv.template
    ├── scoreboard.sv.template
    ├── agent.sv.template
    ├── env.sv.template
    ├── sequence.sv.template
    ├── sequence_item.sv.template
    ├── test.sv.template
    ├── interface.sv.template
    └── package.sv.template
```

---

## Common Workflows

### 1. Creating a New UVM Agent
```
User: /uvm-agent
Claude: Will ask for:
  - Agent name
  - Interface signals
  - Protocol details
  - Active/Passive mode
Then generates: driver, monitor, sequencer, agent, sequence_item
```

### 2. Debugging a Simulation Failure
```
User: /rtl-debug
Claude: Will ask for:
  - Error message or log file
  - Test name
  - Expected vs actual behavior
Then analyzes and suggests fixes
```

### 3. Improving Coverage
```
User: /coverage
Claude: Will ask for:
  - Coverage report location
  - Target coverage percentage
Then analyzes gaps and suggests new tests/sequences
```

---

## UVM Coding Standards

When generating UVM code, Claude follows these conventions:

1. **Naming Conventions**
   - Classes: `my_driver`, `my_monitor` (snake_case)
   - Signals: `data_valid`, `read_enable` (snake_case)
   - Parameters: `DATA_WIDTH`, `ADDR_WIDTH` (UPPER_CASE)
   - Macros: `uvm_component_utils`, `uvm_field_int`

2. **File Organization**
   - One class per file
   - Filename matches class name: `my_driver.sv`
   - Package file: `my_pkg.sv`

3. **UVM Phases**
   - Use standard phase methods: `build_phase`, `connect_phase`, `run_phase`
   - Avoid deprecated phases

4. **Factory Registration**
   - Always use `uvm_component_utils` or `uvm_object_utils`
   - Use factory create methods: `my_driver::type_id::create()`

5. **Messaging**
   - Use UVM reporting: `uvm_info`, `uvm_warning`, `uvm_error`, `uvm_fatal`
   - Include meaningful message IDs

---

## Environment Variables

The following environment variables are commonly used:

| Variable | Description |
|----------|-------------|
| `UVM_HOME` | UVM library installation path |
| `VCS_HOME` | VCS installation directory |
| `VERDI_HOME` | Verdi installation directory |
| `TB_TOP` | Testbench top module |
| `DUT_TOP` | DUT top module |
| `SIM_DIR` | Simulation run directory |
| `COV_DIR` | Coverage database directory |

---

## Tips for Users

1. **Be Specific**: When asking for help, provide context about your DUT and testbench
2. **Share Error Messages**: Copy the full error, not just fragments
3. **Mention Constraints**: Specify any coding standards or restrictions
4. **Provide Examples**: If you have preferred coding style, share a sample

---

## Agent Flow - Architecture Deep Dive

The Agent Flow is an intelligent PD task automation system with **two operational modes**:

| Mode | Location | Entry Point | Use Case |
|------|----------|-------------|----------|
| **Email Flow (Original)** | `mail_centre/` | Send email to VTO | Remote access, automated submissions |
| **CLI Flow (Genie - Alternative)** | `main_agent/` | `/agent` skill, natural language, or CLI | Claude Code integration, faster iteration |

Both modes share the same scripts, configuration files, and logic - only the entry point differs.

### Directory Structure Overview

The agent system is organized into multiple directories under `rosenhorn_agent_flow/`:

```
rosenhorn_agent_flow/
├── main_agent/          # CLI agent (genie_cli.py) - current working directory
├── mail_centre/         # Email-based agent (vtoHybridModel.py)
├── params_centre/       # Central params repository (per-tile overrides)
├── tune_centre/         # Central tune files repository (per-tile/target)
└── log_centre/          # Centralized log storage
```

| Directory | Purpose | Key Files |
|-----------|---------|-----------|
| **main_agent/** | CLI interface (this directory) | `script/genie_cli.py`, `script/rtg_oss_feint/`, `data/`, `runs/` |
| **mail_centre/** | Email flow processing | `tasksMail.csv`, `vtoHybridModel.py`, `instruction.csv` |
| **params_centre/** | TileBuilder params storage | `<tile>/override.params`, `<tile>/override.controls` |
| **tune_centre/** | Tune TCL files storage | `<tile>/<target>/*.tcl`, `*.sdc` |
| **log_centre/** | Centralized logs | (currently empty) |

**Relationship:**
```
┌─────────────────┐     ┌─────────────────┐
│   mail_centre   │     │   main_agent    │
│ (Email Flow)    │     │ (CLI Flow)      │
└────────┬────────┘     └────────┬────────┘
         │                       │
         └───────────┬───────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │   Execute Scripts     │
         │   (shared scripts)    │
         └───────────┬───────────┘
                     │
         ┌───────────┴───────────┐
         ▼                       ▼
┌─────────────────┐     ┌─────────────────┐
│  params_centre  │     │  tune_centre    │
│ (Push/Pull)     │     │ (Push/Pull)     │
└─────────────────┘     └─────────────────┘
```

**params_centre structure:**
```
params_centre/
├── osssys/override.params
├── sdma0_gc/override.params
├── umccmd/override.params
└── umcdat/
    ├── override.params      # TileBuilder params (NICKNAME, TILES_TO_RUN, etc.)
    └── override.controls    # TileBuilder controls
```

**tune_centre structure:**
```
tune_centre/
├── umccmd/<target>/*.tcl
└── umcdat/
    └── FxSynthesize/
        ├── FxSynthesize.post_initial_map.tcl
        ├── FxSynthesize.post_logic_opto.tcl
        ├── FxSynthesize.post_opt.tcl
        └── Syn.Constraints.sdc
```

---

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                             AGENT FLOW                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────┐                    ┌─────────────────┐                 │
│  │   EMAIL FLOW    │                    │    CLI FLOW     │                 │
│  │ (vtoHybridModel)│                    │   (genie_cli)   │                 │
│  └────────┬────────┘                    └────────┬────────┘                 │
│           │                                      │                          │
│           ▼                                      ▼                          │
│  ┌─────────────────┐                    ┌─────────────────┐                 │
│  │ tasksMail.csv   │                    │  User Input     │                 │
│  │ (from emails)   │                    │  (natural lang) │                 │
│  └────────┬────────┘                    └────────┬────────┘                 │
│           │                                      │                          │
│           └────────────────┬─────────────────────┘                          │
│                            ▼                                                │
│                   ┌─────────────────┐                                       │
│                   │  ONE-HOT ENCODE │ ◄── keyword.csv (252 keywords)        │
│                   │  (Best Match)   │                                       │
│                   └────────┬────────┘                                       │
│                            │                                                │
│                            ▼                                                │
│                   ┌─────────────────┐                                       │
│                   │ INSTRUCTION     │ ◄── instruction.csv (60 patterns)     │
│                   │ MATCHING        │                                       │
│                   └────────┬────────┘                                       │
│                            │                                                │
│                            ▼                                                │
│                   ┌─────────────────┐                                       │
│                   │ ARGUMENT PARSE  │ ◄── arguement.csv + patterns.csv      │
│                   │ (Extract vars)  │                                       │
│                   └────────┬────────┘                                       │
│                            │                                                │
│                            ▼                                                │
│                   ┌─────────────────┐                                       │
│                   │ CSH SCRIPT GEN  │ ◄── script/rtg_oss_feint/*.csh        │
│                   │ + EXECUTION     │                                       │
│                   └────────┬────────┘                                       │
│                            │                                                │
│                            ▼                                                │
│                   ┌─────────────────┐                                       │
│                   │ EMAIL RESULTS   │ ◄── assignment.csv (debuggers)        │
│                   │ (HTML format)   │                                       │
│                   └─────────────────┘                                       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Two Operational Modes

| Mode | Entry Point | Use Case |
|------|-------------|----------|
| **Email Flow** | `vtoHybridModel.py` | Processes emails from VTOs, parses requests, executes tasks |
| **CLI Flow** | `genie_cli.py` | Direct invocation from Claude Code or command line |

---

### Configuration Files

The agent reads several CSV configuration files from the `main_agent` directory (your current working directory):

#### 1. keyword.csv (252 entries)
Defines keywords and their synonyms for one-hot encoding.

**Format:** `keyword,synonym1,synonym2,...`

**Examples:**
```csv
branch,TileBuilderBranch
close,shut down
impact tiles,for tiles,For tiles,Impact tiles,impact tile
run,execute,start,kick off
monitor,check status,watch
```

**Purpose:** Each keyword is assigned a unique position in the one-hot vector. Synonyms map to the same position, enabling flexible natural language matching.

#### 2. instruction.csv (60 entries)
Maps instruction patterns to executable scripts.

**Format:** `instruction_text,script_path,id,type,...`

**Examples:**
```csv
could you run cdc_rdc,rtg_oss_feint/static_check_unified.csh $refDir $ip $tile $integer $tag $p4File $checkType,134,start run
could you report timing and area,rtg_oss_feint/supra/synthesis_timing.csh $refDir $ip $tile $integer $tag $noLsf,134,start run
could you branch from,rtg_oss_feint/supra/tb_branch.csh $tile $runDir $refDir $target $params $tune $tag $table,1,start run
```

**Purpose:** When user input is encoded, it's matched against these instruction encodings to find the best-matching script.

#### 3. arguement.csv (Large file)
Defines argument types for parsing.

**Format:** `keyword,type`

**Argument Types:**
| Type | Description | Example Values |
|------|-------------|----------------|
| `target` | TileBuilder targets | `FxSynthesize`, `FxPlace`, `FxRoute` |
| `params` | Parameter names | `PROJECT`, `TILE`, `CONTEXT` |
| `tune` | Tune file paths | `tune/FxPlace/opt.tcl` |
| `controls` | Control parameters | Various control settings |
| `checkType` | Static check types | `cdc_rdc`, `lint`, `spg_dft`, `full_static_check` |
| `updateType` | Update types | `waiver`, `constraint`, `config`, `version` |
| `tile` | Tile names | Project-specific tile names |
| `ip` | IP/Project codes | `umc9_3`, `umc9_2` |
| `snpstcl` | Synopsys TCL commands | `set_app_var`, `report_timing` |
| `csh` | CSH commands | `source`, `setenv` |
| `edatool` | EDA tool versions | `synopsys/2023.12-SP3` |

#### 4. patterns.csv (19 entries)
Regex patterns for special argument detection.

**Format:** `pattern,type,flags`

**Examples:**
```csv
\d{4}-\d{2}-\d{2},date,
^(cdc|resetcheck)\s+report\s+(crossing|item).*,waiver,I
^netlist\s+(clock|constant|port|blackbox|memory|reset).*,constraint,I
^\s*[A-Z_]+:\s+.*,config,I
^(error|filename|code|msg|line|column|reason|author)\s*:.*,lint_waiver,I
^(CDC_Verif|0in)/[\d._]+$,version,I
```

**Purpose:** Matches complex patterns like waivers, constraints, config entries, dates, and version strings.

#### 5. assignment.csv
Project-specific configuration including debugger emails.

**Key Entries:**
| Key | Description |
|-----|-------------|
| `debugger` | Email addresses for notification (multiple allowed) |
| `manager` | Manager email addresses |
| `flowLead` | Flow lead contacts |
| `tile` | Owned tile names |
| `disk` | Available disk paths |
| `project` | Project name |
| `vto` | VTO names for email filtering |

---

### How One-Hot Encoding Works

1. **Each keyword = unique bit position** in a 252-dimension vector
2. **Synonyms share the same bit position**
3. **Input encoding:** Words from user input are converted to one-hot, then summed
4. **Best-match algorithm:** Compare encoded input against all instruction encodings

**Example:**
```
Input: "run lint at /proj/xxx"
Keywords found: "run" (bit 55), "lint" (bit 123)
Encoded: [0,0,...,1,...,1,...,0]  (bits 55 and 123 set)

Matched instruction: "could you run lint"
→ Script: rtg_oss_feint/static_check_unified.csh
```

**Matching Threshold:** 50% coverage required for a valid match.

---

### Script Execution Flow

#### Immediate Results (Inline Execution)
For queries like `summarize`, `report timing`, `check changelist`:
```
User Input → Parse → Execute Script → Capture Output → Display/Email
```

#### Long-Running Tasks (Background Execution)
For tasks like `run lint`, `run cdc_rdc`, `branch from`:
```
User Input → Parse → Generate Run Script → Submit to Queue → Monitor
                                              │
                                              ▼
                              On completion → Send Email
```

**Generated run scripts saved to:** `runs/<tag>.csh`
**Execution logs saved to:** `runs/<tag>.log`

---

### Script Directory Structure

```
script/
├── genie_cli.py                        # CLI interface
└── rtg_oss_feint/
    ├── static_check_unified.csh        # Unified entry for all static checks
    ├── sync_tree_unified.csh           # Unified entry for tree sync
    ├── finishing_task.csh              # Task completion handler
    ├── lsf.csh                         # LSF job submission utilities
    │
    ├── umc/                            # UMC project scripts
    ├── oss/                            # OSS project scripts
    ├── gmc/                            # GMC project scripts (Orion)
    │
    └── supra/                          # TileBuilder/Supra scripts
```

### Script Categories

| Category | Scripts | Description |
|----------|---------|-------------|
| **Static Checks** | `static_check*.csh`, `run_*.csh` | CDC/RDC, lint, SPG_DFT, build_rtl checks |
| **P4/Version Control** | `sync_tree.csh`, `check_cl.csh`, `submit_*.csh` | Perforce operations |
| **Waivers/Updates** | `update_cdc.csh`, `update_lint.csh`, `update_spg_dft.csh` | Add/update waivers and constraints |
| **TileBuilder** | `tb_branch.csh`, `*supra_regression*.csh` | TileBuilder branching and regression |
| **Timing/Reports** | `synthesis_timing.csh`, `report_utilization.csh` | Timing and area reports |
| **Params/Tune** | `update_params*.csh`, `update_tune*.csh`, `add_command_to_tune.csh` | Parameter management |
| **Monitoring** | `check_status_supra_regression.csh`, `list_tilebuilder_dir.csh` | Run monitoring |
| **Notifications** | `send_*_notification.csh` | Email notifications |

### Project-Specific Scripts

The agent supports multiple projects with project-specific script directories:

| Project | Directory | IP Prefix | Codeline | Description |
|---------|-----------|-----------|----------|-------------|
| **UMC** | `script/rtg_oss_feint/umc/` | `umc*` | `umc_ip` | UMC project (umc9_2, umc9_3, umc17_0) |
| **OSS** | `script/rtg_oss_feint/oss/` | `oss*` | `oss_ip` | OSS project (oss7_2, oss8_0) - includes Arcadia variants |
| **GMC** | `script/rtg_oss_feint/gmc/` | `gmc*` | `umc4` | GMC project (gmc13_1a) - Orion |

The `static_check_unified.csh` and `sync_tree_unified.csh` scripts automatically detect the project type based on IP prefix and route to the appropriate project-specific scripts.

#### GMC Project Specifics

GMC has some unique characteristics compared to UMC/OSS:

| Feature | GMC | UMC/OSS |
|---------|-----|---------|
| **Codeline** | `umc4` | `umc_ip` / `oss_ip` |
| **Bootenv** | `bootenv -v gmc13_1a` | `bootenv -x <ip>` |
| **Tiles** | Both tiles run automatically via `DROP_TOPS` | Single tile per run |
| **SPG_DFT Output** | Single `gmc_w_phy` | Per-tile output |
| **Full Static Check** | Sequential (Lint → CDC/RDC → SPG_DFT) | Sequential |

**GMC Tiles:**
- `gmc_gmcctrl_t` - GMC Controller Tile
- `gmc_gmcch_t` - GMC Channel Tile

**Note:** GMC commands automatically run both tiles via `DROP_TOPS="gmc_gmcctrl_t+gmc_gmcch_t"`, so no tile specification is needed.

---

### Argument Variable Reference

When scripts are called, these variables are substituted:

| Variable | Source | Description |
|----------|--------|-------------|
| `$refDir` | Path detection | Reference/tree directory |
| `$ip` | arguement.csv | Project/IP code (e.g., `umc9_3`) |
| `$tile` | arguement.csv | Tile name |
| `$target` | arguement.csv | TileBuilder target |
| `$tag` | Auto-generated | Unique timestamp tag |
| `$checkType` | Keyword match | `cdc_rdc`, `lint`, `spg_dft`, etc. |
| `$updateType` | Keyword match | `waiver`, `constraint`, `config` |
| `$params` | Parsed params | Parameter specifications |
| `$tune` | Parsed tune | Tune file path |
| `$integer` | Numeric detection | Integer values |
| `$p4File` | P4 path detection | Perforce file paths |
| `$noLsf` | CLI mode flag | Skip LSF submission |

---

### Pattern Detection in genie_cli.py

The CLI automatically detects and extracts special patterns from instructions:

#### Directory & Path Detection

| Pattern | Detection Method | Example |
|---------|------------------|---------|
| `refDir` | `os.path.isdir()` check | `/proj/rtg_oss_er_feint1/abinbaba/tree_dir` |
| `tune` | Starts with `tune/` | `tune/FxPlace/opt.tcl` |
| `p4File` | Starts with `//depot/` | `//depot/umc_ip/branches/UMC_14_2_WHLP_BRANCH` |

**Note:** `refDir` only extracts paths that actually exist as directories on the filesystem.

#### Numeric & Date Patterns

| Pattern | Regex | Example | Use Case |
|---------|-------|---------|----------|
| `integer` | `^[0-9]+$` | `12345678` | Changelist numbers |
| `digit` | `^[0-9]+\.[0-9]+$` | `1.5`, `2.0` | Decimal values |
| `date` | `^\d{4}-\d{2}-\d{2}$` | `2026-02-22` | Date specifications |
| `mem` | `^[0-9]+x[0-9]+$` | `64x32` | Memory dimensions |
| `regu` | `\S*\*\S*` | `*pattern*` | Wildcard patterns |

#### P4 Branch Auto-Detection

When syncing a new tree, the CLI can auto-detect the branch from a P4 depot path:

```bash
# Branch is extracted from //depot/umc_ip/branches/<BRANCH_NAME>/...
python3 script/genie_cli.py -i "sync up new tree for umc9_3 from branch //depot/umc_ip/branches/UMC_14_2_WHLP_BRANCH" --execute

# With changelist
python3 script/genie_cli.py -i "sync up new tree for umc9_3 from branch //depot/umc_ip/branches/UMC_14_2_WHLP_BRANCH at changelist 12345678" --execute
```

The `sync_tree.csh` script extracts the branch using:
```tcsh
set branch_name = `echo $p4file_name | grep -o 'branches/[^/]*' | sed 's/branches\///'`
```

#### Special Content Patterns

These patterns are detected and written to data files for script consumption:

| Pattern Type | Regex/Detection | Data File | Example |
|--------------|-----------------|-----------|---------|
| `config` | `[A-Z][A-Z0-9_]+:\s+\S+` | `data/<tag>.cdc_rdc_config` | `ENABLE_TECHIND_CDCFEPM: 1` |
| `waiver` | `(cdc\|resetcheck) report (crossing\|item)...` | `data/<tag>.cdc_rdc_waiver` | `cdc report crossing ...` |
| `constraint` | `netlist (clock\|constant\|port\|...)...` | `data/<tag>.cdc_rdc_constraint` | `netlist clock clk_main` |
| `lint_waiver` | `(error\|filename\|code\|msg):...` | `data/<tag>.lint_waiver` | `error: LINT-123` |
| `version` | `(CDC_Verif\|0in)/[\d._]+` | `data/<tag>.cdc_rdc_version` | `CDC_Verif/2023.12` |
| `spg_dft_params` | `SPGDFT_[A-Z0-9_]+...` | `data/<tag>.spg_dft_params` | `SPGDFT_CLOCK_DOMAIN = main` |
| `p4_file` | `(src\|_env)/\S+` | `data/<tag>.p4_files` | `src/meta/tools/cdc.yml` |
| `p4_description` | `Description:\s*(.+)` | `data/<tag>.p4_description` | `Description: Update config` |
| `params` | `PARAM = VALUE` (from arguement.csv) | `data/<tag>.params` | `NICKNAME = test_run` |

#### Params Block Format (`<: ... :>`)

For passing multiple parameters, use the `<: ... :>` block syntax:

```
with params <: PARAM1 = value1
PARAM2 = value2
PARAM3 = value3 :>
```

**Key Points:**
- Opening `<:` marks the start of params block
- Closing `:>` marks the end of params block
- Each param on a new line in format `PARAM = value`
- Params must be defined in `arguement.csv` with type `params`
- The closing `:>` is automatically stripped from the last param value

**Common Params (from arguement.csv):**
| Param | Type | Description |
|-------|------|-------------|
| `NICKNAME` | params | Custom run name suffix |
| `SYN_VF_FILE` | params | RTL verilog filelist path |
| `TILES_TO_RUN` | params | Override tile to run |
| `DSO_USE` | params | Enable/disable DSO |
| `PROJECT` | params | Project name override |

#### Usage Examples

```bash
# CDC config update - config pattern detected
python3 genie_cli.py -i "update cdc_rdc config for umc9_3 at /proj/xxx ENABLE_TECHIND_CDCFEPM: 1" --execute

# CDC version update - version pattern detected
python3 genie_cli.py -i "update cdc_rdc version for umc9_3 at /proj/xxx CDC_Verif/2023.12" --execute

# Add command to tune - tune path detected
python3 genie_cli.py -i "add command to tune/FxPlace/opt.tcl at /proj/xxx" --execute

# Submit P4 files - p4_file and description patterns detected
python3 genie_cli.py -i "submit files at /proj/xxx src/meta/cdc.yml src/rtl/module.v Description: Update CDC" --execute

# SPG_DFT params update - spg_dft_params pattern detected
python3 genie_cli.py -i "update spg_dft parameters for umc9_3 at /proj/xxx SPGDFT_CLOCK_DOMAIN = main" --execute
```

---

### Email Flow - Original Method (vtoHybridModel.py)

The **original method** for using the agent is via email. Located in `mail_centre/`:

**How it works:**
1. **User sends email to VTO** - Instructions written in natural language
2. **Read tasksMail.csv** - Emails fetched from communication interface
3. **Filter by VTO name** - Only process emails addressed to configured VTOs
4. **Parse mail body** - Extract instructions sentence by sentence
5. **Encode and match** - One-hot encode, match to instructions
6. **Extract arguments** - Parse directories, tiles, params, etc.
7. **Execute scripts** - Same scripts as CLI flow
8. **Send email reply** - Results sent back to sender

**Special Handlers:**
- Params/controls extraction from `<: ... :>` blocks
- Tune file detection from `tune/...` paths
- P4 file detection from `//...` patterns
- Waiver/constraint parsing from pattern matches

**When to use Email Flow:**
- When working remotely without Claude Code access
- For automated/scheduled task submissions
- When you prefer email-based communication

---

### CLI Flow - Alternative Method (genie_cli.py)

The **alternative method** that bypasses email entirely. Located in `main_agent/`:

**Why it was created:**
- Faster execution (no email round-trip)
- Direct integration with Claude Code
- Real-time feedback and monitoring
- Easier debugging and iteration

Direct interface for Claude Code integration:

```bash
# Basic usage (dry run - shows command without executing)
python3 genie_cli.py -i "run lint at /proj/xxx for umc9_3"

# Execute the task in background
python3 genie_cli.py -i "run lint at /proj/xxx for umc9_3" --execute

# Execute with email notification on completion
python3 genie_cli.py -i "run lint at /proj/xxx for umc9_3" --execute --email

# List available instructions
python3 genie_cli.py --list

# Check task status
python3 genie_cli.py --status <tag>

# Kill a running task
python3 genie_cli.py --kill <tag>
```

**CLI Options:**

| Option | Short | Description |
|--------|-------|-------------|
| `--help` | `-h` | Show help message and exit |
| `--instruction` | `-i` | The instruction to parse and execute |
| `--execute` | `-e` | Actually execute the command (default is dry-run) |
| `--xterm` | `-x` | Run task in xterm popup window (interactive mode) |
| `--email` | `-m` | Send results to debugger emails from assignment.csv |
| `--to EMAIL` | | Override email recipients (comma-separated). Use with `--email` |
| `--list` | `-l` | List all available instructions |
| `--base-dir` | `-b` | Base directory for the agent (default: auto-detect) |
| `--status` | `-s` | Check status of a task by tag |
| `--tasks` | `-t` | List tasks: `running`, `today`, `yesterday`, or `YYYY-MM-DD` |
| `--kill` | `-k` | Kill a running background task by tag |
| `--send-completion-email` | | Internal: Send completion email for a finished task |
| `--setup-user` | | Setup user-specific directory for multi-user environment |
| `--user-email EMAIL` | | Email address for `--setup-user` (required, or will prompt) |
| `--user-disk PATH` | | Disk path for `--setup-user` (required, or will prompt) |
| `--analyze` | `-a` | Claude Code monitors task and analyzes results (static checks only) |

**What is Dry-Run?**

Dry-run is the **default mode** when you don't use `--execute`. It parses your instruction and shows:
- **Input**: Your instruction
- **Matched**: Which instruction pattern it matched to
- **Script**: Which script will be called
- **Command**: The full command that would be executed
- **Extracted Arguments**: All parsed arguments (refDir, ip, checkType, etc.)

But it does **NOT actually run anything**. Use cases:
- Verify your instruction is parsed correctly before running
- Check which script will be called
- See what arguments were extracted
- Debug issues with instruction matching

---

### Execution Modes

The CLI supports three execution modes:

#### 1. Dry Run (Default)
Shows what would be executed without actually running:
```bash
python3 genie_cli.py -i "report timing and area for /proj/xxx/tile_dir"
```

#### 2. Background Execution (`--execute`)
Runs the task in the background, freeing the terminal:
```bash
python3 genie_cli.py -i "run lint at /proj/xxx for umc9_3" --execute --email
```
- Task runs in a detached process
- Output is written to `runs/<tag>.log`
- PID saved to `data/<tag>_pid` for later killing
- Email sent on completion (if `--email` flag used)

#### 3. Xterm Popup Mode (`--xterm`)
Runs the task in a visible xterm window for real-time monitoring:
```bash
python3 genie_cli.py -i "report timing and area for /proj/xxx/tile_dir" --execute --xterm --email
```
- Opens an xterm window showing live output
- Uses `script` command to capture output to log file
- Window closes automatically when task completes
- Email sent on completion (if `--email` flag used)
- Useful for monitoring long-running tasks visually

**Xterm Mode Examples:**
```bash
# Timing report with xterm popup and email
python3 genie_cli.py -i "report timing and area for /proj/xxx/tile_dir" --execute --xterm --email

# Full static check in xterm (auto-creates workspace if no directory specified)
python3 genie_cli.py -i "run full_static_check for umc9_3" --execute --xterm --email

# Monitor supra run in xterm
python3 genie_cli.py -i "monitor supra run at /proj/xxx/tile_dir for target FxSynthesize" --execute --xterm
```

**Xterm vs Background vs Analyze Comparison:**

| Feature | Background (`--execute`) | Xterm (`--execute --xterm`) | Analyze (`--execute --analyze`) |
|---------|--------------------------|----------------------------|--------------------------------|
| Terminal | Frees terminal immediately | Opens popup window | Frees terminal, Claude monitors |
| Output | Hidden (check log file) | Visible in real-time | Claude reads and analyzes |
| Monitoring | Check `runs/<tag>.log` | Watch xterm window | Automatic by Claude Code |
| Email | Sent on completion | Sent on completion | Sent with analysis |
| Use Case | Set and forget | Visual monitoring | Automated violation analysis |

---

### Analyze Mode (`--analyze`) - Agent Teams Architecture

The `--analyze` flag enables **Claude Code to monitor and analyze static check results** using a specialized **Agent Teams architecture**. This provides intelligent violation analysis with minimal context usage.

**Supported Check Types:**
- `cdc_rdc` - CDC/RDC reports (analyzes BOTH cdc_report.rpt AND rdc_report.rpt)
- `lint` - Lint reports
- `spg_dft` - SpyGlass DFT reports
- `full_static_check` - All of the above

**Usage:**
```bash
# Run CDC/RDC with analyze mode
python3 script/genie_cli.py -i "run cdc_rdc at /proj/xxx for umc9_3" --execute --analyze --email

# Run full static check with analyze mode in xterm
python3 script/genie_cli.py -i "run full_static_check for umc17_0" --execute --xterm --analyze --email
```

**How It Works:**
1. **Task Execution**: genie_cli.py launches the static check in background
2. **Signal Detection**: Prints `ANALYZE_MODE_ENABLED` with task metadata
3. **Background Monitoring**: Claude spawns ONE background agent to monitor log file for completion
4. **Live Analysis**: Upon completion, Claude runs analysis LIVE (not background) using Agent Teams
5. **HTML Report**: Compiles all results into beautiful HTML report (`data/<tag>_analysis.html`)
6. **Email Results**: Full HTML analysis sent to debuggers - ALL details in email, NOT conversation

**Agent Teams Architecture:**

The analysis uses specialized agents organized by check type:

```
config/analyze_agents/
├── ORCHESTRATOR.md              # Main orchestration guide
├── cdc_rdc/                     # CDC/RDC specific agents
│   ├── precondition_agent.md    # Check inferred clks/rsts, unresolved modules
│   ├── violation_extractor.md   # Parse CDC Section 3 + RDC Section 5
│   └── rtl_analyzer.md          # Analyze CDC crossings in RTL
├── lint/                        # Lint specific agents
│   ├── violation_extractor.md   # Parse unwaived violations
│   └── rtl_analyzer.md          # Analyze undriven ports, etc.
├── spgdft/                      # SpgDFT specific agents
│   ├── precondition_agent.md    # Check blackbox modules
│   ├── violation_extractor.md   # Parse DFT violations
│   └── rtl_analyzer.md          # Analyze TDR ports, etc.
└── shared/                      # Shared agents
    ├── library_finder.md        # Find missing libraries from lib.list
    └── report_compiler.md       # Generate HTML report
```

**Agent Invocation by Check Type:**

| check_type | Agents Invoked | NOT Invoked |
|------------|----------------|-------------|
| `cdc_rdc` | CDC/RDC Precondition, CDC/RDC Violation Extractor, CDC/RDC RTL Analyzers | Lint, SpgDFT |
| `lint` | Lint Violation Extractor, Lint RTL Analyzers | CDC/RDC, SpgDFT |
| `spg_dft` | SpgDFT Precondition, SpgDFT Violation Extractor, SpgDFT RTL Analyzers | CDC/RDC, Lint |
| `full_static_check` | ALL agents from all three flows | - |

**IP Configuration (Faster Path Resolution):**

The agents use `config/IP_CONFIG.yaml` for fast report path discovery:
- **UMC** (`umc9_3`, `umc17_0`, etc.): Default tile `umc_top`
- **OSS** (`oss7_2`, `oss8_0`, etc.): Default tile `osssys`
- **GMC** (`gmc13_1a`, etc.): Default tile varies

**Library Finder - Dynamic Discovery:**

For blackbox modules, the Library Finder searches lib.list files (NOT hardcoded paths):
1. **Priority 1**: `<ref_dir>/out/linux_*/*/config/*/pub/sim/publish/tiles/tile/{tile}/publish_rtl/manifest/{tile}_lib.list`
2. **Priority 2**: `<ref_dir>/src/meta/tools/spgdft/variant/{ip}/project.params`
3. **Priority 3**: `<ref_dir>/src/meta/tools/cdc0in/variant/{ip}/{tile}_lib.list`

**LOW_RISK Patterns (Filtered Out):**
- `rsmu`, `RSMU` - Reset Scan MUX
- `rdft`, `RDFT` - DFT related
- `dft_`, `DFT_` - DFT prefix
- `jtag`, `JTAG` - JTAG debug
- `scan_`, `SCAN_` - Scan chain
- `bist_`, `BIST_` - Built-in self test
- `test_mode`, `TEST_MODE` - Test mode
- `sms_fuse` - Fuse signals
- `tdr_`, `TDR_` - Test Data Register

**Output Flow:**

| Content | Email | Conversation |
|---------|-------|--------------|
| Precondition summary table | YES | NO |
| Violation counts and types | YES | NO |
| RTL analysis details | YES | NO |
| Recommendations & code snippets | YES | NO |
| "Analysis complete. Email sent." | YES | YES |

**Reference:** See `config/analyze_agents/ORCHESTRATOR.md` for detailed orchestration guide.

---

**Task Management:**

When a task is executed with `--execute`:
1. A unique tag (timestamp) is generated: `YYYYMMDDHHMMSS`
2. The process PID is saved to `data/<tag>_pid`
3. Logs are written to `runs/<tag>.log`
4. Task spec saved to `data/<tag>_spec`
5. Main script runs in a subshell to ensure email is sent even on failure

**Retrieving Task Output (IMPORTANT):**

After executing a task, **always check the `data/<tag>_spec` file** for the actual output/results:

```bash
cat data/<tag>_spec
```

The `_spec` file contains the formatted results from the task execution. The log file (`runs/<tag>.log`) shows script execution details but the actual output is written to `data/<tag>_spec`.

Example workflow:
1. Execute: `python3 genie_cli.py -i "check changelist number for /proj/xxx" --execute`
2. Note the tag from output (e.g., `20260210014814`)
3. Wait briefly for execution to complete
4. Read results: `cat data/20260210014814_spec`

**Email Notification:**
- When `--email` flag is used, email flag file is created: `data/<tag>_email`
- Email is sent on task completion (success OR failure)
- Main script runs in subshell so parent script continues even if task fails
- Email includes task results from `data/<tag>_spec`
- Sent to all debuggers from `assignment.csv` (first as To, rest as CC)
- Use `--to user@amd.com` to override recipients (for testing)

**Email Subject Format:**
```
[Status] TASK_TYPE - tile @ directory (tag)
```

Examples:
- `[Success] STATIC_CHECK_SUMMARY @ umc_rosenhorn_Feb9082038 (20260210223845)`
- `[Failed] CDC_RDC @ oss_tree_Jan15 (20260210002012)`
- `[Success] FXSYNTHESIZE - umcdat @ umcdat_Feb10152424 (20260210152424)`
- `[Completed] BRANCH @ umc_rosenhorn_Feb9082038 (20260210002012)`

Status is auto-detected from task output:
- `[Success]` - Task completed with success indicators
- `[Failed]` - Task completed with error indicators
- `[Completed]` - Task completed (status unclear)

**Killing Tasks:**
- Uses saved PID to kill the entire process group (including child processes)
- Automatically removes PID file and email flag file
- Falls back to grep-based process search if PID file missing

**Generated Run Script Structure:**
```tcsh
#!/bin/tcsh -f
cd /path/to/main_agent
# For TileBuilder commands:
source /tool/aticad/1.0/src/sysadmin/cpd.cshrc
# For non-TileBuilder commands:
# source csh/env.csh
set tag = <tag>
set tasksModelFile = tasksModelCLI.csv

# Execute main script in subshell (continues even on failure)
( source script/rtg_oss_feint/... )
set script_status = $status
echo 'Script exit status:' $script_status

# Always send email (even on failure)
if (-f data/<tag>_email) then
    python3 genie_cli.py --send-completion-email <tag>
endif
```

**Note:** The script uses `tcsh` (not `csh`) for compatibility with TileBuilder's `cpd.cshrc` which uses tcsh-specific syntax. The main script runs in a `( )` subshell to catch any exit calls and ensure email is always sent.

**Key Methods:**
- `encode_instruction()` - One-hot encode user input
- `find_best_match()` - Match against instruction patterns
- `build_command()` - Substitute variables into script command
- `run_and_capture()` - Execute inline or generate run script
- `send_email()` - Send HTML-formatted results

---

### Inline Params Support

The CLI supports inline `PARAM = VALUE` syntax for TileBuilder commands:

```bash
# Run supra regression with custom params
python3 genie_cli.py -i "run supra regression for umcdat for target FxSynthesize \
  at /proj/xxx/tiles \
  with NICKNAME = my_run_name \
  and SYN_VF_FILE = /proj/xxx/umc_top.vf" --execute
```

**How it works:**
1. Parser detects `PARAM = VALUE` patterns separated by `with` or `and`
2. Params are validated against `arguement.csv` (must be type `params`)
3. Params are written to `data/<tag>.params`
4. Script merges params into `override.params` in tile directory

**Supported separators:**
- `with PARAM = value` - starts param list
- `and PARAM = value` - continues param list
- Newlines and commas also work as separators

---

### TileBuilder Environment

TileBuilder commands require a special environment that conflicts with cbwa modules.

**Problem:** The cbwa environment (`cbwa_init.csh`) and TileBuilder environment are mutually exclusive. Loading both causes module conflicts.

**Solution:** TileBuilder scripts use `lsf_tilebuilder.csh` instead of `lsf.csh`:

| File | Description |
|------|-------------|
| `lsf.csh` | Standard LSF + cbwa_init.csh (for static checks, etc.) |
| `lsf_tilebuilder.csh` | LSF only, NO cbwa_init.csh (for TileBuilder) |

**Scripts using `lsf_tilebuilder.csh`:**
- `make_tilebuilder_run.csh`
- `monitor_tilebuilder.csh`
- `extract_utilization.csh`

**CLI Environment Handling:**

For TileBuilder commands, `genie_cli.py` uses:
1. `env -i` to start with clean environment (no inherited cbwa modules)
2. `tcsh -f` to skip `.cshrc` (which may source cbwa) - **Note: uses tcsh, not csh, for cpd.cshrc compatibility**
3. Passes `DISPLAY` for X11 (required by TileBuilderTerm)
4. Sources `cpd.cshrc` instead of `env.csh`

For xterm mode:
1. Makes run script executable (`chmod 755`)
2. Uses `script -c 'tcsh -f <run_script>'` to capture output
3. xterm window closes automatically on completion

---

### Task Management

**PID Tracking:**

Each background task saves its PID for management:
- PID file: `data/<tag>_pid`
- Kill command: `python3 genie_cli.py --kill <tag>`
- Status check: `python3 genie_cli.py --status <tag>`

**Example:**
```bash
# Start a task
python3 genie_cli.py -i "run supra regression ..." --execute
# Output: Tag: 20260210022423, PID: 1812546

# Check PID
cat data/20260210022423_pid
# Output: 1812546

# Kill if needed
python3 genie_cli.py --kill 20260210022423
```

---

### Data Directory Structure

```
data/
├── <tag>/                    # Per-task data directory
│   ├── <tag>.log             # Execution log
│   ├── <tag>.csh             # Generated CSH commands
│   ├── <tag>.tcl             # Generated TCL commands
│   ├── subject.info          # Email subject
│   ├── runDir.list           # Run directories
│   └── tune/                 # Extracted tune files
├── <tag>.params              # Extracted parameters
├── <tag>.table               # Extracted tables
├── <tag>.controls            # Extracted controls
├── <tag>.cdc_rdc_waiver      # CDC/RDC waivers
├── <tag>.cdc_rdc_constraint  # CDC/RDC constraints
├── <tag>.lint_waiver         # Lint waivers
├── <tag>_pid                 # Process ID for killing tasks
├── <tag>_email               # Email flag file (triggers email on completion)
├── <tag>_spec                # Task specification
└── jira/                     # JIRA integration data
    ├── edatool.list          # Tool version updates
    ├── params.<date>.list    # Daily params updates
    └── p4.<date>.list        # P4 file submissions
```

---

### Extending the Agent

#### Adding a New Instruction

1. **Add keyword** to `keyword.csv` if needed:
   ```csv
   newaction,synonym1,synonym2
   ```

2. **Add instruction** to `instruction.csv`:
   ```csv
   could you newaction at following directory,rtg_oss_feint/new_script.csh $refDir $ip $tag,xxx,start run
   ```

3. **Create script** in `script/rtg_oss_feint/`:
   ```bash
   #!/bin/csh -f
   # new_script.csh
   set refDir = $1
   set ip = $2
   set tag = $3
   # ... implementation
   ```

#### Adding a New Argument Type

1. **Add to arguement.csv**:
   ```csv
   myarg,newtype
   ```

2. **Add pattern** to `patterns.csv` if complex regex needed:
   ```csv
   ^MY_.*,mypattern,I
   ```

---

### RHEL Version Detection

The agent automatically detects RHEL version for LSF resource selection. This is critical because builds must run on the correct RHEL version.

**Detection Script:** `script/rtg_oss_feint/get_rhel_version.csh`

```tcsh
#!/bin/tcsh
# Get RHEL version from kernel string
set kernel_str = `uname -r`
set rhel_ver = `echo $kernel_str | grep -oE 'el[0-9]+'`

if ("$rhel_ver" == "el8") then
    set RHEL_TYPE = "RHEL8_64"
else if ("$rhel_ver" == "el7") then
    set RHEL_TYPE = "RHEL7_64"
else
    set RHEL_TYPE = "RHEL8_64"  # Default
endif
```

**Usage in command scripts:**
```tcsh
source $source_dir/script/rtg_oss_feint/get_rhel_version.csh
lsf_bsub -R "select[type==${RHEL_TYPE}] rusage[mem=50000]" ...
```

**RHEL Version Mapping:**

| Kernel Pattern | RHEL Version | LSF Type | Output Directory |
|----------------|--------------|----------|------------------|
| `el7` in `uname -r` | RHEL 7 | `RHEL7_64` | `out/linux_3.10.0_64.VCS/` |
| `el8` in `uname -r` | RHEL 8 | `RHEL8_64` | `out/linux_4.18.0_64.VCS/` |

---

### Dual RHEL Path Handling

When both RHEL7 and RHEL8 output directories exist (e.g., after running checks on different systems), the analysis scripts automatically select the **most recent** results.

**Problem:** Both paths may exist:
- `out/linux_3.10.0_64.VCS/...` (RHEL7 - older)
- `out/linux_4.18.0_64.VCS/...` (RHEL8 - newer)

**Solution:** Use wildcard `linux_*.VCS` with time-based sorting:

```tcsh
# For ls-based file discovery (newest first)
set report = `ls -t out/linux_*.VCS/.../report.rpt | grep $tile | head -1`

# For find-based file discovery (newest first)
set file = `find $dir -name "file.log" -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2`
```

**How it works:**

| Command | Purpose |
|---------|---------|
| `ls -t` | Sort files by modification time (newest first) |
| `head -1` | Take only the first (newest) result |
| `-printf '%T@ %p\n'` | Print timestamp + path for find |
| `sort -rn` | Sort numerically in reverse (newest first) |
| `cut -d' ' -f2` | Extract just the path (remove timestamp) |

**Example:**
```bash
# Both exist:
# linux_3.10.0_64.VCS/.../leda_waiver.log (Feb 15)
# linux_4.18.0_64.VCS/.../leda_waiver.log (Feb 18)

ls -t out/linux_*.VCS/.../leda_waiver.log | head -1
# Returns: linux_4.18.0_64.VCS/.../leda_waiver.log (newest)
```

**Updated Scripts:**
- `umc/static_check_analysis.csh` - CDC/RDC, Lint, SPG_DFT report extraction
- `oss/static_check_analysis.csh` - Same for OSS project
- `umc/update_lint.csh` - Lint log discovery
- `oss/update_lint.csh` - Same for OSS project
- `umc/command/run_spg_dft.csh` - Dynamic output directory detection

---

### Auto-Workspace Creation (Static Checks)

For static checks (CDC/RDC, Lint, SPG_DFT, full_static_check), if no directory is specified, the system automatically:

1. Creates a new workspace directory using disk path from `assignment.csv`
2. Runs `p4_mkwa` to sync the codebase based on IP:
   - `umc9_3` → Default UMC trunk
   - `umc9_2` → `UMC_9_2_WEISSHORN_TRUNK` branch
3. Verifies sync success (checks `P4_MKWA.log` and `configuration_id`)
4. Runs the requested static checks

**Example:**
```bash
# Auto-creates workspace and runs all static checks
python3 genie_cli.py -i "run full_static_check for umc9_3" --execute --xterm --email

# Auto-creates workspace for specific check
python3 genie_cli.py -i "run cdc_rdc for umc9_3" --execute --email
```

**Workspace naming:** `umc_<project>_<timestamp>` (e.g., `umc_rosenhorn_Feb15203045`)

---

### Monitor Task Runtime Limits

The `monitor supra run` command has built-in runtime limits to prevent issues with xterm/DISPLAY expiration:

| Limit | Duration | Behavior |
|-------|----------|----------|
| **Session Timeout** | 23 hours (82,800s) | Attempts to relaunch in new xterm session |
| **Max Total Runtime** | 60 hours (216,000s / 2.5 days) | Gracefully exits and sends email with current status |

**Why the 2.5-day limit?**
- xterm sessions and DISPLAY connections typically expire after ~3 days
- Session relaunch may fail if DISPLAY becomes invalid
- Graceful exit ensures email notification is sent

**When max runtime is reached:**
1. Monitoring stops gracefully
2. Email is sent with current status (`STILL_RUNNING`)
3. Email includes instructions to:
   - Check status manually: `cd <dir> && TileBuilderTerm -x TileBuilderShow`
   - Restart monitoring: `python3 genie_cli.py -i "monitor supra run at <dir> for target <target>" --execute --xterm --email`

**Customizing the limit:**
Edit `script/rtg_oss_feint/supra/monitor_tilebuilder.csh`:
```tcsh
set max_total_runtime = 216000  # 2.5 days in seconds
```

---

### SpyGlass SaveRestoreDB Cleanup

SpyGlass DFT creates large `.SG_SaveRestoreDB` directories (often 50-150GB each) that are not needed after analysis. The agent automatically cleans these up after SPG_DFT analysis.

**Location:** `static_check_analysis.csh` (spg_dft section)

**How it works:**
```tcsh
# Find all .SG_SaveRestoreDB directories recursively
set sg_tmpfile = /tmp/sg_cleanup_$$.txt
find "$refdir_name" -name ".SG_SaveRestoreDB" -type d > $sg_tmpfile

# Remove each directory and report size freed
foreach sg_dir (`cat $sg_tmpfile`)
    set sg_size = `du -sh "$sg_dir" | awk '{print $1}'`
    echo "  Removing: $sg_dir ($sg_size)"
    rm -rf "$sg_dir"
end
```

**Typical space savings:** 100-300GB per static check run

**Manual cleanup script:** `script/rtg_oss_feint/test_sg_cleanup.csh`
```bash
# Dry-run (show what would be deleted)
tcsh script/rtg_oss_feint/test_sg_cleanup.csh /proj/xxx/tree_dir

# Actually delete
tcsh script/rtg_oss_feint/test_sg_cleanup.csh /proj/xxx/tree_dir --delete
```

---

### Timing Report Features

The timing and area report (`synthesis_timing.csh`) extracts:

| Section | Description |
|---------|-------------|
| **Summary Metrics** | WNS, TNS, NVP, StdCell Area, RAM Area, ULVTLL%, TotalCells |
| **Primary Timing Groups** | R2R path groups (case-insensitive matching) |
| **Other Path Groups** | I2R, R2O, I2C, C2O, clock_gating, etc. |
| **Vt Cell Usage** | UltraLow_Vt_LL, UltraLow_Vt, Low_Vt_LL, Low_Vt breakdown |
| **Pass Progression** | Multi-pass optimization tracking (Pass_1, Pass_2, Pass_3) |
| **LOL Report** | List of Lists (flop2flop timing violations ≥27 levels) |

**Auto-detection:**
- Synthesize target: `FxSynthesize` (UMC) or `FxPixSynthesize` (OSS)
- Pass Progression: Only shown if pass files exist
- Vt data: Falls back to JSON if multi_vt report unavailable

---

### Formality Report Features

The formality report (`report_formality.csh`) extracts Formality (FM) verification results from TileBuilder runs:

**Usage:**
```bash
# Report formality for a tile at a TileBuilder directory
python3 genie_cli.py -i "report formality for umccmd at /proj/xxx/tiles/umccmd_Jan26" --execute --xterm --email
```

**What it extracts:**

| Section | Description |
|---------|-------------|
| **Overall Status** | PASS/FAIL based on LEC result and failing points |
| **LEC Result** | SUCCEEDED/FAILED from `.dat` file |
| **Equivalent Points** | Number of matched compare points |
| **Non-Equivalent Points** | Number of mismatched compare points |
| **Failing Points** | Count and report path (CLEAN if 0) |
| **Unmatched Points** | Reference and Implementation unmatched counts |
| **Blackbox Summary** | Tech macros, interface-only, user set, unresolved |

**Compare Point Types:**
- `DFF` - D Flip-Flop
- `LATCG` - Latch Clock Gate

**Blackbox Types:**
- `m` - Technology Macro (.db)
- `i` - Interface-only
- `s` - User set_black_box
- `u` - Unresolved
- `e` - Empty module
- `cp` - Cutpoint blackbox

**FM Status Handling:**
| TileBuilder Status | Action |
|-------------------|--------|
| `NOTRUN` | Starts FM target and monitors |
| `RUNNING` | Monitors every 15 min (max 3 hours) |
| `PASSED` / `WARNING` | Extracts reports |
| `FAILED` | Reports failure with log path |

**Script:** `script/rtg_oss_feint/supra/report_formality.csh`

---

## Clock/Reset Structure Analyzer

Analyzes RTL clock and reset structures from a .vf file, generating comprehensive reports with hierarchical port tracing.

### Usage

```bash
# Analyze clock/reset structure at a tree directory
python3 script/genie_cli.py -i "analyze clock reset structure at /proj/xxx/tree_dir for umc17_0" --execute --email

# Or run the analyzer directly
python3 script/rtg_oss_feint/clock_reset_analyzer.py <vf_file> --top <top_module> --output <report.rpt> --html <report.html> --dot <prefix>
```

### What it Does

1. **Parses .vf file** to find all RTL source files
2. **Identifies primary clocks** (UCLKin0, DFICLKin0, Cpl_REFCLK, etc.)
3. **Identifies primary resets** (Cpl_PWROK, Cpl_RESETn, etc.)
4. **Traces signal paths** through the design hierarchy with recursive port-name-following
5. **Detects clock gating cells** (ati_clock_gate, UMCCLKGATER)
6. **Detects CDC synchronizers** (techind_sync, UMCSYNC)
7. **Generates reports**:
   - Text report (`.rpt`)
   - HTML report (`.html`)
   - Clock structure diagram (`.dot` → `.png`)
   - Reset structure diagram (`.dot` → `.png`)

### Output Files

| File | Description |
|------|-------------|
| `clock_reset_report.rpt` | Text report with clock/reset hierarchy |
| `clock_reset_report.html` | HTML report for email |
| `clock_reset_clock.png` | Clock hierarchy diagram |
| `clock_reset_reset.png` | Reset hierarchy diagram |

### Hierarchical Port Tracing

The analyzer performs **recursive port-name-following tracing**. When a signal connects to a differently-named port (e.g., `UCLKin0` → `.UCLK`), the tracing continues inside the instantiated module using the new port name:

```
UCLKin0 (top input)
  └─→ umc0 (umc).UCLK
    └─→ umcdat (umcdat).UCLK
      └─→ I_CHGATER_UCLK_FuncCGCG (UMCCLKGATER).C [GATING]
        └─→ I_CLKGATER (ati_clock_gate).clk_src [GATING]
          └─→ d0nt_clkgate_cell (HDN6BLVT08_CKGTPLT_V7Y2_4).CLK
```

### DOT Diagram Legend

| Shape | Clock Diagram | Reset Diagram |
|-------|---------------|---------------|
| **Ellipse** | Primary Clock | Primary Reset |
| **Diamond** | Clock Gating Cell | Reset Gen/Control |
| **Hexagon** | CDC Synchronizer | CDC Synchronizer |
| **Octagon** | - | Sync Buffer |
| **Box** | Module Instance | Module Instance |

### Example Output

**Clock Diagram** shows:
- Primary clock inputs (ellipse, blue)
- Clock gating cells (diamond, green) - ati_clock_gate, UMCCLKGATER
- CDC synchronizers (hexagon, pink) - UMCSYNC, techind_sync
- Module instances with port connections

**Reset Diagram** shows:
- Primary reset inputs (ellipse, red)
- Reset generation modules (diamond, orange) - rsmu_rdft_instance, rsmu_cac_logger
- CDC synchronizers (hexagon, pink)
- Sync buffers (octagon, gold) - buf_asn

---

**Version:** 2.1
**Last Updated:** 2026-03-17

**Changelog:**
- v2.1: Enhanced `--analyze` mode with Agent Teams architecture - specialized agents per check type, IP_CONFIG.yaml for fast path resolution, dynamic library discovery from lib.list files, improved HTML report colors for visibility (see config/analyze_agents/ORCHESTRATOR.md)
- v2.0: Added `--analyze` mode - Claude Code monitors and analyzes static check results with priority-based approach
- v1.9: Removed `--agent-team` and `--self-debug` (script-based analysis not robust enough; MultiAgentOrchestrator disabled, backed up as genie_cli.py.bak)
- v1.8: Added `--user-disk` to `--setup-user` - disk path now required during first-time setup
- v1.7: Added GMC project support (gmc13_1a, Orion) - codeline umc4, bootenv -v, both tiles via DROP_TOPS
- v1.6: Added `--setup-user` for multi-user environment setup, detailed user directory structure
- v1.5: Added Clock/Reset Structure Analyzer with recursive port-name-following tracing
- v1.4: Added Formality Report (`report_formality.csh`) documentation, project name in email subject for static checks
- v1.3: Added RHEL version detection (`get_rhel_version.csh`), dual RHEL path handling (linux_*.VCS with `ls -t`), complete CLI options documentation, dry-run explanation
- v1.2: Added xterm mode (`--xterm`), auto-workspace creation, timing report features, tcsh compatibility fixes
- v1.1: Initial CLI documentation
