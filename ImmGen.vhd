library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ImmGen is
    port(
        imm : in std_logic_vector(11 downto 0);
        imm_out : out std_logic_vector(31 downto 0)
    );
end entity ImmGen;

architecture RTL of ImmGen is
begin
    imm_out <= (31 downto 12 => (imm(11))) & (imm);   
end architecture RTL;

