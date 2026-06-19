-- Paradox Combo — core logic (carrega antes de paradox_combo.lua)
ParadoxCombo = ParadoxCombo or {}

local UNIT_METER = 37.7358490566
local GRENADE_SLOT = 0
local WALL_SLOT    = 1
local CARBINE_SLOT = 2
local SWAP_SLOT    = 3
local FOV_RADIUS_SCALE = 6.5

local function require_mod(name)
    local ok, mod = pcall(require, name)
    return ok and mod or nil
end

local Utils = require_mod("utils")
local DC    = require_mod("damage_calc")
local KS    = require_mod("killstealer")
local Aim   = require_mod("aim")
local Prediction = require_mod("prediction")
ParadoxCombo.DC = DC

-- ─── Combo item registry ──────────────────────────────────────────────────────

local ITEM_PHASE = {
    POST_SWAP      = 1,
    POST_SWAP_CC   = 2,
    POST_SWAP_ECHO = 3,
    PRE_CARBINE    = 4,
    PASSIVE        = 5,
}

local COMBO_ITEMS = {
    {
        id = "mystic_vulnerability", name = "Mystic Vulnerability",
        patterns = { "mystic vulnerability", "upgrade_mystic_vulnerability", "mystic_vulnerability" },
        phase = ITEM_PHASE.POST_SWAP, order = 10, cast = true, needs_target = true,
        default_on = true, timing = "Post-Swap (before CC)",
        desc = "Reduces spirit resistance — amplifies grenade and carbine.",
    },
    {
        id = "silence_glyph", name = "Silence Wave",
        patterns = { "upgrade_targeted_silence", "silence wave", "silence_glyph", "targeted_silence" },
        phase = ITEM_PHASE.POST_SWAP, order = 20, cast = true, needs_target = true,
        default_on = true, timing = "Post-Swap",
        desc = "Silences the target so they cannot ability-escape the grenade.",
    },
    {
        id = "slowing_hex", name = "Slowing Hex",
        patterns = { "slowing hex", "upgrade_containment", "slowing_hex", "containment" },
        phase = ITEM_PHASE.POST_SWAP, order = 25, cast = true, needs_target = true,
        default_on = false, timing = "Post-Swap",
        desc = "Heavy slow — keeps enemy in the grenade area.",
    },
    {
        id = "magic_slow", name = "Mystic Slow",
        patterns = { "mystic slow", "upgrade_magic_slow", "magic_slow", "mystic_slow" },
        phase = ITEM_PHASE.POST_SWAP, order = 26, cast = true, needs_target = true,
        default_on = false, timing = "Post-Swap",
        desc = "Spirit slow alternative (do not use with Slowing Hex).",
    },
    {
        id = "knockdown", name = "Knockdown",
        patterns = { "knockdown", "upgrade_target_stun", "target_stun" },
        phase = ITEM_PHASE.POST_SWAP_CC, order = 30, cast = true, needs_target = true,
        default_on = true, timing = "Post-Swap (on grenade)",
        desc = "Delayed stun — locks enemy in grenade pulses.",
    },
    {
        id = "echo_shard", name = "Echo Shard",
        patterns = { "echo shard", "upgrade_ability_power_shard", "echo_shard", "ability_power_shard" },
        phase = ITEM_PHASE.POST_SWAP_ECHO, order = 35, cast = true, needs_target = false,
        default_on = false, timing = "After Knockdown",
        desc = "Echoes the last ability (knockdown or debuff). Use right after CC.",
    },
    {
        id = "infuser", name = "Infuser",
        patterns = { "infuser", "upgrade_infuser" },
        phase = ITEM_PHASE.PRE_CARBINE, order = 40, cast = true, needs_target = false,
        default_on = true, timing = "Pre-Carbine",
        desc = "Spirit power spike before the headshot.",
    },
    {
        id = "unstoppable", name = "Unstoppable",
        patterns = { "unstoppable", "upgrade_unstoppable" },
        phase = ITEM_PHASE.PRE_CARBINE, order = 45, cast = true, needs_target = false,
        default_on = false, timing = "Start of Carbine charge",
        desc = "Immune to interrupts during C charge.",
    },
    {
        id = "mystic_burst", name = "Mystic Burst",
        patterns = { "mystic burst", "upgrade_magic_burst", "magic_burst", "mystic_burst" },
        phase = ITEM_PHASE.PASSIVE, order = 50, cast = false, needs_target = false,
        default_on = true, timing = "On Carbine proc",
        desc = "Extra burst on big hit — included in lethal damage calc.",
    },
    {
        id = "spirit_burn", name = "Spirit Burn",
        patterns = { "spirit burn", "upgrade_spirit_burn", "spirit_burn" },
        phase = ITEM_PHASE.PASSIVE, order = 51, cast = false, needs_target = false,
        default_on = true, timing = "On Carbine proc",
        desc = "Spirit DoT after high damage.",
    },
    {
        id = "tank_buster", name = "Tankbuster",
        patterns = { "tankbuster", "upgrade_magic_shock", "magic_shock", "tank_buster" },
        phase = ITEM_PHASE.PASSIVE, order = 52, cast = false, needs_target = false,
        default_on = true, timing = "On Carbine proc",
        desc = "Extra proc vs high-HP targets.",
    },
    {
        id = "headshot_booster", name = "Headshot Booster",
        patterns = { "headshot booster", "upgrade_headshot_booster", "headshot_booster" },
        phase = ITEM_PHASE.PASSIVE, order = 60, cast = false, needs_target = false,
        weapon_finisher = true, default_on = true, timing = "Passive (Carbine HS)",
        desc = "Extra headshot damage — tracked in Carbine killsteal.",
    },
    {
        id = "glass_cannon", name = "Glass Cannon",
        patterns = { "glass cannon", "upgrade_glass_cannon", "glass_cannon" },
        phase = ITEM_PHASE.PASSIVE, order = 61, cast = false, needs_target = false,
        weapon_finisher = true, default_on = true, timing = "Passive (weapon amp)",
        desc = "+weapon damage — amps Carbine base portion in lethal calc.",
    },
    {
        id = "crippling_headshot", name = "Crippling Headshot",
        patterns = { "crippling headshot", "crippling_headshot" },
        phase = ITEM_PHASE.PASSIVE, order = 62, cast = false, needs_target = false,
        weapon_finisher = true, default_on = true, timing = "Passive (headshot)",
        desc = "Headshot amp on Carbine finisher — included in lethal calc.",
    },
    {
        id = "hollow_point", name = "Hollow Point",
        patterns = { "hollow point", "upgrade_hollow_point_rounds", "hollow_point" },
        phase = ITEM_PHASE.PASSIVE, order = 63, cast = false, needs_target = false,
        weapon_finisher = true, default_on = true, timing = "Passive (low HP)",
        desc = "Bonus weapon damage vs low-HP targets on Carbine finisher.",
    },
    {
        id = "mystic_reverb", name = "Mystic Reverb",
        patterns = { "mystic reverb", "upgrade_mystic_reverb", "mystic_reverb" },
        phase = ITEM_PHASE.PASSIVE, order = 64, cast = false, needs_target = false,
        default_on = false, timing = "Imbue Carbine (manual)",
        desc = "Imbue Carbine for AoE slow — track in build; AoE not in calc yet.",
    },
}
ParadoxCombo.COMBO_ITEMS = COMBO_ITEMS

-- UI refs (definidos por paradox_combo.lua após o menu)
local ui, ui_i, ui_a, ui_item

function ParadoxCombo.bind_menu(u, u_i, u_a, u_item_tbl, u_build)
    ui = u
    ui_i = u_i
    ui_a = u_a
    ui_item = u_item_tbl
    if ParadoxWall and ParadoxWall.bind_menu then
        ParadoxWall.bind_menu(u, u_a)
    end
    if ParadoxSwap and ParadoxSwap.bind_menu then
        ParadoxSwap.bind_menu(u_a)
    end
    if ParadoxBuild and ParadoxBuild.bind_menu and u_build then
        ParadoxBuild.bind_menu(u_build)
    end
end

-- ─── State ──────────────────────────────────────────────────────────────────

local S = {
    IDLE         = "IDLE",
    ACQUIRE_AIM  = "ACQUIRE_AIM",
    AIM_DOWN     = "AIM_DOWN",
    CAST         = "CAST",
    RESTORE_AIM  = "RESTORE_AIM",
    WALL_AIM     = "WALL_AIM",
    WALL_SELECT  = "WALL_SELECT",
    WALL_CONFIRM = "WALL_CONFIRM",
    SWAP_AIM     = "SWAP_AIM",
    SWAP_CAST      = "SWAP_CAST",
    DONE           = "DONE",
    ITEMS_AIM      = "ITEMS_AIM",
    ITEMS_CAST     = "ITEMS_CAST",
    CARBINE_CHARGE = "CARBINE_CHARGE",
    CARBINE_FIRE   = "CARBINE_FIRE",
}

local AS = {
    IDLE   = "IDLE",
    CHARGE = "CHARGE",
    FIRE   = "FIRE",
}

local GS = {
    IDLE    = "IDLE",
    AIM     = "AIM",
    CAST    = "CAST",
    RESTORE = "RESTORE",
}

local state = {
    phase       = S.IDLE,
    t0          = 0,
    aim_pos     = nil,
    ground_pos  = nil,
    pitch_deg   = 0,
    locked_yaw  = nil,
    saved_pitch = nil,
    saved_yaw   = nil,
    user_pitch  = nil,
    user_yaw    = nil,
    target      = nil,
    wall_pos    = nil,
    track_until = 0,
    charge_t0   = 0,
    item_segment = "",
    item_queue  = {},
    item_index  = 0,
    loadout     = {},
    release_until = 0,
    last_msg    = "",
}

function ParadoxCombo.is_combo_active()
    return state.phase ~= S.IDLE
end

local assist = {
    carbine = {
        phase = AS.IDLE, t0 = 0, charge_t0 = 0, target = nil, msg = "",
        last_pred = nil, last_pred_hp = 0,
    },
    grenade = {
        phase = GS.IDLE, t0 = 0, target = nil, msg = "",
        saved_pitch = nil, saved_yaw = nil, feet_pos = nil, lead_t = 0,
    },
}


local font_hud  = nil
local font_mono = nil
local is_paradox = false
local last_hero_idx = -1
local pitch_down_sign = nil  -- +1 ou -1, detectado via Angle:GetForward()

-- ─── Helpers ──────────────────────────────────────────────────────────────────

local function safe(fn)
    local ok, v = pcall(fn)
    return ok and v or nil
end

local SLOT_MASK = {
    [GRENADE_SLOT] = InputBitMask_t.IN_ABILITY1,
    [WALL_SLOT]    = InputBitMask_t.IN_ABILITY2,
    [CARBINE_SLOT] = InputBitMask_t.IN_ABILITY3,
    [SWAP_SLOT]    = InputBitMask_t.IN_ABILITY4,
}

local ITEM_SLOT_FIRST = (EAbilitySlots_t and EAbilitySlots_t.ESlot_ActiveItem_First) or 4
local ITEM_INPUT_BY_IDX = {
    [1] = InputBitMask_t.IN_ITEM1,
    [2] = InputBitMask_t.IN_ITEM2,
    [3] = InputBitMask_t.IN_ITEM3,
    [4] = InputBitMask_t.IN_ITEM4,
}

local COMBO_ITEM_BY_ID = {}
for i = 1, #COMBO_ITEMS do
    COMBO_ITEM_BY_ID[COMBO_ITEMS[i].id] = COMBO_ITEMS[i]
end

local loadout_cache = { t = -1, lp = nil, slots = {}, by_id = {} }

local function item_name_matches(name, patterns)
    if not name or not patterns then return false end
    local ln = string.lower(name)
    for i = 1, #patterns do
        if string.find(ln, string.lower(patterns[i]), 1, true) then
            return true
        end
    end
    return false
end

local function get_item_def(id)
    return COMBO_ITEM_BY_ID[id]
end

local function item_use_enabled(def)
    if not def or not def.cast then return false end
    if not ui_i or not ui_i.enable or not ui_i.enable:Get() then return false end
    if not ui_item then return false end
    local w = ui_item[def.id]
    return w and w.use and w.use:Get() or false
end

local function weapon_finisher_enabled(def)
    if not def or not def.weapon_finisher then return false end
    local w = ui_item and ui_item[def.id]
    if w and w.track then return w.track:Get() end
    return def.default_on ~= false
end

local function carbine_weapon_passives_enabled()
    local out = {}
    for i = 1, #COMBO_ITEMS do
        local def = COMBO_ITEMS[i]
        if def.weapon_finisher then
            out[def.id] = weapon_finisher_enabled(def)
        end
    end
    return out
end

local function item_slot_ready(lp, slot)
    local ab = safe(function() return lp:get_ability_by_slot(slot) end)
    if not ab or not ab:valid() then return false end
    local st = safe(function() return ab:can_be_executed() end)
    if st == 0 or st == true or st == 23 then return true end
    local cd = safe(function() return ab:get_cooldown() end)
    return cd ~= nil and cd <= 0.05
end

local function item_status(lp, slot)
    local ab = safe(function() return lp:get_ability_by_slot(slot) end)
    if not ab or not ab:valid() then return "nil" end
    local st = safe(function() return ab:can_be_executed() end)
    if st == 0 then return "ready" end
    if st == 2 then return "cd" end
    if st == 10 then return "busy" end
    return "st=" .. tostring(st)
end

