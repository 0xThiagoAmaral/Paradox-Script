-- Paradox Time Wall — placement + two-phase cast (offensive / defensive)
ParadoxWall = ParadoxWall or {}

local UNIT_METER = 37.7358490566
local WALL_SLOT  = 1
local WALL_INPUT = InputBitMask_t.IN_ABILITY2

local WALL_MODE = { OFFENSIVE = 1, DEFENSIVE = 2 }

local WS = {
    IDLE    = "IDLE",
    AIM     = "AIM",
    SELECT  = "SELECT",
    CONFIRM = "CONFIRM",
    RESTORE = "RESTORE",
}

local AIM_MODE = { PSILENT = 0, SMOOTH = 1, HYBRID = 2 }

local function require_mod(name)
    local ok, mod = pcall(require, name)
    return ok and mod or nil
end

local Prediction = require_mod("prediction")

local ui_c, ui_a
local assist = {
    phase = WS.IDLE, t0 = 0, target = nil, wall_pos = nil, mode = WALL_MODE.OFFENSIVE,
    saved_pitch = nil, saved_yaw = nil, msg = "",
}
local defense = { last_cast_t = 0 }

local function safe(fn)
    local ok, v = pcall(fn)
    return ok and v or nil
end

function ParadoxWall.bind_menu(ui_combo, ui_assist)
    ui_c = ui_combo
    ui_a = ui_assist
end

function ParadoxWall.is_busy()
    return assist.phase ~= WS.IDLE
end

function ParadoxWall.get_assist_phase()
    return assist.phase
end

local function wall_ui()
    return ui_a or ui_c
end

local function slot_ready(lp, slot)
    slot = slot or WALL_SLOT
    local ab = safe(function() return lp:get_ability_by_slot(slot) end)
    if not ab or not ab:valid() then return false end
    local st = safe(function() return ab:can_be_executed() end)
    return st == 0 or st == true or st == 23
end

local function ability_status(lp, slot)
    slot = slot or WALL_SLOT
    local ab = safe(function() return lp:get_ability_by_slot(slot) end)
    if not ab or not ab:valid() then return "nil" end
    local st = safe(function() return ab:can_be_executed() end)
    if st == 0 then return "ready" end
    if st == 2 then return "cd" end
    if st == 10 then return "busy" end
    return "st=" .. tostring(st)
end

local function is_wall_selected(lp)
    local ab = safe(function() return lp:get_ability_by_slot(WALL_SLOT) end)
    if not ab or not ab:valid() then return false end
    if HERO_LIB and HERO_LIB.is_ability_selected then
        return HERO_LIB.is_ability_selected(lp, ab)
    end
    return false
end

local function is_enemy(lp, ent)
    if not lp or not ent or not ent:valid() or not ent:is_alive() then return false end
    return lp.m_iTeamNum ~= ent.m_iTeamNum
end

local function trace_ground_at(x, y, ref_z)
    if not trace or not trace.line then
        return Vector(x, y, ref_z)
    end
    local start = Vector(x, y, ref_z + 512)
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

local function anchor_pos(target, lp)
    if target and target:valid() then
        return safe(function() return target:get_origin() end)
            or safe(function() return target:get_bone_pos("pelvis") end)
    end
    return safe(function() return lp:get_origin() end)
end

local function placement_fraction(mode, source)
    if mode == WALL_MODE.DEFENSIVE then
        if source == "combo" and ui_c and ui_c.wall_defensive_pct then
            return ui_c.wall_defensive_pct:Get() / 100.0
        end
        if ui_a and ui_a.wall_defensive_pct then
            return ui_a.wall_defensive_pct:Get() / 100.0
        end
        return 0.30
    end
    if source == "combo" and ui_c and ui_c.wall_offensive_pct then
        return ui_c.wall_offensive_pct:Get() / 100.0
    end
    if ui_a and ui_a.wall_offensive_pct then
        return ui_a.wall_offensive_pct:Get() / 100.0
    end
    return 0.55
end

local function wall_height_m(source)
    if source == "combo" and ui_c and ui_c.wall_height_m then
        return ui_c.wall_height_m:Get()
    end
    if ui_a and ui_a.wall_height_m then
        return ui_a.wall_height_m:Get()
    end
    return 1.75
