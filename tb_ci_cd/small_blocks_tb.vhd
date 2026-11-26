--------------------------------------------------------------------------------
-- small_blocks_tb : self-checking testbench for the small datapath blocks
--   pc, PCPlus4, PCTarget, ZeroGen, MuxJalr, Pc_mux, alu_mux, SrcAMux, result_mux
--
-- Spec: README "Datapath" table.
--   F1 pc: synchronous reset -> 0x0000_1000 (whatever PCNext is), else loads PCNext on every
--      rising edge; reset in the middle of activity works too
--   F2 PCPlus4 = PC + 4 mod 2^32;  PCTarget = base + offset mod 2^32 (offset may be negative)
--   F3 ZeroGen clears bit 0 and nothing else
--   F4 MuxJalr: JalrReg 0 -> PC, 1 -> RD1
--   F5 Pc_mux: 00 PC+4, 01 target, 10 mtvec, 11 mepc
--   F6 alu_mux: 0 rd2, 1 imm;  SrcAMux: 00 rs1, 01 PC, 10 zero  (11 unspecified: not checked)
--   F7 result_mux: 00 ALU, 01 load data, 10 PC+4, 11 CSR
-- Mux inputs always carry different random values, so a wrong selection is visible.
-- Adders are checked against a ripple-carry model (not numeric_std "+").
-- E1 wrong mux prediction, E2 wrong pc prediction must be caught.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tb_pkg.all;

entity small_blocks_tb is
    generic(
        G_SEED   : positive := 1;
        G_N_RAND : natural  := 2000;
        G_INJECT : boolean  := true
    );
end entity small_blocks_tb;

architecture sim of small_blocks_tb is
    subtype word_t is std_logic_vector(31 downto 0);
    constant C_PERIOD : time := 10 ns;
    constant C_TCO    : time := 1 ns;
    constant C_SETTLE : time := 1 ns;
    constant RESET_PC : word_t := x"00001000";

    signal clk  : std_logic;
    signal run  : boolean := true;
    signal done : boolean := false;

    -- pc
    signal rst     : std_logic := '1';
    signal pc_next : word_t := (others => '1');
    signal pc_reg  : word_t;
    -- combinational blocks: d0..d3 are the data inputs
    signal d0, d1, d2, d3 : word_t := (others => '0');
    signal sel1           : std_logic := '0';
    signal sel2           : std_logic_vector(1 downto 0) := "00";
    signal plus4, target, zeroed, jalr_base, pcmux, bmux, amux, rmux : word_t;

    shared variable rnd : tb_rand_t;

    function m_add(a, b : word_t) return word_t is
        variable s : word_t;
        variable c : std_logic := '0';
    begin
        for i in 0 to 31 loop
            s(i) := a(i) xor b(i) xor c;
            c    := (a(i) and b(i)) or (a(i) and c) or (b(i) and c);
        end loop;
        return s;
    end function;
