library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Boot ROM at 0x1000, preloaded from boot.hex:
--   0x1000: 800002B7  lui  x5, 0x80000
--   0x1004: 00028067  jalr x0, 0(x5)      -> jump to RAM at 0x8000_0000
-- Both the instruction port (PC) and the data port (address) read the same words.
entity bootrom_tb is
end entity;

architecture sim of bootrom_tb is
    signal PC, addr  : std_logic_vector(31 downto 0) := (others => '0');
    signal RD, instr : std_logic_vector(31 downto 0);
begin
    dut : entity work.bootrom
        generic map(file_S => "boot.hex", size => 64)
        port map(PC => PC, address => addr, RD => RD, instr_out => instr);

    process
        procedure check(a : std_logic_vector(31 downto 0); d : std_logic_vector(31 downto 0); msg : string) is
        begin
            PC <= a; addr <= a;
            wait for 1 ns;
            assert instr = d report msg & " (instr port): got " & to_hstring(instr) & " expected " & to_hstring(d) severity error;
            assert RD = d report msg & " (data port): got " & to_hstring(RD) & " expected " & to_hstring(d) severity error;
        end procedure;
    begin
        check(x"00001000", x"800002B7", "reset vector: lui x5, 0x80000");
        check(x"00001004", x"00028067", "jalr x0, 0(x5)");
        check(x"00001008", x"00000000", "rest of ROM is 0");
        check(x"000010FC", x"00000000", "last word is 0");
        check(x"00001100", x"800002B7", "wraps after 64 words");
        check(x"00001006", x"00028067", "byte address inside a word selects that word");
        report "bootrom_tb done";
        wait;
    end process;
end architecture;
