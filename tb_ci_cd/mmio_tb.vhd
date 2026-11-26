--------------------------------------------------------------------------------
-- mmio_tb : self-checking testbench for MMIO, interselmux and ReadDatamux
--
-- Spec: README "Boot and memory map" + "Top level" table.
--   F1 data address decode (RDsel / write enable):
--        ROM   0x0000_1000..0x0000_1FFF  001  none (read only)
--        CLINT 0x0200_0000..0x0200_FFFF  100  We_4 = any MemWrite bit
--        PLIC  0x0C00_0000..0x0FFF_FFFF  011  We_3 = any MemWrite bit
--        UART  0x1000_0000..0x1000_00FF  010  WE3_2 = MemWrite (byte lanes)
--        GPIO  0x1000_1000               101  We_5 = any MemWrite bit
--        RAM   0x8000_0000..             000  WE3M_1 = MemWrite (byte lanes)
--        else                            101  none
--   F2 at most one write enable group is active, and none when MemWrite = 0000
--   F3 instruction source: PC in ROM -> boot ROM, PC >= 0x8000_0000 -> RAM, else 0x0000_0000
--   F4 interselmux: 00 boot, 01 RAM, else 0;  ReadDatamux: 000..101 the six sources, else 0
-- The intersel code for "neither" is not specified, only that the instruction is 0.
--
-- Checking: region model written from the table with integer ranges; mux data inputs are
-- distinct constants so the selected source is identifiable.
-- Stimulus: base-1 / base / end / end+1 of every region x all 16 MemWrite values, random
-- addresses skewed to the region edges, and the muxes driven directly for unreachable codes.
-- E1 wrong RDsel prediction must be caught.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tb_pkg.all;

entity mmio_tb is
    generic(
        G_SEED   : positive := 1;
        G_N_RAND : natural  := 5000;
        G_INJECT : boolean  := true
    );
end entity mmio_tb;

architecture sim of mmio_tb is
    subtype word_t is std_logic_vector(31 downto 0);
    constant C_SETTLE : time := 1 ns;

    type region_t is (R_ROM, R_CLINT, R_PLIC, R_UART, R_GPIO, R_RAM, R_NONE);
    type bound_t is record
        r      : region_t;
        lo, hi : unsigned(31 downto 0);
    end record;
    type bound_array is array (natural range <>) of bound_t;
    constant MAP_T : bound_array := (
        (R_ROM,   x"00001000", x"00001FFF"),
        (R_CLINT, x"02000000", x"0200FFFF"),
        (R_PLIC,  x"0C000000", x"0FFFFFFF"),
        (R_UART,  x"10000000", x"100000FF"),
        (R_GPIO,  x"10001000", x"10001000"),
        (R_RAM,   x"80000000", x"FFFFFFFF"));

    -- data inputs of the muxes: one distinct value per source
    constant I_BOOT  : word_t := x"B0071111";
    constant I_RAM   : word_t := x"5A3A2222";
    constant D_RAM   : word_t := x"000000A0";
    constant D_ROM   : word_t := x"000000A1";
    constant D_UART  : word_t := x"000000A2";
    constant D_PLIC  : word_t := x"000000A3";
    constant D_CLINT : word_t := x"000000A4";
    constant D_GPIO  : word_t := x"000000A5";

    function region_of(a : word_t) return region_t is
    begin
        for i in MAP_T'range loop
            if unsigned(a) >= MAP_T(i).lo and unsigned(a) <= MAP_T(i).hi then
                return MAP_T(i).r;
            end if;
        end loop;
        return R_NONE;
    end function;

    signal MemWrite         : std_logic_vector(3 downto 0) := "0000";
    signal PC, addr         : word_t := (others => '0');
    signal WE3M_1, WE3_2    : std_logic_vector(3 downto 0);
    signal We_3, We_4, We_5 : std_logic;
    signal RDsel            : std_logic_vector(2 downto 0);
    signal intersel         : std_logic_vector(1 downto 0);
    signal instr_R, ReadData : word_t;
    -- directly driven mux copies (codes MMIO never produces)
    signal s_isel  : std_logic_vector(1 downto 0) := "00";
    signal s_rsel  : std_logic_vector(2 downto 0) := "000";
    signal instr_d, rdata_d : word_t;
    signal done    : boolean := false;

    shared variable rnd : tb_rand_t;
