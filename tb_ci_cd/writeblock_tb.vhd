library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Exhaustive over Mem_Write x funct3 x address offset. Spec: sb/sh/sw store 1/2/4 bytes at the
-- address; WE selects exactly those byte lanes, each enabled lane carries the matching byte of rs2.
-- Misaligned accesses, other funct3 values and Mem_Write = 0 must not write anything.
entity writeblock_tb is
end entity;

architecture sim of writeblock_tb is
    signal rd2    : std_logic_vector(31 downto 0) := x"A1B2C3D4";
    signal addr   : std_logic_vector(1 downto 0) := "00";
    signal mw     : std_logic := '0';
    signal funct3 : std_logic_vector(2 downto 0) := "000";
    signal WE     : std_logic_vector(3 downto 0);
    signal wD     : std_logic_vector(31 downto 0);
begin
    dut : entity work.WriteBlock
        port map(rd2 => rd2, addr_2_bits => addr, Mem_Write => mw, funct3 => funct3, WE => WE, wD => wD);

    process
        variable width, off : integer;
        variable exp_we : std_logic_vector(3 downto 0);
    begin
        for m in 0 to 1 loop
            for f in 0 to 7 loop
                for a in 0 to 3 loop
                    mw <= '1' when m = 1 else '0';
                    funct3 <= std_logic_vector(to_unsigned(f, 3));
                    addr <= std_logic_vector(to_unsigned(a, 2));
                    wait for 1 ns;

                    exp_we := (others => '0');
                    if m = 1 and f <= 2 then
                        width := 2 ** f;
                        off := a;
                        if off mod width = 0 then
                            for i in 0 to width - 1 loop exp_we(off + i) := '1'; end loop;
                        end if;
                    end if;

                    assert WE = exp_we
                        report "WE wrong: mw=" & integer'image(m) & " f3=" & integer'image(f) &
                               " addr=" & integer'image(a) & " got " & to_string(WE) severity error;

                    if exp_we /= "0000" then
                        for i in 0 to 3 loop
                            if exp_we(i) = '1' then
                                assert wD(8 * i + 7 downto 8 * i) = rd2(8 * (i - a) + 7 downto 8 * (i - a))
                                    report "wD lane " & integer'image(i) & " wrong: f3=" & integer'image(f) &
                                           " addr=" & integer'image(a) severity error;
                            end if;
                        end loop;
                    end if;
                end loop;
            end loop;
        end loop;
        report "writeblock_tb done";
        std.env.finish;
    end process;
end architecture;
