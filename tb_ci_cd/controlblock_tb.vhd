library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- controlblock = ControlUnit + branch decision. Checks PCsrc for every opcode/funct3/zero.
entity controlblock_tb is
end entity;

architecture sim of controlblock_tb is
    signal instr       : std_logic_vector(31 downto 0) := (others => '0');
    signal zero        : std_logic := '0';
    signal Illegal, RegWrite, BSrc, Mem_Write, JalrReg : std_logic;
    signal PCsrc, Result_Src, CSRop : std_logic_vector(1 downto 0);
    signal irq, MIE, MEIE : std_logic := '0';
    signal TRAP, CSWrite, MRET : std_logic;
    signal ASrc        : std_logic_vector(1 downto 0);
    signal ImmSrc      : std_logic_vector(2 downto 0);
    signal alu_control : std_logic_vector(3 downto 0);
begin
    dut : entity work.controlblock
        port map(instr => instr, zero => zero, Illegal => Illegal, RegWrite => RegWrite,
                 ASrc => ASrc, BSrc => BSrc, ImmSrc => ImmSrc, alu_control => alu_control, PCsrc => PCsrc, Mem_Write => Mem_Write,
                 Result_Src => Result_Src, JalrReg => JalrReg, irq => irq, MIE => MIE, MEIE => MEIE,
                 TRAP => TRAP, CSRop => CSRop, CSWrite => CSWrite, MRET => MRET);

    process
        variable expected : std_logic_vector(1 downto 0);
    begin
        -- named examples
        instr <= x"00500093"; wait for 1 ns; -- addi x1,x0,5
        assert RegWrite = '1' and BSrc = '1' and ASrc = "00" and alu_control = "0000" and Illegal = '0' report "addi" severity error;
        instr <= x"40208133"; wait for 1 ns; -- sub x2,x1,x2
        assert RegWrite = '1' and BSrc = '0' and ASrc = "00" and alu_control = "1000" and Illegal = '0' report "sub" severity error;
        instr <= x"FFFFFFFF"; wait for 1 ns;
        assert Illegal = '1' and RegWrite = '0' and PCsrc = "00" report "garbage must be illegal" severity error;

        instr <= x"0020A423"; wait for 1 ns; -- sw x2,8(x1)
        assert Mem_Write = '1' and RegWrite = '0' and BSrc = '1' and ImmSrc = "001" and Illegal = '0'
            report "sw" severity error;
        instr <= x"00500093"; wait for 1 ns;
        assert Mem_Write = '0' report "addi must not write memory" severity error;

        instr <= x"008000EF"; zero <= '0'; wait for 1 ns; -- jal x1,+8
        assert PCsrc = "01" and RegWrite = '1' and JalrReg = '0' and ImmSrc = "011" and Illegal = '0'
            report "jal" severity error;
        instr <= x"00408167"; zero <= '0'; wait for 1 ns; -- jalr x2,4(x1)
        assert PCsrc = "01" and RegWrite = '1' and JalrReg = '1' and Illegal = '0' report "jalr" severity error;
        instr <= x"00409167"; wait for 1 ns; -- jalr with funct3=1 is illegal
        assert Illegal = '1' and PCsrc = "00" and JalrReg = '0' report "jalr funct3/=0 must be illegal" severity error;
        zero <= '0';

        instr <= x"123450B7"; wait for 1 ns; -- lui x1,0x12345
        assert Illegal = '0' and RegWrite = '1' and Mem_Write = '0' and PCsrc = "00"
            report "lui: must be legal, write rd, not jump" severity error;
        assert ImmSrc = "100" and BSrc = '1' and ASrc = "10" and alu_control = "0000"
            report "lui: ALU must compute 0 + U-imm" severity error;
        instr <= x"00001117"; wait for 1 ns; -- auipc x2,0x1
        assert Illegal = '0' and RegWrite = '1' and Mem_Write = '0' and PCsrc = "00"
            report "auipc: must be legal, write rd, not jump" severity error;
        assert ImmSrc = "100" and BSrc = '1' and ASrc = "01" and alu_control = "0000"
            report "auipc: ALU must compute PC + U-imm" severity error;

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
                    expected := "00";
                    if op = 99 and (f3 = 0 or f3 = 5 or f3 = 7) and z = 1 then expected := "01"; end if;
                    if op = 99 and (f3 = 1 or f3 = 4 or f3 = 6) and z = 0 then expected := "01"; end if;
                    if op = 111 or (op = 103 and f3 = 0) then expected := "01"; end if;
                    assert PCsrc = expected and TRAP = '0' and MRET = '0'
                        report "PCsrc wrong: op=" & integer'image(op) & " f3=" & integer'image(f3) &
                               " zero=" & integer'image(z) & " got " & to_string(PCsrc) severity error;
                end loop;
            end loop;
        end loop;

        zero <= '0';

        instr <= x"30559673"; wait for 1 ns;
        assert Illegal = '0' and RegWrite = '1' and Result_Src = "11" and CSWrite = '1' and CSRop = "01"
            and Mem_Write = '0' and PCsrc = "00" report "csrrw" severity error;
        instr <= x"30082073"; wait for 1 ns;
        assert Illegal = '0' and CSWrite = '1' and CSRop = "10" and PCsrc = "00" report "csrrs" severity error;
        instr <= x"30002973"; wait for 1 ns;
        assert Illegal = '0' and RegWrite = '1' and Result_Src = "11" and CSWrite = '0' and CSRop = "10"
            report "csrrs with rs1 = x0 must not write the CSR" severity error;
        instr <= x"30083073"; wait for 1 ns;
        assert Illegal = '0' and CSWrite = '1' and CSRop = "11" report "csrrc" severity error;
        instr <= x"30003073"; wait for 1 ns;
        assert Illegal = '0' and CSWrite = '0' and CSRop = "11"
            report "csrrc with rs1 = x0 must not write the CSR" severity error;
        instr <= x"00000073"; wait for 1 ns;
        assert Illegal = '1' and CSWrite = '0' and MRET = '0' and RegWrite = '0' and PCsrc = "00"
            report "ecall must be illegal and write nothing" severity error;
        instr <= x"3005D073"; wait for 1 ns;
        assert Illegal = '1' and CSWrite = '0' and RegWrite = '0' report "csrrwi must be illegal" severity error;

        instr <= x"30200073"; wait for 1 ns;
        assert Illegal = '0' and MRET = '1' and PCsrc = "11" and RegWrite = '0' and Mem_Write = '0'
            and CSWrite = '0' and TRAP = '0' report "mret" severity error;

        for i in 0 to 7 loop
            if i mod 2 = 1 then irq <= '1'; else irq <= '0'; end if;
            if (i / 2) mod 2 = 1 then MIE <= '1'; else MIE <= '0'; end if;
            if i / 4 = 1 then MEIE <= '1'; else MEIE <= '0'; end if;
            instr <= x"0020A423"; wait for 1 ns;
            if i = 7 then
                assert TRAP = '1' and PCsrc = "10" and Mem_Write = '0' report "trap must block a store" severity error;
            else
                assert TRAP = '0' and Mem_Write = '1' report "no trap unless irq, MIE and MEIE are all 1, i="
                    & integer'image(i) severity error;
            end if;
            instr <= x"00500093"; wait for 1 ns;
            if i = 7 then
                assert TRAP = '1' and PCsrc = "10" and RegWrite = '0' report "trap must block a register write" severity error;
            else
                assert TRAP = '0' and PCsrc = "00" and RegWrite = '1' report "addi without trap" severity error;
            end if;
        end loop;
        instr <= x"008000EF"; wait for 1 ns;
        assert TRAP = '1' and PCsrc = "10" and RegWrite = '0' report "trap must win over jal" severity error;
        instr <= x"00000463"; zero <= '1'; wait for 1 ns;
        assert PCsrc = "10" report "trap must win over a taken branch" severity error;
        instr <= x"30200073"; wait for 1 ns;
        assert TRAP = '1' and PCsrc = "10" report "trap must win over mret" severity error;
        instr <= x"30559673"; wait for 1 ns;
        assert TRAP = '1' and RegWrite = '0' report "trap must block the rd write of csrrw" severity error;
        irq <= '0'; MIE <= '0'; MEIE <= '0'; zero <= '0';

        report "controlblock_tb done";
        wait;
    end process;
end architecture;
