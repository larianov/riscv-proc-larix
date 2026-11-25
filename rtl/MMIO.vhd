library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity MMIO is
    port(
        MemWrite : in std_logic_vector(3 downto 0);
        PC : in std_logic_vector(31 downto 0);
        address : in std_logic_vector(31 downto 0);
        WE3M_1 : out std_logic_vector(3 downto 0);
        WE3_2 : out std_logic_vector(3 downto 0);
        We_3 : out std_logic;
        We_4 : out std_logic;
        We_5 : out std_logic;
        RDsel : out std_logic_vector(2 downto 0);
        intersel : out std_logic_vector(1 downto 0)
    );
end entity MMIO;


architecture RTL of MMIO is
begin
    process(PC)
        begin
            if PC >= x"8000_0000" then
                intersel <= "01";
            elsif PC >= x"0000_1000" and PC <= x"0000_1FFF" then
                intersel <= "00";
            else
                intersel <= "10";
            end if;
        end process;
    process(MemWrite, address)
        begin
        RDsel <= "101";
        WE3M_1 <= "0000";
        WE3_2 <= "0000";
        We_3 <= '0';
        We_4 <= '0';
        We_5 <= '0';
        if address >= x"8000_0000" then --RAM
            WE3M_1 <= MemWrite;
            RDsel <= "000";
        elsif(address >= x"0000_1000" and address <= x"0000_1FFF") then -- ROM
            WE3M_1 <= (others => '0');
            RDsel <= "001";
        elsif address >= x"1000_0000" and address <= x"1000_00FF" then --UART
            WE3_2 <= MemWrite;
            RDsel <= "010";
        elsif address >= x"0C00_0000" and address <= x"0FFF_FFFF" then --PLIC
            RDsel <= "011";
            if to_integer(UNSIGNED(MemWrite)) > 0 then
                We_3 <= '1';
            else
                We_3 <= '0';
            end if;
        elsif address >= x"0200_0000" and address <= x"0200_FFFF" then --CLINT
            RDsel <= "100";
            if to_integer(UNSIGNED(MemWrite)) > 0 then
                We_4 <= '1';
            else
                We_4 <= '0';
            end if;
        elsif address >= x"1000_1000" and address <= x"1000_1000" then --GPIO
            if to_integer(UNSIGNED(MemWrite)) > 0 then
                We_5 <= '1';
            else
                We_5 <= '0';
            end if;
            RDsel <= "101";
        end if;
    end process;
end architecture RTL;
