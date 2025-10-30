library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tt_um_VHDL_PWM_DEMUX is
    port (
        ui_in   : in  std_logic_vector(7 downto 0);
        uo_out  : out std_logic_vector(7 downto 0);
        uio_in  : in  std_logic_vector(7 downto 0);
        uio_out : out std_logic_vector(7 downto 0);
        uio_oe  : out std_logic_vector(7 downto 0);
        ena     : in  std_logic;
        clk     : in  std_logic;
        rst_n   : in  std_logic
    );
end tt_um_VHDL_PWM_DEMUX;

architecture rtl of tt_um_VHDL_PWM_DEMUX is
  component pwm_cfg_demux is   
    clk       : in  std_logic;
    res_ni    : in  std_logic;

    -- Compact config interface (demuxed 8-bit bus)
    data_i    : in  unsigned(7 downto 0);              -- shared 8-bit bus
    sel_i     : in  std_logic_vector(1 downto 0);      -- "00"=set, "01"=clear, "10"=reload
    wr_i      : in  std_logic;                         -- 1-cycle write strobe
    commit_i  : in  std_logic;                         -- atomic apply (same-cycle OK)

    pwm_o     : out std_logic
 end component;
    
    signal data_s      : unsigned(7 downto 0);
    signal sel_s       : std_logic_vector(1 downto 0);
    signal wr_s        : std_logic;
    signal commit_s    : std_logic;
    signal pwm_s       : std_logic;
    signal res_ni_g    : std_logic;
begin
    -- Hold in reset when not enabled (saves power on the shuttle)
    res_ni_g <= rst_n and ena;

    -- Use uio as inputs for control; don't drive them
    uio_out <= (others => '0');
    uio_oe  <= (others => '0');

    -- Map compact config interface
    data_s   <= unsigned(ui_in);
    sel_s    <= uio_in(1 downto 0);
    wr_s     <= uio_in(2);
    commit_s <= uio_in(3);

    -- Show PWM on uo_out(0); others low
    uo_out <= "0000000" & pwm_s;

    -- Instantiate your wrapper+core
    u_cfg: pwm_cfg_demux
        port map (
            clk       => clk,
            res_ni    => res_ni_g,
            data_i    => data_s,
            sel_i     => sel_s,
            wr_i      => wr_s,
            commit_i  => commit_s,
            pwm_o     => pwm_s
        );
end rtl;
