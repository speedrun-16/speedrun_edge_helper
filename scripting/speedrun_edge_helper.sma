/**
 * Speedrun Edge Helper
 *
 * While the player is crouching on the ground, waits a short time and
 * draws a square around their crouch footprint if their
 * center point is hanging over an edge.
 */

#pragma semicolon 1
#pragma compress 1

#include <amxmodx>
#include <reapi>

#include <visual>

#define PLUGIN  "Speedrun: Edge Helper"
#define VERSION "1.0"
#define AUTHOR  "PWNED"

// ============================================================================
// CONSTANTS
// ============================================================================

#define EDGE_HELPER_MIN_GROUND_TIME 0.5
#define EDGE_HELPER_DRAW_INTERVAL   0.05
#define EDGE_HELPER_TRACE_DISTANCE  4096.0
#define EDGE_HELPER_Z_OFFSET        2.0
#define EDGE_HELPER_DRAW_INSET      1.0

#define EDGE_HELPER_BEAM_LIFE       1
#define EDGE_HELPER_BEAM_WIDTH      3
#define EDGE_HELPER_BEAM_BRIGHTNESS 90

// ============================================================================
// GLOBALS
// ============================================================================

new const g_edge_helper_color[3] = {205, 92, 92};

new bool:g_enabled[MAX_PLAYERS + 1];
new Float:g_started_on_ground[MAX_PLAYERS + 1];
new Float:g_next_draw_at[MAX_PLAYERS + 1];
new g_sprite_beam;

// ============================================================================
// LIFECYCLE
// ============================================================================

public plugin_natives()
{
    register_library("speedrun_edge_helper");
    register_native("sr_edge_helper_set_enabled", "@native_set_enabled");
}

public plugin_precache()
{
    g_sprite_beam = precache_model("sprites/laserbeam.spr");
    visual_set_sprite(g_sprite_beam);
}

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);
    RegisterHookChain(RG_CBasePlayer_PreThink, "@hc_cbaseplayer_prethink", true);
}

public client_putinserver(id)
{
    g_enabled[id] = false;
    reset_player_state(id);
}

public client_disconnected(id)
{
    g_enabled[id] = false;
    reset_player_state(id);
}

// ============================================================================
// NATIVE HANDLERS
// ============================================================================

@native_set_enabled(plugin_id, argc)
{
    new id       = get_param(1);
    new bool:val = bool:get_param(2);
    g_enabled[id] = val;
}

// ============================================================================
// HOOK CHAIN HANDLERS
// ============================================================================

public @hc_cbaseplayer_prethink(id)
{
    if (!is_user_alive(id) || is_user_bot(id))
    {
        reset_player_state(id);
        return HC_CONTINUE;
    }

    if (!g_enabled[id])
    {
        reset_player_state(id);
        return HC_CONTINUE;
    }

    new flags = get_entvar(id, var_flags);
    new buttons = get_entvar(id, var_button);

    if (!(flags & FL_ONGROUND) || !(buttons & IN_DUCK))
    {
        g_started_on_ground[id] = 0.0;
        g_next_draw_at[id] = 0.0;
        return HC_CONTINUE;
    }

    new Float:now = get_gametime();
    if (g_started_on_ground[id] == 0.0) {
        g_started_on_ground[id] = now;
    }

    if ((now - g_started_on_ground[id]) < EDGE_HELPER_MIN_GROUND_TIME || now < g_next_draw_at[id]) {
        return HC_CONTINUE;
    }

    g_next_draw_at[id] = now + EDGE_HELPER_DRAW_INTERVAL;

    new Float:abs_mins[3], Float:abs_maxs[3];
    if (!is_player_over_edge(id, abs_mins, abs_maxs)) {
        return HC_CONTINUE;
    }

    draw_edge_outline(id, abs_mins, abs_maxs);
    return HC_CONTINUE;
}

// ============================================================================
// STOCK UTILITIES
// ============================================================================

stock reset_player_state(id)
{
    g_started_on_ground[id] = 0.0;
    g_next_draw_at[id] = 0.0;
}

