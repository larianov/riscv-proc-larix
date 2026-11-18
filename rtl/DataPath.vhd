library ieee;
use ieee.std_logic_1164.all;

entity DataPath is
    port(
        clk : in std_logic;
        rst : in std_logic;
        PC_Src : in std_logic;
        ImmSrc : in std_logic_vector(1 downto 0);
        instr : in std_logic_vector(31 downto 0);
        AluSrc : in std_logic;
        alu_control : in std_logic_vector(3 downto 0);
        RegWrite : in STD_LOGIC;
        Zero : out STD_LOGIC;
        REZ : out std_logic_vector(31 downto 0);
        PC : out std_logic_vector(31 downto 0);
        ReadData : in std_logic_vector(31 downto 0);
        Result_Src : in std_logic_vector(1 downto 0);
        WD : out std_logic_vector(31 downto 0)
    );
end entity DataPath;

architecture RTL of DataPath is
    signal Write_Input : std_logic_vector(31 downto 0);
    signal Alu_Result : std_logic_vector(31 downto 0);
    signal A_input : std_logic_vector(31 downto 0);
    signal B_input : std_logic_vector(31 downto 0);
    signal ImmOut : std_logic_vector(31 downto 0) := (others => '0');
    signal PC_NOW : STD_LOGIC_VECTOR(31 downto 0) := (others => '0'); 
    signal PC_NEXT_4 : STD_LOGIC_VECTOR(31 downto 0) := (others => '0'); 
    signal PC_NEXT_OFFSET : std_logic_vector(31 downto 0) := (others => '0');
    signal B_input_real : std_logic_vector(31 downto 0);
    signal PC_Next_R : std_logic_vector(31 downto 0) := (others => '0');
begin
    pc_inst : entity work.pc
    port map(
        clk    => clk,
        rst    => rst,
        PC_Reg     => PC_NOW,
        PCNext => PC_Next_R
    );
    PCPlus4_inst : entity work.PCPlus4
        port map(
            PC   => PC_NOW,
            PC_O => PC_NEXT_4
        );
    PCTarget_inst : entity work.PCTarget
        port map(
            PC       => PC_NOW,
            offset   => ImmOut,
            PCOFFSET => PC_NEXT_OFFSET
        );
    Pc_mux_inst : entity work.Pc_mux
        port map(
            PCPlus4 => PC_NEXT_4,
            PCL     => PC_NEXT_OFFSET,
            S       => PC_Src,
            PCOUT   => PC_Next_R
        );
    riscvregfile_inst : entity work.riscvregfile
        port map(
            clk             => clk,
            read_idx_second => instr(24 downto 20),
            read_idx_first  => instr(19 downto 15),
            write_idx       => instr(11 downto 7),
            read_out_first  => A_input,
            read_out_second => B_input,
            write_en        => RegWrite,
            write_In        => Write_Input
        );
    ImmGen_inst : entity work.ImmGen
        port map(
            imm     => instr,
            imm_src => ImmSrc,
            imm_out => ImmOut
        );
    alu_mux_inst : entity work.alu_mux
        port map(
            rd2    => B_input,
            imm    => ImmOut,
            S      => AluSrc,
            muxout => B_input_real
        );
    alu_inst : entity work.alu
        port map(
            A_input     => A_input,
            B_input     => B_input_real,
            alu_control => alu_control,
            res_out     => Alu_Result,
            Z           => Zero
        );
    result_mux_inst : entity work.result_mux
        port map(
            Result_Src => Result_Src,
            ReadData   => ReadData,
            ALU_Res    => Alu_Result,
            PC_4       => PC_NEXT_4,
            Mux_Res    => Write_Input
        );
    WD <= B_input;
    PC <= PC_NOW;
    REZ <= Alu_Result;
end architecture RTL;

