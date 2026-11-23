library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cpu is
    port(
        clk : in std_logic;
        rst : in std_logic;
        Illegal : out std_logic;
        RezOUT : out std_logic_vector(31 downto 0);
        PC : out std_logic_vector(31 downto 0)
    );
end entity cpu;


architecture RTL of cpu is
    signal rez : std_logic_vector(31 downto 0);
    signal instr : std_logic_vector(31 downto 0) := (others => '0');
    signal PC_s : std_logic_vector(31 downto 0) := (others => '0');
    signal ReadData : std_logic_vector(31 downto 0);
    signal WE : std_logic_vector(3 downto 0);
    signal WD : std_logic_vector(31 downto 0);
    
    
begin
    unifiedmem_inst : entity work.unifiedmem
        generic map(
            file_S => "hex.hex",
            size   => 128
        )
        port map(
            PC        => PC,
            instr_out => instr,
            clk       => clk,
            address   => rez,
            wD        => wD,
            WE        => WE,
            RD        => ReadData
        );
    
    core_inst : entity work.core
        port map(
            rst     => rst,
            clk     => clk,
            instr   => instr,
            PC      => PC_s,
            Illegal => Illegal,
            rez     => rez,
            OUT_OF_MEMORY_DATA => ReadData,
            WD      => WD,
            WE      => WE    
        );
    PC <= PC_s;
    RezOUT <= rez;
end architecture RTL;
