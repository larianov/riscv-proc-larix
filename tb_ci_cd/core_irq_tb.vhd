--------------------------------------------------------------------------------
-- core_irq_tb : interrupt testbench for core (black-box: PC, WE, rez, WD, Illegal)
--
-- Spec: README "CSRs and interrupts".
--   F1 trap when irq = 1 and mstatus.MIE = 1 and mie.MEIE = 1 (level-sensitive)
--   F2 on a trap the current instruction is cancelled (no register write, no store),
--      mepc <- its PC, mcause <- 0x8000_000B, MPIE <- MIE, MIE <- 0, PC <- mtvec
--   F3 the trap wins over jumps (jal in the loop)
--   F4 while MIE = 0 (setup, handler) irq is ignored: no re-entry while irq is held
--   F5 mret: PC <- mepc, MIE <- MPIE, MPIE <- 1; if irq is still 1 the handler is entered again
--      right after mret (the README: the source must drop irq before mret)
--
-- Program (ROM at 0x1000, fed by the testbench):
--   setup   mtvec = 0x1100, mie.MEIE = 1, mstatus.MIE = 1
--   loop    0x101C addi x4,x4,1 ; 0x1020 sw x4,0x200(x0) ; 0x1024 jal x0,-8
--   handler 0x1100 addi x5,x5,1 ; read mcause, mepc, mstatus ; store x5/mcause/mepc/mstatus
--           to 0x300/0x304/0x308/0x30C ; mret
-- Everything the handler reads is visible on the store port, so no internal signal is used.
-- irq is random every cycle (setup, loop, handler, the mret cycle). A small model of this
-- program, written from the spec rules above, predicts PC, stores and traps every cycle.
-- Coverage: trap at each loop instruction, irq held in the handler, re-entry after mret,
-- irq ignored during setup.
-- E1 wrong PC prediction must be caught.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tb_pkg.all;

entity core_irq_tb is
    generic(
        G_SEED     : positive := 1;
        G_N_CYCLES : natural  := 4000;
        G_INJECT   : boolean  := true
    );
end entity core_irq_tb;

architecture sim of core_irq_tb is
    subtype word_t is std_logic_vector(31 downto 0);
    constant C_PERIOD : time := 10 ns;
    constant C_TCO    : time := 1 ns;

    type rom_t is array (natural range <>) of word_t;
    constant MAIN : rom_t(0 to 9) := (
        x"000010B7",   -- 0x1000 lui   x1, 0x1
        x"10008093",   -- 0x1004 addi  x1, x1, 0x100      x1 = 0x1100
        x"30509073",   -- 0x1008 csrrw x0, mtvec, x1
        x"80000113",   -- 0x100C addi  x2, x0, -2048      x2 = 0xFFFFF800 (bit 11)
        x"30412073",   -- 0x1010 csrrs x0, mie, x2        MEIE = 1
        x"00800193",   -- 0x1014 addi  x3, x0, 8
        x"3001A073",   -- 0x1018 csrrs x0, mstatus, x3    MIE = 1
        x"00120213",   -- 0x101C addi  x4, x4, 1
        x"20402023",   -- 0x1020 sw    x4, 0x200(x0)
        x"FF9FF06F");  -- 0x1024 jal   x0, -8
    constant HANDLER : rom_t(0 to 9) := (
        x"00128293",   -- 0x1100 addi  x5, x5, 1
        x"34202373",   -- 0x1104 csrrs x6, mcause, x0
        x"341023F3",   -- 0x1108 csrrs x7, mepc, x0
        x"30002473",   -- 0x110C csrrs x8, mstatus, x0
        x"30502023",   -- 0x1110 sw    x5, 0x300(x0)
        x"30602223",   -- 0x1114 sw    x6, 0x304(x0)
        x"30702423",   -- 0x1118 sw    x7, 0x308(x0)
        x"30802623",   -- 0x111C sw    x8, 0x30C(x0)
        x"30200073",   -- 0x1120 mret
        x"00000013");  -- 0x1124 (never reached)

    signal clk     : std_logic;
    signal run     : boolean := true;
    signal done    : boolean := false;
    signal rst     : std_logic := '1';
    signal irq     : std_logic := '0';
    signal instr   : word_t;
    signal PC      : word_t;
    signal Illegal : std_logic;
    signal rez, WD : word_t;
    signal WE      : std_logic_vector(3 downto 0);

    shared variable rnd : tb_rand_t;
