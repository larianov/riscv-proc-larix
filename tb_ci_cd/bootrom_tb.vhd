--------------------------------------------------------------------------------
-- bootrom_tb : self-checking testbench for bootrom (64-word ROM, combinational reads)
--
-- Spec: README "bootrom" + "Boot and memory map".
--   F1 contents = boot.hex, one word per line, rest 0; word 0 = 800002B7 (lui x5,0x80000),
--      word 1 = 00028067 (jalr x0,0(x5))
--   F2 two independent asynchronous ports: instr_out by PC, RD by address
--   F3 word index = (byte address / 4) mod size: byte offset ignored, wraps after 64 words
--
-- Checking: the testbench reads boot.hex itself into a model array, and the two boot
-- instructions are also checked against the README constants (so a wrong file is caught too).
-- Stimulus: every word on both ports, then random PC/address pairs (different on the two ports).
-- E1 wrong prediction must be caught.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.tb_pkg.all;

entity bootrom_tb is
    generic(
        G_SEED   : positive := 1;
        G_FILE   : string   := "boot.hex";
        G_N_RAND : natural  := 2000;
        G_INJECT : boolean  := true
    );
end entity bootrom_tb;

architecture sim of bootrom_tb is
    subtype word_t is std_logic_vector(31 downto 0);
    constant C_SIZE   : positive := 64;
    constant C_SETTLE : time := 1 ns;
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

    constant MODEL : mem_t := load_hex(G_FILE);

    signal PC, addr  : word_t := (others => '0');
    signal RD, instr : word_t;
    signal done      : boolean := false;

    shared variable rnd : tb_rand_t;
begin
    watchdog : tb_watchdog(done, 1 ms);

    dut : entity work.bootrom
        generic map(file_S => G_FILE, size => C_SIZE)
        port map(PC => PC, address => addr, RD => RD, instr_out => instr);

    stimulus : process
        variable n_wrap, n_unaligned : natural := 0;

        impure function expect_at(a : word_t) return word_t is
        begin
            return MODEL((to_integer(unsigned(a(31 downto 2))) mod C_SIZE));
        end function;

        procedure check_ports(p, a : word_t; corrupt : boolean := false) is
            variable exp : word_t := expect_at(a);
        begin
            PC   <= p;
            addr <= a;
            wait for C_SETTLE;
            if corrupt then exp := not exp; end if;
            tb_check_equal(instr, expect_at(p), "instr port at PC " & to_str(p));
            tb_check_equal(RD, exp, "data port at address " & to_str(a));
            if unsigned(p(31 downto 2)) >= C_SIZE + 16#1000# / 4 then n_wrap := n_wrap + 1; end if;
            if a(1 downto 0) /= "00" then n_unaligned := n_unaligned + 1; end if;
        end procedure;

        variable a : word_t;
    begin
        rnd.seed(G_SEED);
        tb_info("bootrom_tb seed=" & integer'image(G_SEED) & " file=" & G_FILE);

        tb_info("T1: boot code matches the README");
        tb_check_equal(MODEL(0), x"800002B7", "boot.hex word 0 (lui x5, 0x80000)");
        tb_check_equal(MODEL(1), x"00028067", "boot.hex word 1 (jalr x0, 0(x5))");
        check_ports(x"00001000", x"00001004");
        tb_check_equal(instr, x"800002B7", "reset vector instruction");
        tb_check_equal(RD, x"00028067", "data port word 1");

        tb_info("T2: every word on both ports (ports addressed differently)");
        for i in 0 to C_SIZE - 1 loop
            check_ports(std_logic_vector(to_unsigned(16#1000# + 4 * i, 32)),
                        std_logic_vector(to_unsigned(16#1000# + 4 * (C_SIZE - 1 - i), 32)));
        end loop;

        tb_info("T3: wraparound and byte offsets");
        check_ports(x"00001100", x"00001101");      -- word 64 -> word 0
        check_ports(x"00001104", x"00001006");      -- word 65 -> 1, byte 2 of word 1
        check_ports(x"000010FC", x"00001007");

        tb_info("T4: random addresses");
        tb_set_verbose(false);
        for k in 1 to G_N_RAND loop
            a := rnd.slv(32);
            check_ports(rnd.slv(32), a);
        end loop;
        tb_set_verbose(true);
        tb_check(n_wrap > 0 and n_unaligned > 0, "coverage: wrap / unaligned");

        if G_INJECT then
            tb_expect_errors(1, "E1: wrong ROM prediction must be caught");
            check_ports(x"00001000", x"00001000", corrupt => true);
            tb_end_expect;
        end if;

        done <= true;
        tb_finish;
        wait;
    end process stimulus;
end architecture sim;
