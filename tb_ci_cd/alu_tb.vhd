--------------------------------------------------------------------------------
-- alu_tb : self-checking testbench for alu (combinational)
--
-- Spec: README "ALU codes" + RV32I semantics.
--   F1 0000 add / 1000 sub, modulo 2^32 (carry/borrow dropped)
--   F2 0001 sll / 0101 srl / 1101 sra, shift amount = B[4:0] only (B[31:5] ignored)
--   F3 0010 slt (signed) / 0011 sltu (unsigned): result is exactly 0 or 1
--   F4 0100 xor / 0110 or / 0111 and
--   F5 the 6 other codes give 0
--   F6 Z = 1 exactly when the result is 0 (every code)
-- Must never happen: X/U on res_out or Z for defined inputs.
--
-- Checking: a bit-level reference model written differently from the RTL (ripple adder,
-- bit-by-bit shifter, MSB-first comparator), not numeric_std operators.
-- Stimulus: corner operands (0, 1, -1, min/max signed, AA../55.., shift amounts 0/1/31 with
-- garbage in B[31:5]) crossed with all 16 codes, then G_N_RAND random pairs skewed to corners.
-- Coverage: carry out, borrow, Z on every op group, slt/sltu both outcomes and disagreeing,
-- sra of a negative value, shift by 0 and 31.
-- E1 wrong result prediction must be caught; E2 wrong Z prediction must be caught.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tb_pkg.all;

entity alu_tb is
    generic(
        G_SEED   : positive := 1;
        G_N_RAND : natural  := 20000;
        G_INJECT : boolean  := true
    );
end entity alu_tb;

architecture sim of alu_tb is
    subtype word_t is std_logic_vector(31 downto 0);
    constant C_SETTLE : time := 1 ns;

    signal A_input     : word_t := (others => '0');
    signal B_input     : word_t := (others => '0');
    signal alu_control : std_logic_vector(3 downto 0) := (others => '0');
    signal res_out     : word_t;
    signal Z           : std_logic;
    signal done        : boolean := false;

    shared variable rnd : tb_rand_t;

    ---------------------------------------------------------------- reference model
    -- ripple-carry adder, bit by bit
    function m_add(a, b : word_t; cin : std_logic) return word_t is
        variable s : word_t;
        variable c : std_logic := cin;
    begin
        for i in 0 to 31 loop
            s(i) := a(i) xor b(i) xor c;
            c    := (a(i) and b(i)) or (a(i) and c) or (b(i) and c);
        end loop;
        return s;
    end function;

    function m_carry(a, b : word_t) return boolean is
        variable c : std_logic := '0';
    begin
        for i in 0 to 31 loop
            c := (a(i) and b(i)) or (a(i) and c) or (b(i) and c);
        end loop;
        return c = '1';
    end function;

    -- unsigned a < b, comparing from the MSB down
    function m_ltu(a, b : word_t) return boolean is
    begin
        for i in 31 downto 0 loop
            if a(i) /= b(i) then
                return b(i) = '1';
            end if;
        end loop;
        return false;
    end function;

    function m_lts(a, b : word_t) return boolean is
    begin
        if a(31) /= b(31) then
            return a(31) = '1';            -- negative < non-negative
        end if;
        return m_ltu(a, b);
    end function;

    -- shift by moving bits one position at a time; fill = '0' or the sign bit
    function m_shift(a : word_t; n : natural; left : boolean; fill : std_logic) return word_t is
        variable v : word_t := a;
    begin
        for k in 1 to n loop
            if left then
                v := v(30 downto 0) & '0';
            else
                v := fill & v(31 downto 1);
            end if;
        end loop;
        return v;
    end function;

    function bool01(b : boolean) return word_t is
    begin
        if b then return x"00000001"; else return x"00000000"; end if;
    end function;

    function model(a, b : word_t; code : std_logic_vector(3 downto 0)) return word_t is
        variable sh : natural := 0;
        variable r  : word_t;
    begin
        for i in 4 downto 0 loop
            sh := sh * 2;
            if b(i) = '1' then sh := sh + 1; end if;
        end loop;
        case code is
            when "0000" => return m_add(a, b, '0');
            when "1000" => return m_add(a, not b, '1');
            when "0001" => return m_shift(a, sh, true, '0');
            when "0101" => return m_shift(a, sh, false, '0');
            when "1101" => return m_shift(a, sh, false, a(31));
            when "0010" => return bool01(m_lts(a, b));
            when "0011" => return bool01(m_ltu(a, b));
            when "0100" | "0110" | "0111" =>
                for i in 0 to 31 loop
                    case code is
                        when "0100" => if a(i) /= b(i) then r(i) := '1'; else r(i) := '0'; end if;
                        when "0110" => if a(i) = '1' or b(i) = '1' then r(i) := '1'; else r(i) := '0'; end if;
                        when others => if a(i) = '1' and b(i) = '1' then r(i) := '1'; else r(i) := '0'; end if;
                    end case;
                end loop;
                return r;
            when others => return x"00000000";
        end case;
    end function;

    function op_name(code : std_logic_vector(3 downto 0)) return string is
    begin
        case code is
            when "0000" => return "add";
            when "1000" => return "sub";
            when "0001" => return "sll";
            when "0101" => return "srl";
            when "1101" => return "sra";
            when "0010" => return "slt";
            when "0011" => return "sltu";
            when "0100" => return "xor";
            when "0110" => return "or";
            when "0111" => return "and";
            when others => return "unused " & to_string(code);
        end case;
    end function;

    type word_array is array (natural range <>) of word_t;
    constant CORNERS : word_array := (
        x"00000000", x"00000001", x"FFFFFFFF", x"7FFFFFFF", x"80000000",
        x"AAAAAAAA", x"55555555", x"0000001F", x"FFFFFFE1", x"12345678");
