library ieee;
use ieee.std_logic_1164.all;

-- Control signals are driven by hand, so only the datapath is tested.
entity datapath_tb is
end entity;

architecture sim of datapath_tb is
    signal clk         : std_logic := '0';
    signal rst         : std_logic := '1';
    signal PC_Src      : std_logic := '0';
    signal ImmSrc      : std_logic_vector(1 downto 0) := "00";
    signal instr       : std_logic_vector(31 downto 0) := (others => '0');
    signal AluSrc      : std_logic := '0';
    signal alu_control : std_logic_vector(3 downto 0) := "0000";
    signal RegWrite    : std_logic := '0';
    signal Zero        : std_logic;
    signal REZ, PC     : std_logic_vector(31 downto 0);
begin
    clk <= not clk after 5 ns;

    dut : entity work.DataPath
        port map(clk => clk, rst => rst, PC_Src => PC_Src, ImmSrc => ImmSrc, instr => instr,
                 AluSrc => AluSrc, alu_control => alu_control, RegWrite => RegWrite,
                 Zero => Zero, REZ => REZ, PC => PC);

    process
    begin
        wait until falling_edge(clk);
        wait until falling_edge(clk);

        -- release reset together with the first instruction: addi x1, x0, 5
        rst <= '0';
        instr <= x"00500093"; AluSrc <= '1'; RegWrite <= '1';
        wait until falling_edge(clk);
        assert REZ = x"00000005" report "addi x1 result wrong" severity error;
        assert PC = x"00000004" report "PC should be 4" severity error;

        -- addi x2, x0, 7
        instr <= x"00700113";
        wait until falling_edge(clk);
        assert PC = x"00000008" report "PC should be 8" severity error;

        -- add x3, x1, x2  -> 12
        instr <= x"002081B3"; AluSrc <= '0';
        wait for 1 ns;
        assert REZ = x"0000000C" report "add result wrong" severity error;
        assert Zero = '0' report "Zero should be 0" severity error;
        wait until falling_edge(clk);

        -- sub x4, x1, x1  -> 0, Zero = 1
        instr <= x"40108233"; alu_control <= "1000"; RegWrite <= '0';
        wait for 1 ns;
        assert REZ = x"00000000" and Zero = '1' report "sub / Zero wrong" severity error;

        -- taken branch: PC (now 0xC) + offset 8 = 0x14
        instr <= x"00008463"; ImmSrc <= "10"; PC_Src <= '1';  -- beq x1, x0, +8
        wait until falling_edge(clk);
        assert PC = x"00000014" report "branch target wrong" severity error;

        report "datapath_tb done";
        std.env.finish;
    end process;
end architecture;
