# Round Robin Arbiter — SystemVerilog Verification

**VLSI Verification Methodologies | VIT Vellore**
> **Syed Faheem,**
>  M.Tech VLSI Design — VIT Vellore  
   

A parameterised Round Robin arbiter supporting three arbitration policies, fully verified using a layered, UVM-inspired SystemVerilog testbench.

---

## Table of Contents

- [Overview](#overview)
- [Repository Structure](#repository-structure)
- [DUT — Arbitration Modes](#dut--arbitration-modes)
- [Testbench Architecture](#testbench-architecture)
- [Quick Start](#quick-start)
- [Parameters](#parameters)
- [Test Results](#test-results)
- [Code Coverage](#code-coverage)
- [Known Issues](#known-issues)
- [Acknowledgement](#acknowledgement)

---

## Overview

This project implements and verifies a parameterised Round Robin (RR) arbiter in SystemVerilog. The DUT supports three arbitration policies selected at compile time via the `TYPE` parameter:

| TYPE | Mode | Description |
|------|------|-------------|
| 0 | Conventional RR | Pointer increments by 1 after every arbitration cycle |
| 1 | Modified RR | Pointer jumps to `winner + 1`, eliminating stale pointer positions |
| 2 | Weighted RR | Each requester holds a weight counter; higher-weight requesters receive proportionally more grants |

The testbench follows an OOP layered architecture inspired by UVM, with typed mailboxes for inter-component communication. All three arbitration types were verified across `N = 4, 5, 7, 10` requesters with 100 randomised transactions per run.

---

## Repository Structure

```
round-robin-arbiter/
├── rtl/
│   └── round_robin.sv          # DUT — parameterised arbiter (TYPE 0/1/2)
├── tb/
│   ├── rr_interface.sv         # SV interface with driver_cb and monitor_cb clocking blocks
│   ├── rr_pkg.sv               # Package: transaction, generator, driver, monitor, scoreboard,
│   │                           #          environment, test — all in one compilation unit
│   └── rr_tb_top.sv            # Top-level module: clock gen, DUT instance, test launch
├── sim/
│   └── Makefile                # Questa compile & run targets
└── README.md
```

---

## DUT — Arbitration Modes

The DUT uses a **Rotate–Priority–Rotate (RPR)** scheme:

1. Rotate the N-bit request vector right by `ptr` positions.
2. Priority-encode: isolate the lowest set bit (`rotate_r & ~(rotate_r - 1)`).
3. Rotate the one-hot result left by `ptr` to recover original bit positions.

**TYPE=0 (Conventional RR)** — `ptr` increments by 1 every enabled cycle regardless of winner.

**TYPE=1 (Modified RR)** — `ptr` jumps directly to `winner + 1`, skipping unused pointer slots.

**TYPE=2 (Weighted RR)** — Each requester has a `W`-bit weight counter. Only the highest-weight active requesters are eligible in any given cycle. After a grant the winner's counter decrements; a `i_load` pulse reloads all counters from `i_weights`.

---

## Testbench Architecture

```
┌─────────────┐   gen2drv mailbox   ┌─────────────┐
│  Generator  │ ──────────────────► │   Driver    │
└─────────────┘                     └──────┬──────┘
                                           │ virtual interface (driver_cb)
                                    ┌──────▼──────┐
                                    │     DUT     │
                                    └──────┬──────┘
                                           │ virtual interface (monitor_cb)
                                    ┌──────▼──────┐   mon2scb mailbox   ┌─────────────┐
                                    │   Monitor   │ ──────────────────► │ Scoreboard  │
                                    └─────────────┘                     └─────────────┘
```

| Component | File | Role |
|-----------|------|------|
| `rr_transaction` | `rr_pkg.sv` | Stimulus/response container with `rand` constraints |
| `rr_generator` | `rr_pkg.sv` | Randomises and pushes transactions; fires `done` event |
| `rr_driver` | `rr_pkg.sv` | Applies reset then drives each transaction via `driver_cb` |
| `rr_monitor` | `rr_pkg.sv` | Samples DUT inputs and registered grant output; pairs req→gnt |
| `rr_scoreboard` | `rr_pkg.sv` | Reference model for all three TYPEs; reports PASS/FAIL |
| `rr_environment` | `rr_pkg.sv` | Instantiates components, wires mailboxes and events |
| `rr_test` | `rr_pkg.sv` | Top-level test class; sets transaction count and calls `env.run()` |
| `rr_interface` | `rr_interface.sv` | SV interface with separate driver/monitor clocking blocks |
| `rr_tb_top` | `rr_tb_top.sv` | Module top: clock, DUT, interface, initial block |

The scoreboard accounts for `o_gnt` being a **registered output** — the grant at cycle N reflects the request at cycle N−1. The monitor captures this by waiting an extra clock after sampling inputs before reading `gnt`.

---

## Quick Start

### Prerequisites

- Questa Sim (ModelSim) with SystemVerilog support

### Run from the `sim/` directory

```bash
# Default: TYPE=2, N=10, W=3
make questa_cmd

# Override parameters
make questa_cmd N=4 W=3 TYPE=0

# GUI mode with waveforms
make questa_gui N=7 W=3 TYPE=1

# Clean build artefacts
make clean
```

### Manual compile & simulate (without Make)

```bash
# Compile
vlib work
vmap work work
vlog +define+N=4+W=3+TYPE=0 rtl/round_robin.sv tb/rr_interface.sv tb/rr_pkg.sv tb/rr_tb_top.sv

# Batch simulate
vsim -c -novopt -do "run -all; quit" rr_tb_top

# Save waveform
vsim -novopt -wlf wave.wlf -do "add wave -r *; run -all; quit" rr_tb_top
```

### Code coverage

```bash
vlog +define+N=4+W=3+TYPE=0 +cover=bcesf \
     rtl/round_robin.sv tb/rr_interface.sv tb/rr_pkg.sv tb/rr_tb_top.sv

vsim -c -novopt -coverage \
     -do "coverage save -onexit cov_TYPE0_N4.ucdb; run -all; quit" rr_tb_top

# Merge multiple runs
vcover merge combined.ucdb cov_TYPE*.ucdb

# Report
vcover report combined.ucdb
```

---

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `N` | 10 | Number of requesters |
| `W` | 3 | Weight counter width (max weight = 2^W − 1) |
| `TYPE` | 2 | Arbitration mode: 0 = Conventional, 1 = Modified, 2 = Weighted |

`N` and `W` are passed as Verilog defines (`+define+N=...+W=...+TYPE=...`) at compile time and propagate through both the DUT and the testbench package.

---

## Test Results

100 randomised transactions per configuration; first transaction skipped due to the DUT's one-cycle pipeline latency.

| TYPE | N | PASS | FAIL | Status |
|------|---|------|------|--------|
| 0 (Conventional) | 4 | 59 | 0 | ✅ ALL PASS |
| 0 (Conventional) | 5 | 59 | 0 | ✅ ALL PASS |
| 0 (Conventional) | 7 | 59 | 0 | ✅ ALL PASS |
| 0 (Conventional) | 10 | 59 | 0 | ✅ ALL PASS |
| 1 (Modified) | 4 | 59 | 0 | ✅ ALL PASS |
| 1 (Modified) | 5 | 59 | 0 | ✅ ALL PASS |
| 1 (Modified) | 7 | 59 | 0 | ✅ ALL PASS |
| 1 (Modified) | 10 | 59 | 0 | ✅ ALL PASS |
| 2 (Weighted) | 4 | 41 | 19 | ⚠️ Scoreboard bug (see below) |
| 2 (Weighted) | 5 | 40 | 20 | ⚠️ Scoreboard bug (see below) |
| 2 (Weighted) | 10 | 37 | 23 | ⚠️ Scoreboard bug (see below) |

---

## Code Coverage

Combined across all 12 runs (TYPE=0,1,2 × N=4,5,7,10).

| File | Stmt % | Branch % | Cond % | Notes |
|------|--------|----------|--------|-------|
| `round_robin.sv` (DUT) | 100% | 100% | ~95% | 1 FEC condition missed |
| `rr_driver.sv` | 100% | 100% | 100% | — |
| `rr_monitor.sv` | 100% | 100% | 100% | — |
| `rr_generator.sv` | ~69% | ~69% | — | TYPE=2 branches partially exercised |
| `rr_scoreboard.sv` | ~73% | ~73% | — | TYPE=2 weight branches not fully hit |
| `rr_transaction.sv` | ~0% | 100% | 100% | `copy()` method not called in this build |

The single missed FEC condition in the DUT corresponds to the corner case where all requesters are simultaneously active with exactly equal TYPE=2 weights.

---

## Known Issues

**TYPE=2 scoreboard failures** — The DUT is functionally correct (confirmed by waveform inspection). The failures are caused by a one-cycle timing mismatch in the reference model: the scoreboard applies a weight-load in the same cycle it is issued, whereas the DUT registers the new weights on the *next* posedge. The fix is to delay `weights_ref` application by one cycle in `compute_expected()`.

**Planned fixes / future work:**
- Fix TYPE=2 scoreboard weight-load timing
- Add a functional covergroup (all requesters granted, all `ptr` values visited, `en=0` idle cycles)
- Add directed test sequence for the equal-weight tie-breaking edge case
- Migrate to a full UVM environment with `uvm_agent` and `uvm_sequencer`

---

## Acknowledgement

I would like to express my sincere gratitude to my teammates for their valuable contributions to this project:

* **Sreehari R** — LinkedIn: https://www.linkedin.com/in/sreehari-r-599633229/
* **Anupamkrishna P** — LinkedIn: https://www.linkedin.com/in/anupamkrishna-k-m-7ab24738b/

Their efforts in design, verification, debugging, and documentation were instrumental in the successful completion of this work.

This project was submitted to **Dr. Prayline Rajabai C**, Associate Professor, School of Electronics Engineering (SENSE), VIT Vellore, as part of the course **VLSI Verification Methodologies**.
