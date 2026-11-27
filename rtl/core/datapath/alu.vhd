library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity alu is
    port(
        A_input     : in  std_logic_vector(31 downto 0);
        B_input     : in  std_logic_vector(31 downto 0);
        alu_control : in  std_logic_vector(3 downto 0);
        res_out     : out std_logic_vector(31 downto 0);
        Z           : out std_logic
    );
end entity alu;

architecture RTL of alu is
    signal res_init : std_logic_vector(31 downto 0) := (others => '0');
    function from_bool_to_logic_vector(fb : boolean; width : positive) return std_logic_vector is
        variable result : std_logic_vector(width - 1 downto 0) := (others => '0');
    begin
        if fb then
            result(0) := '1';
        end if;
        return result;

    end function from_bool_to_logic_vector;

begin
    res_init <= std_logic_vector(unsigned(A_input) + unsigned(B_input)) when alu_control = "0000" else -- ADD
                std_logic_vector(unsigned(A_input) - unsigned(B_input)) when alu_control = "1000" else -- SUB
                A_input and B_input when alu_control = "0111" else -- AND
                A_input or B_input when alu_control = "0110" else -- OR
                A_input xor B_input when alu_control = "0100" else -- XOR
                std_logic_vector(shift_left(unsigned(A_input), to_integer(unsigned((B_input(4 downto 0)))))) when alu_control = "0001" else -- SLL
                from_bool_to_logic_vector((signed(A_input) < signed(B_input)), 32) when alu_control = "0010" else -- SLT (signed)
                from_bool_to_logic_vector((unsigned(A_input) < unsigned(B_input)), 32) when alu_control = "0011" else -- SLTU (unsigned)
                std_logic_vector(shift_right(unsigned(A_input), to_integer(unsigned(B_input(4 downto 0))))) when alu_control = "0101" else -- SRL (logical)
                std_logic_vector(shift_right(signed(A_input), to_integer(unsigned(B_input(4 downto 0))))) when alu_control = "1101" else -- SRA (arithmetic)
                (others => '0');

    res_out <= res_init;
    -- zero flag, used by branches
    Z       <= '1' when res_init = x"00000000" else '0';
end architecture RTL;
