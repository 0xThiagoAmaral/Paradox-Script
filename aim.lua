local AimModule = {}

local function require_compat(candidates)
    for i = 1, #candidates do
        local ok, mod = pcall(require, candidates[i])
        if ok and mod then
            return mod
        end
    end
    return nil
end

local Prediction = require_compat({ "libs.prediction", "prediction" })
local Utils = require_compat({ "libs.utils", "utils" })

if not Prediction then
    error("[libs.aim] failed to load prediction module")
end
if not Utils then
    error("[libs.aim] failed to load utils module")
end

-- ═══════ Constants ═══════

AimModule.UNIT_METER = 37.7358490566

AimModule.DefaultBones = {
    "head", "neck_0", "spine_3", "spine_2", "pelvis",
    "leg_upper_R", "leg_upper_L", "ankle_R", "ankle_L"
}

AimModule.BONES_HEAD  = { "head" }
AimModule.BONES_UPPER = { "head", "neck_0", "spine_3", "spine_2" }
AimModule.BONES_FULL  = AimModule.DefaultBones
AimModule.BONES_FEET  = { "ankle_R", "ankle_L" }

-- Target priority modes
AimModule.PRIORITY_CROSSHAIR  = 0
AimModule.PRIORITY_DISTANCE   = 1
AimModule.PRIORITY_LOWEST_HP  = 2
AimModule.PRIORITY_HIGHEST_HP = 3

-- Aim position types for GetAimPositionForSkill
AimModule.SKILL_HEAD = "head"
AimModule.SKILL_BODY = "body"
AimModule.SKILL_FEET = "feet"
AimModule.SKILL_LEAD = "lead"
AimModule.SKILL_BEST = "best"

