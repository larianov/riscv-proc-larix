library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top_calc is
    port(
        clk : in std_logic;
        instr_inp : in std_logic_vector(31 downto 0);
        Illegal : out std_logic;
        alu_out : out std_logic_vector(31 downto 0)
    );
end entity top_calc;

architecture RTL of top_calc is
    signal read_out_first : std_logic_vector(31 downto 0) := (others => '0');
    signal read_out_second : std_logic_vector(31 downto 0) := (others => '0');
    signal write_In : std_logic_vector(31 downto 0) := (others => '0');
    signal write_en : std_logic := '0';
    signal imm_out : std_logic_vector(31 downto 0) := (others => '0');
    signal AluSrc : std_logic := '0';
    signal alu_control : std_logic_vector(3 downto 0) := (others => '0');
    signal muxout : std_logic_vector(31 downto 0) := (others => '0');
begin
    riscvregfile_inst : entity work.riscvregfile
        port map(
            clk             => clk,
            read_out_first  => read_out_first,
            read_idx_first  => instr_inp(19 downto 15),
            read_out_second => read_out_second,
            read_idx_second => instr_inp(24 downto 20),
            write_en        => write_en,
            write_In        => write_In,
            write_idx       => instr_inp(11 downto 7)
        );
    ImmGen_inst : entity work.ImmGen
        port map(
            imm     => instr_inp(31 downto 20),
            imm_out => imm_out
        );
    ControlUnit_inst : entity work.ControlUnit
        port map(
            opcode      => instr_inp(6 downto 0),
            funct3      => instr_inp(14 downto 12),
            funct7      => instr_inp(31 downto 25),
            RegWrite    => write_en,
            AluSrc      => AluSrc,
            Illegal     => Illegal,
            alu_control => alu_control
        );
    alu_mux_inst : entity work.alu_mux
        port map(
            rd2    => read_out_second,
            imm    => imm_out,
            S      => AluSrc,
            muxout => muxout
        );
    alu_inst : entity work.alu
        port map(
            A_input     => read_out_first,
            B_input     => muxout,
            alu_control => alu_control,
            res_out     => write_In,
            Z           => open
        );

    alu_out <= write_In;
end architecture RTL;