begin
    watchdog : tb_watchdog(done, 10 ms);

    dut : entity work.alu
        port map(
            A_input     => A_input,
            B_input     => B_input,
            alu_control => alu_control,
            res_out     => res_out,
            Z           => Z
        );

    stimulus : process
        variable n_carry, n_borrow, n_z_arith, n_z_logic, n_z_shift : natural := 0;
        variable n_slt_true, n_slt_false, n_slt_ne_sltu, n_sra_neg, n_sh0, n_sh31 : natural := 0;

        -- apply one operation and check it; corrupt_* inject a wrong prediction
        procedure check_op(a, b : word_t; code : std_logic_vector(3 downto 0);
                           corrupt_res : boolean := false; corrupt_z : boolean := false) is
            variable exp   : word_t := model(a, b, code);
            variable exp_z : std_logic := '0';
        begin
            if exp = x"00000000" then exp_z := '1'; end if;
            if corrupt_res then exp := exp xor x"00000001"; end if;
            if corrupt_z then exp_z := not exp_z; end if;
            A_input     <= a;
            B_input     <= b;
            alu_control <= code;
            wait for C_SETTLE;
            tb_check_equal(res_out, exp, op_name(code) & " a=" & to_str(a) & " b=" & to_str(b));
            tb_check_equal(Z, exp_z, "Z for " & op_name(code) & " a=" & to_str(a) & " b=" & to_str(b));

            -- coverage
            case code is
                when "0000" => if m_carry(a, b) then n_carry := n_carry + 1; end if;
                when "1000" => if m_ltu(a, b) then n_borrow := n_borrow + 1; end if;
                when "0010" =>
                    if m_lts(a, b) then n_slt_true := n_slt_true + 1; else n_slt_false := n_slt_false + 1; end if;
                    if m_lts(a, b) /= m_ltu(a, b) then n_slt_ne_sltu := n_slt_ne_sltu + 1; end if;
                when "1101" => if a(31) = '1' and b(4 downto 0) /= "00000" then n_sra_neg := n_sra_neg + 1; end if;
                when others => null;
            end case;
            if code = "0001" or code = "0101" or code = "1101" then
                if b(4 downto 0) = "00000" then n_sh0 := n_sh0 + 1; end if;
                if b(4 downto 0) = "11111" then n_sh31 := n_sh31 + 1; end if;
            end if;
            if exp_z = '1' and not corrupt_z then
                case code is
                    when "0000" | "1000" | "0010" | "0011" => n_z_arith := n_z_arith + 1;
                    when "0100" | "0110" | "0111" => n_z_logic := n_z_logic + 1;
                    when "0001" | "0101" | "1101" => n_z_shift := n_z_shift + 1;
                    when others => null;
                end case;
            end if;
        end procedure;

        impure function rnd_operand return word_t is
        begin
            if rnd.bool(0.2) then
                return CORNERS(rnd.int(0, CORNERS'length - 1));
            end if;
            return rnd.slv(32);
        end function;

        variable a, b : word_t;
    begin
        rnd.seed(G_SEED);
        tb_info("alu_tb seed=" & integer'image(G_SEED) & " n_rand=" & integer'image(G_N_RAND));

        tb_info("T1: corner operands x all 16 codes");
        for code in 0 to 15 loop
            for i in CORNERS'range loop
                for j in CORNERS'range loop
                    check_op(CORNERS(i), CORNERS(j), std_logic_vector(to_unsigned(code, 4)));
                end loop;
            end loop;
        end loop;

        tb_info("T2: equal operands (sub = 0, slt = 0)");
        for i in CORNERS'range loop
            check_op(CORNERS(i), CORNERS(i), "1000");
            check_op(CORNERS(i), CORNERS(i), "0010");
            check_op(CORNERS(i), CORNERS(i), "0011");
            check_op(CORNERS(i), CORNERS(i), "0100");
        end loop;

        tb_info("T3: random operands x all 16 codes");
        tb_set_verbose(false);
        for k in 1 to G_N_RAND loop
            a := rnd_operand;
            b := rnd_operand;
            if rnd.bool(0.1) then b := a; end if;   -- equal operands are rare otherwise
            check_op(a, b, std_logic_vector(to_unsigned(rnd.int(0, 15), 4)));
        end loop;
        tb_set_verbose(true);

        tb_info("coverage: carry=" & integer'image(n_carry) & " borrow=" & integer'image(n_borrow) &
                " Z(arith/logic/shift)=" & integer'image(n_z_arith) & "/" & integer'image(n_z_logic) &
                "/" & integer'image(n_z_shift) & " slt(t/f)=" & integer'image(n_slt_true) & "/" &
                integer'image(n_slt_false) & " slt/=sltu=" & integer'image(n_slt_ne_sltu) &
                " sra<0=" & integer'image(n_sra_neg) & " sh0=" & integer'image(n_sh0) &
                " sh31=" & integer'image(n_sh31));
        tb_check(n_carry > 0 and n_borrow > 0, "coverage: add carry-out / sub borrow never hit");
        tb_check(n_z_arith > 0 and n_z_logic > 0 and n_z_shift > 0, "coverage: Z=1 not seen for every op group");
        tb_check(n_slt_true > 0 and n_slt_false > 0 and n_slt_ne_sltu > 0, "coverage: slt outcomes");
        tb_check(n_sra_neg > 0 and n_sh0 > 0 and n_sh31 > 0, "coverage: shift corners");

        if G_INJECT then
            tb_expect_errors(1, "E1: wrong result prediction (add) must be caught");
            check_op(x"00000003", x"00000004", "0000", corrupt_res => true);
            tb_end_expect;
            tb_expect_errors(1, "E2: wrong Z prediction must be caught");
            check_op(x"00000005", x"00000005", "1000", corrupt_z => true);
            tb_end_expect;
        end if;

        done <= true;
        tb_finish;
        wait;
    end process stimulus;
end architecture sim;
