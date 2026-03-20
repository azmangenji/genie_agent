# run-static-check

Run static checks (CDC/RDC, Lint, SpgDFT) with automatic monitoring and Agent Teams analysis.

## Usage

```
/run-static-check <check_type> at <tree_path> for <ip>
```

### Examples
```
/run-static-check cdc_rdc at /proj/rtg_oss_er_feint1/abinbaba/umc_grimlock for umc17_0
/run-static-check lint at /proj/xxx for umc9_3
/run-static-check full_static_check at /proj/xxx for oss8_0
```

### Check Types
- `cdc_rdc` - CDC and RDC analysis (analyzes BOTH reports)
- `lint` - Lint check
- `spg_dft` - SpyGlass DFT check
- `full_static_check` - All checks (CDC, RDC, Lint, SpgDFT)

### Options
- `--xterm` - Run in visible xterm window
- `--email` - Send results to debuggers

## Agent Teams Architecture

When `--analyze` mode is used, the analysis uses specialized agents:

```
config/analyze_agents/
├── ORCHESTRATOR.md              # Main guide
├── cdc_rdc/                     # CDC/RDC agents
│   ├── precondition_agent.md    # Inferred clks/rsts, unresolved
│   ├── violation_extractor.md   # CDC Section 3 + RDC Section 5
│   └── rtl_analyzer.md          # CDC crossing analysis
├── lint/                        # Lint agents
│   ├── violation_extractor.md   # Unwaived violations
│   └── rtl_analyzer.md          # Undriven ports
├── spgdft/                      # SpgDFT agents
│   ├── precondition_agent.md    # Blackbox modules
│   ├── violation_extractor.md   # DFT violations
│   └── rtl_analyzer.md          # TDR ports
└── shared/                      # Shared agents
    ├── library_finder.md        # Find libraries from lib.list
    └── report_compiler.md       # HTML report generation
```

### Agent Invocation by Check Type

| check_type | Agents to Invoke |
|------------|------------------|
| `cdc_rdc` | CDC/RDC Precondition, Violation Extractor, RTL Analyzers |
| `lint` | Lint Violation Extractor, RTL Analyzers |
| `spg_dft` | SpgDFT Precondition, Violation Extractor, RTL Analyzers |
| `full_static_check` | ALL agents from all three flows |

## Workflow

When this skill is invoked, Claude will:

1. **Parse the instruction** and validate inputs
2. **Launch the check** via genie_cli.py with `--analyze --email`
3. **Spawn background monitoring agent** to watch for completion
4. **Wait for completion** (user can continue other conversations)
5. **Run live analysis** when done using Agent Teams:
   - Read `config/IP_CONFIG.yaml` for report paths
   - Check preconditions (inferred clks/rsts, blackboxes)
   - If blackboxes found, search lib.list for libraries
   - Extract violations, filter LOW_RISK (RSMU/DFT) patterns
   - Analyze top violations in RTL
6. **Compile HTML report** with all findings
7. **Send email** to debuggers (ALL details in email)
8. **Minimal conversation output**: Just "Analysis complete. Email sent."

## Instructions for Claude

<instructions>
When the user invokes this skill:

1. Extract parameters from the command:
   - check_type: cdc_rdc, lint, spg_dft, or full_static_check
   - tree_path: The /proj/... directory path
   - ip: The IP name (e.g., umc17_0, umc9_3, oss8_0)

2. Launch the static check with analyze mode:
   ```bash
   python3 script/genie_cli.py -i "run <check_type> at <tree_path> for <ip>" --execute --analyze --email
   ```
   Capture the tag from output.

3. Detect `ANALYZE_MODE_ENABLED` signal and spawn background monitoring agent:
   ```
   Task tool with run_in_background=true, model=haiku
   Prompt: Monitor log file <log_file> for completion.
           Look for "STATIC_CHECK_COMPLETE" or "Build completed" or errors.
           Return when task completes.
   ```

4. Tell the user:
   "Static check launched (tag: <tag>). Monitoring in background.
    You'll be notified when analysis is complete. Email will be sent to debuggers."

5. When monitoring agent returns, run LIVE analysis (not background):

   a. Read config/analyze_agents/ORCHESTRATOR.md for guidance

   b. Based on check_type, invoke ONLY the relevant agents:
      - cdc_rdc → CDC/RDC agents only
      - lint → Lint agents only
      - spg_dft → SpgDFT agents only
      - full_static_check → ALL agents

   c. Use config/IP_CONFIG.yaml to find report paths quickly

   d. For CDC/RDC, analyze BOTH cdc_report.rpt AND rdc_report.rpt

   e. If blackbox modules found:
      - Use Library Finder to search lib.list files
      - DO NOT use hardcoded library paths
      - Priority: manifest lib.list > spgdft params > cdc lib.list

   f. Filter LOW_RISK patterns:
      rsmu, rdft, dft_, jtag, scan_, bist_, test_mode, tdr_

6. Compile HTML report:
   - Use template from config/analyze_agents/shared/report_compiler.md
   - Include summary tables, violation cards, recommendations
   - Save to data/<tag>_analysis.html

7. Send email:
   - ALL analysis details go in email (tables, violations, recommendations)
   - Use sendmail: `(echo "Content-Type: text/html"; echo ""; cat data/<tag>_analysis.html) | /usr/sbin/sendmail -t`

8. Conversation output (minimal - save context):
   - Just say: "Analysis complete. Email sent to debuggers."
   - DO NOT display tables or full analysis in conversation
</instructions>

## LOW_RISK Patterns (Filtered)

These patterns are typically DFT-related and safe to skip:
- `rsmu`, `RSMU` - Reset Scan MUX
- `rdft`, `RDFT` - DFT related
- `dft_`, `DFT_` - DFT prefix
- `jtag`, `JTAG` - JTAG debug
- `scan_`, `SCAN_` - Scan chain
- `bist_`, `BIST_` - Built-in self test
- `test_mode`, `TEST_MODE` - Test mode
- `sms_fuse` - Fuse signals
- `tdr_`, `TDR_` - Test Data Register

## Reference

- Orchestration: `config/analyze_agents/ORCHESTRATOR.md`
- IP Config: `config/IP_CONFIG.yaml`
- HTML Template: `config/analyze_agents/shared/report_compiler.md`
