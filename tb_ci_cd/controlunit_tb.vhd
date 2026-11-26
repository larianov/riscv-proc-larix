library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Exhaustive: every opcode (128) x funct3 (8) x funct7 (128) is compared with a reference table
-- written straight from the RISC-V spec.
entity controlunit_tb is
end entity;

architecture sim of controlunit_tb is
    signal opcode : std_logic_vector(6 downto 0) := (others => '0');
    signal funct3 : std_logic_vector(2 downto 0) := (others => '0');
    signal funct7 : std_logic_vector(6 downto 0) := (others => '0');
    signal rs1    : std_logic_vector(4 downto 0) := (others => '0');
    signal RegWrite, BSrc, Illegal, Branch, Mem_Write, JalrReg, Jump, CSRwrite, MRET : std_logic;
    signal CSRop : std_logic_vector(1 downto 0);
    signal ASrc : std_logic_vector(1 downto 0);
    signal ImmSrc : std_logic_vector(2 downto 0);
    signal alu_control : std_logic_vector(3 downto 0);
    signal Result_Src : std_logic_vector(1 downto 0);
begin
    dut : entity work.ControlUnit
        port map(opcode => opcode, funct3 => funct3, funct7 => funct7, RegWrite => RegWrite,
                 ASrc => ASrc, BSrc => BSrc, Illegal => Illegal, Branch => Branch, ImmSrc => ImmSrc,
                 alu_control => alu_control, Mem_Write => Mem_Write, Result_Src => Result_Src,
                 JalrReg => JalrReg, Jump => Jump, rs1 => rs1, CSRwrite => CSRwrite, CSRop => CSRop, MRET => MRET);

    process
        variable f3, f7, op : integer;
        variable exp_illegal : boolean;
        variable exp_ctl : std_logic_vector(3 downto 0);
        variable exp_branch, exp_bsrc, exp_regwrite, exp_memwrite, exp_jump, exp_jalr : std_logic;
        variable exp_csrwrite, exp_mret : std_logic;
        variable exp_csrop : std_logic_vector(1 downto 0);
        variable n_rs1 : integer;
        constant RS1_VALUES : integer_vector(0 to 2) := (0, 1, 31);
        variable check_alu : boolean;
        variable exp_rsrc, exp_asrc : std_logic_vector(1 downto 0);
        variable exp_imm : std_logic_vector(2 downto 0);
        variable errors : integer := 0;
        variable checked : integer := 0;
        -- ImmSrc encoding
        constant IMM_I : std_logic_vector(2 downto 0) := "000";
        constant IMM_S : std_logic_vector(2 downto 0) := "001";
        constant IMM_B : std_logic_vector(2 downto 0) := "010";
        constant IMM_J : std_logic_vector(2 downto 0) := "011";
        constant IMM_U : std_logic_vector(2 downto 0) := "100";
        -- ASrc encoding (SrcA of the ALU)
        constant A_RS1  : std_logic_vector(1 downto 0) := "00";
        constant A_PC   : std_logic_vector(1 downto 0) := "01";
        constant A_ZERO : std_logic_vector(1 downto 0) := "10";

        -- alu_control for an ALU operation: (funct3, bit 5 of funct7 = "alternate" op)
        function alu_code(f3 : integer; alt : boolean) return std_logic_vector is
        begin
            case f3 is
                when 0 => if alt then return "1000"; else return "0000"; end if; -- sub / add
                when 1 => return "0001"; -- sll
                when 2 => return "0010"; -- slt
                when 3 => return "0011"; -- sltu
                when 4 => return "0100"; -- xor
                when 5 => if alt then return "1101"; else return "0101"; end if; -- sra / srl
                when 6 => return "0110"; -- or
                when others => return "0111"; -- and
            end case;
        end function;
    begin
        for op in 0 to 127 loop
            for f3 in 0 to 7 loop
                for f7 in 0 to 127 loop
                  if op = 115 then n_rs1 := 2; else n_rs1 := 0; end if;
                  for r in 0 to n_rs1 loop
                    rs1    <= std_logic_vector(to_unsigned(RS1_VALUES(r), 5));
                    opcode <= std_logic_vector(to_unsigned(op, 7));
                    funct3 <= std_logic_vector(to_unsigned(f3, 3));
                    funct7 <= std_logic_vector(to_unsigned(f7, 7));

                    exp_illegal := true; exp_ctl := "0000"; exp_branch := '0';
                    exp_bsrc := '0'; exp_regwrite := '0'; exp_memwrite := '0'; exp_rsrc := "00";
                    exp_asrc := A_RS1; exp_imm := IMM_I;
                    exp_jump := '0'; exp_jalr := '0'; check_alu := true;
                    exp_csrwrite := '0'; exp_csrop := "00"; exp_mret := '0';

                    if op = 51 then -- R-type
                        exp_bsrc := '0';
                        if f7 = 0 then
                            exp_illegal := false; exp_ctl := alu_code(f3, false);
                        elsif f7 = 32 and (f3 = 0 or f3 = 5) then
                            exp_illegal := false; exp_ctl := alu_code(f3, true);
                        end if;
                        if not exp_illegal then exp_regwrite := '1'; end if;
                    elsif op = 19 then -- I-type ALU
                        exp_bsrc := '1';
                        if f3 = 1 then
                            exp_illegal := (f7 /= 0);
                            exp_ctl := alu_code(f3, false);
                        elsif f3 = 5 then
                            exp_illegal := not (f7 = 0 or f7 = 32);
                            exp_ctl := alu_code(f3, f7 = 32);
                        else
                            exp_illegal := false;
                            exp_ctl := alu_code(f3, false);
                        end if;
                        if not exp_illegal then exp_regwrite := '1'; end if;
                    elsif op = 99 then -- branch
                        if f3 = 0 or f3 = 1 then      -- beq bne: compare by subtraction
                            exp_illegal := false; exp_branch := '1'; exp_ctl := "1000"; exp_imm := IMM_B;
                        elsif f3 = 4 or f3 = 5 then   -- blt bge: signed compare
                            exp_illegal := false; exp_branch := '1'; exp_ctl := "0010"; exp_imm := IMM_B;
                        elsif f3 = 6 or f3 = 7 then   -- bltu bgeu: unsigned compare
                            exp_illegal := false; exp_branch := '1'; exp_ctl := "0011"; exp_imm := IMM_B;
                        end if;
                    elsif op = 35 then -- store: sb sh sw
                        if f3 <= 2 then
                            exp_illegal := false; exp_ctl := "0000"; exp_bsrc := '1'; exp_memwrite := '1';
                            exp_imm := IMM_S;
                        end if;
                    elsif op = 3 then -- load: lb lh lw lbu lhu
                        if f3 = 0 or f3 = 1 or f3 = 2 or f3 = 4 or f3 = 5 then
                            exp_illegal := false; exp_ctl := "0000"; exp_bsrc := '1'; exp_regwrite := '1';
                            exp_rsrc := "01";
                        end if;
                    elsif op = 111 then -- jal: rd = PC+4, PC = PC + J-imm (ALU unused)
                        exp_illegal := false; exp_jump := '1'; exp_regwrite := '1'; exp_rsrc := "10";
                        exp_imm := IMM_J; check_alu := false;
                    elsif op = 103 then -- jalr (funct3 must be 0): rd = PC+4, PC = (rs1 + I-imm) & ~1
                        if f3 = 0 then
                            exp_illegal := false; exp_jump := '1'; exp_jalr := '1'; exp_regwrite := '1';
                            exp_rsrc := "10"; check_alu := false;
                        end if;
                    elsif op = 55 then -- lui: rd = U-imm  (ALU: 0 + imm)
                        exp_illegal := false; exp_regwrite := '1'; exp_imm := IMM_U;
                        exp_asrc := A_ZERO; exp_bsrc := '1'; exp_ctl := "0000";
                    elsif op = 23 then -- auipc: rd = PC + U-imm  (ALU: PC + imm)
                        exp_illegal := false; exp_regwrite := '1'; exp_imm := IMM_U;
                        exp_asrc := A_PC; exp_bsrc := '1'; exp_ctl := "0000";
                    elsif op = 115 then
                        check_alu := false;
                        if f3 = 0 and f7 = 24 then
                            exp_illegal := false; exp_mret := '1';
                        elsif f3 = 1 then
                            exp_illegal := false; exp_regwrite := '1'; exp_rsrc := "11";
                            exp_csrwrite := '1'; exp_csrop := "01";
                        elsif f3 = 2 or f3 = 3 then
                            exp_illegal := false; exp_regwrite := '1'; exp_rsrc := "11";
                            if RS1_VALUES(r) /= 0 then exp_csrwrite := '1'; end if;
                            if f3 = 2 then exp_csrop := "10"; else exp_csrop := "11"; end if;
                        end if;
                    end if;

                    wait for 1 ns;

                    if (Illegal = '1') /= exp_illegal then
                        errors := errors + 1;
                        report "Illegal wrong: op=" & integer'image(op) & " f3=" & integer'image(f3) &
                               " f7=" & integer'image(f7) severity error;
                    end if;
                    if RegWrite /= exp_regwrite or Branch /= exp_branch or Mem_Write /= exp_memwrite then
                        errors := errors + 1;
                        report "RegWrite/Branch/Mem_Write wrong: op=" & integer'image(op) & " f3=" & integer'image(f3) &
                               " f7=" & integer'image(f7) severity error;
                    end if;
                    if Jump /= exp_jump or JalrReg /= exp_jalr then
                        errors := errors + 1;
                        report "Jump/JalrReg wrong: op=" & integer'image(op) & " f3=" & integer'image(f3) severity error;
                    end if;
                    if CSRwrite /= exp_csrwrite or MRET /= exp_mret then
                        errors := errors + 1;
                        report "CSRwrite/MRET wrong: op=" & integer'image(op) & " f3=" & integer'image(f3) &
                               " f7=" & integer'image(f7) & " rs1=" & integer'image(RS1_VALUES(r)) severity error;
                    end if;
                    if not exp_illegal and exp_csrop /= "00" and CSRop /= exp_csrop then
                        errors := errors + 1;
                        report "CSRop wrong: f3=" & integer'image(f3) & " got " & to_string(CSRop) severity error;
                    end if;
                    checked := checked + 1;
                    if not exp_illegal then -- other outputs are don't-care for illegal instructions
                        if check_alu and (alu_control /= exp_ctl or BSrc /= exp_bsrc or ASrc /= exp_asrc) then
                            errors := errors + 1;
                            report "alu_control/ASrc/BSrc wrong: op=" & integer'image(op) & " f3=" & integer'image(f3) &
                                   " f7=" & integer'image(f7) & " got ctl=" & to_string(alu_control) &
                                   " ASrc=" & to_string(ASrc) & " BSrc=" & std_logic'image(BSrc) severity error;
                        end if;
                        if Result_Src /= exp_rsrc then
                            errors := errors + 1;
                            report "Result_Src wrong: op=" & integer'image(op) & " f3=" & integer'image(f3) severity error;
                        end if;
                        if ImmSrc /= exp_imm then
                            errors := errors + 1;
                            report "ImmSrc wrong: op=" & integer'image(op) & " f3=" & integer'image(f3) &
                                   " got " & to_string(ImmSrc) & " expected " & to_string(exp_imm) severity error;
                        end if;
                    end if;
                  end loop;
                end loop;
            end loop;
        end loop;
        assert errors = 0 report integer'image(errors) & " mismatches" severity failure;
        report "controlunit_tb done, all " & integer'image(checked) & " combinations OK";
        wait;
    end process;
end architecture;
