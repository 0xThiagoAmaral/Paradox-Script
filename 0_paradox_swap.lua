-- Paradox Paradoxical Swap — aim + predict + cast + post-cast track
ParadoxSwap = ParadoxSwap or {}

local UNIT_METER = 37.7358490566
local SWAP_SLOT  = 3
local SWAP_INPUT = InputBitMask_t.IN_ABILITY4
local SWAP_FALLBACK_SPEED = 3500.0
local SWAP_MAX_RANGE_M    = 25.0
local SWAP_PREDICT_BONE   = "spine_2"
local PSILENT_BONE_FALLBACK = { "spine_2", "pelvis", "spine_0", "neck_0", "head" }

local SS = {
    IDLE    = "IDLE",
    AIM     = "AIM",
    CAST    = "CAST",
    TRACK   = "TRACK",
    RESTORE = "RESTORE",
}

local AIM_MODE = { PSILENT = 0, SMOOTH = 1, HYBRID = 2 }

local function require_mod(name)
    local ok, mod = pcall(require, name)
    return ok and mod or nil
end

local Prediction = require_mod("prediction")

local ui_a
local assist = {
    phase = SS.IDLE, t0 = 0, track_until = 0,
    target = nil, aim_pos = nil, lead_t = 0,
    saved_pitch = nil, saved_yaw = nil, msg = "",
}

local function safe(fn)
    local ok, v = pcall(fn)
    return ok and v or nil
end

function ParadoxSwap.bind_menu(ui_assist)
    ui_a = ui_assist
end

function ParadoxSwap.is_busy()
    return assist.phase ~= SS.IDLE
end

function ParadoxSwap.get_assist_phase()
    return assist.phase
end

function ParadoxSwap.get_assist_msg()
    return assist.msg
end

local function assist_elapsed()
    return global_vars.curtime() - assist.t0
end

local function slot_ready(lp, slot)
    slot = slot or SWAP_SLOT
    local ab = safe(function() return lp:get_ability_by_slot(slot) end)
    if not ab or not ab:valid() then return false end
    local st = safe(function() return ab:can_be_executed() end)
    return st == 0 or st == true or st == 23
end

local function ability_status(lp, slot)
    slot = slot or SWAP_SLOT
    local ab = safe(function() return lp:get_ability_by_slot(slot) end)
    if not ab or not ab:valid() then return "nil" end
    local st = safe(function() return ab:can_be_executed() end)
    if st == 0 then return "ready" end
    if st == 2 then return "cd" end
    if st == 10 then return "busy" end
    return "st=" .. tostring(st)
end

local function is_enemy(lp, ent)
    if not lp or not ent or not ent:valid() or not ent:is_alive() then return false end
    return lp.m_iTeamNum ~= ent.m_iTeamNum
end

local function get_bone_name()
    if not ui_a or not ui_a.swap_bone then return SWAP_PREDICT_BONE end
    local idx = ui_a.swap_bone:Get()
    if idx == 1 then return "pelvis" end
    if idx == 2 then return "head" end
    return "spine_2"
end

local function get_target_pos_for_bone(target, lead_t, bone)
    if not target or not target:valid() then return nil end
    lead_t = lead_t or 0
    bone = bone or SWAP_PREDICT_BONE

    if lead_t > 0 and Prediction then
        if Prediction.PredictPlayerAdvanced then
            local pos = Prediction.PredictPlayerAdvanced(target, lead_t, bone, {
                use_acceleration = true,
                clamp_to_max_speed = true,
                max_lead_distance = 12 * UNIT_METER,
                multi_sample = lead_t > 0.04,
                sample_count = 3,
            })
            if pos then return pos end
        end
        if Prediction.PredictPlayer then
            local pos = Prediction.PredictPlayer(target, lead_t, nil, nil, nil, nil, bone, true)
            if pos then return pos end
        end
    end

    return safe(function() return target:get_bone_pos(bone) end)
        or safe(function() return target:get_origin() end)
end

local function get_target_pos(target, lead_t)
    return get_target_pos_for_bone(target, lead_t, get_bone_name())
end

