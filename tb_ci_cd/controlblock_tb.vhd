library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- controlblock = ControlUnit + branch decision. Checks PCsrc for every opcode/funct3/zero.
entity controlblock_tb is
end entity;

architecture sim of controlblock_tb is
    signal instr       : std_logic_vector(31 downto 0) := (others => '0');
    signal zero        : std_logic := '0';
    signal Illegal, RegWrite, AluSrc, PCsrc, Mem_Write, JalrReg : std_logic;
    signal ImmSrc      : std_logic_vector(1 downto 0);
    signal alu_control : std_logic_vector(3 downto 0);
begin
    dut : entity work.controlblock
        port map(instr => instr, zero => zero, Illegal => Illegal, RegWrite => RegWrite,
                 AluSrc => AluSrc, ImmSrc => ImmSrc, alu_control => alu_control, PCsrc => PCsrc, Mem_Write => Mem_Write,
                 JalrReg => JalrReg);

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

        instr <= x"0020A423"; wait for 1 ns; -- sw x2,8(x1)
        assert Mem_Write = '1' and RegWrite = '0' and AluSrc = '1' and ImmSrc = "01" and Illegal = '0'
            report "sw" severity error;
        instr <= x"00500093"; wait for 1 ns;
        assert Mem_Write = '0' report "addi must not write memory" severity error;

        instr <= x"008000EF"; zero <= '0'; wait for 1 ns; -- jal x1,+8
        assert PCsrc = '1' and RegWrite = '1' and JalrReg = '0' and ImmSrc = "11" and Illegal = '0'
            report "jal" severity error;
        instr <= x"00408167"; zero <= '0'; wait for 1 ns; -- jalr x2,4(x1)
        assert PCsrc = '1' and RegWrite = '1' and JalrReg = '1' and Illegal = '0' report "jalr" severity error;
        instr <= x"00409167"; wait for 1 ns; -- jalr with funct3=1 is illegal
        assert Illegal = '1' and PCsrc = '0' and JalrReg = '0' report "jalr funct3/=0 must be illegal" severity error;
        zero <= '0';

        -- PCsrc: the ALU result is 0 when the compared condition is false for blt/bltu (slt/sltu = 0)
        -- and for bne (a-b = 0), so: beq jumps on zero=1, bne/blt/bltu jump on zero=0,
        -- bge/bgeu jump on zero=1 (slt = 0 means "not less"). jal/jalr always jump (any zero); nothing else ever jumps.
        for op in 0 to 127 loop
            for f3 in 0 to 7 loop
                for z in 0 to 1 loop
                    instr <= x"00000000";
                    instr(6 downto 0)   <= std_logic_vector(to_unsigned(op, 7));
                    instr(14 downto 12) <= std_logic_vector(to_unsigned(f3, 3));
                    if z = 1 then zero <= '1'; else zero <= '0'; end if;
                    wait for 1 ns;
                    expected := '0';
                    if op = 99 and (f3 = 0 or f3 = 5 or f3 = 7) and z = 1 then expected := '1'; end if;
                    if op = 99 and (f3 = 1 or f3 = 4 or f3 = 6) and z = 0 then expected := '1'; end if;
                    if op = 111 or (op = 103 and f3 = 0) then expected := '1'; end if;
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
