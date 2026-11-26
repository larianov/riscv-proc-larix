--------------------------------------------------------------------------------
-- immgen_tb : self-checking testbench for ImmGen (combinational)
--
-- Spec: README (ImmSrc 000 I, 001 S, 010 B, 011 J, 100 U) + RV32I immediate encodings.
--   F1 I: imm[11:0] = instr[31:20], sign-extended
--   F2 S: imm[11:5] = instr[31:25], imm[4:0] = instr[11:7], sign-extended
--   F3 B: imm[12|10:5] = instr[31|30:25], imm[4:1|11] = instr[11:8|7], bit 0 = 0, sign-extended
--   F4 J: imm[20|10:1|11|19:12] = instr[31|30:21|20|19:12], bit 0 = 0, sign-extended
--   F5 U: imm[31:12] = instr[31:12], low 12 bits 0
--   F6 the output depends only on the immediate bits: the other fields (rd, rs1, rs2, funct3,
--      opcode) are random in every test
--
-- Checking: independent path. The testbench ENCODES a chosen integer immediate into an
-- instruction word (the way an assembler does) and expects ImmGen to give the same integer
-- back. Immediates are skewed to the range ends (min, max, 0, -1, +/-step).
-- ImmSrc 101..111 is not specified (open question), so it is not checked.
-- E1 wrong prediction must be caught.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tb_pkg.all;

entity immgen_tb is
    generic(
        G_SEED   : positive := 1;
        G_N_RAND : natural  := 4000;   -- per format
        G_INJECT : boolean  := true
    );
end entity immgen_tb;

architecture sim of immgen_tb is
    subtype word_t is std_logic_vector(31 downto 0);
    constant C_SETTLE : time := 1 ns;

    constant SRC_I : std_logic_vector(2 downto 0) := "000";
    constant SRC_S : std_logic_vector(2 downto 0) := "001";
    constant SRC_B : std_logic_vector(2 downto 0) := "010";
    constant SRC_J : std_logic_vector(2 downto 0) := "011";
    constant SRC_U : std_logic_vector(2 downto 0) := "100";

    signal imm     : word_t := (others => '0');
    signal imm_src : std_logic_vector(2 downto 0) := "000";
    signal imm_out : word_t;
    signal done    : boolean := false;

    shared variable rnd : tb_rand_t;

    function fmt_name(s : std_logic_vector(2 downto 0)) return string is
    begin
        case s is
            when SRC_I => return "I";
            when SRC_S => return "S";
            when SRC_B => return "B";
            when SRC_J => return "J";
            when others => return "U";
        end case;
    end function;
begin
    watchdog : tb_watchdog(done, 10 ms);

    dut : entity work.ImmGen
        port map(
            imm     => imm,
            imm_src => imm_src,
            imm_out => imm_out
        );

    stimulus : process
        variable n_neg, n_pos : natural := 0;

        -- encode value v of format src into a word whose other bits are random
        impure function encode(src : std_logic_vector(2 downto 0); v : integer) return word_t is
            variable w : word_t := rnd.slv(32);   -- random rd/rs1/rs2/funct3/opcode
            variable s : signed(31 downto 0) := to_signed(v, 32);
        begin
            case src is
                when SRC_I =>
                    w(31 downto 20) := std_logic_vector(s(11 downto 0));
                when SRC_S =>
                    w(31 downto 25) := std_logic_vector(s(11 downto 5));
                    w(11 downto 7)  := std_logic_vector(s(4 downto 0));
                when SRC_B =>
                    w(31)           := s(12);
                    w(30 downto 25) := std_logic_vector(s(10 downto 5));
                    w(11 downto 8)  := std_logic_vector(s(4 downto 1));
                    w(7)            := s(11);
                when SRC_J =>
                    w(31)           := s(20);
                    w(30 downto 21) := std_logic_vector(s(10 downto 1));
                    w(20)           := s(11);
                    w(19 downto 12) := std_logic_vector(s(19 downto 12));
                when others =>          -- U: v is the 20-bit upper value (signed view)
                    w(31 downto 12) := std_logic_vector(s(19 downto 0));
            end case;
            return w;
        end function;

        -- expected 32-bit immediate for value v
        function expected(src : std_logic_vector(2 downto 0); v : integer) return word_t is
        begin
            if src = SRC_U then
                return std_logic_vector(to_signed(v, 20)) & x"000";
            end if;
            return std_logic_vector(to_signed(v, 32));
        end function;

        procedure check_imm(src : std_logic_vector(2 downto 0); v : integer; corrupt : boolean := false) is
            variable w   : word_t := encode(src, v);
            variable exp : word_t := expected(src, v);
        begin
            if corrupt then exp := exp xor x"00001000"; end if;
            imm     <= w;
            imm_src <= src;
            wait for C_SETTLE;
            tb_check_equal(imm_out, exp, fmt_name(src) & "-imm " & integer'image(v) & " instr=" & to_str(w));
            if v < 0 then n_neg := n_neg + 1; else n_pos := n_pos + 1; end if;
        end procedure;

        -- legal range of each format: lo..hi in steps of step
        procedure range_of(src : std_logic_vector(2 downto 0); lo, hi, step : out integer) is
        begin
            case src is
                when SRC_I | SRC_S => lo := -2048;    hi := 2047;    step := 1;
                when SRC_B         => lo := -4096;    hi := 4094;    step := 2;
                when SRC_J         => lo := -1048576; hi := 1048574; step := 2;
                when others        => lo := -524288;  hi := 524287;  step := 1;
            end case;
        end procedure;

        type src_array is array (natural range <>) of std_logic_vector(2 downto 0);
        constant FORMATS : src_array := (SRC_I, SRC_S, SRC_B, SRC_J, SRC_U);
        variable lo, hi, step, v : integer;
    begin
        rnd.seed(G_SEED);
        tb_info("immgen_tb seed=" & integer'image(G_SEED));

        for f in FORMATS'range loop
            range_of(FORMATS(f), lo, hi, step);
            tb_info("T" & integer'image(f + 1) & ": " & fmt_name(FORMATS(f)) & "-immediate, directed + random");
            -- directed: ends of the range, 0, +/- one step, single-bit values
            check_imm(FORMATS(f), lo);
            check_imm(FORMATS(f), hi);
            check_imm(FORMATS(f), 0);
            check_imm(FORMATS(f), step);
            check_imm(FORMATS(f), -step);
            v := step;
            while v <= hi loop
                check_imm(FORMATS(f), v);
                check_imm(FORMATS(f), -v);
                v := v * 2;
            end loop;
            -- random, skewed to the range ends
            for k in 1 to G_N_RAND loop
                v := rnd.int_skewed(lo / step, hi / step) * step;
                check_imm(FORMATS(f), v);
            end loop;
        end loop;

        tb_info("coverage: negative=" & integer'image(n_neg) & " non-negative=" & integer'image(n_pos));
        tb_check(n_neg > 0 and n_pos > 0, "coverage: both signs of every immediate");

        if G_INJECT then
            tb_expect_errors(1, "E1: wrong immediate prediction must be caught");
            check_imm(SRC_B, -2, corrupt => true);
            tb_end_expect;
        end if;

        done <= true;
        tb_finish;
        wait;
    end process stimulus;
end architecture sim;