local function psilent_bone_order()
    local primary = get_bone_name()
    local order = { primary }
    for i = 1, #PSILENT_BONE_FALLBACK do
        local bone = PSILENT_BONE_FALLBACK[i]
        if bone ~= primary then
            order[#order + 1] = bone
        end
    end
    return order
end

local function collect_psilent_positions(target, lead_t)
    local positions = {}
    local seen = {}
    local function add(pos)
        if not pos then return end
        local key = string.format("%.0f:%.0f:%.0f", pos.x, pos.y, pos.z)
        if seen[key] then return end
        seen[key] = true
        positions[#positions + 1] = pos
    end

    for _, bone in ipairs(psilent_bone_order()) do
        add(get_target_pos_for_bone(target, lead_t, bone))
    end
    add(safe(function() return target:get_origin() end))
    return positions
end

local function get_swap_speed(lp)
    local ab = safe(function() return lp:get_ability_by_slot(SWAP_SLOT) end)
    if Utils and Utils.GetAbilityProjectileSpeed and ab then
        return Utils.GetAbilityProjectileSpeed(ab) or SWAP_FALLBACK_SPEED
    end
    return SWAP_FALLBACK_SPEED
end

local function estimate_swap_lead_time(lp, target, extra_s)
    extra_s = extra_s or 0
    if not target or not target:valid() then return extra_s + 0.06 end

    local cam = safe(function() return utils.get_camera_pos() end)
    if not cam then return extra_s + 0.06 end

    local speed = lp and get_swap_speed(lp) or SWAP_FALLBACK_SPEED
    local predicted = get_target_pos(target, 0)
    if not predicted then return extra_s + 0.06 end

    local t = 0
    if speed > 100 then
        for _ = 1, 8 do
            local dist = cam:Distance(predicted)
            local new_t = dist / speed
            if math.abs(new_t - t) < 0.005 then break end
            t = new_t
            predicted = get_target_pos(target, t) or predicted
        end
    else
        local vel = Prediction and Prediction.GetTrackedVelocity and Prediction.GetTrackedVelocity(target)
        if vel and vel:Length2D() > 40 then
            t = 0.10
        else
            t = 0.04
        end
    end

    return t + extra_s
end

local function get_swap_aim_pos(target, lp)
    if not target or not target:valid() then return nil, 0 end
    local use_predict = ui_a and ui_a.swap_predict and ui_a.swap_predict:Get()
    local extra = ui_a and ui_a.swap_lead_ms and (ui_a.swap_lead_ms:Get() / 1000.0) or 0

    if use_predict and Prediction then
        local lead_t = estimate_swap_lead_time(lp, target, extra)
        local pos = get_target_pos(target, lead_t)
        return pos, lead_t
    end

    return get_target_pos(target, 0), 0
end

local function aim_cfg_from_assist()
    return {
        mode = ui_a and ui_a.swap_aim_mode and ui_a.swap_aim_mode:Get() or AIM_MODE.HYBRID,
        smooth = ui_a and ui_a.swap_smooth and ui_a.swap_smooth:Get() or 15,
        psilent_fov = ui_a and ui_a.swap_psilent_fov and ui_a.swap_psilent_fov:Get() or 30,
        max_fov = ui_a and ui_a.swap_fov and ui_a.swap_fov:Get() or 30,
    }
end

local function can_psilent_positions(cmd, positions, cfg)
    if not positions or not cfg then return false end
    local cam = cmd.orig_vec_camera_position or safe(function() return utils.get_camera_pos() end)
    local cam_ang = safe(function() return utils.get_camera_angles() end)
    if not cam or not cam_ang then return false end

    local psilent_fov = cfg.psilent_fov or 30
    for i = 1, #positions do
        local pos = positions[i]
        local ang = utils.calc_angle(cam, pos)
        local fov = utils.get_fov(cam_ang, ang)
        if fov <= psilent_fov and safe(function() return cmd:can_psilent_at_pos(pos) end) then
            return true
        end
    end
    return false
end

local function try_psilent_positions(cmd, positions, cfg)
    if not positions or not cfg then return false, nil end
    local cam = cmd.orig_vec_camera_position or safe(function() return utils.get_camera_pos() end)
    local cam_ang = safe(function() return utils.get_camera_angles() end)
    if not cam or not cam_ang then return false, nil end

    local psilent_fov = cfg.psilent_fov or 30
    for i = 1, #positions do
        local pos = positions[i]
        local ang = utils.calc_angle(cam, pos)
        local fov = utils.get_fov(cam_ang, ang)
        if fov <= psilent_fov and safe(function() return cmd:can_psilent_at_pos(pos) end) then
            pcall(function() cmd:set_psilent_at_pos(pos) end)
            return true, pos
        end
    end
    return false, nil
end

local function apply_swap_aim(cmd, pos, cfg, target, lead_t)
    if not pos or not cfg then return false, "none", pos end
    local cam = cmd.orig_vec_camera_position or safe(function() return utils.get_camera_pos() end)
    local cam_ang = safe(function() return utils.get_camera_angles() end)
    if not cam or not cam_ang then return false, "none", pos end

    local mode = cfg.mode or AIM_MODE.PSILENT
    local positions = { pos }
    if target and target:valid() and (mode == AIM_MODE.PSILENT or mode == AIM_MODE.HYBRID) then
        positions = collect_psilent_positions(target, lead_t or 0)
    end

    if mode == AIM_MODE.PSILENT or mode == AIM_MODE.HYBRID then
        local ok, hit_pos = try_psilent_positions(cmd, positions, cfg)
        if ok then
            return true, "psilent", hit_pos
        end
        if mode == AIM_MODE.PSILENT then
            return false, "psilent_wait", pos
        end
    end

    local ang = utils.calc_angle(cam, pos)
    local fov = utils.get_fov(cam_ang, ang)
    if fov > (cfg.max_fov or 180) then
        return false, "out_fov", pos
    end

    local pitch = ang.pitch or ang.x or 0
    local yaw = ang.yaw or ang.y or 0
    if (cfg.smooth or 1) > 1 and cmd.smooth_aim then
        pcall(function() cmd:smooth_aim(ang, cfg.smooth) end)
    else
        cmd.viewangles = Angle(pitch, yaw, 0)
        pcall(function() cmd.ang_camera_angles = Angle(pitch, yaw, 0) end)
        if utils.set_camera_angles then
            utils.set_camera_angles(Angle(pitch, yaw, 0))
        end
    end
    return true, "smooth", pos
end

local function is_aim_settled(cmd, pos, cfg, tol, target, lead_t)
    if not pos or not cfg then return false end
    tol = tol or 8
    local mode = cfg.mode or AIM_MODE.PSILENT
    if mode == AIM_MODE.PSILENT or mode == AIM_MODE.HYBRID then
        local positions = { pos }
        if target and target:valid() then
            positions = collect_psilent_positions(target, lead_t or 0)
        end
        if can_psilent_positions(cmd, positions, cfg) then
            return true
        end
        if mode == AIM_MODE.PSILENT then
            return false
        end
    end

    local cam = cmd.orig_vec_camera_position or safe(function() return utils.get_camera_pos() end)
    local cam_ang = safe(function() return utils.get_camera_angles() end)
    if not cam or not cam_ang then return false end
    local ang = utils.calc_angle(cam, pos)
    return utils.get_fov(cam_ang, ang) <= tol
end

local function clear_primary_attack(cmd)
    pcall(function() cmd:clear_buttonstate1(InputBitMask_t.IN_ATTACK) end)
    if cmd.clear_buttonstate2 then
        pcall(function() cmd:clear_buttonstate2(InputBitMask_t.IN_ATTACK) end)
    end
end

local function clear_swap_slot(cmd)
    pcall(function() cmd:clear_buttonstate1(SWAP_INPUT) end)
    if cmd.clear_buttonstate2 then
        pcall(function() cmd:clear_buttonstate2(SWAP_INPUT) end)
    end
    if cmd.execute_ability_indices ~= nil then
        cmd.execute_ability_indices = cmd.execute_ability_indices & ~(1 << SWAP_SLOT)
    end
end

local function press_swap_slot(cmd)
    cmd:add_buttonstate1(SWAP_INPUT)
    if cmd.add_buttonstate2 then cmd:add_buttonstate2(SWAP_INPUT) end
    cmd.execute_ability_indices = (cmd.execute_ability_indices or 0) | (1 << SWAP_SLOT)
end

local function capture_saved_aim(cmd)
    local cam_ang = safe(function() return utils.get_camera_angles() end) or cmd.viewangles
    if not cam_ang then return false end
    assist.saved_pitch = cam_ang.pitch or cam_ang.x or 0
    assist.saved_yaw = cam_ang.yaw or cam_ang.y or 0
    return true
end

local function normalize_yaw_delta(a, b)
    local d = (a or 0) - (b or 0)
    while d > 180 do d = d - 360 end
    while d < -180 do d = d + 360 end
    return d
end

local function get_current_angles()
    local cam_ang = safe(function() return utils.get_camera_angles() end)
    if not cam_ang then return nil, nil end
    return cam_ang.pitch or cam_ang.x or 0, cam_ang.yaw or cam_ang.y or 0
end

local function is_restore_settled()
    if assist.saved_pitch == nil or assist.saved_yaw == nil then return true end
    local cp, cy = get_current_angles()
    if cp == nil or cy == nil then return assist_elapsed() >= 0.03 end
    local tol = ui_a and ui_a.swap_restore_tol and ui_a.swap_restore_tol:Get() or 5
    return math.abs(cp - assist.saved_pitch) < tol
        and math.abs(normalize_yaw_delta(cy, assist.saved_yaw)) < tol
end

local function complete_assist(cmd, msg)
    clear_swap_slot(cmd)
    clear_primary_attack(cmd)
    assist.phase = SS.IDLE
    assist.track_until = 0
    assist.target = nil
    assist.aim_pos = nil
    assist.lead_t = 0
    assist.saved_pitch = nil
    assist.saved_yaw = nil
    assist.msg = msg or ""
end

function ParadoxSwap.reset(cmd)
    if assist.phase ~= SS.IDLE then
        complete_assist(cmd, "")
    end
end

local function find_target_in_fov(lp, cmd, max_fov)
    local cam = (cmd and cmd.orig_vec_camera_position) or safe(function() return utils.get_camera_pos() end)
    local cam_ang = safe(function() return utils.get_camera_angles() end) or (cmd and cmd.viewangles)
    if not cam or not cam_ang then return nil end

    local best, best_fov = nil, max_fov or 30
    for _, pawn in ipairs(entity_list.by_class_name("C_CitadelPlayerPawn")) do
        if is_enemy(lp, pawn) then
            local pos = get_target_pos(pawn, 0)
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

local function is_in_swap_range(lp, target)
    local origin = safe(function() return lp:get_origin() end)
    local pos = get_target_pos(target, 0)
    if not origin or not pos then return true end
    local max_r = (ui_a and ui_a.swap_max_range_m and ui_a.swap_max_range_m:Get() or SWAP_MAX_RANGE_M) * UNIT_METER
    return origin:Distance(pos) <= max_r
end

local function user_pressed_swap(cmd)
    local mask = SWAP_INPUT
    if cmd.buttonstate1 and (cmd.buttonstate1 & mask) ~= 0 then return true end
    if cmd.buttonstate2 and (cmd.buttonstate2 & mask) ~= 0 then return true end
    if cmd.execute_ability_indices and (cmd.execute_ability_indices & (1 << SWAP_SLOT)) ~= 0 then
        return true
    end
    return false
end

local function other_busy()
    if ParadoxCombo and ParadoxCombo.is_combo_active and ParadoxCombo.is_combo_active() then
        return true
    end
    if ParadoxWall and ParadoxWall.is_busy and ParadoxWall.is_busy() then
        return true
    end
    return false
end

local function start_assist(target, lp, msg)
    assist.target = target
    assist.aim_pos, assist.lead_t = get_swap_aim_pos(target, lp)
    assist.phase = SS.AIM
    assist.t0 = global_vars.curtime()
    assist.track_until = 0
    assist.msg = msg or "swap: AIM"
end

function ParadoxSwap.run_assist(cmd, lp)
    if assist.phase == SS.IDLE and (not ui_a or not ui_a.swap_enable or not ui_a.swap_enable:Get()) then
        return false
    end

    if assist.phase == SS.IDLE then
        if other_busy() then return false end
        if not slot_ready(lp, SWAP_SLOT) then return false end

        local triggered = false
        if ui_a.swap_mode and ui_a.swap_mode:Get() == 0 then
            triggered = user_pressed_swap(cmd)
        else
            triggered = ui_a.swap_key and ui_a.swap_key:IsPressed()
        end
        if not triggered then return false end

        local target = find_target_in_fov(lp, cmd, ui_a.swap_fov:Get())
        if not target then
            assist.msg = string.format("swap: no target (%.0f°)", ui_a.swap_fov:Get())
            return false
        end
        if not is_in_swap_range(lp, target) then
            assist.msg = "swap: target out of range"
            return false
        end

        capture_saved_aim(cmd)
        start_assist(target, lp, "swap: AIM")
    end

    if assist.phase == SS.IDLE then return false end

    if not assist.target or not assist.target:valid() or not assist.target:is_alive() then
        complete_assist(cmd, "swap: target lost")
        return true
    end

    assist.aim_pos, assist.lead_t = get_swap_aim_pos(assist.target, lp)
    if not assist.aim_pos then
        complete_assist(cmd, "swap: aim pos lost")
        return true
    end

    clear_primary_attack(cmd)
    local cfg = aim_cfg_from_assist()

    if assist.phase == SS.AIM then
        local _, phase, hit_pos = apply_swap_aim(cmd, assist.aim_pos, cfg, assist.target, assist.lead_t)
        if hit_pos then assist.aim_pos = hit_pos end
        if ui_a.swap_predict:Get() and assist.lead_t > 0 then
            assist.msg = string.format("swap: %s (%.0fms)", phase, assist.lead_t * 1000)
        else
            assist.msg = string.format("swap: %s", phase)
        end

        local delay = (ui_a.swap_aim_delay_ms:Get() or 50) / 1000.0
        local tol = ui_a.swap_aim_tol and ui_a.swap_aim_tol:Get() or 10
        local timeout = (ui_a.swap_ready_wait_ms:Get() or 300) / 1000.0
        if assist_elapsed() >= delay
            and is_aim_settled(cmd, assist.aim_pos, cfg, tol, assist.target, assist.lead_t) then
            assist.phase = SS.CAST
            assist.t0 = global_vars.curtime()
            assist.msg = "swap: CAST"
        elseif assist_elapsed() >= delay + timeout then
            assist.phase = SS.CAST
            assist.t0 = global_vars.curtime()
            assist.msg = "swap: CAST (timeout)"
        end
        return true
    end

    if assist.phase == SS.CAST then
        local _, _, hit_pos = apply_swap_aim(cmd, assist.aim_pos, cfg, assist.target, assist.lead_t)
        if hit_pos then assist.aim_pos = hit_pos end
        local sst = ability_status(lp, SWAP_SLOT)
        local psilent_only = cfg.mode == AIM_MODE.PSILENT
        local can_fire = not psilent_only
            or can_psilent_positions(cmd, collect_psilent_positions(assist.target, assist.lead_t), cfg)
            or assist_elapsed() >= (ui_a.swap_ready_wait_ms:Get() or 300) / 1000.0
        if slot_ready(lp, SWAP_SLOT) and can_fire then
            press_swap_slot(cmd)
        else
            clear_swap_slot(cmd)
        end

        assist.msg = string.format("swap: CAST (%s)", sst)
        local hold = (ui_a.swap_cast_hold_ms:Get() or 100) / 1000.0
        if sst == "cd" or sst == "busy" or assist_elapsed() >= hold then
            if ui_a.swap_track_enable and ui_a.swap_track_enable:Get() then
                assist.phase = SS.TRACK
                assist.t0 = global_vars.curtime()
                assist.track_until = global_vars.curtime() + (ui_a.swap_track_ms:Get() or 1100) / 1000.0
                assist.msg = "swap: TRACK"
            elseif ui_a.swap_restore and ui_a.swap_restore:Get() and assist.saved_pitch then
                assist.phase = SS.RESTORE
                assist.t0 = global_vars.curtime()
                assist.msg = "swap: RESTORE"
            else
                complete_assist(cmd, "swap: done")
            end
        end
        return true
    end

    if assist.phase == SS.TRACK then
        local _, _, hit_pos = apply_swap_aim(cmd, assist.aim_pos, cfg, assist.target, assist.lead_t)
        if hit_pos then assist.aim_pos = hit_pos end
        clear_swap_slot(cmd)
        assist.msg = "swap: TRACK"
        if global_vars.curtime() >= assist.track_until then
            if ui_a.swap_restore and ui_a.swap_restore:Get() and assist.saved_pitch then
                assist.phase = SS.RESTORE
                assist.t0 = global_vars.curtime()
                assist.msg = "swap: RESTORE"
            else
                complete_assist(cmd, "swap: done")
            end
        end
        return true
    end

    if assist.phase == SS.RESTORE then
        clear_swap_slot(cmd)
        clear_primary_attack(cmd)
        local pitch, yaw = assist.saved_pitch or 0, assist.saved_yaw or 0
        cmd.viewangles = Angle(pitch, yaw, 0)
        if utils.set_camera_angles then utils.set_camera_angles(Angle(pitch, yaw, 0)) end
        assist.msg = "swap: RESTORE"
        if is_restore_settled() or assist_elapsed() >= 0.25 then
            complete_assist(cmd, "swap: done")
        end
        return true
    end

    return false
end
