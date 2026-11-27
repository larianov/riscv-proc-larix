library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity HazardController is
    port(
        StallF : out std_logic;
        StallD : out std_logic;
        FlushD : out std_logic;
        Rs1D : in std_logic_vector(4 downto 0);
        Rs2D : in std_logic_vector(4 downto 0);
        Rs1E : in std_logic_vector(4 downto 0);
        Rs2E : in std_logic_vector(4 downto 0);
        RDE : in std_logic_vector(4 downto 0);
        FlushE : out std_logic;
        PCsrcE : in std_logic_vector(1 downto 0);
        ForwardAE : out std_logic_vector(1 downto 0);
        ForwardBE : out std_logic_vector(1 downto 0);
        Result_SrcE : in std_logic_vector(1 downto 0);
        RdM : in std_logic_vector(4 downto 0);
        RegWriteM : in std_logic;        
        RDW : in std_logic_vector(4 downto 0);
        RegWriteW : in std_logic;
        Result_SrcM : in std_logic_vector(1 downto 0)
    );
end entity HazardController;


architecture RTL of HazardController is
    constant zeros : std_logic_vector(4 downto 0) := (others => '0');
    
begin
    Result_SrcE_Check : process(Result_SrcE, Rs1D, Rs2D, RDE, PCsrcE) is
    begin
        StallF <='0';
        StallD <= '0';
        FlushD <= '0';
        FlushE <= '0';
        if Result_SrcE = "01" then --loading
            if Rs1D = RDE or Rs2D = RDE then
                StallF <= '1';
                StallD <= '1';
                FlushE <= '1';
            end if;
        end if;
        if PCsrcE = "01" then
            FlushD <= '1';
            FlushE <= '1';
        end if;
    end process Result_SrcE_Check;
    
    ForwardingA : process(Result_SrcM, RegWriteM, Rs1E, RdM, RDW, RegWriteW, Rs2E) is
    begin
        ForwardAE <= (others => '0');
        ForwardBE <= (others => '0');
        if RegWriteW = '1' then
            if Rs1E = RDW and Rs1E /= zeros then
                ForwardAE <= "01";
            end if;
            if Rs2E = RdW and Rs2E /= zeros then
                ForwardBE <= "01";
            end if;
        end if;
        if Result_SrcM = "00" then
            if RegWriteM = '1' then
                if Rs1E = RdM and Rs1E /= zeros then
                    ForwardAE <= "10";
                end if;
                if Rs2E = RdM and Rs2E /= zeros then
                    ForwardBE <= "10";
                end if;
            end if;
        end if;
    end process ForwardingA;
    
end architecture RTL;
