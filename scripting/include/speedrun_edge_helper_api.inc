#if defined _speedrun_edge_helper_api_included
    #endinput
#endif
#define _speedrun_edge_helper_api_included

#pragma semicolon 1

/**
 * @brief Sets the edge helper enabled state for a player.
 *
 * @param[in] id      Player index
 * @param[in] enabled True to enable the edge helper overlay for this player
 */
native sr_edge_helper_set_enabled(id, bool:enabled);
