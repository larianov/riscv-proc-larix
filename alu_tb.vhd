library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity alu_tb is
end entity alu_tb;

architecture sim of alu_tb is
    signal A_input      : std_logic_vector(31 downto 0) := (others => '0');
    signal B_input      : std_logic_vector(31 downto 0) := (others => '0');
    signal res_out      : std_logic_vector(31 downto 0) := (others => '0');
    signal temp_res_out : integer                       := 0;
    signal Z            : std_logic                     := '1';
    signal alu_control  : std_logic_vector(3 downto 0)  := (others => '0');
begin
    alu_inst : entity work.alu
        port map(
            A_input     => A_input,
            B_input     => B_input,
            alu_control => alu_control,
            res_out     => res_out,
            Z           => Z
        );

    process
    begin
        wait on temp_res_out, Z;
        wait for 1 ns;
        if temp_res_out = 0 then
            if Z /= '1' then
                report "ZERO S DOESNT WORK: res=0, Z=" & std_logic'image(Z) severity error;
            end if;
        else
            if Z /= '0' then
                report "ZERO S DOESNT WORK: res=" & integer'image(temp_res_out) & ", Z=" & std_logic'image(Z) severity error;
            end if;
        end if;
    end process;
    process
        variable expected  : integer  := 0;
        variable err_count : integer  := 0;
        variable seed1     : positive := 42;
        variable seed2     : positive := 7;
        variable i, j      : integer;

        impure function rand_int(min_v, max_v : integer) return integer is
            variable r : real;
        begin
            uniform(seed1, seed2, r);
            return min_v + integer(floor(r * real(max_v - min_v + 1)));
        end function;

    begin
        for k in 0 to 2 ** 16 loop
            i       := rand_int(0, 2 ** 30);
            j       := rand_int(0, 2 ** 30);
            A_input <= std_logic_vector(to_unsigned(i, 32));
            B_input <= std_logic_vector(to_unsigned(j, 32));

            wait for 5 ns;
            --sum
            expected    := i + j;
            alu_control <= "0000";
            wait for 5 ns;
            if temp_res_out /= expected then
                report "Error adding: " & integer'image(i) & " + " & integer'image(j) & " = " & integer'image(temp_res_out) severity error;
                err_count := err_count + 1;
            end if;

            --minus
            alu_control <= "1000";
            expected    := i - j;
            wait for 5 ns;
            if temp_res_out /= expected then
                report "Error sub: " & integer'image(i) & " - " & integer'image(j) & " = " & integer'image(temp_res_out) severity error;
                err_count := err_count + 1;
            end if;

            --and 
            alu_control <= "0111";
            expected    := to_integer(UNSIGNED(A_input and B_input));
            wait for 5 ns;
            if temp_res_out /= expected then
                report "Error and: " & integer'image(i) & " and " & integer'image(j) & " = " & integer'image(temp_res_out) severity error;
                err_count := err_count + 1;
            end if;

            --or
            alu_control <= "0110";
            expected    := to_integer(UNSIGNED(A_input or B_input));
            wait for 5 ns;
            if temp_res_out /= expected then
                report "Error or: " & integer'image(i) & " or " & integer'image(j) & " = " & integer'image(temp_res_out) severity error;
                err_count := err_count + 1;
            end if;

            --xor
            alu_control <= "0100";
            expected    := to_integer(UNSIGNED(A_input xor B_input));
            wait for 5 ns;
            if temp_res_out /= expected then
                report "Error xor: " & integer'image(i) & " xor " & integer'image(j) & " = " & integer'image(temp_res_out) severity error;
                err_count := err_count + 1;
            end if;

            --bit shift 

            if j < 16 then
                alu_control <= "0001";
                expected    := to_integer(shift_left(to_unsigned(i, 32), j));
                wait for 5 ns;
                if temp_res_out /= expected then
                    report "Error shift_left: " & integer'image(i) & " shift_left " & integer'image(j) & " = " & integer'image(temp_res_out) severity error;
                    err_count := err_count + 1;
                end if;
            end if;

            if j < 32 then
                alu_control <= "0101";
                expected    := to_integer(SHIFT_RIGHT(to_UNSIGNED(i, 32), j));
                wait for 5 ns;
                if temp_res_out /= expected then
                    report "Error shift_RIGHTt: " & integer'image(i) & " shift_right " & integer'image(j) & " = " & integer'image(temp_res_out) severity error;
                    err_count := err_count + 1;
                end if;

                alu_control <= "1101";
                expected    := to_integer(SHIFT_RIGHT(to_SIGNED(i, 32), j));
                wait for 5 ns;
                if temp_res_out /= expected then
                    report "Error shift_RIGHTt_Arithm: " & integer'image(i) & " shift_right_arithm" & integer'image(j) & " = " & integer'image(temp_res_out) severity error;
                    err_count := err_count + 1;
                end if;
            end if;

            --bool 
            if i < j then
                expected := 1;
            else
                expected := 0;
            end if;

            alu_control <= "0010";
            wait for 10 ns;
            if temp_res_out /= expected then
                report "Error bool signed: " & integer'image(i) & " " & integer'image(j) & " = " & integer'image(temp_res_out) severity error;
                err_count := err_count + 1;
            end if;

            alu_control <= "0011";
            wait for 5 ns;
            if temp_res_out /= expected then
                report "Error bool unsigned: " & integer'image(i) & " " & integer'image(j) & " = " & integer'image(temp_res_out) severity error;
                err_count := err_count + 1;
            end if;
        end loop;
        report "All tests finished, errors: " & integer'image(err_count) severity note;
        std.env.stop;
        wait;
    end process;
    temp_res_out <= TO_INTEGER(SIGNED(res_out));
end architecture sim;