local function scan_item_slots(lp)
    local t = safe(function() return global_vars.framecount() end) or global_vars.curtime()
    if loadout_cache.t == t and loadout_cache.lp == lp then
        return loadout_cache.slots, loadout_cache.by_id
    end

    local slots = {}
    local by_id = {}

    for i = 0, 3 do
        local slot = ITEM_SLOT_FIRST + i
        local ab = safe(function() return lp:get_ability_by_slot(slot) end)
        local entry = {
            slot = slot,
            idx = i + 1,
            name = nil,
            ready = false,
            status = "empty",
            cd = 0,
        }
        if ab and ab:valid() then
            entry.name = safe(function() return ab:get_name() end)
            entry.status = item_status(lp, slot)
            entry.ready = item_slot_ready(lp, slot)
            entry.cd = safe(function() return ab:get_cooldown() end) or 0
        end
        slots[i + 1] = entry

        if entry.name then
            for j = 1, #COMBO_ITEMS do
                local def = COMBO_ITEMS[j]
                if def and def.id and def.patterns
                    and item_name_matches(entry.name, def.patterns) and not by_id[def.id] then
                    by_id[def.id] = {
                        def = def,
                        slot = slot,
                        idx = i + 1,
                        name = entry.name,
                        ready = entry.ready,
                        status = entry.status,
                        cd = entry.cd,
                    }
                end
            end
        end
    end

    local ok_abs, abs = pcall(lp.get_abilities, lp)
    if ok_abs and abs then
        for i = 1, #abs do
            local ab = abs[i]
            if ab and ab:valid() then
                local name = safe(function() return ab:get_name() end)
                if name then
                    for j = 1, #COMBO_ITEMS do
                        local def = COMBO_ITEMS[j]
                        if def and def.id and def.patterns
                            and not by_id[def.id] and item_name_matches(name, def.patterns) then
                            by_id[def.id] = {
                                def = def,
                                slot = nil,
                                idx = 0,
                                name = name,
                                ready = true,
                                status = "passive",
                                cd = 0,
                            }
                        end
                    end
                end
            end
        end
    end

    loadout_cache = { t = t, lp = lp, slots = slots, by_id = by_id }
    return slots, by_id
end

local function find_owned_item(lp, def)
    local _, by_id = scan_item_slots(lp)
    return by_id[def.id]
end

local function build_item_queue(lp, phase_from, phase_to)
    local queue = {}
    if not ui_i or not ui_i.enable or not ui_i.enable:Get() then return queue end

    local _, by_id = scan_item_slots(lp)
    for i = 1, #COMBO_ITEMS do
        local def = COMBO_ITEMS[i]
        if def.cast and def.phase >= phase_from and def.phase <= phase_to and item_use_enabled(def) then
            local owned = by_id[def.id]
            if owned and owned.ready then
                queue[#queue + 1] = {
                    def = def,
                    slot = owned.slot,
                    idx = owned.idx,
                    name = owned.name,
                }
            end
        end
    end

    table.sort(queue, function(a, b)
        return a.def.order < b.def.order
    end)
    return queue
end

local function current_item_entry()
    if not state.item_queue or state.item_index < 1 then return nil end
    return state.item_queue[state.item_index]
end

local function item_phase_delay(def)
    if not def or not ui_i then return 0 end
    if def.phase == ITEM_PHASE.PRE_CARBINE then
        return (ui_i.pre_carbine_delay_ms and ui_i.pre_carbine_delay_ms:Get() or 60) / 1000.0
    end
    return (ui_i.post_swap_delay_ms and ui_i.post_swap_delay_ms:Get() or 350) / 1000.0
end

local function clear_item_slots(cmd)
    pcall(function() cmd:clear_buttonstate1(InputBitMask_t.IN_ITEM1) end)
    pcall(function() cmd:clear_buttonstate1(InputBitMask_t.IN_ITEM2) end)
    pcall(function() cmd:clear_buttonstate1(InputBitMask_t.IN_ITEM3) end)
    pcall(function() cmd:clear_buttonstate1(InputBitMask_t.IN_ITEM4) end)
    if cmd.clear_buttonstate2 then
        pcall(function() cmd:clear_buttonstate2(InputBitMask_t.IN_ITEM1) end)
        pcall(function() cmd:clear_buttonstate2(InputBitMask_t.IN_ITEM2) end)
        pcall(function() cmd:clear_buttonstate2(InputBitMask_t.IN_ITEM3) end)
        pcall(function() cmd:clear_buttonstate2(InputBitMask_t.IN_ITEM4) end)
    end
    if cmd.execute_ability_indices ~= nil then
        for s = ITEM_SLOT_FIRST, ITEM_SLOT_FIRST + 3 do
            cmd.execute_ability_indices = cmd.execute_ability_indices & ~(1 << s)
        end
    end
end

local function press_item_slot(cmd, item_idx, ability_slot)
    local mask = ITEM_INPUT_BY_IDX[item_idx]
    if mask then
        cmd:add_buttonstate1(mask)
        if cmd.add_buttonstate2 then cmd:add_buttonstate2(mask) end
    end
    local cast_bit = ability_slot
    if cast_bit == nil and item_idx then
        cast_bit = ITEM_SLOT_FIRST + (item_idx - 1)
    end
    if cast_bit ~= nil then
        cmd.execute_ability_indices = (cmd.execute_ability_indices or 0) | (1 << cast_bit)
    end
end

local function is_cast_locked(lp)
    for i = 0, 3 do
        local ab = safe(function() return lp:get_ability_by_slot(i) end)
        if ab and ab:valid() then
            if ab.m_bInCastDelay then return true end
            if ab.m_bChanneling then return true end
        end
    end
    return false
end

local function is_enemy(lp, ent)
    if not lp or not ent or not ent:valid() or not ent:is_alive() then return false end
    return lp.m_iTeamNum ~= ent.m_iTeamNum
end

local function get_pitch_down_sign()
    if pitch_down_sign ~= nil then return pitch_down_sign end
    for _, test_pitch in ipairs({ 89, -89 }) do
        local fwd = safe(function() return Angle(test_pitch, 0, 0):GetForward() end)
        if fwd and fwd.z < -0.5 then
            pitch_down_sign = test_pitch > 0 and 1 or -1
            return pitch_down_sign
        end
    end
    pitch_down_sign = 1
    return pitch_down_sign
end

local function resolve_down_pitch()
    local sign = get_pitch_down_sign()
    local mag  = ui.max_pitch:Get()
    if mag < 0 then mag = -mag end
    if mag > 89 then mag = 89 end
    return sign * mag
end

local function angles_to_forward(pitch_deg, yaw_deg)
    local fwd = safe(function() return Angle(pitch_deg, yaw_deg, 0):GetForward() end)
    if fwd then return fwd end
    local pr = math.rad(pitch_deg)
    local yr = math.rad(yaw_deg)
    return Vector(
        math.cos(pr) * math.cos(yr),
        math.cos(pr) * math.sin(yr),
        -math.sin(pr)
    )
end

local function elapsed()
    return global_vars.curtime() - state.t0
end

local function set_phase(phase)
    state.phase = phase
    state.t0    = global_vars.curtime()
end

local function clear_primary_attack(cmd)
    pcall(function() cmd:clear_buttonstate1(InputBitMask_t.IN_ATTACK) end)
    if cmd.clear_buttonstate2 then pcall(function() cmd:clear_buttonstate2(InputBitMask_t.IN_ATTACK) end) end
end


local function ability_status(lp, slot)
    local ab = safe(function() return lp:get_ability_by_slot(slot) end)
    if not ab or not ab:valid() then return "nil" end
    local st = safe(function() return ab:can_be_executed() end)
    if st == 0 then return "ready" end
    if st == 2 then return "cd" end
    if st == 10 then return "busy" end
    return "st=" .. tostring(st)
end

local function press_slot(cmd, slot)
    local mask = (slot == 0 and InputBitMask_t.IN_ABILITY1)
        or (slot == 1 and InputBitMask_t.IN_ABILITY2)
        or (slot == 2 and InputBitMask_t.IN_ABILITY3)
        or (slot == 3 and InputBitMask_t.IN_ABILITY4)
    if not mask then return end
    cmd:add_buttonstate1(mask)
    if cmd.add_buttonstate2 then cmd:add_buttonstate2(mask) end
    cmd.execute_ability_indices = (cmd.execute_ability_indices or 0) | (1 << slot)
end

local function clear_slot(cmd, slot)
    local mask = (slot == 0 and InputBitMask_t.IN_ABILITY1)
        or (slot == 1 and InputBitMask_t.IN_ABILITY2)
        or (slot == 2 and InputBitMask_t.IN_ABILITY3)
        or (slot == 3 and InputBitMask_t.IN_ABILITY4)
    if not mask then return end
    pcall(function() cmd:clear_buttonstate1(mask) end)
    if cmd.clear_buttonstate2 then pcall(function() cmd:clear_buttonstate2(mask) end) end
end

local function get_current_angles()
    local cam_ang = safe(function() return utils.get_camera_angles() end)
    if not cam_ang then return nil, nil end
    local pitch = cam_ang.pitch or cam_ang.x or 0
    local yaw   = cam_ang.yaw or cam_ang.y or 0
    return pitch, yaw
end

local function get_current_pitch()
    local pitch = get_current_angles()
    return pitch
end

local function normalize_yaw_delta(a, b)
    local d = a - b
    while d > 180 do d = d - 360 end
    while d < -180 do d = d + 360 end
    return d
end

local function capture_user_aim(cmd)
    local cam_ang = cmd.orig_ang_camera_angles
        or safe(function() return utils.get_camera_angles() end)
        or cmd.viewangles
    if not cam_ang then return false end
    state.user_pitch = cam_ang.pitch or cam_ang.x or 0
    state.user_yaw   = cam_ang.yaw or cam_ang.y or 0
    return true
end

local function capture_saved_aim(cmd)
    local cam_ang = safe(function() return utils.get_camera_angles() end) or cmd.viewangles
    if not cam_ang then return false end
    state.saved_pitch = cam_ang.pitch or cam_ang.x or 0
    state.saved_yaw   = cam_ang.yaw or cam_ang.y or 0
    state.locked_yaw  = state.saved_yaw
    return true
end

local function apply_cmd_aim(cmd, pitch, yaw)
    local ang = Angle(pitch, yaw, 0)
    cmd.viewangles = ang
    pcall(function() cmd.ang_camera_angles = ang end)
    local cam = cmd.orig_vec_camera_position or safe(function() return utils.get_camera_pos() end)
    if cam then pcall(function() cmd.vec_camera_position = cam end) end
    state.pitch_deg = pitch
end

-- move_visible=true só quando a câmera precisa mover de verdade (granada/restore).
local function apply_view_angles(cmd, pitch, yaw, move_visible)
    apply_cmd_aim(cmd, pitch, yaw)
    if move_visible and utils.set_camera_angles then
        utils.set_camera_angles(Angle(pitch, yaw, 0))
    end
end

local function get_target_bone_pos(target)
    return safe(function() return target:get_bone_pos("spine_2") end)
        or safe(function() return target:get_bone_pos("pelvis") end)
        or safe(function() return target:get_origin() end)
end

local function find_target_in_crosshair(lp, cmd, max_fov)
    local cam = (cmd and cmd.orig_vec_camera_position) or safe(function() return utils.get_camera_pos() end)
    local cam_ang = safe(function() return utils.get_camera_angles() end)
        or (cmd and cmd.viewangles)
    if not cam or not cam_ang then return nil end

    local best, best_fov = nil, max_fov or 30
    for _, pawn in ipairs(entity_list.by_class_name("C_CitadelPlayerPawn")) do
        if is_enemy(lp, pawn) then
            local pos = get_target_bone_pos(pawn)
            if pos then
                local ang = utils.calc_angle(cam, pos)
                local fov = utils.get_fov(cam_ang, ang)
                if fov < best_fov then
                    best_fov = fov
                    best = pawn
                end
            end
        end
    end
    return best
end

local function get_locked_target(lp, cmd)
    if state.target and state.target:valid() and state.target:is_alive() and is_enemy(lp, state.target) then
        return state.target
    end
    local acquired = find_target_in_crosshair(lp, cmd, ui.track_fov:Get())
    if acquired then state.target = acquired end
    return acquired
end

local function get_view_angles(cmd)
    if cmd and cmd.viewangles then
        local a = cmd.viewangles
        return a.pitch or a.x or 0, a.yaw or a.y or 0
    end
    return get_current_angles()
end

local function is_tracking_on_target(lp, cmd, max_fov)
    local target = get_locked_target(lp, cmd)
    if not target then return false end
    local pos = get_target_bone_pos(target)
    local cam = (cmd and cmd.orig_vec_camera_position) or safe(function() return utils.get_camera_pos() end)
    if not pos or not cam then return false end

    local cam_p, cam_y = get_view_angles(cmd)
    if cam_p == nil or cam_y == nil then return false end

    local ang = utils.calc_angle(cam, pos)
    local check_ang = Angle(cam_p, cam_y, 0)
    return utils.get_fov(check_ang, ang) <= (max_fov or 10)
end

local function is_acquire_ready(lp, cmd)
    if elapsed() < ui.acquire_delay_ms:Get() / 1000.0 then return false end
    return is_tracking_on_target(lp, cmd, ui.acquire_tol:Get())
end

local function is_acquire_failed()
    return elapsed() >= ui.acquire_timeout_ms:Get() / 1000.0
end

local function get_head_aim_pos(target)
    return safe(function() return target:get_bone_pos("head") end)
        or safe(function() return target:get_bone_pos("neck_0") end)
        or get_target_bone_pos(target)
end

