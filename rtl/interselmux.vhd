library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity interselmux is
    port(
        instr_boot : in std_logic_vector(31 downto 0);
        instr_ram : in std_logic_vector(31 downto 0);
        S : in std_logic_vector(1 downto 0);
        instr_R : out std_logic_vector(31 downto 0)
    );
end entity interselmux;

architecture RTL of interselmux is
begin
    instr_R <= instr_boot when S = "00" else instr_ram when S = "01" else (others => '0');
end architecture RTL;

