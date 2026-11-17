library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity core is
    port(
        rst : in std_logic;
        clk : in std_logic;
        instr : in std_logic_vector(31 downto 0);
        PC : out std_logic_vector(31 downto 0);
        Illegal : out std_logic;
        rez : out std_logic_vector(31 downto 0)
    );
end entity core;
architecture RTL of core is
    signal zero : std_logic := '0';
    signal RegWrite : std_logic;
    signal AluSrc : std_logic := '0';
    signal ImmSrc : std_logic_vector(1 downto 0) := (others => '0');
    signal alu_control : std_logic_vector(3 downto 0);
    signal PC_src : std_logic := '0';
        
begin
    DataPath_inst : entity work.DataPath
        port map(
            clk         => clk,
            rst         => rst,
            PC_Src      => PC_src,
            ImmSrc      => ImmSrc,
            instr       => instr,
            AluSrc      => AluSrc,
            alu_control => alu_control,
            RegWrite    => RegWrite,
            Zero        => Zero,
            REZ         => rez,
            PC          => PC
        );
    controlblock_inst : entity work.controlblock
        port map(
            instr       => instr,
            zero        => zero,
            Illegal     => Illegal,
            RegWrite    => RegWrite,
            AluSrc      => AluSrc,
            ImmSrc      => ImmSrc,
            alu_control => alu_control,
            PCsrc       => PC_src
        );
        
end architecture RTL;