begin
    watchdog : tb_watchdog(done, 1 ms);

    dut : entity work.MMIO
        port map(MemWrite => MemWrite, PC => PC, address => addr, WE3M_1 => WE3M_1, WE3_2 => WE3_2,
                 We_3 => We_3, We_4 => We_4, We_5 => We_5, RDsel => RDsel, intersel => intersel);
    imux : entity work.interselmux
        port map(instr_boot => I_BOOT, instr_ram => I_RAM, S => intersel, instr_R => instr_R);
    rmux : entity work.ReadDatamux
        port map(S => RDsel, MEMRAM => D_RAM, MEMROM => D_ROM, UART => D_UART, PLIC => D_PLIC,
                 CLINT => D_CLINT, GPIO => D_GPIO, ReadData => ReadData);
    imux_d : entity work.interselmux
        port map(instr_boot => I_BOOT, instr_ram => I_RAM, S => s_isel, instr_R => instr_d);
    rmux_d : entity work.ReadDatamux
        port map(S => s_rsel, MEMRAM => D_RAM, MEMROM => D_ROM, UART => D_UART, PLIC => D_PLIC,
                 CLINT => D_CLINT, GPIO => D_GPIO, ReadData => rdata_d);

    stimulus : process
        type count_array is array (region_t) of natural;
        variable hits : count_array := (others => 0);

        procedure check_data(a : word_t; mw : std_logic_vector(3 downto 0); corrupt : boolean := false) is
            variable r     : region_t := region_of(a);
            variable any   : std_logic := '0';
            variable e_sel : std_logic_vector(2 downto 0);
            variable e_dat : word_t;
            variable e_ram, e_uart : std_logic_vector(3 downto 0) := "0000";
            variable e3, e4, e5 : std_logic := '0';
        begin
            if mw /= "0000" then any := '1'; end if;
            case r is
                when R_RAM   => e_sel := "000"; e_dat := D_RAM;   e_ram := mw;
                when R_ROM   => e_sel := "001"; e_dat := D_ROM;
                when R_UART  => e_sel := "010"; e_dat := D_UART;  e_uart := mw;
                when R_PLIC  => e_sel := "011"; e_dat := D_PLIC;  e3 := any;
                when R_CLINT => e_sel := "100"; e_dat := D_CLINT; e4 := any;
                when R_GPIO  => e_sel := "101"; e_dat := D_GPIO;  e5 := any;
                when R_NONE  => e_sel := "101"; e_dat := D_GPIO;
            end case;
            if corrupt then e_sel := not e_sel; end if;
            addr     <= a;
            MemWrite <= mw;
            wait for C_SETTLE;
            tb_check_equal(RDsel, e_sel, "RDsel at " & to_str(a) & " (" & region_t'image(r) & ")");
            if corrupt then return; end if;
            tb_check_equal(ReadData, e_dat, "ReadData at " & to_str(a));
            tb_check_equal(WE3M_1, e_ram, "WE3M_1 at " & to_str(a) & " MemWrite=" & to_str(mw));
            tb_check_equal(WE3_2, e_uart, "WE3_2 at " & to_str(a) & " MemWrite=" & to_str(mw));
            tb_check_equal(We_3, e3, "We_3 (PLIC) at " & to_str(a) & " MemWrite=" & to_str(mw));
            tb_check_equal(We_4, e4, "We_4 (CLINT) at " & to_str(a) & " MemWrite=" & to_str(mw));
            tb_check_equal(We_5, e5, "We_5 (GPIO) at " & to_str(a) & " MemWrite=" & to_str(mw));
            hits(r) := hits(r) + 1;
        end procedure;

        procedure check_fetch(p : word_t) is
            variable r : region_t := region_of(p);
        begin
            PC <= p;
            wait for C_SETTLE;
            if r = R_ROM then
                tb_check_equal(intersel, "00", "intersel at PC " & to_str(p));
                tb_check_equal(instr_R, I_BOOT, "instruction from boot ROM at PC " & to_str(p));
            elsif r = R_RAM then
                tb_check_equal(intersel, "01", "intersel at PC " & to_str(p));
                tb_check_equal(instr_R, I_RAM, "instruction from RAM at PC " & to_str(p));
            else
                tb_check(intersel /= "00" and intersel /= "01", "intersel must select nothing at PC " & to_str(p));
                tb_check_equal(instr_R, x"00000000", "instruction outside ROM/RAM at PC " & to_str(p));
            end if;
        end procedure;

        variable a, base : unsigned(31 downto 0);
        type word_array is array (0 to 3) of word_t;
        variable edges : word_array;
    begin
        rnd.seed(G_SEED);
        tb_info("mmio_tb seed=" & integer'image(G_SEED));

        tb_info("T1: region edges x all MemWrite values, instruction fetch at the same addresses");
        for i in MAP_T'range loop
            edges := (std_logic_vector(MAP_T(i).lo - 1), std_logic_vector(MAP_T(i).lo),
                      std_logic_vector(MAP_T(i).hi), std_logic_vector(MAP_T(i).hi + 1));
            for e in edges'range loop
                for mw in 0 to 15 loop
                    check_data(edges(e), std_logic_vector(to_unsigned(mw, 4)));
                end loop;
                check_fetch(edges(e));
            end loop;
        end loop;
        check_data(x"00000000", "1111");
        check_fetch(x"00000000");
        check_data(x"10001001", "0001");          -- next to GPIO: not GPIO
        check_data(x"10000FFF", "1000");

        tb_info("T2: random addresses (half of them near a region edge)");
        tb_set_verbose(false);
        for k in 1 to G_N_RAND loop
            if rnd.bool(0.5) then
                base := MAP_T(rnd.int(0, MAP_T'length - 1)).lo;
                if rnd.bool then base := MAP_T(rnd.int(0, MAP_T'length - 1)).hi; end if;
                a := base + to_unsigned(rnd.int(0, 8), 32) - 4;
            else
                a := unsigned(rnd.slv(32));
            end if;
            check_data(std_logic_vector(a), rnd.slv(4));
            check_fetch(std_logic_vector(a));
        end loop;
        tb_set_verbose(true);

        tb_info("T3: muxes, every select code");
        for s in 0 to 3 loop
            s_isel <= std_logic_vector(to_unsigned(s, 2));
            wait for C_SETTLE;
            case s is
                when 0 => tb_check_equal(instr_d, I_BOOT, "interselmux 00");
                when 1 => tb_check_equal(instr_d, I_RAM, "interselmux 01");
                when others => tb_check_equal(instr_d, x"00000000", "interselmux " & to_str(s_isel));
            end case;
        end loop;
        for s in 0 to 7 loop
            s_rsel <= std_logic_vector(to_unsigned(s, 3));
            wait for C_SETTLE;
            case s is
                when 0 => tb_check_equal(rdata_d, D_RAM, "ReadDatamux 000");
                when 1 => tb_check_equal(rdata_d, D_ROM, "ReadDatamux 001");
                when 2 => tb_check_equal(rdata_d, D_UART, "ReadDatamux 010");
                when 3 => tb_check_equal(rdata_d, D_PLIC, "ReadDatamux 011");
                when 4 => tb_check_equal(rdata_d, D_CLINT, "ReadDatamux 100");
                when 5 => tb_check_equal(rdata_d, D_GPIO, "ReadDatamux 101");
                when others => tb_check_equal(rdata_d, x"00000000", "ReadDatamux " & to_str(s_rsel));
            end case;
        end loop;

        for r in region_t loop
            tb_check(hits(r) > 0, "coverage: region " & region_t'image(r) & " never hit");
        end loop;

        if G_INJECT then
            tb_expect_errors(1, "E1: wrong RDsel prediction must be caught");
            check_data(x"80000000", "0000", corrupt => true);
            tb_end_expect;
        end if;

        done <= true;
        tb_finish;
        wait;
    end process stimulus;
end architecture sim;
