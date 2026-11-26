--------------------------------------------------------------------------------
-- unifiedmem_tb : self-checking testbench for unifiedmem (RAM, code + data)
--
-- Spec: README "unifiedmem" + "Boot and memory map".
--   F1 initial contents = the hex file (one word per line), rest 0
--   F2 instr_out (by PC) and RD (by address) are asynchronous reads of the same array
--   F3 word index = (byte address / 4) mod size: the 0x8000_0000 base and byte offset don't matter
--   F4 write on the rising edge: each WE(i) = 1 replaces byte lane i with wD lane i, other lanes keep
--   F5 WE = 0000 writes nothing; before the edge, reads still show the old value
--   F6 a data write is visible on the instruction port (one array, self-modifying code)
--
-- Checking: shadow array loaded by the testbench from the same file, updated lane by lane.
-- wD is 'X' while WE = 0000, so sampling it at the wrong time is visible.
-- Stimulus: every WE combination at fixed and random words, random reads on both ports.
-- E1 wrong prediction must be caught.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.tb_pkg.all;

entity unifiedmem_tb is
    generic(
        G_SEED   : positive := 1;
        G_FILE   : string   := "program.hex";
        G_N_RAND : natural  := 3000;
        G_INJECT : boolean  := true
    );
end entity unifiedmem_tb;

architecture sim of unifiedmem_tb is
    subtype word_t is std_logic_vector(31 downto 0);
    constant C_SIZE   : positive := 32;
    constant C_PERIOD : time := 10 ns;
    constant C_TCO    : time := 1 ns;
    constant RAM_BASE : unsigned(31 downto 0) := x"80000000";
    type mem_t is array (0 to C_SIZE - 1) of word_t;

    impure function load_hex(name : string) return mem_t is
        file f     : text open read_mode is name;
        variable l : line;
        variable m : mem_t := (others => (others => '0'));
        variable n : natural := 0;
    begin
        while not endfile(f) and n < C_SIZE loop
            readline(f, l);
            if l'length > 0 then
                hread(l, m(n));
                n := n + 1;
            end if;
        end loop;
        return m;
    end function;

    signal clk   : std_logic;
    signal run   : boolean := true;
    signal done  : boolean := false;
    signal PC    : word_t := std_logic_vector(RAM_BASE);
    signal instr : word_t;
    signal addr  : word_t := std_logic_vector(RAM_BASE);
    signal wD    : word_t := (others => 'X');
    signal WE    : std_logic_vector(3 downto 0) := "0000";
    signal RD    : word_t;

    shared variable rnd : tb_rand_t;
begin
    clock    : tb_clock(clk, C_PERIOD, run);
    watchdog : tb_watchdog(done, 10 ms);

    dut : entity work.unifiedmem
        generic map(file_S => G_FILE, size => C_SIZE)
        port map(PC => PC, instr_out => instr, clk => clk, address => addr, wD => wD, WE => WE, RD => RD);

    stimulus : process
        variable model : mem_t := load_hex(G_FILE);
        variable n_we  : natural := 0;
        variable we_seen : std_logic_vector(15 downto 0) := (others => '0');

        function idx(a : word_t) return natural is
        begin
            return to_integer(unsigned(a(31 downto 2))) mod C_SIZE;
        end function;

        function ram(off : natural) return word_t is
        begin
            return std_logic_vector(RAM_BASE + to_unsigned(off, 32));
        end function;

        procedure read_check(p, a : word_t; corrupt : boolean := false) is
            variable exp : word_t := model(idx(a));
        begin
            PC   <= p;
            addr <= a;
            wait for C_TCO;
            if corrupt then exp := not exp; end if;
            tb_check_equal(RD, exp, "data port at " & to_str(a));
            tb_check_equal(instr, model(idx(p)), "instr port at " & to_str(p));
        end procedure;

        procedure write_mem(a : word_t; d : word_t; en : std_logic_vector(3 downto 0)) is
        begin
            wait until falling_edge(clk);          -- start mid-cycle: exactly one rising edge follows
            addr <= a;
            wD   <= d;
            WE   <= en;
            wait for C_TCO;
            tb_check_equal(RD, model(idx(a)), "old value must stay until the edge at " & to_str(a));
            wait until rising_edge(clk);
            for i in 0 to 3 loop
                if en(i) = '1' then
                    model(idx(a))(8 * i + 7 downto 8 * i) := d(8 * i + 7 downto 8 * i);
                end if;
            end loop;
            we_seen(to_integer(unsigned(en))) := '1';
            n_we := n_we + 1;
            WE <= "0000" after C_TCO;
            wD <= (others => 'X') after C_TCO;
            wait for C_TCO;
            read_check(a, a);                      -- visible on both ports right after the edge
        end procedure;

        variable a : word_t;
    begin
        rnd.seed(G_SEED);
        tb_info("unifiedmem_tb seed=" & integer'image(G_SEED) & " file=" & G_FILE);
        wait until rising_edge(clk);
        wait for C_TCO;

        tb_info("T1: preloaded contents on both ports, wraparound, base ignored");
        tb_check_equal(model(0), x"00500093", "program.hex word 0");
        for i in 0 to C_SIZE - 1 loop
            read_check(ram(4 * i), ram(4 * (C_SIZE - 1 - i)));
        end loop;
        read_check(ram(4 * C_SIZE), x"00000000");          -- wraps to word 0; address without base
        read_check(x"00000004", ram(4 * C_SIZE + 5));      -- byte offset ignored

        tb_info("T2: every WE combination on one word");
        for e in 0 to 15 loop
            write_mem(ram(80), rnd.slv(32), std_logic_vector(to_unsigned(e, 4)));
        end loop;
        read_check(ram(84), ram(76));                       -- neighbours untouched

        tb_info("T3: self-modifying code: data write seen by the instruction port");
        write_mem(ram(8), x"DEADBEEF", "1111");
        read_check(ram(8), ram(0));

        tb_info("T4: random writes / reads");
        tb_set_verbose(false);
        for k in 1 to G_N_RAND loop
            a := rnd.slv(32);
            if rnd.bool(0.4) then
                write_mem(a, rnd.slv(32), rnd.slv(4));
            else
                read_check(rnd.slv(32), a);
            end if;
        end loop;
        tb_set_verbose(true);
        tb_check(we_seen = x"FFFF", "coverage: every WE combination, seen " & to_str(we_seen));

        if G_INJECT then
            tb_expect_errors(1, "E1: wrong memory prediction must be caught");
            read_check(ram(0), ram(4), corrupt => true);
            tb_end_expect;
        end if;

        done <= true;
        run  <= false;
        tb_finish;
        wait;
    end process stimulus;
end architecture sim;
