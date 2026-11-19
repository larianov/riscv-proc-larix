library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity controlblock is
    port(
        instr : in std_logic_vector(31 downto 0);
        zero : in STD_LOGIC;
        Illegal : out std_logic;
        RegWrite : out std_logic;
        ASrc : out std_logic_vector(1 downto 0);
        BSrc : out std_logic;
        ImmSrc : out std_logic_vector(2 downto 0);
        alu_control : out std_logic_vector(3 downto 0);
        PCsrc : out STD_LOGIC;
        Result_Src : out std_logic_vector(1 downto 0);
        Mem_Write : out std_logic;
        JalrReg : out std_logic
    );
end entity controlblock;

architecture RTL of controlblock is
    signal Branch : std_logic := '0';
    signal Jump : std_logic;
    
    
begin
    ControlUnit_inst : entity work.ControlUnit
        port map(
            opcode      => instr(6 downto 0),
            funct3      => instr(14 downto 12),
            funct7      => instr(31 downto 25),
            RegWrite    => RegWrite,
            ASrc        => ASrc,
            BSrc        => BSrc,
            Illegal     => Illegal,
            Branch      => Branch,
            ImmSrc      => ImmSrc,
            alu_control => alu_control,
            Mem_Write => Mem_Write,
            Result_Src => Result_Src,
            JalrReg     => JalrReg,
            Jump        => Jump
        );
    PCsrc <= (branch and (zero xor instr(12) xor instr(14))) or Jump;
end architecture RTL;

