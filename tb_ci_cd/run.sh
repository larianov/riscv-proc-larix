#!/bin/sh
# Compile rtl + run every testbench in this folder. Fails on the first error.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d)
RTL="ControlUnit ImmGen PCPlus4 PCTarget Pc_mux alu alu_mux pc riscvregfile instruction_memory controlblock DataPath core cpu"
for f in $RTL; do ghdl -a --std=08 --workdir=$W ../rtl/$f.vhd; done
for tb in alu riscvregfile instruction_memory controlblock datapath core; do
    ghdl -a --std=08 --workdir=$W ${tb}_tb.vhd
    echo "== ${tb}_tb"
    ghdl --elab-run --std=08 --workdir=$W ${tb}_tb --assert-level=error
done
rm -rf $W
echo "ALL PASSED"
