library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ReadBlock is
    port(
        Memory_Data : in std_logic_vector(31 downto 0);
        addr_2_bits : in std_logic_vector(1 downto 0);
        funct3 : in std_logic_vector(2 downto 0);
        ReadData : out std_logic_vector(31 downto 0)
    );
end entity ReadBlock;

architecture RTL of ReadBlock is
begin
    process(Memory_Data, addr_2_bits, funct3) 
        variable temp_addr : integer range 0 to 5 := 0;
        
    begin
        ReadData <= (others => '0');
        if funct3 = "010" then
            if addr_2_bits = "00" then
                ReadData <= Memory_Data;
            end if;
        elsif funct3 = "000" then
            temp_addr := TO_INTEGER(UNSIGNED(addr_2_bits));
            ReadData <= (23 downto 0 => Memory_Data(temp_addr*8+7)) & Memory_Data(temp_addr*8+7 downto temp_addr*8);
        elsif funct3 = "100" then
            temp_addr := TO_INTEGER(UNSIGNED(addr_2_bits));
            ReadData <= (23 downto 0 => '0') & Memory_Data(temp_addr*8+7 downto temp_addr*8);
        elsif funct3 = "001" then
            if addr_2_bits = "00" or addr_2_bits = "10" then
                temp_addr := TO_INTEGER(UNSIGNED(addr_2_bits));   
                ReadData <= (15 downto 0 => Memory_Data(temp_addr*8+15)) & Memory_Data((temp_addr+1)*8+7 downto (temp_addr+1)*8) &  Memory_Data((temp_addr)*8+7 downto (temp_addr)*8);                
            end if;         
        elsif funct3 = "101" then
            if addr_2_bits = "00" or addr_2_bits = "10" then
                temp_addr := TO_INTEGER(UNSIGNED(addr_2_bits));   
                ReadData <= (15 downto 0 => '0') & Memory_Data((temp_addr+1)*8+7 downto (temp_addr+1)*8) &  Memory_Data((temp_addr)*8+7 downto (temp_addr)*8);                
            end if;     
        end if;
    end process;
end architecture RTL;

