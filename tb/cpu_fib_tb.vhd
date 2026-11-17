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
    signal PC      : std_logic_vector(31 downto 0);
begin
    dut : entity work.cpu
        port map(clk => clk, 
            rst => rst,
            Illegal => Illegal, 
            rez => rez,
            PC => PC);

    clk <= not clk after 5 ns;

    process
    begin
        wait for 20 ns;
        rst <= '0';
        for i in 1 to 1000 loop
            wait until falling_edge(clk);
        end loop;
        std.env.finish;
    end process;
end architecture;
