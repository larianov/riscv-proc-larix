--------------------------------------------------------------------------------
-- readblock_tb : self-checking testbench for ReadBlock (load formatting, combinational)
--
-- Spec: README "ReadBlock" + "Supported instructions" (little-endian RV32I loads).
--   F1 lb  (000): byte at addr[1:0], sign-extended
--   F2 lbu (100): byte at addr[1:0], zero-extended
--   F3 lh  (001): halfword at addr[1:0] = 0 or 2, sign-extended; misaligned (1, 3) -> 0
--   F4 lhu (101): same, zero-extended; misaligned -> 0
--   F5 lw  (010): the word at addr[1:0] = 0; misaligned -> 0
-- funct3 011/110/111 are not loads (ControlUnit marks them illegal); the README does not say
-- what ReadBlock outputs for them, so they are not checked (open question).
--
-- Checking: the memory word is split into a little-endian byte array, and the expected value
-- is built from bytes + an explicit sign test (not by slicing like the RTL).
-- Stimulus: every funct3 x offset for directed words (sign bits set/clear in every byte,
-- 0, all-ones) and G_N_RAND random words.
-- E1 wrong prediction must be caught.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tb_pkg.all;

entity readblock_tb is
    generic(
        G_SEED   : positive := 1;
        G_N_RAND : natural  := 500;
        G_INJECT : boolean  := true
    );
end entity readblock_tb;

architecture sim of readblock_tb is
    subtype word_t is std_logic_vector(31 downto 0);
    subtype byte_t is std_logic_vector(7 downto 0);
    constant C_SETTLE : time := 1 ns;

    signal mem    : word_t := (others => '0');
    signal addr   : std_logic_vector(1 downto 0) := "00";
    signal funct3 : std_logic_vector(2 downto 0) := "000";
    signal rd     : word_t;
    signal done   : boolean := false;

    shared variable rnd : tb_rand_t;

    type bytes_t is array (0 to 3) of byte_t;

    function to_bytes(w : word_t) return bytes_t is
        variable b : bytes_t;
    begin
        for i in 0 to 3 loop
            for k in 0 to 7 loop
                b(i)(k) := w(8 * i + k);
            end loop;
        end loop;
        return b;
    end function;

    -- expected load result; valid = false for funct3 values that are not loads
    procedure model(w : word_t; f3, off : natural; exp : out word_t; valid : out boolean) is
        variable b    : bytes_t := to_bytes(w);
        variable fill : byte_t;
        variable size : natural;
        variable sext : boolean;
    begin
        valid := true;
        case f3 is
            when 0 => size := 1; sext := true;
            when 4 => size := 1; sext := false;
            when 1 => size := 2; sext := true;
            when 5 => size := 2; sext := false;
            when 2 => size := 4; sext := false;
            when others => valid := false; exp := (others => '-'); return;
        end case;
        if off mod size /= 0 then
            exp := (others => '0');             -- misaligned: reads 0
            return;
        end if;
        fill := x"00";
        if sext and b(off + size - 1)(7) = '1' then fill := x"FF"; end if;
        for i in 0 to 3 loop
            if i < size then
                exp(8 * i + 7 downto 8 * i) := b(off + i);
            else
                exp(8 * i + 7 downto 8 * i) := fill;
            end if;
        end loop;
    end procedure;
begin
    watchdog : tb_watchdog(done, 1 ms);

    dut : entity work.ReadBlock
        port map(Memory_Data => mem, addr_2_bits => addr, funct3 => funct3, ReadData => rd);

    stimulus : process
        variable n_neg, n_mis : natural := 0;

        procedure check_word(w : word_t; corrupt : boolean := false) is
            variable exp   : word_t;
            variable valid : boolean;
        begin
            for f3 in 0 to 7 loop
                for off in 0 to 3 loop
                    model(w, f3, off, exp, valid);
                    next when not valid;
                    if corrupt then exp(0) := not exp(0); end if;
                    mem    <= w;
                    funct3 <= std_logic_vector(to_unsigned(f3, 3));
                    addr   <= std_logic_vector(to_unsigned(off, 2));
                    wait for C_SETTLE;
                    tb_check_equal(rd, exp, "load f3=" & integer'image(f3) & " off=" & integer'image(off) &
                                            " word=" & to_str(w));
                    if exp(31) = '1' then n_neg := n_neg + 1; end if;
                    if exp = x"00000000" and w /= x"00000000" then n_mis := n_mis + 1; end if;
                    if corrupt then return; end if;   -- one injected error only
                end loop;
            end loop;
        end procedure;

        type word_array is array (natural range <>) of word_t;
        constant WORDS : word_array := (
            x"A1B2C3D4", x"7F80FF01", x"00000000", x"FFFFFFFF", x"807F807F", x"7F807F80", x"01020304");
    begin
        rnd.seed(G_SEED);
        tb_info("readblock_tb seed=" & integer'image(G_SEED));
        tb_info("T1: directed words, every funct3 x offset");
        for i in WORDS'range loop
            check_word(WORDS(i));
        end loop;
        tb_info("T2: random words");
        for k in 1 to G_N_RAND loop
            check_word(rnd.slv(32));
        end loop;
        tb_check(n_neg > 0 and n_mis > 0, "coverage: sign extension and misaligned zero");

        if G_INJECT then
            tb_expect_errors(1, "E1: wrong load prediction must be caught");
            check_word(x"12345678", corrupt => true);
            tb_end_expect;
        end if;

        done <= true;
        tb_finish;
        wait;
    end process stimulus;
end architecture sim;
