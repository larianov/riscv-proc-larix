library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pc is
    port(
        clk : in std_logic;
        rst : in std_logic;
        PCNext : in std_logic_vector(31 downto 0);
        PC : out std_logic_vector(31 downto 0)
    );
end entity pc;


architecture RTL of pc is
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                PC <= (others => '0');
            else
                PC <= PCNext;
            end if;
        end if;
    end process;
end architecture RTL;