end

function ParadoxWall.compute_pos(lp, target, mode, source)
    source = source or "assist"
    if not lp or not lp:valid() then return nil end

    local my_pos = safe(function() return lp:get_origin() end)
    local en_pos = anchor_pos(target, lp)
    if not my_pos or not en_pos then return nil end

    local dx, dy = en_pos.x - my_pos.x, en_pos.y - my_pos.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.1 then return nil end

    local frac = placement_fraction(mode, source)
    local min_d = 2.5 * UNIT_METER
    local max_d = 12.0 * UNIT_METER
    if mode == WALL_MODE.DEFENSIVE then
        max_d = math.min(max_d, 5.5 * UNIT_METER)
    end
    local dist = math.max(min_d, math.min(len * frac, max_d))

    local px = my_pos.x + (dx / len) * dist
    local py = my_pos.y + (dy / len) * dist
    local ground = trace_ground_at(px, py, math.max(my_pos.z, en_pos.z))
    local pos = Vector(ground.x, ground.y, ground.z + wall_height_m(source) * UNIT_METER)

    local use_solver = false
    if source == "combo" and ui_c and ui_c.wall_use_solver then
        use_solver = ui_c.wall_use_solver:Get()
    elseif ui_a and ui_a.wall_use_solver then
        use_solver = ui_a.wall_use_solver:Get()
    end

    if use_solver and Prediction and Prediction.FindBestWallTargetAdvanced then
        local cam = safe(function() return utils.get_camera_pos() end)
        local cam_ang = safe(function() return utils.get_camera_angles() end)
        local solver_m = 18.0
        if ui_a and ui_a.wall_solver_dist_m then
            solver_m = ui_a.wall_solver_dist_m:Get()
        end
        if cam and cam_ang then
            local best = Prediction.FindBestWallTargetAdvanced(
                en_pos, solver_m * UNIT_METER, cam, cam_ang, {
                    rays = 16,
                    max_fov = 45,
                    focus_pos = en_pos,
                    max_focus_distance = 360,
                })
            if best and best.pos then
                pos = best.pos
            end
        end
    end

    return pos
end

local function aim_cfg_from(source)
    if source == "combo" then
        return {
            mode = AIM_MODE.HYBRID,
            smooth = 12,
            psilent_fov = ui_c and ui_c.track_fov and ui_c.track_fov:Get() or 30,
            max_fov = ui_c and ui_c.track_fov and ui_c.track_fov:Get() or 30,
        }
    end
    return {
        mode = ui_a and ui_a.wall_aim_mode and ui_a.wall_aim_mode:Get() or AIM_MODE.HYBRID,
        smooth = ui_a and ui_a.wall_smooth and ui_a.wall_smooth:Get() or 15,
        psilent_fov = ui_a and ui_a.wall_psilent_fov and ui_a.wall_psilent_fov:Get() or 30,
        max_fov = ui_a and ui_a.wall_fov and ui_a.wall_fov:Get() or 30,
    }
end

function ParadoxWall.apply_aim(cmd, pos, cfg)
    if not pos or not cfg then return false, "none" end
    local cam = cmd.orig_vec_camera_position or safe(function() return utils.get_camera_pos() end)
    local cam_ang = safe(function() return utils.get_camera_angles() end)
    if not cam or not cam_ang then return false, "none" end

    local ang = utils.calc_angle(cam, pos)
    local fov = utils.get_fov(cam_ang, ang)
    local mode = cfg.mode or AIM_MODE.HYBRID

    if mode == AIM_MODE.PSILENT or mode == AIM_MODE.HYBRID then
        if fov <= (cfg.psilent_fov or 30) and safe(function() return cmd:can_psilent_at_pos(pos) end) then
            pcall(function() cmd:set_psilent_at_pos(pos) end)
            return true, "psilent"
        end
        if mode == AIM_MODE.PSILENT then
            return false, "psilent_wait"
        end
    end

    if fov > (cfg.max_fov or 180) then
        return false, "out_fov"
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
    return true, "smooth"
end

