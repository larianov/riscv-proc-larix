library ieee;
use ieee.std_logic_1164.all;

-- core + a tiny ROM written inline: addi x1,x0,5 ; addi x2,x1,3 ; beq x0,x0,0 (halt)
entity core_tb is
end entity;

architecture sim of core_tb is
    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal instr   : std_logic_vector(31 downto 0);
    signal PC      : std_logic_vector(31 downto 0);
    signal Illegal : std_logic;
    signal rez     : std_logic_vector(31 downto 0);
begin
    clk <= not clk after 5 ns;

    instr <= x"00500093" when PC = x"00000000" else
             x"00308113" when PC = x"00000004" else
             x"00000063";

    dut : entity work.core
        port map(rst => rst, clk => clk, instr => instr, PC => PC, Illegal => Illegal, rez => rez);

    process
    begin
        wait until falling_edge(clk);
        wait until falling_edge(clk);
        rst <= '0';
        wait until PC = x"00000004";
        wait for 1 ns;
        assert rez = x"00000008" report "x2 = x1 + 3 should be 8" severity error;
        wait until PC = x"00000008";
        wait for 20 ns;
        assert PC = x"00000008" report "halt loop broken" severity error;
        assert Illegal = '0' report "unexpected Illegal" severity error;
        report "core_tb done";
        std.env.finish;
    end process;
end architecture;
