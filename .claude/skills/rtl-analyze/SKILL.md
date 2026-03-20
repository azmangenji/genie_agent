# RTL Analyze Skill

Analyze RTL (Verilog/SystemVerilog) code for issues, best practices, and potential bugs.

## Trigger
`/rtl-analyze`

## Workflow

1. **Gather Information**
   Ask the user for:
   - File(s) to analyze
   - Specific concerns (timing, lint, style, synthesizability)
   - Design type (combinational, sequential, FSM, datapath)

2. **Perform Analysis**
   Check for:
   - Linting issues (undriven signals, width mismatches)
   - Coding style violations
   - Potential synthesis issues
   - Clock domain crossing concerns
   - Reset handling
   - FSM encoding and completeness

3. **Report Findings**
   Provide:
   - Categorized list of issues
   - Severity levels (Error, Warning, Info)
   - Specific line references
   - Suggested fixes

## Analysis Categories

### Linting Checks
- Undriven nets
- Multi-driven nets
- Width mismatches in assignments
- Unused signals
- Inferred latches
- Incomplete sensitivity lists

### Synthesizability Checks
- Non-synthesizable constructs
- Delays in RTL (should be for simulation only)
- Initial blocks (synthesis vs simulation)
- Proper use of generate statements
- Blocking vs non-blocking assignments

### Timing Checks
- Combinational loops
- Long combinational paths
- Missing registers in pipeline stages
- Clock gating issues

### FSM Analysis
- Unreachable states
- Missing state transitions
- Default case handling
- One-hot vs binary encoding
- Safe FSM implementation

### Reset Analysis
- Asynchronous vs synchronous reset usage
- Missing reset for flip-flops
- Reset value consistency

## Output Format

```
=== RTL Analysis Report for {filename} ===

ERRORS (Must Fix):
[E001] Line 45: Width mismatch: assigning 8-bit value to 4-bit signal 'count'
       Suggestion: Truncate explicitly or widen target signal

[E002] Line 78: Inferred latch on signal 'state_next'
       Suggestion: Add default assignment or cover all cases

WARNINGS (Should Review):
[W001] Line 23: Signal 'debug_data' is declared but never used
       Suggestion: Remove if unused, or add `// synopsys translate_off` if debug only

[W002] Line 56: Blocking assignment in clocked always block
       Suggestion: Use non-blocking (<=) for sequential logic

INFO (Best Practice):
[I001] Line 12: Consider parameterizing DATA_WIDTH for reusability
[I002] Line 89: FSM has 8 states - consider one-hot encoding for timing

=== Summary ===
Errors: 2 | Warnings: 2 | Info: 2
```

## Best Practice Recommendations

### Signal Naming
- Use consistent prefixes: `i_` (input), `o_` (output), `r_` (register)
- Use `_n` suffix for active-low signals
- Use descriptive names, not abbreviations

### Coding Style
- One module per file
- Consistent indentation (2 or 4 spaces)
- Group related signals
- Comment complex logic

### Synthesizable Code
```systemverilog
// Good - synthesizable counter
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n)
    count <= '0;
  else if (enable)
    count <= count + 1'b1;
end

// Bad - infers latch
always_comb begin
  if (sel)
    out = a;
  // Missing else!
end
```

## Interactive Mode

When running interactively, Claude will:
1. Read the specified RTL file(s)
2. Perform comprehensive analysis
3. Present findings by severity
4. Offer to help fix specific issues
5. Explain reasoning for each finding
