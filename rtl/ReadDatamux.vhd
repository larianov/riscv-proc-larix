library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ReadDatamux is
    port(
        S : in std_logic_vector(2 downto 0);
        MEMRAM : in std_logic_vector(31 downto 0);
        MEMROM : in std_logic_vector(31 downto 0);
        UART : in std_logic_vector(31 downto 0);
        PLIC : in std_logic_vector(31 downto 0);
        CLINT : in std_logic_vector(31 downto 0);
        GPIO : in std_logic_vector(31 downto 0);
        ReadData : out std_logic_vector(31 downto 0)
    );
end entity ReadDatamux;

architecture RTL of ReadDatamux is
begin
    ReadData <= MEMRAM when S = "000" else
                MEMROM when S = "001" else
                UART when S = "010" else
                PLIC when S = "011" else
                CLINT when S = "100" else
                GPIO when S = "101" else
                (others => '0');
end architecture RTL;

