library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cpu_fib_tb is
end entity;

architecture sim of cpu_fib_tb is
    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal Illegal : std_logic;
    signal rez     : std_logic_vector(31 downto 0);

    constant HALT_PC  : std_logic_vector(31 downto 0) := x"00000024";
    constant MV_A0_PC : std_logic_vector(31 downto 0) := x"00000010";  -- mv a0, a3
    constant FIB20    : integer := 6765;
begin

    dut : entity work.core
        port map(rst => rst, clk => clk, Illegal => Illegal, rez => rez);

    clk <= not clk after 5 ns;

    process
        alias PC is << signal .cpu_fib_tb.dut.PC : std_logic_vector(31 downto 0) >>;
        variable a0     : integer := -1;
        variable cycles : integer := 0;
    begin
        rst <= '1';
        wait until falling_edge(clk);
        wait until falling_edge(clk);
        rst <= '0';

        -- run until the program reaches the halt loop (or give up)
        while PC /= HALT_PC and cycles < 1000 loop
            assert Illegal /= '1'
                report "Illegal instruction at PC = " & to_hstring(PC) severity error;
            if PC = MV_A0_PC then
                a0 := to_integer(signed(rez));   -- value written to a0
            end if;
            wait until falling_edge(clk);
            cycles := cycles + 1;
        end loop;

        assert PC = HALT_PC
            report "never reached halt at 0x24, PC = " & to_hstring(PC) severity failure;
        report "reached halt after " & integer'image(cycles) & " cycles";

        assert a0 = FIB20
            report "a0 = " & integer'image(a0) & ", expected " & integer'image(FIB20) severity error;

        -- halt loop must keep PC at 0x24
        for i in 1 to 3 loop
            wait until falling_edge(clk);
            assert PC = HALT_PC
                report "PC left the halt loop: " & to_hstring(PC) severity error;
        end loop;

        report "done, a0 = " & integer'image(a0);
        std.env.finish;
    end process;

end architecture;