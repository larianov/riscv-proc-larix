library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity riscvregfile_tb is
end entity riscvregfile_tb;

architecture tb of riscvregfile_tb is
    constant CLK_CONST : time := 10 ns;
    
    signal clk : std_logic := '0';

    signal read_out_first : std_logic_vector(31 downto 0);
    signal read_idx_first : integer range 0 to 31;

    signal read_out_second : std_logic_vector(31 downto 0);        
    signal read_idx_second : integer range 0 to 31;
    
    signal write_en : std_logic;
    signal write_In : std_logic_vector(31 downto 0);
    signal write_idx : integer range 0 to 31 ;
begin
    clk <= not clk after CLK_CONST /2;
    dut : entity work.riscvregfile
        port map(
            clk             => clk,
            read_out_first  => read_out_first,
            read_idx_first  => read_idx_first,
            read_out_second => read_out_second,
            read_idx_second => read_idx_second,
            write_en        => write_en,
            write_In        => write_In,
            write_idx       => write_idx
        );
        process 
            variable expected : std_logic_vector(31 downto 0);  
        begin
        for i in 0 to 31 loop
            write_en <= '1';
            write_idx <= i;
            if i = 0 then 
                write_In <= (others => '1');
            else
                write_In <= STD_LOGIC_VECTOR(to_unsigned(i*7, write_In'length));
            end if;
            wait until rising_edge(clk);
            wait for 1 ns;
        end loop;
        write_en <= '0';
        for i in 0 to 31 loop
            read_idx_first <= i;
            read_idx_second <= i;
            expected := STD_LOGIC_VECTOR(TO_UNSIGNED(i*7, read_out_first'length));
            wait until rising_edge(clk);
            wait for 1 ns;
            if i = 0 then 
                if read_out_first /= "00000000000000000000000000000000" then
                    report "0 hardware rx error" severity ERROR;
                end if;
            elsif read_out_first /= expected or read_out_second /= expected then
                report "expected value: " & integer'image(i*7) & "recieved value " & integer'image(TO_INTEGER(UNSIGNED(read_out_first))) & " and: " & integer'image(TO_INTEGER(UNSIGNED(read_out_second)))  severity error;
            end if;
        end loop;
        std.env.stop;
        wait;
    end process;
end architecture tb;