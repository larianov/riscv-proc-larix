library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity result_mux is
    port(
        Result_Src : in std_logic_vector(1 downto 0);
        RD : in std_logic_vector(31 downto 0);
        ALU_Res : in std_logic_vector(31 downto 0);
        PC_4 : in std_logic_vector(31 downto 0);
        Mux_Res : out std_logic_vector(31 downto 0);
    );
end entity result_mux;


architecture RTL of result_mux is
begin
    Mux_Res <= ALU_Res when Result_Src = "00" else
               RD when Result_Src = "01" else
               PC_4 when Result_Src = "10" else
               (others => '0');
end architecture RTL;
