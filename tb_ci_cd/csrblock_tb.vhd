library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity csrblock_tb is
end entity;

architecture sim of csrblock_tb is
    constant MSTATUS : std_logic_vector(11 downto 0) := x"300";
    constant MIE_CSR : std_logic_vector(11 downto 0) := x"304";
    constant MTVEC   : std_logic_vector(11 downto 0) := x"305";
    constant MEPC    : std_logic_vector(11 downto 0) := x"341";
    constant MCAUSE  : std_logic_vector(11 downto 0) := x"342";
    constant MIP     : std_logic_vector(11 downto 0) := x"344";
    constant OP_W    : std_logic_vector(1 downto 0) := "01";
    constant OP_S    : std_logic_vector(1 downto 0) := "10";
    constant OP_C    : std_logic_vector(1 downto 0) := "11";

    signal clk      : std_logic := '0';
    signal rst      : std_logic := '1';
    signal w_DATA   : std_logic_vector(31 downto 0) := (others => '0');
    signal mepc_in  : std_logic_vector(31 downto 0) := (others => '0');
    signal mtvec_o, mepc_o, res : std_logic_vector(31 downto 0);
    signal TRAP, CSRwrite, MRET, irq : std_logic := '0';
    signal CSROp    : std_logic_vector(1 downto 0) := "00";
    signal CSRnum   : std_logic_vector(11 downto 0) := (others => '0');
    signal MIE, MEIE : std_logic;
