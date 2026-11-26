library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Full cpu: boot.hex (lui x5,0x80000 ; jalr x0,0(x5)) jumps to hex.hex in RAM at 0x8000_0000,
-- which computes fib(20) into a0 (x10) and halts with beq x0,x0,0 at 0x8000_0024.
entity cpu_fib_tb is
end entity;

architecture sim of cpu_fib_tb is
    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal Illegal : std_logic;
    signal rez     : std_logic_vector(31 downto 0);
    signal a0      : std_logic_vector(31 downto 0) := (others => '0');

    constant HALT : std_logic_vector(31 downto 0) := x"80000024";
begin
    dut : entity work.cpu
        port map(clk => clk, rst => rst, Illegal => Illegal, irq => '0', RezOUT => rez);

    clk <= not clk after 5 ns;

    -- track writes to a0 (x10) through the regfile write port
    shadow : process(clk)
        alias we  is <<signal .cpu_fib_tb.dut.core_inst.DataPath_inst.riscvregfile_inst.write_en  : std_logic>>;
        alias idx is <<signal .cpu_fib_tb.dut.core_inst.DataPath_inst.riscvregfile_inst.write_idx : std_logic_vector(4 downto 0)>>;
        alias wd  is <<signal .cpu_fib_tb.dut.core_inst.DataPath_inst.riscvregfile_inst.write_In  : std_logic_vector(31 downto 0)>>;
    begin
        if rising_edge(clk) and rst = '0' and we = '1' and unsigned(idx) = 10 then
            a0 <= wd;
        end if;
    end process;

    process
        alias PC is <<signal .cpu_fib_tb.dut.PC_s : std_logic_vector(31 downto 0)>>;
    begin
        wait for 20 ns;
        rst <= '0';
        for i in 1 to 1000 loop
            wait until falling_edge(clk);
            assert Illegal = '0' report "Illegal at PC " & to_hstring(PC) severity error;
            exit when PC = HALT;
        end loop;
        assert PC = HALT report "did not reach halt, PC = " & to_hstring(PC) severity error;
        assert to_integer(unsigned(a0)) = 6765
            report "fib(20) wrong: a0 = " & integer'image(to_integer(unsigned(a0))) severity error;
        report "cpu_fib_tb done: a0 = " & integer'image(to_integer(unsigned(a0)));
        std.env.finish;
    end process;
end architecture;
