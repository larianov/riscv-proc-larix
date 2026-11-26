--------------------------------------------------------------------------------
-- datapath_tb : self-checking testbench for DataPath with hand-driven control signals
--
-- Spec: README "Datapath" block table, "ALU codes", "CSRs and interrupts", reset.
-- The control inputs are random and independent of the instruction (ControlUnit is not in
-- this DUT), so every mux / path is exercised in combinations a program would rarely hit.
--   F1 REZ = ALU(A, B, alu_control): A by AluSRCA (00 RD1, 01 PC, 10 zero), B by AluSrcB
--      (0 RD2, 1 ImmExt), ImmExt by ImmSrc from instr; Zero = (REZ = 0)
--   F2 WD = RD2 (register instr[24:20]); register reads are asynchronous
--   F3 write-back on the edge when RegWrite = 1 and rd /= x0: Result_Src 00 ALU, 01 ReadData,
--      10 PC+4, 11 old CSR value
--   F4 next PC by PC_Src: 00 PC+4, 01 (JalrReg ? RD1 : PC) + ImmExt with bit 0 cleared,
--      10 mtvec, 11 mepc
--   F5 CSRs: number instr[31:20], write data RD1, ops/trap/mret as in csrblock_tb; mepc on a
--      trap = the PC of the trapped cycle; MIE/MEIE outputs
--   F6 synchronous reset: PC <- 0x1000, CSRs <- 0 (also in the middle of a run)
-- Register file has no reset in the spec: the test first writes all 31 registers, and
-- RegWrite is 0 during reset cycles (spec does not say what a write during reset does).
--
-- Checking: a cycle-level model of the datapath built from the block table (uses ref_alu /
-- ref_imm from riscv_ref_pkg; alu and ImmGen are verified on their own). REZ, Zero, WD, PC,
-- MIE, MEIE are compared every cycle; registers are observed black-box through WD and REZ.
-- E1 wrong PC prediction must be caught.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tb_pkg.all;
use work.riscv_ref_pkg.all;

entity datapath_tb is
    generic(
        G_SEED   : positive := 1;
        G_N_RAND : natural  := 20000;
        G_VERBOSE : boolean := false;   -- log every cycle's controls (debug)
        G_INJECT : boolean  := true
    );
end entity datapath_tb;

architecture sim of datapath_tb is
    subtype word_t is std_logic_vector(31 downto 0);
    constant C_PERIOD : time := 10 ns;
    constant C_TCO    : time := 1 ns;
    constant RESET_PC : word_t := x"00001000";

    type ctl_in_t is record
        rst         : std_logic;
        PC_Src      : std_logic_vector(1 downto 0);
        ImmSrc      : std_logic_vector(2 downto 0);
        instr       : word_t;
        AluSrcB     : std_logic;
        AluSrcA     : std_logic_vector(1 downto 0);
        alu_control : std_logic_vector(3 downto 0);
        RegWrite    : std_logic;
        ReadData    : word_t;
        Result_Src  : std_logic_vector(1 downto 0);
        JalrReg     : std_logic;
        TRAP        : std_logic;
        CSRwrite    : std_logic;
        CSRop       : std_logic_vector(1 downto 0);
        MRET        : std_logic;
        irq         : std_logic;
    end record;

    signal clk  : std_logic;
    signal run  : boolean := true;
    signal done : boolean := false;
    signal c    : ctl_in_t := ('1', "00", "000", (others => '0'), '0', "00", "0000", '0', (others => '0'),
                               "00", '0', '0', '0', "01", '0', '0');
    signal Zero, MIE, MEIE : std_logic;
    signal REZ, PC, WD     : word_t;

    shared variable rnd : tb_rand_t;
