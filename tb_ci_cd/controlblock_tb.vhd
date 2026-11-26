--------------------------------------------------------------------------------
-- controlblock_tb : self-checking testbench for controlblock (combinational)
--
-- Spec: README "controlblock", "Control signals", "CSRs and interrupts".
--   F1 decode outputs = ControlUnit's (README table), for every opcode/funct3 and random fields
--   F2 TRAP = irq and MIE and MEIE (all 8 combinations)
--   F3 TRAP forces RegWrite and Mem_Write to 0 (the other decode outputs pass through)
--   F4 branch taken: beq on Zero = 1, bne on Zero = 0, blt/bltu when slt = 1 (Zero = 0),
--      bge/bgeu when slt = 0 (Zero = 1); jal/jalr always jump
--   F5 PCsrc priority: 10 TRAP, else 11 MRET, else 01 taken branch / jump, else 00
--   F6 an illegal instruction never jumps or writes (PCsrc 00 unless TRAP)
--
-- Checking: reference decode from riscv_ref_pkg (README table), branch decision written as
-- an explicit per-instruction table (not the RTL's xor formula), all outputs every vector.
-- Stimulus: every opcode x funct3 x Zero x (irq, MIE, MEIE) with random funct7/rs1/rest,
-- the listed example instructions, then G_N_RAND fully random instructions.
-- E1 wrong PCsrc prediction must be caught.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tb_pkg.all;
use work.riscv_ref_pkg.all;

entity controlblock_tb is
    generic(
        G_SEED   : positive := 1;
        G_N_RAND : natural  := 20000;
        G_INJECT : boolean  := true
    );
end entity controlblock_tb;

architecture sim of controlblock_tb is
    subtype word_t is std_logic_vector(31 downto 0);
    constant C_SETTLE : time := 1 ns;

    signal instr       : word_t := (others => '0');
    signal zero        : std_logic := '0';
    signal irq, MIE, MEIE : std_logic := '0';
    signal Illegal, RegWrite, BSrc, Mem_Write, JalrReg, TRAP, CSWrite, MRET : std_logic;
    signal PCsrc, Result_Src, CSRop, ASrc : std_logic_vector(1 downto 0);
    signal ImmSrc      : std_logic_vector(2 downto 0);
    signal alu_control : std_logic_vector(3 downto 0);
    signal done        : boolean := false;

    shared variable rnd : tb_rand_t;
begin
    watchdog : tb_watchdog(done, 10 ms);

    dut : entity work.controlblock
        port map(instr => instr, zero => zero, Illegal => Illegal, RegWrite => RegWrite,
                 ASrc => ASrc, BSrc => BSrc, ImmSrc => ImmSrc, alu_control => alu_control, PCsrc => PCsrc,
                 Mem_Write => Mem_Write, Result_Src => Result_Src, JalrReg => JalrReg, irq => irq, MIE => MIE,
                 MEIE => MEIE, TRAP => TRAP, CSRop => CSRop, CSWrite => CSWrite, MRET => MRET);

    stimulus : process
        type count_array is array (0 to 3) of natural;
        variable pcsrc_hits : count_array := (others => 0);
        variable n_trap_blocked : natural := 0;

        -- is a branch/jump taken? (README "Branch taken", stated per instruction)
        function taken(c : ctl_t; f3 : natural; z : std_logic) return boolean is
        begin
            if c.Jump = '1' then return true; end if;
            if c.Branch /= '1' then return false; end if;
            case f3 is
                when 0     => return z = '1';         -- beq: a - b = 0
                when 1     => return z = '0';         -- bne
                when 4 | 6 => return z = '0';         -- blt / bltu: slt = 1 -> result /= 0
                when 5 | 7 => return z = '1';         -- bge / bgeu: slt = 0
                when others => return false;
            end case;
        end function;

        procedure check_vec(w : word_t; z, i, m, e : std_logic; corrupt : boolean := false) is
            variable c        : ctl_t := ref_decode(w);
            variable trap     : std_logic := i and m and e;
            variable exp_pc   : std_logic_vector(1 downto 0);
            variable exp, got : std_logic_vector(21 downto 0);
            variable f3       : natural := to_integer(unsigned(w(14 downto 12)));
        begin
            if trap = '1' then
                exp_pc := "10";
                if c.RegWrite = '1' or c.MemWrite = '1' then n_trap_blocked := n_trap_blocked + 1; end if;
                c.RegWrite := '0';
                c.MemWrite := '0';
            elsif c.MRET = '1' then
                exp_pc := "11";
            elsif taken(c, f3, z) then
                exp_pc := "01";
            else
                exp_pc := "00";
            end if;
            if corrupt then exp_pc := not exp_pc; end if;

            instr <= w; zero <= z; irq <= i; MIE <= m; MEIE <= e;
            wait for C_SETTLE;
            tb_check_equal(TRAP, trap, "TRAP irq/MIE/MEIE=" & to_str(i) & to_str(m) & to_str(e));
            tb_check_equal(PCsrc, exp_pc, "PCsrc instr=" & to_str(w) & " zero=" & to_str(z) &
                                          " trap=" & to_str(trap));
            -- controlblock has no Branch/Jump outputs: those bits are don't care
            got := RegWrite & ASrc & BSrc & Illegal & '-' & ImmSrc & Mem_Write & Result_Src &
                   alu_control & CSWrite & CSRop & MRET & JalrReg & '-';
            exp := pack(c);
            exp(16) := '-';    -- Branch
            exp(0)  := '-';    -- Jump
            tb_check(std_match(got, exp),
                     "decode instr=" & to_str(w) & " trap=" & to_str(trap) & LF &
                     "        fields " & CTL_FIELDS & LF &
                     "        got      " & to_string(got) & LF & "        expected " & to_string(exp));
            pcsrc_hits(to_integer(unsigned(PCsrc))) := pcsrc_hits(to_integer(unsigned(PCsrc))) + 1;
        end procedure;

        procedure check_all_ctx(w : word_t) is
        begin
            for k in 0 to 15 loop
                check_vec(w, std_logic(to_unsigned(k, 4)(3)), std_logic(to_unsigned(k, 4)(2)),
                          std_logic(to_unsigned(k, 4)(1)), std_logic(to_unsigned(k, 4)(0)));
            end loop;
        end procedure;

        type word_array is array (natural range <>) of word_t;
        constant EXAMPLES : word_array := (
            x"00500093",   -- addi x1,x0,5
            x"40208133",   -- sub x2,x1,x2
            x"0020A423",   -- sw x2,8(x1)
            x"008000EF",   -- jal x1,+8
            x"00408167",   -- jalr x2,4(x1)
            x"00409167",   -- jalr funct3=1: illegal
            x"123450B7",   -- lui
            x"00001117",   -- auipc
            x"00000463",   -- beq x0,x0,+8
            x"30559673",   -- csrrw x12,mtvec,x11
            x"30082073",   -- csrrs x0,mstatus,x16
            x"30002973",   -- csrrs x18,mstatus,x0 (read only)
            x"30083073",   -- csrrc
            x"30003073",   -- csrrc rs1=x0
            x"30200073",   -- mret
            x"00000073",   -- ecall: illegal
            x"00100073",   -- ebreak: illegal
            x"3005D073",   -- csrrwi: illegal
            x"0000000F",   -- fence: illegal
            x"FFFFFFFF");  -- garbage
        variable w : word_t;
    begin
        rnd.seed(G_SEED);
        tb_info("controlblock_tb seed=" & integer'image(G_SEED));

        tb_info("T1: example instructions x Zero x irq/MIE/MEIE");
        for i in EXAMPLES'range loop
            check_all_ctx(EXAMPLES(i));
        end loop;

        tb_info("T2: every opcode x funct3 x Zero x irq/MIE/MEIE, random other fields");
        tb_set_verbose(false);
        for op in 0 to 127 loop
            for f3 in 0 to 7 loop
                w := rnd.slv(32);
                w(6 downto 0) := std_logic_vector(to_unsigned(op, 7));
                w(14 downto 12) := std_logic_vector(to_unsigned(f3, 3));
                if rnd.bool then w(31 downto 25) := "0000000"; end if;   -- make R/I-type legal often
                check_all_ctx(w);
            end loop;
        end loop;

        tb_info("T3: random instructions with random context");
        for k in 1 to G_N_RAND loop
            w := rnd.slv(32);
            if rnd.bool(0.7) then   -- bias towards valid opcodes
                case rnd.int(0, 9) is
                    when 0 => w(6 downto 0) := "0110011";
                    when 1 => w(6 downto 0) := "0010011";
                    when 2 => w(6 downto 0) := "0000011";
                    when 3 => w(6 downto 0) := "0100011";
                    when 4 => w(6 downto 0) := "1100011";
                    when 5 => w(6 downto 0) := "1101111";
                    when 6 => w(6 downto 0) := "1100111";
                    when 7 => w(6 downto 0) := "0110111";
                    when 8 => w(6 downto 0) := "0010111";
                    when others => w(6 downto 0) := "1110011";
                end case;
            end if;
            check_vec(w, rnd.slv(1)(0), rnd.slv(1)(0), rnd.slv(1)(0), rnd.slv(1)(0));
        end loop;
        tb_set_verbose(true);

        tb_info("coverage: PCsrc 00/01/10/11 = " & integer'image(pcsrc_hits(0)) & "/" &
                integer'image(pcsrc_hits(1)) & "/" & integer'image(pcsrc_hits(2)) & "/" &
                integer'image(pcsrc_hits(3)) & ", trap blocked a write " & integer'image(n_trap_blocked));
        for k in 0 to 3 loop
            tb_check(pcsrc_hits(k) > 0, "coverage: PCsrc value " & integer'image(k) & " never produced");
        end loop;
        tb_check(n_trap_blocked > 0, "coverage: trap never cancelled a write");

        if G_INJECT then
            tb_expect_errors(1, "E1: wrong PCsrc prediction must be caught");
            check_vec(x"008000EF", '0', '0', '0', '0', corrupt => true);
            tb_end_expect;
        end if;

        done <= true;
        tb_finish;
        wait;
    end process stimulus;
end architecture sim;
