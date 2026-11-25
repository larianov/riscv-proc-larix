library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Unified RAM (instructions + data), mapped at 0x8000_0000 by MMIO.
--  * instr port: preloaded from program.hex, addressed by PC, wraps mod size
--  * data port: word addressed, per-byte write enables, WE = 0 writes nothing
--  * a data write is visible on the instruction port (same array)
-- program.hex: 00500093, 00700113, 002081B3 (3 words, rest of the RAM is 0)
entity unifiedmem_tb is
end entity;

architecture sim of unifiedmem_tb is
    constant SIZE : integer := 32;
    signal clk   : std_logic := '0';
    signal PC    : std_logic_vector(31 downto 0) := (others => '0');
    signal instr : std_logic_vector(31 downto 0);
    signal addr  : std_logic_vector(31 downto 0) := x"80000000";
    signal wD    : std_logic_vector(31 downto 0) := (others => '0');
    signal WE    : std_logic_vector(3 downto 0) := "0000";
    signal RD    : std_logic_vector(31 downto 0);
begin
    clk <= not clk after 5 ns;
    dut : entity work.unifiedmem
        generic map(file_S => "program.hex", size => SIZE)
        port map(PC => PC, instr_out => instr, clk => clk, address => addr, wD => wD, WE => WE, RD => RD);

    process
        -- addresses are given as RAM offsets; the 0x8000_0000 base must not matter (mod size)
        procedure write(a : integer; d : std_logic_vector(31 downto 0); en : std_logic_vector(3 downto 0)) is
        begin
            addr <= std_logic_vector(x"80000000" + to_unsigned(a, 32)); wD <= d; WE <= en;
            wait until rising_edge(clk);
            wait for 1 ns;
            WE <= "0000";
            wait for 1 ns;
        end procedure;

        procedure expect(a : integer; d : std_logic_vector(31 downto 0); msg : string) is
        begin
            addr <= std_logic_vector(x"80000000" + to_unsigned(a, 32));
            wait for 1 ns;
            assert RD = d report msg & ": got " & to_hstring(RD) & " expected " & to_hstring(d) severity error;
        end procedure;

        procedure fetch(p : std_logic_vector(31 downto 0); d : std_logic_vector(31 downto 0); msg : string) is
        begin
            PC <= p;
            wait for 1 ns;
            assert instr = d report msg & ": got " & to_hstring(instr) & " expected " & to_hstring(d) severity error;
        end procedure;
    begin
        wait until falling_edge(clk);

        -- instruction port: file contents
        fetch(x"80000000", x"00500093", "word 0");
        fetch(x"80000004", x"00700113", "word 1");
        fetch(x"80000008", x"002081B3", "word 2");
        fetch(x"8000000C", x"00000000", "word past the file must be 0");
        fetch(x"8000007C", x"00000000", "last word must be 0");
        fetch(x"00000000", x"00500093", "PC is taken mod size (no base check)");
        fetch(x"80000080", x"00500093", "PC wraps after size words");

        -- data port reads the same preloaded contents
        expect(4, x"00700113", "data port sees program word 1");

        -- byte enables (word 20 is past the program)
        write(80, x"11223344", "1111"); expect(80, x"11223344", "full word write");
        write(80, x"AABBCCDD", "0001"); expect(80, x"112233DD", "byte 0 only");
        write(80, x"AABBCCDD", "0010"); expect(80, x"1122CCDD", "byte 1 only");
        write(80, x"AABBCCDD", "0100"); expect(80, x"11BBCCDD", "byte 2 only");
        write(80, x"AABBCCDD", "1000"); expect(80, x"AABBCCDD", "byte 3 only");
        write(80, x"01234567", "0011"); expect(80, x"AABB4567", "low half");
        write(80, x"89ABCDEF", "1100"); expect(80, x"89AB4567", "high half");
        write(80, x"FFFFFFFF", "0000"); expect(80, x"89AB4567", "WE=0 must not write");
        write(80, x"FFFFFFFF", "0101"); expect(80, x"89FF45FF", "non-contiguous lanes");

        expect(84, x"00000000", "neighbour untouched");
        expect(81, x"89FF45FF", "byte address inside a word selects that word");
        expect(4, x"00700113", "program word untouched");

        -- self-modifying: a data write shows up on the instruction port
        write(8, x"DEADBEEF", "1111");
        fetch(x"80000008", x"DEADBEEF", "instr port must see data write");

        report "unifiedmem_tb done";
        std.env.finish;
    end process;
end architecture;