local function apply_track_head(cmd, lp)
    local target = get_locked_target(lp, cmd)
    if not target then
        if state.saved_pitch == nil or state.saved_yaw == nil then return false end
        apply_cmd_aim(cmd, state.saved_pitch, state.saved_yaw)
        return true
    end

    local pos = get_head_aim_pos(target)
    if not pos then return false end

    if ui.carbine_psilent:Get() and safe(function() return cmd:can_psilent_at_pos(pos) end) then
        pcall(function() cmd:set_psilent_at_pos(pos) end)
        state.last_msg = "track head: psilent"
        return true
    end

    local cam = cmd.orig_vec_camera_position or safe(function() return utils.get_camera_pos() end)
    if not cam then return false end

    local ang = utils.calc_angle(cam, pos)
    local pitch = ang.pitch or ang.x or 0
    local yaw   = ang.yaw or ang.y or 0
    apply_cmd_aim(cmd, pitch, yaw)
    state.saved_pitch = pitch
    state.saved_yaw   = yaw
    state.last_msg = string.format("track head: pitch=%.1f° yaw=%.1f°", pitch, yaw)
    return true
end

local function press_attack(cmd)
    cmd:add_buttonstate1(InputBitMask_t.IN_ATTACK)
    if cmd.add_buttonstate2 then cmd:add_buttonstate2(InputBitMask_t.IN_ATTACK) end
end

local function apply_track_target(cmd, lp)
    local target = get_locked_target(lp, cmd)
    if not target then
        if state.saved_pitch == nil or state.saved_yaw == nil then return false end
        apply_cmd_aim(cmd, state.saved_pitch, state.saved_yaw)
        return true
    end

    local pos = get_target_bone_pos(target)
    if not pos then
        if state.saved_pitch == nil or state.saved_yaw == nil then return false end
        apply_cmd_aim(cmd, state.saved_pitch, state.saved_yaw)
        return true
    end

    if ui.swap_psilent:Get() then
        local bones = { "spine_2", "pelvis", "spine_0", "neck_0", "head" }
        for i = 1, #bones do
            local bpos = safe(function() return target:get_bone_pos(bones[i]) end) or (bones[i] == "spine_2" and pos)
            if bpos and safe(function() return cmd:can_psilent_at_pos(bpos) end) then
                pcall(function() cmd:set_psilent_at_pos(bpos) end)
                local name = safe(function() return target:get_name() end) or "?"
                state.last_msg = string.format("track: %s psilent (%s)", name, bones[i])
                return true
            end
        end
    end

    local cam = cmd.orig_vec_camera_position or safe(function() return utils.get_camera_pos() end)
    if not cam then return false end

    local ang = utils.calc_angle(cam, pos)
    local pitch = ang.pitch or ang.x or 0
    local yaw   = ang.yaw or ang.y or 0
    apply_cmd_aim(cmd, pitch, yaw)
    state.saved_pitch = pitch
    state.saved_yaw   = yaw

    local name = safe(function() return target:get_name() end) or "?"
    state.last_msg = string.format("track: %s pitch=%.1f° yaw=%.1f°", name, pitch, yaw)
    return true
end

local function should_keep_tracking()
    return state.track_until > 0 and global_vars.curtime() < state.track_until
end

local function start_swap_tracking()
    state.track_until = global_vars.curtime() + ui.swap_track_ms:Get() / 1000.0
end

local function is_aim_settled()
    local delay = ui.aim_delay_ms:Get() / 1000.0
    if elapsed() < delay then return false end

    local target = resolve_down_pitch()
    if math.abs((state.pitch_deg or 0) - target) > 0.5 then return false end

    local current_p = get_current_pitch()
    if current_p == nil then return true end
    if math.abs(current_p - target) < 12.0 then return true end

    -- câmera ainda apontando pra cima: espera o snap visível, mas não trava o combo
    return elapsed() >= math.max(delay + 0.12, 0.25)
end

local function is_restore_settled()
    if state.saved_pitch == nil or state.saved_yaw == nil then return true end
    local current_p, current_y = get_current_angles()
    if current_p == nil or current_y == nil then return elapsed() >= 0.03 end
    local tol = ui.restore_tol:Get()
    local pitch_ok = math.abs(current_p - state.saved_pitch) < tol
    local yaw_ok   = math.abs(normalize_yaw_delta(current_y, state.saved_yaw)) < tol
    return pitch_ok and yaw_ok
end

local function slot_ready(lp, slot)
    local ab = safe(function() return lp:get_ability_by_slot(slot) end)
    return ab and ab:valid() and ab:can_be_executed() == 0
end

-- ─── Carbine damage / killsteal ─────────────────────────────────────────────

local carbine_props_cache = { t = -1, ab = nil, props = nil }

local function read_ab_scaled(ab, key, def)
    if not ab or not ab:valid() then return def or 0 end
    local ok, v = pcall(ab.get_scaled_property, ab, key)
    if ok and type(v) == "number" then return v end
    return def or 0
end

local function get_carbine_ability(lp)
    return safe(function() return lp:get_ability_by_slot(CARBINE_SLOT) end)
        or safe(function() return lp:get_ability("citadel_ability_chrono_kinetic_carbine") end)
end

local function get_carbine_props(ab)
    if not ab or not ab:valid() then return nil end
    local t = safe(function() return global_vars.framecount() end) or global_vars.curtime()
    if carbine_props_cache.t == t and carbine_props_cache.ab == ab then
        return carbine_props_cache.props
    end

    local spirit_base = read_ab_scaled(ab, "Damage", 0)
    if spirit_base <= 0 then
        for _, key in ipairs({ "TechDamage", "SpiritDamage", "PulseDamage" }) do
            local v = read_ab_scaled(ab, key, 0)
            if v > 0 then spirit_base = v; break end
        end
    end

    local props = {
        base_bullet = read_ab_scaled(ab, "BaseBulletDamage", 5),
        min_bonus   = read_ab_scaled(ab, "MinBonusBulletDamage", 5),
        max_bonus   = read_ab_scaled(ab, "MaxBonusBulletDamage", 5),
        hs_bonus    = read_ab_scaled(ab, "HeadshotBonus", 14) / 100.0,
        max_charge  = math.max(0.05, read_ab_scaled(ab, "MaxChargeDuration", 2.5)),
        spirit_base = spirit_base,
    }
    carbine_props_cache = { t = t, ab = ab, props = props }
    return props
end

local function target_ehp(target)
    if not target or not target:valid() then return 0 end
    local hp = target.m_iHealth or 0
    local shield = target.m_iTechShield or target.m_flTechShield or 0
    if type(shield) ~= "number" then shield = 0 end
    return hp + shield
end

local function is_bad_kill_target(target)
    if not target or not target:valid() or not target:is_alive() then return true end
    if Utils and Utils.IsWastedTarget and Utils.IsWastedTarget(target) then return true end
    if KS and KS.HasReadyCounterspell and KS.HasReadyCounterspell(target) then return true end
    return false
end

local function carbine_charge_frac(charge_t0, max_charge_s, configured_ms)
    if not charge_t0 or charge_t0 <= 0 then return 0 end
    local elapsed = global_vars.curtime() - charge_t0
    local full = math.max(0.05, max_charge_s or 2.5)
    if configured_ms and configured_ms > 0 then
        full = math.max(full, configured_ms / 1000.0)
    end
    if elapsed <= 0 then return 0 end
    if elapsed >= full then return 1 end
    return elapsed / full
end

local function carbine_damage_pool(props, charge_frac, headshot)
    local frac = charge_frac or 0
    if frac < 0 then frac = 0 end
    if frac > 1 then frac = 1 end
    local bonus = props.min_bonus + (props.max_bonus - props.min_bonus) * frac
    local pool = props.base_bullet + bonus
    if headshot ~= false then pool = pool * (1 + props.hs_bonus) end
    return pool, frac
end

local function predict_carbine_damage(lp, ab, target, charge_frac, headshot)
    if not DC or not lp or not ab or not target or not target:valid() then return nil end
    local props = get_carbine_props(ab)
    if not props then return nil end

    local pool, frac = carbine_damage_pool(props, charge_frac, headshot)
    if pool <= 0 then return nil end

    local pred
    local ok_pred, pred_err = pcall(function()
        if DC.PredictCarbineKill then
            return DC.PredictCarbineKill(lp, ab, target, {
                carbine_props   = props,
                charge_frac     = charge_frac,
                headshot        = headshot,
                safety_factor   = 1.0,
                enabled_weapons = carbine_weapon_passives_enabled(),
            })
        end
        return DC.PredictAbilityKill(lp, ab, target, {
            damage_type   = "spirit",
            safety_factor = 1.0,
            base_damage   = pool,
        })
    end)
    if not ok_pred then
        pred = { total = 0, total_safe = 0, raw = pool, lethal = false, lethal_safe = false }
    else
        pred = pred_err
    end

    return {
        total      = pred.total or 0,
        total_safe = pred.total_safe or 0,
        raw        = pred.raw or pool,
        lethal     = pred.lethal,
        lethal_safe = pred.lethal_safe,
        charge_pct = math.floor(frac * 100 + 0.5),
        pool       = pool,
    }
end

local function is_carbine_lethal(lp, ab, target, charge_frac, safety_pct, headshot)
    if is_bad_kill_target(target) then return false, nil end
    local pred = predict_carbine_damage(lp, ab, target, charge_frac, headshot)
    if not pred then return false, nil end
    local safety = (safety_pct or 92) / 100.0
    if safety > 1 then safety = 1 end
    if safety < 0 then safety = 0 end
    local need = target_ehp(target)
    local dmg = pred.total * safety
    return dmg >= need, pred
end

local function should_fire_carbine_early(lp, target, charge_t0, charge_ms)
    if not ui_a.carbine_fire_lethal:Get() then return false, nil end
    if not DC then return false, nil end
    local ab = get_carbine_ability(lp)
    if not ab or not ab:valid() then return false, nil end
    local props = get_carbine_props(ab)
    if not props then return false, nil end

    local frac = carbine_charge_frac(charge_t0, props.max_charge, charge_ms)
    if frac < (ui_a.carbine_kill_min_chg:Get() / 100.0) then return false, nil end

    local lethal, pred = is_carbine_lethal(lp, ab, target, frac, ui_a.carbine_kill_safety:Get(), true)
    return lethal, pred
end

local function find_lethal_carbine_target(lp, cmd, charge_frac)
    if not DC then return nil, nil end
    local ab = get_carbine_ability(lp)
    if not ab or not ab:valid() then return nil, nil end

    local best, best_pred = nil, nil
    local fov = ui_a.carbine_fov:Get()

    local function consider(pawn)
        if is_bad_kill_target(pawn) then return end
        local lethal, pred = is_carbine_lethal(lp, ab, pawn, charge_frac, ui_a.carbine_kill_safety:Get(), true)
        if lethal and pred then
            if not best or pred.total > best_pred.total then
                best, best_pred = pawn, pred
            end
        end
    end

    local cross = find_target_in_crosshair(lp, cmd, fov)
    if cross then consider(cross) end

    if not best and Utils and Utils.GetEnemies then
        local cam = (cmd and cmd.orig_vec_camera_position) or safe(function() return utils.get_camera_pos() end)
        local cam_ang = safe(function() return utils.get_camera_angles() end) or (cmd and cmd.viewangles)
        if cam and cam_ang then
            for _, pawn in ipairs(Utils.GetEnemies(lp)) do
                local pos = get_target_bone_pos(pawn)
                if pos then
                    local ang = utils.calc_angle(cam, pos)
                    if utils.get_fov(cam_ang, ang) <= fov then
                        consider(pawn)
                    end
                end
            end
        end
    end

    return best, best_pred
end

-- ─── Carbine Assist ─────────────────────────────────────────────────────────

local function user_pressed_slot(cmd, slot)
    local mask = SLOT_MASK[slot]
    if not mask or not cmd.get_orig_button_state1 then return false end
    local orig = safe(function() return cmd:get_orig_button_state1() end)
    if not orig then return false end
    return (orig & mask) ~= 0
end

local function assist_elapsed(a)
    return global_vars.curtime() - a.t0
end

local function apply_head_aim(cmd, target, use_psilent)
    if not target or not target:valid() then return false end
    local pos = get_head_aim_pos(target)
    if not pos then return false end

    if use_psilent and safe(function() return cmd:can_psilent_at_pos(pos) end) then
        pcall(function() cmd:set_psilent_at_pos(pos) end)
        return true
    end

    local cam = cmd.orig_vec_camera_position or safe(function() return utils.get_camera_pos() end)
    if not cam then return false end
    local ang = utils.calc_angle(cam, pos)
    apply_cmd_aim(cmd, ang.pitch or ang.x or 0, ang.yaw or ang.y or 0)
    return true
end

local function clear_assist_inputs(cmd)
    clear_primary_attack(cmd)
    clear_slot(cmd, GRENADE_SLOT)
    clear_slot(cmd, WALL_SLOT)
    clear_slot(cmd, SWAP_SLOT)
    clear_slot(cmd, CARBINE_SLOT)
    if cmd.execute_ability_indices ~= nil then
        cmd.execute_ability_indices = 0
    end
end

local function complete_carbine_assist(cmd, msg)
    clear_assist_inputs(cmd)
    assist.carbine.phase = AS.IDLE
    assist.carbine.charge_t0 = 0
    assist.carbine.target = nil
    assist.carbine.last_pred = nil
    assist.carbine.last_pred_hp = 0
    assist.carbine.msg = msg or ""
    state.release_until = global_vars.curtime() + 0.4
end

