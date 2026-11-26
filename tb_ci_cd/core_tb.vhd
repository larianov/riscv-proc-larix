--------------------------------------------------------------------------------
-- core_tb : random-program testbench for core against an instruction-level RV32I model
--
-- Spec: README "Supported instructions", "CSRs", top-level port meanings, RV32I semantics.
-- irq = 0 here (interrupts: core_irq_tb).
--   F1 every supported instruction does what RV32I says: R-type, I-type ALU, lui, auipc,
--      lb lh lw lbu lhu, sb sh sw, beq bne blt bge bltu bgeu, jal, jalr (bit 0 cleared),
--      csrrw csrrs csrrc (csrrs/csrrc with rs1 = x0 only read)
--   F2 misaligned lh/lhu/lw read 0; misaligned sh/sw write nothing (WE = 0000)
--   F3 store interface: WE = exactly the stored byte lanes, each enabled lane carries the
--      right byte of rs2; WE = 0000 for every non-store
--   F4 rez = ALU result: the value for ALU ops, the data address for loads/stores, the
--      lui/auipc result, rs1-rs2 / slt / sltu for branches (jal/jalr/CSR: not checked)
--   F5 illegal instructions (fence, ecall, ebreak, csrr*i, bad funct3/funct7, unknown opcode):
--      Illegal = 1, executed as a no-op: no register write, no store, PC + 4
--   F6 x0 stays 0 (random rd includes x0)
--   F7 reset: PC = 0x0000_1000
--
-- Program (random per seed): prologue sets x1..x15 to random values and x31 = 0x1000 (jalr
-- base, never a destination); body of random instructions on x0..x15 with forward branches/
-- jumps only, so it always terminates; epilogue "add x0, xN, x0" for N = 1..31 exposes every
-- register on rez (black-box register dump); halt "beq x0, x0, 0".
-- Load data comes from a memory model that is a pure function of the address.
-- Checking: PC, Illegal, rez, WE, WD every cycle against the model.
-- E1 wrong PC prediction must be caught.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tb_pkg.all;
use work.riscv_ref_pkg.all;

entity core_tb is
    generic(
        G_SEED   : positive := 1;
        G_INJECT : boolean  := true
    );
end entity core_tb;

