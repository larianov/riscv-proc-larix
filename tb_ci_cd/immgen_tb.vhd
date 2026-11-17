library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity immgen_tb is
end entity;

architecture sim of immgen_tb is
    signal imm     : std_logic_vector(31 downto 0) := (others => '0');
    signal imm_src : std_logic_vector(1 downto 0)  := "00";
    signal imm_out : std_logic_vector(31 downto 0);
begin
    dut : entity work.ImmGen port map(imm => imm, imm_src => imm_src, imm_out => imm_out);

    process
        variable s1 : positive := 7;
        variable s2 : positive := 99;
        variable r  : real;
        variable hi : std_logic_vector(15 downto 0);
        variable w  : std_logic_vector(31 downto 0);
        variable exp_i, exp_b : std_logic_vector(31 downto 0);
    begin
        for k in 0 to 20000 loop
            uniform(s1, s2, r);
            hi := std_logic_vector(to_unsigned(integer(floor(r * 65536.0)), 16));
            uniform(s1, s2, r);
            w := hi & std_logic_vector(to_unsigned(integer(floor(r * 65536.0)), 16));
            if k = 0 then w := (others => '0'); end if;
            if k = 1 then w := (others => '1'); end if;

            exp_i := (31 downto 12 => w(31)) & w(31 downto 20);
            exp_b := (31 downto 13 => w(31)) & w(31) & w(7) & w(30 downto 25) & w(11 downto 8) & '0';

            imm <= w;
            imm_src <= "00"; wait for 1 ns;
            assert imm_out = exp_i report "I-immediate wrong for " & to_hstring(w) severity error;
            imm_src <= "10"; wait for 1 ns;
            assert imm_out = exp_b report "B-immediate wrong for " & to_hstring(w) severity error;
            imm_src <= "01"; wait for 1 ns;
            assert imm_out = x"00000000" report "unused imm_src 01 must give 0" severity error;
            imm_src <= "11"; wait for 1 ns;
            assert imm_out = x"00000000" report "unused imm_src 11 must give 0" severity error;
        end loop;
        report "immgen_tb done";
        wait;
    end process;
end architecture;
