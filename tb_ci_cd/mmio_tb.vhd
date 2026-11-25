library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Address decoding: MMIO, plus the two muxes it drives (interselmux, ReadDatamux).
--   0x8000_0000..        RAM    RDsel 000, WE3M_1 = MemWrite
--   0x0000_1000..0x1FFF  ROM    RDsel 001, never writable
--   0x1000_0000..0x00FF  UART   RDsel 010, WE3_2  = MemWrite
--   0x0C00_0000..0x0FFF_FFFF PLIC  RDsel 011, We_3
--   0x0200_0000..0x0200_FFFF CLINT RDsel 100, We_4
--   0x1000_1000          GPIO   RDsel 101, We_5
--   anything else        RDsel 101, no write enable
-- instruction source: PC in ROM -> 00 (boot), PC >= 0x8000_0000 -> 01 (RAM), else 10 (zero)
entity mmio_tb is
end entity;

architecture sim of mmio_tb is
    signal MemWrite : std_logic_vector(3 downto 0) := "0000";
    signal PC, addr : std_logic_vector(31 downto 0) := (others => '0');
    signal WE3M_1, WE3_2 : std_logic_vector(3 downto 0);
    signal We_3, We_4, We_5 : std_logic;
    signal RDsel : std_logic_vector(2 downto 0);
    signal intersel : std_logic_vector(1 downto 0);
    signal instr_R, ReadData : std_logic_vector(31 downto 0);

    constant I_BOOT : std_logic_vector(31 downto 0) := x"B0071111";
    constant I_RAM  : std_logic_vector(31 downto 0) := x"5A3A2222";
    constant D_RAM   : std_logic_vector(31 downto 0) := x"000000A0";
    constant D_ROM   : std_logic_vector(31 downto 0) := x"000000A1";
    constant D_UART  : std_logic_vector(31 downto 0) := x"000000A2";
    constant D_PLIC  : std_logic_vector(31 downto 0) := x"000000A3";
    constant D_CLINT : std_logic_vector(31 downto 0) := x"000000A4";
    constant D_GPIO  : std_logic_vector(31 downto 0) := x"000000A5";
begin
    dut : entity work.MMIO
        port map(MemWrite => MemWrite, PC => PC, address => addr, WE3M_1 => WE3M_1, WE3_2 => WE3_2,
                 We_3 => We_3, We_4 => We_4, We_5 => We_5, RDsel => RDsel, intersel => intersel);
    imux : entity work.interselmux
        port map(instr_boot => I_BOOT, instr_ram => I_RAM, S => intersel, instr_R => instr_R);
    rmux : entity work.ReadDatamux
        port map(S => RDsel, MEMRAM => D_RAM, MEMROM => D_ROM, UART => D_UART, PLIC => D_PLIC,
                 CLINT => D_CLINT, GPIO => D_GPIO, ReadData => ReadData);

    process
        -- region check: decode of a with MemWrite = 1111 and 0000
        procedure region(a : std_logic_vector(31 downto 0); sel : std_logic_vector(2 downto 0);
                         d : std_logic_vector(31 downto 0);
                         ram, uart : std_logic_vector(3 downto 0); p, c, g : std_logic; msg : string) is
        begin
            addr <= a; MemWrite <= "1111";
            wait for 1 ns;
            assert RDsel = sel report msg & ": RDsel " & to_string(RDsel) & " expected " & to_string(sel) severity error;
            assert ReadData = d report msg & ": ReadData " & to_hstring(ReadData) severity error;
            assert WE3M_1 = ram report msg & ": WE3M_1 " & to_string(WE3M_1) severity error;
            assert WE3_2 = uart report msg & ": WE3_2 " & to_string(WE3_2) severity error;
            assert We_3 = p and We_4 = c and We_5 = g report msg & ": We_3/4/5 wrong" severity error;
            MemWrite <= "0000";
            wait for 1 ns;
            assert WE3M_1 = "0000" and WE3_2 = "0000" and We_3 = '0' and We_4 = '0' and We_5 = '0'
                report msg & ": write enable without MemWrite" severity error;
        end procedure;

        procedure fetch(p : std_logic_vector(31 downto 0); s : std_logic_vector(1 downto 0);
                        d : std_logic_vector(31 downto 0); msg : string) is
        begin
            PC <= p;
            wait for 1 ns;
            assert intersel = s report msg & ": intersel " & to_string(intersel) & " expected " & to_string(s) severity error;
            assert instr_R = d report msg & ": instr " & to_hstring(instr_R) severity error;
        end procedure;
    begin
        -- instruction source
        fetch(x"00001000", "00", I_BOOT, "PC = reset vector -> boot ROM");
        fetch(x"00001FFC", "00", I_BOOT, "PC = end of ROM");
        fetch(x"80000000", "01", I_RAM,  "PC = RAM base");
        fetch(x"FFFFFFFC", "01", I_RAM,  "PC = top of RAM");
        fetch(x"00000000", "10", x"00000000", "PC = 0 is unmapped");
        fetch(x"00000FFC", "10", x"00000000", "PC just below ROM");
        fetch(x"00002000", "10", x"00000000", "PC just above ROM");
        fetch(x"7FFFFFFC", "10", x"00000000", "PC just below RAM");

        -- data regions                              RDsel  data     RAM     UART    P    C    G
        region(x"80000000", "000", D_RAM,   "1111", "0000", '0', '0', '0', "RAM base");
        region(x"80000100", "000", D_RAM,   "1111", "0000", '0', '0', '0', "RAM");
        region(x"00001000", "001", D_ROM,   "0000", "0000", '0', '0', '0', "ROM base (read only)");
        region(x"00001FFF", "001", D_ROM,   "0000", "0000", '0', '0', '0', "ROM end (read only)");
        region(x"10000000", "010", D_UART,  "0000", "1111", '0', '0', '0', "UART");
        region(x"100000FF", "010", D_UART,  "0000", "1111", '0', '0', '0', "UART end");
        region(x"0C000000", "011", D_PLIC,  "0000", "0000", '1', '0', '0', "PLIC");
        region(x"0FFFFFFF", "011", D_PLIC,  "0000", "0000", '1', '0', '0', "PLIC end");
        region(x"02000000", "100", D_CLINT, "0000", "0000", '0', '1', '0', "CLINT");
        region(x"0200FFFF", "100", D_CLINT, "0000", "0000", '0', '1', '0', "CLINT end");
        region(x"10001000", "101", D_GPIO,  "0000", "0000", '0', '0', '1', "GPIO");
        region(x"00000000", "101", D_GPIO,  "0000", "0000", '0', '0', '0', "unmapped 0");
        region(x"00002000", "101", D_GPIO,  "0000", "0000", '0', '0', '0', "unmapped above ROM");
        region(x"7FFFFFFF", "101", D_GPIO,  "0000", "0000", '0', '0', '0', "unmapped below RAM");

        -- RAM write enable passes byte lanes through unchanged
        addr <= x"80000004"; MemWrite <= "0110";
        wait for 1 ns;
        assert WE3M_1 = "0110" report "RAM byte lanes not passed through" severity error;

        report "mmio_tb done";
        wait;
    end process;
end architecture;
