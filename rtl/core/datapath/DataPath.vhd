library ieee;
use ieee.std_logic_1164.all;

entity DataPath is
    port(
        clk : in std_logic;
        rst : in std_logic;
        clr : in std_logic;
        en : in std_logic;
        PC_Src : in std_logic_vector(1 downto 0);
        ImmSrc : in std_logic_vector(2 downto 0);
        instr : in std_logic_vector(31 downto 0);
        instrD_DATAP : out std_logic_vector(31 downto 0);
        AluSRCA : std_logic_vector(1 downto 0);
        AluSrcB : in std_logic;
        alu_control : in std_logic_vector(3 downto 0);
        RegWrite : in STD_LOGIC;
        Zero : out STD_LOGIC;
        REZ : out std_logic_vector(31 downto 0);
        PC : out std_logic_vector(31 downto 0);
        ReadData : in std_logic_vector(31 downto 0);
        Result_Src : in std_logic_vector(1 downto 0);
        WD : out std_logic_vector(31 downto 0);
        JalrReg : in std_logic;
        TRAP : in std_logic;
        CSRwrite : in std_logic;
        CSRop : in std_logic_vector(1 downto 0);
        MIE : out std_logic;
        MEIE : out std_logic;
        MRET : in std_logic;
        irq : in std_logic;
        funct3M : out std_logic_vector(2 downto 0);

    );
end entity DataPath;

architecture RTL of DataPath is
    signal ResultW : std_logic_vector(31 downto 0);
    signal PCPlus4M : std_logic_vector(31 downto 0);
    signal ReadDataW : std_logic_vector(31 downto 0);
    signal Alu_Result_W : std_logic_vector(31 downto 0);
    signal PCPlus4W : std_logic_vector(31 downto 0);
    signal RD2M : std_logic_vector(31 downto 0);
    signal instrD : std_logic_vector(31 downto 0);
    signal Alu_Result_E : std_logic_vector(31 downto 0);
    signal Alu_Result_M : std_logic_vector(31 downto 0);    
    signal RD1D : std_logic_vector(31 downto 0);
    signal RD1E : std_logic_vector(31 downto 0);
    signal RD2D : std_logic_vector(31 downto 0);
    signal RD2E : std_logic_vector(31 downto 0);
    signal PCF : STD_LOGIC_VECTOR(31 downto 0) := (others => '0'); 
    signal ImmExtD : std_logic_vector(31 downto 0) := (others => '0');
    signal PCPlus4F : STD_LOGIC_VECTOR(31 downto 0) := (others => '0'); 
    signal PCPlus4D : std_logic_vector(31 downto 0);
    signal PCD : std_logic_vector(31 downto 0);
    signal PCE : std_logic_vector(31 downto 0);
    signal ImmExtE : std_logic_vector(31 downto 0);
    signal PCPlus4E : std_logic_vector(31 downto 0);
    signal PC_NEXT_OFFSET_E : std_logic_vector(31 downto 0) := (others => '0');
    signal SrcAE : std_logic_vector(31 downto 0);
    signal SRcBE : std_logic_vector(31 downto 0);
    signal PC_Next_F : std_logic_vector(31 downto 0) := (others => '0');
    signal PCtarget_E : std_logic_vector(31 downto 0) := (others => '0');
    signal PC_NEXT_OFFSET_ZERO_E : std_logic_vector(31 downto 0);
    signal mtvec_handler_addr : std_logic_vector(31 downto 0);
    signal mepc_ret_addr : std_logic_vector(31 downto 0);
    signal CSR_RES : std_logic_vector(31 downto 0);
    signal JalrRegE : std_logic;
    signal RegWriteE : STD_LOGIC;
    signal RegWriteM : std_logic;
    signal RegWriteW : std_logic;
    signal AluSrcBE : std_logic;
    signal AluSRCAE : std_logic_vector(1 downto 0);
    signal alu_controlE : std_logic_vector(3 downto 0);
    signal Result_SrcE : std_logic_vector(1 downto 0);
    signal Result_SrcM : std_logic_vector(1 downto 0);
    signal Result_SrcW : std_logic_vector(1 downto 0);
    signal instrE : std_logic_vector(31 downto 0);
    signal instrM : std_logic_vector(31 downto 0);
    signal instrW : std_logic_vector(31 downto 0);
    

