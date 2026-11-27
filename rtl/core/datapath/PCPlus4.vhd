library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity PCPlus4 is
    port(
        PC : IN std_logic_vector(31 downto 0);
        PC_O : out std_logic_vector(31 downto 0)
    );
end entity PCPlus4;

architecture RTL of PCPlus4 is
begin
    PC_O <= STD_LOGIC_VECTOR(UNSIGNED(PC)+4);
end architecture RTL;

