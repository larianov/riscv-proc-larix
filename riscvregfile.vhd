library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity riscvregfile is
    port(
        clk             : in  std_logic;
        read_out_first  : out std_logic_vector(31 downto 0);
        read_idx_first  : in  integer range 0 to 31;
        read_out_second : out std_logic_vector(31 downto 0);
        read_idx_second : in  integer range 0 to 31;
        write_en        : in  std_logic;
        write_In        : in  std_logic_vector(31 downto 0);
        write_idx       : in  integer range 0 to 31
    );
end entity riscvregfile;

architecture RTL of riscvregfile is
    type   MemRam    is array (31 downto 0) of std_logic_vector(31 downto 0);
    signal mem_array : MemRam := (others => (others => '0'));
begin
    clocking : process(clk) is
    begin
        if rising_edge(clk) then
            if write_en = '1' and write_idx /= 0 then
                mem_array(write_idx) <= write_In;
            end if;
        end if;
    end process clocking;
    read_out_first  <= mem_array(read_idx_first);
    read_out_second <= mem_array(read_idx_second);
end architecture RTL;
