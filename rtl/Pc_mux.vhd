library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Pc_mux is
    port(
        PCPlus4 : in std_logic_vector(31 downto 0);
        PCL : in std_logic_vector(31 downto 0);
        mtvec_handler_addr : in std_logic_vector(31 downto 0);
        mepc_ret_addr : in std_logic_vector(31 downto 0);
        S : in std_logic_vector(1 downto 0);
        PCOUT : out std_logic_vector(31 downto 0)
    );
end entity Pc_mux;

architecture RTL of Pc_mux is
begin
    PCOUT <= PCPlus4 when S = "00" else PCL when S = "01" else mtvec_handler_addr when S = "10" else mepc_ret_addr when S = "11" else (others => '0');
end architecture RTL;

