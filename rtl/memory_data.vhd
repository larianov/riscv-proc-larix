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
        WE : in std_logic;
        RD : out std_logic_vector(31 downto 0)
    );
end entity memory_data;

architecture RTL of memory_data is
    type memory is array(0 to size-1) of std_logic_vector(31 downto 0);
    signal mem_array : memory := (others => (others => '0'));
    signal index : integer range 0 to size-1 := 0;
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if WE = '1' then
                mem_array(index) <= wD;
            end if;
        end if;
    end process;
    index <= TO_INTEGER(SHIFT_RIGHT((UNSIGNED(address)), 2)) mod size;
    RD <= mem_array(index);
end architecture RTL;
