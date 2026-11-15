library ieee;
use ieee.std_logic_1164.all;

entity top_calc_tb is
end entity top_calc_tb;

architecture tb of top_calc_tb is
    constant CLK_CONST : time := 10 ns;
    signal clk       : std_logic := '0';
    signal instr_inp : std_logic_vector(31 downto 0) := (others => '0');
    signal Illegal   : std_logic;
    signal alu_out   : std_logic_vector(31 downto 0);
begin
    clk <= not clk after CLK_CONST / 2;

    dut : entity work.top_calc
        port map(clk => clk, instr_inp => instr_inp,
                 Illegal => Illegal, alu_out => alu_out);

    process
        procedure exec(i : std_logic_vector(31 downto 0)) is
        begin
            instr_inp <= i;
            wait until rising_edge(clk);
            wait for 1 ns;
        end procedure;

        procedure check(exp : std_logic_vector(31 downto 0); name : string) is
        begin
            if alu_out /= exp or Illegal /= '0' then
                report name & " error" severity error;
            end if;
        end procedure;
    begin
        exec(x"00500093");  -- ADDI x1, x0, 5
        exec(x"00300113");  -- ADDI x2, x0, 3

        exec(x"00208033");  
        check(x"00000008", "ADD");  -- 5 + 3

        exec(x"40208033");
        check(x"00000002", "SUB");  -- 5 - 3


        exec(x"0020F033");
        check(x"00000001", "AND");  -- 5 and 3


        exec(x"0020E033");  
        check(x"00000007", "OR");   -- 5 or 3


        exec(x"0020C033"); 
        check(x"00000006", "XOR");  -- 5 xor 3

        exec(x"002081B3"); 
         check(x"00000008", "ADD  x3  = x1 + x2");       -- 5 + 3 = 8
        exec(x"40118233"); 
         check(x"00000003", "SUB  x4  = x3 - x1");       -- 8 - 5 = 3
        exec(x"0021C2B3"); 
         check(x"0000000B", "XOR  x5  = x3 ^ x2");       -- 8 xor 3 = 11
        exec(x"0012E333"); 
         check(x"0000000F", "OR   x6  = x5 | x1");       -- 11 or 5 = 15
        exec(x"003373B3"); 
         check(x"00000008", "AND  x7  = x6 & x3");       -- 15 and 8 = 8
        exec(x"40110433"); 
         check(x"FFFFFFFE", "SUB  x8  = x2 - x1");       -- 3 - 5 = -2
        exec(x"006404B3"); 
         check(x"0000000D", "ADD  x9  = x8 + x6");       -- -2 + 15 = 13
        exec(x"00242533"); 
         check(x"00000001", "SLT  x10 = x8 < x2");       -- -2 < 3 = 1
        exec(x"002435B3"); 
         check(x"00000000", "SLTU x11 = x8 < x2");       -- 0xFFFFFFFE < 3 = 0
        exec(x"00211633"); 
         check(x"00000018", "SLL  x12 = x2 << x2");      -- 3 << 3 = 24
        exec(x"002356B3"); 
         check(x"00000001", "SRL  x13 = x6 >> x2");      -- 15 >> 3 = 1
        exec(x"40145733"); 
         check(x"FFFFFFFF", "SRA  x14 = x8 >>> x1");     -- -2 >>> 5 = -1
        exec(x"FFC60793"); 
         check(x"00000014", "ADDI x15 = x12 - 4");       -- 24 - 4 = 20
        exec(x"00737813"); 
         check(x"00000007", "ANDI x16 = x6 & 7");        -- 15 and 7 = 7
        exec(x"0FF3C893");
          check(x"000000F7", "XORI x17 = x7 ^ 255");      -- 8 xor 255 = 247
        exec(x"00300933");
          check(x"00000008", "ADD  x18 = x0 + x3");       -- x0 = 0, 8

        exec(x"00108013"); 
         check(x"00000006", "ADDI x0  = x1 + 1");        
        exec(x"000009B3"); 
         check(x"00000000", "ADD  x19 = x0 + x0");   

        exec(x"0000007F");                              
        if Illegal /= '1' then
            report "Illegal not set" severity error;
        end if;

        std.env.stop;
        wait;
    end process;
end architecture tb;