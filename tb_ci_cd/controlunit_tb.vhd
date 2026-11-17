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
    signal RegWrite, AluSrc, Illegal, Branch : std_logic;
    signal ImmSrc : std_logic_vector(1 downto 0);
    signal alu_control : std_logic_vector(3 downto 0);
begin
    dut : entity work.ControlUnit
        port map(opcode => opcode, funct3 => funct3, funct7 => funct7, RegWrite => RegWrite,
                 AluSrc => AluSrc, Illegal => Illegal, Branch => Branch, ImmSrc => ImmSrc,
                 alu_control => alu_control);

    process
        variable f3, f7, op : integer;
        variable exp_illegal : boolean;
        variable exp_ctl : std_logic_vector(3 downto 0);
        variable exp_branch, exp_alusrc, exp_regwrite : std_logic;
        variable errors : integer := 0;

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
                    opcode <= std_logic_vector(to_unsigned(op, 7));
                    funct3 <= std_logic_vector(to_unsigned(f3, 3));
                    funct7 <= std_logic_vector(to_unsigned(f7, 7));

                    exp_illegal := true; exp_ctl := "0000"; exp_branch := '0';
                    exp_alusrc := '0'; exp_regwrite := '0';

                    if op = 51 then -- R-type
                        exp_alusrc := '0';
                        if f7 = 0 then
                            exp_illegal := false; exp_ctl := alu_code(f3, false);
                        elsif f7 = 32 and (f3 = 0 or f3 = 5) then
                            exp_illegal := false; exp_ctl := alu_code(f3, true);
                        end if;
                        if not exp_illegal then exp_regwrite := '1'; end if;
                    elsif op = 19 then -- I-type ALU
                        exp_alusrc := '1';
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
                        if f3 = 0 or f3 = 1 then
                            exp_illegal := false; exp_branch := '1'; exp_ctl := "1000";
                        end if;
                    end if;

                    wait for 1 ns;

                    if (Illegal = '1') /= exp_illegal then
                        errors := errors + 1;
                        report "Illegal wrong: op=" & integer'image(op) & " f3=" & integer'image(f3) &
                               " f7=" & integer'image(f7) severity error;
                    end if;
                    if RegWrite /= exp_regwrite or Branch /= exp_branch then
                        errors := errors + 1;
                        report "RegWrite/Branch wrong: op=" & integer'image(op) & " f3=" & integer'image(f3) &
                               " f7=" & integer'image(f7) severity error;
                    end if;
                    if not exp_illegal then -- other outputs are don't-care for illegal instructions
                        if alu_control /= exp_ctl or AluSrc /= exp_alusrc then
                            errors := errors + 1;
                            report "alu_control/AluSrc wrong: op=" & integer'image(op) & " f3=" & integer'image(f3) &
                                   " f7=" & integer'image(f7) severity error;
                        end if;
                        if exp_branch = '1' and ImmSrc /= "10" then
                            errors := errors + 1;
                            report "ImmSrc must be B-type for branches" severity error;
                        end if;
                        if exp_branch = '0' and ImmSrc /= "00" then
                            errors := errors + 1;
                            report "ImmSrc must be I-type for ALU instructions" severity error;
                        end if;
                    end if;
                end loop;
            end loop;
        end loop;
        assert errors = 0 report integer'image(errors) & " mismatches" severity failure;
        report "controlunit_tb done, all 131072 combinations OK";
        wait;
    end process;
end architecture;
