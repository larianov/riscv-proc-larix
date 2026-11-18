library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Word-addressed data memory with per-byte write enables: a write changes only the enabled
-- lanes of the addressed word, nothing else, and WE = 0 changes nothing.
entity memory_data_tb is
end entity;

architecture sim of memory_data_tb is
    signal clk  : std_logic := '0';
    signal addr : std_logic_vector(31 downto 0) := (others => '0');
    signal wD   : std_logic_vector(31 downto 0) := (others => '0');
    signal WE   : std_logic_vector(3 downto 0) := "0000";
    signal RD   : std_logic_vector(31 downto 0);
begin
    clk <= not clk after 5 ns;
    dut : entity work.memory_data generic map(size => 16)
        port map(clk => clk, address => addr, wD => wD, WE => WE, RD => RD);

    process
        procedure write(a : integer; d : std_logic_vector(31 downto 0); en : std_logic_vector(3 downto 0)) is
        begin
            addr <= std_logic_vector(to_unsigned(a, 32)); wD <= d; WE <= en;
            wait until falling_edge(clk);
            WE <= "0000";
            wait for 1 ns;
        end procedure;

        procedure expect(a : integer; d : std_logic_vector(31 downto 0); msg : string) is
        begin
            addr <= std_logic_vector(to_unsigned(a, 32));
            wait for 1 ns;
            assert RD = d report msg & ": got " & to_hstring(RD) & " expected " & to_hstring(d) severity error;
        end procedure;
    begin
        wait until falling_edge(clk);

        write(0, x"11223344", "1111");
        expect(0, x"11223344", "full word write");

        write(0, x"AABBCCDD", "0001"); expect(0, x"112233DD", "byte 0 only");
        write(0, x"AABBCCDD", "0010"); expect(0, x"1122CCDD", "byte 1 only");
        write(0, x"AABBCCDD", "0100"); expect(0, x"11BBCCDD", "byte 2 only");
        write(0, x"AABBCCDD", "1000"); expect(0, x"AABBCCDD", "byte 3 only");
        write(0, x"01234567", "0011"); expect(0, x"AABB4567", "low half");
        write(0, x"89ABCDEF", "1100"); expect(0, x"89AB4567", "high half");
        write(0, x"FFFFFFFF", "0000"); expect(0, x"89AB4567", "WE=0 must not write");
        write(0, x"FFFFFFFF", "0101"); expect(0, x"89FF45FF", "non-contiguous lanes");

        -- other words are untouched and independent
        expect(4, x"00000000", "neighbour untouched");
        write(12, x"CAFEBABE", "1111");
        expect(12, x"CAFEBABE", "word 3");
        expect(0, x"89FF45FF", "word 0 intact");

        -- byte address inside a word selects that word
        expect(13, x"CAFEBABE", "byte address 13 -> word 3");

        report "memory_data_tb done";
        std.env.finish;
    end process;
end architecture;
