library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity CSRblock is
    port(
        clk : in std_logic;
        rst : in std_logic;

        w_DATA : in std_logic_vector(31 downto 0);


        mtvec_handler_addr : out std_logic_vector(31 downto 0);
        mepc_ret_addr_in : in std_logic_vector(31 downto 0);
        mepc_ret_addr_out : out std_logic_vector(31 downto 0);
        TRAP : in std_logic;
        CSRwrite : in std_logic;
        CSROp : in std_logic_vector(1 downto 0);
        CSRnum : in std_logic_vector(11 downto 0);
        irq : in std_logic;
        MIE : out std_logic;
        MEIE : out std_logic;
        MRET : in std_logic;
        CSR_RES : out std_logic_vector(31 downto 0)
    );
end entity CSRblock;

architecture RTL of CSRblock is
    signal MPIE : std_logic := '0';
    signal oldDATA : std_logic_vector(31 downto 0);
    signal MIE_R : std_logic := '0';
    signal MEIE_R : std_logic := '0';
    signal mepc_ret_addr_out_Saved  : std_logic_vector(31 downto 0);
    signal mtvec_handler_addr_Saved : std_logic_vector(31 downto 0);
    signal MCAUSE_S : std_logic_vector(31 downto 0);
    
    
begin
    clockDriver : process(clk)
        variable temp_input : std_logic_vector(31 downto 0) := (others => '0');
    begin
        if(rising_edge(clk)) then
            if rst = '1' then
                MPIE <= '0';
                MIE_R <= '0';
                MCAUSE_S <= (others => '0');
                MEIE_R <= '0';
                mepc_ret_addr_out_Saved  <= (others => '0');
                mtvec_handler_addr_Saved <= (others => '0');
            else
                if TRAP = '1' then
                    MPIE <= MIE_R;
                    MIE_R <= '0';
                    MCAUSE_S <= x"8000000B";
                    mepc_ret_addr_out_Saved <= mepc_ret_addr_in;
                elsif MRET = '1' then
                    MPIE <= '1';
                    MIE_R <= MPIE;
                elsif CSRwrite = '1' then
                    if CSROp = "01" then
                        temp_input := w_DATA;
                    elsif CSROp = "10" then
                        temp_input := w_DATA or oldDATA;
                    elsif CSROp = "11" then
                        temp_input := oldDATA and (not w_DATA);
                    else
                        temp_input := (others => '0');
                    end if;
                    
                    case CSRnum is
                        when x"300" =>
                           MIE_R <= temp_input(3); 
                           MPIE <= temp_input(7);
                        when x"304" =>                   
                            MEIE_R <= temp_input(11);
                        when x"305" =>                   
                            mtvec_handler_addr_Saved <= temp_input;
                        when x"341" =>                   
                            mepc_ret_addr_out_Saved <= temp_input;
                        when x"342" =>                   
                            MCAUSE_S <= temp_input;
                        when others =>
                            null;
                    end case;
                end if;
            end if;
        end if;
    end process clockDriver;

    CsrReadPROC : process(CSRnum, MIE_R, MPIE, MEIE_R,
                      mtvec_handler_addr_Saved, mepc_ret_addr_out_Saved, MCAUSE_S, irq)
    begin
        oldDATA <= (others => '0');
        case CSRnum is
            when x"300" =>
                oldDATA(3) <= MIE_R;
                oldDATA(7) <= MPIE;
            when x"304" =>                   
                oldDATA(11) <= MEIE_R;
            when x"305" =>                   
                oldDATA <= mtvec_handler_addr_Saved;
            when x"341" =>                   
                oldDATA <= mepc_ret_addr_out_Saved;
            when x"342" =>                   
                oldDATA <= MCAUSE_S;
            when x"344" =>                   
                oldDATA(11) <= irq;
            when others =>
                null;
        end case;
    end process CsrReadPROC;
    
    CSR_RES <= oldDATA;
    mepc_ret_addr_out <= mepc_ret_addr_out_Saved;
    mtvec_handler_addr <= mtvec_handler_addr_Saved;
    MIE <= MIE_R;
    MEIE <= MEIE_R;
end architecture RTL;

