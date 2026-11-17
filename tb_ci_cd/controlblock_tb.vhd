library ieee;
use ieee.std_logic_1164.all;

entity controlblock_tb is
end entity;

architecture sim of controlblock_tb is
    signal instr       : std_logic_vector(31 downto 0) := (others => '0');
    signal zero        : std_logic := '0';
    signal Illegal, RegWrite, AluSrc, PCsrc : std_logic;
    signal ImmSrc      : std_logic_vector(1 downto 0);
    signal alu_control : std_logic_vector(3 downto 0);
begin
    dut : entity work.controlblock
        port map(instr => instr, zero => zero, Illegal => Illegal, RegWrite => RegWrite,
                 AluSrc => AluSrc, ImmSrc => ImmSrc, alu_control => alu_control, PCsrc => PCsrc);

    process
    begin
        -- addi x1, x0, 5
        instr <= x"00500093"; wait for 1 ns;
        assert RegWrite = '1' and AluSrc = '1' and alu_control = "0000" and Illegal = '0' and PCsrc = '0'
            report "addi wrong" severity error;

        -- add x3, x1, x2
        instr <= x"002081B3"; wait for 1 ns;
        assert RegWrite = '1' and AluSrc = '0' and alu_control = "0000" and Illegal = '0'
            report "add wrong" severity error;

        -- sub x2, x1, x2
        instr <= x"40208133"; wait for 1 ns;
        assert RegWrite = '1' and AluSrc = '0' and alu_control = "1000" and Illegal = '0'
            report "sub wrong" severity error;

        -- beq x1, x0, +0x20: taken only when zero = 1
        instr <= x"02008063"; zero <= '1'; wait for 1 ns;
        assert PCsrc = '1' and RegWrite = '0' and ImmSrc = "10" and alu_control = "1000"
            report "beq taken wrong" severity error;
        zero <= '0'; wait for 1 ns;
        assert PCsrc = '0' report "beq not taken wrong" severity error;

        -- bne x1, x0, -16: taken only when zero = 0
        instr <= x"FE0098E3"; zero <= '0'; wait for 1 ns;
        assert PCsrc = '1' report "bne taken wrong" severity error;
        zero <= '1'; wait for 1 ns;
        assert PCsrc = '0' report "bne not taken wrong" severity error;

        -- garbage
        instr <= x"FFFFFFFF"; wait for 1 ns;
        assert Illegal = '1' and RegWrite = '0' report "illegal not detected" severity error;

        report "controlblock_tb done";
        wait;
    end process;
end architecture;
