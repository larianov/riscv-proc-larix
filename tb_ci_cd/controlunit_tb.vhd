--------------------------------------------------------------------------------
-- controlunit_tb : exhaustive self-checking testbench for ControlUnit (combinational)
--
-- Spec: README "Control signals" table (blank = 0), "Supported instructions", "CSRs".
--   F1 every opcode (128) x funct3 (8) x funct7 (128) gives the table's outputs for legal
--      instructions; for SYSTEM also rs1 = 0 / 1 / 31 (csrrs/csrrc with rs1 = x0 must not write)
--   F2 illegal (fence, ecall, ebreak, csrr*i, unknown opcode/funct3/funct7): Illegal = 1 and
--      no side effect: RegWrite, Mem_Write, CSRwrite, MRET, Branch, Jump all 0. The other
--      outputs are don't care.
--   F3 outside SYSTEM the decode does not depend on rs1 (rs1 is random there)
--
-- Checking: all 22 output bits packed into one vector, compared with std_match against a
-- reference written from the README table (riscv_ref_pkg, '-' = don't care).
-- E1 wrong prediction for one instruction must be caught.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tb_pkg.all;
use work.riscv_ref_pkg.all;

entity controlunit_tb is
    generic(
        G_SEED   : positive := 1;
        G_INJECT : boolean  := true
    );
end entity controlunit_tb;

architecture sim of controlunit_tb is
    constant C_SETTLE : time := 1 ns;

    signal opcode : std_logic_vector(6 downto 0) := (others => '0');
    signal funct3 : std_logic_vector(2 downto 0) := (others => '0');
    signal funct7 : std_logic_vector(6 downto 0) := (others => '0');
    signal rs1    : std_logic_vector(4 downto 0) := (others => '0');
    signal RegWrite, BSrc, Illegal, Branch, Mem_Write, JalrReg, Jump, CSRwrite, MRET : std_logic;
    signal ASrc, Result_Src, CSRop : std_logic_vector(1 downto 0);
    signal ImmSrc      : std_logic_vector(2 downto 0);
    signal alu_control : std_logic_vector(3 downto 0);
    signal done        : boolean := false;

    shared variable rnd : tb_rand_t;

begin
    watchdog : tb_watchdog(done, 10 ms);

    dut : entity work.ControlUnit
        port map(opcode => opcode, funct3 => funct3, funct7 => funct7, RegWrite => RegWrite,
                 ASrc => ASrc, BSrc => BSrc, Illegal => Illegal, Branch => Branch, ImmSrc => ImmSrc,
                 alu_control => alu_control, Mem_Write => Mem_Write, Result_Src => Result_Src,
                 JalrReg => JalrReg, Jump => Jump, rs1 => rs1, CSRwrite => CSRwrite, CSRop => CSRop, MRET => MRET);

    stimulus : process
        type int_array is array (natural range <>) of natural;
        constant RS1_SYSTEM : int_array := (0, 1, 31);
        variable n_legal, n_illegal : natural := 0;

        procedure check_one(op, f3, f7, r1 : natural; corrupt : boolean := false) is
            variable exp : ctl_t := ref_decode(op, f3, f7, r1);
            variable e, g : std_logic_vector(21 downto 0);
        begin
            if corrupt then exp.RegWrite := not exp.RegWrite; end if;
            opcode <= std_logic_vector(to_unsigned(op, 7));
            funct3 <= std_logic_vector(to_unsigned(f3, 3));
            funct7 <= std_logic_vector(to_unsigned(f7, 7));
            rs1    <= std_logic_vector(to_unsigned(r1, 5));
            wait for C_SETTLE;
            e := pack(exp);
            g := RegWrite & ASrc & BSrc & Illegal & Branch & ImmSrc & Mem_Write & Result_Src &
                 alu_control & CSRwrite & CSRop & MRET & JalrReg & Jump;
            if std_match(g, e) then
                tb_check(true, "");
            else
                tb_check(false, "decode op=" & to_hstring(std_logic_vector(to_unsigned(op, 8))) &
                                " f3=" & integer'image(f3) & " f7=" & integer'image(f7) &
                                " rs1=" & integer'image(r1) & LF &
                                "        fields " & CTL_FIELDS & LF &
                                "        got      " & to_string(g) & LF & "        expected " & to_string(e));
            end if;
            if exp.Illegal = '1' then n_illegal := n_illegal + 1; else n_legal := n_legal + 1; end if;
        end procedure;
    begin
        rnd.seed(G_SEED);
        tb_info("controlunit_tb seed=" & integer'image(G_SEED));
        tb_info("T1: all opcode x funct3 x funct7 (SYSTEM also rs1 = 0/1/31)");
        tb_set_verbose(false);
        for op in 0 to 127 loop
            for f3 in 0 to 7 loop
                for f7 in 0 to 127 loop
                    if op = 16#73# then
                        for r in RS1_SYSTEM'range loop
                            check_one(op, f3, f7, RS1_SYSTEM(r));
                        end loop;
                    else
                        check_one(op, f3, f7, rnd.int(0, 31));
                    end if;
                end loop;
            end loop;
        end loop;
        tb_set_verbose(true);
        tb_info("legal combinations: " & integer'image(n_legal) & ", illegal: " & integer'image(n_illegal));
        tb_check(n_legal > 0 and n_illegal > 0, "coverage: legal and illegal decodes");

        if G_INJECT then
            tb_expect_errors(1, "E1: wrong decode prediction (add) must be caught");
            check_one(16#33#, 0, 0, 1, corrupt => true);
            tb_end_expect;
        end if;

        done <= true;
        tb_finish;
        wait;
    end process stimulus;
end architecture sim;
