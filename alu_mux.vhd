library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity alu_mux is
    port(
        rd2 : in std_logic_vector(31 downto 0);
        imm : in std_logic_vector(31 downto 0);
        S : in std_logic;
        muxout : out std_logic_vector(31 downto 0)
    );
end entity alu_mux;

architecture RTL of alu_mux is
begin
    muxout <= rd2 when S = '0' else imm;
end architecture RTL;
