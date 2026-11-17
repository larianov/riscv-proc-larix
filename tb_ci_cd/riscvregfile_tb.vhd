library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity riscvregfile_tb is
end entity;

architecture sim of riscvregfile_tb is
    signal clk : std_logic := '0';
    signal read_idx_first, read_idx_second, write_idx : std_logic_vector(4 downto 0) := (others => '0');
    signal read_out_first, read_out_second, write_In  : std_logic_vector(31 downto 0);
    signal write_en : std_logic := '0';
begin
    clk <= not clk after 5 ns;

    dut : entity work.riscvregfile
        port map(clk => clk, read_idx_first => read_idx_first, read_idx_second => read_idx_second,
                 read_out_first => read_out_first, read_out_second => read_out_second,
                 write_en => write_en, write_In => write_In, write_idx => write_idx);

    process
        type reg_array is array (0 to 31) of std_logic_vector(31 downto 0);
        variable model : reg_array := (others => (others => '0'));
        variable s1 : positive := 3;
        variable s2 : positive := 11;
        variable r : real;
        variable i, j, k : integer;
        variable v : std_logic_vector(31 downto 0);

        impure function rnd(n : integer) return integer is
            variable x : real;
        begin
            uniform(s1, s2, x);
            return integer(floor(x * real(n)));
        end function;
    begin
        -- all registers start at 0
        for n in 0 to 31 loop
            read_idx_first <= std_logic_vector(to_unsigned(n, 5));
            wait for 1 ns;
            assert read_out_first = x"00000000" report "reg not 0 at start: " & integer'image(n) severity error;
        end loop;

        -- random writes (also to x0, also with write_en = 0), random double reads checked against model
        for n in 0 to 5000 loop
            i := rnd(32);
            v := std_logic_vector(to_unsigned(rnd(65536), 16)) & std_logic_vector(to_unsigned(rnd(65536), 16));
            write_idx <= std_logic_vector(to_unsigned(i, 5));
            write_In  <= v;
            if rnd(4) = 0 then write_en <= '0'; else write_en <= '1'; end if;
            wait until falling_edge(clk);          -- rising edge happened in between
            if write_en = '1' and i /= 0 then model(i) := v; end if;

            j := rnd(32); k := rnd(32);
            read_idx_first  <= std_logic_vector(to_unsigned(j, 5));
            read_idx_second <= std_logic_vector(to_unsigned(k, 5));
            wait for 1 ns;
            assert read_out_first = model(j)
                report "port 1 wrong, reg " & integer'image(j) severity error;
            assert read_out_second = model(k)
                report "port 2 wrong, reg " & integer'image(k) severity error;
            assert read_out_first /= x"00000000" or model(j) = x"00000000" report "x0 broken" severity error;
        end loop;

        -- x0 is hard-wired to zero
        write_en <= '1'; write_idx <= "00000"; write_In <= x"FFFFFFFF";
        wait until falling_edge(clk);
        read_idx_first <= "00000"; wait for 1 ns;
        assert read_out_first = x"00000000" report "x0 was written" severity error;

        report "riscvregfile_tb done";
        std.env.finish;
    end process;
end architecture;
