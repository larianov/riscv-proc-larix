--------------------------------------------------------------------------------
-- riscvregfile_tb : self-checking testbench for riscvregfile
--
-- Spec: README "riscvregfile": 32 x 32-bit registers, 2 asynchronous reads, 1 write on the
-- rising clock edge, x0 always 0.
--   F1 a write with write_en = 1 is visible on both read ports after the rising edge
--   F2 before that edge the read ports still show the old value (write is synchronous)
--   F3 write_en = 0 writes nothing
--   F4 x0 reads 0 on both ports, also after writes to x0
--   F5 both ports read independent registers (including the same one)
--   F6 a write changes only the addressed register
-- The README gives no power-up value for x1..x31, so registers that were never written are not
-- checked (open question). write_In is 'X' while write_en = 0, so sampling it then shows up.
--
-- Checking: shadow model (array) updated on every write, every read compared with it.
-- E1 wrong model value must be caught.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tb_pkg.all;

entity riscvregfile_tb is
    generic(
        G_SEED   : positive := 1;
        G_N_RAND : natural  := 5000;
        G_INJECT : boolean  := true
    );
end entity riscvregfile_tb;

architecture sim of riscvregfile_tb is
    subtype word_t is std_logic_vector(31 downto 0);
    constant C_PERIOD : time := 10 ns;
    constant C_TCO    : time := 1 ns;

    signal clk      : std_logic;
    signal run      : boolean := true;
    signal done     : boolean := false;
    signal rd_idx1  : std_logic_vector(4 downto 0) := (others => '0');
    signal rd_idx2  : std_logic_vector(4 downto 0) := (others => '0');
    signal wr_idx   : std_logic_vector(4 downto 0) := (others => '0');
    signal rd_out1  : word_t;
    signal rd_out2  : word_t;
    signal write_en : std_logic := '0';
    signal write_in : word_t := (others => 'X');

    shared variable rnd : tb_rand_t;
begin
    clock    : tb_clock(clk, C_PERIOD, run);
    watchdog : tb_watchdog(done, 10 ms);

    dut : entity work.riscvregfile
        port map(
            clk             => clk,
            read_idx_first  => rd_idx1,
            read_idx_second => rd_idx2,
            write_idx       => wr_idx,
            read_out_first  => rd_out1,
            read_out_second => rd_out2,
            write_en        => write_en,
            write_In        => write_in
        );

    stimulus : process
        type reg_array is array (0 to 31) of word_t;
        type flag_array is array (0 to 31) of boolean;
        variable model   : reg_array := (others => (others => '0'));
        variable written : flag_array := (0 => true, others => false);   -- x0 is always known
        variable n_x0_wr, n_disabled, n_same_port, n_old_seen : natural := 0;

        -- read registers a/b on the two ports and compare with the model
        procedure read_check(a, b : natural; corrupt : boolean := false) is
            variable exp : word_t;
        begin
            rd_idx1 <= std_logic_vector(to_unsigned(a, 5));
            rd_idx2 <= std_logic_vector(to_unsigned(b, 5));
            wait for C_TCO;
            if written(a) then
                exp := model(a);
                if corrupt then exp := not exp; end if;
                tb_check_equal(rd_out1, exp, "port 1 reads x" & integer'image(a));
            end if;
            if written(b) and not corrupt then
                tb_check_equal(rd_out2, model(b), "port 2 reads x" & integer'image(b));
            end if;
            if a = b then n_same_port := n_same_port + 1; end if;
        end procedure;

        -- one write cycle; checks that the register keeps its old value until the edge
        procedure write_reg(idx : natural; d : word_t; en : std_logic) is
        begin
            wait until falling_edge(clk);          -- start mid-cycle: exactly one rising edge follows
            wr_idx   <= std_logic_vector(to_unsigned(idx, 5));
            write_in <= d;
            write_en <= en;
            if en = '0' then write_in <= (others => 'X'); end if;
            rd_idx1  <= std_logic_vector(to_unsigned(idx, 5));
            wait for C_TCO;
            if written(idx) then
                tb_check_equal(rd_out1, model(idx), "x" & integer'image(idx) & " must keep its value before the edge");
                n_old_seen := n_old_seen + 1;
            end if;
            wait until rising_edge(clk);
            if en = '1' and idx /= 0 then
                model(idx)   := d;
                written(idx) := true;
            end if;
            if idx = 0 and en = '1' then n_x0_wr := n_x0_wr + 1; end if;
            if en = '0' then n_disabled := n_disabled + 1; end if;
            write_en <= '0' after C_TCO;
            write_in <= (others => 'X') after C_TCO;
            wait for C_TCO;
        end procedure;

        variable v : word_t;
    begin
        rnd.seed(G_SEED);
        tb_info("riscvregfile_tb seed=" & integer'image(G_SEED));
        wait until rising_edge(clk);
        wait for C_TCO;

        tb_info("T1: x0 reads 0, writing x0 is ignored");
        read_check(0, 0);
        write_reg(0, x"FFFFFFFF", '1');
        read_check(0, 0);

        tb_info("T2: fill every register with a distinct signature, read all back");
        for r in 1 to 31 loop
            write_reg(r, std_logic_vector(to_unsigned(r, 8)) & x"A5A5" & std_logic_vector(to_unsigned(r, 8)), '1');
        end loop;
        for r in 0 to 31 loop
            read_check(r, 31 - r);
        end loop;

        tb_info("T3: write_en = 0 writes nothing");
        for r in 0 to 31 loop
            write_reg(r, x"DEADBEEF", '0');
        end loop;
        for r in 0 to 31 loop
            read_check(r, r);
        end loop;

        tb_info("T4: random writes / reads");
        tb_set_verbose(false);
        for k in 1 to G_N_RAND loop
            v := rnd.slv(32);
            if rnd.bool(0.1) then v := x"00000000"; elsif rnd.bool(0.1) then v := x"FFFFFFFF"; end if;
            if rnd.bool(0.75) then
                write_reg(rnd.int_skewed(0, 31), v, '1');
            else
                write_reg(rnd.int(0, 31), v, '0');
            end if;
            read_check(rnd.int_skewed(0, 31), rnd.int_skewed(0, 31));
        end loop;
        tb_set_verbose(true);

        tb_info("coverage: x0 writes=" & integer'image(n_x0_wr) & " disabled=" & integer'image(n_disabled) &
                " same reg on both ports=" & integer'image(n_same_port) &
                " old value before edge=" & integer'image(n_old_seen));
        tb_check(n_x0_wr > 0 and n_disabled > 0 and n_same_port > 0 and n_old_seen > 0, "coverage");

        if G_INJECT then
            tb_expect_errors(1, "E1: wrong register model must be caught");
            read_check(5, 5, corrupt => true);
            tb_end_expect;
        end if;

        done <= true;
        run  <= false;
        tb_finish;
        wait;
    end process stimulus;
end architecture sim;
