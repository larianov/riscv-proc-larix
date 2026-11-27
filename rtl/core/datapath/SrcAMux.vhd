library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SrcAMux is
    port(
        SrcA : in std_logic_vector(31 downto 0);
        PC : in std_logic_vector(31 downto 0);
        S : in std_logic_vector(1 downto 0);
        Y : out std_logic_vector(31 downto 0));
end entity SrcAMux;


architecture RTL of SrcAMux is
begin
    Y <= SrcA when S = "00" else -- rs1
         PC when S = "01" else -- AUIPC
         (others => '0'); -- LUI
end architecture RTL;

