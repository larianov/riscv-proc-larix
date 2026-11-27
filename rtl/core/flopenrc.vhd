library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity flopenrc is
    generic(
        WIDTH : integer := 31;
        
    );

    port(
        clk : in std_logic;
        rst : in std_logic;
        clr : in std_logic;
        en : in std_logic;
        d : in std_logic_vector(WIDTH-1 downto 0);
        q : out std_logic_vector(WIDTH-1 downto 0)
    );
end entity flopenrc;


architecture RTL of flopenrc is
begin
    name : process (clk) is
    begin
        if rising_edge(clk) then
            if rst = '1' then
                q <= (others => '0');
            else
                if en = '1' then
                    if clr = '1' then
                        q <= (others => '0');
                    else
                        q <= d;
                    end if;
                end if;
            end if;
        end if;
    end process name;
end architecture RTL;
