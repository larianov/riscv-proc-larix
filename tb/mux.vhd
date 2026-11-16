library ieee;
use ieee.std_logic_1164.all;

entity cpu_tb is
end entity;

architecture sim of cpu_tb is
    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal Illegal : std_logic;
    signal rez     : std_logic_vector(31 downto 0);
begin

    dut : entity work.cpu
        port map(rst => rst, clk => clk, Illegal => Illegal, rez => rez);

    clk <= not clk after 5 ns;

    process
    begin
        rst <= '1'; wait for 20 ns;
        rst <= '0'; wait for 2000 ns;
        std.env.finish;
    end process;

end architecture;