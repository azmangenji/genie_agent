# CDC/RDC LEARNING.md - Past Fixes and Solutions

**PURPOSE:** Documents past CDC/RDC violations and their confirmed fixes. Check this before analyzing — if a matching pattern exists, apply the same solution.

**MAINTAINER:** abinbaba — DO NOT update or add to this file automatically. It is managed manually by the user only.

---

## How to Add New Learnings

When a fix is confirmed working, add it here with:

1. **Violation Pattern** - The exact or generalized error message
2. **Past Fix Example** - Specific signal/module that had this issue
3. **Root Cause** - Why the violation occurred
4. **Solution** - RTL fix OR constraint/waiver with code snippet

---

### 1. no_sync - "Specification Failed - Receiver outside sync module" for glkcmd1_lib ULVT sync cells

**Violation Pattern:**
```
Single-bit signal does not have proper synchronizer. (no_sync)
Async : start : <signal>
    <CLK> : end : <path>.hdsync3msfqxss1us_ULVT.inst_0.IQ_zint
    Specification Failed - Receiver outside sync module. Scheme Name: two_dff

    <CLK> : end : <path>.hdsync4msfqxss1us_ULVT.inst_0.IQ_zint
    Specification Failed - Receiver outside sync module. Scheme Name: two_dff
```

**Past Fix Example (umc17_0, umc_grimlock_Mar18170524):**
- **Signals affected:** `Cpl_PWROK`, `Cpl_RESETn`, `Cpl_GAP_PWROK`, `oQ_PETCtrl_tECSint[0:9]`, `REG_CtrlUpdClks[0:N]`, `pgfsm_power_down/up_delay_reg[0:31]` — 154 violations total
- **Constraint file:** `src/meta/tools/cdc0in/variant/umc17_0/project.0in_ctrl.v.tcl`

**Root Cause:**
`hdsync3msfqxss1us_ULVT` and `hdsync4msfqxss1us_ULVT` are **instance names** (not module names) inside `techind_sync3_implementation.v` / `techind_sync4_implementation.v`. The actual library **module names** are:
- `SDFSYNC3QD1AMDBWP330HPNPN3P44CPDULVT` (3-stage, from `glkcmd1_lib`)
- `SDFSYNC4QD1AMDBWP440HPNPN3P44CPDULVT` (4-stage, from `glkcmd1_lib`)

These cells were **not registered** as custom synchronizers in the CDC constraint file. The existing `cdc custom sync hdsync*msfqxss1us` constraint targets old cell naming (no `_ULVT` suffix) and uses wrong port names (`CLK`, `SDI`, `SEN`). The actual cells use `CP` for clock, `SI` for scan input, `SE` for scan enable.

The CDC tool auto-detected a partial `two_dff` structure inside the cell but could not resolve the synchronizer boundary, causing it to flag the endpoint (`IQ_zint` — an internal node) as "Receiver outside sync module."

**How to Identify:**
1. All `no_sync` endpoints end at `hdsync3msfqxss1us_ULVT.inst_0.IQ_zint` or `hdsync4msfqxss1us_ULVT.inst_0.IQ_zint`
2. Violation message always says: `Specification Failed - Receiver outside sync module. Scheme Name: two_dff`
3. RTL instantiation in `techind_sync3/4_implementation.v` confirms instance name vs module name

