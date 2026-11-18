library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Exhaustive over funct3 x address offset. Spec: lb/lbu pick byte `addr`, lh/lhu the halfword at
-- `addr` (sign / zero extended), lw returns the word. Misaligned lh/lhu/lw and other funct3
-- values return 0 (the block's documented behaviour).
entity readblock_tb is
end entity;

architecture sim of readblock_tb is
    signal mem    : std_logic_vector(31 downto 0) := x"A1B2C3D4";
    signal addr   : std_logic_vector(1 downto 0) := "00";
    signal funct3 : std_logic_vector(2 downto 0) := "000";
    signal rd     : std_logic_vector(31 downto 0);
begin
    dut : entity work.ReadBlock
        port map(Memory_Data => mem, addr_2_bits => addr, funct3 => funct3, ReadData => rd);

    process
        type word_array is array (0 to 2) of std_logic_vector(31 downto 0);
        constant WORDS : word_array := (x"A1B2C3D4", x"7F80FF01", x"00000000");
        variable exp : std_logic_vector(31 downto 0);
        variable b : std_logic_vector(7 downto 0);
        variable h : std_logic_vector(15 downto 0);
    begin
        for wi in WORDS'range loop
            for f in 0 to 7 loop
                for a in 0 to 3 loop
                    mem <= WORDS(wi);
                    funct3 <= std_logic_vector(to_unsigned(f, 3));
                    addr <= std_logic_vector(to_unsigned(a, 2));
                    wait for 1 ns;

                    b := WORDS(wi)(8 * a + 7 downto 8 * a);
                    exp := (others => '0');
                    case f is
                        when 0 => exp := (31 downto 8 => b(7)) & b;
                        when 4 => exp := x"000000" & b;
                        when 1 =>
                            if a = 0 or a = 2 then
                                h := WORDS(wi)(8 * a + 15 downto 8 * a);
                                exp := (31 downto 16 => h(15)) & h;
                            end if;
                        when 5 =>
                            if a = 0 or a = 2 then
                                exp := x"0000" & WORDS(wi)(8 * a + 15 downto 8 * a);
                            end if;
                        when 2 =>
                            if a = 0 then exp := WORDS(wi); end if;
                        when others => null;
                    end case;

                    assert rd = exp
                        report "ReadData wrong: word=" & to_hstring(WORDS(wi)) & " f3=" & integer'image(f) &
                               " addr=" & integer'image(a) & " got " & to_hstring(rd) &
                               " expected " & to_hstring(exp) severity error;
                end loop;
            end loop;
        end loop;
        report "readblock_tb done";
        std.env.finish;
    end process;
end architecture;