-- Smooth easing styles for SmoothAimEx
AimModule.EASING_LINEAR      = 0
AimModule.EASING_EASE_OUT    = 1  -- Fast start, precise finish (recommended for flicks)
AimModule.EASING_EASE_IN     = 2  -- Slow start, fast finish
AimModule.EASING_EASE_IN_OUT = 3  -- Smooth acceleration and deceleration
AimModule.EASING_EXPONENTIAL = 4  -- Very fast approach, very precise near target

    --- Calcs dynamic FOV between camera and a 3D point
    local function get_fov_to_pos(pos)
        local camera_angles = utils.get_camera_angles()
        local camera_pos    = utils.get_camera_pos()
        local aim_angle     = utils.calc_angle(camera_pos, pos)
        return utils.get_fov(camera_angles, aim_angle), aim_angle
    end

    --- Target Selector - Finds the best target based on Range, Team, Visibility, and FOV
    function AimModule.GetBestTarget(range_limit, fov_limit)
        local local_pawn = entity_list.local_pawn()
        if not local_pawn or not local_pawn:valid() then return nil end

        local local_origin = local_pawn:get_origin()
        local local_team   = local_pawn.m_iTeamNum
        
        local best_target = nil
        local best_fov    = fov_limit or 180

        local players = entity_list.by_class_name("C_CitadelPlayerPawn")

        for _, enemy in ipairs(players) do
            if enemy and enemy:valid() and enemy:is_alive() and enemy.m_iTeamNum ~= local_team then
                local enemy_pos = enemy:get_origin()
                local dist = local_origin:Distance(enemy_pos)

                if dist <= range_limit then
                    if enemy:is_visible() then
                        local fov, _ = get_fov_to_pos(enemy_pos)
                        
                        if fov < best_fov then
                            best_fov = fov
                            best_target = enemy
                        end
                    end
                end
            end
        end

        return best_target
    end

    --- Aim Point Selector - Iterates bones to find the closest to crosshair that supports pSilent
    function AimModule.GetBestAimPosition(cmd, target, use_closest_bone)
        if not use_closest_bone then
            return target:get_bone_pos("head") or target:get_origin()
        end

        local best_pos = nil
        local best_fov = 999999

        for _, bone_name in ipairs(AimModule.DefaultBones) do
            local bone_pos = target:get_bone_pos(bone_name)
            
            if bone_pos and cmd:can_psilent_at_pos(bone_pos) then
                local fov, _ = get_fov_to_pos(bone_pos)
                
                if fov < best_fov then
                    best_fov = fov
                    best_pos = bone_pos
                end
            end
        end

        if not best_pos then
            local origin = target:get_origin()
            if cmd:can_psilent_at_pos(origin) then
                best_pos = origin
            end
        end

        return best_pos
    end

    --- Execution - Handles Smoothing, Locking Viewangles, Setting pSilent, and Shooting
    ---@param cmd CUserCmd
    ---@param target_pos Vector3 position to hit
    ---@param config table {smooth_amount, max_psilent_fov, shoot_button}
    function AimModule.ExecuteAim(cmd, target_pos, config)
        if not target_pos then return false end

        local camera_pos = utils.get_camera_pos()
        local aim_angle  = utils.calc_angle(camera_pos, target_pos)

        if config.smooth_amount and config.smooth_amount > 1 then
            cmd:smooth_aim(aim_angle, config.smooth_amount)
        else
            cmd.viewangles = aim_angle
            utils.set_camera_angles(aim_angle)
        end

        local current_angles = utils.get_camera_angles()
        local fov_diff = utils.get_fov(current_angles, aim_angle)
        local psilent_limit = config.max_psilent_fov or 0

        if psilent_limit == 0 or fov_diff <= psilent_limit then
            cmd:set_psilent_at_pos(target_pos)
        end

        if config.shoot_button then
            cmd:add_buttonstate1(config.shoot_button)
        end

        return true
    end

    --- Projectile Interception Helper - Solves for time (t) where: Distance(Source, Target(t)) = Speed * t
    ---@param target entity
    ---@param source_pos Vector
    ---@param speed number
    ---@param aim_bone string|nil
    ---@return Vector|nil
    local function get_interception_point(target, source_pos, speed, aim_bone)
        if not target or not target:valid() then return nil end
        if speed <= 0 then return target:get_origin() end

        local predicted_pos = Prediction.PredictPlayer(target, 0, nil, nil, nil, nil, aim_bone)
        local t = 0.0
        
        for i = 1, 8 do
            local dist = source_pos:Distance(predicted_pos)
            local new_t = dist / speed

            if math.abs(new_t - t) < 0.005 then 
                break 
            end
            
            t = new_t
            
            predicted_pos = Prediction.PredictPlayer(target, t, nil, nil, nil, nil, aim_bone)
        end

        return predicted_pos
    end

    --- Linear Ability Aiming - Main function for aiming abilities with travel time (projectiles)
    ---@param cmd CUserCmd
    ---@param ability_speed number The projectile speed (units/s)
    ---@param target entity|nil (Optional) Specific target, or nil to auto-select
    ---@param config table Configuration table
    ---       {
    ---         range = 2000,
    ---         fov = 180,
    ---         aim_bone = "spine_0",
    ---         smooth_amount = 1.0,
    ---         shoot_button = nil,
    ---         max_psilent_fov = 0
    ---       }
    ---@return boolean success
    function AimModule.AimAbility(cmd, ability_speed, target, config)
        config = config or {}
        
        if not target then
            local range = config.range or 3000
            local fov = config.fov or 180
            target = AimModule.GetBestTarget(range, fov)
        end

        if not target then return false end

        local source_pos = utils.get_camera_pos()
        local aim_bone = config.aim_bone or "spine_0"
        
        local predicted_pos = get_interception_point(target, source_pos, ability_speed, aim_bone)
        
        if not predicted_pos then return false end

    return AimModule.ExecuteAim(cmd, predicted_pos, config)
end

--- Smart Trigger / Cone Fire Helper
--- Checks if a target is within a specific FOV and Range of the crosshair.
--- If yes, it presses the button. If target is nil, it scans for one.
---@param cmd CUserCmd
---@param button_mask number InputBitMask_t to press (e.g. IN_ABILITY1)
---@param range number Max distance to check
---@param fov number Max FOV from crosshair (cone width)
---@param target entity|nil (Optional) Specific target to check
---@return boolean success
function AimModule.FireIfEnemyInFOV(cmd, button_mask, range, fov, target)
    local local_pawn = entity_list.local_pawn()
    if not local_pawn then return false end

    -- If no target provided, try to find the best one currently in the cone
    if not target then
        target = AimModule.GetBestTarget(range, fov)
    else
        -- Manual validation if target is provided
        if not target:valid() or not target:is_alive() then return false end
        
        -- Check Visibility
        if not target:is_visible() then return false end

        -- Check Range
        local dist = local_pawn:get_origin():Distance(target:get_origin())
        if dist > range then return false end

        -- Check FOV
        local current_fov, _ = get_fov_to_pos(target:get_origin())
        if current_fov > fov then return false end
    end

    -- If we have a valid target in position, fire
    if target then
        cmd:add_buttonstate1(button_mask)
        return true
    end

    return false
