# RISC-V single-cycle CPU (VHDL)

Top level (`cpu.vhd`): core, boot ROM, RAM and the MMIO address decoder.

![top level](docs/riscv_soc.png)

Inside the core (`core.vhd` / `DataPath.vhd`):

![datapath](docs/riscv_datapath.png)

| Folder       | Content |
|--------------|---------|
| `rtl/`       | CPU source (`.vhd`) |
| `tb_ci_cd/`  | Automatic tests, one per block, run by CI |
| `tb_uni/`    | Testbenches for the university task (fibonacci program in `hex.hex`) |
| `docs/`      | Diagrams: top level `riscv_soc`, core datapath `riscv_datapath` (`.svg` + `.png`) |
| `quartus/`   | Quartus project |
| `outdated/`  | Old, unused files |

## Boot and memory map

On reset the PC is `0x0000_1000`, the start of the boot ROM (`bootrom.vhd`, loaded from `boot.hex`):

```
0x1000: 800002B7   lui  x5, 0x80000
0x1004: 00028067   jalr x0, 0(x5)      -> jump to RAM at 0x8000_0000
```

The program itself lives in the unified RAM (`unifiedmem.vhd`, loaded from `hex.hex`), which holds both
instructions and data. `cpu.vhd` opens `boot.hex` and `hex.hex` from the directory the simulation runs in.

`MMIO.vhd` decodes addresses:

| Region | Address range | Load data (`RDsel`) | Write enable |
|--------|---------------|---------------------|--------------|
| Boot ROM | `0x0000_1000`–`0x0000_1FFF` | `001` | none (read only) |
| CLINT | `0x0200_0000`–`0x0200_FFFF` | `100` | `We_4` |
| PLIC | `0x0C00_0000`–`0x0FFF_FFFF` | `011` | `We_3` |
| UART | `0x1000_0000`–`0x1000_00FF` | `010` | `WE3_2` (byte lanes) |
| GPIO | `0x1000_1000` | `101` | `We_5` |
| RAM | `0x8000_0000`– | `000` | `WE3M_1` (byte lanes) |

Anything else reads through `RDsel = 101` with no write enable. UART, PLIC, CLINT and GPIO are not connected
yet (their read data is 0 and their write enables are left open in `cpu.vhd`).

Instruction fetch: `interselmux` takes the boot ROM when the PC is in the ROM range, the RAM when
PC ≥ `0x8000_0000`, and `0x00000000` otherwise. Load data goes through `ReadDatamux`.

The RAM and ROM index with `address mod size`, so e.g. a store to the ROM range would hit a RAM word if
MMIO did not block it.

## Run the tests

```sh
./tb_ci_cd/run.sh          # all block tests, prints PASS/FAIL per test, exit code 1 on failure
```

Needs `ghdl` (VHDL-2008). A new test = a new `tb_ci_cd/<name>_tb.vhd` file, it is picked up automatically.
A new RTL file must be added to the `RTL=` list in `run.sh` (in dependency order) and to `ci.yml`.

Fibonacci program on the whole CPU (the university task), expects fib(20) = 6765 in a0:

```sh
cd tb_uni
for f in ControlUnit ImmGen PCPlus4 PCTarget MuxJalr ZeroGen Pc_mux alu alu_mux SrcAMux result_mux pc riscvregfile controlblock DataPath WriteBlock ReadBlock core unifiedmem bootrom MMIO interselmux ReadDatamux cpu; do ghdl -a --std=08 ../rtl/$f.vhd; done
ghdl -a --std=08 cpu_fib_tb.vhd && ghdl --elab-run --std=08 cpu_fib_tb --assert-level=error
```

## What is tested (`tb_ci_cd`)

| Test | Covers |
|------|--------|
| `alu_tb` | every ALU operation, 65k random operand pairs, zero flag |
| `controlunit_tb` | **all** 131 072 opcode/funct3/funct7 combinations vs. a reference table |
| `controlblock_tb` | PCsrc for every opcode/funct3/zero, example instructions |
| `immgen_tb` | I, S, B, J and U immediates for 20k random instructions |
| `riscvregfile_tb` | 5000 random writes/reads vs. model, x0 hard-wired to 0, write enable |
| `readblock_tb` | exhaustive funct3 × address offset: lb/lh/lw/lbu/lhu selection, sign/zero extension, misaligned → 0 |
| `writeblock_tb` | exhaustive MemWrite × funct3 × offset: sb/sh/sw byte enables and data lanes, misaligned → no write |
| `small_blocks_tb` | `pc` (reset to `0x1000`), `PCPlus4`, `PCTarget`, `Pc_mux`, `alu_mux`, `SrcAMux` |
| `datapath_tb` | datapath with hand-driven control signals |
| `core_tb` | ~1000-instruction random program at `0x1000` (R, I, loads, stores, beq/bne, jal/jalr, lui/auipc) vs. an RV32I software model: PC, ALU result, registers, store byte enables/data every cycle |
| `bootrom_tb` | `boot.hex` at `0x1000` (`lui x5,0x80000` ; `jalr x0,0(x5)`) on the instruction and data ports, wraparound |
| `unifiedmem_tb` | file loading, PC wraparound, every byte-enable combination, data writes visible on the instruction port |
| `mmio_tb` | `MMIO` decode of every region and its edges, write enables, `interselmux` and `ReadDatamux` selection |
| `cpu_boot_tb` | whole `cpu`: boot `0x1000` → `0x1004` → `0x8000_0000`, then `hex.hex`: ROM read via `lw`, RAM store/load, store to ROM is dropped, `auipc` in RAM, halt |

`cpu_boot_tb` and `cpu_fib_tb` read the PC and register writes through VHDL-2008 external names
(`<<signal .tb.dut.... >>`), since `cpu` only exposes `RezOUT` and `Illegal`.

CI (`.github/workflows/ci.yml`) runs `tb_ci_cd/run.sh` and the fibonacci test on every push / pull request.
