-- Not a test by itself (no _tb suffix, run.sh skips it): writes ControlUnit's outputs for every
-- opcode / funct3 / funct7 (and rs1 = 0 / 1 for SYSTEM) to controlunit_dump.txt.
-- check_docs.sh compares the file against the JS decoder in docs/cpu.html.
-- Line: op f3 f7 rs1 bits, bits = RegWrite ASrc BSrc Illegal Branch ImmSrc Mem_Write Result_Src
--                                   alu_control CSRwrite CSRop MRET JalrReg Jump
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity controlunit_dump is
end entity;

architecture sim of controlunit_dump is
    signal opcode, funct7 : std_logic_vector(6 downto 0);
    signal funct3 : std_logic_vector(2 downto 0);
    signal rs1 : std_logic_vector(4 downto 0);
    signal RegWrite, BSrc, Illegal, Branch, Mem_Write, CSRwrite, MRET, JalrReg, Jump : std_logic;
    signal ASrc, Result_Src, CSRop : std_logic_vector(1 downto 0);
    signal ImmSrc : std_logic_vector(2 downto 0);
    signal alu_control : std_logic_vector(3 downto 0);
begin
    dut : entity work.ControlUnit
        port map(opcode => opcode, funct3 => funct3, funct7 => funct7, RegWrite => RegWrite, ASrc => ASrc,
                 BSrc => BSrc, Illegal => Illegal, Branch => Branch, ImmSrc => ImmSrc, Mem_Write => Mem_Write,
                 Result_Src => Result_Src, alu_control => alu_control, rs1 => rs1, CSRwrite => CSRwrite,
                 CSRop => CSRop, MRET => MRET, JalrReg => JalrReg, Jump => Jump);

    process
        file f : text open write_mode is "controlunit_dump.txt";
        variable l : line;
        variable last_rs1 : integer;
        function b(s : std_logic_vector) return string is
            variable r : string(1 to s'length);
            variable i : integer := 1;
        begin
            for k in s'range loop
                if s(k) = '1' then r(i) := '1'; else r(i) := '0'; end if;
                i := i + 1;
            end loop;
            return r;
        end function;
        function b(s : std_logic) return string is
        begin
            if s = '1' then return "1"; else return "0"; end if;
        end function;
    begin
        for op in 0 to 127 loop
            if op = 16#73# then last_rs1 := 1; else last_rs1 := 0; end if;
            for f3 in 0 to 7 loop
                for f7 in 0 to 127 loop
                    for r in 0 to last_rs1 loop
                        opcode <= std_logic_vector(to_unsigned(op, 7));
                        funct3 <= std_logic_vector(to_unsigned(f3, 3));
                        funct7 <= std_logic_vector(to_unsigned(f7, 7));
                        rs1 <= std_logic_vector(to_unsigned(r, 5));
                        wait for 1 ns;
                        write(l, integer'image(op) & " " & integer'image(f3) & " " & integer'image(f7) & " " &
                                 integer'image(r) & " " & b(RegWrite) & b(ASrc) & b(BSrc) & b(Illegal) &
                                 b(Branch) & b(ImmSrc) & b(Mem_Write) & b(Result_Src) & b(alu_control) &
                                 b(CSRwrite) & b(CSRop) & b(MRET) & b(JalrReg) & b(Jump));
                        writeline(f, l);
                    end loop;
                end loop;
            end loop;
        end loop;
        file_close(f);
        wait;
    end process;
end architecture;
