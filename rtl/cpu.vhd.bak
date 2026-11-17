library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cpu is
    port(
        clk : in std_logic;
        rst : in std_logic;
        Illegal : out std_logic;
        rez : out std_logic_vector(31 downto 0);
        PC : out std_logic_vector(31 downto 0)
    );
end entity cpu;


architecture RTL of cpu is
    signal instr : std_logic_vector(31 downto 0) := (others => '0');
    signal PC_s : std_logic_vector(31 downto 0) := (others => '0');
    
begin
    instruction_memory_inst : entity work.instruction_memory
        generic map(
            file_S => "hex.hex",
            size   => 1000
        )
        port map(
            PC        => PC_s,
            instr_out => instr
        );
    core_inst : entity work.core
        port map(
            rst     => rst,
            clk     => clk,
            instr   => instr,
            PC      => PC_s,
            Illegal => Illegal,
            rez     => rez
        );
    
    PC <= PC_s;
end architecture RTL;
