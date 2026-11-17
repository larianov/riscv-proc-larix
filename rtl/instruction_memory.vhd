library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;


entity instruction_memory is
    generic(
        file_S : string := "hex.hex";
        size : positive := 32
    );
    port(
        PC : in std_logic_vector(31 downto 0);
        instr_out : out std_logic_vector(31 downto 0)
    );
end entity instruction_memory;


architecture RTL of instruction_memory is
    type instr_rom_t is array(0 to size-1) of std_logic_vector(31 downto 0);
    signal PC_4 : integer := 0;
    impure function ParseFile(file_S : string)
       return instr_rom_t is
        variable loc_arr : instr_rom_t := (others => x"00000013");
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

    constant rom_mem : instr_rom_t := ParseFile(file_S);
begin
    PC_4 <= TO_INTEGER(SHIFT_RIGHT(UNSIGNED(PC), 2));
    process(PC_4)
    begin
        if PC_4 < size then
            instr_out <= rom_mem(PC_4);
        else
            instr_out <= x"00000013";
        end if;
    end process;
end architecture RTL;
