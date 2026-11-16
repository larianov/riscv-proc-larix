library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cpu is
    port(
        rst : in std_logic;
        clk : in std_logic;
        Illegal : out std_logic;
        rez : out std_logic_vector(31 downto 0)
    );
end entity cpu;
architecture RTL of cpu is
    signal PC : std_logic_vector(31 downto 0) := (others => '0');
    signal PC_M : std_logic_vector(31 downto 0) := (others => '0');
    signal PC_Out4 : std_logic_vector(31 downto 0);
    signal zero : std_logic := '0';
    signal branch : std_logic := '0';
    signal PCOFFSET : std_logic_vector(31 downto 0) := (others => '0');
    signal instr : std_logic_vector(31 downto 0) := (others => '0');
    signal RegWrite : std_logic;
    signal readA : std_logic_vector(31 downto 0) := (others => '0');
    signal readB : std_logic_vector(31 downto 0) := (others => '0');    
    signal write_In : std_logic_vector(31 downto 0);
    signal AluSrc : std_logic := '0';
    signal ImmSrc : std_logic_vector(1 downto 0) := (others => '0');
    signal alu_control : std_logic_vector(3 downto 0);
    signal imm_out : std_logic_vector(31 downto 0);
    signal B_input : std_logic_vector(31 downto 0);
    signal zerob : STD_LOGIC := '0';    
begin
    pc_inst : entity work.pc
    port map(
        clk    => clk,
        rst    => rst,
        PC     => PC,
        PCNext => PC_M
    );
    PCPlus4_inst : entity work.PCPlus4
        port map(
            PC   => PC,
            PC_O => PC_Out4
        );
    PCTarget_inst : entity work.PCTarget
        port map(
            PC       => PC,
            offset   => imm_out,
            PCOFFSET => PCOFFSET
        );
    Pc_mux_inst : entity work.Pc_mux
        port map(
            PCPlus4 => PC_Out4,
            PCL     => PCOFFSET,
            S       => zerob,
            PCOUT   => PC_M
        );
    instruction_memory_inst : entity work.instruction_memory
        generic map(
            file_S => "hex.hex",
            size   => 1000
        )
        port map(
            PC        => PC,
            instr_out => instr
        );
    riscvregfile_inst : entity work.riscvregfile
        port map(
            clk             => clk,
            read_idx_second => instr(24 downto 20),
            read_idx_first  => instr(19 downto 15),
            write_idx       => instr(11 downto 7),
            read_out_first  => readA,
            read_out_second => readB,
            write_en        => RegWrite,
            write_In        => write_In
        );
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
            alu_control => alu_control
        );
    ImmGen_inst : entity work.ImmGen
        port map(
            imm     => instr,
            imm_src => ImmSrc,
            imm_out => imm_out
        );
    alu_mux_inst : entity work.alu_mux
        port map(
            rd2    => readB,
            imm    => imm_out,
            S      => AluSrc,
            muxout => B_input
        );
    alu_inst : entity work.alu
        port map(
            A_input     => readA,
            B_input     => B_input,
            alu_control => alu_control,
            res_out     => write_In,
            Z           => zero
        );
    zerob <= (zero and branch and not instr(12)) or (not zero and branch and instr(12));
    rez <= write_In;
end architecture RTL;