begin
    clock    : tb_clock(clk, C_PERIOD, run);
    watchdog : tb_watchdog(done, 1 ms);

    u_pc : entity work.pc port map(clk => clk, rst => rst, PCNext => pc_next, PC_REG => pc_reg);
    u_p4 : entity work.PCPlus4 port map(PC => d0, PC_O => plus4);
    u_tg : entity work.PCTarget port map(PC => d0, offset => d1, PCOFFSET => target);
    u_zg : entity work.ZeroGen port map(INP => d0, OUTP => zeroed);
    u_mj : entity work.MuxJalr port map(PC_NOW => d0, RD1 => d1, JalrReg => sel1, PCtarget_IN => jalr_base);
    u_pm : entity work.Pc_mux
        port map(PCPlus4 => d0, PCL => d1, mtvec_handler_addr => d2, mepc_ret_addr => d3, S => sel2, PCOUT => pcmux);
    u_am : entity work.alu_mux port map(rd2 => d0, imm => d1, S => sel1, muxout => bmux);
    u_sa : entity work.SrcAMux port map(SrcA => d0, PC => d1, S => sel2, Y => amux);
    u_rm : entity work.result_mux
        port map(Result_Src => sel2, ALU_Res => d0, ReadData => d1, PC_4 => d2, CSR_RES => d3, Mux_Res => rmux);

    stimulus : process
        variable exp_pc : word_t;
        variable n_reset_mid, n_wrap : natural := 0;

        -- one clock: drive PCNext/rst after the edge, check pc_reg after the next edge
        procedure pc_cycle(nxt : word_t; reset : std_logic; corrupt : boolean := false) is
        begin
            wait until falling_edge(clk);          -- start mid-cycle: exactly one rising edge follows
            pc_next <= nxt after C_TCO;
            rst     <= reset after C_TCO;
            wait until rising_edge(clk);           -- edge where nxt/reset are sampled
            wait for C_TCO + C_SETTLE;
            if reset = '1' then exp_pc := RESET_PC; else exp_pc := nxt; end if;
            if corrupt then exp_pc := exp_pc xor x"00000004"; end if;
            tb_check_equal(pc_reg, exp_pc, "pc after edge (rst=" & to_str(reset) & ", PCNext=" & to_str(nxt) & ")");
        end procedure;

        -- distinct random data on d0..d3
        procedure new_data is
            variable v : word_t;
        begin
            d0 <= rnd.slv(32);
            d1 <= rnd.slv(32);
            d2 <= rnd.slv(32);
            d3 <= rnd.slv(32);
            wait for 0 ns;
            -- guarantee they differ (a collision would hide a wrong selection)
            if d1 = d0 then d1 <= not d0; end if;
            if d2 = d0 or d2 = d1 then d2 <= d0 xor x"0F0F0F0F"; end if;
            if d3 = d0 or d3 = d1 or d3 = d2 then d3 <= d0 xor x"F0F0F0F0"; end if;
            wait for 0 ns;
        end procedure;

        procedure check_comb(corrupt : boolean := false) is
            type word_array is array (0 to 3) of word_t;
            variable d   : word_array;
            variable exp : word_t;
        begin
            -- adders / ZeroGen do not depend on selects
            wait for C_SETTLE;                  -- also lets the caller's d0..d3 update
            d := (d0, d1, d2, d3);
            tb_check_equal(plus4, m_add(d0, x"00000004"), "PCPlus4 of " & to_str(d0));
            tb_check_equal(target, m_add(d0, d1), "PCTarget " & to_str(d0) & " + " & to_str(d1));
            tb_check_equal(zeroed, d0(31 downto 1) & '0', "ZeroGen of " & to_str(d0));
            if d0 = x"FFFFFFFC" or d0(31) /= plus4(31) then n_wrap := n_wrap + 1; end if;
            for s in 0 to 1 loop
                if s = 1 then sel1 <= '1'; else sel1 <= '0'; end if;
                wait for C_SETTLE;
                exp := d(s);
                if corrupt then exp := d(1 - s); end if;
                tb_check_equal(bmux, exp, "alu_mux S=" & integer'image(s));
                tb_check_equal(jalr_base, d(s), "MuxJalr JalrReg=" & integer'image(s));
            end loop;
            for s in 0 to 3 loop
                sel2 <= std_logic_vector(to_unsigned(s, 2));
                wait for C_SETTLE;
                tb_check_equal(pcmux, d(s), "Pc_mux S=" & integer'image(s));
                tb_check_equal(rmux, d(s), "result_mux S=" & integer'image(s));
                if s < 2 then
                    tb_check_equal(amux, d(s), "SrcAMux S=" & integer'image(s));
                elsif s = 2 then
                    tb_check_equal(amux, x"00000000", "SrcAMux S=10 (lui zero)");
                end if;
            end loop;
        end procedure;

        variable v : word_t;
    begin
        rnd.seed(G_SEED);
        tb_info("small_blocks_tb seed=" & integer'image(G_SEED));

        tb_info("T1: pc reset with all-ones on PCNext, then loads");
        wait until rising_edge(clk);
        pc_cycle(x"FFFFFFFF", '1');
        pc_cycle(x"12345678", '0');
        pc_cycle(x"00000000", '0');
        pc_cycle(x"FFFFFFFF", '0');
        tb_info("T2: pc random loads with reset in the middle");
        for k in 1 to 200 loop
            if rnd.bool(0.1) then
                pc_cycle(rnd.slv(32), '1');
                n_reset_mid := n_reset_mid + 1;
            else
                pc_cycle(rnd.slv(32), '0');
            end if;
        end loop;
        tb_check(n_reset_mid > 0, "coverage: reset during activity");

        tb_info("T3: adders, ZeroGen, muxes: directed corners");
        for k in 0 to 3 loop
            case k is
                when 0 => v := x"00000000";
                when 1 => v := x"FFFFFFFC";
                when 2 => v := x"7FFFFFFD";
                when others => v := x"000000FF";
            end case;
            d0 <= v; d1 <= not v; d2 <= v xor x"0F0F0F0F"; d3 <= v xor x"F0F0F0F0";
            check_comb;
        end loop;
        d0 <= x"00000020"; d1 <= x"FFFFFFF0"; d2 <= x"00000001"; d3 <= x"00000002";  -- negative offset
        check_comb;

        tb_info("T4: random data");
        tb_set_verbose(false);
        for k in 1 to G_N_RAND loop
            new_data;
            check_comb;
        end loop;
        tb_set_verbose(true);
        tb_check(n_wrap > 0, "coverage: PC+4 crossing a sign/wrap boundary");

        if G_INJECT then
            tb_expect_errors(1, "E1: wrong alu_mux prediction must be caught");
            d0 <= x"11111111"; d1 <= x"22222222"; d2 <= x"33333333"; d3 <= x"44444444";
            sel1 <= '0';
            wait for C_SETTLE;
            tb_check_equal(bmux, d1, "alu_mux injected");
            tb_end_expect;
            tb_expect_errors(1, "E2: wrong pc prediction must be caught");
            pc_cycle(x"80000000", '0', corrupt => true);
            tb_end_expect;
        end if;

        done <= true;
        run  <= false;
        tb_finish;
        wait;
    end process stimulus;
end architecture sim;
