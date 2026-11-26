--------------------------------------------------------------------------------
-- csrblock_tb : self-checking testbench for CSRblock
--
-- Spec: README "CSRs and interrupts".
--   F1 reset (synchronous): every CSR 0
--   F2 CSR_RES = current (old) value of CSR CSRnum, combinational:
--        mstatus 0x300 bit 3 MIE, bit 7 MPIE | mie 0x304 bit 11 MEIE | mtvec 0x305, mepc 0x341,
--        mcause 0x342 all 32 bits | mip 0x344 bit 11 = irq input | any other number reads 0
--   F3 CSRwrite on the edge: op 01 write, 10 set (old or w), 11 clear (old and not w); only the
--      implemented bits change; mip and unknown CSRs ignore writes
--   F4 TRAP on the edge: mepc <- mepc_ret_addr_in, mcause <- 0x8000_000B, MPIE <- MIE, MIE <- 0;
--      the trapped instruction is cancelled, so a CSR write in the same cycle is dropped
--   F5 MRET on the edge: MIE <- MPIE, MPIE <- 1; TRAP wins over MRET
--   F6 outputs MIE, MEIE, mtvec_handler_addr, mepc_ret_addr_out always show the CSR state
-- Not generated: CSROp 00 with CSRwrite = 1 and MRET together with CSRwrite (ControlUnit
-- never produces them; the README does not define them).
--
-- Checking: shadow CSR model updated per cycle; CSR_RES checked before every edge, the
-- outputs after every edge.
-- Stimulus: directed sequences, then G_N_RAND random cycles (CSR numbers skewed to the
-- implemented ones and their neighbours, rare trap/mret/reset).
-- E1 wrong CSR prediction must be caught.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tb_pkg.all;

entity csrblock_tb is
    generic(
        G_SEED   : positive := 1;
        G_N_RAND : natural  := 20000;
        G_INJECT : boolean  := true
    );
end entity csrblock_tb;

architecture sim of csrblock_tb is
    subtype word_t is std_logic_vector(31 downto 0);
    subtype csr_t is std_logic_vector(11 downto 0);
    constant C_PERIOD : time := 10 ns;
    constant C_TCO    : time := 1 ns;

    constant MSTATUS : csr_t := x"300";
    constant MIE_CSR : csr_t := x"304";
    constant MTVEC   : csr_t := x"305";
    constant MEPC    : csr_t := x"341";
    constant MCAUSE  : csr_t := x"342";
    constant MIP     : csr_t := x"344";
    constant OP_W    : std_logic_vector(1 downto 0) := "01";
    constant OP_S    : std_logic_vector(1 downto 0) := "10";
    constant OP_C    : std_logic_vector(1 downto 0) := "11";

    signal clk      : std_logic;
    signal run      : boolean := true;
    signal done     : boolean := false;
    signal rst      : std_logic := '1';
    signal w_DATA   : word_t := (others => '0');
    signal mepc_in  : word_t := (others => '0');
    signal mtvec_o, mepc_o, res : word_t;
    signal TRAP, CSRwrite, MRET, irq : std_logic := '0';
    signal CSROp    : std_logic_vector(1 downto 0) := OP_W;
    signal CSRnum   : csr_t := (others => '0');
    signal MIE, MEIE : std_logic;

    shared variable rnd : tb_rand_t;
