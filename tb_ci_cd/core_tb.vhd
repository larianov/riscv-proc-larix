library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

-- Runs a random program (R-type, I-type, loads, stores, forward beq/bne) on the core and compares every cycle
-- with a software model of RV32I: PC, ALU result (rez), the register contents and the store
-- interface (WE byte enables / WD data lanes). Loads (aligned, x0 base) read a memory word that is
-- a pure function of the address; the loaded value is verified through later ALU operations.
entity core_tb is
end entity;

architecture sim of core_tb is
    constant ROM_SIZE : integer := 1024;
    type rom_t is array (0 to ROM_SIZE - 1) of std_logic_vector(31 downto 0);

    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal instr   : std_logic_vector(31 downto 0);
    signal PC      : std_logic_vector(31 downto 0);
    signal Illegal : std_logic;
    signal rez     : std_logic_vector(31 downto 0);
    signal WE      : std_logic_vector(3 downto 0);
    signal WD      : std_logic_vector(31 downto 0);
    signal mem_rd  : std_logic_vector(31 downto 0);

    signal rom : rom_t := (others => x"00000013"); -- nop

    ---------------------------------------------------------------- encoders
    function enc_r(f7, rs2, rs1, f3, rd : integer) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(f7, 7)) & std_logic_vector(to_unsigned(rs2, 5)) &
               std_logic_vector(to_unsigned(rs1, 5)) & std_logic_vector(to_unsigned(f3, 3)) &
               std_logic_vector(to_unsigned(rd, 5)) & "0110011";
    end function;

    function enc_i(imm, rs1, f3, rd : integer) return std_logic_vector is
    begin
        return std_logic_vector(to_signed(imm, 12)) & std_logic_vector(to_unsigned(rs1, 5)) &
               std_logic_vector(to_unsigned(f3, 3)) & std_logic_vector(to_unsigned(rd, 5)) & "0010011";
    end function;

    function enc_s(imm, rs2, rs1, f3 : integer) return std_logic_vector is
        variable o : std_logic_vector(11 downto 0) := std_logic_vector(to_signed(imm, 12));
    begin
        return o(11 downto 5) & std_logic_vector(to_unsigned(rs2, 5)) &
               std_logic_vector(to_unsigned(rs1, 5)) & std_logic_vector(to_unsigned(f3, 3)) &
               o(4 downto 0) & "0100011";
    end function;

    function enc_b(off, rs2, rs1, f3 : integer) return std_logic_vector is
        variable o : std_logic_vector(12 downto 0) := std_logic_vector(to_signed(off, 13));
    begin
        return o(12) & o(10 downto 5) & std_logic_vector(to_unsigned(rs2, 5)) &
               std_logic_vector(to_unsigned(rs1, 5)) & std_logic_vector(to_unsigned(f3, 3)) &
               o(4 downto 1) & o(11) & "1100011";
    end function;

    function enc_l(imm, rs1, f3, rd : integer) return std_logic_vector is
    begin
        return std_logic_vector(to_signed(imm, 12)) & std_logic_vector(to_unsigned(rs1, 5)) &
               std_logic_vector(to_unsigned(f3, 3)) & std_logic_vector(to_unsigned(rd, 5)) & "0000011";
    end function;

    -- memory contents: the word at a (word aligned) address
    function mem_word(addr : std_logic_vector(31 downto 0)) return std_logic_vector is
        variable a : unsigned(31 downto 0) := unsigned(addr(31 downto 2)) & "00";
    begin
        return std_logic_vector(resize(a * unsigned'(x"9E3779B1"), 32) xor x"5A5AC3C3");
    end function;

    -- RV32I load of width/sign given by f3 from the word w at byte offset off (aligned only)
    function load_model(f3 : std_logic_vector(2 downto 0); w : std_logic_vector(31 downto 0);
                        off : integer) return std_logic_vector is
        variable b : std_logic_vector(7 downto 0) := w(8 * off + 7 downto 8 * off);
        variable h : std_logic_vector(15 downto 0) := (others => '0');
    begin
        if off <= 2 then h := w(8 * off + 15 downto 8 * off); end if;
        case f3 is
            when "000" => return (31 downto 8 => b(7)) & b;
            when "100" => return x"000000" & b;
            when "001" => return (31 downto 16 => h(15)) & h;
            when "101" => return x"0000" & h;
            when others => return w;
        end case;
    end function;

    ---------------------------------------------------------------- model of the ALU
    function alu_model(f3 : std_logic_vector(2 downto 0); alt : boolean;
                       a, b : std_logic_vector(31 downto 0)) return std_logic_vector is
        variable sh : integer := to_integer(unsigned(b(4 downto 0)));
        variable lt : std_logic_vector(31 downto 0) := (others => '0');
    begin
        case f3 is
            when "000" =>
                if alt then return std_logic_vector(unsigned(a) - unsigned(b));
                else return std_logic_vector(unsigned(a) + unsigned(b)); end if;
            when "001" => return std_logic_vector(shift_left(unsigned(a), sh));
            when "010" =>
                if signed(a) < signed(b) then lt(0) := '1'; end if;
                return lt;
            when "011" =>
                if unsigned(a) < unsigned(b) then lt(0) := '1'; end if;
                return lt;
            when "100" => return a xor b;
            when "101" =>
                if alt then return std_logic_vector(shift_right(signed(a), sh));
                else return std_logic_vector(shift_right(unsigned(a), sh)); end if;
            when "110" => return a or b;
            when others => return a and b;
        end case;
    end function;
begin
    clk <= not clk after 5 ns;

    -- instruction fetch: combinational ROM
    instr <= rom(to_integer(unsigned(PC(11 downto 2)))) when to_integer(unsigned(PC)) < 4 * ROM_SIZE
             else x"00000013";

    mem_rd <= mem_word(rez);

    dut : entity work.core
        port map(rst => rst, clk => clk, instr => instr, PC => PC, Illegal => Illegal, rez => rez,
                 OUT_OF_MEMORY_DATA => mem_rd, WD => WD, WE => WE);

    ---------------------------------------------------------------- build the program
    gen : process
        variable s1 : positive := 42;
        variable s2 : positive := 4242;
        variable x : real;
        variable p : rom_t := (others => x"00000013");
        variable kind, sel : integer;
        type pair is array (0 to 1) of integer;
        type op_table is array (0 to 9) of pair;
        -- (funct3, funct7) for R-type: add sub sll slt sltu xor srl sra or and
        constant R_OPS : op_table := ((0,0),(0,32),(1,0),(2,0),(3,0),(4,0),(5,0),(5,32),(6,0),(7,0));
        constant I_F3  : integer_vector(0 to 7) := (0, 1, 2, 3, 4, 5, 5, 6); -- 8 choices (5 twice = srli/srai)
        variable f3, lw : integer;

        impure function rnd(n : integer) return integer is
            variable y : real;
        begin
            uniform(s1, s2, y);
            return integer(floor(y * real(n)));
        end function;
    begin
        -- prologue: put some random values into x1..x7
        for r in 1 to 7 loop
            p(r - 1) := enc_i(rnd(4096) - 2048, 0, 0, r);
        end loop;

        for n in 7 to ROM_SIZE - 20 loop
            kind := rnd(12);
            if kind < 5 then      -- R-type
                sel := rnd(10);
                p(n) := enc_r(R_OPS(sel)(1), rnd(8), rnd(8), R_OPS(sel)(0), rnd(8));
            elsif kind < 9 then   -- I-type
                sel := rnd(8);
                f3 := I_F3(sel);
                if f3 = 1 then
                    p(n) := enc_i(rnd(32), rnd(8), 1, rnd(8));              -- slli
                elsif f3 = 5 and sel = 5 then
                    p(n) := enc_i(rnd(32), rnd(8), 5, rnd(8));              -- srli
                elsif f3 = 5 then
                    p(n) := enc_i(1024 + rnd(32), rnd(8), 5, rnd(8));       -- srai
                else
                    p(n) := enc_i(rnd(4096) - 2048, rnd(8), f3, rnd(8));
                end if;
            elsif kind < 10 then  -- store sb / sh / sw
                p(n) := enc_s(rnd(4096) - 2048, rnd(8), rnd(8), rnd(3));
            elsif kind < 11 then  -- load lb lh lw lbu lhu, aligned address = imm (base x0)
                sel := rnd(5);
                lw := 0;
                case sel is
                    when 0 => f3 := 0;
                    when 1 => f3 := 1; lw := 1;
                    when 2 => f3 := 2; lw := 3;
                    when 3 => f3 := 4;
                    when others => f3 := 5; lw := 1;
                end case;
                p(n) := enc_l(((rnd(4096) - 2048) / (lw + 1)) * (lw + 1), 0, f3, rnd(8));
            else                  -- forward branch skipping 1 or 2 instructions
                p(n) := enc_b(8 + 4 * rnd(2), rnd(8), rnd(8), rnd(2));      -- beq / bne
            end if;
        end loop;
        p(ROM_SIZE - 1) := x"00000063"; -- beq x0,x0,0  : halt
        rom <= p;
        wait;
    end process;

    ---------------------------------------------------------------- checker
    check : process
        type reg_array is array (0 to 31) of std_logic_vector(31 downto 0);
        variable regs : reg_array := (others => (others => '0'));
        variable pc_m : integer := 0;
        variable w    : std_logic_vector(31 downto 0);
        variable a, b, exp_rez : std_logic_vector(31 downto 0);
        variable rd, rs1, rs2 : integer;
        variable f3 : std_logic_vector(2 downto 0);
        variable alt, taken : boolean;
        variable exp_we : std_logic_vector(3 downto 0);
        variable width, off : integer;
        variable stores, loads : integer := 0;
        variable cycles, branches_taken, branches_not : integer := 0;
    begin
        wait for 1 ns;                 -- let gen process fill the rom
        wait until falling_edge(clk);
        wait until falling_edge(clk);
        rst <= '0';

        while pc_m /= 4 * (ROM_SIZE - 1) loop
            w   := rom(pc_m / 4);
            rd  := to_integer(unsigned(w(11 downto 7)));
            rs1 := to_integer(unsigned(w(19 downto 15)));
            rs2 := to_integer(unsigned(w(24 downto 20)));
            f3  := w(14 downto 12);
            a   := regs(rs1);

            assert to_integer(unsigned(PC)) = pc_m
                report "PC wrong at cycle " & integer'image(cycles) & ": got " & to_hstring(PC) &
                       " expected " & integer'image(pc_m) severity failure;
            assert Illegal = '0'
                report "Illegal at PC " & integer'image(pc_m) & " instr " & to_hstring(w) severity failure;

            if w(6 downto 0) = "0110011" then          -- R-type
                alt := (w(30) = '1');
                exp_rez := alu_model(f3, alt, a, regs(rs2));
                if rd /= 0 then regs(rd) := exp_rez; end if;
                pc_m := pc_m + 4;
            elsif w(6 downto 0) = "0010011" then       -- I-type
                b := (31 downto 12 => w(31)) & w(31 downto 20);
                alt := (f3 = "101" and w(30) = '1');
                exp_rez := alu_model(f3, alt, a, b);
                if rd /= 0 then regs(rd) := exp_rez; end if;
                pc_m := pc_m + 4;
            elsif w(6 downto 0) = "0100011" then       -- store: ALU computes rs1 + imm_s, regs unchanged
                b := (31 downto 12 => w(31)) & w(31 downto 25) & w(11 downto 7);
                exp_rez := std_logic_vector(unsigned(a) + unsigned(b));
                width := 2 ** to_integer(unsigned(f3));
                off := to_integer(unsigned(exp_rez(1 downto 0)));
                exp_we := (others => '0');
                if off mod width = 0 then
                    for i in 0 to width - 1 loop exp_we(off + i) := '1'; end loop;
                end if;
                assert WE = exp_we
                    report "WE wrong at PC " & integer'image(pc_m) & ": got " & to_string(WE) &
                           " expected " & to_string(exp_we) severity failure;
                for i in 0 to 3 loop    -- every enabled lane must carry the right byte of rs2
                    if exp_we(i) = '1' then
                        assert WD(8 * i + 7 downto 8 * i) = regs(rs2)(8 * (i - off) + 7 downto 8 * (i - off))
                            report "WD lane " & integer'image(i) & " wrong at PC " & integer'image(pc_m) severity failure;
                    end if;
                end loop;
                stores := stores + 1;
                pc_m := pc_m + 4;
            elsif w(6 downto 0) = "0000011" then       -- load: rd = mem[rs1 + imm_i]
                b := (31 downto 12 => w(31)) & w(31 downto 20);
                exp_rez := std_logic_vector(unsigned(a) + unsigned(b));
                if rd /= 0 then
                    regs(rd) := load_model(f3, mem_word(exp_rez), to_integer(unsigned(exp_rez(1 downto 0))));
                end if;
                loads := loads + 1;
                pc_m := pc_m + 4;
            else                                       -- branch: ALU computes rs1 - rs2
                exp_rez := std_logic_vector(unsigned(a) - unsigned(regs(rs2)));
                taken := (exp_rez = x"00000000") = (f3 = "000");
                if taken then
                    b := (31 downto 13 => w(31)) & w(31) & w(7) & w(30 downto 25) & w(11 downto 8) & '0';
                    pc_m := pc_m + to_integer(signed(b));
                    branches_taken := branches_taken + 1;
                else
                    pc_m := pc_m + 4;
                    branches_not := branches_not + 1;
                end if;
            end if;

            if w(6 downto 0) /= "0100011" then
                assert WE = "0000" report "WE must be 0 for non-store at PC " & integer'image(pc_m) severity failure;
            end if;
            assert rez = exp_rez
                report "rez wrong at PC " & integer'image(to_integer(unsigned(PC))) & " instr " & to_hstring(w) &
                       ": got " & to_hstring(rez) & " expected " & to_hstring(exp_rez) severity failure;
            cycles := cycles + 1;
            wait until falling_edge(clk);   -- next cycle
        end loop;

        report "core_tb done: " & integer'image(cycles) & " cycles, branches taken " &
               integer'image(branches_taken) & " / not taken " & integer'image(branches_not);
        assert loads > 20 report "program has too few loads" severity error;
        assert stores > 20 report "program has too few stores" severity error;
        assert branches_taken > 20 and branches_not > 20 report "program has too few branches" severity error;

        -- halt loop must stay put
        for i in 1 to 5 loop
            wait until falling_edge(clk);
            assert to_integer(unsigned(PC)) = 4 * (ROM_SIZE - 1) report "left the halt loop" severity error;
        end loop;
        std.env.finish;
    end process;
end architecture;
