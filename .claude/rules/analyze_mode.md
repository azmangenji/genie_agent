---
paths:
  - "config/analyze_agents/**"
  - "data/*_analysis.html"
  - "data/*_analyze"
---

# Analyze Mode - Agent Teams Architecture

## Overview

The `--analyze` flag enables Claude Code to monitor and analyze static check results using specialized Agent Teams.

**Supported Check Types:**
- `cdc_rdc` - CDC/RDC reports (both cdc_report.rpt AND rdc_report.rpt)
- `lint` - Lint reports
- `spg_dft` - SpyGlass DFT reports
- `full_static_check` - All of the above

## How It Works

1. **Task Execution**: genie_cli.py launches static check in background
2. **Signal Detection**: Prints `ANALYZE_MODE_ENABLED` with metadata
3. **Background Monitoring**: Claude spawns ONE background agent to monitor completion
4. **Live Analysis**: Upon completion, runs analysis using Agent Teams
5. **HTML Report**: Compiles results into `data/<tag>_analysis.html`
6. **Email Results**: Full HTML analysis sent to debuggers

## Agent Teams Structure

```
config/analyze_agents/
├── ORCHESTRATOR.md              # Main orchestration guide
├── LEARNING.md                  # Past fixes knowledge base
├── cdc_rdc/
│   ├── precondition_agent.md    # Inferred clks/rsts, unresolved modules
│   ├── violation_extractor.md   # Parse CDC Section 3 + RDC Section 5
│   └── rtl_analyzer.md          # Analyze CDC crossings in RTL
├── lint/
│   ├── violation_extractor.md   # Parse unwaived violations
│   └── rtl_analyzer.md          # Analyze undriven ports
├── spgdft/
│   ├── precondition_agent.md    # Blackbox modules
│   ├── violation_extractor.md   # Parse DFT violations
│   └── rtl_analyzer.md          # Analyze TDR ports
└── shared/
    ├── library_finder.md        # Find missing libraries
    └── report_compiler.md       # Generate HTML report
```

## Agent Invocation by Check Type

| check_type | Agents Invoked |
|------------|----------------|
| `cdc_rdc` | CDC/RDC Precondition, Violation Extractor, RTL Analyzers |
| `lint` | Lint Violation Extractor, RTL Analyzers |
| `spg_dft` | SpgDFT Precondition, Violation Extractor, RTL Analyzers |
| `full_static_check` | ALL agents from all three flows |

## IP Configuration

`config/IP_CONFIG.yaml` for fast report path discovery:
- **UMC** (`umc9_3`, `umc17_0`): Default tile `umc_top`
- **OSS** (`oss7_2`, `oss8_0`): Default tile `osssys`
- **GMC** (`gmc13_1a`): Default tile varies

## Report Path Patterns

| Check | Path Pattern |
|-------|--------------|
| CDC | `out/linux_*/*/config/*/pub/sim/.../rhea_cdc/cdc_*_output/cdc_report.rpt` |
| RDC | `out/linux_*/*/config/*/pub/sim/.../rhea_cdc/rdc_*_output/rdc_report.rpt` |
| Lint | `out/linux_*/*/config/*/pub/sim/.../rhea_lint/leda_waiver.log` |
| SpgDFT | `out/linux_*/*/config/*/pub/sim/.../spg_dft/*/moresimple.rpt` |

## LOW_RISK Patterns (Filtered Out)

- `rsmu`, `RSMU` - Reset Scan MUX
- `rdft`, `RDFT` - DFT related
- `dft_`, `DFT_` - DFT prefix
- `jtag`, `JTAG` - JTAG debug
- `scan_`, `SCAN_` - Scan chain
- `bist_`, `BIST_` - Built-in self test
- `tdr_`, `TDR_` - Test Data Register

## Output Flow

| Content | Email | Conversation |
|---------|-------|--------------|
| Precondition summary | YES | NO |
| Violation counts | YES | NO |
| RTL analysis details | YES | NO |
| Recommendations | YES | NO |
| "Analysis complete" | YES | YES |

## CRITICAL: NO COMPRESSION for full_static_check

When running `full_static_check`, each check type MUST have SAME level of detail as individual runs:
- Same violation details
- Same root cause analysis
- Same recommendations
- Same code snippets

## LEARNING.md Integration

Agents check `config/analyze_agents/LEARNING.md` for similar past violations:
1. Check LEARNING.md first for matching patterns
2. Apply known fix if found
3. Add new learnings when novel fixes discovered
