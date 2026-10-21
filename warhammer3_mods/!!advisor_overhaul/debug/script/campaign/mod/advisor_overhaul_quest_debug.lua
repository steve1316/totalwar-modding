--- Test switch for the Advisor quests. It is packed on its own into `!!advisor_overhaul_debug.pack`, never into the real pack.
--- Every quest opens at rank 1 with its real targets, so all six show in the missions list with their real requirements.
ADVISOR_OVERHAUL_QUEST_DEBUG = {
	--- The rank every quest opens at.
	rank = 1,
	--- Wins given at load against races not fought yet, so Edge of Final Counsel starts with lines. Greenskins is one win from done.
	races = { wh_main_sc_grn_greenskins = 4, wh_main_sc_vmp_vampire_counts = 2, wh_dlc03_sc_bst_beastmen = 1 },
}
