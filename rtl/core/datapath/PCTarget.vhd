library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity PCTarget is
    port(
        PC : in std_logic_vector(31 downto 0);
        offset : in std_logic_vector(31 downto 0);
        PCOFFSET: out std_logic_vector(31 downto 0) 
    );
end entity PCTarget;

architecture RTL of PCTarget is
begin
    PCOFFSET <= STD_LOGIC_VECTOR(UNSIGNED(PC) + UNSIGNED(offset));
end architecture RTL;

