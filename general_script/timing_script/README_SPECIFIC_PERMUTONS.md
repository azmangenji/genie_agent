# Design-Specific Permuton Strategy

## Overview

Based on detailed timing analysis, we've identified that **umccmd** and **umcdat** have fundamentally different timing bottlenecks requiring separate optimization strategies.

## Files Created

1. **`compile.permutons_original`** - Original 10 permutons (baseline)
2. **`compile.permutons_umccmd_specific`** - 8 permutons targeting umccmd memory controller issues
3. **`compile.permutons_umcdat_specific`** - 10 permutons targeting umcdat encryption/security issues

## Problem Analysis Summary

### umccmd (Memory Controller)
**Baseline:** -142.340 ps WNS, 3,588 violations
**DSO Improvement:** Only +5.19 ps (3.6%) - Poor!

**Root Causes:**
- High-fanout control signals (MrDimmEn_reg: 665 paths = 18.5%)
- Complex DCQ arbiter logic (1000+ violations)
- Timing counter depth (TwtrCtr, WrWrCtr: 170+ paths)
- Limited benefit from pipeline-focused original permutons

### umcdat (Security/Encryption)
**Baseline:** -135.006 ps WNS, 2,600 violations
**DSO Improvement:** +13.58 ps (10.1%) - Much better!

**Root Causes:**
- Deep AES encryption pipelines (3,095 paths!)
- Key expansion logic (RdKeyPipe, WrKeyPipe: 444 paths)
- XTS data transformation (426 paths)
- Better response to pipeline-focused original permutons

## Permuton Strategies

### umccmd-Specific Permutons (8 permutons)

| # | Permuton Name | Target | Strategy |
|---|---------------|--------|----------|
| 1 | `umccmd_fanout_duplication` | MrDimmEn, AutoRefReqPlr, IdleBWCfg | Register replication to reduce fanout |
| 2 | `umccmd_control_buffering` | High-fanout control paths | Aggressive buffering (1.0-3.0x) |
| 3 | `umccmd_dcq_arbiter_pipeline` | DCQARB, DCQARB1 logic | Restructure/balance arbiter |
| 4 | `umccmd_timing_counter_opt` | TwtrCtr, WrWrCtr, RdRdCtr | Pipeline/restructure counters |
| 5 | `umccmd_arb_safe_reg_opt` | ArbSafeRegPc/Ph/Pm | Increase optimization effort |
| 6 | `umccmd_critical_path_groups` | Paths by startpoint | Group and prioritize |
| 7 | `umccmd_pgt_optimization` | PGT allocation logic | Target PgtAlloc/DeAlloc |
| 8 | `umccmd_control_isolation` | Control-to-datapath | Isolate with buffers/spatial |

**Expected Improvement:** Target +20-30 ps by addressing control logic fanout

### umcdat-Specific Permutons (10 permutons)

| # | Permuton Name | Target | Strategy |
|---|---------------|--------|----------|
| 1 | `umcdat_aes_pipeline_balance` | UMCSEC_RDPIPE/WRPIPE | Balance pipeline stages |
| 2 | `umcdat_key_pipeline_retime` | RdKeyPipe, WrKeyPipe | Forward/backward/adaptive retiming |
| 3 | `umcdat_xts_pipeline_opt` | XTSPIPE, XtsDatPipeNxt | Restructure + add stages |
| 4 | `umcdat_aes_mode_fanout` | Aes128Mode_reg | Replicate/buffer control |
| 5 | `umcdat_ecc_read_opt` | ECCRD logic | High effort on ECC paths |
| 6 | `umcdat_wdb_fifo_opt` | wrstor_fifo, RdAdr_s_reg | FIFO access optimization |
| 7 | `umcdat_deep_pipeline_insert` | 25+ level paths | Insert pipeline registers |
| 8 | `umcdat_encrypt_datapath_buffer` | UMCSEC datapath | Strategic buffering (1.0-2.5x) |
| 9 | `umcdat_beq_tx_opt` | beq_tx logic | BEQ transmit optimization |
| 10 | `umcdat_rddatpipe_balance` | RdDatPipe across RDPIPE0-6 | Balance across instances |

**Expected Improvement:** Target +25-35 ps on top of existing +13.58 ps

## Usage Strategy

### Option 1: Design-Specific Only
Use only the design-specific permutons for focused optimization:
```bash
# For umccmd
cp compile.permutons_umccmd_specific compile.permutons

# For umcdat
cp compile.permutons_umcdat_specific compile.permutons
```

### Option 2: Original + Design-Specific (Recommended)
Combine original permutons with design-specific for broader coverage:
```bash
# For umccmd
cat compile.permutons_original compile.permutons_umccmd_specific > compile.permutons

# For umcdat
cat compile.permutons_original compile.permutons_umcdat_specific > compile.permutons
```

### Option 3: All Permutons (Maximum Exploration)
Use all permutons for comprehensive DSO exploration:
```bash
# For umccmd
cat compile.permutons_original compile.permutons_umccmd_specific > compile.permutons

# For umcdat
cat compile.permutons_original compile.permutons_umcdat_specific > compile.permutons
```

**Note:** More permutons = larger exploration space = longer DSO runtime

## Expected Results

### umccmd Timing Target
- **Current baseline:** -142.340 ps
- **Current best DSO:** -137.151 ps (+5.19 ps)
- **Target with new permutons:** -115 to -110 ps (+20-30 ps improvement)
- **Final gap to -90 ps:** 20-25 ps

### umcdat Timing Target
- **Current baseline:** -135.006 ps
- **Current best DSO:** -121.430 ps (+13.58 ps)
- **Target with new permutons:** -95 to -85 ps (+25-35 ps improvement)
- **Final gap to -90 ps:** 0-5 ps ✓ Likely to MEET TARGET

## Next Steps

1. **Create proc files** - Each permuton needs a corresponding TCL proc file
2. **Test individually** - Validate each permuton works correctly
3. **Run DSO** - Execute DSO with new permuton combinations
4. **Analyze results** - Compare improvements vs baseline
5. **Iterate** - Refine permuton parameters based on results

## Proc Files Required

### For umccmd:
- `umccmd_fanout_duplication_procs.tcl`
- `umccmd_control_buffering_procs.tcl`
- `umccmd_dcq_arbiter_procs.tcl`
- `umccmd_timing_counter_procs.tcl`
- `umccmd_arb_safe_reg_procs.tcl`
- `umccmd_critical_groups_procs.tcl`
- `umccmd_pgt_opt_procs.tcl`
- `umccmd_control_isolation_procs.tcl`

### For umcdat:
- `umcdat_aes_pipeline_procs.tcl`
- `umcdat_key_retime_procs.tcl`
- `umcdat_xts_pipeline_procs.tcl`
- `umcdat_aes_mode_procs.tcl`
- `umcdat_ecc_read_procs.tcl`
- `umcdat_wdb_fifo_procs.tcl`
- `umcdat_deep_pipeline_procs.tcl`
- `umcdat_encrypt_buffer_procs.tcl`
- `umcdat_beq_tx_procs.tcl`
- `umcdat_rddatpipe_procs.tcl`

**Note:** Proc files contain the actual TCL implementation of the optimization strategies.
