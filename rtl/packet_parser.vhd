-- ------------------------------------------------------------------------------
-- Master's thesis: Hardware/software co-design for the new QUIC network protocol
-- ------------------------------------------------------------------------------
-- Stupid packet parser
--
-- File: .\rtl\packet_parser.vhd (vhdl)
-- By: Lowie Deferme (UHasselt/KULeuven - FIIW)
-- On: 25 May 2022
-- ------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.quic_offload_pkg.all;

entity packet_parser is
    generic (
        G_MD_IN_WIDTH : integer := 32;
        G_MD_OUT_WIDTH : integer := 32
    );
    port (
        -- Control ports
        clk : in std_logic;
        reset : in std_logic;
        -- Data
        d_in : in std_logic_vector(C_DATA_WIDTH-1 downto 0);
        d_out : out std_logic_vector(C_DATA_WIDTH-1 downto 0);
        -- Metadata
        md_in : in std_logic_vector(G_MD_IN_WIDTH-1 downto 0);
        md_out : out std_logic_vector(G_MD_OUT_WIDTH-1 downto 0)
    );
end packet_parser;

architecture behavioural of packet_parser is

    -- Amount of bytes in data bus
    constant C_DATA_BYTES : integer := C_DATA_WIDTH/8;

    -- (De)localised IO
    signal clk_i : std_logic;
    signal reset_i : std_logic;
    signal d_in_i : std_logic_vector(C_DATA_WIDTH-1 downto 0);
    signal d_out_i : std_logic_vector(C_DATA_WIDTH-1 downto 0);
    signal md_in_i : std_logic_vector(G_MD_IN_WIDTH-1 downto 0);
    signal md_out_i : std_logic_vector(G_MD_OUT_WIDTH-1 downto 0);

    -- Fsm states
    type T_fsm_state IS (R, P);  -- define states (Ready, Parsing,)
    signal fsm_state : T_fsm_state; -- fsm state signal

    -- Byte counter
    signal byte_ctr : std_logic_vector(11 downto 0); -- Maximum ethernet frame size is 1518 bytes which can be represented in 11 bits (no vlan, no jumbo frames)

    -- Metadata definitions (there are C_DATA_BYTES bytes in C_DATA_WIDTH)
    type T_proto_vec is array (C_DATA_BYTES-1 downto 0) of std_logic_vector(C_MS_PROTO-1 downto 0);
    signal proto_vec : T_proto_vec;
    type T_dcid_vec is array (C_DATA_BYTES-1 downto 0) of std_logic;
    signal dcid_vec : T_dcid_vec;
    type T_md_vec is array (C_DATA_BYTES-1 downto 0) of std_logic_vector(C_MS_PROTO + C_MS_DCID_PRESENT - 1 downto 0);
    signal md_vec : T_md_vec;

begin
    
    -----------------------------------------------------------------------------
    -- (De)localising IO
    -----------------------------------------------------------------------------
    clk_i <= clk;
    reset_i <= reset;
    d_in_i <= d_in;
    d_out <= d_out_i;
    md_in_i <= md_in;
    md_out <= md_out_i;

    -----------------------------------------------------------------------------
    -- Define metadata per byte
    -----------------------------------------------------------------------------

    -- Define metadata bits per byte
    G_MD_D: for i in 0 to C_DATA_BYTES-1 generate
        proto_vec(i) <= C_PROTO_ETHERNET when (unsigned(byte_ctr) + i) < 14 else
                        C_PROTO_IP when (unsigned(byte_ctr) + i) < 34 else
                        C_PROTO_UDP when (unsigned(byte_ctr) + i) < 42 else
                        C_PROTO_1RTT_QUIC; -- Fixme: When should protocol be C_PROTO_UNKNOWN or C_PROTO_PADDING?
        dcid_vec(i) <= '1' when ((unsigned(byte_ctr) + i) >= 43) and ((unsigned(byte_ctr) + i) < 63) else '0';
    end generate G_MD_D;

    -- Concatenate metadata bits per byte
    G_MD_F: for i in 0 to C_DATA_BYTES-1 generate
            md_vec(i) <= proto_vec(i) & dcid_vec(i);           
    end generate G_MD_F;

    -- Fill md_out by concatenating metadata per byte
    with fsm_state select md_out_i <=
        (others => '0') when R,
        md_vec(0) & md_vec(1) & md_vec(2) & md_vec(3) when P;
        
    -----------------------------------------------------------------------------
    -- Finite state machine
    -----------------------------------------------------------------------------
    P_FSM : process(clk_i, reset_i)
    begin
        if reset_i = '1' then
            fsm_state <= R;
        elsif rising_edge(clk_i) then
            case fsm_state is
                when R => fsm_state <= P; -- Todo: Only go to P when data valid
                when P => fsm_state <= P; -- Fixme: F is never reached
            end case;
        end if;
    end process ; -- P_FSM

    -----------------------------------------------------------------------------
    -- Data path
    -----------------------------------------------------------------------------
    d_out_i <= d_in_i; -- Since there is no latency in md_out_i there shouldn't be latency in d_out_i

    -----------------------------------------------------------------------------
    -- Byte counter
    -----------------------------------------------------------------------------
    P_BYTE_CLK : process(clk_i, reset_i)
    begin
        if reset_i = '1' then
            byte_ctr <= (others => '0');
        elsif rising_edge(clk_i) then
            case fsm_state is
                when R => byte_ctr <= (others => '0');
                when P => byte_ctr <= std_logic_vector(unsigned(byte_ctr) + 4 );
            end case;
        end if;
    end process ; -- P_BYTE_CLK
    
end architecture behavioural;
