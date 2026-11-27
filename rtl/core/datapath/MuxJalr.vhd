library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity MuxJalr is
    port(
        PC_NOW : in std_logic_vector(31 downto 0);
        RD1 : in std_logic_vector(31 downto 0);
        JalrReg : in STD_LOGIC;
        PCtarget_IN : out std_logic_vector(31 downto 0)
    );
end entity MuxJalr;

architecture RTL of MuxJalr is
begin
    PCtarget_IN <= PC_NOW when JalrReg = '0' else
                   RD1;
end architecture RTL;   