begin
    clock    : tb_clock(clk, C_PERIOD, run);
    watchdog : tb_watchdog(done, 10 ms);

    dut : entity work.CSRblock
        port map(clk => clk, rst => rst, w_DATA => w_DATA, mtvec_handler_addr => mtvec_o,
                 mepc_ret_addr_in => mepc_in, mepc_ret_addr_out => mepc_o, TRAP => TRAP,
                 CSRwrite => CSRwrite, CSROp => CSROp, CSRnum => CSRnum, irq => irq,
                 MIE => MIE, MEIE => MEIE, MRET => MRET, CSR_RES => res);

    stimulus : process
        -- shadow state
        variable s_mie, s_mpie, s_meie : std_logic := '0';
        variable s_mtvec, s_mepc, s_mcause : word_t := (others => '0');
        variable known : boolean := false;            -- false until the first reset
        type hit_t is record
            write, set, clr, trap, mret, trap_over_mret, trap_over_write, rst_mid, unknown_wr : natural;
        end record;
        variable hits : hit_t := (others => 0);

        impure function model_read(num : csr_t; irq_v : std_logic) return word_t is
            variable v : word_t := (others => '0');
        begin
            case num is
                when MSTATUS => v(3) := s_mie; v(7) := s_mpie;
                when MIE_CSR => v(11) := s_meie;
                when MTVEC   => v := s_mtvec;
                when MEPC    => v := s_mepc;
                when MCAUSE  => v := s_mcause;
                when MIP     => v(11) := irq_v;
                when others  => null;
            end case;
            return v;
        end function;

        procedure check_outputs(msg : string) is
        begin
            tb_check_equal(MIE, s_mie, msg & ": MIE output");
            tb_check_equal(MEIE, s_meie, msg & ": MEIE output");
            tb_check_equal(mtvec_o, s_mtvec, msg & ": mtvec output");
            tb_check_equal(mepc_o, s_mepc, msg & ": mepc output");
        end procedure;

        -- one clock cycle with the given inputs
        procedure cycle(num : csr_t; wr : std_logic; op : std_logic_vector(1 downto 0); d : word_t;
                        trap_i, mret_i, irq_i, rst_i : std_logic; pc : word_t;
                        corrupt : boolean := false) is
            variable old : word_t;
            variable nv  : word_t;
        begin
            wait until falling_edge(clk);
            CSRnum <= num; CSRwrite <= wr; CSROp <= op; w_DATA <= d;
            TRAP <= trap_i; MRET <= mret_i; irq <= irq_i; rst <= rst_i; mepc_in <= pc;
            wait for C_TCO;
            if known then
                old := model_read(num, irq_i);
                if corrupt then old := not old; end if;
                tb_check_equal(res, old, "CSR_RES of " & to_str(num));
            end if;
            wait until rising_edge(clk);
            -- model update, in the README's priority order
            if rst_i = '1' then
                if known then hits.rst_mid := hits.rst_mid + 1; end if;
                s_mie := '0'; s_mpie := '0'; s_meie := '0';
                s_mtvec := (others => '0'); s_mepc := (others => '0'); s_mcause := (others => '0');
                known := true;
            elsif trap_i = '1' then
                s_mpie := s_mie; s_mie := '0'; s_mcause := x"8000000B"; s_mepc := pc;
                hits.trap := hits.trap + 1;
                if mret_i = '1' then hits.trap_over_mret := hits.trap_over_mret + 1; end if;
                if wr = '1' then hits.trap_over_write := hits.trap_over_write + 1; end if;
            elsif mret_i = '1' then
                s_mie := s_mpie; s_mpie := '1';
                hits.mret := hits.mret + 1;
            elsif wr = '1' then
                old := model_read(num, irq_i);
                case op is
                    when OP_W => nv := d; hits.write := hits.write + 1;
                    when OP_S => nv := old or d; hits.set := hits.set + 1;
                    when others => nv := old and not d; hits.clr := hits.clr + 1;
                end case;
                case num is
                    when MSTATUS => s_mie := nv(3); s_mpie := nv(7);
                    when MIE_CSR => s_meie := nv(11);
                    when MTVEC   => s_mtvec := nv;
                    when MEPC    => s_mepc := nv;
                    when MCAUSE  => s_mcause := nv;
                    when others  => hits.unknown_wr := hits.unknown_wr + 1;   -- mip / unknown: ignored
                end case;
            end if;
            wait for C_TCO;
            if known then
                check_outputs("after edge");
                CSRwrite <= '0'; TRAP <= '0'; MRET <= '0'; rst <= '0';
                CSRnum <= num;
                wait for C_TCO;
                tb_check_equal(res, model_read(num, irq_i), "CSR_RES of " & to_str(num) & " after edge");
            end if;
        end procedure;

        -- short forms
        procedure csr(num : csr_t; op : std_logic_vector(1 downto 0); d : word_t) is
        begin
            cycle(num, '1', op, d, '0', '0', '0', '0', x"00000000");
        end procedure;
        procedure rd(num : csr_t; irq_i : std_logic := '0') is
        begin
            cycle(num, '0', OP_W, x"FFFFFFFF", '0', '0', irq_i, '0', x"00000000");
        end procedure;
        procedure trap_at(pc : word_t) is
        begin
            cycle(MSTATUS, '0', OP_W, x"00000000", '1', '0', '1', '0', pc);
        end procedure;
        procedure do_mret is
        begin
            cycle(MSTATUS, '0', OP_W, x"00000000", '0', '1', '0', '0', x"00000000");
        end procedure;

        type csr_array is array (natural range <>) of csr_t;
        constant CSRS : csr_array := (MSTATUS, MIE_CSR, MTVEC, MEPC, MCAUSE, MIP,
                                      x"340", x"343", x"301", x"000", x"FFF", x"B00");
        variable num  : csr_t;
        variable op   : std_logic_vector(1 downto 0);
        variable d    : word_t;
    begin
        rnd.seed(G_SEED);
        tb_info("csrblock_tb seed=" & integer'image(G_SEED));

        tb_info("T1: reset with every input active");
        cycle(MTVEC, '1', OP_W, x"FFFFFFFF", '1', '1', '1', '1', x"FFFFFFFF");
        for i in CSRS'range loop
            rd(CSRS(i));
        end loop;

        tb_info("T2: write / set / clear on every CSR (all-ones and patterns)");
        for i in CSRS'range loop
            csr(CSRS(i), OP_W, x"FFFFFFFF");
            csr(CSRS(i), OP_C, x"AAAAAAAA");
            csr(CSRS(i), OP_S, x"00000880");
            csr(CSRS(i), OP_C, x"FFFFFFFF");
            csr(CSRS(i), OP_S, x"12345678");
        end loop;

        tb_info("T3: mip follows irq and is read only");
        rd(MIP, '1');
        rd(MIP, '0');
        cycle(MIP, '1', OP_W, x"FFFFFFFF", '0', '0', '1', '0', x"00000000");

        tb_info("T4: trap and mret");
        csr(MTVEC, OP_W, x"00001100");
        csr(MIE_CSR, OP_W, x"00000800");
        csr(MSTATUS, OP_W, x"00000008");          -- MIE = 1, MPIE = 0
        trap_at(x"8000001C");                     -- MPIE <- 1, MIE <- 0
        rd(MEPC); rd(MCAUSE); rd(MSTATUS);
        do_mret;                                  -- MIE <- 1, MPIE <- 1
        csr(MSTATUS, OP_W, x"00000000");
        trap_at(x"80000040");                     -- MPIE <- 0
        do_mret;                                  -- MIE stays 0
        tb_info("T5: trap wins over mret and over a CSR write in the same cycle");
        csr(MSTATUS, OP_W, x"00000008");
        cycle(MEPC, '1', OP_W, x"11111111", '1', '1', '1', '0', x"80000080");
        cycle(MCAUSE, '1', OP_W, x"22222222", '1', '0', '1', '0', x"80000084");

        tb_info("T6: random cycles");
        tb_set_verbose(false);
        for k in 1 to G_N_RAND loop
            num := CSRS(rnd.int_skewed(0, CSRS'length - 1));
            if rnd.bool(0.1) then num := rnd.slv(12); end if;
            case rnd.int(0, 2) is
                when 0 => op := OP_W;
                when 1 => op := OP_S;
                when others => op := OP_C;
            end case;
            d := rnd.slv(32);
            if rnd.bool(0.2) then d := x"00000888"; end if;     -- the implemented status bits
            if rnd.bool(0.05) then
                cycle(num, rnd.slv(1)(0), op, d, '1', rnd.slv(1)(0), rnd.slv(1)(0), '0', rnd.slv(32));
            elsif rnd.bool(0.05) then
                cycle(num, '0', op, d, '0', '1', rnd.slv(1)(0), '0', rnd.slv(32));
            elsif rnd.bool(0.005) then
                cycle(num, rnd.slv(1)(0), op, d, rnd.slv(1)(0), rnd.slv(1)(0), rnd.slv(1)(0), '1', rnd.slv(32));
            else
                cycle(num, rnd.slv(1)(0), op, d, '0', '0', rnd.slv(1)(0), '0', rnd.slv(32));
            end if;
        end loop;
        tb_set_verbose(true);

        tb_info("coverage: write/set/clear=" & integer'image(hits.write) & "/" & integer'image(hits.set) & "/" &
                integer'image(hits.clr) & " trap=" & integer'image(hits.trap) & " mret=" & integer'image(hits.mret) &
                " trap>mret=" & integer'image(hits.trap_over_mret) & " trap>write=" &
                integer'image(hits.trap_over_write) & " reset mid-run=" & integer'image(hits.rst_mid) &
                " ignored writes=" & integer'image(hits.unknown_wr));
        tb_check(hits.write > 0 and hits.set > 0 and hits.clr > 0 and hits.trap > 0 and hits.mret > 0 and
                 hits.trap_over_mret > 0 and hits.trap_over_write > 0 and hits.rst_mid > 0 and
                 hits.unknown_wr > 0, "coverage: a required case was never hit");

        if G_INJECT then
            tb_expect_errors(1, "E1: wrong CSR prediction must be caught");
            cycle(MTVEC, '0', OP_W, x"00000000", '0', '0', '0', '0', x"00000000", corrupt => true);
            tb_end_expect;
        end if;

        done <= true;
        run  <= false;
        tb_finish;
        wait;
    end process stimulus;
end architecture sim;
