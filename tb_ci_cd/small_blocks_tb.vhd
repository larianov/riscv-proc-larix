library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- pc, PCPlus4, PCTarget, Pc_mux, alu_mux, SrcAMux
entity small_blocks_tb is
end entity;

architecture sim of small_blocks_tb is
    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal pc_next, pc_reg : std_logic_vector(31 downto 0) := (others => '0');

    signal a, b, plus4, target, mux_pc, mux_alu : std_logic_vector(31 downto 0) := (others => '0');
    signal sel : std_logic := '0';
    signal asel : std_logic_vector(1 downto 0) := "00";
    signal mux_a : std_logic_vector(31 downto 0);
begin
    clk <= not clk after 5 ns;

    u_pc : entity work.pc port map(clk => clk, rst => rst, PCNext => pc_next, PC_REG => pc_reg);
    u_p4 : entity work.PCPlus4 port map(PC => a, PC_O => plus4);
    u_tg : entity work.PCTarget port map(PC => a, offset => b, PCOFFSET => target);
    u_pm : entity work.Pc_mux port map(PCPlus4 => a, PCL => b, S => sel, PCOUT => mux_pc);
    u_am : entity work.alu_mux port map(rd2 => a, imm => b, S => sel, muxout => mux_alu);
    u_sa : entity work.SrcAMux port map(SrcA => a, PC => b, S => asel, Y => mux_a);

    process
    begin
        -- pc: reset to 0, then loads PCNext every clock, reset wins
        pc_next <= x"12345678";
        wait until falling_edge(clk);
        assert pc_reg = x"00000000" report "pc must be 0 during reset" severity error;
        rst <= '0';
        wait until falling_edge(clk);
        assert pc_reg = x"12345678" report "pc must load PCNext" severity error;
        pc_next <= x"0000ABCD";
        wait until falling_edge(clk);
        assert pc_reg = x"0000ABCD" report "pc must follow PCNext" severity error;
        rst <= '1';
        wait until falling_edge(clk);
        assert pc_reg = x"00000000" report "reset must clear pc" severity error;
        rst <= '0';

        -- PCPlus4
        a <= x"00000000"; wait for 1 ns; assert plus4 = x"00000004" report "0+4" severity error;
        a <= x"000000FC"; wait for 1 ns; assert plus4 = x"00000100" report "carry" severity error;
        a <= x"FFFFFFFC"; wait for 1 ns; assert plus4 = x"00000000" report "wraparound" severity error;

        -- PCTarget: PC + offset, offset may be negative
        a <= x"00000020"; b <= x"00000010"; wait for 1 ns;
        assert target = x"00000030" report "forward target" severity error;
        b <= x"FFFFFFF0"; wait for 1 ns;
        assert target = x"00000010" report "backward target" severity error;
        a <= x"00000000"; b <= x"00000000"; wait for 1 ns;
        assert target = x"00000000" report "zero target" severity error;

        -- muxes
        a <= x"AAAAAAAA"; b <= x"55555555";
        sel <= '0'; wait for 1 ns;
        assert mux_pc = a and mux_alu = a report "mux S=0 must pick first input" severity error;
        sel <= '1'; wait for 1 ns;
        assert mux_pc = b and mux_alu = b report "mux S=1 must pick second input" severity error;

        -- SrcAMux: 00 -> rs1, 01 -> PC, 10 -> zero (for lui)
        asel <= "00"; wait for 1 ns;
        assert mux_a = a report "SrcAMux 00 must pick SrcA (rs1)" severity error;
        asel <= "01"; wait for 1 ns;
        assert mux_a = b report "SrcAMux 01 must pick PC" severity error;
        asel <= "10"; wait for 1 ns;
        assert mux_a = x"00000000" report "SrcAMux 10 must give zero" severity error;

        report "small_blocks_tb done";
        std.env.finish;
    end process;
end architecture;