begin
    clock    : tb_clock(clk, C_PERIOD, run);
    watchdog : tb_watchdog(done, 1 ms);

    fetch : process(PC)
        variable a : natural;
    begin
        instr <= x"00000013";
        if PC(31 downto 16) = x"0000" then
            a := to_integer(unsigned(PC(15 downto 0)));
            if a >= 16#1000# and a < 16#1000# + 4 * MAIN'length then
                instr <= MAIN((a - 16#1000#) / 4);
            elsif a >= 16#1100# and a < 16#1100# + 4 * HANDLER'length then
                instr <= HANDLER((a - 16#1100#) / 4);
            end if;
        end if;
    end process fetch;

    dut : entity work.core
        port map(rst => rst, clk => clk, irq => irq, instr => instr, PC => PC, Illegal => Illegal,
                 rez => rez, OUT_OF_MEMORY_DATA => x"00000000", WD => WD, WE => WE);

    stimulus : process
        -- architectural state of the model
        variable pc_m : natural := 16#1000#;
        variable x4, x5, x6, x7, x8 : unsigned(31 downto 0) := (others => '0');
        variable mie_b, mpie_b, meie_b : std_logic := '0';
        variable mepc : natural := 0;
        -- coverage
        type trap_hits_t is array (16#101C# / 4 to 16#1024# / 4) of natural;
        variable trap_at : trap_hits_t := (others => 0);
        variable n_trap, n_ignored_setup, n_held_in_handler, n_reentry, n_cycles : natural := 0;
        variable after_mret : boolean := false;

        function w(v : natural) return word_t is
        begin
            return std_logic_vector(to_unsigned(v, 32));
        end function;

        function st(v : std_logic) return natural is
        begin
            if v = '1' then return 1; else return 0; end if;
        end function;

        procedure expect_store(addr : natural; data : unsigned(31 downto 0)) is
        begin
            tb_check_equal(WE, "1111", "store at PC " & to_str(w(pc_m)));
            tb_check_equal(rez, w(addr), "store address at PC " & to_str(w(pc_m)));
            tb_check_equal(WD, std_logic_vector(data), "store data at PC " & to_str(w(pc_m)));
        end procedure;

        -- one cycle with irq level i
        procedure cycle(i : std_logic; corrupt : boolean := false) is
            variable trap : boolean;
            variable next_pc : natural := pc_m + 4;
            variable exp_pc  : word_t := w(pc_m);
        begin
            irq <= i;                          -- called right after a falling edge
            wait for C_TCO;
            if corrupt then exp_pc := w(pc_m + 8); end if;
            tb_check_equal(PC, exp_pc, "PC");
            tb_check_equal(Illegal, '0', "Illegal at " & to_str(PC));
            trap := i = '1' and mie_b = '1' and meie_b = '1';

            if trap then
                tb_check_equal(WE, "0000", "the interrupted instruction must not store");
                mepc := pc_m;
                mpie_b := mie_b;
                mie_b := '0';
                next_pc := 16#1100#;
                n_trap := n_trap + 1;
                if pc_m >= 16#101C# and pc_m <= 16#1024# then
                    trap_at(pc_m / 4) := trap_at(pc_m / 4) + 1;
                end if;
                if after_mret then n_reentry := n_reentry + 1; end if;
            else
                if i = '1' and pc_m < 16#101C# then n_ignored_setup := n_ignored_setup + 1; end if;
                if i = '1' and pc_m >= 16#1100# then n_held_in_handler := n_held_in_handler + 1; end if;
                if pc_m = 16#1020# or (pc_m >= 16#1110# and pc_m <= 16#111C#) then
                    case pc_m is
                        when 16#1020# => expect_store(16#200#, x4);
                        when 16#1110# => expect_store(16#300#, x5);
                        when 16#1114# => expect_store(16#304#, x6);
                        when 16#1118# => expect_store(16#308#, x7);
                        when others   => expect_store(16#30C#, x8);
                    end case;
                else
                    tb_check_equal(WE, "0000", "no store at PC " & to_str(w(pc_m)));
                end if;
                case pc_m is
                    when 16#1010# => meie_b := '1';
                    when 16#1018# => mie_b := '1';
                    when 16#101C# => x4 := x4 + 1;
                    when 16#1024# => next_pc := 16#101C#;
                    when 16#1100# => x5 := x5 + 1;
                    when 16#1104# => x6 := x"8000000B";
                    when 16#1108# => x7 := unsigned(w(mepc));
                    when 16#110C# => x8 := (others => '0'); x8(3) := mie_b; x8(7) := mpie_b;
                    when 16#1120# => next_pc := mepc; mie_b := mpie_b; mpie_b := '1';
                    when others   => null;
                end case;
            end if;
            after_mret := (not trap) and pc_m = 16#1120#;
            pc_m := next_pc;
            n_cycles := n_cycles + 1;
            wait until falling_edge(clk);      -- the rising edge in between executes it
        end procedure;

        variable level : std_logic := '0';
    begin
        rnd.seed(G_SEED);
        tb_info("core_irq_tb seed=" & integer'image(G_SEED));
        wait until falling_edge(clk);
        wait until falling_edge(clk);
        tb_check_equal(PC, x"00001000", "reset vector");
        rst <= '0';

        tb_info("T1: irq held during setup (MIE/MEIE still 0)");
        for k in 1 to 7 loop
            cycle('1');
        end loop;
        tb_check_equal(n_trap, 0, "no trap during setup");

        tb_info("T2: random irq level (bursts) in loop, handler and on mret");
        tb_set_verbose(false);
        for k in 1 to G_N_CYCLES loop
            if rnd.bool(0.15) then level := not level; end if;
            cycle(level);
            exit when tb_error_count > 20;
        end loop;
        tb_set_verbose(true);

        tb_info(integer'image(n_trap) & " traps (at addi/sw/jal " & integer'image(trap_at(16#101C# / 4)) & "/" &
                integer'image(trap_at(16#1020# / 4)) & "/" & integer'image(trap_at(16#1024# / 4)) &
                "), irq ignored in setup " & integer'image(n_ignored_setup) & ", held in handler " &
                integer'image(n_held_in_handler) & ", re-entry right after mret " & integer'image(n_reentry));
        for a in trap_at'range loop
            tb_check(trap_at(a) > 0, "coverage: no trap at PC " & to_str(w(4 * a)));
        end loop;
        tb_check(n_ignored_setup > 0 and n_held_in_handler > 0 and n_reentry > 0, "coverage: irq corner cases");

        if G_INJECT then
            tb_expect_errors(1, "E1: wrong PC prediction must be caught");
            cycle('0', corrupt => true);
            tb_end_expect;
        end if;

        done <= true;
        run  <= false;
        tb_finish;
        wait;
    end process stimulus;
end architecture sim;