/**
 * @brief Checks whether the player's center point hangs over empty space.
 *
 * Traces straight down from the player's bottom center. Returns true only if
 * the floor hit point is below abs_mins[2] (example: center hanging past the edge).
 * abs_mins and abs_maxs are always filled, even when returning false.
 *
 * @param[in]  id        Client index
 * @param[out] abs_mins  Player bounding box minimum corner
 * @param[out] abs_maxs  Player bounding box maximum corner
 *
 * @return true if center point is over empty space, false otherwise
 */
stock bool:is_player_over_edge(id, Float:abs_mins[3], Float:abs_maxs[3])
{
    get_entvar(id, var_absmin, abs_mins);
    get_entvar(id, var_absmax, abs_maxs);

    new Float:trace_start[3], Float:trace_end[3], Float:hit_pos[3];
    trace_start[0] = (abs_mins[0] + abs_maxs[0]) * 0.5;
    trace_start[1] = (abs_mins[1] + abs_maxs[1]) * 0.5;
    trace_start[2] = abs_mins[2];

    trace_end[0] = trace_start[0];
    trace_end[1] = trace_start[1];
    trace_end[2] = trace_start[2] - EDGE_HELPER_TRACE_DISTANCE;

    new tr = create_tr2();
    engfunc(EngFunc_TraceLine, trace_start, trace_end, IGNORE_MONSTERS, id, tr);

    new Float:fraction;
    get_tr2(tr, TR_flFraction, fraction);
    if (fraction >= 1.0)
    {
        free_tr2(tr);
        return false;
    }

    get_tr2(tr, TR_vecEndPos, hit_pos);
    free_tr2(tr);

    return (trace_start[2] - hit_pos[2]) > 0.0;
}

/**
 * @brief Draws a beam square at floor level around the player's crouch footprint.
 *
 * Applies EDGE_HELPER_DRAW_INSET to shrink the outline slightly inside the
 * bounding box so beams don't clip into walls. Uses visual_draw_beam_generic
 * with player_id so the outline is only visible to that player.
 *
 * @param[in]  id        Client index - outline is sent only to this player
 * @param[in]  abs_mins  Player bounding box minimum corner
 * @param[in]  abs_maxs  Player bounding box maximum corner
 *
 * @noreturn
 */
stock draw_edge_outline(id, const Float:abs_mins[3], const Float:abs_maxs[3])
{
    new Float:p0[3], Float:p1[3], Float:p2[3], Float:p3[3];
    new Float:z = abs_mins[2] + EDGE_HELPER_Z_OFFSET;

    p0[0] = abs_mins[0] + EDGE_HELPER_DRAW_INSET; p0[1] = abs_mins[1] + EDGE_HELPER_DRAW_INSET; p0[2] = z;
    p1[0] = abs_maxs[0] - EDGE_HELPER_DRAW_INSET; p1[1] = abs_mins[1] + EDGE_HELPER_DRAW_INSET; p1[2] = z;
    p2[0] = abs_maxs[0] - EDGE_HELPER_DRAW_INSET; p2[1] = abs_maxs[1] - EDGE_HELPER_DRAW_INSET; p2[2] = z;
    p3[0] = abs_mins[0] + EDGE_HELPER_DRAW_INSET; p3[1] = abs_maxs[1] - EDGE_HELPER_DRAW_INSET; p3[2] = z;

    visual_draw_beam_generic(p0, p1, g_sprite_beam, g_edge_helper_color, EDGE_HELPER_BEAM_LIFE, EDGE_HELPER_BEAM_WIDTH, EDGE_HELPER_BEAM_BRIGHTNESS, 0, id);
    visual_draw_beam_generic(p1, p2, g_sprite_beam, g_edge_helper_color, EDGE_HELPER_BEAM_LIFE, EDGE_HELPER_BEAM_WIDTH, EDGE_HELPER_BEAM_BRIGHTNESS, 0, id);
    visual_draw_beam_generic(p2, p3, g_sprite_beam, g_edge_helper_color, EDGE_HELPER_BEAM_LIFE, EDGE_HELPER_BEAM_WIDTH, EDGE_HELPER_BEAM_BRIGHTNESS, 0, id);
    visual_draw_beam_generic(p3, p0, g_sprite_beam, g_edge_helper_color, EDGE_HELPER_BEAM_LIFE, EDGE_HELPER_BEAM_WIDTH, EDGE_HELPER_BEAM_BRIGHTNESS, 0, id);
}
