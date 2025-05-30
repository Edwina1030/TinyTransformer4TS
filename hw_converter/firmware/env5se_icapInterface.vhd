library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
--! @brief Main entity for interfacing with the ICAP of the FPGA
entity icapInterface is
generic
(
	goldenboot_address	:	std_logic_vector(32 downto 0) := (others => '0')	--! Location in flash memory of the Golden boot image
);
port
(
	clk						:	in std_ulogic;	 						--! Clock
	reset					:   in std_ulogic;							--! Reset Async
	enable					:	in std_ulogic;	 						--! Synchronous enable line
	status_running 			:	out std_ulogic;						--! LED to show ICAP activity
	flash_unavailable		:	in std_ulogic;						--! Indicate whether flash can be accessed
	multiboot_address		:	in std_logic_vector(31 downto 0)	--! Address in flash memory of the configuration to switch to
);
end icapInterface;
architecture Behavioral of icapInterface is
type state_type is 
	(IDLE, WAITING_FLASH,DUMMY,SYNC,CMD_0,CMD_1,CMD_2,CMD_3,WRITE_CMD,IPROG);
attribute enum_encoding : string;
attribute enum_encoding of state_type : type is "0000 0001 0010 0011 0100 0101 0110 0111 1000 1001";
type state_type_vector is array (0 to 9) of state_type;
constant state_type_enum : state_type_vector := (IDLE, WAITING_FLASH, DUMMY, SYNC, CMD_0, CMD_1, CMD_2, CMD_3, WRITE_CMD, IPROG);
signal current_state 				: state_type := IDLE;
signal icap_in,icap_in_reorder 		: std_logic_vector(31 downto 0);
signal icap_ce 						: std_ulogic := '0';
begin
	state_transition : process(reset, clk)
	begin
		if reset = '1' then
			current_state <= IDLE;
		else
			if rising_edge(clk) then
				if current_state = IDLE then
					if enable = '1' then
						current_state <= WAITING_FLASH;
					end if;
				elsif current_state = WAITING_FLASH then
					if flash_unavailable = '0' then
						current_state <= DUMMY; -- start icap transaction
					end if;
				else
					current_state <= state_type_enum(state_type'pos(current_state) + 1);
				end if;
			end if;
		end if;
	end process;
    with current_state select icap_in <=
		x"FFFFFFFF" when IDLE,              
		x"FFFFFFFF" when DUMMY,             -- Dummy Word
		x"AA995566" when SYNC,              -- Sync Word
		x"20000000" when CMD_0,             -- Type 1 NO OP
		x"30020001" when CMD_1,				-- Type 1 Write 1 Words to WBSTAR
		multiboot_address when CMD_2,		-- Warm Boot Start Address (Load the Desired Address)
		x"30008001" when CMD_3,	            -- Type 1 Write 1 Words to CMD
		x"0000000F" when WRITE_CMD,         -- IPROG Command
		x"20000000" when IPROG,
		x"FFFFFFFF" when others;
	--! reorder icap_in to select_map standard
	gen: for I in 0 to 7 generate
		icap_in_reorder(I) <= icap_in(7 - I);
		icap_in_reorder(8 + I) <= icap_in(15 - I);
		icap_in_reorder(16 + I) <= icap_in(23 - I);
		icap_in_reorder(24 + I) <= icap_in(31 - I);
	end generate;
	-- led output
	icap_ce <= '0' when (current_state /= IDLE and current_state /= WAITING_FLASH) else '1';
	status_running <= not icap_ce;
end Behavioral;
