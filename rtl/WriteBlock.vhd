library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity WriteBlock is
    port(
        rd2 : in std_logic_vector(31 downto 0);
        addr_2_bits : in std_logic_vector(1 downto 0);
        Mem_Write : in STD_LOGIC;
        funct3 : in std_logic_vector(2 downto 0);
        WE : out std_logic_vector(3 downto 0);
        wD : out STD_LOGIC_VECTOR(31 downto 0)
    );
end entity WriteBlock;


architecture RTL of WriteBlock is
begin
    process(Mem_Write, addr_2_bits, funct3) 
    begin
        if Mem_Write = '0' then
            WE <= (others => '0');
        else
            if addr_2_bits = "00" and funct3 = "010" then 
                WE <= "1111";
            elsif addr_2_bits = "10" and funct3 = "001" then
                WE <= "1100";
            elsif addr_2_bits = "00" and funct3 = "001" then
                WE <= "0011";
            elsif addr_2_bits = "11" and funct3 = "000" then
                WE <= "1000";
            elsif addr_2_bits = "10" and funct3 = "000" then
                WE <= "0100";
            elsif addr_2_bits = "01" and funct3 = "000" then
                WE <= "0010";
            elsif addr_2_bits = "00" and funct3 = "000" then
                WE <= "0001";
            else
                WE <= "0000";
            end if;
        end if;
    end process;

    wD <= rd2 when funct3 = "010" else
          rd2(7 downto 0) & rd2(7 downto 0) & rd2(7 downto 0) & rd2(7 downto 0) when funct3 = "000" else
           rd2(15 downto 0) & rd2(15 downto 0) when funct3 = "001" else rd2;

end architecture RTL;
