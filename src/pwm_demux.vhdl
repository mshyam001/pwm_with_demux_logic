library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity pwm is
  generic (
    WIDTH : positive := 10
  );
  port (
    clk          : in  std_logic;
    res_ni       : in  std_logic;
    set_thres_i  : in  unsigned(WIDTH-1 downto 0);
    clr_thres_i  : in  unsigned(WIDTH-1 downto 0);
    reload_i     : in  unsigned(WIDTH-1 downto 0);
    pwm_o        : out std_logic
  );
end entity pwm;

architecture rtl of pwm is
  constant ZERO_U : unsigned(WIDTH-1 downto 0) := (others => '0');

  signal cnt    : unsigned(WIDTH-1 downto 0) := (others => '0');
  signal pwm_q  : std_logic := '0';
begin
  process (clk, res_ni)
    variable next_cnt : unsigned(WIDTH-1 downto 0);
    variable next_pwm : std_logic;
  begin
    if res_ni = '0' then
      cnt   <= ZERO_U;
      pwm_q <= '0';
    elsif rising_edge(clk) then
      -- Counter next-state
      if cnt = reload_i then
        next_cnt := ZERO_U;      -- wrap to 0 at terminal count
      else
        next_cnt := cnt + 1;
      end if;

      -- PWM next-state (compare on current count)
      next_pwm := pwm_q;
      if cnt = clr_thres_i then
        next_pwm := '0';
      end if;
      if cnt = set_thres_i then
        next_pwm := '1';
      end if;

      cnt   <= next_cnt;
      pwm_q <= next_pwm;

      -- pragma translate_off
      if reload_i = ZERO_U then
        assert false report "pwm: reload_i = 0 -> counter stalls; use >= 1." severity warning;
      end if;
      -- pragma translate_on
    end if;
  end process;

  pwm_o <= pwm_q;
end architecture rtl;

-------------------------------------------------------------------------------
-- COMPACT CONFIG DEMUX WRAPPER
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity pwm_cfg_demux is
  port (
    clk       : in  std_logic;
    res_ni    : in  std_logic;

    -- 10-bit compact config interface
    data_i    : in  unsigned(9 downto 0);             -- shared 10-bit bus
    sel_i     : in  std_logic_vector(1 downto 0);     -- "00"=set, "01"=clear, "10"=reload
    wr_i      : in  std_logic;                        -- 1-cycle write strobe
    commit_i  : in  std_logic;                        -- atomic apply

    pwm_o     : out std_logic
  );
end entity pwm_cfg_demux;

architecture rtl of pwm_cfg_demux is
  -- Shadow registers (written by bus)
  signal set_shadow    : unsigned(9 downto 0) := (others => '0');
  signal clr_shadow    : unsigned(9 downto 0) := (others => '0');
  signal reload_shadow : unsigned(9 downto 0) := (others => '0');

  -- Active registers (drive PWM)
  signal set_active    : unsigned(9 downto 0) := (others => '0');
  signal clr_active    : unsigned(9 downto 0) := (others => '0');
  signal reload_active : unsigned(9 downto 0) := (others => '0');

  component pwm is
    generic ( WIDTH : positive := 10 );
    port (
      clk          : in  std_logic;
      res_ni       : in  std_logic;
      set_thres_i  : in  unsigned(WIDTH-1 downto 0);
      clr_thres_i  : in  unsigned(WIDTH-1 downto 0);
      reload_i     : in  unsigned(WIDTH-1 downto 0);
      pwm_o        : out std_logic
    );
  end component;
begin
  cfg_proc : process (clk, res_ni)
    variable set_v, clr_v, reload_v : unsigned(9 downto 0);
  begin
    if res_ni = '0' then
      set_shadow    <= (others => '0');
      clr_shadow    <= (others => '0');
      reload_shadow <= (others => '0');
      set_active    <= (others => '0');
      clr_active    <= (others => '0');
      reload_active <= (others => '0');

    elsif rising_edge(clk) then
      -- start from current shadows
      set_v    := set_shadow;
      clr_v    := clr_shadow;
      reload_v := reload_shadow;

      -- apply write to the selected shadow
      if wr_i = '1' then
        case sel_i is
          when "00" => set_v    := data_i;
          when "01" => clr_v    := data_i;
          when "10" => reload_v := data_i;
          when others => null; -- reserved/ignored
        end case;
      end if;

      -- update shadows
      set_shadow    <= set_v;
      clr_shadow    <= clr_v;
      reload_shadow <= reload_v;

      -- atomic commit (post-write values)
      if commit_i = '1' then
        set_active    <= set_v;
        clr_active    <= clr_v;
        reload_active <= reload_v;
      end if;

      -- pragma translate_off
      if wr_i = '1' then
        assert (sel_i = "00" or sel_i = "01" or sel_i = "10")
          report "pwm_cfg_demux: sel_i=""11"" (reserved) during wr_i=1; write ignored."
          severity warning;
      end if;
      -- pragma translate_on
    end if;
  end process;

  -- 10-bit PWM core
  u_pwm: pwm
    generic map ( WIDTH => 10 )
    port map (
      clk          => clk,
      res_ni       => res_ni,
      set_thres_i  => set_active,
      clr_thres_i  => clr_active,
      reload_i     => reload_active,
      pwm_o        => pwm_o
    );
end architecture rtl;