**Solution — add to `project.0in_ctrl.v.tcl`:**
```tcl
#Abinbaba Added these cells for Grimlock CDC umc17_0 2026-03-18
cdc custom sync SDFSYNC3QD1AMDBWP330HPNPN3P44CPDULVT -type two_dff
netlist port domain D  -async -clock CP -module SDFSYNC3QD1AMDBWP330HPNPN3P44CPDULVT
netlist port domain Q  -clock CP -module SDFSYNC3QD1AMDBWP330HPNPN3P44CPDULVT
netlist port domain SI -clock CP -module SDFSYNC3QD1AMDBWP330HPNPN3P44CPDULVT
netlist port domain SE -clock CP -module SDFSYNC3QD1AMDBWP330HPNPN3P44CPDULVT

cdc custom sync SDFSYNC4QD1AMDBWP440HPNPN3P44CPDULVT -type two_dff
netlist port domain D  -async -clock CP -module SDFSYNC4QD1AMDBWP440HPNPN3P44CPDULVT
netlist port domain Q  -clock CP -module SDFSYNC4QD1AMDBWP440HPNPN3P44CPDULVT
netlist port domain SI -clock CP -module SDFSYNC4QD1AMDBWP440HPNPN3P44CPDULVT
netlist port domain SE -clock CP -module SDFSYNC4QD1AMDBWP440HPNPN3P44CPDULVT
```

**Port Verification:**
- Clock port confirmed as `CP` from library stub: `/proj/glkcmd1_lib/a0/library/lib_0.0.1_h110/verilog/stdcell/tcba14h110l3p44camdconfidentialulvt.stub.v`
- Same `CP` naming confirmed for Konark cells: `/proj/knr_pd_librel/a0/library/lib_1.0.0/verilog/stdcell/tcbn03cbwp136p5mh273l3p48cpdamdconfidentialulvt_nopwr.v`
- `-type two_dff` consistent with existing Konark `SDFSYNC*` constraints in same file

**Key Lessons:**
1. When `no_sync` points to `<instance>.IQ_zint` — always check if the instance name is being confused with the module name
2. Look up the actual module (cell) name from the RTL where it's instantiated
3. Confirm port names (`CP` vs `CLK`, `SE` vs `SEN`) directly from the library stub `.v` file — do not assume they match older constraints
4. `glkcmd1_lib` cells use `CP` for clock; `CLK` is used by older AMD custom cells

**Status:** Confirmed working ✓ (umc17_0, 2026-03-18)

---

### Why `cdc custom sync` + `netlist port domain` Solves `no_sync` — Step by Step

#### Step 1: What `no_sync` Actually Means

When Questa CDC analyzes a signal crossing from clock domain A to clock domain B, it traces the path and asks:

> "Does this signal pass through a **recognized** synchronizer before being used in the destination domain?"

If the answer is **no** → it flags `no_sync`.

The key word is **"recognized"**. The tool has a built-in library of synchronizer patterns it knows (2-DFF, pulse sync, etc.), but it does **not** automatically know about custom AMD IP cells like `SDFSYNC3QD1AMDBWP330HPNPN3P44CPDULVT`.

---

#### Step 2: What the Tool Was Seeing (Before the Fix)

Take this violation:
```
Async : start : Cpl_PWROK
    UCLK : end : umc0.umcdat.umcsmn.CplPwrOkSyncDficlk.SYNC.u_tis_icd
                 .d0nt_sync...hdsync4msfqxss1us_ULVT.inst_0.IQ_zint
    Specification Failed - Receiver outside sync module. Scheme Name: two_dff
```

The tool traced `Cpl_PWROK` (async) into the design and found it arriving at `IQ_zint` — an **internal node** inside the `SDFSYNC4QD1AMDBWP440HPNPN3P44CPDULVT` library cell. Since the tool doesn't know what this cell is, it:

1. Sees flip-flops inside (auto-detects a `two_dff` structure)
2. Does NOT know which pin is the **safe synchronized output**
3. Considers the "receiver" (logic using the sync output) to be **outside** the synchronizer boundary
4. Flags `no_sync` — from its perspective the signal was never properly synchronized

```
                    +--------------------------------------------+
Cpl_PWROK -------->| SDFSYNC4QD1AMDBWP440HPNPN3P44CPDULVT      |
(async)            |                                            |
                   |  D --> [DFF1] --> [DFF2] --> [DFF3] --> Q  |
                   |           ^                               |
                   |         IQ_zint <-- tool stops here      |
                   |         (internal node)                  |
                   +--------------------------------------------+
                                                               |
                                               Tool says: receiver is
                                               OUTSIDE sync module -> no_sync
```