begin
    clk <= not clk after 5 ns;

    dut : entity work.CSRblock
        port map(clk => clk, rst => rst, w_DATA => w_DATA, mtvec_handler_addr => mtvec_o,
                 mepc_ret_addr_in => mepc_in, mepc_ret_addr_out => mepc_o, TRAP => TRAP,
                 CSRwrite => CSRwrite, CSROp => CSROp, CSRnum => CSRnum, irq => irq,
                 MIE => MIE, MEIE => MEIE, MRET => MRET, CSR_RES => res);

    process
        procedure tick is
        begin
            wait until rising_edge(clk);
            wait for 1 ns;
        end procedure;

        procedure csr_op(num : std_logic_vector(11 downto 0); op : std_logic_vector(1 downto 0);
                         d : std_logic_vector(31 downto 0); old : std_logic_vector(31 downto 0)) is
        begin
            CSRnum <= num; CSROp <= op; w_DATA <= d; CSRwrite <= '1';
            wait for 1 ns;
            assert res = old report "CSR " & to_hstring(num) & " old value " & to_hstring(res) &
                                    " expected " & to_hstring(old) severity error;
            tick;
            CSRwrite <= '0';
        end procedure;

        procedure expect(num : std_logic_vector(11 downto 0); v : std_logic_vector(31 downto 0)) is
        begin
            CSRnum <= num; wait for 1 ns;
            assert res = v report "CSR " & to_hstring(num) & " = " & to_hstring(res) &
                                  " expected " & to_hstring(v) severity error;
        end procedure;
    begin
        tick;
        rst <= '0';
        expect(MSTATUS, x"00000000");
        expect(MIE_CSR, x"00000000");
        expect(MTVEC,   x"00000000");
        expect(MEPC,    x"00000000");
        expect(MCAUSE,  x"00000000");
        assert MIE = '0' and MEIE = '0' and mtvec_o = x"00000000" and mepc_o = x"00000000"
            report "reset values" severity error;

        csr_op(MTVEC, OP_W, x"80000100", x"00000000");
        expect(MTVEC, x"80000100");
        assert mtvec_o = x"80000100" report "mtvec output" severity error;
        csr_op(MTVEC, OP_S, x"0000000F", x"80000100");
        expect(MTVEC, x"8000010F");
        csr_op(MTVEC, OP_C, x"8000000C", x"8000010F");
        expect(MTVEC, x"00000103");
        csr_op(MTVEC, OP_W, x"00001100", x"00000103");

        csr_op(MEPC, OP_W, x"DEADBEEF", x"00000000");
        expect(MEPC, x"DEADBEEF");
        assert mepc_o = x"DEADBEEF" report "mepc output" severity error;
        csr_op(MCAUSE, OP_W, x"12345678", x"00000000");
        expect(MCAUSE, x"12345678");

        csr_op(MSTATUS, OP_W, x"FFFFFFFF", x"00000000");
        expect(MSTATUS, x"00000088");
        assert MIE = '1' report "mstatus.MIE output" severity error;
        csr_op(MSTATUS, OP_C, x"00000008", x"00000088");
        expect(MSTATUS, x"00000080");
        assert MIE = '0' report "csrrc must clear MIE" severity error;
        csr_op(MSTATUS, OP_C, x"00000080", x"00000080");
        expect(MSTATUS, x"00000000");
        csr_op(MSTATUS, OP_S, x"00000008", x"00000000");
        expect(MSTATUS, x"00000008");
        assert MIE = '1' report "csrrs must set MIE" severity error;

        csr_op(MIE_CSR, OP_W, x"FFFFFFFF", x"00000000");
        expect(MIE_CSR, x"00000800");
        assert MEIE = '1' report "mie.MEIE output" severity error;
        csr_op(MIE_CSR, OP_C, x"00000800", x"00000800");
        assert MEIE = '0' report "csrrc must clear MEIE" severity error;
        csr_op(MIE_CSR, OP_S, x"00000800", x"00000000");
        assert MEIE = '1' report "csrrs must set MEIE" severity error;

        irq <= '0'; expect(MIP, x"00000000");
        irq <= '1'; expect(MIP, x"00000800");
        csr_op(MIP, OP_W, x"00000000", x"00000800");
        expect(MIP, x"00000800");
        irq <= '0';

        csr_op(x"340", OP_W, x"FFFFFFFF", x"00000000");
        expect(x"340", x"00000000");
        expect(MTVEC, x"00001100");
        expect(MEPC, x"DEADBEEF");
        expect(MCAUSE, x"12345678");

        CSRnum <= MTVEC; CSROp <= OP_W; w_DATA <= x"FFFFFFFF"; CSRwrite <= '0';
        tick;
        expect(MTVEC, x"00001100");

        mepc_in <= x"8000001C"; TRAP <= '1';
        tick;
        TRAP <= '0';
        expect(MEPC, x"8000001C");
        expect(MCAUSE, x"8000000B");
        expect(MSTATUS, x"00000080");
        assert MIE = '0' and MEIE = '1' report "trap must clear MIE, keep MEIE" severity error;
        assert mepc_o = x"8000001C" and mtvec_o = x"00001100" report "trap outputs" severity error;

        MRET <= '1';
        tick;
        MRET <= '0';
        expect(MSTATUS, x"00000088");
        assert MIE = '1' report "mret must restore MIE from MPIE" severity error;
        expect(MEPC, x"8000001C");

        csr_op(MSTATUS, OP_W, x"00000000", x"00000088");
        mepc_in <= x"80000040"; TRAP <= '1';
        tick;
        TRAP <= '0';
        expect(MSTATUS, x"00000000");
        MRET <= '1';
        tick;
        MRET <= '0';
        expect(MSTATUS, x"00000080");
        assert MIE = '0' report "mret with MPIE = 0 must leave MIE = 0" severity error;

        csr_op(MSTATUS, OP_W, x"00000008", x"00000080");
        mepc_in <= x"80000080"; TRAP <= '1'; MRET <= '1';
        CSRnum <= MEPC; CSROp <= OP_W; w_DATA <= x"11111111"; CSRwrite <= '1';
        tick;
        TRAP <= '0'; MRET <= '0'; CSRwrite <= '0';
        expect(MEPC, x"80000080");
        expect(MSTATUS, x"00000080");

        rst <= '1';
        tick;
        rst <= '0';
        expect(MSTATUS, x"00000000");
        expect(MIE_CSR, x"00000000");
        expect(MTVEC, x"00000000");
        expect(MEPC, x"00000000");
        expect(MCAUSE, x"00000000");

        report "csrblock_tb done";
        std.env.finish;
    end process;
end architecture;
