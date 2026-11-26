#!/bin/sh
# Checks docs/cpu.html against the RTL (see check_docs.js). Needs ghdl and node.
#   - every entity / port / wire in the page model matches rtl/*.vhd
#   - the page's JS decoder == ControlUnit.vhd for every opcode/funct3/funct7(/rs1)
cd "$(dirname "$0")" || exit 1
if ! command -v node > /dev/null 2>&1; then
    echo "check_docs: node not found, SKIPPED"
    exit 0
fi
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
ghdl -a --std=08 --workdir="$W" ../rtl/ControlUnit.vhd controlunit_dump.vhd &&
    (cd "$W" && ghdl --elab-run --std=08 --workdir="$W" controlunit_dump > /dev/null) ||
    { echo "check_docs: cannot build the ControlUnit dump"; exit 1; }
node check_docs.js ../docs/cpu.html ../rtl "$W/controlunit_dump.txt"