local function start_carbine_assist(target, msg)
    assist.carbine.target = target
    assist.carbine.phase = AS.CHARGE
    assist.carbine.t0 = global_vars.curtime()
    assist.carbine.charge_t0 = 0
    assist.carbine.last_pred = nil
    assist.carbine.last_pred_hp = target_ehp(target)
    assist.carbine.msg = msg or "carbine: CHARGE"
end

local function try_auto_carbine_killsteal(cmd, lp)
    if not ui_a.carbine_killsteal:Get() then return false end
    if state.phase ~= S.IDLE or assist.carbine.phase ~= AS.IDLE or assist.grenade.phase ~= GS.IDLE then
        return false
    end
    if ParadoxWall and ParadoxWall.is_busy and ParadoxWall.is_busy() then return false end
    if ParadoxSwap and ParadoxSwap.is_busy and ParadoxSwap.is_busy() then return false end
    if not slot_ready(lp, CARBINE_SLOT) then return false end

    local target, pred = find_lethal_carbine_target(lp, cmd, 1.0)
    if not target then return false end

    start_carbine_assist(target, string.format(
        "carbine: lethal KS (%.0f / %.0f HP)", pred.total_safe or pred.total, assist.carbine.last_pred_hp))
    return true
end

local function try_start_carbine_assist(cmd, lp)
    if not ui_a.carbine_enable:Get() then return false end
    if state.phase ~= S.IDLE or assist.carbine.phase ~= AS.IDLE or assist.grenade.phase ~= GS.IDLE then
        return false
    end
    if ParadoxWall and ParadoxWall.is_busy and ParadoxWall.is_busy() then return false end
    if ParadoxSwap and ParadoxSwap.is_busy and ParadoxSwap.is_busy() then return false end
    if not slot_ready(lp, CARBINE_SLOT) then return false end

    local triggered = false
    if ui_a.carbine_mode:Get() == 0 then
        triggered = user_pressed_slot(cmd, CARBINE_SLOT)
    else
        triggered = ui_a.carbine_key:IsPressed()
    end
    if not triggered then return false end

    local target = find_target_in_crosshair(lp, cmd, ui_a.carbine_fov:Get())
    if not target then
        assist.carbine.msg = string.format("carbine: no target (%.0f°)", ui_a.carbine_fov:Get())
        return false
    end

    start_carbine_assist(target, "carbine: CHARGE")
    return true
end

local function run_carbine_assist(cmd, lp)
    if assist.grenade.phase ~= GS.IDLE then return end
    if not ui_a.carbine_enable:Get() then
        if assist.carbine.phase ~= AS.IDLE then complete_carbine_assist(cmd, "") end
        return
    end

    local a = assist.carbine

    if a.phase == AS.IDLE then
        if try_auto_carbine_killsteal(cmd, lp) then
            -- started by killsteal
        elseif not try_start_carbine_assist(cmd, lp) then
            return
        end
    end

    if a.phase == AS.IDLE then return end

    if not a.target or not a.target:valid() or not a.target:is_alive() then
        complete_carbine_assist(cmd, "carbine: target lost")
        return
    end

    clear_slot(cmd, GRENADE_SLOT)
    clear_slot(cmd, WALL_SLOT)
    clear_slot(cmd, SWAP_SLOT)
    apply_head_aim(cmd, a.target, ui_a.carbine_psilent:Get())

    if a.phase == AS.CHARGE then
        local cst = ability_status(lp, CARBINE_SLOT)
        local ab = get_carbine_ability(lp)
        if ab and a.target then
            local props = get_carbine_props(ab)
            local frac = carbine_charge_frac(a.charge_t0, props and props.max_charge or 2.5, ui_a.carbine_charge_ms:Get())
            local _, pred = is_carbine_lethal(lp, ab, a.target, frac, ui_a.carbine_kill_safety:Get(), true)
            a.last_pred = pred
            a.last_pred_hp = target_ehp(a.target)
        end

        local fire_early, early_pred = should_fire_carbine_early(lp, a.target, a.charge_t0, ui_a.carbine_charge_ms:Get())
        if fire_early then
            a.charge_t0 = 0
            a.phase = AS.FIRE
            a.t0 = global_vars.curtime()
            a.last_pred = early_pred
            a.msg = string.format("carbine: lethal FIRE (%d%%)", early_pred and early_pred.charge_pct or 0)
            return
        end

        if cst == "cd" then
            a.charge_t0 = 0
            a.phase = AS.FIRE
            a.t0 = global_vars.curtime()
            a.msg = "carbine: FIRE"
            return
        end

        if cst == "ready" or cst == "busy" then
            press_slot(cmd, CARBINE_SLOT)
            press_attack(cmd)
            if a.charge_t0 == 0 then
                a.charge_t0 = global_vars.curtime()
            end
            a.msg = string.format("carbine: CHARGE (%s)", cst)
        else
            clear_primary_attack(cmd)
            clear_slot(cmd, CARBINE_SLOT)
            a.msg = string.format("carbine: waiting (%s)", cst)
        end

        if a.charge_t0 > 0
            and (global_vars.curtime() - a.charge_t0) >= ui_a.carbine_charge_ms:Get() / 1000.0 then
            a.charge_t0 = 0
            a.phase = AS.FIRE
            a.t0 = global_vars.curtime()
            a.msg = "carbine: FIRE"
        end
        return
    end

    if a.phase == AS.FIRE then
        local cst = ability_status(lp, CARBINE_SLOT)

        if cst == "ready" then
            press_slot(cmd, CARBINE_SLOT)
            press_attack(cmd)
        else
            clear_primary_attack(cmd)
            clear_slot(cmd, CARBINE_SLOT)
        end

        a.msg = string.format("carbine: FIRE (%s)", cst)
        local hold = ui_a.carbine_fire_ms:Get() / 1000.0
        if cst == "cd" or assist_elapsed(a) >= hold then
            complete_carbine_assist(cmd, "carbine: done")
        end
    end
end

local function clear_cast_buttons(cmd)
    clear_primary_attack(cmd)
    clear_slot(cmd, GRENADE_SLOT)
    clear_slot(cmd, WALL_SLOT)
    clear_slot(cmd, CARBINE_SLOT)
    clear_slot(cmd, SWAP_SLOT)
    clear_item_slots(cmd)
end

local function clear_script_inputs(cmd)
    clear_cast_buttons(cmd)
    if cmd.execute_ability_indices ~= nil then
        cmd.execute_ability_indices = 0
    end
end

local function begin_swap_phase(cmd)
    if ui.use_swap:Get() then
        set_phase(S.SWAP_AIM)
    else
        begin_carbine_phase(cmd)
    end
end

local function is_swap_ready_to_cast(lp)
    if not slot_ready(lp, SWAP_SLOT) then return false end
    if is_cast_locked(lp) then return false end
    return true
end

local function is_swap_aim_settled(lp, cmd)
    local delay = ui.swap_delay_ms:Get() / 1000.0
    if elapsed() < delay then return false end
    return is_tracking_on_target(lp, cmd, 12) or is_restore_settled()
end

local function can_start_swap_cast(lp)
    if is_swap_ready_to_cast(lp) then return true end
    local timeout = ui.swap_ready_wait_ms:Get() / 1000.0
    return elapsed() >= timeout
end

local function begin_carbine_phase(cmd)
    if ui.use_carbine:Get() then
        set_phase(S.CARBINE_CHARGE)
        state.last_msg = "step6: CARBINE_CHARGE"
    else
        complete_combo(cmd, "FINISHED — combo complete")
    end
end

local function start_item_segment(lp, segment, phase_from, phase_to)
    state.item_segment = segment
    state.item_queue = build_item_queue(lp, phase_from, phase_to)
    state.item_index = 1
    if #state.item_queue > 0 then
        set_phase(S.ITEMS_AIM)
        local entry = state.item_queue[1]
        state.last_msg = string.format("step5: ITEMS_AIM [%s] %s", segment, entry.def.name)
        return true
    end
    return false
end

local function begin_pre_carbine_phase(cmd, lp)
    if ui_i.enable:Get() then
        if start_item_segment(lp, "pre_carbine", ITEM_PHASE.PRE_CARBINE, ITEM_PHASE.PRE_CARBINE) then
            return
        end
    end
    begin_carbine_phase(cmd)
end

local function begin_post_swap_phase(cmd, lp)
    if ui_i.enable:Get() and ui.use_swap:Get() then
        if start_item_segment(lp, "post_swap", ITEM_PHASE.POST_SWAP, ITEM_PHASE.POST_SWAP_ECHO) then
            return
        end
        state.last_msg = "post-swap items unavailable — skipping"
    end
    begin_pre_carbine_phase(cmd, lp)
end

local function advance_item_queue(cmd, lp)
    state.item_index = state.item_index + 1
    if state.item_index <= #state.item_queue then
        set_phase(S.ITEMS_AIM)
        local entry = current_item_entry()
        state.last_msg = string.format("step5: ITEMS_AIM [%s] %s",
            state.item_segment, entry and entry.def.name or "?")
        return
    end
    if state.item_segment == "post_swap" then
        begin_pre_carbine_phase(cmd, lp)
    else
        begin_carbine_phase(cmd)
    end
end

local function is_item_aim_ready(lp, cmd, entry)
    local def = entry and entry.def
    if not def then return elapsed() >= 0.05 end
    local delay = state.item_index == 1 and item_phase_delay(def) or 0.06
    if elapsed() < delay then return false end
    if def.needs_target then
        return is_tracking_on_target(lp, cmd, 18) or elapsed() >= delay + 0.15
    end
    return true
end

local function apply_saved_aim(cmd)
    if state.saved_pitch == nil or state.saved_yaw == nil then return false end
    apply_view_angles(cmd, state.saved_pitch, state.saved_yaw, true)
    state.last_msg = string.format("restore: pitch=%.1f° yaw=%.1f°", state.saved_pitch, state.saved_yaw)
    return true
end

local function trace_ground_at(x, y, ref_z)
    if not trace or not trace.line then
        return Vector(x, y, ref_z)
    end
    local start  = Vector(x, y, ref_z + 512)
    local finish = Vector(x, y, ref_z - 512)
    local tr = safe(function()
        return trace.line(start, finish, 0, 0, 0, 0, 0, function() return false end)
    end)
    if tr and tr.fraction and tr.fraction < 1.0 then
        return Vector(
            start.x + (finish.x - start.x) * tr.fraction,
            start.y + (finish.y - start.y) * tr.fraction,
            start.z + (finish.z - start.z) * tr.fraction
        )
    end
    return Vector(x, y, ref_z)
end

local function check_paradox(pawn)
    if not pawn or not pawn:valid() then
        is_paradox = false
        last_hero_idx = -1
        return false
    end
    local idx = pawn:get_index()
    if idx == last_hero_idx then return is_paradox end
    last_hero_idx = idx
    is_paradox = false

    local name = string.lower(safe(function() return pawn:get_name() end) or "")
    if string.find(name, "chrono", 1, true) or string.find(name, "paradox", 1, true) then
        is_paradox = true
        return true
    end

    local ab = safe(function() return pawn:get_ability_by_slot(GRENADE_SLOT) end)
    if ab and ab:valid() then
        local cn = string.lower(safe(function() return ab:get_class_name() end) or "")
        if string.find(cn, "chrono_pulse", 1, true) then
            is_paradox = true
        end
    end
    return is_paradox
end

-- Ponto no chão ao longo do raio da mira (NÃO usar calc_angle em ponto no pé — gimbal lock)
local function get_ground_from_view(cam, pitch_deg, yaw_deg)
    if not cam then return nil, nil end

    local fwd = angles_to_forward(pitch_deg, yaw_deg)
    local dist = ui.ray_dist_m:Get() * UNIT_METER
    local endpt = Vector(
        cam.x + fwd.x * dist,
        cam.y + fwd.y * dist,
        cam.z + fwd.z * dist
    )

    local ground = trace_ground_at(endpt.x, endpt.y, cam.z)
    local below  = ui.below_m:Get() * UNIT_METER
    local aim_pos = Vector(ground.x, ground.y, ground.z - below)
    return aim_pos, ground
end

-- ─── Grenade prediction + feet aim ──────────────────────────────────────────

local GRENADE_PREDICT_BONE = "ankle_R"
local GRENADE_FALLBACK_SPEED = 1400
local predict_cleanup_t = 0

local GRENADE_AIM = { PSILENT = 0, SMOOTH = 1, HYBRID = 2 }

local function get_grenade_projectile_speed(lp)
    if Aim and Aim.GetAbilitySpeed then
        return Aim.GetAbilitySpeed(lp, GRENADE_SLOT, GRENADE_FALLBACK_SPEED)
    end
    if Utils and Utils.GetAbilityProjectileSpeed then
        local ab = safe(function() return lp:get_ability_by_slot(GRENADE_SLOT) end)
        return Utils.GetAbilityProjectileSpeed(ab) or GRENADE_FALLBACK_SPEED
    end
    return GRENADE_FALLBACK_SPEED
end

local function predict_target_bone_pos(target, lead_t)
    if not Prediction or not target or not target:valid() then return nil end
    lead_t = lead_t or 0

    if Prediction.PredictPlayerAdvanced then
        return Prediction.PredictPlayerAdvanced(target, lead_t, GRENADE_PREDICT_BONE, {
            use_acceleration = true,
            clamp_to_max_speed = true,
            max_lead_distance = 15 * UNIT_METER,
            multi_sample = lead_t > 0.04,
            sample_count = 3,
        })
    end

    if Prediction.PredictPlayer then
        return Prediction.PredictPlayer(target, lead_t, nil, nil, nil, nil, GRENADE_PREDICT_BONE, true)
    end

    return nil
