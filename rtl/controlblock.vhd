library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity controlblock is
    port(
        instr : in std_logic_vector(31 downto 0);
        zero : in STD_LOGIC;
        Illegal : out std_logic;
        RegWrite : out std_logic;
        AluSrc : out std_logic;
        ImmSrc : out std_logic_vector(1 downto 0);
        alu_control : out std_logic_vector(3 downto 0);
        PCsrc : out STD_LOGIC;
        Result_Src : out std_logic_vector(1 downto 0);
        Mem_Write : out std_logic
    );
end entity controlblock;

architecture RTL of controlblock is
    signal Branch : std_logic := '0';
    
begin
    ControlUnit_inst : entity work.ControlUnit
        port map(
            opcode      => instr(6 downto 0),
            funct3      => instr(14 downto 12),
            funct7      => instr(31 downto 25),
            RegWrite    => RegWrite,
            AluSrc      => AluSrc,
            Illegal     => Illegal,
            Branch      => Branch,
            ImmSrc      => ImmSrc,
            alu_control => alu_control,
            Mem_Write => Mem_Write,
            Result_Src => Result_Src
        );
    PCsrc <= branch and (zero xor instr(12) xor instr(14));
end architecture RTL;

