library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ZeroGen is
    port(
        INP : in std_logic_vector(31 downto 0);
        OUTP : out std_logic_vector(31 downto 0)
    );
end entity ZeroGen;


architecture RTL of ZeroGen is
begin
    OUTP <= INP(31 downto 1) & '0';
end architecture RTL;
