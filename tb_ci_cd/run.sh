#!/bin/sh
# Regression for tb_ci_cd: every <name>_tb.vhd in this folder, then the docs check.
#
#   ./run.sh                     all testbenches
#   ./run.sh alu_tb core_tb      only these
#   SEEDS="1 2 3" ./run.sh       seeds for testbenches with a G_SEED generic (default "1 2 3")
#   WALL=600 ./run.sh            wall-clock limit per run in seconds (default 300)
#
# A run is PASS only if all three hold: exit code 0, the "TEST PASSED" marker printed by
# tb_finish (tb_pkg.vhd), and no "[ERROR]" line. Silence is not success: a crash, an early stop
# or a hang has no marker and is a FAIL.
#
# The RTL is VHDL-93 (the .qsf has no VHDL_INPUT_VERSION, so Quartus compiles it as 93). Step 1
# proves that with --std=93c; step 2 analyzes everything as VHDL-2008 for simulation (the
# testbenches need 2008: protected types, external names, std.env.finish).
#
# New testbench = drop <name>_tb.vhd here (entity name = file name). New RTL file = add it to
# RTL below (dependency order), to ci.yml, and draw it in docs/cpu.html.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
SEEDS=${SEEDS:-"1 2 3"}
WALL=${WALL:-300}
TIMEOUT=""
command -v timeout > /dev/null 2>&1 && TIMEOUT="timeout $WALL"

RTL="core/control/ControlUnit core/datapath/ImmGen core/datapath/PCPlus4 core/datapath/PCTarget core/datapath/MuxJalr core/datapath/ZeroGen core/datapath/Pc_mux core/datapath/alu core/datapath/alu_mux core/datapath/SrcAMux core/datapath/pc core/datapath/riscvregfile core/control/controlblock core/datapath/result_mux core/datapath/CSRblock core/datapath/DataPath core/WriteBlock core/ReadBlock core/core unifiedmem bootrom MMIO interselmux ReadDatamux cpu"

# 1) the RTL must be valid VHDL-93 (std_logic_textio needs -fsynopsys in 93 mode)
mkdir "$W/v93"
for f in $RTL; do
    if ! ghdl -a --std=93c -fsynopsys --workdir="$W/v93" "../rtl/$f.vhd" > "$W/log" 2>&1; then
        echo "rtl/$f.vhd is not valid VHDL-93 (Quartus compiles it as 93):"
        grep -v '^\s*$' "$W/log" | head -15
        exit 1
    fi
done

# 2) analyze RTL + the testbench packages as VHDL-2008
for f in $RTL; do
    ghdl -a --std=08 --workdir="$W" "../rtl/$f.vhd" > "$W/log" 2>&1 ||
        { echo "cannot compile rtl/$f.vhd"; cat "$W/log"; exit 1; }
done
for f in tb_pkg.vhd riscv_ref_pkg.vhd; do
    ghdl -a --std=08 --workdir="$W" "$f" > "$W/log" 2>&1 ||
        { echo "cannot compile $f"; cat "$W/log"; exit 1; }
done

tests=$*
[ -z "$tests" ] && tests=$(ls ./*_tb.vhd | sed 's|^\./||; s|\.vhd$||')

fail=0
for tb in $tests; do
    if ! ghdl -a --std=08 --workdir="$W" "$tb.vhd" > "$W/log" 2>&1 ||
       ! ghdl -e --std=08 --workdir="$W" "$tb" >> "$W/log" 2>&1; then
        printf '%-34s FAIL (does not compile)\n' "$tb"
        head -20 "$W/log"
        fail=1
        continue
    fi
    seeds=-
    grep -qi 'G_SEED' "$tb.vhd" && seeds=$SEEDS
    for s in $seeds; do
        if [ "$s" = - ]; then label=$tb; gen=""; else label="$tb seed=$s"; gen="-gG_SEED=$s"; fi
        printf '%-34s ' "$label"
        # shellcheck disable=SC2086
        $TIMEOUT ghdl -r --std=08 --workdir="$W" "$tb" $gen --ieee-asserts=disable-at-0 > "$W/log" 2>&1
        rc=$?
        errors=$(grep -c '^\[ERROR\]' "$W/log")
        xerrs=$(grep -c '^\[XERR \]' "$W/log")
        checks=$(sed -n 's/^\[DONE \] .*  \([0-9]*\) checks.*/\1/p' "$W/log" | tail -1)
        if [ $rc -eq 0 ] && [ "$errors" -eq 0 ] && grep -q 'TEST PASSED' "$W/log"; then
            echo "PASS  ($checks checks, $xerrs injected errors caught)"
        else
            if [ $rc -eq 124 ]; then echo "FAIL  (wall-clock timeout ${WALL}s)"
            elif grep -q 'TEST FAILED' "$W/log"; then echo "FAIL  ($errors errors)"
            else echo "FAIL  (exit $rc, no TEST PASSED marker)"; fi
            grep -E '^\[(ERROR|EXPCT|DONE )\]|error|failure' "$W/log" | head -20
            fail=1
        fi
    done
done

if [ -z "$*" ]; then
    printf '%-34s ' "docs/cpu.html"
    sh ./check_docs.sh || fail=1
fi

[ $fail -eq 0 ] && echo "ALL PASSED" || echo "SOME TESTS FAILED"
exit $fail
