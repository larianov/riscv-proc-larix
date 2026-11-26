--------------------------------------------------------------------------------
-- tb_pkg : small, dependency-free verification support for VHDL-2008 / GHDL
--
--   Logging     : tb_info / tb_error / tb_check / tb_check_equal (counts errors)
--   Expected    : tb_expect_errors(n) ... tb_end_expect  (error-injection windows)
--   Termination : tb_finish  -> prints "TEST PASSED" or "TEST FAILED" and stops
--   Watchdog    : tb_watchdog(done, timeout)   (concurrent call, kills hung sims)
--   Clock       : tb_clock(clk, period, run)   (concurrent call)
--   Waiting     : tb_wait_for(sig, value, clk, max_cycles, msg)  (no deadlocks)
--   Random      : protected type tb_rand_t (seeded, uniform + skewed-to-edges)
--   Scoreboard  : protected type tb_queue_t (FIFO of std_logic_vector)
--
-- Message format is fixed so scripts can parse logs:
--   [INFO ] <time> msg      [ERROR] <time> msg      [XERR ] <time> msg (expected)
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;

package tb_pkg is

  -- logging ------------------------------------------------------------------
  procedure tb_info (msg : string);
  procedure tb_error(msg : string);
  procedure tb_check(cond : boolean; msg : string);
  procedure tb_check_equal(got, exp : std_logic_vector; msg : string);
  procedure tb_check_equal(got, exp : std_logic;        msg : string);
  procedure tb_check_equal(got, exp : integer;          msg : string);
  procedure tb_set_verbose(enable : boolean);          -- false: tb_info suppressed
  impure function tb_error_count return natural;
  impure function tb_check_count return natural;

  -- expected-error windows (prove that the checkers can fail) ----------------
  procedure tb_expect_errors(n : positive; why : string);
  procedure tb_end_expect;

  -- termination --------------------------------------------------------------
  procedure tb_finish;

  -- concurrent helpers -------------------------------------------------------
  procedure tb_watchdog(signal done : in boolean; timeout : time);
  procedure tb_clock(signal clk : out std_logic; period : time;
                     signal run : in boolean);

  -- bounded wait: wait (on rising clk edges) until sig = value, at most
  -- max_cycles. Returns ok=false and logs an error instead of hanging.
  procedure tb_wait_for(signal sig : in std_logic; value : std_logic;
                        signal clk : in std_logic; max_cycles : positive;
                        msg : string; ok : out boolean);
  procedure tb_wait_for(signal sig : in std_logic; value : std_logic;
                        signal clk : in std_logic; max_cycles : positive;
                        msg : string);

  -- formatting ---------------------------------------------------------------
  function to_str(v : std_logic_vector) return string;  -- hex if width%4=0
  function to_str(v : std_logic) return string;

  -- random -------------------------------------------------------------------
  type tb_rand_t is protected
    procedure seed(s : positive);
    impure function real01 return real;                     -- [0,1)
    impure function int(lo, hi : integer) return integer;    -- uniform
    -- 30% lo, 30% hi, 40% uniform: stresses the edges of a legal range
    impure function int_skewed(lo, hi : integer) return integer;
    impure function slv(width : positive) return std_logic_vector;
    impure function bool(p_true : real := 0.5) return boolean;
  end protected tb_rand_t;

  -- scoreboard queue ---------------------------------------------------------
  type tb_queue_t is protected
    procedure push(v : std_logic_vector);
    impure function pop return std_logic_vector;   -- error if empty
    impure function peek return std_logic_vector;
    impure function count return natural;
    impure function is_empty return boolean;
    procedure clear;
  end protected tb_queue_t;

end package tb_pkg;