end

local function estimate_grenade_lead_time(lp, target, extra_s)
    extra_s = extra_s or 0
    if not target or not target:valid() then return extra_s + 0.08 end

    local cam = safe(function() return utils.get_camera_pos() end)
    if not cam then return extra_s + 0.08 end

    local speed = lp and get_grenade_projectile_speed(lp) or GRENADE_FALLBACK_SPEED
    local predicted = predict_target_bone_pos(target, 0)
        or safe(function() return target:get_origin() end)
    if not predicted then return extra_s + 0.08 end

    local t = 0
    if speed > 100 then
        for _ = 1, 8 do
            local dist = cam:Distance(predicted)
            local new_t = dist / speed
            if math.abs(new_t - t) < 0.005 then break end
            t = new_t
            predicted = predict_target_bone_pos(target, t) or predicted
        end
    else
        local vel = Prediction and Prediction.GetTrackedVelocity(target)
        if vel and vel:Length2D() > 40 then
            t = 0.12
        else
            t = 0.05
        end
    end

    return t + extra_s
end

local function get_enemy_feet_ground_static(target)
    local ankle = safe(function() return target:get_bone_pos("ankle_R") end)
        or safe(function() return target:get_bone_pos("ankle_L") end)
    if ankle then
        return trace_ground_at(ankle.x, ankle.y, ankle.z)
    end
    local origin = safe(function() return target:get_origin() end)
    if origin then
        return trace_ground_at(origin.x, origin.y, origin.z)
    end
    return nil
end

local function get_predicted_enemy_feet_ground(target, lp, extra_lead_s)
    if not target or not target:valid() then return nil end

    local lead_t = estimate_grenade_lead_time(lp, target, extra_lead_s or 0)
    local predicted = predict_target_bone_pos(target, lead_t)

    if predicted then
        local ground = trace_ground_at(predicted.x, predicted.y, predicted.z)
        if ground then
            return ground, lead_t, predicted
        end
    end

    return get_enemy_feet_ground_static(target), 0, nil
end

local function get_enemy_feet_aim_pos(target, lp, opts)
    opts = opts or {}
    local below_m = opts.below_m or 0
    local use_predict = opts.predict ~= false and Prediction ~= nil
    local extra_lead = opts.lead_s or 0

    local ground, lead_t, predicted
    if use_predict and lp then
        ground, lead_t, predicted = get_predicted_enemy_feet_ground(target, lp, extra_lead)
    else
        ground = get_enemy_feet_ground_static(target)
        lead_t = 0
    end

    if not ground then return nil, lead_t end
    return Vector(ground.x, ground.y, ground.z - below_m * UNIT_METER), lead_t
end

local function grenade_predict_opts_for_assist()
    return {
        predict = ui_a.grenade_predict:Get(),
        lead_s = ui_a.grenade_lead_ms:Get() / 1000.0,
        below_m = ui_a.grenade_below_m:Get(),
    }
end

local function grenade_aim_cfg_from_assist()
    return {
        mode = ui_a.grenade_aim_mode:Get(),
        smooth = ui_a.grenade_smooth:Get(),
        psilent_fov = ui_a.grenade_psilent_fov:Get(),
        max_fov = ui_a.grenade_fov:Get(),
    }
end

local function apply_grenade_aim(cmd, pos, cfg)
    if not pos or not cfg then return false, "none" end

    local cam = cmd.orig_vec_camera_position or safe(function() return utils.get_camera_pos() end)
    local cam_ang = safe(function() return utils.get_camera_angles() end)
    if not cam or not cam_ang then return false, "none" end

    local ang = utils.calc_angle(cam, pos)
    local fov = utils.get_fov(cam_ang, ang)
    local mode = cfg.mode or GRENADE_AIM.HYBRID
    local psilent_fov = cfg.psilent_fov or 30
    local max_fov = cfg.max_fov or 180
    local smooth = cfg.smooth or 15

    if mode == GRENADE_AIM.PSILENT or mode == GRENADE_AIM.HYBRID then
        if fov <= psilent_fov and safe(function() return cmd:can_psilent_at_pos(pos) end) then
            pcall(function() cmd:set_psilent_at_pos(pos) end)
            return true, "psilent"
        end
        if mode == GRENADE_AIM.PSILENT then
            return false, "psilent_wait"
        end
    end

    if fov > max_fov then
        return false, "out_fov"
    end

    if smooth > 1 then
        pcall(function() cmd:smooth_aim(ang, smooth) end)
    else
        local pitch = ang.pitch or ang.x or 0
        local yaw = ang.yaw or ang.y or 0
        apply_view_angles(cmd, pitch, yaw, true)
    end
    return true, "smooth"
end

local function is_grenade_aim_settled(cmd, pos, cfg, tol)
    if not pos or not cfg then return false end
    tol = tol or 8

    local cam = cmd.orig_vec_camera_position or safe(function() return utils.get_camera_pos() end)
    local cam_ang = safe(function() return utils.get_camera_angles() end)
    if not cam or not cam_ang then return false end

    local ang = utils.calc_angle(cam, pos)
    local fov = utils.get_fov(cam_ang, ang)
    local mode = cfg.mode or GRENADE_AIM.HYBRID

    if mode == GRENADE_AIM.PSILENT or mode == GRENADE_AIM.HYBRID then
        if fov <= (cfg.psilent_fov or 30)
            and safe(function() return cmd:can_psilent_at_pos(pos) end) then
            return true
        end
        if mode == GRENADE_AIM.PSILENT then
            return fov <= tol
        end
    end

    return fov <= tol
end

local function apply_aim_down(cmd, lp)
    local cam = cmd.orig_vec_camera_position or safe(function() return utils.get_camera_pos() end)
    if not cam then return false end

    -- granada nos pés: yaw do jogador no início do combo, não o yaw do track no inimigo
    local yaw = state.user_yaw
    if yaw == nil then
        if state.locked_yaw == nil then
            local cam_p, cam_y = get_view_angles(cmd)
            state.locked_yaw = cam_y or 0
        end
        yaw = state.locked_yaw
    end

    local pitch = resolve_down_pitch()
    apply_view_angles(cmd, pitch, yaw, true)

    local aim_pos, ground = get_ground_from_view(cam, pitch, yaw)
    state.aim_pos = aim_pos
    state.ground_pos = ground
    state.last_msg = string.format("aim: pitch=%.1f° yaw=%.1f° (feet)", pitch, yaw)
    return aim_pos ~= nil
end

-- ─── Grenade Assist ─────────────────────────────────────────────────────────

local function get_enemy_feet_ground(target)
    return get_enemy_feet_ground_static(target)
end

local function grenade_assist_elapsed()
    return global_vars.curtime() - assist.grenade.t0
end

local function capture_grenade_saved_aim(cmd)
    local cam_ang = safe(function() return utils.get_camera_angles() end)
        or cmd.viewangles
    if not cam_ang then return false end
    assist.grenade.saved_pitch = cam_ang.pitch or cam_ang.x or 0
    assist.grenade.saved_yaw   = cam_ang.yaw or cam_ang.y or 0
    return true
end

local function is_grenade_restore_settled()
    local g = assist.grenade
    if g.saved_pitch == nil or g.saved_yaw == nil then return true end
    local current_p, current_y = get_current_angles()
    if current_p == nil or current_y == nil then return grenade_assist_elapsed() >= 0.03 end
    local tol = ui_a.grenade_restore_tol:Get()
    return math.abs(current_p - g.saved_pitch) < tol
        and math.abs(normalize_yaw_delta(current_y, g.saved_yaw)) < tol
end

local function complete_grenade_assist(cmd, msg)
    clear_cast_buttons(cmd)
    assist.grenade.phase = GS.IDLE
    assist.grenade.target = nil
    assist.grenade.feet_pos = nil
    assist.grenade.saved_pitch = nil
    assist.grenade.saved_yaw = nil
    assist.grenade.msg = msg or ""
    state.release_until = global_vars.curtime() + 0.4
end

local function start_grenade_assist(target, lp, msg)
    local g = assist.grenade
    local feet_pos, lead_t = get_enemy_feet_aim_pos(target, lp, grenade_predict_opts_for_assist())
    g.target = target
    g.phase = GS.AIM
    g.t0 = global_vars.curtime()
    g.feet_pos = feet_pos
    g.lead_t = lead_t or 0
    g.msg = msg or "grenade: AIM"
end

local function try_start_grenade_assist(cmd, lp)
    if not ui_a.grenade_enable:Get() then return false end
    if state.phase ~= S.IDLE or assist.carbine.phase ~= AS.IDLE or assist.grenade.phase ~= GS.IDLE then
        return false
    end
    if ParadoxWall and ParadoxWall.is_busy and ParadoxWall.is_busy() then return false end
    if ParadoxSwap and ParadoxSwap.is_busy and ParadoxSwap.is_busy() then return false end
    if not slot_ready(lp, GRENADE_SLOT) then return false end

    local triggered = false
    if ui_a.grenade_mode:Get() == 0 then
        triggered = user_pressed_slot(cmd, GRENADE_SLOT)
    else
        triggered = ui_a.grenade_key:IsPressed()
    end
    if not triggered then return false end

    local target = find_target_in_crosshair(lp, cmd, ui_a.grenade_fov:Get())
    if not target then
        assist.grenade.msg = string.format("grenade: no target (%.0f°)", ui_a.grenade_fov:Get())
        return false
    end

    capture_grenade_saved_aim(cmd)
    start_grenade_assist(target, lp, "grenade: AIM")
    return true
end

local function run_grenade_assist(cmd, lp)
    if not ui_a.grenade_enable:Get() then
        if assist.grenade.phase ~= GS.IDLE then complete_grenade_assist(cmd, "") end
        return false
    end

    local g = assist.grenade

    if g.phase == GS.IDLE then
        if not try_start_grenade_assist(cmd, lp) then return false end
    end

    if g.phase == GS.IDLE then return false end

    if not g.target or not g.target:valid() or not g.target:is_alive() then
        complete_grenade_assist(cmd, "grenade: target lost")
        return true
    end

    local feet_pos, lead_t = get_enemy_feet_aim_pos(g.target, lp, grenade_predict_opts_for_assist())
    g.feet_pos = feet_pos or g.feet_pos
    g.lead_t = lead_t or g.lead_t or 0
    if not g.feet_pos then
        complete_grenade_assist(cmd, "grenade: feet pos lost")
        return true
    end

    clear_slot(cmd, WALL_SLOT)
    clear_slot(cmd, CARBINE_SLOT)
    clear_slot(cmd, SWAP_SLOT)
    clear_primary_attack(cmd)

    if g.phase == GS.AIM then
        local aim_cfg = grenade_aim_cfg_from_assist()
        local _, phase = apply_grenade_aim(cmd, g.feet_pos, aim_cfg)
        if ui_a.grenade_predict:Get() and g.lead_t and g.lead_t > 0 then
            g.msg = string.format("grenade: %s (%.0fms)", phase, g.lead_t * 1000)
        else
            g.msg = string.format("grenade: %s", phase)
        end

        local delay = ui_a.grenade_aim_delay_ms:Get() / 1000.0
        local settled = is_grenade_aim_settled(cmd, g.feet_pos, aim_cfg, ui_a.grenade_aim_tol:Get())
        if grenade_assist_elapsed() >= delay and settled then
            g.phase = GS.CAST
            g.t0 = global_vars.curtime()
            g.msg = "grenade: CAST"
        elseif grenade_assist_elapsed() >= delay + ui_a.grenade_ready_wait_ms:Get() / 1000.0 then
            g.phase = GS.CAST
            g.t0 = global_vars.curtime()
            g.msg = "grenade: CAST (timeout)"
        end
        return true
    end

    if g.phase == GS.CAST then
        apply_grenade_aim(cmd, g.feet_pos, grenade_aim_cfg_from_assist())

        local gst = ability_status(lp, GRENADE_SLOT)
        if slot_ready(lp, GRENADE_SLOT) then
            press_slot(cmd, GRENADE_SLOT)
        else
            clear_slot(cmd, GRENADE_SLOT)
        end

        g.msg = string.format("grenade: CAST (%s)", gst)
        local hold = ui_a.grenade_cast_hold_ms:Get() / 1000.0
        if gst == "cd" or gst == "busy" or grenade_assist_elapsed() >= hold then
            if ui_a.grenade_restore:Get() and g.saved_pitch ~= nil and g.saved_yaw ~= nil then
                g.phase = GS.RESTORE
                g.t0 = global_vars.curtime()
                g.msg = "grenade: RESTORE"
            else
                complete_grenade_assist(cmd, "grenade: done")
            end
        end
        return true
    end

    if g.phase == GS.RESTORE then
        clear_cast_buttons(cmd)
        apply_view_angles(cmd, g.saved_pitch, g.saved_yaw, true)
        g.msg = "grenade: RESTORE"
        if is_grenade_restore_settled() or grenade_assist_elapsed() >= 0.25 then
            complete_grenade_assist(cmd, "grenade: done")
        end
        return true
    end

    return false
end

local function reset_state(msg)
    state.phase       = S.IDLE
    state.t0          = 0
    state.aim_pos     = nil
    state.ground_pos  = nil
    state.pitch_deg   = 0
    state.locked_yaw  = nil
    state.saved_pitch = nil
    state.saved_yaw   = nil
    state.user_pitch  = nil
    state.user_yaw    = nil
    state.target      = nil
    state.wall_pos    = nil
    state.track_until = 0
    state.charge_t0   = 0
    state.item_segment = ""
    state.item_queue  = {}
    state.item_index  = 0
    state.last_msg    = msg or ""