end

-- ═══════════════════════════════════════════════════════
-- New stuff down here
-- ═══════════════════════════════════════════════════════

local function compute_eased_smoothness(fov_diff, base_smooth, max_fov, easing)
    local t = 1.0 - math.min(fov_diff / math.max(max_fov, 1), 1.0)
    local factor

    if easing == AimModule.EASING_LINEAR then
        factor = t
    elseif easing == AimModule.EASING_EASE_OUT then
        factor = 1.0 - (1.0 - t) * (1.0 - t)
    elseif easing == AimModule.EASING_EASE_IN then
        factor = t * t
    elseif easing == AimModule.EASING_EASE_IN_OUT then
        if t < 0.5 then
            factor = 2 * t * t
        else
            factor = 1 - ((-2 * t + 2) * (-2 * t + 2)) / 2
        end
    elseif easing == AimModule.EASING_EXPONENTIAL then
        factor = 1.0 - math.exp(-3.0 * t)
    else
        factor = t
    end

    -- Far from target = low smooth (fast), close = high smooth (precise)
    local min_smooth = math.max(base_smooth * 0.3, 1)
    local max_smooth = base_smooth * 2.0
    return min_smooth + (max_smooth - min_smooth) * factor
end

-- ═══════ Enhanced Target Selection ═══════
-- Supports priority modes, custom filters, ally targeting, and return-all
--
-- config fields:
--   range (units), fov, priority (PRIORITY_*), require_visible (default true),
--   filter (function(ent)->bool), allies (bool), return_all (bool)