--------------------------------------------------------------------------------
package body tb_pkg is

  type tb_state_t is protected
    procedure error_seen(variable expected : out boolean);
    procedure check_seen;
    procedure set_expect(n : natural);
    impure function expect_left return natural;
    impure function errors return natural;
    impure function checks return natural;
    procedure set_verbose(enable : boolean);
    impure function verbose return boolean;
    procedure add_unmet(n : natural);
  end protected tb_state_t;

  type tb_state_t is protected body
    variable n_err    : natural := 0;
    variable n_chk    : natural := 0;
    variable n_expect : natural := 0;
    variable verb     : boolean := true;

    procedure error_seen(variable expected : out boolean) is
    begin
      if n_expect > 0 then
        n_expect := n_expect - 1;
        expected := true;
      else
        n_err    := n_err + 1;
        expected := false;
      end if;
    end procedure;
    procedure check_seen is begin n_chk := n_chk + 1; end procedure;
    procedure set_expect(n : natural) is begin n_expect := n; end procedure;
    impure function expect_left return natural is begin return n_expect; end function;
    impure function errors return natural is begin return n_err; end function;
    impure function checks return natural is begin return n_chk; end function;
    procedure set_verbose(enable : boolean) is begin verb := enable; end procedure;
    impure function verbose return boolean is begin return verb; end function;
    procedure add_unmet(n : natural) is begin n_err := n_err + n; end procedure;
  end protected body tb_state_t;

  shared variable st : tb_state_t;

  procedure put(tag : string; msg : string) is
    variable l : line;
  begin
    write(l, tag & " " & to_string(now, ns) & "  " & msg);
    writeline(output, l);
  end procedure;

  procedure tb_info(msg : string) is
  begin
    if st.verbose then put("[INFO ]", msg); end if;
  end procedure;

  procedure tb_error(msg : string) is
    variable exp : boolean;
  begin
    st.error_seen(exp);
    if exp then put("[XERR ]", msg); else put("[ERROR]", msg); end if;
  end procedure;

  procedure tb_check(cond : boolean; msg : string) is
  begin
    st.check_seen;
    if not cond then tb_error(msg); end if;
  end procedure;

  function to_str(v : std_logic) return string is
  begin
    return std_logic'image(v);
  end function;

  function to_str(v : std_logic_vector) return string is
    variable n : std_logic_vector(v'length - 1 downto 0) := v;
  begin
    if v'length mod 4 = 0 and not is_x(v) then
      return "x""" & to_hstring(n) & """";
    else
      return """" & to_string(n) & """";
    end if;
  end function;

  procedure tb_check_equal(got, exp : std_logic_vector; msg : string) is
  begin
    -- "=" on std_logic_vector is literal: 'X'/'U' in got fails unless exp has
    -- the same metavalue, which is what we want (unknown output = bug).
    tb_check(got'length = exp'length and got = exp,
             msg & ": got " & to_str(got) & ", expected " & to_str(exp));
  end procedure;

  procedure tb_check_equal(got, exp : std_logic; msg : string) is
  begin
    tb_check(got = exp, msg & ": got " & to_str(got) & ", expected " & to_str(exp));
  end procedure;

  procedure tb_check_equal(got, exp : integer; msg : string) is
  begin
    tb_check(got = exp, msg & ": got " & integer'image(got) &
                        ", expected " & integer'image(exp));
  end procedure;

  procedure tb_set_verbose(enable : boolean) is begin st.set_verbose(enable); end procedure;
  impure function tb_error_count return natural is begin return st.errors; end function;
  impure function tb_check_count return natural is begin return st.checks; end function;

  procedure tb_expect_errors(n : positive; why : string) is
  begin
    if st.expect_left /= 0 then
      tb_error("tb_expect_errors called while a previous window is still open");
    end if;
    put("[EXPCT]", integer'image(n) & " error(s) expected: " & why);
    st.set_expect(n);
  end procedure;

  procedure tb_end_expect is
    variable left : natural := st.expect_left;
  begin
    st.set_expect(0);
    if left /= 0 then
      st.add_unmet(1);
      put("[ERROR]", integer'image(left) &
          " expected error(s) were NOT detected - the checker is blind here");
    else
      put("[EXPCT]", "all expected errors were detected");
    end if;
  end procedure;

  procedure tb_finish is
  begin
    if st.expect_left /= 0 then tb_end_expect; end if;
    put("[DONE ]", integer'image(st.checks) & " checks, " &
                   integer'image(st.errors) & " errors");
    if st.checks = 0 then
      put("[ERROR]", "no checks were executed - a testbench that checks nothing proves nothing");
      st.add_unmet(1);
    end if;
    if st.errors = 0 then
      put("[DONE ]", "TEST PASSED");
      std.env.finish;
    else
      put("[DONE ]", "TEST FAILED");
      report "TEST FAILED" severity failure;
    end if;
  end procedure;

  procedure tb_watchdog(signal done : in boolean; timeout : time) is
  begin
    wait until done for timeout;
    if not done then
      put("[ERROR]", "watchdog: test did not finish within " & time'image(timeout));
      put("[DONE ]", "TEST FAILED");
      report "watchdog timeout" severity failure;
    end if;
    wait;
  end procedure;

  procedure tb_clock(signal clk : out std_logic; period : time;
                     signal run : in boolean) is
  begin
    clk <= '0';
    while run loop
      wait for period / 2;
      clk <= '1';
      wait for period - period / 2;
      clk <= '0';
    end loop;
    wait;
  end procedure;

  procedure tb_wait_for(signal sig : in std_logic; value : std_logic;
                        signal clk : in std_logic; max_cycles : positive;
                        msg : string; ok : out boolean) is
  begin
    for i in 1 to max_cycles loop
      wait until rising_edge(clk);
      if sig = value then
        ok := true;
        return;
      end if;
    end loop;
    tb_error("timeout after " & integer'image(max_cycles) & " cycles: " & msg);
    ok := false;
  end procedure;

  procedure tb_wait_for(signal sig : in std_logic; value : std_logic;
                        signal clk : in std_logic; max_cycles : positive;
                        msg : string) is
    variable ok : boolean;
  begin
    tb_wait_for(sig, value, clk, max_cycles, msg, ok);
  end procedure;

  -- random -------------------------------------------------------------------
  type tb_rand_t is protected body
    variable s1 : positive := 42;
    variable s2 : positive := 4711;

    procedure seed(s : positive) is
    begin
      s1 := s;
      s2 := (s mod 2147483562) + 1;
    end procedure;

    impure function real01 return real is
      variable r : real;
    begin
      uniform(s1, s2, r);
      return r;
    end function;

    impure function int(lo, hi : integer) return integer is
    begin
      return lo + integer(floor(real01 * real(hi - lo + 1)));
    end function;

    impure function int_skewed(lo, hi : integer) return integer is
      variable r : real := real01;
    begin
      if r < 0.3 then return lo;
      elsif r < 0.6 then return hi;
      else return int(lo, hi);
      end if;
    end function;

    impure function slv(width : positive) return std_logic_vector is
      variable v : std_logic_vector(width - 1 downto 0);
    begin
      for i in v'range loop
        if real01 < 0.5 then v(i) := '0'; else v(i) := '1'; end if;
      end loop;
      return v;
    end function;

    impure function bool(p_true : real := 0.5) return boolean is
    begin
      return real01 < p_true;
    end function;
  end protected body tb_rand_t;

  -- queue --------------------------------------------------------------------
  type tb_queue_t is protected body
    type item_t;
    type item_ptr is access item_t;
    type slv_ptr is access std_logic_vector;
    type item_t is record
      data : slv_ptr;
      nxt  : item_ptr;
    end record;
    variable head, tail : item_ptr := null;
    variable garbage    : item_ptr := null;  -- freed lazily on the next pop
    variable n : natural := 0;

    procedure free(p : inout item_ptr) is
    begin
      if p /= null then
        deallocate(p.data);
        deallocate(p);
      end if;
    end procedure;

    procedure push(v : std_logic_vector) is
      variable it : item_ptr := new item_t;
    begin
      it.data := new std_logic_vector'(v);
      if tail = null then head := it; else tail.nxt := it; end if;
      tail := it;
      n := n + 1;
    end procedure;

    impure function peek return std_logic_vector is
    begin
      if head = null then
        tb_error("scoreboard: peek on empty queue (unexpected output?)");
        return "X";
      end if;
      return head.data.all;
    end function;

    impure function pop return std_logic_vector is
    begin
      free(garbage);
      if head = null then
        tb_error("scoreboard: pop on empty queue (unexpected output?)");
        return "X";
      end if;
      garbage := head;
      head := head.nxt;
      if head = null then tail := null; end if;
      n := n - 1;
      return garbage.data.all;
    end function;

    impure function count return natural is begin return n; end function;
    impure function is_empty return boolean is begin return n = 0; end function;

    procedure clear is
      variable p : item_ptr;
    begin
      free(garbage);
      while head /= null loop
        p := head;
        head := head.nxt;
        free(p);
      end loop;
      tail := null;
      n := 0;
    end procedure;
  end protected body tb_queue_t;

end package body tb_pkg;
