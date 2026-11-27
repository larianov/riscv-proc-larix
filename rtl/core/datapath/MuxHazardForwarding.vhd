library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity MuxHazardForwarding is
    port(
        S : in std_logic_vector(1 downto 0);
        Orig : in std_logic_vector(31 downto 0);
        Result_W : in std_logic_vector(31 downto 0);
        Alu_Result_M : in std_logic_vector(31 downto 0);
        OutP : out std_logic_vector(31 downto 0)
    );
end entity MuxHazardForwarding;

architecture RTL of MuxHazardForwarding is
begin
    OutP <= Orig when S = "00" else 
            Result_W when S = "01" else
            Alu_Result_M when s = "10" else
            (others => '0');
end architecture RTL;

