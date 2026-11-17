# RISC-V single-cycle CPU (VHDL)

| Folder       | Content |
|--------------|---------|
| `rtl/`       | CPU source (`.vhd`) |
| `tb_ci_cd/`  | Automatic tests, one per block, run by CI |
| `tb_uni/`    | Testbenches for the university task (fibonacci program in `hex.hex`) |
| `quartus/`   | Quartus project |
| `outdated/`  | Old, unused files |

## Run the tests

```sh
./tb_ci_cd/run.sh          # all block tests, prints PASS/FAIL per test, exit code 1 on failure
```

Needs `ghdl` (VHDL-2008). A new test = a new `tb_ci_cd/<name>_tb.vhd` file, it is picked up automatically.

Fibonacci program on the whole CPU (the university task):

```sh
cd tb_uni
for f in ControlUnit ImmGen PCPlus4 PCTarget Pc_mux alu alu_mux pc riscvregfile instruction_memory controlblock DataPath core cpu; do ghdl -a --std=08 ../rtl/$f.vhd; done
ghdl -a --std=08 cpu_fib_tb.vhd && ghdl --elab-run --std=08 cpu_fib_tb
```

## What is tested (`tb_ci_cd`)

| Test | Covers |
|------|--------|
| `alu_tb` | every ALU operation, 65k random operand pairs, zero flag |
| `controlunit_tb` | **all** 131 072 opcode/funct3/funct7 combinations vs. a reference table |
| `controlblock_tb` | PCsrc for every opcode/funct3/zero, example instructions |
| `immgen_tb` | I- and B-immediates for 20k random instructions |
| `riscvregfile_tb` | 5000 random writes/reads vs. model, x0 hard-wired to 0, write enable |
| `instruction_memory_tb` | file loading, NOP outside the program |
| `small_blocks_tb` | `pc`, `PCPlus4`, `PCTarget`, `Pc_mux`, `alu_mux` |
| `datapath_tb` | datapath with hand-driven control signals |
| `core_tb` | ~1000-instruction random program (R, I, beq/bne) vs. an RV32I software model: PC, ALU result every cycle |

CI (`.github/workflows/ci.yml`) runs `tb_ci_cd/run.sh` and the fibonacci test on every push / pull request.
