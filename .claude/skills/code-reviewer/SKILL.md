# SystemVerilog Code Review Skill

Review SystemVerilog code for best practices, style, and potential issues.

## Trigger
`/review-sv`

## Workflow

1. **Gather Information**
   Ask the user for:
   - File(s) to review
   - Code type (RTL, testbench, or both)
   - Specific concerns or focus areas
   - Coding standard to follow (if any)

2. **Perform Review**
   Check against:
   - Industry best practices
   - Common pitfalls
   - Style consistency
   - Maintainability

3. **Provide Feedback**
   - Categorize findings
   - Explain reasoning
   - Suggest improvements

## Review Categories

### Naming Conventions

**Good Practices:**
```systemverilog
// Signals
logic [7:0] data_in;      // snake_case
logic       valid_n;      // _n for active low
logic       clk_100mhz;   // Descriptive

// Parameters
parameter int DATA_WIDTH = 32;  // UPPER_CASE
localparam int FIFO_DEPTH = 16;

// Types
typedef enum logic [1:0] {
  IDLE,
  READ,
  WRITE,
  DONE
} state_e;  // _e suffix for enum

typedef struct packed {
  logic [31:0] addr;
  logic [31:0] data;
} request_t;  // _t suffix for typedef
```

**Avoid:**
```systemverilog
logic [7:0] d;        // Too short, not descriptive
logic Data_Valid;     // Inconsistent case
logic flg;            // Cryptic abbreviation
```

### Code Structure

**Module Template:**
```systemverilog
// File: module_name.sv
// Description: Brief description of module functionality
// Author: Name
// Date: YYYY-MM-DD

module module_name #(
  parameter int WIDTH = 8,
  parameter int DEPTH = 16
) (
  // Clock and Reset
  input  logic              clk,
  input  logic              rst_n,

  // Input Interface
  input  logic [WIDTH-1:0]  data_in,
  input  logic              valid_in,
  output logic              ready_out,

  // Output Interface
  output logic [WIDTH-1:0]  data_out,
  output logic              valid_out,
  input  logic              ready_in
);

  // Local Parameters
  localparam int ADDR_WIDTH = $clog2(DEPTH);

  // Internal Signals
  logic [ADDR_WIDTH-1:0] wr_ptr;
  logic [ADDR_WIDTH-1:0] rd_ptr;

  // Sequential Logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr <= '0;
    end else begin
      // Logic here
    end
  end

  // Combinational Logic
  always_comb begin
    // Logic here
  end

  // Assertions
  `ifndef SYNTHESIS
  assert property (@(posedge clk) valid_in |-> !$isunknown(data_in))
    else $error("Data unknown when valid");
  `endif

endmodule
```

### Common Issues Checklist

**Synthesizability:**
- [ ] No delays in synthesizable code
- [ ] No initial blocks (except for memories)
- [ ] Proper use of always_ff, always_comb, always_latch
- [ ] No blocking assignments in sequential blocks
- [ ] No non-blocking assignments in combinational blocks

**Completeness:**
- [ ] All cases covered in case statements
- [ ] All signals assigned in combinational blocks
- [ ] No inferred latches
- [ ] Sensitivity lists complete (or use always_comb)

**Robustness:**
- [ ] Reset handling for all flops
- [ ] X-propagation considered
- [ ] Clock domain crossings handled
- [ ] Assertions for protocol checking

### Style Guidelines

**Indentation:** 2 spaces (no tabs)

**Line Length:** Max 100 characters

**Operators:**
```systemverilog
// Good - spaces around operators
assign result = (a + b) * c;

// Avoid - no spaces
assign result=(a+b)*c;
```

**Begin/End:**
```systemverilog
// Good - always use begin/end
if (condition) begin
  a <= b;
end else begin
  a <= c;
end

// Avoid - single line without begin/end
if (condition) a <= b;
```

**Comments:**
```systemverilog
// Single line comment for brief notes

/*
 * Multi-line comment for longer explanations
 * that span multiple lines
 */

// TODO: Mark items needing attention
// FIXME: Mark known issues
// NOTE: Mark important information
```

## Review Output Format

```
=== Code Review: {filename} ===

STYLE (Consistency):
[S001] Line 15: Inconsistent naming - 'DataValid' should be 'data_valid'
[S002] Line 42: Missing begin/end block in if statement

BEST PRACTICE:
[B001] Line 28: Consider using always_ff instead of always @(posedge clk)
[B002] Line 56: Magic number '8' should be a parameter

POTENTIAL BUG:
[P001] Line 33: Possible latch inferred - missing else branch
[P002] Line 67: Signal 'count' may overflow (no saturation logic)

IMPROVEMENT:
[I001] Line 10: Consider adding assertions for interface protocol
[I002] Line 89: Complex expression could be broken into named signals

=== Summary ===
Style: 2 | Best Practice: 2 | Potential Bugs: 2 | Improvements: 2
```
