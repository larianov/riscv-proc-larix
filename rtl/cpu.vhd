library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cpu is
    port(
        clk : in std_logic;
        rst : in std_logic;
        Illegal : out std_logic;
        RezOUT : out std_logic_vector(31 downto 0)
    );
end entity cpu;


architecture RTL of cpu is
    signal rez : std_logic_vector(31 downto 0);
    signal instr : std_logic_vector(31 downto 0) := (others => '0');
    signal PC_s : std_logic_vector(31 downto 0) := (others => '0');
    signal ReadData : std_logic_vector(31 downto 0);
    signal WE : std_logic_vector(3 downto 0);
    signal WD : std_logic_vector(31 downto 0);
    signal WE3M_1 : std_logic_vector(3 downto 0);
    signal intersel : std_logic_vector(1 downto 0);
    signal RDsel : std_logic_vector(2 downto 0);
    signal instr_boot : std_logic_vector(31 downto 0);
    signal instr_ram : std_logic_vector(31 downto 0);
    signal MEMRAM : std_logic_vector(31 downto 0);
    signal MEMROM : std_logic_vector(31 downto 0);    
    
begin
    unifiedmem_inst : entity work.unifiedmem
        generic map(
            file_S => "hex.hex",
            size   => 128
        )
        port map(
            PC        => PC_s,
            instr_out => instr_ram,

            clk       => clk,
            address   => rez,
            wD        => wD,
            WE        => WE3M_1,
            RD        => MEMRAM
    );
    bootrom_inst : entity work.bootrom
        generic map(
            file_S => "boot.hex",
            size   => 64
        )
        port map(
            PC        => PC_s,
            address   => rez,
            RD        => MEMROM,
            instr_out => instr_boot
        );
    

    core_inst : entity work.core
        port map(
            rst     => rst,
            clk     => clk,
            instr   => instr,
            PC      => PC_s,
            Illegal => Illegal,
            rez     => rez,
            OUT_OF_MEMORY_DATA => ReadData,
            WD      => WD,
            WE      => WE    
        );

    MMIO_inst : entity work.MMIO
        port map(
            MemWrite => WE,
            PC       => PC_s,
            address  => rez,
            WE3M_1   => WE3M_1,
            WE3_2    => open,
            We_3     => open,
            We_4     => open,
            We_5     => open,
            RDsel    => RDsel,
            intersel => intersel
        );

    interselmux_inst : entity work.interselmux
        port map(
            instr_boot => instr_boot,
            instr_ram  => instr_ram,
            S          => intersel,
            instr_R    => instr
        );
    ReadDatamux_inst : entity work.ReadDatamux
        port map(
            S        => RDsel,
            MEMRAM   => MEMRAM,
            MEMROM   => MEMROM,
            UART     => (others => '0'),
            PLIC     => (others => '0'),
            CLINT    => (others => '0'),
            GPIO     => (others => '0'),
            ReadData => ReadData
        );
    RezOUT <= rez;
end architecture RTL;
