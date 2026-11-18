#!/bin/sh
# Compile ../rtl and run EVERY *_tb.vhd in this folder. Exit code != 0 if anything fails.
# New testbench = just drop a <name>_tb.vhd here (entity name must match the file name).
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

RTL="ControlUnit ImmGen PCPlus4 PCTarget Pc_mux alu alu_mux pc riscvregfile instruction_memory controlblock result_mux DataPath WriteBlock ReadBlock core memory_data cpu"
for f in $RTL; do
    ghdl -a --std=08 --workdir="$W" ../rtl/$f.vhd 2>/dev/null || { echo "cannot compile rtl/$f.vhd"; exit 1; }
done

fail=0
for t in *_tb.vhd; do
    tb=${t%.vhd}
    printf '%-24s' "$tb"
    if ghdl -a --std=08 --workdir="$W" "$t" > "$W/log" 2>&1 &&
       ghdl --elab-run --std=08 --workdir="$W" "$tb" --assert-level=error >> "$W/log" 2>&1; then
        echo PASS
    else
        echo FAIL
        grep -v metavalue "$W/log" | tail -15
        fail=1
    fi
done

[ $fail -eq 0 ] && echo "ALL PASSED" || echo "SOME TESTS FAILED"
exit $fail