local function is_aim_settled(cmd, pos, cfg, tol)
    if not pos or not cfg then return false end
    tol = tol or 8
    local cam = cmd.orig_vec_camera_position or safe(function() return utils.get_camera_pos() end)
    local cam_ang = safe(function() return utils.get_camera_angles() end)
    if not cam or not cam_ang then return false end
    local ang = utils.calc_angle(cam, pos)
    local fov = utils.get_fov(cam_ang, ang)
    local mode = cfg.mode or AIM_MODE.HYBRID
    if mode == AIM_MODE.PSILENT or mode == AIM_MODE.HYBRID then
        if fov <= (cfg.psilent_fov or 30) and safe(function() return cmd:can_psilent_at_pos(pos) end) then
            return true
        end
        if mode == AIM_MODE.PSILENT then
            return fov <= tol
        end
    end
    return fov <= tol
end

local function clear_primary_attack(cmd)
    pcall(function() cmd:clear_buttonstate1(InputBitMask_t.IN_ATTACK) end)
    if cmd.clear_buttonstate2 then
        pcall(function() cmd:clear_buttonstate2(InputBitMask_t.IN_ATTACK) end)
    end
end

local function clear_wall_slot(cmd)
    pcall(function() cmd:clear_buttonstate1(WALL_INPUT) end)
    if cmd.clear_buttonstate2 then
        pcall(function() cmd:clear_buttonstate2(WALL_INPUT) end)
    end
    if cmd.execute_ability_indices ~= nil then
        cmd.execute_ability_indices = cmd.execute_ability_indices & ~(1 << WALL_SLOT)
    end
end

local function press_wall_slot(cmd)
    cmd:add_buttonstate1(WALL_INPUT)
    if cmd.add_buttonstate2 then cmd:add_buttonstate2(WALL_INPUT) end
    cmd.execute_ability_indices = (cmd.execute_ability_indices or 0) | (1 << WALL_SLOT)
end

local function press_attack(cmd)
    cmd:add_buttonstate1(InputBitMask_t.IN_ATTACK)
    if cmd.add_buttonstate2 then cmd:add_buttonstate2(InputBitMask_t.IN_ATTACK) end
end

local function assist_elapsed()
    return global_vars.curtime() - assist.t0
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
    local tol = ui_a and ui_a.wall_restore_tol and ui_a.wall_restore_tol:Get() or 5
    return math.abs(cp - assist.saved_pitch) < tol
        and math.abs(normalize_yaw_delta(cy, assist.saved_yaw)) < tol
end

local function complete_assist(cmd, msg)
    clear_wall_slot(cmd)
    clear_primary_attack(cmd)
    assist.phase = WS.IDLE
    assist.target = nil
    assist.wall_pos = nil
    assist.saved_pitch = nil
    assist.saved_yaw = nil
    assist.msg = msg or ""
end

local function find_target_in_fov(lp, cmd, max_fov)
    local cam = (cmd and cmd.orig_vec_camera_position) or safe(function() return utils.get_camera_pos() end)
    local cam_ang = safe(function() return utils.get_camera_angles() end) or (cmd and cmd.viewangles)
    if not cam or not cam_ang then return nil end

    local best, best_fov = nil, max_fov or 30
    for _, pawn in ipairs(entity_list.by_class_name("C_CitadelPlayerPawn")) do
        if is_enemy(lp, pawn) then
            local pos = safe(function() return pawn:get_bone_pos("spine_2") end)
                or safe(function() return pawn:get_origin() end)
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

local function find_nearest_threat(lp, radius_units)
    local origin = safe(function() return lp:get_origin() end)
    if not origin then return nil end
    local best, best_d = nil, radius_units or 99999
    for _, pawn in ipairs(entity_list.by_class_name("C_CitadelPlayerPawn")) do
        if is_enemy(lp, pawn) then
            local pos = safe(function() return pawn:get_origin() end)
            if pos then
                local dx, dy, dz = pos.x - origin.x, pos.y - origin.y, pos.z - origin.z
                local d = math.sqrt(dx * dx + dy * dy + dz * dz)
                if d < best_d then
                    best_d = d
                    best = pawn
                end
            end
        end
    end
    return best
end