begin
    clock    : tb_clock(clk, C_PERIOD, run);
    watchdog : tb_watchdog(done, 10 ms);

    dut : entity work.DataPath
        port map(clk => clk, rst => c.rst, PC_Src => c.PC_Src, ImmSrc => c.ImmSrc, instr => c.instr,
                 AluSrcB => c.AluSrcB, AluSRCA => c.AluSrcA, alu_control => c.alu_control,
                 RegWrite => c.RegWrite, Zero => Zero, REZ => REZ, PC => PC, ReadData => c.ReadData,
                 Result_Src => c.Result_Src, WD => WD, JalrReg => c.JalrReg, TRAP => c.TRAP,
                 CSRwrite => c.CSRwrite, CSRop => c.CSRop, MIE => MIE, MEIE => MEIE, MRET => c.MRET,
                 irq => c.irq);

    stimulus : process
        type reg_array is array (0 to 31) of word_t;
        variable regs    : reg_array := (others => (others => '0'));
        variable known   : std_logic_vector(31 downto 0) := (0 => '1', others => '0');
        variable pc_m    : word_t := RESET_PC;
        variable pc_known : boolean := false;
        variable s_mie, s_mpie, s_meie : std_logic := '0';
        variable s_mtvec, s_mepc, s_mcause : word_t := (others => '0');
        type count4 is array (0 to 3) of natural;
        variable h_pcsrc, h_res, h_asrc : count4 := (others => 0);
        variable h_trap, h_mret, h_rst_mid, h_jalr : natural := 0;

        impure function csr_read(num : std_logic_vector(11 downto 0); irq_v : std_logic) return word_t is
            variable v : word_t := (others => '0');
        begin
            case num is
                when x"300" => v(3) := s_mie; v(7) := s_mpie;
                when x"304" => v(11) := s_meie;
                when x"305" => v := s_mtvec;
                when x"341" => v := s_mepc;
                when x"342" => v := s_mcause;
                when x"344" => v(11) := irq_v;
                when others => null;
            end case;
            return v;
        end function;

        -- one cycle: drive k after the falling edge, check, model the rising edge
        procedure cycle(k : ctl_in_t; corrupt : boolean := false) is
            variable rs1 : natural := to_integer(unsigned(k.instr(19 downto 15)));
            variable rs2 : natural := to_integer(unsigned(k.instr(24 downto 20)));
            variable rd  : natural := to_integer(unsigned(k.instr(11 downto 7)));
            variable num : std_logic_vector(11 downto 0) := k.instr(31 downto 20);
            variable imm, a, b, rez_m, wb, old, nv, base, nxt, exp_pc, rd1 : word_t;
            variable rez_ok : boolean;
        begin
            wait until falling_edge(clk);
            c <= k;
            wait for C_TCO;
            if G_VERBOSE then
                report "cyc instr=" & to_hstring(k.instr) & " rst=" & to_string(k.rst) & " PCsrc=" & to_string(k.PC_Src) &
                       " Imm=" & to_string(k.ImmSrc) & " A=" & to_string(k.AluSrcA) & " B=" & to_string(k.AluSrcB) &
                       " alu=" & to_string(k.alu_control) & " RW=" & to_string(k.RegWrite) & " RS=" & to_string(k.Result_Src) &
                       " J=" & to_string(k.JalrReg) & " T=" & to_string(k.TRAP) & " M=" & to_string(k.MRET) &
                       " CW=" & to_string(k.CSRwrite) & " op=" & to_string(k.CSRop) & " pc_m=" & to_hstring(pc_m) &
                       " PC=" & to_hstring(PC);
            end if;

            imm := ref_imm(k.instr, k.ImmSrc);
            case k.AluSrcA is
                when "00"   => a := regs(rs1); rez_ok := known(rs1) = '1';
                when "01"   => a := pc_m; rez_ok := pc_known;
                when others => a := (others => '0'); rez_ok := true;
            end case;
            if k.AluSrcB = '1' then
                b := imm;
            else
                b := regs(rs2);
                rez_ok := rez_ok and known(rs2) = '1';
            end if;
            rez_m := ref_alu(a, b, k.alu_control);
            old   := csr_read(num, k.irq);

            if pc_known then
                exp_pc := pc_m;
                if corrupt then exp_pc := exp_pc xor x"00000010"; end if;
                tb_check_equal(PC, exp_pc, "PC");
            end if;
            if rez_ok then
                tb_check_equal(REZ, rez_m, "REZ instr=" & to_str(k.instr) & " A/B/alu=" & to_str(k.AluSrcA) &
                                           "/" & to_str(k.AluSrcB) & "/" & to_str(k.alu_control));
                tb_check((Zero = '1') = (rez_m = x"00000000"), "Zero = " & to_str(Zero) & " for REZ " & to_str(rez_m));
            end if;
            if known(rs2) = '1' then
                tb_check_equal(WD, regs(rs2), "WD = x" & integer'image(rs2));
            end if;
            if pc_known then
                tb_check_equal(MIE, s_mie, "MIE output");
                tb_check_equal(MEIE, s_meie, "MEIE output");
            end if;

            -- values computed before the edge
            case k.Result_Src is
                when "00"   => wb := rez_m;
                when "01"   => wb := k.ReadData;
                when "10"   => wb := std_logic_vector(unsigned(pc_m) + 4);
                when others => wb := old;
            end case;
            rd1 := regs(rs1);                   -- read before the edge (rd may equal rs1)
            if k.JalrReg = '1' then base := rd1; else base := pc_m; end if;
            case k.PC_Src is
                when "00"   => nxt := std_logic_vector(unsigned(pc_m) + 4);
                when "01"   => nxt := std_logic_vector(unsigned(base) + unsigned(imm));
                               nxt(0) := '0';
                when "10"   => nxt := s_mtvec;
                when others => nxt := s_mepc;
            end case;

            wait until rising_edge(clk);
            if k.rst = '1' then
                if pc_known then h_rst_mid := h_rst_mid + 1; end if;
                pc_m := RESET_PC;
                pc_known := true;
                s_mie := '0'; s_mpie := '0'; s_meie := '0';
                s_mtvec := (others => '0'); s_mepc := (others => '0'); s_mcause := (others => '0');
            else
                if k.RegWrite = '1' and rd /= 0 then
                    regs(rd) := wb;
                    known(rd) := '1' when (k.Result_Src /= "00" or rez_ok) and pc_known else '0';
                end if;
                if k.TRAP = '1' then
                    s_mpie := s_mie; s_mie := '0'; s_mcause := x"8000000B"; s_mepc := pc_m;
                    h_trap := h_trap + 1;
                elsif k.MRET = '1' then
                    s_mie := s_mpie; s_mpie := '1';
                    h_mret := h_mret + 1;
                elsif k.CSRwrite = '1' then
                    case k.CSRop is
                        when "01"   => nv := rd1;
                        when "10"   => nv := old or rd1;
                        when others => nv := old and not rd1;
                    end case;
                    case num is
                        when x"300" => s_mie := nv(3); s_mpie := nv(7);
                        when x"304" => s_meie := nv(11);
                        when x"305" => s_mtvec := nv;
                        when x"341" => s_mepc := nv;
                        when x"342" => s_mcause := nv;
                        when others => null;
                    end case;
                end if;
                pc_m := nxt;
                h_pcsrc(to_integer(unsigned(k.PC_Src))) := h_pcsrc(to_integer(unsigned(k.PC_Src))) + 1;
                h_res(to_integer(unsigned(k.Result_Src))) := h_res(to_integer(unsigned(k.Result_Src))) + 1;
                h_asrc(to_integer(unsigned(k.AluSrcA))) := h_asrc(to_integer(unsigned(k.AluSrcA))) + 1;
                if k.PC_Src = "01" and k.JalrReg = '1' then h_jalr := h_jalr + 1; end if;
            end if;
        end procedure;

        impure function random_ctl return ctl_in_t is
            variable k : ctl_in_t;
        begin
            k.rst         := '0';
            k.instr       := rnd.slv(32);
            if rnd.bool(0.3) then   -- point the CSR number at an implemented CSR
                case rnd.int(0, 5) is
                    when 0 => k.instr(31 downto 20) := x"300";
                    when 1 => k.instr(31 downto 20) := x"304";
                    when 2 => k.instr(31 downto 20) := x"305";
                    when 3 => k.instr(31 downto 20) := x"341";
                    when 4 => k.instr(31 downto 20) := x"342";
                    when others => k.instr(31 downto 20) := x"344";
                end case;
            end if;
            k.PC_Src      := rnd.slv(2);
            k.ImmSrc      := std_logic_vector(to_unsigned(rnd.int(0, 4), 3));
            k.AluSrcB     := rnd.slv(1)(0);
            k.AluSrcA     := std_logic_vector(to_unsigned(rnd.int(0, 2), 2));
            k.alu_control := rnd.slv(4);
            k.RegWrite    := rnd.slv(1)(0);
            k.ReadData    := rnd.slv(32);
            k.Result_Src  := rnd.slv(2);
            k.JalrReg     := rnd.slv(1)(0);
            k.TRAP        := '1' when rnd.bool(0.05) else '0';
            k.MRET        := '1' when rnd.bool(0.05) else '0';
            k.CSRwrite    := '1' when rnd.bool(0.3) and k.MRET = '0' else '0';
            k.CSRop       := std_logic_vector(to_unsigned(rnd.int(1, 3), 2));
            k.irq         := rnd.slv(1)(0);
            return k;
        end function;

        variable k : ctl_in_t;
    begin
        rnd.seed(G_SEED);
        tb_info("datapath_tb seed=" & integer'image(G_SEED));

        tb_info("T1: reset with random controls (RegWrite = 0)");
        k := random_ctl;
        k.rst := '1';
        k.RegWrite := '0';
        cycle(k);
        cycle(k);

        tb_info("T2: write every register with lui-style controls (A = 0, B = U-imm)");
        for r in 1 to 31 loop
            k := random_ctl;
            k.instr(11 downto 7) := std_logic_vector(to_unsigned(r, 5));
            k.AluSrcA := "10"; k.AluSrcB := '1'; k.ImmSrc := "100"; k.alu_control := "0000";
            k.Result_Src := "00"; k.RegWrite := '1'; k.PC_Src := "00"; k.TRAP := '0'; k.MRET := '0';
            k.CSRwrite := '0';
            cycle(k);
        end loop;
        for r in 1 to 31 loop
            tb_check(known(r) = '1', "x" & integer'image(r) & " not initialised by T2");
        end loop;

        tb_info("T3: random control signals");
        tb_set_verbose(false);
        for n in 1 to G_N_RAND loop
            k := random_ctl;
            if rnd.bool(0.003) then
                k.rst := '1';
                k.RegWrite := '0';
            end if;
            cycle(k);
        end loop;
        tb_set_verbose(true);

        tb_info("coverage: trap=" & integer'image(h_trap) & " mret=" & integer'image(h_mret) &
                " reset mid-run=" & integer'image(h_rst_mid) & " jalr-target=" & integer'image(h_jalr));
        for i in 0 to 3 loop
            tb_check(h_pcsrc(i) > 0 and h_res(i) > 0, "coverage: PC_Src/Result_Src value " & integer'image(i));
        end loop;
        tb_check(h_asrc(0) > 0 and h_asrc(1) > 0 and h_asrc(2) > 0, "coverage: AluSRCA values");
        tb_check(h_trap > 0 and h_mret > 0 and h_rst_mid > 0 and h_jalr > 0, "coverage: trap/mret/reset/jalr");

        if G_INJECT then
            tb_expect_errors(1, "E1: wrong PC prediction must be caught");
            k := random_ctl;
            k.RegWrite := '0';
            cycle(k, corrupt => true);
            tb_end_expect;
        end if;

        done <= true;
        run  <= false;
        tb_finish;
        wait;
    end process stimulus;
end architecture sim;
