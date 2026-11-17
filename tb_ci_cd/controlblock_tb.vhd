library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- controlblock = ControlUnit + branch decision. Checks PCsrc for every opcode/funct3/zero.
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
        variable expected : std_logic;
    begin
        -- named examples
        instr <= x"00500093"; wait for 1 ns; -- addi x1,x0,5
        assert RegWrite = '1' and AluSrc = '1' and alu_control = "0000" and Illegal = '0' report "addi" severity error;
        instr <= x"40208133"; wait for 1 ns; -- sub x2,x1,x2
        assert RegWrite = '1' and AluSrc = '0' and alu_control = "1000" and Illegal = '0' report "sub" severity error;
        instr <= x"FFFFFFFF"; wait for 1 ns;
        assert Illegal = '1' and RegWrite = '0' and PCsrc = '0' report "garbage must be illegal" severity error;

        -- PCsrc: beq jumps when zero=1, bne jumps when zero=0, nothing else ever jumps
        for op in 0 to 127 loop
            for f3 in 0 to 7 loop
                for z in 0 to 1 loop
                    instr <= x"00000000";
                    instr(6 downto 0)   <= std_logic_vector(to_unsigned(op, 7));
                    instr(14 downto 12) <= std_logic_vector(to_unsigned(f3, 3));
                    if z = 1 then zero <= '1'; else zero <= '0'; end if;
                    wait for 1 ns;
                    expected := '0';
                    if op = 99 and f3 = 0 and z = 1 then expected := '1'; end if;
                    if op = 99 and f3 = 1 and z = 0 then expected := '1'; end if;
                    assert PCsrc = expected
                        report "PCsrc wrong: op=" & integer'image(op) & " f3=" & integer'image(f3) &
                               " zero=" & integer'image(z) severity error;
                end loop;
            end loop;
        end loop;

        report "controlblock_tb done";
        wait;
    end process;
end architecture;