function AimModule.GetBestTargetEx(config)
    config = config or {}
    local local_pawn = entity_list.local_pawn()
    if not local_pawn or not local_pawn:valid() then return nil end

    local local_origin = local_pawn:get_origin()
    local local_team   = local_pawn.m_iTeamNum
    local range_limit  = config.range or 3000
    local fov_limit    = config.fov or 180
    local priority     = config.priority or AimModule.PRIORITY_CROSSHAIR
    local require_visible = config.require_visible ~= false
    local filter_fn       = config.filter
    local target_allies   = config.allies or false

    local players = entity_list.by_class_name("C_CitadelPlayerPawn")
    local candidates = {}

    for _, p in ipairs(players) do
        if p and p:valid() and p:is_alive() then
            local is_same_team = p.m_iTeamNum == local_team
            local is_self      = p:get_handle() == local_pawn:get_handle()
            local team_ok
            if target_allies then
                team_ok = is_same_team and not is_self
            else
                team_ok = not is_same_team
            end

            if team_ok then
                if not require_visible or p:is_visible() then
                    local pos  = p:get_origin()
                    local dist = local_origin:Distance(pos)

                    if dist <= range_limit then
                        local fov = get_fov_to_pos(pos)

                        if fov <= fov_limit then
                            if not filter_fn or filter_fn(p) then
                                local hp     = p.m_iHealth or 0
                                local max_hp = p:get_max_health() or 1
                                local hp_pct = max_hp > 0 and (hp / max_hp) or 1.0

                                candidates[#candidates + 1] = {
                                    entity = p,
                                    dist   = dist,
                                    fov    = fov,
                                    hp_pct = hp_pct,
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    if #candidates == 0 then return nil end

    if priority == AimModule.PRIORITY_CROSSHAIR then
        table.sort(candidates, function(a, b) return a.fov < b.fov end)
    elseif priority == AimModule.PRIORITY_DISTANCE then
        table.sort(candidates, function(a, b) return a.dist < b.dist end)
    elseif priority == AimModule.PRIORITY_LOWEST_HP then
        table.sort(candidates, function(a, b) return a.hp_pct < b.hp_pct end)
    elseif priority == AimModule.PRIORITY_HIGHEST_HP then
        table.sort(candidates, function(a, b) return a.hp_pct > b.hp_pct end)
    end

    if config.return_all then
        local result = {}
        for _, c in ipairs(candidates) do result[#result + 1] = c.entity end
        return result
    end
    return candidates[1].entity
end

-- ═══════ Advanced Smooth Aim with Easing ═══════
-- Dynamic smoothness: fast when far from target, precise when close.
--
-- config fields:
--   smooth (base smoothness 1-100), easing (EASING_*),
--   psilent_fov (0=no psilent), max_fov_range (FOV range for easing, default 90)

function AimModule.SmoothAimEx(cmd, target_pos, config)
    if not target_pos then return false end
    config = config or {}

    local base_smooth   = config.smooth or 15
    local easing        = config.easing or AimModule.EASING_LINEAR
    local psilent_fov   = config.psilent_fov or 0
    local max_fov_range = config.max_fov_range or 90

    local camera_pos = utils.get_camera_pos()
    local aim_angle  = utils.calc_angle(camera_pos, target_pos)
    local cur_angles = utils.get_camera_angles()
    local fov_diff   = utils.get_fov(cur_angles, aim_angle)

    if easing ~= AimModule.EASING_LINEAR then
        local smooth_val = compute_eased_smoothness(fov_diff, base_smooth, max_fov_range, easing)
        if smooth_val > 1 then
            cmd:smooth_aim(aim_angle, smooth_val)
        else
            cmd.viewangles = aim_angle
            utils.set_camera_angles(aim_angle)
        end
    else
        if base_smooth > 1 then
            cmd:smooth_aim(aim_angle, base_smooth)
        else
            cmd.viewangles = aim_angle
            utils.set_camera_angles(aim_angle)
        end
    end

    if psilent_fov > 0 then
        cur_angles = utils.get_camera_angles()
        fov_diff   = utils.get_fov(cur_angles, aim_angle)
        if fov_diff <= psilent_fov then
            cmd:set_psilent_at_pos(target_pos)
        end
    end

    return true
end

-- ═══════ Clean P-Silent Wrapper ═══════
-- Checks FOV and can_psilent before applying. Returns true if applied.

function AimModule.PsilentAt(cmd, pos, max_fov)
    if not pos then return false end
    max_fov = max_fov or 180

    local camera_pos = utils.get_camera_pos()
    local aim_angle  = utils.calc_angle(camera_pos, pos)
    local cur_angles = utils.get_camera_angles()
    local fov_diff   = utils.get_fov(cur_angles, aim_angle)

    if fov_diff <= max_fov and cmd:can_psilent_at_pos(pos) then
        cmd:set_psilent_at_pos(pos)
        return true
    end
    return false
end

-- ═══════ Range Check Helper ═══════

function AimModule.IsTargetInRange(target, range_metres)
    if not target or not target:valid() then return false end
    local local_pawn = entity_list.local_pawn()
    if not local_pawn or not local_pawn:valid() then return false end
    return local_pawn:get_origin():Distance(target:get_origin()) <= range_metres * AimModule.UNIT_METER
end

-- ═══════ Skill-Based Aim Position ═══════
-- Returns the appropriate aim position based on skill type.
-- skill_type: SKILL_HEAD, SKILL_BODY, SKILL_FEET, SKILL_LEAD, SKILL_BEST
-- options: { bone = "custom_bone", lead_metres = 6 }

function AimModule.GetAimPositionForSkill(cmd, target, skill_type, options)
    if not target or not target:valid() then return nil end
    options = options or {}

    if skill_type == AimModule.SKILL_HEAD then
        return target:get_bone_pos("head") or target:get_origin()

    elseif skill_type == AimModule.SKILL_BODY then
        local bone = options.bone or "spine_2"
        return target:get_bone_pos(bone) or target:get_origin()

    elseif skill_type == AimModule.SKILL_FEET then
        local bone = options.bone or "ankle_R"
        return target:get_bone_pos(bone) or target:get_origin()

    elseif skill_type == AimModule.SKILL_LEAD then
        local vel = Prediction.GetTrackedVelocity(target)
        if vel then
            local speed = vel:Length2D()
            if speed > 30 then
                local lead_dist = (options.lead_metres or 6) * AimModule.UNIT_METER
                local dir    = Vector(vel.x, vel.y, 0):Normalized()
                local origin = target:get_origin()
                return Vector(
                    origin.x + dir.x * lead_dist,
                    origin.y + dir.y * lead_dist,
                    origin.z
                )
            end
        end
        return target:get_origin()

    elseif skill_type == AimModule.SKILL_BEST then
        return AimModule.GetBestAimPosition(cmd, target, true)

    else
        return target:get_origin()
    end
end

-- ═══════ Integrated Prediction + Aim ═══════
-- One-call aim at a predicted position. Handles hitscan, linear projectile, and arc.
--
-- config fields:
--   projectile_speed (0 or nil=hitscan), gravity (nil=linear, number=arc),
--   aim_bone, smooth/smooth_amount, easing, psilent_fov/max_psilent_fov,
--   shoot_button (InputBitMask_t)
-- Returns: success, target_pos

function AimModule.AimAtPredicted(cmd, target, config)
    if not target or not target:valid() then return false, nil end
    config = config or {}

    local speed    = config.projectile_speed or 0
    local gravity  = config.gravity
    local aim_bone = config.aim_bone or "spine_0"
    local source_pos = utils.get_camera_pos()
    local target_pos

    if gravity and speed > 0 then
        target_pos = Prediction.PredictArc(source_pos, target, speed, gravity, aim_bone)
    elseif speed > 0 then
        target_pos = get_interception_point(target, source_pos, speed, aim_bone)
    else
        target_pos = target:get_bone_pos(aim_bone) or target:get_origin()
    end

    if not target_pos then return false, nil end

    local smooth      = config.smooth or config.smooth_amount
    local easing      = config.easing
    local psilent_fov = config.psilent_fov or config.max_psilent_fov or 0

    if easing or (smooth and smooth > 1) then
        AimModule.SmoothAimEx(cmd, target_pos, {
            smooth      = smooth,
            easing      = easing or AimModule.EASING_LINEAR,
            psilent_fov = psilent_fov,
        })
    elseif psilent_fov > 0 then
        AimModule.PsilentAt(cmd, target_pos, psilent_fov)
    else
        cmd:set_psilent_at_pos(target_pos)
    end

    if config.shoot_button then
        cmd:add_buttonstate1(config.shoot_button)
    end

    return true, target_pos
end

-- ═══════ Two-Phase Ground-Target Ability Helper ═══════
-- Reusable state machine for abilities that require:
--   Phase 0: Activate ability (IN_ABILITY_X)
--   Phase 1: Aim at target with psilent, wait, then confirm (IN_ATTACK)
--   Phase 2: Wait for ability to go on cooldown
--
-- state: persistent table { phase = 0 } (caller owns this)
-- config fields:
--   key (bind with :IsDown()), ability_slot, ability_button,
--   fov, range_metres, psilent_fov, confirm_delay (default 0.05),
--   aim_type ("feet"/"body"/"head"/"lead"/"best"), aim_options,
--   get_target (function()->entity), get_aim_pos (function(target)->Vector)
-- Returns: "idle", "selected", "confirming", "confirmed", "casting", "done", "reset"

function AimModule.TwoPhaseAbility(cmd, pawn, state, config)
    if not pawn or not pawn:valid() or not pawn:is_alive() then return "idle" end

    local key                = config.key
    local ability_slot       = config.ability_slot
    local ability_button     = config.ability_button
    local use_execute_indices = config.use_execute_indices or false
    local fov                = config.fov or 25
    local range_metres       = config.range_metres or 35
    local psilent_fov        = config.psilent_fov or 20
    local confirm_delay      = config.confirm_delay or 0.05
    local aim_type           = config.aim_type or "feet"
    local aim_options        = config.aim_options
    local get_target_fn      = config.get_target
    local get_aim_pos_fn     = config.get_aim_pos

    local cur_time = global_vars.curtime()
    if not state.phase then state.phase = 0 end

    -- Reset when key released — only in Phase 0 (haven't committed yet).
    -- In Phase 1/2 the ability is already activated and needs to complete.
    if key and not key:IsDown() and state.phase == 0 then
        state.phase   = 0
        state.target  = nil
        state.aim_pos = nil
        return "reset"
    end

    local ability = pawn:get_ability_by_slot(ability_slot)

    -- Phase 0: Find target, aim, activate ability
    if state.phase == 0 then
        if not ability or not ability:valid() or ability:can_be_executed() ~= 0 then
            return "idle"
        end

        local range_units = range_metres * AimModule.UNIT_METER
        local target = get_target_fn and get_target_fn()
            or AimModule.GetBestTarget(range_units, fov)

        if not target or not target:valid() or not target:is_alive() or not target:is_visible() then
            return "idle"
        end

        local aim_pos = get_aim_pos_fn and get_aim_pos_fn(target)
            or AimModule.GetAimPositionForSkill(cmd, target, aim_type, aim_options)

        if not aim_pos then return "idle" end

        local cam_pos    = utils.get_camera_pos()
        local aim_angle  = utils.calc_angle(cam_pos, aim_pos)
        local cur_angles = utils.get_camera_angles()
        local fov_diff   = utils.get_fov(cur_angles, aim_angle)

        if fov_diff <= psilent_fov and cmd:can_psilent_at_pos(aim_pos) then
            cmd:set_psilent_at_pos(aim_pos)
            if use_execute_indices then
                cmd.execute_ability_indices = cmd.execute_ability_indices | (1 << ability_slot)
            else
                cmd:add_buttonstate1(ability_button)
            end

            state.phase       = 1
            state.target      = target
            state.aim_pos     = aim_pos
            state.select_time = cur_time
            return "selected"
        end

        return "idle"

    -- Phase 1: Keep aiming, wait for confirm delay, then LMB
    elseif state.phase == 1 then
        if state.target and state.target:valid() and state.target:is_alive() then
            state.aim_pos = get_aim_pos_fn and get_aim_pos_fn(state.target)
                or AimModule.GetAimPositionForSkill(cmd, state.target, aim_type, aim_options)
        end

        if state.aim_pos then
            cmd:set_psilent_at_pos(state.aim_pos)

            if (cur_time - state.select_time) >= confirm_delay then
                cmd:add_buttonstate1(InputBitMask_t.IN_ATTACK)
                state.phase = 2
                return "confirmed"
            end
            return "confirming"
        else
            state.phase   = 0
            state.target  = nil
            state.aim_pos = nil
            return "reset"
        end

    -- Phase 2: Wait for ability cooldown (cast completed)
    elseif state.phase == 2 then
        if ability and ability:valid() then
            if ability:can_be_executed() ~= 0 then
                state.phase   = 0
                state.target  = nil
                state.aim_pos = nil
                return "done"
            end
        else
            state.phase   = 0
            state.target  = nil
            state.aim_pos = nil
            return "done"
        end
        return "casting"
    end

    return "idle"
end

-- ═══════ Ally-or-Self Targeted Ability Helper ═══════
-- State machine for abilities that can target either an ally or self.
--   Self-cast:  Instant via IN_ALT_CAST (no aiming needed)
--   Ally-cast:  Two-phase psilent → confirm with IN_ATTACK
--
-- state: persistent table { phase = 0 } (caller owns this)
-- config fields:
--   key (bind with :IsDown()), ability_slot, ability_button,
--   psilent_fov (max psilent degree for ally), confirm_delay (default 0.05),
--   aim_bone (default "spine_2"), fallback_bone (default "spine_0"),
--   get_target (function() -> target_entity, is_self_cast, reason)
-- Returns: "idle", "self_cast", "selected", "confirming", "confirmed",
--          "casting", "done", "reset"

function AimModule.AllyOrSelfAbility(cmd, pawn, state, config)
    if not pawn or not pawn:valid() or not pawn:is_alive() then return "idle" end

    local key                = config.key
    local ability_slot       = config.ability_slot
    local ability_button     = config.ability_button
    local use_execute_indices = config.use_execute_indices or false
    local psilent_fov        = config.psilent_fov or 25
    local confirm_delay      = config.confirm_delay or 0.05
    local aim_bone           = config.aim_bone or "spine_2"
    local fallback_bone      = config.fallback_bone or "spine_0"
    local get_target_fn      = config.get_target

    local cur_time = global_vars.curtime()
    if not state.phase then state.phase = 0 end

    -- Reset when key released — only in Phase 0 (haven't committed yet).
    -- In Phase 1/2 the ability is already activated and needs to complete.
    if key and not key:IsDown() and state.phase == 0 then
        state.phase   = 0
        state.target  = nil
        state.aim_pos = nil
        state.is_self = false
        return "reset"
    end

    local ability = pawn:get_ability_by_slot(ability_slot)

    -- Phase 0: Determine target, execute self-cast or start ally-cast
    if state.phase == 0 then
        if not ability or not ability:valid() or ability:can_be_executed() ~= 0 then
            return "idle"
        end

        if not get_target_fn then return "idle" end
        local target, is_self, reason = get_target_fn()

        if not target then return "idle" end

        if is_self then
            -- SELF-CAST: Instant via ability + IN_ALT_CAST
            if use_execute_indices then
                cmd.execute_ability_indices = cmd.execute_ability_indices | (1 << ability_slot)
            else
                cmd:add_buttonstate1(ability_button)
            end
            cmd:add_buttonstate1(InputBitMask_t.IN_ALT_CAST)
            state.phase   = 2  -- Skip Phase 1, go straight to cooldown wait
            state.target  = nil
            state.aim_pos = nil
            state.is_self = true
            return "self_cast"
        else
            -- ALLY-CAST: Psilent at ally + ability key
            local bone_pos = target:get_bone_pos(aim_bone)
                or (fallback_bone and target:get_bone_pos(fallback_bone))
                or target:get_origin()

            if not bone_pos then return "idle" end

            local cam_pos    = utils.get_camera_pos()
            local aim_angle  = utils.calc_angle(cam_pos, bone_pos)
            local cur_angles = utils.get_camera_angles()
            local fov_diff   = utils.get_fov(cur_angles, aim_angle)

            if fov_diff <= psilent_fov and cmd:can_psilent_at_pos(bone_pos) then
                cmd:set_psilent_at_pos(bone_pos)
                if use_execute_indices then
                    cmd.execute_ability_indices = cmd.execute_ability_indices | (1 << ability_slot)
                else
                    cmd:add_buttonstate1(ability_button)
                end

                state.phase       = 1
                state.target      = target
                state.aim_pos     = bone_pos
                state.is_self     = false
                state.select_time = cur_time
                return "selected"
            end
        end

        return "idle"

    -- Phase 1: Ally-cast confirm (keep aiming, wait, then IN_ATTACK)
    elseif state.phase == 1 then
        if state.target and state.target:valid() and state.target:is_alive() then
            state.aim_pos = state.target:get_bone_pos(aim_bone)
                or (fallback_bone and state.target:get_bone_pos(fallback_bone))
                or state.target:get_origin()
        end

        if state.aim_pos then
            cmd:set_psilent_at_pos(state.aim_pos)

            if (cur_time - state.select_time) >= confirm_delay then
                cmd:add_buttonstate1(InputBitMask_t.IN_ATTACK)
                state.phase = 2
                return "confirmed"
            end
            return "confirming"
        else
            state.phase   = 0
            state.target  = nil
            state.aim_pos = nil
            state.is_self = false
            return "reset"
        end

    -- Phase 2: Wait for ability cooldown
    elseif state.phase == 2 then
        if ability and ability:valid() then
            if ability:can_be_executed() ~= 0 then
                state.phase   = 0
                state.target  = nil
                state.aim_pos = nil
                state.is_self = false
                return "done"
            end
        else
            state.phase   = 0
            state.target  = nil
            state.aim_pos = nil
            state.is_self = false
            return "done"
        end
        return "casting"
    end

    return "idle"
end

-- ═══════ Ability Execution via execute_ability_indices ═══════

function AimModule.ExecuteAbilityBySlot(cmd, pawn, slot)
    if not pawn or not pawn:valid() then return false end
    local ability = pawn:get_ability_by_slot(slot)
    if not ability or not ability:valid() then return false end
    if ability:can_be_executed() ~= 0 then return false end
    cmd.execute_ability_indices = cmd.execute_ability_indices | (1 << slot)
    return true
end

function AimModule.FindItemSlot(pawn, name_pattern)
    if not pawn or not pawn:valid() then return nil, nil end
    local pattern_lower = string.lower(name_pattern)
    for slot = 4, 7 do
        local ability = pawn:get_ability_by_slot(slot)
        if ability and ability:valid() then
            local name = ability:get_name()
            if name and string.find(string.lower(name), pattern_lower) then
                return slot, ability
            end
        end
    end
    return nil, nil
end

function AimModule.AutoCastItem(cmd, pawn, name_pattern)
    local slot = AimModule.FindItemSlot(pawn, name_pattern)
    if not slot then return false end
    return AimModule.ExecuteAbilityBySlot(cmd, pawn, slot)
end

-- ═══════ Wall-Aware Aim Helpers ═══════

function AimModule.GetWallFallbackPosition(target, config)
    if not target or not target:valid() then return nil, false end
    config = config or {}

    local camera_pos    = utils.get_camera_pos()
    local camera_angles = utils.get_camera_angles()
    local target_pos    = target:get_origin()

    if Prediction.IsPositionVisible(camera_pos, target_pos) then
        return target_pos, false
    end

    local max_wall_dist = config.max_wall_dist or 600
    local num_rays      = config.num_rays or 16
    local best_wall = Prediction.FindBestWallTarget(
        target_pos, max_wall_dist, camera_pos, camera_angles, num_rays
    )

    if best_wall then
        return best_wall.pos, true
    end

    return nil, false
end

-- ═══════ VData Projectile Speed Reader ═══════
-- Reads projectile speed directly from an ability's VData instead of hardcoding.
-- Falls back to provided default if VData read fails.
--
---@param pawn entity The hero pawn
---@param ability_slot number Ability slot index (0-3 for abilities, 4-7 for items)
---@param fallback_speed number Speed to return if VData read fails
---@return number speed in units/s
function AimModule.GetAbilitySpeed(pawn, ability_slot, fallback_speed)
    fallback_speed = fallback_speed or 0
    if not pawn or not pawn:valid() then return fallback_speed end
    local ability = pawn:get_ability_by_slot(ability_slot)
    return Utils.GetAbilityProjectileSpeed(ability) or fallback_speed
end

-- ═══════ Anti-Parry / Target Viability Checks ═══════
-- Prevents wasting abilities on parrying / invulnerable targets.

--- Returns true if the target can be meaningfully damaged right now.
--- Use before ability casts to avoid wasting cooldowns.
---@param target entity
---@return boolean
function AimModule.CanDamageTarget(target)
    return Utils.IsAlive(target) and not Utils.IsWastedTarget(target)
end

--- Full pre-cast check: ability ready + target damageable + in range + visible
---@param pawn entity Local pawn
---@param ability_slot number Ability slot
---@param target entity Target to check
---@param range_units number|nil Max range in game units (nil = skip range check)
---@return boolean can_cast
---@return entity|nil ability
function AimModule.CanCastOnTarget(pawn, ability_slot, target, range_units)
    if not pawn or not pawn:valid() then return false, nil end
    if not Utils.IsAlive(target) then return false, nil end
    if Utils.IsWastedTarget(target) then return false, nil end

    local ability = pawn:get_ability_by_slot(ability_slot)
    if not ability or not ability:valid() then return false, nil end
    if ability:can_be_executed() ~= 0 then return false, nil end

    if range_units then
        local dist = pawn:get_origin():Distance(target:get_origin())
        if dist > range_units then return false, nil end
    end

    if not target:is_visible() then return false, nil end

    return true, ability
end

--- Integrated projectile aim that reads speed from VData and checks target viability.
--- Combines VData speed reading + anti-parry + prediction + aim execution in one call.
---@param cmd CUserCmd
---@param pawn entity Local pawn
---@param ability_slot number Ability slot (0-3)
---@param target entity|nil Explicit target (nil = auto-select)
---@param config table Same as AimAtPredicted + { skip_parry = true, range_metres = 30 }
---@return boolean success
---@return Vector|nil aim_pos
function AimModule.SmartAbilityAim(cmd, pawn, ability_slot, target, config)
    config = config or {}
    if not pawn or not pawn:valid() then return false, nil end

    -- Check ability readiness
    local ability = pawn:get_ability_by_slot(ability_slot)
    if not ability or not ability:valid() or ability:can_be_executed() ~= 0 then
        return false, nil
    end

    -- Auto-select target if not provided
    if not target then
        local range = (config.range_metres or 30) * AimModule.UNIT_METER
        local fov = config.fov or 180
        target = AimModule.GetBestTarget(range, fov)
    end
    if not target then return false, nil end

    -- Anti-parry / viability check (on by default)
    if config.skip_parry ~= false then
        if Utils.IsWastedTarget(target) then return false, nil end
    end

    -- Read VData projectile speed (or use provided override)
    local speed = config.projectile_speed
    if not speed then
        speed = Utils.GetAbilityProjectileSpeed(ability) or 0
    end

    -- Delegate to AimAtPredicted with the resolved speed
    local aim_config = {}
    for k, v in pairs(config) do aim_config[k] = v end
    aim_config.projectile_speed = speed

    return AimModule.AimAtPredicted(cmd, target, aim_config)
end

-- ═══════ Safe Bone Position ═══════
-- pcall-wrapped bone read with fallback chain

function AimModule.SafeBonePos(target, primary, fallback)
    if not target or not target:valid() then return nil end
    local ok, pos = pcall(function() return target:get_bone_pos(primary) end)
    if ok and pos then return pos end
    if fallback then
        ok, pos = pcall(function() return target:get_bone_pos(fallback) end)
        if ok and pos then return pos end
    end
    return target:get_origin()
end

return AimModule
