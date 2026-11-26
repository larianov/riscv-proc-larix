library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity core_irq_tb is
end entity;

architecture sim of core_irq_tb is
    type rom_t is array (natural range <>) of std_logic_vector(31 downto 0);
    constant MAIN : rom_t(0 to 8) := (
        x"000010B7",
        x"10008093",
        x"30509073",
        x"80000113",
        x"30412073",
        x"00800193",
        x"3001A073",
        x"00120213",
        x"FFDFF06F");
    constant HANDLER : rom_t(0 to 3) := (
        x"00128293",
        x"34202373",
        x"341023F3",
        x"30200073");
    constant LOOP_ADD : std_logic_vector(31 downto 0) := x"0000101C";
    constant LOOP_JAL : std_logic_vector(31 downto 0) := x"00001020";
    constant VEC      : std_logic_vector(31 downto 0) := x"00001100";

    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal irq     : std_logic := '0';
    signal instr   : std_logic_vector(31 downto 0);
    signal PC      : std_logic_vector(31 downto 0);
    signal Illegal : std_logic;
    signal rez, WD : std_logic_vector(31 downto 0);
    signal WE      : std_logic_vector(3 downto 0);

    type reg_array is array (0 to 31) of std_logic_vector(31 downto 0);
    signal regs : reg_array := (others => (others => '0'));
    signal x4_writes : natural := 0;
begin
    clk <= not clk after 5 ns;

    fetch : process(PC)
        variable a : integer;
    begin
        a := to_integer(unsigned(PC(15 downto 0)));
        if PC(31 downto 16) = x"0000" and a >= 16#1000# and a < 16#1000# + 4 * MAIN'length then
            instr <= MAIN((a - 16#1000#) / 4);
        elsif PC(31 downto 16) = x"0000" and a >= 16#1100# and a < 16#1100# + 4 * HANDLER'length then
            instr <= HANDLER((a - 16#1100#) / 4);
        else
            instr <= x"00000013";
        end if;
    end process;

    dut : entity work.core
        port map(rst => rst, clk => clk, irq => irq, instr => instr, PC => PC, Illegal => Illegal,
                 rez => rez, OUT_OF_MEMORY_DATA => x"00000000", WD => WD, WE => WE);

    shadow : process(clk)
        alias we  is <<signal .core_irq_tb.dut.DataPath_inst.riscvregfile_inst.write_en  : std_logic>>;
        alias idx is <<signal .core_irq_tb.dut.DataPath_inst.riscvregfile_inst.write_idx : std_logic_vector(4 downto 0)>>;
        alias wd  is <<signal .core_irq_tb.dut.DataPath_inst.riscvregfile_inst.write_In  : std_logic_vector(31 downto 0)>>;
    begin
        if rising_edge(clk) and rst = '0' and we = '1' and unsigned(idx) /= 0 then
            regs(to_integer(unsigned(idx))) <= wd;
            if unsigned(idx) = 4 then
                x4_writes <= x4_writes + 1;
            end if;
        end if;
    end process;

    process
        variable trapped_pc : std_logic_vector(31 downto 0);
        variable x4_before  : natural;

        procedure expect_reg(r : integer; v : std_logic_vector(31 downto 0)) is
        begin
            assert regs(r) = v report "x" & integer'image(r) & " = " & to_hstring(regs(r)) &
                                      " expected " & to_hstring(v) severity error;
        end procedure;

        procedure step is
        begin
            assert Illegal = '0' report "Illegal at PC " & to_hstring(PC) severity error;
            assert WE = "0000" report "unexpected store at PC " & to_hstring(PC) severity error;
            wait until falling_edge(clk);
        end procedure;
    begin
        wait until falling_edge(clk);
        rst <= '0';
        irq <= '1';

        for i in 0 to 6 loop
            assert PC = std_logic_vector(to_unsigned(16#1000# + 4 * i, 32))
                report "setup must not be interrupted while MIE/MEIE are 0, PC = " & to_hstring(PC) severity error;
            step;
        end loop;
        irq <= '0';
        expect_reg(1, VEC);
        expect_reg(2, x"FFFFF800");
        expect_reg(3, x"00000008");

        for i in 1 to 7 loop
            assert PC = LOOP_ADD or PC = LOOP_JAL report "main loop expected, PC = " & to_hstring(PC) severity error;
            step;
        end loop;
        assert x4_writes > 0 report "main loop did not run" severity error;
        while PC /= LOOP_ADD loop
            step;
        end loop;

        irq <= '1';
        trapped_pc := PC;
        x4_before := x4_writes;
        wait until falling_edge(clk);
        assert PC = VEC report "irq must jump to mtvec 0x1100, PC = " & to_hstring(PC) severity error;
        assert x4_writes = x4_before report "the interrupted instruction must not write rd" severity error;

        for i in 0 to 2 loop
            assert PC = std_logic_vector(unsigned(VEC) + 4 * i)
                report "handler must not be re-entered while irq is held, PC = " & to_hstring(PC) severity error;
            step;
        end loop;
        assert PC = x"0000110C" report "mret expected, PC = " & to_hstring(PC) severity error;
        irq <= '0';
        step;
        assert PC = trapped_pc report "mret must return to " & to_hstring(trapped_pc) & ", PC = " &
                                      to_hstring(PC) severity error;
        expect_reg(5, x"00000001");
        expect_reg(6, x"8000000B");
        expect_reg(7, trapped_pc);

        for i in 1 to 4 loop
            assert PC = LOOP_ADD or PC = LOOP_JAL report "back in main loop, PC = " & to_hstring(PC) severity error;
            step;
        end loop;
        assert x4_writes > x4_before report "main loop must continue after mret" severity error;

        irq <= '1';
        trapped_pc := PC;
        wait until falling_edge(clk);
        assert PC = VEC report "second irq must trap again (MIE restored by mret)" severity error;
        irq <= '0';
        for i in 1 to 4 loop
            step;
        end loop;
        assert PC = trapped_pc report "second mret, PC = " & to_hstring(PC) severity error;
        expect_reg(5, x"00000002");
        expect_reg(7, trapped_pc);

        report "core_irq_tb done";
        std.env.finish;
    end process;
end architecture;