begin

    flopenrc_inst_INSTR : entity work.flopenrc
        generic map(
            WIDTH => 32
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d   => instr,
            q   => instrD
        );
    flopenrc_inst_PLUS4 : entity work.flopenrc
        generic map(
            WIDTH => 32
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d   => PCPlus4F,
            q   => PCPlus4D
        );
    flopenrc_inst_PCD : entity work.flopenrc
        generic map(
            WIDTH => 32
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d   => PCF,
            q   => PCD
        );
    
    pc_inst : entity work.pc
    port map(
        clk    => clk,
        rst    => rst,
        PC_Reg     => PCF,
        PCNext => PC_Next_F
    );
    PCPlus4_inst : entity work.PCPlus4
        port map(
            PC   => PCF,
            PC_O => PCPlus4F
        );

    flopenrc_inst_MUXJALE : entity work.flopenrc
        generic map(
            WIDTH => 1
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d(0)   => JalrReg,
            q(0)   => JalrRegE
        );
    
    MuxJalr_inst : entity work.MuxJalr
        port map(
            PC_NOW      => PCE,
            RD1         => RD1E,
            JalrReg     => JalrRegE,
            PCtarget_IN => PCtarget_E
        );
    
    PCTarget_inst : entity work.PCTarget
        port map(
            PC       => PCtarget_E,
            offset   => ImmExtE,
            PCOFFSET => PC_NEXT_OFFSET_E
        );
    ZeroGen_inst : entity work.ZeroGen
        port map(
            INP  => PC_NEXT_OFFSET_E,
            OUTP => PC_NEXT_OFFSET_ZERO_E
        );
    
    Pc_mux_inst : entity work.Pc_mux
        port map(
            PCPlus4 => PCPlus4F,
            PCL     => PC_NEXT_OFFSET_ZERO_E,
            mtvec_handler_addr => mtvec_handler_addr,
            mepc_ret_addr => mepc_ret_addr,
            S       => PC_Src,
            PCOUT   => PC_Next_F
        );

    flopenrc_inst_REGE : entity work.flopenrc
        generic map(
            WIDTH => 1
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d(0)   => RegWrite,
            q(0)   => RegWriteE
        );

    flopenrc_inst_REGM : entity work.flopenrc
        generic map(
            WIDTH => 1
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d(0)   => RegWriteE,
            q(0)   => RegWriteM
        );
    flopenrc_inst_REGW : entity work.flopenrc
        generic map(
            WIDTH => 1
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d(0)   => RegWriteM,
            q(0)   => RegWriteW
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
    flopenrc_inst_INSTRM : entity work.flopenrc
        generic map(
            WIDTH => 32
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d   => instrE,
            q   => instrM
        );
    flopenrc_inst_INSTRW : entity work.flopenrc
        generic map(
            WIDTH => 32
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d   => instrM,
            q   => instrW
        );
    
    
    
    riscvregfile_inst : entity work.riscvregfile
        port map(
            clk             => clk,
            read_idx_second => instrD(24 downto 20),
            read_idx_first  => instrD(19 downto 15),
            write_idx       => instrW(11 downto 7),
            read_out_first  => RD1D,
            read_out_second => RD2D,
            write_en        => RegWriteW,
            write_In        => ResultW
        );

    flopenrc_inst_RD1 : entity work.flopenrc
        generic map(
            WIDTH => 32
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d   => RD1D,
            q   => RD1E
        );

    flopenrc_inst_RD2 : entity work.flopenrc
        generic map(
            WIDTH => 32
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d   => RD2D,
            q   => RD2E
        );
        
    flopenrc_inst_PCE : entity work.flopenrc
        generic map(
            WIDTH => 32
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d   => PCD,
            q   => PCE
        );
    
    flopenrc_inst_Immext : entity work.flopenrc
        generic map(
            WIDTH => 32
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d   => ImmExtD,
            q   => ImmExtE
        );
    flopenrc_inst_PC4D : entity work.flopenrc
        generic map(
            WIDTH => 32
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d   => PCPlus4D,
            q   => PCPlus4E
        );
    
    CSRblock_inst : entity work.CSRblock
        port map(
            clk                => clk,
            rst                => rst,
            w_DATA             => RD1D,
            mtvec_handler_addr => mtvec_handler_addr,
            mepc_ret_addr_in   => PCF,
            mepc_ret_addr_out  => mepc_ret_addr,
            TRAP               => TRAP,
            CSRwrite           => CSRwrite,
            CSROp              => CSROp,
            CSRnum             => instrD(31 downto 20),
            irq                => irq,
            MIE                => MIE,
            MEIE               => MEIE,
            MRET               => MRET,
            CSR_RES            => CSR_RES
        );
    
    ImmGen_inst : entity work.ImmGen
        port map(
            imm     => instrD,
            imm_src => ImmSrc,
            imm_out => ImmExtD
        );
    
    
    flopenrc_inst_ALUSRCBE : entity work.flopenrc
        generic map(
            WIDTH => 1
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d(0)   => AluSrcB,
            q(0)   => AluSrcBE
        );
    
    alu_muxSRCB_inst : entity work.alu_mux
        port map(
            rd2    => RD2E,
            imm    => ImmExtE,
            S      => AluSrcBE,
            muxout => SRcBE
        );

    flopenrc_inst_ALUSRCAE : entity work.flopenrc
        generic map(
            WIDTH => 2
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d   => AluSRCA,
            q   => AluSRCAE
        );
    
    SrcAMux_inst : entity work.SrcAMux
        port map(
            SrcA => RD1E,
            PC   => PCE,
            S    => AluSRCAE,
            Y    => SrcAE
        );
    flopenrc_inst_ALu_ControlE : entity work.flopenrc
        generic map(
            WIDTH => 4
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d   => alu_control,
            q   => alu_controlE
        );
    
    alu_inst : entity work.alu
        port map(
            A_input     => SrcAE,
            B_input     => SRcBE,
            alu_control => alu_controlE,
            res_out     => Alu_Result_E,
            Z           => Zero
        );

    flopenrc_inst_ALu : entity work.flopenrc
        generic map(
            WIDTH => 32
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d   => Alu_Result_E,
            q   => Alu_Result_M
        );
    flopenrc_inst_PC4M : entity work.flopenrc
        generic map(
            WIDTH => 32
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d   => PCPlus4E,
            q   => PCPlus4M
        );
    flopenrc_inst : entity work.flopenrc
        generic map(
            WIDTH => 32
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d   => RD2E,
            q   => RD2M
        );
    

    flopenrc_inst_READdata : entity work.flopenrc
        generic map(
            WIDTH => 32
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d   => ReadData,
            q   => ReadDataW
        );
    
    flopenrc_inst_ALu_E : entity work.flopenrc
        generic map(
            WIDTH => 32
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d   => Alu_Result_M,
            q   => Alu_Result_W
        );
    flopenrc_inst_PC4W : entity work.flopenrc
        generic map(
            WIDTH => 32
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d   => PCPlus4M,
            q   => PCPlus4W
        );
    
    flopenrc_inst_ResultSRCE : entity work.flopenrc
        generic map(
            WIDTH => 2
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d   => Result_Src,
            q   => Result_SrcE
        );
    flopenrc_inst_ResultSRCM : entity work.flopenrc
        generic map(
            WIDTH => 2
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d   => Result_SrcE,
            q   => Result_SrcM
        );
    flopenrc_inst_SRCW : entity work.flopenrc
        generic map(
            WIDTH => 2
        )
        port map(
            clk => clk,
            rst => rst,
            clr => clr,
            en  => en,
            d   => Result_SrcM,
            q   => Result_SrcW
        );
    
    
    result_mux_inst : entity work.result_mux
        port map(
            Result_Src => Result_SrcW,
            ReadData   => ReadDataW,
            ALU_Res    => Alu_Result_W,
            PC_4       => PCPlus4W,
            CSR_RES    => CSR_RES,
            Mux_Res    => ResultW
        );
    WD <= RD2M;
    instrD_DATAP <= instrD;
    PC <= PCF;
    REZ <= Alu_Result_M;
    funct3M <= instrM(14 downto 12);
end architecture RTL;

