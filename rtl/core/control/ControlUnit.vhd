library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ControlUnit is
    port(
        opcode : in std_logic_vector(6 downto 0);
        funct3 : in std_logic_vector(2 downto 0);
        funct7 : in std_logic_vector(6 downto 0);
        RegWrite : out std_logic;
        ASrc : out std_logic_vector(1 downto 0);
        BSrc : out std_logic;
        Illegal : out STD_LOGIC;
        Branch : out STD_LOGIC;
        ImmSrc : out std_logic_vector(2 downto 0);
        Mem_Write : out STD_LOGIC;
        Result_Src : out std_logic_vector(1 downto 0) := "01";
        alu_control : out std_logic_vector(3 downto 0);
        rs1 : in STD_LOGIC_VECTOR(4 downto 0);
        CSRwrite : out std_logic;
        CSRop : out std_logic_vector(1 downto 0);
        MRET : out std_logic;
        JalrReg : out std_logic;
        Jump : out std_logic
    );
end entity ControlUnit;


architecture RTL of ControlUnit is
begin
    asunit : process(opcode, funct3, funct7, rs1) is
    begin
        Illegal <= '0';
        RegWrite <= '0';
        JalrReg <= '0';
        ASrc <= (others => '0');
        MRET <= '0';
        BSrc <= '0';
        Jump <= '0';
        Branch <= '0';
        ImmSrc <= "000";
        Mem_Write <= '0';
        Result_Src <= (others => '0');
        alu_control <= (others => '0');
        CSRwrite <= '0';
        CSRop <= (others => '0');
        if opcode = "0110011" then -- R
            BSrc <= '0';
            if funct3 = "000" then -- ADD / SUB
                if funct7 = "0000000" then
                    RegWrite <= '1';
                    alu_control <= "0000"; -- ADD
                elsif funct7 = "0100000" then
                    RegWrite <= '1';
                    alu_control <= "1000"; -- SUB
                else 
                    Illegal <= '1';
                end if;
            elsif funct3 = "001" then -- SLL
                if funct7 = "0000000" then
                    alu_control <= "0001"; -- SLL
                    RegWrite <= '1';
                else
                    Illegal <= '1';
                end if;
                
            elsif funct3 = "010" then -- SLT
                if funct7 = "0000000" then
                    alu_control <= "0010"; -- SLT
                    RegWrite <= '1';
                else
                    Illegal <= '1';
                end if;
            elsif funct3 = "011" then -- SLTU
                if funct7 = "0000000" then
                    alu_control <= "0011"; -- SLTU
                    RegWrite <= '1';
                else
                    Illegal <= '1';
                end if;
            elsif funct3 = "100" then -- XOR
                if funct7 = "0000000" then
                    alu_control <= "0100"; -- XOR
                    RegWrite <= '1';
                else
                    Illegal <= '1';
                end if;
            elsif funct3 = "101" then -- SRL / SRA
                if funct7 = "0000000" then
                    alu_control <= "0101"; -- SRL
                    RegWrite <= '1';
                elsif funct7 = "0100000" then
                    alu_control <= "1101"; -- SRA
                    RegWrite <= '1';
                else
                    Illegal <= '1';
                end if;
            elsif funct3 = "110" then -- OR
                if funct7 = "0000000" then
                    alu_control <= "0110"; -- OR
                    RegWrite <= '1';
                else
                    Illegal <= '1';
                end if;
            elsif funct3 = "111" then -- AND
                if funct7 = "0000000" then
                    alu_control <= "0111"; -- AND
                    RegWrite <= '1';
                else
                    Illegal <= '1';
                end if;
            else
                Illegal <= '1';
            end if;
        elsif opcode = "0010011" then -- I
            BSrc <= '1';
            if funct3 = "000" then -- ADDI
                alu_control <= "0000"; -- ADD
                RegWrite <= '1';
            elsif funct3 = "001" then -- SLLI
                if funct7 = "0000000" then
                    alu_control <= "0001"; -- SLL
                    RegWrite <= '1';
                else
                    Illegal <= '1';
                end if;
            elsif funct3 = "010" then -- SLTI
                alu_control <= "0010"; -- SLT
                RegWrite <= '1';
            elsif funct3 = "011" then -- SLTIU
                RegWrite <= '1';
                alu_control <= "0011"; -- SLTU
            elsif funct3 = "100" then -- XORI
                RegWrite <= '1';
                alu_control <= "0100"; -- XOR
            elsif funct3 = "101" then -- SRLI / SRAI
                if funct7 = "0000000" then
                    alu_control <= "0101"; -- SRL
                    RegWrite <= '1';
                elsif funct7 = "0100000" then
                    alu_control <= "1101"; -- SRA
                    RegWrite <= '1';
                else 
                    Illegal <= '1';
                end if;
            elsif funct3 = "110" then -- ORI
                RegWrite <= '1';
                alu_control <= "0110"; -- OR
            elsif funct3 = "111" then -- ANDI
                RegWrite <= '1';
                alu_control <= "0111"; -- AND
            else
                Illegal <= '1';
                end if;
        elsif opcode = "1100011" then -- B
            if funct3 = "000" or funct3 = "001" then -- BEQ / BNE 
                Branch <= '1';
                ImmSrc <= "010"; -- B-imm
                alu_control <= "1000";
            elsif funct3 = "100" or funct3 = "101" then -- BLT / BGE (SLT)
                Branch <= '1';
                ImmSrc <= "010"; -- B-imm
                alu_control <= "0010";
            elsif funct3 = "110" or funct3 = "111" then -- BLTU / BGEU (SLTU)
                Branch <= '1';
                ImmSrc <= "010"; -- B-imm
                alu_control <= "0011";
            else
                Illegal <= '1';
            end if;
        elsif opcode = "0100011" then -- S
            if funct3(2) /= '1'  and funct3 /= "011" then -- SB / SH / SW
                Mem_Write <= '1';
                alu_control <= "0000";
                BSrc <= '1';
                ImmSrc <= "001"; -- S-imm
            else
                Illegal <= '1';
            end if;
        elsif opcode = "0000011" then -- loads
            if funct3 = "000" or funct3 = "001" or funct3 = "100" or funct3 = "101" or funct3 = "010" then -- LB / LH / LBU / LHU / LW
                RegWrite <= '1';
                ImmSrc <= "000"; -- I-imm
                BSrc <= '1';
                alu_control <= "0000";
                Result_Src <= "01"; -- rd
            else
                Illegal <= '1';
            end if;
        elsif opcode = "1101111" then -- JAL
            Jump <= '1';
            Result_Src <= "10"; -- rd = PC+4
            RegWrite <= '1';
            ImmSrc <= "011"; -- J-imm
        elsif opcode = "1100111" then -- JALR
            if funct3 = "000" then
                JalrReg <= '1';
                Jump <= '1';
                Result_Src <= "10"; -- rd = PC+4
                RegWrite <= '1';
            else
                Illegal <= '1';
            end if;
        elsif opcode = "0110111" or opcode = "0010111" then -- LUI / AUIPC
            BSrc <= '1';
            ImmSrc <= "100"; -- U-imm
            RegWrite <= '1';
            if opcode = "0110111" then
                ASrc <= "10"; -- LUI: A = 0
            else
                ASrc <= "01"; -- AUIPC: A = PC
            end if;
        elsif opcode = "1110011" then -- SYSTEM (CSR, MRET)
            if funct3 = "000" and funct7 = "0011000" then -- MRET
                MRET <= '1';
            else
                RegWrite <= '1';
                Result_Src <= "11";
                if funct3 = "001" then -- CSRRW
                    CSRwrite <= '1';
                    CSRop <= "01";
                elsif funct3 = "010" then -- CSRRS 
                    CSRop <= "10";
                    if TO_INTEGER(UNSIGNED(rs1)) /= 0 then
                        CSRwrite <= '1';
                    end if;                    
                elsif funct3 = "011" then -- CSRRC 
                    if TO_INTEGER(UNSIGNED(rs1)) /= 0 then
                        CSRwrite <= '1';
                    end if;
                    CSRop <= "11";
                else
                    RegWrite <= '0';
                    Result_Src <= (others => '0');
                    Illegal <= '1';
                end if;
            end if;            
        else
            Illegal <= '1';
        end if;
    end process asunit;
end architecture RTL;
