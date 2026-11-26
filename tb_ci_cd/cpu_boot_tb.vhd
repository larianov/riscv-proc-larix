library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Whole cpu: reset -> boot ROM (boot.hex) -> jump to RAM (hex.hex) -> run the program below.
-- PC and register writes are observed through VHDL-2008 external names; a shadow register file
-- is rebuilt from the regfile write port.
--
-- boot.hex (0x1000)          hex.hex (0x8000_0000)
--   800002B7 lui  x5,0x80000    00001337 lui   x6, 0x1          x6  = 0x1000
--   00028067 jalr x0,0(x5)      00032383 lw    x7, 0(x6)        x7  = 800002B7 (ROM via data port)
--                               80000437 lui   x8, 0x80000      x8  = 0x8000_0000
--                               12300493 addi  x9, x0, 0x123    x9  = 0x123
--                               10942023 sw    x9, 0x100(x8)    RAM[0x8000_0100] = 0x123
--                               10042503 lw    x10, 0x100(x8)   x10 = 0x123
--                               00932023 sw    x9, 0(x6)        store to ROM: must be dropped
--                               00032583 lw    x11, 0(x6)       x11 = 800002B7
--                               00042683 lw    x13, 0(x8)       x13 = 00001337 (RAM word 0 aliases 0x1000 mod size: not clobbered)
--                               00000617 auipc x12, 0           x12 = 0x8000_0024
--                               00000063 beq   x0, x0, 0        halt at 0x8000_0028
entity cpu_boot_tb is
end entity;

architecture sim of cpu_boot_tb is
    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal Illegal : std_logic;
    signal rez     : std_logic_vector(31 downto 0);

    type reg_array is array (0 to 31) of std_logic_vector(31 downto 0);
    signal regs : reg_array := (others => (others => '0'));

    constant HALT : std_logic_vector(31 downto 0) := x"80000028";
begin
    clk <= not clk after 5 ns;

    dut : entity work.cpu
        port map(clk => clk, rst => rst, Illegal => Illegal, irq => '0', RezOUT => rez);

    -- shadow register file
    shadow : process(clk)
        alias we  is <<signal .cpu_boot_tb.dut.core_inst.DataPath_inst.riscvregfile_inst.write_en  : std_logic>>;
        alias idx is <<signal .cpu_boot_tb.dut.core_inst.DataPath_inst.riscvregfile_inst.write_idx : std_logic_vector(4 downto 0)>>;
        alias wd  is <<signal .cpu_boot_tb.dut.core_inst.DataPath_inst.riscvregfile_inst.write_In  : std_logic_vector(31 downto 0)>>;
    begin
        if rising_edge(clk) and rst = '0' and we = '1' and unsigned(idx) /= 0 then
            regs(to_integer(unsigned(idx))) <= wd;
        end if;
    end process;

    process
        alias PC is <<signal .cpu_boot_tb.dut.PC_s : std_logic_vector(31 downto 0)>>;

        procedure expect_reg(r : integer; v : std_logic_vector(31 downto 0)) is
        begin
            assert regs(r) = v report "x" & integer'image(r) & " = " & to_hstring(regs(r)) &
                                      " expected " & to_hstring(v) severity error;
        end procedure;
    begin
        wait until falling_edge(clk);
        assert PC = x"00001000" report "reset vector must be 0x1000, got " & to_hstring(PC) severity error;
        rst <= '0';

        -- boot sequence
        assert Illegal = '0' report "boot instr 0 illegal" severity error;
        wait until falling_edge(clk);
        assert PC = x"00001004" report "boot: PC must be 0x1004, got " & to_hstring(PC) severity error;
        assert Illegal = '0' report "boot instr 1 illegal" severity error;
        wait until falling_edge(clk);
        assert PC = x"80000000" report "boot: jalr must land at 0x8000_0000, got " & to_hstring(PC) severity error;
        expect_reg(5, x"80000000");

        -- program in RAM
        for i in 1 to 40 loop
            assert Illegal = '0' report "Illegal at PC " & to_hstring(PC) severity error;
            exit when PC = HALT;
            wait until falling_edge(clk);
        end loop;
        assert PC = HALT report "did not reach halt, PC = " & to_hstring(PC) severity error;
        for i in 1 to 3 loop
            wait until falling_edge(clk);
            assert PC = HALT report "left the halt loop" severity error;
        end loop;

        expect_reg(6,  x"00001000");
        expect_reg(7,  x"800002B7");
        expect_reg(8,  x"80000000");
        expect_reg(9,  x"00000123");
        expect_reg(10, x"00000123");
        expect_reg(11, x"800002B7");
        expect_reg(12, x"80000024");
        expect_reg(13, x"00001337");

        report "cpu_boot_tb done";
        std.env.finish;
    end process;
end architecture;