end

local function release_combo_control(cmd)
    if not cmd then return end
    clear_script_inputs(cmd)
    pcall(function() cmd:reset_camera_ang() end)
    pcall(function() cmd:reset_camera_pos() end)
    if state.user_pitch ~= nil and state.user_yaw ~= nil then
        local ang = Angle(state.user_pitch, state.user_yaw, 0)
        cmd.viewangles = ang
        pcall(function() cmd.ang_camera_angles = ang end)
    end
end

local function complete_combo(cmd, msg)
    release_combo_control(cmd)
    reset_state(msg or "")
    state.release_until = global_vars.curtime() + 0.6
end

local function tick_camera_release(cmd)
    if state.release_until <= 0 or global_vars.curtime() > state.release_until then
        state.release_until = 0
        return false
    end
    clear_script_inputs(cmd)
    pcall(function() cmd:reset_camera_ang() end)
    pcall(function() cmd:reset_camera_pos() end)
    return true
end

-- ─── Logic ──────────────────────────────────────────────────────────────────

local function try_start_combo(cmd, lp)
    if not slot_ready(lp, GRENADE_SLOT) then
        state.last_msg = "grenade on cooldown"
        return false
    end
    if not capture_user_aim(cmd) then
        state.last_msg = "no camera angles"
        return false
    end

    if ui.auto_acquire:Get() then
        state.target = find_target_in_crosshair(lp, cmd, ui.track_fov:Get())
        if not state.target then
            state.last_msg = string.format("no enemy in FOV (%.0f°)", ui.track_fov:Get())
            return false
        end
        set_phase(S.ACQUIRE_AIM)
        return true
    end

    if not capture_saved_aim(cmd) then
        state.last_msg = "no camera angles"
        return false
    end
    state.target = find_target_in_crosshair(lp, cmd, ui.track_fov:Get())
    set_phase(S.AIM_DOWN)
    return true
end

local function run_combo(cmd, lp)
    if state.phase == S.IDLE then
        if not ui.test_key:IsPressed() then return end
        if not try_start_combo(cmd, lp) then return end
    end

    if state.phase == S.ACQUIRE_AIM then
        clear_script_inputs(cmd)

        if not state.target or not state.target:valid() or not state.target:is_alive() then
            state.target = find_target_in_crosshair(lp, cmd, ui.track_fov:Get())
        end
        if not state.target then
            state.last_msg = string.format("target lost (FOV %.0f°)", ui.track_fov:Get())
            return
        end

        apply_track_target(cmd, lp)
        local name = safe(function() return state.target:get_name() end) or "enemy"
        state.last_msg = string.format("step0: ACQUIRE → %s", name)

        if is_acquire_ready(lp, cmd) then
            capture_saved_aim(cmd)
            set_phase(S.AIM_DOWN)
            state.last_msg = "step1: AIM_DOWN — aim at feet"
        elseif is_acquire_failed() then
            complete_combo(cmd, "acquire timeout — combo cancelled")
        end
        return
    end

    if state.phase == S.AIM_DOWN then
        apply_aim_down(cmd, lp)
        clear_script_inputs(cmd)
        state.last_msg = string.format("step1: AIM_DOWN pitch=%.1f°", state.pitch_deg)

        if is_aim_settled() then
            set_phase(S.CAST)
        end
        return
    end

    if state.phase == S.CAST then
        apply_aim_down(cmd, lp)
        clear_primary_attack(cmd)
        press_slot(cmd, GRENADE_SLOT)
        state.last_msg = string.format("step1: CAST pitch=%.1f°", state.pitch_deg)

        local ab = safe(function() return lp:get_ability_by_slot(GRENADE_SLOT) end)
        local on_cd = ab and ab:valid() and ab:can_be_executed() ~= 0
        if on_cd or elapsed() > 0.15 then
            set_phase(S.RESTORE_AIM)
        end
        return
    end

    if state.phase == S.RESTORE_AIM then
        clear_script_inputs(cmd)
        apply_saved_aim(cmd)
        state.last_msg = string.format("step2: RESTORE → pitch=%.1f° yaw=%.1f°",
            state.saved_pitch or 0, state.saved_yaw or 0)

        if is_restore_settled() or elapsed() > 0.12 then
            if ui.use_wall:Get() then
                set_phase(S.WALL_AIM)
                state.last_msg = "step3: WALL_AIM"
            else
                begin_swap_phase(cmd)
            end
        end
        return
    end

    if state.phase == S.WALL_AIM or state.phase == S.WALL_SELECT or state.phase == S.WALL_CONFIRM then
        if ParadoxWall and ParadoxWall.combo_step then
            local phase_name = state.phase
            ParadoxWall.combo_step(cmd, lp, {
                phase = phase_name,
                t0 = state.t0,
                target = state.target,
                wall_pos = state.wall_pos,
                set_phase = function(name)
                    if name == "WALL_AIM" then set_phase(S.WALL_AIM)
                    elseif name == "WALL_SELECT" then set_phase(S.WALL_SELECT)
                    elseif name == "WALL_CONFIRM" then set_phase(S.WALL_CONFIRM)
                    end
                end,
                on_fail = function() begin_swap_phase(cmd) end,
                on_done = function() begin_swap_phase(cmd) end,
                elapsed = elapsed,
                clear_inputs = clear_script_inputs,
                set_msg = function(m) state.last_msg = m end,
            })
        else
            begin_swap_phase(cmd)
        end
        return
    end

    if state.phase == S.SWAP_AIM then
        clear_script_inputs(cmd)
        apply_track_target(cmd, lp)
        local sst = ability_status(lp, SWAP_SLOT)
        local locked = is_cast_locked(lp)
        state.last_msg = string.format("step4: SWAP_AIM swap=%s locked=%s", sst, tostring(locked))

        if is_swap_aim_settled(lp, cmd) and can_start_swap_cast(lp) then
            start_swap_tracking()
            set_phase(S.SWAP_CAST)
        end
        return
    end

    if state.phase == S.SWAP_CAST then
        apply_track_target(cmd, lp)
        clear_primary_attack(cmd)
        clear_slot(cmd, GRENADE_SLOT)
        clear_slot(cmd, WALL_SLOT)
        press_slot(cmd, SWAP_SLOT)

        local hold = ui.swap_hold_ms:Get() / 1000.0
        local sst  = ability_status(lp, SWAP_SLOT)
        state.last_msg = string.format("step4: SWAP_CAST hold=%.0fms swap=%s", hold * 1000, sst)

        local on_cd = sst == "cd" or sst == "busy"
        if on_cd then
            set_phase(S.DONE)
            state.last_msg = "DONE — combo complete (tracking)"
        elseif elapsed() > hold + 0.35 then
            set_phase(S.DONE)
            state.last_msg = "DONE — swap timeout (" .. sst .. ")"
        end
        return
    end

    if state.phase == S.DONE then
        if should_keep_tracking() then
            apply_track_target(cmd, lp)
            return
        end
        begin_post_swap_phase(cmd, lp)
        return
    end

    if state.phase == S.ITEMS_AIM then
        clear_script_inputs(cmd)
        local entry = current_item_entry()
        if entry and entry.def.needs_target then
            apply_track_target(cmd, lp)
        end

        local slot = entry and entry.slot
        local ist = slot and item_status(lp, slot) or "nil"
        state.last_msg = string.format("step5: ITEMS_AIM [%s] %s item=%s",
            state.item_segment, entry and entry.def.name or "?", ist)

        if not entry or not slot or not item_slot_ready(lp, slot) then
            if elapsed() >= 0.35 then
                advance_item_queue(cmd, lp)
            end
            return
        end

        if is_item_aim_ready(lp, cmd, entry) then
            set_phase(S.ITEMS_CAST)
            state.last_msg = string.format("step5: ITEMS_CAST %s", entry.def.name)
        elseif elapsed() >= 0.9 then
            advance_item_queue(cmd, lp)
        end
        return
    end

    if state.phase == S.ITEMS_CAST then
        local entry = current_item_entry()
        if entry and entry.def.needs_target then
            apply_track_target(cmd, lp)
        end
        clear_script_inputs(cmd)

        local slot = entry and entry.slot
        local idx  = entry and entry.idx
        local ist  = slot and item_status(lp, slot) or "nil"

        if slot and item_slot_ready(lp, slot) then
            press_item_slot(cmd, idx, slot)
        else
            clear_item_slots(cmd)
        end

        state.last_msg = string.format("step5: ITEMS_CAST %s item=%s",
            entry and entry.def.name or "?", ist)

        local hold = ui_i.item_hold_ms:Get() / 1000.0
        if ist == "cd" or elapsed() >= hold then
            advance_item_queue(cmd, lp)
        end
        return
    end

    if state.phase == S.CARBINE_CHARGE then
        apply_track_head(cmd, lp)
        clear_slot(cmd, GRENADE_SLOT)
        clear_slot(cmd, WALL_SLOT)
        clear_slot(cmd, SWAP_SLOT)

        local cst = ability_status(lp, CARBINE_SLOT)

        if cst == "cd" then
            state.charge_t0 = 0
            set_phase(S.CARBINE_FIRE)
            return
        end

        if cst == "ready" or cst == "busy" then
            press_slot(cmd, CARBINE_SLOT)
            press_attack(cmd)
            if state.charge_t0 == 0 then
                state.charge_t0 = global_vars.curtime()
            end
            state.last_msg = string.format("step5: CARBINE_CHARGE carbine=%s", cst)

            if state.target and ui_a.carbine_fire_lethal:Get() then
                local fire_early, early_pred = should_fire_carbine_early(
                    lp, state.target, state.charge_t0, ui.carbine_charge_ms:Get())
                if fire_early then
                    state.charge_t0 = 0
                    set_phase(S.CARBINE_FIRE)
                    state.last_msg = string.format("step5: CARBINE_FIRE lethal (%d%%)",
                        early_pred and early_pred.charge_pct or 0)
                    return
                end
            end
        else
            clear_primary_attack(cmd)
            clear_slot(cmd, CARBINE_SLOT)
            state.last_msg = string.format("step5: CARBINE_AIM carbine=%s", cst)
            if elapsed() >= ui.carbine_ready_ms:Get() / 1000.0 then
                complete_combo(cmd, "carbine unavailable")
            end
        end

        if state.charge_t0 > 0
            and (global_vars.curtime() - state.charge_t0) >= ui.carbine_charge_ms:Get() / 1000.0 then
            state.charge_t0 = 0
            set_phase(S.CARBINE_FIRE)
            state.last_msg = "step5: CARBINE_FIRE"
        end
        return
    end

    if state.phase == S.CARBINE_FIRE then
        apply_track_head(cmd, lp)
        clear_slot(cmd, GRENADE_SLOT)
        clear_slot(cmd, WALL_SLOT)
        clear_slot(cmd, SWAP_SLOT)

        local cst = ability_status(lp, CARBINE_SLOT)

        if cst == "ready" then
            press_slot(cmd, CARBINE_SLOT)
            press_attack(cmd)
        else
            clear_primary_attack(cmd)
            clear_slot(cmd, CARBINE_SLOT)
        end

        state.last_msg = string.format("step5: CARBINE_FIRE carbine=%s", cst)

        local hold = ui.carbine_fire_ms:Get() / 1000.0
        if cst == "cd" or elapsed() >= hold then
            complete_combo(cmd, "FINISHED — combo complete (carbine)")
        end
        return
    end
end

-- ─── Debug draw ─────────────────────────────────────────────────────────────

local function ensure_fonts()
    if not font_hud then
        font_hud = Render.LoadFont("Tahoma", Enum.FontCreate.FONTFLAG_ANTIALIAS)
    end
    if not font_mono then
        font_mono = Render.LoadFont("Consolas", Enum.FontCreate.FONTFLAG_ANTIALIAS)
    end
end

local function get_screen_center()
    local scr = Render.ScreenSize()
    return scr.x * 0.5, scr.y * 0.5
end

local function clamp_fov(slider, delta, min_v, max_v)
    local v = slider:Get() + delta
    if v < min_v then v = min_v end
    if v > max_v then v = max_v end
    slider:Set(v)
end

local function handle_fov_hotkeys()
    if ui.fov_inc:IsPressed() then clamp_fov(ui.track_fov, ui.fov_step:Get(), 1, 180) end
    if ui.fov_dec:IsPressed() then clamp_fov(ui.track_fov, -ui.fov_step:Get(), 1, 180) end
    if ui_a.fov_inc:IsPressed() then clamp_fov(ui_a.carbine_fov, ui_a.fov_step:Get(), 1, 180) end
    if ui_a.fov_dec:IsPressed() then clamp_fov(ui_a.carbine_fov, -ui_a.fov_step:Get(), 1, 180) end
    if ui_a.grenade_fov_inc:IsPressed() then clamp_fov(ui_a.grenade_fov, ui_a.grenade_fov_step:Get(), 1, 180) end
    if ui_a.grenade_fov_dec:IsPressed() then clamp_fov(ui_a.grenade_fov, -ui_a.grenade_fov_step:Get(), 1, 180) end
end

local function draw_fov_ring(fov_deg, color, thickness)
    if not fov_deg or fov_deg <= 0 then return end
    local cx, cy = get_screen_center()
    Render.Circle(Vec2(cx, cy), fov_deg * FOV_RADIUS_SCALE, color, thickness or 1)
end

