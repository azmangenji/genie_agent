# FSDB Skill

Extract and analyze signals from FSDB waveform files using Python NPI API.

## Trigger
`/fsdb`

## Required Inputs

**User MUST provide:**
1. **FSDB path** - Full path to the FSDB file
2. **Signal source** - ONE of the following:
   - **RC file** - Path to Verdi signal.rc file, OR
   - **Full signal paths** - Complete hierarchical paths to signals

**AI will use Python NPI API exclusively** - No VCD conversion unless absolutely required.

---

## How to Request FSDB Signal Extraction

### When User Invokes This Guide

**AI Response:**
```
I can extract signals from FSDB using Python NPI API.

Please provide:
1. FSDB path (e.g., /path/to/verilog.fsdb)
2. Signal source - ONE of:
   - RC file path (e.g., /path/to/signal.rc)
   - Full signal paths (e.g., tb.umc_w_phy.dfi_if_0_3_0.signal_name)

Optional:
- Time range (e.g., 20ms-25ms)
- Specific analysis (e.g., "when valid=1", "error events")
```

---

## Input Option 1: RC File + FSDB Path

### User Provides:
```
FSDB: /path/to/run/verilog.fsdb
RC file: /path/to/signal.rc
```

### AI Workflow:
1. Parse signal.rc to extract signal paths
2. Open FSDB with Python NPI
3. Extract values for all signals in RC file
4. Analyze and report results

### Example Interaction:
```
User: "Extract signals from my FSDB"
AI:   "Please provide FSDB path and signal source (RC file or signal paths)"

User: "FSDB: /proj/test/run/verilog.fsdb
       RC: /proj/test/run/signal.rc"
AI:   "Reading signal.rc...
       Found 3 signal groups with 48 signals total.
       Extracting from FSDB using Python NPI...
       [Results]"
```

---

## Input Option 2: Full Signal Paths + FSDB Path

### User Provides:
```
FSDB: /path/to/run/verilog.fsdb
Signals:
  - tb.umc_w_phy.dfi_if_0_3_0.dfi_row_p0
  - tb.umc_w_phy.dfi_if_0_3_0.dfi_col_p0
  - tb.umc_w_phy.umc_top0.umc0.umcch0.umcdat.umc_rec.REC_BEQ_Cmd0Vld0
```

### AI Workflow:
1. Open FSDB with Python NPI
2. Extract values for each provided signal path
3. Analyze and report results

### Example Interaction:
```
User: "Extract these signals:
       FSDB: /proj/test/run/verilog.fsdb
       Signals:
         tb.module.signal1
         tb.module.signal2"
AI:   "Extracting 2 signals from FSDB using Python NPI...
       [Results]"
```

---

## Python NPI Implementation

### Prerequisites

```bash
# Verify VERDI_HOME is set
echo $VERDI_HOME
# Expected: /tool/cbar/apps/verdi/2024.09-SP2-4 (or similar)
```

### Core Extraction Code

```python
import sys, os

# Setup Python NPI
sys.path.append(f"{os.environ['VERDI_HOME']}/share/NPI/python")
from pynpi import npisys, waveform

# Initialize
npisys.init(["fsdb_extract"])

# Open FSDB
fsdb_path = "/path/to/verilog.fsdb"  # User-provided
fh = waveform.open(fsdb_path)

# Extract signal value at specific time
sig_path = "tb.module.signal"  # User-provided (dot separator!)
time = 22_000_000_000_000  # 22ms in fs (adjust for timescale)
value = waveform.sig_value_at(fh, sig_path, time)

# Extract all value changes in time range
begin_time = 20_000_000_000_000  # 20ms
end_time = 25_000_000_000_000    # 25ms
values = waveform.sig_value_between(fh, sig_path, begin_time, end_time)
# Returns list of (time, value) tuples

# Cleanup
waveform.close(fh)
npisys.end()
```

### Parsing RC File

```python
def parse_rc_file(rc_path):
    """Extract signal paths from Verdi signal.rc file."""
    signals = []
    with open(rc_path, 'r') as f:
        for line in f:
            line = line.strip()
            # RC files contain signal paths in various formats
            # Common patterns:
            if line.startswith('/') or line.startswith('tb.'):
                # Convert / separator to . for Python NPI
                sig_path = line.replace('/', '.')
                if sig_path.startswith('.'):
                    sig_path = sig_path[1:]
                signals.append(sig_path)
    return signals
```

### Complete Extraction Script

