library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity controlblock is
    port(
        clk : in std_logic;
        rst : in std_logic;
        clr : in std_logic;
        en : in std_logic;
        instrD : in std_logic_vector(31 downto 0);
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
    signal MemWrite_D : std_logic := '0';    
    signal branchE : std_logic;
    signal instrE : std_logic_vector(31 downto 0);
    signal JumpE : std_logic;
    signal Mem_Write_E : std_logic;
    signal MemWrite_M : std_logic;
    
    
begin
    ControlUnit_inst : entity work.ControlUnit
        port map(
            opcode      => instrd(6 downto 0),
            funct3      => instrd(14 downto 12),
            funct7      => instrd(31 downto 25),
            RegWrite    => RegWrite_I,
            ASrc        => ASrc,
            BSrc        => BSrc,
            Illegal     => Illegal,
            Branch      => Branch,
            ImmSrc      => ImmSrc,
            alu_control => alu_control,
            Mem_Write   => MemWrite_D,
            Result_Src  => Result_Src,
            JalrReg     => JalrReg,
            Jump        => Jump,
            rs1         => instrd(19 downto 15), 
            MRET        => MRET_R,
            CSRwrite    => CSWrite,
            CSRop       => CSRop
            
        );

    flopenrc_inst_MemWriteM : entity work.flopenrc
        generic map(
            WIDTH => 1
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d(0)   => MemWrite_D,
            q(0)   => Mem_Write_E
        );
    flopenrc_inst : entity work.flopenrc
        generic map(
            WIDTH => 1
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d(0)   => Mem_Write_E,
            q(0)   => MemWrite_M
        );
    
    
    RegWrite <= RegWrite_I and not TRAP_INS;
    Mem_Write <= MemWrite_M and not TRAP_INS;
    TRAP_INS <= MEIE and MIE and irq;
    TRAP <= TRAP_INS;


    flopenrc_inst_zero : entity work.flopenrc
        generic map(
            WIDTH => 1
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d(0)   => branch,
            q(0)   => branchE
        );
    flopenrc_inst_INSTRE : entity work.flopenrc
        generic map(
            WIDTH => 32
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d   => instrD,
            q   => instrE
        );
    flopenrc_inst_JumpE : entity work.flopenrc
        generic map(
            WIDTH => 1
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d(0)   => Jump,
            q(0)   => JumpE
        );
    
    PCsrc <= "10" when TRAP_INS = '1' else
             "11" when MRET_R = '1' else
             "01" when (branche = '1' and (zero xor instre(12) xor instrE(14)) = '1') or (JumpE = '1') else
             "00";
    MRET <= MRET_R;
end architecture RTL;