local function count_nearby_enemies(lp, radius_units)
    local origin = safe(function() return lp:get_origin() end)
    if not origin then return 0 end
    local count = 0
    for _, pawn in ipairs(entity_list.by_class_name("C_CitadelPlayerPawn")) do
        if is_enemy(lp, pawn) then
            local pos = safe(function() return pawn:get_origin() end)
            if pos then
                local dx, dy, dz = pos.x - origin.x, pos.y - origin.y, pos.z - origin.z
                if math.sqrt(dx * dx + dy * dy + dz * dz) <= radius_units then
                    count = count + 1
                end
            end
        end
    end
    return count
end

local function get_lp_hp_pct(lp)
    local hp = safe(function() return lp:get_health() end) or 0
    local max_hp = safe(function() return lp:get_max_health() end) or 1
    if max_hp <= 0 then return 1 end
    return hp / max_hp
end

local function user_pressed_wall(cmd)
    local mask = WALL_INPUT
    if cmd.buttonstate1 and (cmd.buttonstate1 & mask) ~= 0 then return true end
    if cmd.buttonstate2 and (cmd.buttonstate2 & mask) ~= 0 then return true end
    if cmd.execute_ability_indices and (cmd.execute_ability_indices & (1 << WALL_SLOT)) ~= 0 then
        return true
    end
    return false
end

local function resolve_assist_mode()
    if not ui_a or not ui_a.wall_mode_placement then return WALL_MODE.OFFENSIVE end
    local m = ui_a.wall_mode_placement:Get()
    if m == 1 then return WALL_MODE.DEFENSIVE end
    return WALL_MODE.OFFENSIVE
end

local function run_cast_phases(cmd, lp, wall_pos, cfg, aim_delay_s, confirm_delay_s, timeout_s, aim_tol)
    local phase = assist.phase
    local t = assist_elapsed()

    if phase == WS.AIM then
        ParadoxWall.apply_aim(cmd, wall_pos, cfg)
        if t >= aim_delay_s and is_aim_settled(cmd, wall_pos, cfg, aim_tol) then
            assist.phase = WS.SELECT
            assist.t0 = global_vars.curtime()
            assist.msg = "wall: SELECT"
        elseif t >= aim_delay_s + timeout_s then
            assist.phase = WS.SELECT
            assist.t0 = global_vars.curtime()
            assist.msg = "wall: SELECT (timeout)"
        end
        return true
    end

    if phase == WS.SELECT then
        ParadoxWall.apply_aim(cmd, wall_pos, cfg)
        clear_primary_attack(cmd)
        if is_wall_selected(lp) then
            assist.phase = WS.CONFIRM
            assist.t0 = global_vars.curtime()
            assist.msg = "wall: CONFIRM"
        elseif slot_ready(lp, WALL_SLOT) then
            press_wall_slot(cmd)
        elseif t >= timeout_s then
            complete_assist(cmd, "wall: select timeout")
        end
        return true
    end

    if phase == WS.CONFIRM then
        ParadoxWall.apply_aim(cmd, wall_pos, cfg)
        clear_wall_slot(cmd)
        if t >= confirm_delay_s then
            press_attack(cmd)
        end
        local wst = ability_status(lp, WALL_SLOT)
        assist.msg = string.format("wall: CONFIRM (%s)", wst)
        if wst == "cd" or wst == "busy" or t >= timeout_s then
            if ui_a and ui_a.wall_restore and ui_a.wall_restore:Get() and assist.saved_pitch then
                assist.phase = WS.RESTORE
                assist.t0 = global_vars.curtime()
                assist.msg = "wall: RESTORE"
            else
                complete_assist(cmd, "wall: done")
            end
        end
        return true
    end

    if phase == WS.RESTORE then
        clear_wall_slot(cmd)
        clear_primary_attack(cmd)
        local pitch, yaw = assist.saved_pitch or 0, assist.saved_yaw or 0
        cmd.viewangles = Angle(pitch, yaw, 0)
        if utils.set_camera_angles then utils.set_camera_angles(Angle(pitch, yaw, 0)) end
        if is_restore_settled() or t >= 0.25 then
            complete_assist(cmd, "wall: done")
        end
        return true
    end

    return false
end

