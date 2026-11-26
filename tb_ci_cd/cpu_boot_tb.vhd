--------------------------------------------------------------------------------
-- cpu_boot_tb : whole-cpu testbench: boot ROM -> RAM program, memory map, reset mid-run
--
-- Spec: README "Boot and memory map", top-level ports, "Supported instructions".
--   F1 reset: PC = 0x0000_1000; boot.hex runs lui x5,0x80000 ; jalr x0,0(x5) -> 0x8000_0000
--   F2 instructions come from the boot ROM at 0x1000 and from RAM (hex.hex) at 0x8000_0000
--   F3 loads read the ROM through the data port; RAM stores/loads with byte lanes merge
--      correctly (sw, then sb and sh into the same word); misaligned lh reads 0
--   F4 a store to the ROM range is dropped: ROM unchanged, and the RAM word it aliases
--      (address mod RAM size) is not clobbered
--   F5 RezOUT = ALU result of the current instruction; Illegal stays 0
--   F6 reset in the middle of a run restarts the boot sequence and the program
--
-- hex.hex (RAM, 0x8000_0000):
--   00 lui x6,0x1          x6  = 0x1000            12 sb  x9,0x105(x8)    lane 1 = 0x23
--   04 lw  x7,0(x6)        x7  = ROM[0] 800002B7   13 sh  x9,0x106(x8)    lanes 3..2 = 0x0123
--   08 lui x8,0x80000      x8  = 0x8000_0000       14 lw  x15,0x104(x8)   x15 = 012323FF
--   0C addi x9,x0,0x123    x9  = 0x123             15 lbu x16,0x105(x8)   x16 = 0x23
--   10 sw  x9,0x100(x8)                            16 lh  x17,0x107(x8)   misaligned: x17 = 0
--   14 lw  x10,0x100(x8)   x10 = 0x123             17 lb  x18,0x104(x8)   x18 = FFFFFFFF
--   18 sw  x9,0(x6)        store to ROM: dropped   18..31 add x0,xN,x0    N = 5..18: xN on RezOUT
--   1C lw  x11,0(x6)       x11 = 800002B7          32 beq x0,x0,0         halt at 0x8000_0080
--   20 lw  x13,0(x8)       x13 = 00001337 (RAM word 0 = alias of 0x1000, not clobbered)
--   24 auipc x12,0         x12 = 0x8000_0024
--   28 addi x14,x0,-1 ; 2C sw x14,0x104(x8)
-- Registers are checked black-box through the "add x0, xN, x0" dump on RezOUT. The PC is not
-- a cpu port, so it is read with a VHDL-2008 external name (white-box, read only).
-- Checking: a per-cycle trace (PC, RezOUT) written from the program above.
-- E1 wrong RezOUT prediction must be caught.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tb_pkg.all;

entity cpu_boot_tb is
    generic(
        G_INJECT : boolean := true
    );
end entity cpu_boot_tb;

