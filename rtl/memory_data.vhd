library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity memory_data is
    generic(
        size : integer := 32
    );
    port(
        clk : in std_logic;
        address : in std_logic_vector(31 downto 0);
        wD : in std_logic_vector(31 downto 0);
        WE : in std_logic_vector(3 downto 0);
        RD : out std_logic_vector(31 downto 0)
    );
end entity memory_data;

architecture RTL of memory_data is
    type memory is array(0 to size-1) of std_logic_vector(31 downto 0);
    signal mem_array : memory := (others => (others => '0'));
    signal index : integer range 0 to size-1 := 0;
begin
    process(clk)
        variable temp_we : std_logic_vector(31 downto 0) := (others => '0');
        
    begin
        if rising_edge(clk) then
            if we /= "0000" then
                temp_we := mem_array(index);
                if WE(0) = '1' then
                    temp_we(7 downto 0) := wD(7 downto 0);
                end if;
                if WE(1) = '1' then
                    temp_we(15 downto 8) := wD(15 downto 8);
                end if;       
                if WE(2) = '1' then
                    temp_we(23 downto 16) := wD(23 downto 16);
                end if;
                if WE(3) = '1' then
                    temp_we(31 downto 24) := wD(31 downto 24);
                end if;
                mem_array(index) <= temp_we;
            end if;                
        end if;
    end process;
    index <= TO_INTEGER(SHIFT_RIGHT((UNSIGNED(address)), 2)) mod size;
    RD <= mem_array(index);
end architecture RTL;