function ParadoxWall.start_assist(target, lp, mode, msg)
    mode = mode or WALL_MODE.OFFENSIVE
    assist.target = target
    assist.mode = mode
    assist.wall_pos = ParadoxWall.compute_pos(lp, target, mode, "assist")
    assist.phase = WS.AIM
    assist.t0 = global_vars.curtime()
    assist.msg = msg or "wall: AIM"
end

function ParadoxWall.run_assist(cmd, lp)
    if assist.phase == WS.IDLE and (not ui_a or not ui_a.wall_enable or not ui_a.wall_enable:Get()) then
        return false
    end

    if assist.phase == WS.IDLE then
        if ParadoxCombo and ParadoxCombo.is_combo_active and ParadoxCombo.is_combo_active() then
            return false
        end
        if ParadoxSwap and ParadoxSwap.is_busy and ParadoxSwap.is_busy() then
            return false
        end
        if not slot_ready(lp, WALL_SLOT) then return false end

        local triggered = false
        if ui_a.wall_mode and ui_a.wall_mode:Get() == 0 then
            triggered = user_pressed_wall(cmd)
        else
            triggered = ui_a.wall_key and ui_a.wall_key:IsPressed()
        end
        if not triggered then return false end

        local mode = resolve_assist_mode()
        local target
        if mode == WALL_MODE.DEFENSIVE then
            local radius = (ui_a.wall_def_radius_m and ui_a.wall_def_radius_m:Get() or 18) * UNIT_METER
            target = find_nearest_threat(lp, radius)
        else
            target = find_target_in_fov(lp, cmd, ui_a.wall_fov:Get())
        end
        if not target then
            assist.msg = string.format("wall: no target (%.0f°)", ui_a.wall_fov:Get())
            return false
        end

        capture_saved_aim(cmd)
        ParadoxWall.start_assist(target, lp, mode, "wall: AIM")
    end

    if assist.phase == WS.IDLE then return false end

    if assist.mode == WALL_MODE.DEFENSIVE and assist.target then
        assist.wall_pos = ParadoxWall.compute_pos(lp, assist.target, WALL_MODE.DEFENSIVE, "assist")
    elseif assist.target and assist.target:valid() and assist.target:is_alive() then
        assist.wall_pos = ParadoxWall.compute_pos(lp, assist.target, WALL_MODE.OFFENSIVE, "assist")
    else
        complete_assist(cmd, "wall: target lost")
        return true
    end

    if not assist.wall_pos then
        complete_assist(cmd, "wall: pos failed")
        return true
    end

    clear_primary_attack(cmd)
    return run_cast_phases(cmd, lp, assist.wall_pos, aim_cfg_from("assist"),
        (ui_a.wall_aim_delay_ms:Get() or 80) / 1000.0,
        (ui_a.wall_confirm_ms:Get() or 100) / 1000.0,
        (ui_a.wall_ready_wait_ms:Get() or 350) / 1000.0,
        ui_a.wall_aim_tol and ui_a.wall_aim_tol:Get() or 8)
end

function ParadoxWall.run_defense(cmd, lp)
    if not ui_a or not ui_a.wall_def_enable or not ui_a.wall_def_enable:Get() then
        return false
    end
    if ParadoxCombo and ParadoxCombo.is_combo_active and ParadoxCombo.is_combo_active() then
        return false
    end
    if ParadoxSwap and ParadoxSwap.is_busy and ParadoxSwap.is_busy() then
        return false
    end
    if assist.phase ~= WS.IDLE then return false end
    if not slot_ready(lp, WALL_SLOT) then return false end

    local now = global_vars.curtime()
    local cd = (ui_a.wall_def_cooldown_ms:Get() or 1200) / 1000.0
    if now - defense.last_cast_t < cd then return false end

    local panic = ui_a.wall_def_panic_key and ui_a.wall_def_panic_key:IsPressed()
    local hp_pct = get_lp_hp_pct(lp) * 100
    local hp_thr = ui_a.wall_def_hp:Get() or 40
    local radius = (ui_a.wall_def_radius_m:Get() or 18) * UNIT_METER
    local min_n = ui_a.wall_def_min_enemies:Get() or 1
    local threat_n = count_nearby_enemies(lp, radius)

    local should = panic
    if not should and hp_pct <= hp_thr then
        if not ui_a.wall_def_require_threat or not ui_a.wall_def_require_threat:Get() then
            should = true
        elseif threat_n >= min_n then
            should = true
        end
    end
    if not should then return false end

    local threat = find_nearest_threat(lp, radius)
    if not threat then return false end

    local wall_pos = ParadoxWall.compute_pos(lp, threat, WALL_MODE.DEFENSIVE, "assist")
    if not wall_pos then return false end

    capture_saved_aim(cmd)
    assist.target = threat
    assist.mode = WALL_MODE.DEFENSIVE
    assist.wall_pos = wall_pos
    assist.phase = WS.AIM
    assist.t0 = now
    assist.msg = panic and "wall def: PANIC" or "wall def: AUTO"
    defense.last_cast_t = now
    return false
