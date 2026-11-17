library ieee;
use ieee.std_logic_1164.all;

-- program.hex: 00500093, 00700113, 002081B3
entity instruction_memory_tb is
end entity;

architecture sim of instruction_memory_tb is
    signal PC        : std_logic_vector(31 downto 0) := (others => '0');
    signal instr_out : std_logic_vector(31 downto 0);
begin
    dut : entity work.instruction_memory
        generic map(file_S => "program.hex", size => 32)
        port map(PC => PC, instr_out => instr_out);

    process
    begin
        PC <= x"00000000"; wait for 10 ns;
        assert instr_out = x"00500093" report "word 0 wrong" severity error;
        PC <= x"00000004"; wait for 10 ns;
        assert instr_out = x"00700113" report "word 1 wrong" severity error;
        PC <= x"00000008"; wait for 10 ns;
        assert instr_out = x"002081B3" report "word 2 wrong" severity error;
        PC <= x"0000000C"; wait for 10 ns;
        assert instr_out = x"00000013" report "empty word must be NOP" severity error;
        report "instruction_memory_tb done";
        wait;
    end process;
end architecture;
