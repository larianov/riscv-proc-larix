library ieee;
use ieee.std_logic_1164.all;

entity instruction_memory_tb is
end entity;

architecture sim of instruction_memory_tb is
    signal PC        : std_logic_vector(31 downto 0);
    signal instr_out : std_logic_vector(31 downto 0);
begin

    dut : entity work.instruction_memory
        generic map(file_S => "program.hex",
            size => 32
        )
        port map(
            PC => PC,
            instr_out => instr_out
        );
    process
    begin
        PC <= x"00000000"; wait for 10 ns;
        PC <= x"00000004"; wait for 10 ns;
        PC <= x"00000008"; wait for 10 ns;
        PC <= x"0000000C"; wait for 10 ns;
        wait;
    end process;

end architecture;