library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Pc_mux is
    port(
        PCPlus4 : in std_logic_vector(31 downto 0);
        PCL : in std_logic_vector(31 downto 0);
        S : in std_logic;
        PCOUT : out std_logic_vector(31 downto 0)
    );
end entity Pc_mux;

architecture RTL of Pc_mux is
begin
    PCOUT <= PCPlus4 when S = '0' else PCL;
end architecture RTL;

