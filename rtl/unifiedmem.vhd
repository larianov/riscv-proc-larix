library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;


entity unifiedmem is
    generic(
        file_S : string := "hex.hex";
        size : positive := 256
    );
    port(
        PC : in std_logic_vector(31 downto 0);
        instr_out : out std_logic_vector(31 downto 0);
        
        clk : in std_logic;
        address : in std_logic_vector(31 downto 0);
        wD : in std_logic_vector(31 downto 0);
        WE : in std_logic_vector(3 downto 0);
        RD : out std_logic_vector(31 downto 0)
    );
end entity unifiedmem;


architecture RTL of unifiedmem is
    type mem_arr is array(0 to size-1) of std_logic_vector(31 downto 0);
    signal PC_4 : integer := 0;
    signal index : integer range 0 to size-1 := 0;
    impure function ParseFile(file_S : string)
       return mem_arr is
        variable loc_arr : mem_arr := (others => (others => '0'));
        variable ln: line;
        file f : text open READ_MODE is file_S;
        variable line_c : integer := 0;
    begin
        for i in 0 to size-1 loop
            if endfile(f) then
                exit;
            end if;
            readline(f, ln);
            if ln'length /= 0 then
                hread(ln, loc_arr(line_c));
                line_c := line_c+1;
            end if;
        end loop;
        file_close(f);
        report "ROM loaded, words = " & integer'image(line_c);
        return loc_arr;
    end function ParseFile;

    signal uni_mem : mem_arr := ParseFile(file_S);
begin
    PC_4 <= TO_INTEGER(SHIFT_RIGHT((UNSIGNED(PC)), 2)) mod size;
    process(PC_4, uni_mem)
    begin
        instr_out <= uni_mem(PC_4);
    end process;
    process(clk)
        variable temp_we : std_logic_vector(31 downto 0) := (others => '0');    
    begin
        if rising_edge(clk) then
            if we /= "0000" then
                temp_we := uni_mem(index);
                if WE(0) = '1' then
                    temp_we(7 downto 0) := wD(7 downto 0);
                end if;
                if WE(1) = '1' then
                    temp_we(15 downto 8) := wD(15 downto 8);
                end if;       
                if WE(2) = '1' then
                    temp_we(23 downto 16) := wD(23 downto 16);
                end if;
                if WE(3) = '1' then
                    temp_we(31 downto 24) := wD(31 downto 24);
                end if;
                uni_mem(index) <= temp_we;
            end if;                
        end if;
    end process;
    index <= TO_INTEGER(SHIFT_RIGHT((UNSIGNED(address)), 2)) mod size;
    RD <= uni_mem(index);
end architecture RTL;
