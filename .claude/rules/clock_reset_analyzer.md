---
paths:
  - "script/rtg_oss_feint/clock_reset_analyzer.py"
  - "**/clock_reset_report.*"
  - "**/*.vf"
---

# Clock/Reset Structure Analyzer

Analyzes RTL clock and reset structures from a .vf file, generating comprehensive reports with hierarchical port tracing.

## Usage

```bash
# Via Genie CLI
python3 script/genie_cli.py -i "analyze clock reset structure at /proj/xxx/tree_dir for umc17_0" --execute --email

# Direct invocation
python3 script/rtg_oss_feint/clock_reset_analyzer.py <vf_file> --top <top_module> --output <report.rpt> --html <report.html> --dot <prefix>
```

## What it Does

1. **Parses .vf file** to find all RTL source files
2. **Identifies primary clocks** (UCLKin0, DFICLKin0, Cpl_REFCLK, etc.)
3. **Identifies primary resets** (Cpl_PWROK, Cpl_RESETn, etc.)
4. **Traces signal paths** through design hierarchy with recursive port-name-following
5. **Detects clock gating cells** (ati_clock_gate, UMCCLKGATER)
6. **Detects CDC synchronizers** (techind_sync, UMCSYNC)
7. **Generates reports**:
   - Text report (`.rpt`)
   - HTML report (`.html`)
   - Clock structure diagram (`.dot` → `.png`)
   - Reset structure diagram (`.dot` → `.png`)

## Output Files

| File | Description |
|------|-------------|
| `clock_reset_report.rpt` | Text report with clock/reset hierarchy |
| `clock_reset_report.html` | HTML report for email |
| `clock_reset_clock.png` | Clock hierarchy diagram |
| `clock_reset_reset.png` | Reset hierarchy diagram |

## Hierarchical Port Tracing

Performs **recursive port-name-following tracing**. When a signal connects to a differently-named port (e.g., `UCLKin0` → `.UCLK`), tracing continues inside the instantiated module using the new port name:

```
UCLKin0 (top input)
  └─→ umc0 (umc).UCLK
    └─→ umcdat (umcdat).UCLK
      └─→ I_CHGATER_UCLK_FuncCGCG (UMCCLKGATER).C [GATING]
        └─→ I_CLKGATER (ati_clock_gate).clk_src [GATING]
          └─→ d0nt_clkgate_cell (HDN6BLVT08_CKGTPLT_V7Y2_4).CLK
```

## DOT Diagram Legend

| Shape | Clock Diagram | Reset Diagram |
|-------|---------------|---------------|
| **Ellipse** | Primary Clock | Primary Reset |
| **Diamond** | Clock Gating Cell | Reset Gen/Control |
| **Hexagon** | CDC Synchronizer | CDC Synchronizer |
| **Octagon** | - | Sync Buffer |
| **Box** | Module Instance | Module Instance |

## Clock Diagram Shows

- Primary clock inputs (ellipse, blue)
- Clock gating cells (diamond, green) - ati_clock_gate, UMCCLKGATER
- CDC synchronizers (hexagon, pink) - UMCSYNC, techind_sync
- Module instances with port connections

## Reset Diagram Shows

- Primary reset inputs (ellipse, red)
- Reset generation modules (diamond, orange) - rsmu_rdft_instance, rsmu_cac_logger
- CDC synchronizers (hexagon, pink)
- Sync buffers (octagon, gold) - buf_asn
