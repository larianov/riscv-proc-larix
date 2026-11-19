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
        rez : out std_logic_vector(31 downto 0);
        OUT_OF_MEMORY_DATA : in std_logic_vector(31 downto 0);
        WD : out std_logic_vector(31 downto 0);
        WE : out std_Logic_vector(3 downto 0)
    );
end entity core;
architecture RTL of core is
    signal zero : std_logic := '0';
    signal Mem_Write:  STD_LOGIC := '0';
    signal RegWrite : std_logic;
    signal ASrc : std_logic_vector(1 downto 0);
    signal BSrc : std_logic := '0';
    signal ImmSrc : std_logic_vector(2 downto 0) := (others => '0');
    signal alu_control : std_logic_vector(3 downto 0);
    signal PC_src : std_logic := '0';
    signal Result_Src : std_logic_vector(1 downto 0);
    signal WD_Temp : std_logic_vector(31 downto 0);
    signal temp_res: std_logic_vector(31 downto 0) := (others => '0');
    signal READDATA : std_logic_vector(31 downto 0);
    signal JalrReg : std_logic;
begin
    DataPath_inst : entity work.DataPath
        port map(
            clk         => clk,
            rst         => rst,
            PC_Src      => PC_src,
            ImmSrc      => ImmSrc,
            instr       => instr,
            AluSrcB      => BSrc,
            AluSRCA     => ASrc,
            alu_control => alu_control,
            RegWrite    => RegWrite,
            Zero        => Zero,
            REZ         => temp_res,
            PC          => PC,
            ReadData    => ReadData,
            Result_Src  => Result_Src,
            WD          => WD_Temp,
            JalrReg     => JalrReg
        );
    controlblock_inst : entity work.controlblock
        port map(
            instr       => instr,
            zero        => zero,
            Illegal     => Illegal,
            RegWrite    => RegWrite,
            ASrc        => ASrc,
            BSrc      => BSrc,
            ImmSrc      => ImmSrc,
            alu_control => alu_control,
            PCsrc       => PC_src,
            Result_Src  => Result_Src,
            Mem_Write   => Mem_Write,
            JalrReg     => JalrReg
        );
    WriteBlock_inst : entity work.WriteBlock
        port map(
            rd2         => WD_Temp,
            addr_2_bits => temp_res(1 downto 0),
            Mem_Write   => Mem_Write,
            funct3      => instr(14 downto 12),
            WE          => WE,
            wD          => WD
        );

    ReadBlock_inst : entity work.ReadBlock
        port map(
            Memory_Data => OUT_OF_MEMORY_DATA,
            addr_2_bits => temp_res(1 downto 0),
            funct3      => instr(14 downto 12),
            ReadData    => READDATA
        );
    
    rez <= temp_res;
end architecture RTL;