---

#### Step 3: What `cdc custom sync` Does

```tcl
cdc custom sync SDFSYNC4QD1AMDBWP440HPNPN3P44CPDULVT -type two_dff
```

This tells the CDC tool:

> "This module IS a synchronizer. Treat it as a valid two-DFF synchronization boundary. Stop looking inside it."

The tool now **recognizes the entire cell as a synchronizer** and does not trace through its internals. The cell boundary itself becomes the sync boundary.

```
                    +--------------------------------------------+
Cpl_PWROK -------->| SDFSYNC4QD1AMDBWP440HPNPN3P44CPDULVT      |<-- Tool now
(async)            |  <--  recognized as synchronizer  -->      |    knows this
                   |                                            |    is a sync
                   +--------------------------------------------+
                                          |
                                          v Q
                                   (safe to use in UCLK domain)
```

---

#### Step 4: What `netlist port domain` Does

`cdc custom sync` alone is not enough — the tool also needs to know **which pin is async** and **which pin is the synchronized output**. That is what `netlist port domain` provides:

```tcl
netlist port domain D  -async -clock CP -module SDFSYNC4QD1AMDBWP440HPNPN3P44CPDULVT
netlist port domain Q  -clock CP        -module SDFSYNC4QD1AMDBWP440HPNPN3P44CPDULVT
netlist port domain SI -clock CP        -module SDFSYNC4QD1AMDBWP440HPNPN3P44CPDULVT
netlist port domain SE -clock CP        -module SDFSYNC4QD1AMDBWP440HPNPN3P44CPDULVT
```

Each line tells the tool something specific:

| Constraint | Meaning |
|---|---|
| `D -async -clock CP` | Pin `D` accepts signals from **any clock domain** — metastability is expected and handled internally by the sync cell |
| `Q -clock CP` | Pin `Q` output belongs to the **`CP` (destination) clock domain** — safe to use downstream |
| `SI -clock CP` | Scan input is in `CP` domain — not a CDC crossing, ignore it |
| `SE -clock CP` | Scan enable is in `CP` domain — not a CDC crossing, ignore it |

Full picture after both constraints:

```
           SDFSYNC4QD1AMDBWP440HPNPN3P44CPDULVT
          +------------------------------------------+
          |                                          |
any_clk ->| D (-async)   [4-stage sync cells]   Q ->|-> CP domain (safe)
          |                                          |
CP ------>| CP (clock)                               |
          |                                          |
CP ------>| SI, SE (scan ports, CP domain)           |
          +------------------------------------------+
```

---

#### Step 5: The Combined Effect

With both constraints together:

1. **`cdc custom sync`** → tool treats this cell as a black-box synchronizer, stops tracing internals
2. **`netlist port domain D -async`** → tool knows `Cpl_PWROK` (async) entering `D` is expected and handled
3. **`netlist port domain Q -clock CP`** → tool knows anything reading `Q` is safely in the destination clock domain

Result: the crossing is now **classified as properly synchronized** → `no_sync` disappears → crossing moves to **Evaluations** (verified).

---

#### Why It Was Working for Other Crossings But Not These

| Crossing Type | Count | Status | Why |
|---|---|---|---|
| `techind_cdcefpm_single` | 610 | Evaluations (PASS) | Custom scheme already registered with its own constraint |
| `hdsync3/4msfqxss1us_ULVT` cells | 154 | Violations (FAIL) | New `glkcmd1_lib` cells had NO constraint registered — tool didn't know they were synchronizers |

The 610 passing crossings use `techind_cdcefpm` — a separately defined custom scheme. The 154 failing ones use `SDFSYNC*HPNPN3P44CPDULVT` cells that were new to this library version and had no entry in the constraint file.

---

**Last Updated:** 2026-03-18
**Maintainer:** abinbaba