local function draw_fov_labels()
    local cx, cy = get_screen_center()
    local y = cy + 28
    if ui.enable:Get() and ui.show_fov_combo:Get() then
        Render.Text(font_mono, 10,
            string.format("Combo FOV: %.0f°", ui.track_fov:Get()),
            Vec2(cx - 40, y), Color(0, 220, 255, 200))
        y = y + 12
    end
    if ui_a.carbine_enable:Get() and ui_a.show_fov_carbine:Get() then
        Render.Text(font_mono, 10,
            string.format("Carbine FOV: %.0f°", ui_a.carbine_fov:Get()),
            Vec2(cx - 40, y), Color(255, 200, 60, 200))
        y = y + 12
    end
    if ui_a.grenade_enable:Get() and ui_a.show_fov_grenade:Get() then
        Render.Text(font_mono, 10,
            string.format("Grenade FOV: %.0f°", ui_a.grenade_fov:Get()),
            Vec2(cx - 40, y), Color(255, 120, 60, 200))
        y = y + 12
    end
    if ui_a.wall_enable:Get() and ui_a.show_fov_wall:Get() then
        Render.Text(font_mono, 10,
            string.format("Wall FOV: %.0f°", ui_a.wall_fov:Get()),
            Vec2(cx - 40, y), Color(80, 220, 255, 200))
        y = y + 12
    end
    if ui_a.swap_enable:Get() and ui_a.show_fov_swap:Get() then
        Render.Text(font_mono, 10,
            string.format("Swap FOV: %.0f°", ui_a.swap_fov:Get()),
            Vec2(cx - 40, y), Color(200, 100, 255, 200))
    end
end

local function draw_fov_visuals()
    if ui.enable:Get() and ui.show_fov_combo:Get() then
        draw_fov_ring(ui.track_fov:Get(), ui.fov_combo_color:Get(), ui.fov_combo_thick:Get())
    end
    if ui_a.carbine_enable:Get() and ui_a.show_fov_carbine:Get() then
        draw_fov_ring(ui_a.carbine_fov:Get(), ui_a.fov_carbine_color:Get(), ui_a.fov_carbine_thick:Get())
    end
    if ui_a.grenade_enable:Get() and ui_a.show_fov_grenade:Get() then
        draw_fov_ring(ui_a.grenade_fov:Get(), ui_a.fov_grenade_color:Get(), ui_a.fov_grenade_thick:Get())
    end
    if ui_a.wall_enable:Get() and ui_a.show_fov_wall:Get() then
        draw_fov_ring(ui_a.wall_fov:Get(), ui_a.fov_wall_color:Get(), ui_a.fov_wall_thick:Get())
    end
    if ui_a.swap_enable:Get() and ui_a.show_fov_swap:Get() then
        draw_fov_ring(ui_a.swap_fov:Get(), ui_a.fov_swap_color:Get(), ui_a.fov_swap_thick:Get())
    end
    if (ui.enable:Get() and ui.show_fov_combo:Get())
        or (ui_a.carbine_enable:Get() and ui_a.show_fov_carbine:Get())
        or (ui_a.grenade_enable:Get() and ui_a.show_fov_grenade:Get())
        or (ui_a.wall_enable:Get() and ui_a.show_fov_wall:Get())
        or (ui_a.swap_enable:Get() and ui_a.show_fov_swap:Get()) then
        draw_fov_labels()
    end
end

local function draw_world_marker(pos, color, label)
    if not pos then return end
    local sp, vis = Render.WorldToScreen(pos)
    if not vis or not sp then return end
    Render.Circle(sp, 7, color, 2)
    Render.Line(Vec2(sp.x - 6, sp.y), Vec2(sp.x + 6, sp.y), color, 1)
    Render.Line(Vec2(sp.x, sp.y - 6), Vec2(sp.x, sp.y + 6), color, 1)
    if label then
        Render.Text(font_mono, 11, label, Vec2(sp.x + 10, sp.y - 6), color)
    end
end

function ParadoxCombo.on_createmove(cmd)
    if tick_camera_release(cmd) then return end

    handle_fov_hotkeys()

    if Prediction and Prediction.CleanupStaleTracking then
        local now = global_vars.curtime()
        if now - predict_cleanup_t > 2.0 then
            predict_cleanup_t = now
            Prediction.CleanupStaleTracking()
        end
    end

    local lp = entity_list.local_pawn()
    if not lp or not lp:valid() or not lp:is_alive() then
        if state.phase ~= S.IDLE then complete_combo(cmd, "") end
        if assist.grenade.phase ~= GS.IDLE then complete_grenade_assist(cmd, "") end
        if assist.carbine.phase ~= AS.IDLE then complete_carbine_assist(cmd, "") end
        if ParadoxWall and ParadoxWall.reset then ParadoxWall.reset(cmd) end
        if ParadoxSwap and ParadoxSwap.reset then ParadoxSwap.reset(cmd) end
        return
    end

    if not check_paradox(lp) then return end

    local combo_active = state.phase ~= S.IDLE

    if ui and ui.enable and ui.enable:Get() then
        run_combo(cmd, lp)
    elseif combo_active then
        complete_combo(cmd, "")
    end

    if state.phase ~= S.IDLE then return end

    if ParadoxWall then
        if ParadoxWall.run_defense then ParadoxWall.run_defense(cmd, lp) end
        if ParadoxWall.run_assist and ParadoxWall.run_assist(cmd, lp) then return end
    end

    if ParadoxSwap and ParadoxSwap.run_assist and ParadoxSwap.run_assist(cmd, lp) then return end

    if run_grenade_assist(cmd, lp) then return end

    run_carbine_assist(cmd, lp)
end

local HUD_LEFT      = 18
local HUD_WIDTH     = 300
local HUD_PAD_X     = 10
local HUD_PAD_Y     = 8
local HUD_OFFSET_Y  = -80
local HUD_ROW_H     = 13
local HUD_LINE_H    = 15
local HUD_SECTION   = 8

local PHASE_LABEL = {
    [S.IDLE]           = "Waiting",
    [S.ACQUIRE_AIM]    = "Snap aim",
    [S.AIM_DOWN]       = "Grenade · feet",
    [S.CAST]           = "Grenade · cast",
    [S.RESTORE_AIM]    = "Restore aim",
    [S.WALL_AIM]       = "Time Wall · aim",
    [S.WALL_SELECT]    = "Time Wall · select",
    [S.WALL_CONFIRM]   = "Time Wall · confirm",
    [S.SWAP_AIM]       = "Swap · aim",
    [S.SWAP_CAST]      = "Swap",
    [S.DONE]           = "Swap · track",
    [S.ITEMS_AIM]      = "Items · aim",
    [S.ITEMS_CAST]     = "Items · cast",
    [S.CARBINE_CHARGE] = "Carbine · charge",
    [S.CARBINE_FIRE]   = "Carbine · fire",
}

local ASSIST_LABEL = {
    [AS.IDLE]   = "Waiting",
    [AS.CHARGE] = "Charging",
    [AS.FIRE]   = "Firing",
}

local GRENADE_LABEL = {
    [GS.IDLE]    = "Waiting",
    [GS.AIM]     = "Aim at feet",
    [GS.CAST]    = "Casting",
    [GS.RESTORE] = "Restore aim",
}

local SWAP_LABEL = {
    IDLE    = "Waiting",
    AIM     = "Aim target",
    CAST    = "Casting",
    TRACK   = "Tracking",
    RESTORE = "Restore aim",
}

local WALL_LABEL = {
    IDLE    = "Waiting",
    AIM     = "Aim placement",
    SELECT  = "Select wall",
    CONFIRM = "Confirm cast",
    RESTORE = "Restore aim",
}

local function get_combo_phase_color(phase)
    local col = Color(140, 160, 180, 220)
    if phase == S.ACQUIRE_AIM    then col = Color(120, 255, 255, 255) end
    if phase == S.AIM_DOWN       then col = Color(255, 200, 0, 255) end
    if phase == S.CAST           then col = Color(255, 120, 80, 255) end
    if phase == S.RESTORE_AIM    then col = Color(180, 120, 255, 255) end
    if phase == S.WALL_AIM       then col = Color(100, 255, 200, 255) end
    if phase == S.WALL_SELECT    then col = Color(80, 220, 255, 255) end
    if phase == S.WALL_CONFIRM   then col = Color(60, 180, 255, 255) end
    if phase == S.SWAP_AIM       then col = Color(200, 100, 255, 255) end
    if phase == S.SWAP_CAST      then col = Color(255, 80, 180, 255) end
    if phase == S.DONE           then col = Color(80, 255, 120, 255) end
    if phase == S.ITEMS_AIM      then col = Color(200, 120, 255, 255) end
    if phase == S.ITEMS_CAST     then col = Color(180, 80, 255, 255) end
    if phase == S.CARBINE_CHARGE then col = Color(255, 220, 60, 255) end
    if phase == S.CARBINE_FIRE   then col = Color(255, 160, 40, 255) end
    return col
end

local function draw_hud_panel_bg(px, py, w, h)
    if Render.FilledRect then
        Render.FilledRect(Vec2(px, py), Vec2(px + w, py + h), Color(6, 8, 14, 165), 6)
    end
    if Render.Rect then
        Render.Rect(Vec2(px, py), Vec2(px + w, py + h), Color(0, 150, 190, 40), 6, nil, 1)
    end
end

local function draw_hud_separator(x, y, w)
    Render.Line(Vec2(x, y), Vec2(x + w, y), Color(55, 75, 95, 90), 1)
end

local function draw_status_dot(px, py, col)
    if Render.FilledCircle then
        Render.FilledCircle(Vec2(px, py), 3.5, col)
    else
        Render.FilledRect(Vec2(px - 3, py - 3), Vec2(px + 3, py + 3), col, 2)
    end
end

local function truncate_text(text, max_len)
    if not text then return "" end
    if #text <= max_len then return text end
    return string.sub(text, 1, max_len - 1) .. "…"
end

