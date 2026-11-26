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
        PCsrc : out STD_LOGIC_VECTOR(1 downto 0);
        Result_Src : out std_logic_vector(1 downto 0);
        Mem_Write : out std_logic;
        irq : in STD_LOGIC;
        MIE : in std_logic;
        MEIE : in std_logic;
        TRAP : out STD_LOGIC;
        CSRop : out STD_LOGIC_VECTOR(1 downto 0);
        CSWrite : out STD_LOGIC;
        MRET : out STD_LOGIC;
        JalrReg : out std_logic
    );
end entity controlblock;

architecture RTL of controlblock is
    signal Branch : std_logic := '0';
    signal Jump : std_logic;
    signal TRAP_INS : std_logic := '0';
    signal MRET_R : std_logic := '0';
    signal RegWrite_I : std_logic := '0';
    signal MemWrite_I : std_logic := '0';    
    
begin
    ControlUnit_inst : entity work.ControlUnit
        port map(
            opcode      => instr(6 downto 0),
            funct3      => instr(14 downto 12),
            funct7      => instr(31 downto 25),
            RegWrite    => RegWrite_I,
            ASrc        => ASrc,
            BSrc        => BSrc,
            Illegal     => Illegal,
            Branch      => Branch,
            ImmSrc      => ImmSrc,
            alu_control => alu_control,
            Mem_Write   => MemWrite_I,
            Result_Src  => Result_Src,
            JalrReg     => JalrReg,
            Jump        => Jump,
            rs1         => instr(19 downto 15), 
            MRET        => MRET_R,
            CSRwrite    => CSWrite,
            CSRop       => CSRop
            
        );
    RegWrite <= RegWrite_I and not TRAP_INS;
    Mem_Write <= MemWrite_I and not TRAP_INS;
    TRAP_INS <= MEIE and MIE and irq;
    TRAP <= TRAP_INS;
    PCsrc <= "10" when TRAP_INS = '1' else
             "11" when MRET_R = '1' else
             "01" when (branch = '1' and (zero xor instr(12) xor instr(14)) = '1') or (Jump = '1') else
             "00";
    MRET <= MRET_R;
end architecture RTL;

