--------------------------------------------------------------------------------
-- writeblock_tb : self-checking testbench for WriteBlock (store formatting, combinational)
--
-- Spec: README "WriteBlock" + "Supported instructions" (little-endian RV32I stores).
--   F1 sb (000): WE has exactly the one lane addr[1:0]; that lane of wD = rs2[7:0]
--   F2 sh (001): addr 0 -> WE 0011, addr 2 -> WE 1100; those lanes = rs2[15:0]; misaligned -> 0000
--   F3 sw (010): addr 0 -> WE 1111, wD = rs2; misaligned -> 0000
--   F4 Mem_Write = 0 -> WE = 0000 for every funct3/offset
--   F5 (assumption, spec only says "anything else writes nothing" at CPU level):
--      funct3 011..111 with Mem_Write = 1 -> WE = 0000
-- Lanes with WE = 0 are don't care (not checked).
--
-- Checking: byte enables built from (size, offset) with a loop, lane data taken from a
-- little-endian byte array of rs2.
-- E1 wrong WE prediction, E2 wrong lane data prediction must be caught.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tb_pkg.all;

entity writeblock_tb is
    generic(
        G_SEED   : positive := 1;
        G_N_RAND : natural  := 500;
        G_INJECT : boolean  := true
    );
end entity writeblock_tb;

architecture sim of writeblock_tb is
    subtype word_t is std_logic_vector(31 downto 0);
    constant C_SETTLE : time := 1 ns;

    signal rd2    : word_t := (others => '0');
    signal addr   : std_logic_vector(1 downto 0) := "00";
    signal mw     : std_logic := '0';
    signal funct3 : std_logic_vector(2 downto 0) := "000";
    signal WE     : std_logic_vector(3 downto 0);
    signal wD     : word_t;
    signal done   : boolean := false;

    shared variable rnd : tb_rand_t;
begin
    watchdog : tb_watchdog(done, 1 ms);

    dut : entity work.WriteBlock
        port map(rd2 => rd2, addr_2_bits => addr, Mem_Write => mw, funct3 => funct3, WE => WE, wD => wD);

    stimulus : process
        variable n_lanes : natural := 0;

        procedure check_store(d : word_t; m : std_logic; f3, off : natural;
                              corrupt_we : boolean := false; corrupt_data : boolean := false) is
            variable size   : natural := 0;
            variable exp_we : std_logic_vector(3 downto 0) := "0000";
        begin
            case f3 is
                when 0 => size := 1;
                when 1 => size := 2;
                when 2 => size := 4;
                when others => size := 0;
            end case;
            if m = '1' and size > 0 and off mod size = 0 then
                for i in 0 to size - 1 loop
                    exp_we(off + i) := '1';
                end loop;
            end if;
            if corrupt_we then exp_we := not exp_we; end if;
            rd2    <= d;
            mw     <= m;
            funct3 <= std_logic_vector(to_unsigned(f3, 3));
            addr   <= std_logic_vector(to_unsigned(off, 2));
            wait for C_SETTLE;
            tb_check_equal(WE, exp_we, "WE mw=" & to_str(m) & " f3=" & integer'image(f3) & " off=" &
                                       integer'image(off));
            if corrupt_we then return; end if;
            for lane in 0 to 3 loop
                if exp_we(lane) = '1' then
                    -- lane `lane` holds byte (lane - off) of rs2
                    if corrupt_data then
                        tb_check_equal(wD(8 * lane + 7 downto 8 * lane), not d(8 * (lane - off) + 7 downto 8 * (lane - off)),
                                       "wD lane " & integer'image(lane) & " (injected)");
                        return;
                    end if;
                    tb_check_equal(wD(8 * lane + 7 downto 8 * lane), d(8 * (lane - off) + 7 downto 8 * (lane - off)),
                                   "wD lane " & integer'image(lane) & " f3=" & integer'image(f3) &
                                   " off=" & integer'image(off) & " rs2=" & to_str(d));
                    n_lanes := n_lanes + 1;
                end if;
            end loop;
        end procedure;

        procedure all_cases(d : word_t) is
        begin
            for m in 0 to 1 loop
                for f3 in 0 to 7 loop
                    for off in 0 to 3 loop
                        if m = 1 then check_store(d, '1', f3, off); else check_store(d, '0', f3, off); end if;
                    end loop;
                end loop;
            end loop;
        end procedure;
    begin
        rnd.seed(G_SEED);
        tb_info("writeblock_tb seed=" & integer'image(G_SEED));
        tb_info("T1: directed data, every Mem_Write x funct3 x offset");
        all_cases(x"A1B2C3D4");
        all_cases(x"00000000");
        all_cases(x"FFFFFFFF");
        tb_info("T2: random data");
        for k in 1 to G_N_RAND loop
            all_cases(rnd.slv(32));
        end loop;
        tb_check(n_lanes > 0, "coverage: no lane data was checked");

        if G_INJECT then
            tb_expect_errors(1, "E1: wrong byte-enable prediction must be caught");
            check_store(x"11223344", '1', 1, 2, corrupt_we => true);
            tb_end_expect;
            tb_expect_errors(1, "E2: wrong lane data prediction must be caught");
            check_store(x"11223344", '1', 0, 3, corrupt_data => true);
            tb_end_expect;
        end if;

        done <= true;
        tb_finish;
        wait;
    end process stimulus;
end architecture sim;