local function hud_text_size(font, size, text)
    if not text or text == "" then return 0 end
    local ts = safe(function() return Render.TextSize(font, size, text) end)
    return ts and ts.x or (#text * size * 0.55)
end

local function draw_hud_text_right(font, size, text, right_x, y, col)
    if not text or text == "" then return end
    local w = hud_text_size(font, size, text)
    Render.Text(font, size, text, Vec2(right_x - w, y), col)
end

local function truncate_to_width(font, size, text, max_w)
    if not text then return "" end
    if max_w <= 8 then return "…" end
    if hud_text_size(font, size, text) <= max_w then return text end
    local s = text
    while #s > 1 do
        s = string.sub(s, 1, #s - 1)
        local candidate = s .. "…"
        if hud_text_size(font, size, candidate) <= max_w then
            return candidate
        end
    end
    return "…"
end

local function draw_hud_item_row(x, cy, inner_w, name, status_text, tag, dot_col, text_col, tag_col)
    draw_status_dot(x + 4, cy + 6, dot_col)

    local tag_w = 0
    if tag and tag ~= "" then
        tag_w = hud_text_size(font_mono, 9, tag) + 6
        draw_hud_text_right(font_mono, 9, tag, x + inner_w, cy + 1, tag_col)
    end

    local status_w = hud_text_size(font_mono, 10, status_text) + 6
    draw_hud_text_right(font_mono, 10, status_text, x + inner_w - tag_w, cy, text_col)

    local name_max_w = inner_w - tag_w - status_w - 18
    local name_text = truncate_to_width(font_mono, 10, name, name_max_w)
    Render.Text(font_mono, 10, name_text, Vec2(x + 12, cy), text_col)
end

local function draw_paradox_side_hud(lp)
    local show_combo = ui and ui.enable and ui.draw_hud and ui.enable:Get() and ui.draw_hud:Get()
    local show_carbine_assist = ui_a and ui_a.show_hud and ui_a.show_hud:Get() and assist.carbine.phase ~= AS.IDLE
    local show_grenade_assist = ui_a and ui_a.show_hud and ui_a.show_hud:Get() and assist.grenade.phase ~= GS.IDLE
    local show_wall_assist = ui_a and ui_a.show_hud and ui_a.show_hud:Get()
        and ParadoxWall and ParadoxWall.is_busy and ParadoxWall.is_busy()
    local show_swap_assist = ui_a and ui_a.show_hud and ui_a.show_hud:Get()
        and ParadoxSwap and ParadoxSwap.is_busy and ParadoxSwap.is_busy()
    local show_assist = show_carbine_assist or show_grenade_assist or show_wall_assist or show_swap_assist
    local show_items = ui_i and ui_i.show_loadout_hud and ui_i.show_loadout_hud:Get()
    if not show_combo and not show_assist and not show_items then return end

    local combo_active = state.phase ~= S.IDLE
    local show_combo_block = show_combo
    local item_entry = current_item_entry()
    local current_item_id = item_entry and item_entry.def.id or nil
    local show_kill_pred = show_assist and ui_a and ui_a.carbine_kill_hud and ui_a.carbine_kill_hud:Get()
        and assist.carbine.last_pred and assist.carbine.last_pred_hp > 0

    local content_h = 18
    if show_combo_block then
        content_h = content_h + HUD_SECTION + HUD_LINE_H
        if combo_active then
            content_h = content_h + 13
            if current_item_id and (state.phase == S.ITEMS_AIM or state.phase == S.ITEMS_CAST) then
                content_h = content_h + 13
            end
            if state.last_msg ~= "" then content_h = content_h + 13 end
        end
    end
    if show_assist then
        content_h = content_h + HUD_SECTION + HUD_LINE_H + 13
    end
    if show_carbine_assist then
        if assist.carbine.msg ~= "" then content_h = content_h + 13 end
        if show_kill_pred then content_h = content_h + 13 end
    end
    if show_wall_assist then
        content_h = content_h + HUD_LINE_H
    end
    if show_swap_assist then
        content_h = content_h + HUD_LINE_H
    end
    if show_grenade_assist and assist.grenade.msg ~= "" then
        content_h = content_h + 13
    end
    if show_wall_assist and ParadoxWall.get_assist_msg and ParadoxWall.get_assist_msg() ~= "" then
        content_h = content_h + 13
    end
    if show_swap_assist and ParadoxSwap.get_assist_msg and ParadoxSwap.get_assist_msg() ~= "" then
        content_h = content_h + 13
    end
    if show_items then
        content_h = content_h + HUD_SECTION + HUD_LINE_H + (#COMBO_ITEMS * HUD_ROW_H) + 4
    end

    local panel_h = content_h + HUD_PAD_Y * 2
    local panel_w = HUD_WIDTH + HUD_PAD_X * 2

    local scr = Render.ScreenSize()
    local default_px = HUD_LEFT
    local default_py = math.floor((scr.y - panel_h) * 0.5 + HUD_OFFSET_Y)
    local px, py = default_px, default_py
    if HudDrag and HudDrag.apply then
        px, py = HudDrag.apply("paradox", default_px, default_py, panel_w, panel_h)
    end
    local x = px + HUD_PAD_X
    local inner_w = HUD_WIDTH

    draw_hud_panel_bg(px, py, panel_w, panel_h)
    if HudDrag and HudDrag.draw_header_hint then
        HudDrag.draw_header_hint(px, py, panel_w)
    end

    local cy = py + HUD_PAD_Y
    Render.Text(font_hud, 13, "PARADOX", Vec2(x, cy), Color(0, 220, 255, 255))
    cy = cy + 18

    if show_combo_block then
        cy = cy + 4
        draw_hud_separator(x, cy, inner_w)
        cy = cy + HUD_SECTION

        local phase_col = get_combo_phase_color(state.phase)
        if not combo_active then phase_col = Color(110, 125, 145, 200) end
        local phase_label = truncate_to_width(font_mono, 11, PHASE_LABEL[state.phase] or state.phase,
            inner_w - 58)
        Render.Text(font_hud, 12, "Combo", Vec2(x, cy), Color(180, 200, 220, 230))
        Render.Text(font_mono, 11, phase_label, Vec2(x + 52, cy + 1), phase_col)
        cy = cy + HUD_LINE_H

        if combo_active then
            Render.Text(font_mono, 10,
                truncate_to_width(font_mono, 10,
                    string.format("target: %s  |  track: %s",
                        state.target and state.target:valid() and "locked" or "none",
                        should_keep_tracking() and "ON" or "off"),
                    inner_w),
                Vec2(x, cy), Color(150, 165, 180, 215))
            cy = cy + 13

            if current_item_id and (state.phase == S.ITEMS_AIM or state.phase == S.ITEMS_CAST) then
                Render.Text(font_mono, 10,
                    truncate_to_width(font_mono, 10, "item: " .. item_entry.def.name, inner_w),
                    Vec2(x, cy), Color(200, 140, 255, 235))
                cy = cy + 13
            end

            if state.last_msg ~= "" then
                Render.Text(font_mono, 10,
                    truncate_to_width(font_mono, 10, state.last_msg, inner_w),
                    Vec2(x, cy), Color(185, 190, 200, 225))
                cy = cy + 13
            end
        end
    end

    if show_assist then
        cy = cy + 4
        draw_hud_separator(x, cy, inner_w)
        cy = cy + HUD_SECTION

        if show_grenade_assist then
            local grenade_col = Color(255, 140, 60, 255)
            if assist.grenade.phase == GS.CAST then grenade_col = Color(255, 100, 40, 255) end
            if assist.grenade.phase == GS.RESTORE then grenade_col = Color(180, 120, 255, 255) end
            local grenade_label = GRENADE_LABEL[assist.grenade.phase] or assist.grenade.phase
            Render.Text(font_hud, 12, "Grenade", Vec2(x, cy), Color(180, 200, 220, 230))
            Render.Text(font_mono, 11, grenade_label, Vec2(x + 58, cy + 1), grenade_col)
            cy = cy + HUD_LINE_H
            if assist.grenade.msg ~= "" then
                Render.Text(font_mono, 10,
                    truncate_to_width(font_mono, 10, assist.grenade.msg, inner_w),
                    Vec2(x, cy), Color(185, 190, 200, 225))
                cy = cy + 13
            end
        end

        if show_wall_assist and ParadoxWall then
            local wall_phase = ParadoxWall.get_assist_phase and ParadoxWall.get_assist_phase() or "IDLE"
            local wall_col = Color(80, 220, 255, 255)
            if wall_phase == "SELECT" then wall_col = Color(60, 200, 255, 255) end
            if wall_phase == "CONFIRM" then wall_col = Color(40, 170, 255, 255) end
            if wall_phase == "RESTORE" then wall_col = Color(180, 120, 255, 255) end
            local wall_label = WALL_LABEL[wall_phase] or wall_phase
            Render.Text(font_hud, 12, "Wall", Vec2(x, cy), Color(180, 200, 220, 230))
            Render.Text(font_mono, 11, wall_label, Vec2(x + 58, cy + 1), wall_col)
            cy = cy + HUD_LINE_H
            local wall_msg = ParadoxWall.get_assist_msg and ParadoxWall.get_assist_msg() or ""
            if wall_msg ~= "" then
                Render.Text(font_mono, 10,
                    truncate_to_width(font_mono, 10, wall_msg, inner_w),
                    Vec2(x, cy), Color(185, 190, 200, 225))
                cy = cy + 13
            end
        end

        if show_swap_assist and ParadoxSwap then
            local swap_phase = ParadoxSwap.get_assist_phase and ParadoxSwap.get_assist_phase() or "IDLE"
            local swap_col = Color(200, 100, 255, 255)
            if swap_phase == "CAST" then swap_col = Color(255, 80, 180, 255) end
            if swap_phase == "TRACK" then swap_col = Color(180, 120, 255, 255) end
            if swap_phase == "RESTORE" then swap_col = Color(160, 140, 255, 255) end
            local swap_label = SWAP_LABEL[swap_phase] or swap_phase
            Render.Text(font_hud, 12, "Swap", Vec2(x, cy), Color(180, 200, 220, 230))
            Render.Text(font_mono, 11, swap_label, Vec2(x + 58, cy + 1), swap_col)
            cy = cy + HUD_LINE_H
            local swap_msg = ParadoxSwap.get_assist_msg and ParadoxSwap.get_assist_msg() or ""
            if swap_msg ~= "" then
                Render.Text(font_mono, 10,
                    truncate_to_width(font_mono, 10, swap_msg, inner_w),
                    Vec2(x, cy), Color(185, 190, 200, 225))
                cy = cy + 13
            end
        end

        if show_carbine_assist then
            local assist_col = Color(255, 200, 60, 255)
            if assist.carbine.phase == AS.FIRE then assist_col = Color(255, 140, 40, 255) end
            local assist_label = ASSIST_LABEL[assist.carbine.phase] or assist.carbine.phase
            Render.Text(font_hud, 12, "Carbine", Vec2(x, cy), Color(180, 200, 220, 230))
            Render.Text(font_mono, 11, assist_label, Vec2(x + 58, cy + 1), assist_col)
            cy = cy + HUD_LINE_H

            if assist.carbine.msg ~= "" then
                Render.Text(font_mono, 10,
                    truncate_to_width(font_mono, 10, assist.carbine.msg, inner_w),
                    Vec2(x, cy), Color(185, 190, 200, 225))
                cy = cy + 13
            end

            if show_kill_pred then
                local pred = assist.carbine.last_pred
                local safe_dmg = pred.total_safe or pred.total
                local is_lethal = safe_dmg >= assist.carbine.last_pred_hp
                local lethal_col = is_lethal and Color(80, 255, 120, 230) or Color(255, 180, 80, 230)
                Render.Text(font_mono, 10,
                    string.format("dmg %.0f/%.0f (%d%%)%s",
                        safe_dmg, assist.carbine.last_pred_hp, pred.charge_pct or 0,
                        is_lethal and " LETHAL" or ""),
                    Vec2(x, cy), lethal_col)
                cy = cy + 13
            end
        end
    end

    if show_items then
        cy = cy + 4
        draw_hud_separator(x, cy, inner_w)
        cy = cy + HUD_SECTION

        local _, by_id = scan_item_slots(lp)
        state.loadout = by_id

        Render.Text(font_hud, 12, "Items", Vec2(x, cy), Color(180, 200, 220, 230))
        cy = cy + HUD_LINE_H

        for i = 1, #COMBO_ITEMS do
            local def = COMBO_ITEMS[i]
            if not def or not def.id or not def.name then goto continue_item end
            local owned = by_id[def.id]
            local dot_col, status_text, text_col

            if not owned then
                dot_col = Color(70, 75, 85, 180)
                status_text = "—"
                text_col = Color(95, 100, 110, 175)
            elseif owned.ready then
                dot_col = Color(70, 230, 110, 240)
                status_text = string.format("S%d", owned.idx)
                text_col = Color(195, 205, 215, 235)
            elseif owned.status == "cd" then
                dot_col = Color(255, 170, 70, 240)
                status_text = string.format("S%d %.1fs", owned.idx, owned.cd or 0)
                text_col = Color(220, 175, 120, 230)
            else
                dot_col = Color(160, 165, 175, 210)
                status_text = string.format("S%d %s", owned.idx, owned.status)
                text_col = Color(175, 180, 190, 220)
            end

            local is_current = current_item_id == def.id
                and (state.phase == S.ITEMS_AIM or state.phase == S.ITEMS_CAST)
            if is_current then
                dot_col = Color(210, 120, 255, 255)
                text_col = Color(220, 180, 255, 245)
            end

            local tag = ""
            if def.cast and item_use_enabled(def) then
                tag = "combo"
            elseif def.weapon_finisher and owned and weapon_finisher_enabled(def) then
                tag = "weapon"
            elseif not def.cast and owned then
                tag = "proc"
            end

            local tag_col = Color(0, 200, 255, 170)
            if tag == "proc" then tag_col = Color(180, 140, 255, 160) end
            if tag == "weapon" then tag_col = Color(255, 180, 80, 180) end
            draw_hud_item_row(x, cy, inner_w, def.name, status_text, tag, dot_col, text_col, tag_col)
            cy = cy + HUD_ROW_H
            ::continue_item::
        end
    end

end

function ParadoxCombo.on_draw()
    if not is_paradox then return end
    ensure_fonts()

    if HudDrag and ui and ui.hud_drag_lock then
        HudDrag.set_locked(ui.hud_drag_lock:Get())
    end

    local lp = entity_list.local_pawn()
    if not lp or not lp:valid() or not lp:is_alive() then return end

    pcall(draw_fov_visuals)
    pcall(draw_paradox_side_hud, lp)

    if ParadoxBuild and ParadoxBuild.draw_hud then
        pcall(ParadoxBuild.draw_hud)
    end

    if not ui or not ui.draw_debug or not ui.draw_debug:Get() then return end

    local cam = safe(function() return utils.get_camera_pos() end)
    local pitch = state.pitch_deg ~= 0 and state.pitch_deg or resolve_down_pitch()
    local yaw   = state.user_yaw or state.locked_yaw
    if yaw == nil then
        local cam_ang = safe(function() return utils.get_camera_angles() end)
        yaw = cam_ang and cam_ang.yaw or 0
    end
    local aim_pos, ground = get_ground_from_view(cam, pitch, yaw)
    local ankle = safe(function() return lp:get_bone_pos("ankle_R") end)
        or safe(function() return lp:get_bone_pos("ankle_L") end)

    if ui.draw_debug:Get() then
        local origin = safe(function() return lp:get_origin() end)
        if origin then draw_world_marker(origin, Color(255, 255, 255, 200), "origin") end
        if ankle  then draw_world_marker(ankle,  Color(255, 200, 80, 255),  "ankle") end
        if ground then draw_world_marker(ground, Color(80, 220, 255, 255),  "ground") end
        if aim_pos then draw_world_marker(aim_pos, Color(255, 60, 60, 255), "AIM") end

        local dbg_target = state.target
            or (assist.grenade.phase ~= GS.IDLE and assist.grenade.target)
        if dbg_target and dbg_target:valid() then
            local static_feet = get_enemy_feet_ground_static(dbg_target)
            if static_feet then
                draw_world_marker(static_feet, Color(255, 255, 80, 220), "feet now")
            end
            local pred_feet = get_predicted_enemy_feet_ground(dbg_target, lp, ui_a.grenade_lead_ms:Get() / 1000.0)
            if pred_feet then
                draw_world_marker(pred_feet, Color(80, 255, 120, 255), "feet pred")
            end
        end

        if state.wall_pos then
            draw_world_marker(state.wall_pos, Color(80, 200, 255, 255), "wall")
        elseif ParadoxWall and ParadoxWall.get_wall_pos then
            local wp = ParadoxWall.get_wall_pos()
            if wp then draw_world_marker(wp, Color(60, 180, 255, 255), "wall") end
        end

        if cam and aim_pos then
            local c1, v1 = Render.WorldToScreen(cam)
            local c2, v2 = Render.WorldToScreen(aim_pos)
            if v1 and v2 and c1 and c2 then
                Render.Line(c1, c2, Color(255, 120, 40, 180), 1)
            end
        end
    end
end

function ParadoxCombo.init()
    get_pitch_down_sign()
end