```python
import sys, os
sys.path.append(f"{os.environ['VERDI_HOME']}/share/NPI/python")
from pynpi import npisys, waveform

def extract_signals(fsdb_path, signal_paths, begin_time=0, end_time=None):
    """
    Extract signal values from FSDB using Python NPI.

    Args:
        fsdb_path: Path to FSDB file
        signal_paths: List of full signal paths (dot separator)
        begin_time: Start time in FSDB time units
        end_time: End time in FSDB time units (None = entire sim)

    Returns:
        Dict mapping signal paths to list of (time, value) tuples
    """
    npisys.init(["extract"])
    fh = waveform.open(fsdb_path)

    if end_time is None:
        end_time = 100_000_000_000_000  # 100ms in fs (adjust as needed)

    results = {}
    for sig_path in signal_paths:
        try:
            values = waveform.sig_value_between(fh, sig_path, begin_time, end_time)
            results[sig_path] = values
            print(f"Extracted {len(values)} transitions for {sig_path}")
        except Exception as e:
            print(f"Error extracting {sig_path}: {e}")
            results[sig_path] = []

    waveform.close(fh)
    npisys.end()

    return results

# Usage with user-provided inputs:
fsdb_path = "/user/provided/path/verilog.fsdb"
signals = [
    "tb.umc_w_phy.umc_top0.signal1",
    "tb.umc_w_phy.umc_top0.signal2",
]
results = extract_signals(fsdb_path, signals)
```

---

## Time Unit Handling

### Check Timescale First

```python
import subprocess

def get_timescale(fsdb_path):
    """Get FSDB timescale using fsdb2vcd summary."""
    result = subprocess.run(
        ["fsdb2vcd", fsdb_path, "-summary"],
        capture_output=True, text=True
    )
    for line in result.stdout.split('\n'):
        if "scale unit" in line.lower():
            return line.split(':')[-1].strip()
    return "unknown"
```

### Common Time Conversions

| Timescale | 1 ns | 1 us | 1 ms |
|-----------|------|------|------|
| **1fs** | 1,000,000 | 1,000,000,000 | 1,000,000,000,000 |
| **1ps** | 1,000 | 1,000,000 | 1,000,000,000 |
| **1ns** | 1 | 1,000 | 1,000,000 |

---

## Important Notes

### Signal Path Format
- **Python NPI uses `.` (dot) separator**
- Correct: `tb.umc_w_phy.umc_top0.signal`
- Wrong: `tb/umc_w_phy/umc_top0/signal`

### VCD Conversion - AVOID
**Only use VCD conversion if Python NPI fails completely.**

VCD conversion is slow (8-15 minutes) compared to Python NPI (~36 seconds).

If VCD is absolutely required:
```bash
# Last resort only!
fsdb2vcd /path/to/verilog.fsdb -s "tb/scope" -o /tmp/output.vcd
```

### Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| Signal not found | Wrong separator | Use `.` not `/` |
| No module pynpi | VERDI_HOME not set | `export VERDI_HOME=/tool/cbar/apps/verdi/...` |
| None values | Signal not dumped | Check FSDB dump configuration |
| Wrong times | Timescale mismatch | Check timescale first |

---

## AI Workflow Summary

```
1. User provides FSDB path + (RC file OR signal paths)
           ↓
2. AI validates inputs are complete
           ↓
3. If RC file: Parse to extract signal paths
           ↓
4. Open FSDB with Python NPI (NOT VCD)
           ↓
5. Extract signal values using waveform.sig_value_between()
           ↓
6. Analyze results and report to user
           ↓
7. Close FSDB and cleanup
```

**Key Rule: Use Python NPI exclusively. No VCD conversion unless NPI completely fails.**

---

## Quick Reference

### Minimum Required Inputs
```
FSDB: /full/path/to/verilog.fsdb
RC: /full/path/to/signal.rc
   OR
Signals:
  - tb.full.path.to.signal1
  - tb.full.path.to.signal2
```

### Python NPI Essentials
```python
# Setup
sys.path.append(f"{os.environ['VERDI_HOME']}/share/NPI/python")
from pynpi import npisys, waveform

# Open
npisys.init(["name"])
fh = waveform.open(fsdb_path)

# Extract
value = waveform.sig_value_at(fh, sig_path, time)
values = waveform.sig_value_between(fh, sig_path, t1, t2)

# Cleanup
waveform.close(fh)
npisys.end()
```

### Documentation
```bash
zcat $VERDI_HOME/doc/.verdi_python_npi_waveform.txt.gz | less
```

---

**Version:** 2.0
**Last Updated:** 2026-01-16