architecture sim of core_tb is
    subtype word_t is std_logic_vector(31 downto 0);
    constant C_PERIOD : time := 10 ns;
    constant ROM_SIZE : positive := 1024;
    constant BASE     : natural := 16#1000#;     -- reset vector
    constant BASE_REG : natural := 31;           -- holds BASE, jalr base register
    constant N_REG    : natural := 15;           -- random instructions use x0..x15
    constant NOP      : word_t := x"00000013";
    constant HALT_W   : word_t := x"00000063";   -- beq x0, x0, 0
    type rom_t is array (0 to ROM_SIZE - 1) of word_t;

    signal clk     : std_logic;
    signal run     : boolean := true;
    signal done    : boolean := false;
    signal rst     : std_logic := '1';
    signal instr   : word_t;
    signal PC      : word_t;
    signal Illegal : std_logic;
    signal rez     : word_t;
    signal WE      : std_logic_vector(3 downto 0);
    signal WD      : word_t;
    signal mem_rd  : word_t;
    signal rom     : rom_t := (others => NOP);
    signal halt_pc : natural := BASE;

    shared variable rnd : tb_rand_t;

    ---------------------------------------------------------------- encoders (assembler)
    function u(v, n : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(v, n));
    end function;

    function enc_r(f7, rs2, rs1, f3, rd : natural) return word_t is
    begin
        return u(f7, 7) & u(rs2, 5) & u(rs1, 5) & u(f3, 3) & u(rd, 5) & "0110011";
    end function;

    function enc_i(op : std_logic_vector(6 downto 0); imm : integer; rs1, f3, rd : natural) return word_t is
    begin
        return std_logic_vector(to_signed(imm, 12)) & u(rs1, 5) & u(f3, 3) & u(rd, 5) & op;
    end function;

    function enc_s(imm : integer; rs2, rs1, f3 : natural) return word_t is
        variable o : std_logic_vector(11 downto 0) := std_logic_vector(to_signed(imm, 12));
    begin
        return o(11 downto 5) & u(rs2, 5) & u(rs1, 5) & u(f3, 3) & o(4 downto 0) & "0100011";
    end function;

    function enc_b(off : integer; rs2, rs1, f3 : natural) return word_t is
        variable o : std_logic_vector(12 downto 0) := std_logic_vector(to_signed(off, 13));
    begin
        return o(12) & o(10 downto 5) & u(rs2, 5) & u(rs1, 5) & u(f3, 3) & o(4 downto 1) & o(11) & "1100011";
    end function;

    function enc_j(off : integer; rd : natural) return word_t is
        variable o : std_logic_vector(20 downto 0) := std_logic_vector(to_signed(off, 21));
    begin
        return o(20) & o(10 downto 1) & o(11) & o(19 downto 12) & u(rd, 5) & "1101111";
    end function;

    function enc_u(imm20 : natural; rd : natural; op : std_logic_vector(6 downto 0)) return word_t is
    begin
        return u(imm20, 20) & u(rd, 5) & op;
    end function;

    function enc_csr(csr : std_logic_vector(11 downto 0); rs1, f3, rd : natural) return word_t is
    begin
        return csr & u(rs1, 5) & u(f3, 3) & u(rd, 5) & "1110011";
    end function;

    ---------------------------------------------------------------- data memory model
    function mem_word(addr : word_t) return word_t is
        variable a : unsigned(31 downto 0) := unsigned(addr(31 downto 2)) & "00";
    begin
        return std_logic_vector(resize(a * unsigned'(x"9E3779B1"), 32) xor x"5A5AC3C3");
    end function;
begin
    clock    : tb_clock(clk, C_PERIOD, run);
    watchdog : tb_watchdog(done, 2 ms);

    -- instruction fetch: combinational ROM at BASE, nop elsewhere
    instr <= rom((to_integer(unsigned(PC)) - BASE) / 4)
             when unsigned(PC) >= BASE and unsigned(PC) < BASE + 4 * ROM_SIZE else NOP;
    mem_rd <= mem_word(rez);

    dut : entity work.core
        port map(rst => rst, clk => clk, instr => instr, PC => PC, Illegal => Illegal, rez => rez,
                 OUT_OF_MEMORY_DATA => mem_rd, WD => WD, WE => WE, irq => '0');

    ---------------------------------------------------------------- program generator
    gen : process
        variable p   : rom_t := (others => NOP);
        variable n   : natural := 0;
        variable f3, kind : natural;
        type csr_array is array (natural range <>) of std_logic_vector(11 downto 0);
        constant CSRS : csr_array := (x"300", x"304", x"305", x"341", x"342", x"344", x"340");
        type word_array is array (natural range <>) of word_t;
        constant ILLEGALS : word_array := (
            x"0000000F",  -- fence
            x"00000073",  -- ecall
            x"00100073",  -- ebreak
            x"3005D073",  -- csrrwi
            x"30516073",  -- csrrsi
            x"30517073",  -- csrrci
            x"00004073",  -- SYSTEM funct3 = 4
            x"02208133",  -- mul (funct7 = 1)
            x"40209133",  -- sll with funct7 = 0x20
            x"4020C133",  -- xor with funct7 = 0x20
            x"0020B183",  -- load funct3 = 3 (ld)
            x"0020E183",  -- load funct3 = 6
            x"0020B023",  -- store funct3 = 3 (sd)
            x"0020C023",  -- store funct3 = 4
            x"00002063",  -- branch funct3 = 2
            x"00003063",  -- branch funct3 = 3
            x"00009067",  -- jalr funct3 = 1
            x"40209093",  -- slli with funct7 = 0x20
            x"0420D093",  -- srli with funct7 = 2
            x"00000000",  -- all zero
            x"FFFFFFFF",  -- all ones
            x"0000002B",  -- custom opcode
            x"00000057"); -- vector opcode

        impure function r_reg return natural is
        begin
            return rnd.int_skewed(0, N_REG);
        end function;

        procedure emit(w : word_t) is
        begin
            p(n) := w;
            n := n + 1;
        end procedure;
    begin
        rnd.seed(G_SEED);
        -- prologue: x1..x15 random (lui + addi), x31 = BASE
        for r in 1 to N_REG loop
            emit(enc_u(rnd.int(0, 1048575), r, "0110111"));
            emit(enc_i("0010011", rnd.int(-2048, 2047), r, 0, r));
        end loop;
        emit(enc_u(BASE / 4096, BASE_REG, "0110111"));

        -- body
        while n < ROM_SIZE - 40 loop
            kind := rnd.int(0, 99);
            if kind < 22 then                                    -- R-type
                case rnd.int(0, 9) is
                    when 0 => emit(enc_r(0, r_reg, r_reg, 0, r_reg));
                    when 1 => emit(enc_r(32, r_reg, r_reg, 0, r_reg));
                    when 2 => emit(enc_r(32, r_reg, r_reg, 5, r_reg));
                    when others => emit(enc_r(0, r_reg, r_reg, rnd.int(1, 7), r_reg));
                end case;
            elsif kind < 40 then                                 -- I-type ALU
                f3 := rnd.int(0, 7);
                if f3 = 1 then
                    emit(enc_i("0010011", rnd.int(0, 31), r_reg, 1, r_reg));            -- slli
                elsif f3 = 5 then
                    emit(enc_i("0010011", rnd.int(0, 31) + 1024 * rnd.int(0, 1), r_reg, 5, r_reg));  -- srli / srai
                else
                    emit(enc_i("0010011", rnd.int_skewed(-2048, 2047), r_reg, f3, r_reg));
                end if;
            elsif kind < 50 then                                 -- loads, any base, any alignment
                case rnd.int(0, 4) is
                    when 0 => f3 := 0;
                    when 1 => f3 := 1;
                    when 2 => f3 := 2;
                    when 3 => f3 := 4;
                    when others => f3 := 5;
                end case;
                emit(enc_i("0000011", rnd.int(-2048, 2047), r_reg, f3, r_reg));
            elsif kind < 60 then                                 -- stores, any alignment
                emit(enc_s(rnd.int(-2048, 2047), r_reg, r_reg, rnd.int(0, 2)));
            elsif kind < 70 then                                 -- forward branches, all six
                case rnd.int(0, 5) is
                    when 0 => f3 := 0;
                    when 1 => f3 := 1;
                    when 2 => f3 := 4;
                    when 3 => f3 := 5;
                    when 4 => f3 := 6;
                    when others => f3 := 7;
                end case;
                if rnd.bool(0.3) then
                    emit(enc_b(4 * rnd.int(2, 3), rnd.int(0, N_REG), rnd.int(0, N_REG) mod 4, f3));   -- small regs: equal more often
                else
                    emit(enc_b(4 * rnd.int(2, 3), r_reg, r_reg, f3));
                end if;
            elsif kind < 74 then                                 -- jal forward
                emit(enc_j(4 * rnd.int(1, 3), r_reg));
            elsif kind < 78 and n < 480 then                     -- jalr x31 + odd imm -> bit 0 cleared
                emit(enc_i("1100111", 4 * (n + 1 + rnd.int(1, 2)) + rnd.int(0, 1), BASE_REG, 0, r_reg));
            elsif kind < 84 then                                 -- lui / auipc
                if rnd.bool then
                    emit(enc_u(rnd.int(0, 1048575), r_reg, "0110111"));
                else
                    emit(enc_u(rnd.int(0, 1048575), r_reg, "0010111"));
                end if;
            elsif kind < 94 then                                 -- csrrw / csrrs / csrrc
                emit(enc_csr(CSRS(rnd.int(0, CSRS'length - 1)), r_reg, rnd.int(1, 3), r_reg));
            else                                                 -- illegal: no-op
                emit(ILLEGALS(rnd.int(0, ILLEGALS'length - 1)));
            end if;
        end loop;

        -- epilogue: register dump through rez, then halt
        for r in 1 to 31 loop
            emit(enc_r(0, 0, r, 0, 0));                          -- add x0, xr, x0
        end loop;
        halt_pc <= BASE + 4 * n;
        emit(HALT_W);
        rom <= p;
        wait;
    end process gen;

    ---------------------------------------------------------------- model + checker
    check : process
        type reg_array is array (0 to 31) of word_t;
        variable regs : reg_array := (others => (others => '0'));
        variable pc_m : natural := BASE;
        variable s_mie, s_mpie, s_meie : std_logic := '0';
        variable s_mtvec, s_mepc, s_mcause : word_t := (others => '0');

        type count_t is record
            r, i, ld, ld_mis, st, st_mis, br_t, br_n, jal, jalr, lui, auipc, csr, csr_ro, ill, x0_wr : natural;
        end record;
        variable cnt : count_t := (others => 0);
        type br_array is array (0 to 7) of natural;
        variable br_taken, br_not : br_array := (others => 0);
        variable cycles : natural := 0;

        impure function csr_read(num : std_logic_vector(11 downto 0)) return word_t is
            variable v : word_t := (others => '0');
        begin
            case num is
                when x"300" => v(3) := s_mie; v(7) := s_mpie;
                when x"304" => v(11) := s_meie;
                when x"305" => v := s_mtvec;
                when x"341" => v := s_mepc;
                when x"342" => v := s_mcause;
                when others => null;                              -- mip = irq = 0, unknown = 0
            end case;
            return v;
        end function;

        procedure csr_write(num : std_logic_vector(11 downto 0); v : word_t) is
        begin
            case num is
                when x"300" => s_mie := v(3); s_mpie := v(7);
                when x"304" => s_meie := v(11);
                when x"305" => s_mtvec := v;
                when x"341" => s_mepc := v;
                when x"342" => s_mcause := v;
                when others => null;
            end case;
        end procedure;

        function load_val(f3 : natural; addr : word_t) return word_t is
            variable w    : word_t := mem_word(addr);
            variable off  : natural := to_integer(unsigned(addr(1 downto 0)));
            variable size : natural;
            variable v    : word_t := (others => '0');
        begin
            case f3 is
                when 0 | 4 => size := 1;
                when 1 | 5 => size := 2;
                when others => size := 4;
            end case;
            if off mod size /= 0 then
                return x"00000000";
            end if;
            v(8 * size - 1 downto 0) := w(8 * (off + size) - 1 downto 8 * off);
            if (f3 = 0 or f3 = 1) and v(8 * size - 1) = '1' then
                v(31 downto 8 * size) := (others => '1');
            end if;
            return v;
        end function;

        -- model one instruction; checks DUT outputs of this cycle
        procedure step(w : word_t; corrupt : boolean := false) is
            variable op  : std_logic_vector(6 downto 0) := w(6 downto 0);
            variable f3  : natural := to_integer(unsigned(w(14 downto 12)));
            variable f7  : natural := to_integer(unsigned(w(31 downto 25)));
            variable rd  : natural := to_integer(unsigned(w(11 downto 7)));
            variable rs1 : natural := to_integer(unsigned(w(19 downto 15)));
            variable rs2 : natural := to_integer(unsigned(w(24 downto 20)));
            variable a   : word_t := regs(rs1);
            variable b   : word_t := regs(rs2);
            variable c   : ctl_t := ref_decode(w);   -- only used for "is it legal"
            variable imm_i : word_t := std_logic_vector(resize(signed(w(31 downto 20)), 32));
            variable imm_s : word_t := std_logic_vector(resize(signed(std_logic_vector'(w(31 downto 25) & w(11 downto 7))), 32));
            variable imm_b : word_t := std_logic_vector(resize(signed(std_logic_vector'(w(31) & w(7) & w(30 downto 25) & w(11 downto 8) & '0')), 32));
            variable imm_j : word_t := std_logic_vector(resize(signed(std_logic_vector'(w(31) & w(19 downto 12) & w(20) & w(30 downto 21) & '0')), 32));
            variable imm_u : word_t := w(31 downto 12) & x"000";
            variable pcv   : word_t := std_logic_vector(to_unsigned(pc_m, 32));
            variable next_pc : natural := pc_m + 4;
            variable exp_rez : word_t;
            variable chk_rez : boolean := true;
            variable wr_val  : word_t;
            variable do_wr   : boolean := false;
            variable exp_we  : std_logic_vector(3 downto 0) := "0000";
            variable size, off : natural;
            variable taken   : boolean;
            variable old     : word_t;
            variable exp_pc  : word_t := pcv;
            variable tgt     : word_t;
        begin
            if corrupt then exp_pc := std_logic_vector(unsigned(pcv) + 4); end if;
            tb_check_equal(PC, exp_pc, "PC");
            tb_check_equal(Illegal, c.Illegal, "Illegal for " & to_str(w) & " at " & to_str(pcv));

            if c.Illegal = '1' then
                chk_rez := false;
                cnt.ill := cnt.ill + 1;
            elsif op = "0110011" then                                     -- R-type
                exp_rez := ref_alu(a, b, alu_code(f3, f7 = 32));
                wr_val := exp_rez; do_wr := true;
                cnt.r := cnt.r + 1;
            elsif op = "0010011" then                                     -- I-type ALU
                exp_rez := ref_alu(a, imm_i, alu_code(f3, f3 = 5 and f7 = 32));
                wr_val := exp_rez; do_wr := true;
                cnt.i := cnt.i + 1;
            elsif op = "0000011" then                                     -- load
                exp_rez := std_logic_vector(unsigned(a) + unsigned(imm_i));
                wr_val := load_val(f3, exp_rez); do_wr := true;
                cnt.ld := cnt.ld + 1;
                if (f3 = 1 or f3 = 5) and exp_rez(0) = '1' then cnt.ld_mis := cnt.ld_mis + 1; end if;
                if f3 = 2 and exp_rez(1 downto 0) /= "00" then cnt.ld_mis := cnt.ld_mis + 1; end if;
            elsif op = "0100011" then                                     -- store
                exp_rez := std_logic_vector(unsigned(a) + unsigned(imm_s));
                size := 2 ** f3;
                off  := to_integer(unsigned(exp_rez(1 downto 0)));
                if off mod size = 0 then
                    for i in 0 to size - 1 loop
                        exp_we(off + i) := '1';
                    end loop;
                else
                    cnt.st_mis := cnt.st_mis + 1;
                end if;
                cnt.st := cnt.st + 1;
            elsif op = "1100011" then                                     -- branch
                case f3 is
                    when 0 => taken := a = b;                          exp_rez := ref_alu(a, b, "1000");
                    when 1 => taken := a /= b;                         exp_rez := ref_alu(a, b, "1000");
                    when 4 => taken := signed(a) < signed(b);          exp_rez := ref_alu(a, b, "0010");
                    when 5 => taken := signed(a) >= signed(b);         exp_rez := ref_alu(a, b, "0010");
                    when 6 => taken := unsigned(a) < unsigned(b);      exp_rez := ref_alu(a, b, "0011");
                    when others => taken := unsigned(a) >= unsigned(b); exp_rez := ref_alu(a, b, "0011");
                end case;
                if taken then
                    next_pc := to_integer(unsigned(pcv) + unsigned(imm_b));
                    br_taken(f3) := br_taken(f3) + 1;
                    cnt.br_t := cnt.br_t + 1;
                else
                    br_not(f3) := br_not(f3) + 1;
                    cnt.br_n := cnt.br_n + 1;
                end if;
            elsif op = "1101111" then                                     -- jal
                chk_rez := false;
                wr_val := std_logic_vector(to_unsigned(pc_m + 4, 32)); do_wr := true;
                next_pc := to_integer(unsigned(pcv) + unsigned(imm_j));
                cnt.jal := cnt.jal + 1;
            elsif op = "1100111" then                                     -- jalr
                chk_rez := false;
                wr_val := std_logic_vector(to_unsigned(pc_m + 4, 32)); do_wr := true;
                tgt := std_logic_vector(unsigned(a) + unsigned(imm_i));
                tgt(0) := '0';
                next_pc := to_integer(unsigned(tgt));
                cnt.jalr := cnt.jalr + 1;
            elsif op = "0110111" then                                     -- lui
                exp_rez := imm_u;
                wr_val := exp_rez; do_wr := true;
                cnt.lui := cnt.lui + 1;
            elsif op = "0010111" then                                     -- auipc
                exp_rez := std_logic_vector(unsigned(pcv) + unsigned(imm_u));
                wr_val := exp_rez; do_wr := true;
                cnt.auipc := cnt.auipc + 1;
            else                                                          -- csrrw / csrrs / csrrc
                chk_rez := false;
                old := csr_read(w(31 downto 20));
                wr_val := old; do_wr := true;
                case f3 is
                    when 1 => csr_write(w(31 downto 20), a);
                    when 2 => if rs1 /= 0 then csr_write(w(31 downto 20), old or a); else cnt.csr_ro := cnt.csr_ro + 1; end if;
                    when others => if rs1 /= 0 then csr_write(w(31 downto 20), old and not a); else cnt.csr_ro := cnt.csr_ro + 1; end if;
                end case;
                cnt.csr := cnt.csr + 1;
            end if;

            if chk_rez then
                tb_check_equal(rez, exp_rez, "rez for " & to_str(w) & " at " & to_str(pcv));
            end if;
            tb_check_equal(WE, exp_we, "WE for " & to_str(w) & " at " & to_str(pcv));
            for lane in 0 to 3 loop
                if exp_we(lane) = '1' then
                    tb_check_equal(WD(8 * lane + 7 downto 8 * lane), b(8 * (lane - off) + 7 downto 8 * (lane - off)),
                                   "WD lane " & integer'image(lane) & " for " & to_str(w) & " at " & to_str(pcv));
                end if;
            end loop;

            if do_wr then
                if rd = 0 then
                    cnt.x0_wr := cnt.x0_wr + 1;
                else
                    regs(rd) := wr_val;
                end if;
            end if;
            pc_m := next_pc;
        end procedure;
    begin
        tb_info("core_tb seed=" & integer'image(G_SEED));
        wait until falling_edge(clk);
        wait until falling_edge(clk);
        tb_check_equal(PC, x"00001000", "reset vector");
        rst <= '0';

        tb_set_verbose(false);
        while pc_m /= halt_pc loop
            step(rom((pc_m - BASE) / 4));
            cycles := cycles + 1;
            exit when tb_error_count > 20;           -- the model has diverged: stop the flood
            wait until falling_edge(clk);
        end loop;
        tb_set_verbose(true);

        tb_info(integer'image(cycles) & " instructions: R " & integer'image(cnt.r) & ", I " & integer'image(cnt.i) &
                ", load " & integer'image(cnt.ld) & " (misaligned " & integer'image(cnt.ld_mis) & "), store " &
                integer'image(cnt.st) & " (misaligned " & integer'image(cnt.st_mis) & "), branch taken/not " &
                integer'image(cnt.br_t) & "/" & integer'image(cnt.br_n) & ", jal " & integer'image(cnt.jal) &
                ", jalr " & integer'image(cnt.jalr) & ", lui/auipc " & integer'image(cnt.lui) & "/" &
                integer'image(cnt.auipc) & ", csr " & integer'image(cnt.csr) & " (read-only " &
                integer'image(cnt.csr_ro) & "), illegal " & integer'image(cnt.ill) & ", rd=x0 " & integer'image(cnt.x0_wr));
        tb_check(cnt.r > 0 and cnt.i > 0 and cnt.ld_mis > 0 and cnt.st_mis > 0 and cnt.jal > 0 and cnt.jalr > 0 and
                 cnt.lui > 0 and cnt.auipc > 0 and cnt.csr_ro > 0 and cnt.ill > 0 and cnt.x0_wr > 0,
                 "coverage: an instruction class was never executed");
        for f3 in 0 to 7 loop
            if f3 /= 2 and f3 /= 3 then
                tb_check(br_taken(f3) > 0 and br_not(f3) > 0,
                         "coverage: branch funct3=" & integer'image(f3) & " taken " & integer'image(br_taken(f3)) &
                         ", not taken " & integer'image(br_not(f3)));
            end if;
        end loop;

        tb_info("halt loop must stay put");
        for i in 1 to 3 loop
            step(HALT_W);
            wait until falling_edge(clk);
        end loop;

        if G_INJECT then
            tb_expect_errors(1, "E1: wrong PC prediction must be caught");
            step(HALT_W, corrupt => true);
            tb_end_expect;
        end if;

        done <= true;
        run  <= false;
        tb_finish;
        wait;
    end process check;
end architecture sim;
