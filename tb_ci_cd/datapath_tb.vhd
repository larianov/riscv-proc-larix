library ieee;
use ieee.std_logic_1164.all;

-- Control signals are driven by hand, so only the datapath is tested.
entity datapath_tb is
end entity;

architecture sim of datapath_tb is
    signal clk         : std_logic := '0';
    signal rst         : std_logic := '1';
    signal PC_Src      : std_logic := '0';
    signal ImmSrc      : std_logic_vector(2 downto 0) := "000";
    signal instr       : std_logic_vector(31 downto 0) := (others => '0');
    signal AluSrcB     : std_logic := '0';
    signal AluSrcA     : std_logic_vector(1 downto 0) := "00";
    signal alu_control : std_logic_vector(3 downto 0) := "0000";
    signal RegWrite    : std_logic := '0';
    signal Zero        : std_logic;
    signal JalrReg     : std_logic := '0';
    signal REZ, PC, WD : std_logic_vector(31 downto 0);
begin
    clk <= not clk after 5 ns;

    dut : entity work.DataPath
        port map(clk => clk, rst => rst, PC_Src => PC_Src, ImmSrc => ImmSrc, instr => instr,
                 AluSrcB => AluSrcB, AluSRCA => AluSrcA, alu_control => alu_control, RegWrite => RegWrite,
                 Zero => Zero, REZ => REZ, PC => PC,
                 ReadData => x"00000000", Result_Src => "00", WD => WD, JalrReg => JalrReg);

    process
    begin
        wait until falling_edge(clk);
        wait until falling_edge(clk);

        -- release reset together with the first instruction: addi x1, x0, 5
        rst <= '0';
        instr <= x"00500093"; AluSrcB <= '1'; RegWrite <= '1';
        wait until falling_edge(clk);
        assert REZ = x"00000005" report "addi x1 result wrong" severity error;
        assert PC = x"00001004" report "PC should be 0x1004 (reset vector 0x1000 + 4)" severity error;

        -- addi x2, x0, 7
        instr <= x"00700113";
        wait until falling_edge(clk);
        assert PC = x"00001008" report "PC should be 0x1008" severity error;

        -- add x3, x1, x2  -> 12
        instr <= x"002081B3"; AluSrcB <= '0';
        wait for 1 ns;
        assert REZ = x"0000000C" report "add result wrong" severity error;
        assert Zero = '0' report "Zero should be 0" severity error;
        wait until falling_edge(clk);

        -- sub x4, x1, x1  -> 0, Zero = 1
        instr <= x"40108233"; alu_control <= "1000"; RegWrite <= '0';
        wait for 1 ns;
        assert REZ = x"00000000" and Zero = '1' report "sub / Zero wrong" severity error;

        -- taken branch: PC (now 0x100C) + offset 8 = 0x1014
        instr <= x"00008463"; ImmSrc <= "010"; PC_Src <= '1';  -- beq x1, x0, +8
        wait until falling_edge(clk);
        assert PC = x"00001014" report "branch target wrong" severity error;

        -- jal-style jump: PC (now 0x1014) + offset 8 = 0x101C
        instr <= x"008000EF"; ImmSrc <= "011"; PC_Src <= '1';
        wait until falling_edge(clk);
        assert PC = x"0000101C" report "jal target wrong" severity error;

        -- jalr-style jump: target = (x1 + imm) with bit 0 cleared. x1 = 5, imm = 4 -> 9 -> 8
        instr <= x"00408167"; ImmSrc <= "000"; JalrReg <= '1'; AluSrcB <= '1';
        wait until falling_edge(clk);
        assert PC = x"00000008" report "jalr target wrong (bit 0 must be cleared)" severity error;

        -- lui x5, 0xABCDE : SrcA = 0, SrcB = U-imm -> 0xABCDE000, written to x5
        instr <= x"ABCDE2B7"; ImmSrc <= "100"; AluSrcA <= "10"; AluSrcB <= '1'; alu_control <= "0000";
        JalrReg <= '0'; PC_Src <= '0'; RegWrite <= '1';
        wait for 1 ns;
        assert REZ = x"ABCDE000" report "lui result wrong: " & to_hstring(REZ) severity error;
        wait until falling_edge(clk);
        assert PC = x"0000000C" report "lui must just advance PC by 4" severity error;

        -- auipc x6, 0x00010 at PC = 0xC : PC + 0x10000 = 0x1000C
        instr <= x"00010317"; AluSrcA <= "01";
        wait for 1 ns;
        assert REZ = x"0001000C" report "auipc result wrong: " & to_hstring(REZ) severity error;
        wait until falling_edge(clk);

        -- auipc with negative upper imm at PC = 0x10: 0x10 + 0xFFFFF000 = 0xFFFFF010
        instr <= x"FFFFF397"; -- auipc x7, 0xFFFFF
        wait for 1 ns;
        assert REZ = x"FFFFF010" report "auipc negative result wrong: " & to_hstring(REZ) severity error;
        wait until falling_edge(clk);

        -- read back x5 (lui) and x6 (auipc) through the register file: add x8, x5, x0 ; add x9, x6, x0
        instr <= x"00028433"; ImmSrc <= "000"; AluSrcA <= "00"; AluSrcB <= '0'; RegWrite <= '0';
        wait for 1 ns;
        assert REZ = x"ABCDE000" report "lui did not write rd: x5 = " & to_hstring(REZ) severity error;
        instr <= x"000304B3";
        wait for 1 ns;
        assert REZ = x"0001000C" report "auipc did not write rd: x6 = " & to_hstring(REZ) severity error;
        instr <= x"00038533"; -- add x10, x7, x0
        wait for 1 ns;
        assert REZ = x"FFFFF010" report "auipc did not write rd: x7 = " & to_hstring(REZ) severity error;

        report "datapath_tb done";
        std.env.finish;
    end process;
end architecture;
