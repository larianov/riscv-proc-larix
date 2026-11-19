library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ImmGen is
    port(
        imm : in std_logic_vector(31 downto 0);
        imm_src : in std_logic_vector(2 downto 0);
        imm_out : out std_logic_vector(31 downto 0)
    );
end entity ImmGen;

architecture RTL of ImmGen is
begin
    
    imm_out <= (31 downto 12 => (imm(31))) & (imm(31 downto 20)) when imm_src = "000" else 
               (31 downto 13 => (imm(31))) & (imm(31)) & imm(7) & imm(30 downto 25) & imm(11 downto 8) & '0' when imm_src = "010" else
               (31 downto 12 => (imm(31))) & (imm(31 downto 25)) & (imm(11 downto 7)) when imm_src = "001" else
               (31 downto 20 => (imm(31))) & (imm(19 downto 12) & imm(20) & imm(30 downto 21)) & '0' when imm_src = "011" else
               (imm(31 downto 12) & (11 downto 0 => ('0'))) when imm_src = "100" else
               (others => '0');    
end architecture RTL;