end

-- Combo integration: returns true if step consumed tick
function ParadoxWall.combo_step(cmd, lp, combo)
    -- combo: { phase, t0, target, wall_pos, set_phase, elapsed, clear_inputs }
    local wall_pos = combo.wall_pos
    if combo.target and combo.target:valid() then
        wall_pos = ParadoxWall.compute_pos(lp, combo.target, WALL_MODE.OFFENSIVE, "combo")
        combo.wall_pos = wall_pos
    end
    if not wall_pos then
        if combo.on_fail then combo.on_fail() end
        if combo.set_msg then combo.set_msg("wall: pos failed — skip") end
        return true
    end

    local cfg = aim_cfg_from("combo")
    local aim_delay = (ui_c.wall_delay_ms:Get() or 80) / 1000.0
    local confirm_delay = (ui_c.wall_confirm_ms:Get() or 100) / 1000.0
    local timeout = (ui_c.wall_ready_wait_ms:Get() or 350) / 1000.0
    local t = combo.elapsed()

    if combo.phase == "WALL_AIM" then
        combo.clear_inputs(cmd)
        local _, aim_mode = ParadoxWall.apply_aim(cmd, wall_pos, cfg)
        if combo.set_msg then combo.set_msg(string.format("step3: WALL_AIM (%s)", aim_mode or "?")) end
        if t >= aim_delay and is_aim_settled(cmd, wall_pos, cfg, 10) then
            combo.set_phase("WALL_SELECT")
            if combo.set_msg then combo.set_msg("step3: WALL_SELECT") end
        elseif t >= aim_delay + timeout then
            combo.set_phase("WALL_SELECT")
            if combo.set_msg then combo.set_msg("step3: WALL_SELECT (timeout)") end
        end
        return true
    end

    if combo.phase == "WALL_SELECT" then
        ParadoxWall.apply_aim(cmd, wall_pos, cfg)
        combo.clear_inputs(cmd)
        if is_wall_selected(lp) then
            combo.set_phase("WALL_CONFIRM")
            if combo.set_msg then combo.set_msg("step3: WALL_CONFIRM") end
        elseif slot_ready(lp, WALL_SLOT) then
            press_wall_slot(cmd)
            if combo.set_msg then combo.set_msg("step3: WALL_SELECT press F") end
        elseif t >= timeout then
            if combo.on_fail then combo.on_fail() end
            if combo.set_msg then combo.set_msg("step3: wall select timeout") end
        end
        return true
    end

    if combo.phase == "WALL_CONFIRM" then
        ParadoxWall.apply_aim(cmd, wall_pos, cfg)
        clear_wall_slot(cmd)
        if t >= confirm_delay then
            press_attack(cmd)
        end
        local wst = ability_status(lp, WALL_SLOT)
        if combo.set_msg then combo.set_msg(string.format("step3: WALL_CONFIRM (%s)", wst)) end
        if wst == "cd" or wst == "busy" or t >= timeout + confirm_delay then
            if combo.on_done then combo.on_done() end
            if combo.set_msg then combo.set_msg("step4: SWAP_AIM — wall ok") end
        end
        return true
    end

    return false
end

function ParadoxWall.get_assist_msg()
    return assist.msg
end

function ParadoxWall.get_wall_pos()
    return assist.wall_pos
end

function ParadoxWall.reset(cmd)
    complete_assist(cmd, "")
    defense.last_cast_t = 0
end
