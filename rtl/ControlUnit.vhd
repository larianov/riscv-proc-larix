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
        if opcode = "0110011" then
            BSrc <= '0';
            if funct3 = "000" then
                if funct7 = "0000000" then
                    RegWrite <= '1';
                    alu_control <= "0000";
                elsif funct7 = "0100000" then
                    RegWrite <= '1';
                    alu_control <= "1000";
                else 
                    Illegal <= '1';
                end if;
            elsif funct3 = "001" then
                if funct7 = "0000000" then
                    alu_control <= "0001";
                    RegWrite <= '1';
                else
                    Illegal <= '1';
                end if;
                
            elsif funct3 = "010" then
                if funct7 = "0000000" then
                    alu_control <= "0010";
                    RegWrite <= '1';
                else
                    Illegal <= '1';
                end if;
            elsif funct3 = "011" then
                if funct7 = "0000000" then
                    alu_control <= "0011";
                    RegWrite <= '1';
                else
                    Illegal <= '1';
                end if;
            elsif funct3 = "100" then
                if funct7 = "0000000" then
                    alu_control <= "0100";
                    RegWrite <= '1';
                else
                    Illegal <= '1';
                end if;
            elsif funct3 = "101" then
                if funct7 = "0000000" then
                    alu_control <= "0101";
                    RegWrite <= '1';
                elsif funct7 = "0100000" then
                    alu_control <= "1101";
                    RegWrite <= '1';
                else
                    Illegal <= '1';
                end if;
            elsif funct3 = "110" then
                if funct7 = "0000000" then
                    alu_control <= "0110";
                    RegWrite <= '1';
                else
                    Illegal <= '1';
                end if;
            elsif funct3 = "111" then
                if funct7 = "0000000" then
                    alu_control <= "0111";
                    RegWrite <= '1';
                else
                    Illegal <= '1';
                end if;
            else
                Illegal <= '1';
            end if;
        elsif opcode = "0010011" then
            BSrc <= '1';
            if funct3 = "000" then
                alu_control <= "0000";
                RegWrite <= '1';
            elsif funct3 = "001" then
                if funct7 = "0000000" then
                    alu_control <= "0001";
                    RegWrite <= '1';
                else
                    Illegal <= '1';
                end if;
            elsif funct3 = "010" then
                alu_control <= "0010";
                RegWrite <= '1';
            elsif funct3 = "011" then
                RegWrite <= '1';
                alu_control <= "0011";
            elsif funct3 = "100" then
                RegWrite <= '1';
                alu_control <= "0100";
            elsif funct3 = "101" then
                if funct7 = "0000000" then
                    alu_control <= "0101";
                    RegWrite <= '1';
                elsif funct7 = "0100000" then
                    alu_control <= "1101";
                    RegWrite <= '1';
                else 
                    Illegal <= '1';
                end if;
            elsif funct3 = "110" then
                RegWrite <= '1';
                alu_control <= "0110";
            elsif funct3 = "111" then
                RegWrite <= '1';
                alu_control <= "0111";
            else
                Illegal <= '1';
                end if;
        elsif opcode = "1100011" then
            if funct3 = "000" or funct3 = "001" then
                Branch <= '1';
                ImmSrc <= "010";
                alu_control <= "1000";
            elsif funct3 = "100" or funct3 = "101" then
                Branch <= '1';
                ImmSrc <= "010";
                alu_control <= "0010";
            elsif funct3 = "110" or funct3 = "111" then
                Branch <= '1';
                ImmSrc <= "010";
                alu_control <= "0011";
            else
                Illegal <= '1';
            end if;
        elsif opcode = "0100011" then
            if funct3(2) /= '1'  and funct3 /= "011" then
                Mem_Write <= '1';
                alu_control <= "0000";
                BSrc <= '1';
                ImmSrc <= "001";
            else
                Illegal <= '1';
            end if;
        elsif opcode = "0000011" then
            if funct3 = "000" or funct3 = "001" or funct3 = "100" or funct3 = "101" or funct3 = "010" then
                RegWrite <= '1';
                ImmSrc <= "000";
                BSrc <= '1';
                alu_control <= "0000";
                Result_Src <= "01";
            else
                Illegal <= '1';
            end if;
        elsif opcode = "1101111" then
            Jump <= '1';
            Result_Src <= "10";
            RegWrite <= '1';
            ImmSrc <= "011";
        elsif opcode = "1100111" then
            if funct3 = "000" then
                JalrReg <= '1';
                Jump <= '1';
                Result_Src <= "10";
                RegWrite <= '1';
            else
                Illegal <= '1';
            end if;
        elsif opcode = "0110111" or opcode = "0010111" then
            BSrc <= '1';
            ImmSrc <= "100";
            RegWrite <= '1';
            if opcode = "0110111" then
                ASrc <= "10";
            else
                ASrc <= "01";
            end if;
        elsif opcode = "1110011" then
            if funct3 = "000" and funct7 = "0011000" then
                MRET <= '1';
            else
                RegWrite <= '1';
                Result_Src <= "11";
                if funct3 = "001" then
                    CSRwrite <= '1';
                    CSRop <= "01";
                elsif funct3 = "010" then
                    CSRop <= "10";
                    if TO_INTEGER(UNSIGNED(rs1)) /= 0 then
                        CSRwrite <= '1';
                    end if;                    
                elsif funct3 = "011" then
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