architecture sim of cpu_boot_tb is
    subtype word_t is std_logic_vector(31 downto 0);
    constant C_PERIOD : time := 10 ns;
    constant C_TCO    : time := 1 ns;
    constant DONT     : word_t := (others => '-');

    type step_t is record
        pc  : word_t;
        rez : word_t;        -- DONT = not checked
    end record;
    type trace_t is array (natural range <>) of step_t;
    constant TRACE : trace_t := (
        (x"00001000", x"80000000"),   -- lui x5, 0x80000
        (x"00001004", DONT),          -- jalr x0, 0(x5)
        (x"80000000", x"00001000"),   -- lui x6
        (x"80000004", x"00001000"),   -- lw x7, 0(x6): address
        (x"80000008", x"80000000"),   -- lui x8
        (x"8000000C", x"00000123"),   -- addi x9
        (x"80000010", x"80000100"),   -- sw: address
        (x"80000014", x"80000100"),   -- lw x10
        (x"80000018", x"00001000"),   -- sw to ROM
        (x"8000001C", x"00001000"),   -- lw x11
        (x"80000020", x"80000000"),   -- lw x13
        (x"80000024", x"80000024"),   -- auipc x12
        (x"80000028", x"FFFFFFFF"),   -- addi x14, x0, -1
        (x"8000002C", x"80000104"),   -- sw x14
        (x"80000030", x"80000105"),   -- sb x9
        (x"80000034", x"80000106"),   -- sh x9
        (x"80000038", x"80000104"),   -- lw x15
        (x"8000003C", x"80000105"),   -- lbu x16
        (x"80000040", x"80000107"),   -- lh x17 (misaligned)
        (x"80000044", x"80000104"),   -- lb x18
        -- register dump: add x0, xN, x0 -> RezOUT = xN
        (x"80000048", x"80000000"),   -- x5
        (x"8000004C", x"00001000"),   -- x6
        (x"80000050", x"800002B7"),   -- x7  ROM word 0 via the data port
        (x"80000054", x"80000000"),   -- x8
        (x"80000058", x"00000123"),   -- x9
        (x"8000005C", x"00000123"),   -- x10 RAM store/load
        (x"80000060", x"800002B7"),   -- x11 ROM unchanged after the store to ROM
        (x"80000064", x"80000024"),   -- x12 auipc in RAM
        (x"80000068", x"00001337"),   -- x13 RAM word 0 not clobbered by the ROM store
        (x"8000006C", x"FFFFFFFF"),   -- x14
        (x"80000070", x"012323FF"),   -- x15 sw + sb + sh merged
        (x"80000074", x"00000023"),   -- x16 lbu
        (x"80000078", x"00000000"),   -- x17 misaligned lh reads 0
        (x"8000007C", x"FFFFFFFF"),   -- x18 lb sign-extends
        (x"80000080", x"00000000"),   -- halt: beq x0, x0, 0 (x0 - x0)
        (x"80000080", x"00000000"),
        (x"80000080", x"00000000"));

    signal clk     : std_logic;
    signal run     : boolean := true;
    signal done    : boolean := false;
    signal rst     : std_logic := '1';
    signal Illegal : std_logic;
    signal rez     : word_t;
begin
    clock    : tb_clock(clk, C_PERIOD, run);
    watchdog : tb_watchdog(done, 100 us);

    dut : entity work.cpu
        port map(clk => clk, rst => rst, Illegal => Illegal, irq => '0', RezOUT => rez);

    stimulus : process
        alias PC is <<signal .cpu_boot_tb.dut.PC_s : std_logic_vector(31 downto 0)>>;

        -- reset for 2 cycles, then run the trace; called right after a falling edge
        procedure run_trace(pass : string; inject_at : integer := -1) is
            variable exp : word_t;
        begin
            rst <= '1';
            wait until falling_edge(clk);
            wait until falling_edge(clk);
            rst <= '0';
            for k in TRACE'range loop
                wait for C_TCO;
                tb_check_equal(PC, TRACE(k).pc, pass & " step " & integer'image(k) & ": PC");
                tb_check_equal(Illegal, '0', pass & " step " & integer'image(k) & ": Illegal");
                exp := TRACE(k).rez;
                if k = inject_at then exp := not exp; end if;
                if exp /= DONT then
                    tb_check_equal(rez, exp, pass & " step " & integer'image(k) & " (PC " & to_str(PC) & "): RezOUT");
                end if;
                wait until falling_edge(clk);
            end loop;
        end procedure;
    begin
        tb_info("cpu_boot_tb");
        wait until falling_edge(clk);
        tb_info("T1: reset, boot ROM -> RAM program -> halt");
        run_trace("run 1");
        tb_info("T2: reset in the middle of the halt loop, everything again (RAM keeps its data)");
        run_trace("run 2");

        if G_INJECT then
            tb_expect_errors(1, "E1: wrong RezOUT prediction must be caught");
            run_trace("run 3", inject_at => 5);
            tb_end_expect;
        end if;

        done <= true;
        run  <= false;
        tb_finish;
        wait;
    end process stimulus;
end architecture sim;
