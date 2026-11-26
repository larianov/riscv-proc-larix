--------------------------------------------------------------------------------
-- riscv_ref_pkg : reference models shared by the testbenches
--   ref_decode : control signals (controlunit_tb, controlblock_tb)
--   ref_alu    : ALU by code (datapath_tb, core_tb); alu.vhd itself is verified by alu_tb with
--                an independent bit-level model, here numeric_std is enough
--   ref_imm    : immediate by ImmSrc (datapath_tb); ImmGen is verified by immgen_tb
--
-- Written from the README "Control signals" table (blank = 0), not from ControlUnit.vhd.
-- For an illegal instruction only the side-effect outputs are defined (Illegal = 1, nothing
-- written, no branch/jump); everything else is '-' (don't care, compare with std_match).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package riscv_ref_pkg is
    type ctl_t is record
        RegWrite  : std_logic;
        ASrc      : std_logic_vector(1 downto 0);
        BSrc      : std_logic;
        Illegal   : std_logic;
        Branch    : std_logic;
        ImmSrc    : std_logic_vector(2 downto 0);
        MemWrite  : std_logic;
        ResultSrc : std_logic_vector(1 downto 0);
        Alu       : std_logic_vector(3 downto 0);
        CSRwrite  : std_logic;
        CSRop     : std_logic_vector(1 downto 0);
        MRET      : std_logic;
        JalrReg   : std_logic;
        Jump      : std_logic;
    end record;

    constant CTL_FIELDS : string :=
        "RegWrite ASrc BSrc Illegal Branch ImmSrc MemWrite ResultSrc alu CSRwrite CSRop MRET JalrReg Jump";

    -- all fields in the order of CTL_FIELDS, 22 bits
    function pack(c : ctl_t) return std_logic_vector;
    -- ALU code of an ALU operation (README "ALU codes"); alt = funct7 bit 5 (sub / sra)
    function alu_code(f3 : natural; alt : boolean) return std_logic_vector;
    -- reference decode
    function ref_decode(op, f3, f7, rs1 : natural) return ctl_t;
    function ref_decode(instr : std_logic_vector(31 downto 0)) return ctl_t;

    -- README "ALU codes": unknown codes give 0
    function ref_alu(a, b : std_logic_vector(31 downto 0); code : std_logic_vector(3 downto 0))
        return std_logic_vector;
    -- README ImmSrc: 000 I, 001 S, 010 B, 011 J, 100 U (others: 0 is NOT assumed, returns X)
    function ref_imm(w : std_logic_vector(31 downto 0); src : std_logic_vector(2 downto 0))
        return std_logic_vector;
end package riscv_ref_pkg;

package body riscv_ref_pkg is
    constant ZERO_CTL : ctl_t := ('0', "00", '0', '0', '0', "000", '0', "00", "0000", '0', "00", '0', '0', '0');

    function pack(c : ctl_t) return std_logic_vector is
    begin
        return c.RegWrite & c.ASrc & c.BSrc & c.Illegal & c.Branch & c.ImmSrc & c.MemWrite & c.ResultSrc &
               c.Alu & c.CSRwrite & c.CSRop & c.MRET & c.JalrReg & c.Jump;
    end function;

    function alu_code(f3 : natural; alt : boolean) return std_logic_vector is
    begin
        case f3 is
            when 0 => if alt then return "1000"; else return "0000"; end if;   -- sub / add
            when 1 => return "0001";                                          -- sll
            when 2 => return "0010";                                          -- slt
            when 3 => return "0011";                                          -- sltu
            when 4 => return "0100";                                          -- xor
            when 5 => if alt then return "1101"; else return "0101"; end if;  -- sra / srl
            when 6 => return "0110";                                          -- or
            when others => return "0111";                                     -- and
        end case;
    end function;

    function ref_decode(op, f3, f7, rs1 : natural) return ctl_t is
        variable c     : ctl_t := ZERO_CTL;
        variable legal : boolean := false;
    begin
        case op is
            when 16#33# =>                                   -- R-type
                if f7 = 0 or (f7 = 32 and (f3 = 0 or f3 = 5)) then
                    legal := true;
                    c.RegWrite := '1';
                    c.Alu := alu_code(f3, f7 = 32);
                end if;
            when 16#13# =>                                   -- I-type ALU
                if f3 = 1 then
                    legal := f7 = 0;                         -- slli
                elsif f3 = 5 then
                    legal := f7 = 0 or f7 = 32;              -- srli / srai
                else
                    legal := true;
                end if;
                c.RegWrite := '1';
                c.BSrc := '1';
                c.Alu := alu_code(f3, f3 = 5 and f7 = 32);
            when 16#03# =>                                   -- lb lh lw lbu lhu
                legal := f3 = 0 or f3 = 1 or f3 = 2 or f3 = 4 or f3 = 5;
                c.RegWrite := '1';
                c.BSrc := '1';
                c.ResultSrc := "01";
            when 16#23# =>                                   -- sb sh sw
                legal := f3 <= 2;
                c.ImmSrc := "001";
                c.BSrc := '1';
                c.MemWrite := '1';
            when 16#63# =>                                   -- beq bne blt bge bltu bgeu
                legal := f3 /= 2 and f3 /= 3;
                c.ImmSrc := "010";
                c.Branch := '1';
                if f3 <= 1 then
                    c.Alu := "1000";
                elsif f3 <= 5 then
                    c.Alu := "0010";
                else
                    c.Alu := "0011";
                end if;
            when 16#6F# =>                                   -- jal
                legal := true;
                c.RegWrite := '1';
                c.ImmSrc := "011";
                c.ResultSrc := "10";
                c.Jump := '1';
            when 16#67# =>                                   -- jalr
                legal := f3 = 0;
                c.RegWrite := '1';
                c.ResultSrc := "10";
                c.Jump := '1';
                c.JalrReg := '1';
            when 16#37# =>                                   -- lui
                legal := true;
                c.RegWrite := '1';
                c.ImmSrc := "100";
                c.ASrc := "10";
                c.BSrc := '1';
            when 16#17# =>                                   -- auipc
                legal := true;
                c.RegWrite := '1';
                c.ImmSrc := "100";
                c.ASrc := "01";
                c.BSrc := '1';
            when 16#73# =>                                   -- SYSTEM
                if f3 = 0 and f7 = 16#18# then               -- mret
                    legal := true;
                    c.MRET := '1';
                elsif f3 >= 1 and f3 <= 3 then               -- csrrw csrrs csrrc
                    legal := true;
                    c.RegWrite := '1';
                    c.ResultSrc := "11";
                    c.CSRop := std_logic_vector(to_unsigned(f3, 2));
                    if f3 = 1 or rs1 /= 0 then
                        c.CSRwrite := '1';
                    end if;
                end if;
            when others =>
                null;
        end case;
        if not legal then
            c := ('0', "--", '-', '1', '0', "---", '0', "--", "----", '0', "--", '0', '-', '0');
        end if;
        return c;
    end function;

    function ref_decode(instr : std_logic_vector(31 downto 0)) return ctl_t is
    begin
        return ref_decode(to_integer(unsigned(instr(6 downto 0))), to_integer(unsigned(instr(14 downto 12))),
                          to_integer(unsigned(instr(31 downto 25))), to_integer(unsigned(instr(19 downto 15))));
    end function;

    function ref_alu(a, b : std_logic_vector(31 downto 0); code : std_logic_vector(3 downto 0))
        return std_logic_vector is
        variable sh : natural := to_integer(unsigned(b(4 downto 0)));
        variable r  : std_logic_vector(31 downto 0) := (others => '0');
    begin
        case code is
            when "0000" => r := std_logic_vector(unsigned(a) + unsigned(b));
            when "1000" => r := std_logic_vector(unsigned(a) - unsigned(b));
            when "0001" => r := std_logic_vector(shift_left(unsigned(a), sh));
            when "0101" => r := std_logic_vector(shift_right(unsigned(a), sh));
            when "1101" => r := std_logic_vector(shift_right(signed(a), sh));
            when "0010" => if signed(a) < signed(b) then r(0) := '1'; end if;
            when "0011" => if unsigned(a) < unsigned(b) then r(0) := '1'; end if;
            when "0100" => r := a xor b;
            when "0110" => r := a or b;
            when "0111" => r := a and b;
            when others => null;
        end case;
        return r;
    end function;

    function ref_imm(w : std_logic_vector(31 downto 0); src : std_logic_vector(2 downto 0))
        return std_logic_vector is
    begin
        case src is
            when "000" => return std_logic_vector(resize(signed(w(31 downto 20)), 32));
            when "001" => return std_logic_vector(resize(signed(w(31 downto 25) & w(11 downto 7)), 32));
            when "010" => return std_logic_vector(resize(signed(w(31) & w(7) & w(30 downto 25) & w(11 downto 8) & '0'), 32));
            when "011" => return std_logic_vector(resize(signed(w(31) & w(19 downto 12) & w(20) & w(30 downto 21) & '0'), 32));
            when "100" => return w(31 downto 12) & x"000";
            when others => return (31 downto 0 => 'X');
        end case;
    end function;
end package body riscv_ref_pkg;
