local Prediction = {}

-- Require Utils for safe wrappers and modifier state checks
local function require_compat(candidates)
    for i = 1, #candidates do
        local ok, mod = pcall(require, candidates[i])
        if ok and mod then
            return mod
        end
    end
    return nil
end

local Utils = require_compat({ "libs.utils", "utils" })

local DASH_BUCKET_1 = { speed = 635.0, duration = 0.62 }
local DASH_BUCKET_2 = { speed = 579.0, duration = 0.68 }
local DASH_BUCKET_3 = { speed = 562.0, duration = 0.70 }

local DEFAULT_DASH_BUCKET = DASH_BUCKET_2

local HERO_DASH_BUCKETS = {
    hero_haze       = DASH_BUCKET_1,
    hero_orion      = DASH_BUCKET_1,
    hero_astro      = DASH_BUCKET_1,
    hero_yamato     = DASH_BUCKET_1,
    hero_wraith     = DASH_BUCKET_2,
    hero_gigawatt   = DASH_BUCKET_2,
    hero_inferno    = DASH_BUCKET_2,
    hero_viper      = DASH_BUCKET_2,
    hero_drifter    = DASH_BUCKET_2,
    hero_lash       = DASH_BUCKET_2,
    hero_mirage     = DASH_BUCKET_2,
    hero_viscous    = DASH_BUCKET_2,
    hero_synth      = DASH_BUCKET_2,
    hero_bookworm   = DASH_BUCKET_2,
    hero_chrono     = DASH_BUCKET_2,
    hero_magician   = DASH_BUCKET_2,
    hero_doorman    = DASH_BUCKET_2,
    hero_hornet     = DASH_BUCKET_2,
    hero_warden     = DASH_BUCKET_2,
    hero_ghost      = DASH_BUCKET_2,
    hero_vampirebat = DASH_BUCKET_2,
    hero_bebop      = DASH_BUCKET_3,
    hero_dynamo     = DASH_BUCKET_3,
    hero_atlas      = DASH_BUCKET_3,
    hero_kelvin     = DASH_BUCKET_3,
    hero_forge      = DASH_BUCKET_3,
    hero_krill      = DASH_BUCKET_3,
    hero_shiv       = DASH_BUCKET_3,
    hero_frank      = DASH_BUCKET_3,
    hero_punkgoat   = DASH_BUCKET_3,
    hero_nano       = DASH_BUCKET_3,
}

local function get_dash_stats(hero_name)
    return HERO_DASH_BUCKETS[hero_name] or DEFAULT_DASH_BUCKET
end

local HERO_SPEEDS = {
    hero_atlas      = { move = 241.51, sprint = 60.38,  total = 301.89 },
    hero_bebop      = { move = 243.40, sprint = 150.94, total = 394.34 },
    hero_punkgoat   = { move = 264.15, sprint = 60.38,  total = 324.53 },
    hero_nano       = { move = 271.70, sprint = 60.38,  total = 332.08 },
    hero_drifter    = { move = 260.38, sprint = 60.38,  total = 320.75 },
    hero_dynamo     = { move = 252.83, sprint = 60.38,  total = 313.21 },
    hero_orion      = { move = 237.74, sprint = 60.38,  total = 298.11 },
    hero_haze       = { move = 309.43, sprint = 60.38,  total = 369.81 },
    hero_astro      = { move = 309.43, sprint = 60.38,  total = 369.81 },
    hero_inferno    = { move = 252.83, sprint = 60.38,  total = 313.21 },
    hero_kelvin     = { move = 252.83, sprint = 41.51,  total = 294.34 },
    hero_ghost      = { move = 237.74, sprint = 98.11,  total = 335.85 },
    hero_lash       = { move = 271.70, sprint = 79.25,  total = 350.94 },
    hero_forge      = { move = 252.83, sprint = 60.38,  total = 313.21 },
    hero_vampirebat = { move = 249.06, sprint = 60.38,  total = 309.43 },
    hero_mirage     = { move = 264.15, sprint = 60.38,  total = 324.53 },
    hero_krill      = { move = 301.89, sprint = 60.38,  total = 362.26 },
    hero_bookworm   = { move = 260.38, sprint = 132.08, total = 392.45 },
    hero_chrono     = { move = 252.83, sprint = 60.38,  total = 313.21 },
    hero_synth      = { move = 271.70, sprint = 60.38,  total = 332.08 },
    hero_gigawatt   = { move = 252.83, sprint = 22.64,  total = 275.47 },
    hero_shiv       = { move = 252.83, sprint = 60.38,  total = 313.21 },
    hero_magician   = { move = 271.70, sprint = 60.38,  total = 332.08 },
    hero_doorman    = { move = 298.11, sprint = 60.38,  total = 358.49 },
    hero_frank      = { move = 237.74, sprint = 41.51,  total = 279.25 },
    hero_hornet     = { move = 298.11, sprint = 60.38,  total = 358.49 },
    hero_viscous    = { move = 271.70, sprint = 60.38,  total = 332.08 },
    hero_viper      = { move = 260.38, sprint = 60.38,  total = 320.75 }, 
    hero_warden     = { move = 237.74, sprint = 60.38,  total = 298.11 },
    hero_wraith     = { move = 271.70, sprint = 60.38,  total = 332.08 },
    hero_yamato     = { move = 309.43, sprint = 60.38,  total = 369.81 },
}

local function calculate_mean_speeds()
    local sum_move, sum_sprint, sum_total, count = 0, 0, 0, 0
    for _, speeds in pairs(HERO_SPEEDS) do
        sum_move = sum_move + speeds.move
        sum_sprint = sum_sprint + speeds.sprint
        sum_total = sum_total + speeds.total
        count = count + 1
    end
    return {
        move = sum_move / count,
        sprint = sum_sprint / count,
        total = sum_total / count
    }
end

local MEAN_HERO_SPEEDS = calculate_mean_speeds()

local SPIRIT_SCALING = {
    hero_orion    = 0.31698,
    hero_gigawatt = 0.45283,
    hero_viper    = 0.52075,
}

local CROUCH = {
    BASE = 181.13,
    PENALTY = 166.04,
}

local MASK_SOLID = 0x1

local VELOCITY_CONFIG = {
    HISTORY_SIZE = 8,           -- Number of samples to keep
    MIN_DELTA_TIME = 0.001,     -- Minimum time delta to avoid division by zero
    MAX_DELTA_TIME = 0.5,       -- Maximum time delta before considering data stale
    VELOCITY_SMOOTHING = 0.3,   -- Exponential smoothing factor for velocity (0-1, lower = smoother)
    ACCEL_SMOOTHING = 0.2,      -- Exponential smoothing factor for acceleration
    STALE_THRESHOLD = 1.0,      -- Seconds before data is considered stale
}

-- Storage for entity tracking data
-- Key: entity handle, Value: tracking data
local entity_tracking = {}

---@class TrackingData
---@field positions {pos: Vector, time: number}[]
---@field velocity Vector
---@field acceleration Vector
---@field last_update number
---@field write_index number

-- Creates a new tracking data structure
---@return TrackingData
local function create_tracking_data()
    return {
        positions = {},
        velocity = Vector(0, 0, 0),
        acceleration = Vector(0, 0, 0),
        last_update = 0,
        write_index = 1,
    }
end

-- Adds a position sample to the ring buffer
---@param data TrackingData
---@param pos Vector
---@param time number
local function add_position_sample(data, pos, time)
    data.positions[data.write_index] = { pos = pos, time = time }
    data.write_index = (data.write_index % VELOCITY_CONFIG.HISTORY_SIZE) + 1
end

-- Gets the oldest valid position sample
---@param data TrackingData
---@param current_time number
---@return {pos: Vector, time: number}|nil
local function get_oldest_sample(data, current_time)
    local oldest = nil
    local oldest_time = current_time
    
    for i = 1, VELOCITY_CONFIG.HISTORY_SIZE do
        local sample = data.positions[i]
        if sample and (current_time - sample.time) < VELOCITY_CONFIG.MAX_DELTA_TIME then
            if sample.time < oldest_time then
                oldest_time = sample.time
                oldest = sample
            end
        end
    end
    
    return oldest
end

-- Gets the most recent position sample
---@param data TrackingData
---@return {pos: Vector, time: number}|nil
local function get_newest_sample(data)
    local newest = nil
    local newest_time = 0
    
    for i = 1, VELOCITY_CONFIG.HISTORY_SIZE do
        local sample = data.positions[i]
        if sample and sample.time > newest_time then
            newest_time = sample.time
            newest = sample
        end
    end
    
    return newest
end

-- Calculates velocity from position history using linear regression for better accuracy
---@param data TrackingData
---@param current_time number
---@return Vector
local function calculate_velocity_from_history(data, current_time)
    local samples = {}
    local count = 0
    
    -- Collect valid samples
    for i = 1, VELOCITY_CONFIG.HISTORY_SIZE do
        local sample = data.positions[i]
        if sample and (current_time - sample.time) < VELOCITY_CONFIG.MAX_DELTA_TIME then
            count = count + 1
            samples[count] = sample
        end
    end
    
    if count < 2 then
        return Vector(0, 0, 0)
    end
    
    -- Sort samples by time
    table.sort(samples, function(a, b) return a.time < b.time end)
    
    -- Use weighted average of velocity between consecutive samples
    -- More recent samples get higher weight
    local total_weight = 0
    local weighted_vel = Vector(0, 0, 0)
    
    for i = 2, count do
        local prev = samples[i - 1]
        local curr = samples[i]
        local dt = curr.time - prev.time
        
        if dt > VELOCITY_CONFIG.MIN_DELTA_TIME then
            local vel = (curr.pos - prev.pos) / dt
            -- Weight by recency (more recent = higher weight)
            local weight = i / count
            weighted_vel = weighted_vel + vel * weight
            total_weight = total_weight + weight
        end
    end
    
    if total_weight > 0 then
        return weighted_vel / total_weight
    end
    
    return Vector(0, 0, 0)
end

-- Smoothly interpolates between vectors using exponential smoothing
---@param current Vector
---@param target Vector
---@param factor number
---@return Vector
local function smooth_vector(current, target, factor)
    return current + (target - current) * factor
end

-- Updates tracking data for an entity
---@param ent entity
---@param current_time number
---@return Vector velocity
---@return Vector acceleration
local function update_entity_tracking(ent, current_time)
    if not ent or not ent:valid() then
        return Vector(0, 0, 0), Vector(0, 0, 0)
    end
    
    local handle = ent:get_handle()
    local current_pos = ent:get_origin()
    
    if not current_pos then
        return Vector(0, 0, 0), Vector(0, 0, 0)
    end
    
    -- Initialize tracking data if needed
    if not entity_tracking[handle] then
        entity_tracking[handle] = create_tracking_data()
    end
    
    local data = entity_tracking[handle]
    local dt = current_time - data.last_update
    
    -- Check if this is a new update (avoid processing same frame twice)
    if dt < VELOCITY_CONFIG.MIN_DELTA_TIME then
        return data.velocity, data.acceleration
    end
    
    -- Store previous velocity for acceleration calculation
    local prev_velocity = data.velocity
    
    -- Add new position sample
    add_position_sample(data, current_pos, current_time)
    data.last_update = current_time
    
    -- Calculate raw velocity from history
    local raw_velocity = calculate_velocity_from_history(data, current_time)
    
    -- Apply exponential smoothing to velocity
    data.velocity = smooth_vector(data.velocity, raw_velocity, VELOCITY_CONFIG.VELOCITY_SMOOTHING)
    
    -- Calculate and smooth acceleration
    if dt < VELOCITY_CONFIG.MAX_DELTA_TIME then
        local raw_accel = (data.velocity - prev_velocity) / dt
        data.acceleration = smooth_vector(data.acceleration, raw_accel, VELOCITY_CONFIG.ACCEL_SMOOTHING)
    end
    
    return data.velocity, data.acceleration
end

-- Gets the tracked velocity for an entity (call this instead of ent:get_velocity() for enemies)
---@param ent entity
---@return Vector velocity
---@return Vector acceleration
function Prediction.GetTrackedVelocity(ent)
    if not ent or not ent:valid() then
        return Vector(0, 0, 0), Vector(0, 0, 0)
    end
    
    local current_time = global_vars.curtime()
    return update_entity_tracking(ent, current_time)
end

-- Checks if we have valid tracking data for an entity
---@param ent entity
---@return boolean
function Prediction.HasValidTracking(ent)
    if not ent or not ent:valid() then
        return false
    end
    
    local handle = ent:get_handle()
    local data = entity_tracking[handle]
    
    if not data then
        return false
    end
    
    local current_time = global_vars.curtime()
    return (current_time - data.last_update) < VELOCITY_CONFIG.STALE_THRESHOLD
end

-- Cleans up stale tracking data (call periodically to prevent memory leaks)
function Prediction.CleanupStaleTracking()
    local current_time = global_vars.curtime()
    local to_remove = {}
    
    for handle, data in pairs(entity_tracking) do
        if (current_time - data.last_update) > VELOCITY_CONFIG.STALE_THRESHOLD * 2 then
            to_remove[#to_remove + 1] = handle
        end
    end
    
    for _, handle in ipairs(to_remove) do
        entity_tracking[handle] = nil
    end
end

-- Resets tracking data for a specific entity
---@param ent entity
function Prediction.ResetTracking(ent)
    if not ent or not ent:valid() then
        return
    end
    entity_tracking[ent:get_handle()] = nil
end

-- Resets all tracking data
function Prediction.ResetAllTracking()
    entity_tracking = {}
end

---@endsection

---@section Helpers

local function get_hero_name(ent)
    if not ent or not ent:valid() then return nil end
    
    local name = ent:get_name()
    if name and HERO_SPEEDS[name] then
        return name
    end
    
    local class_name = ent:get_class_name()
    if class_name then
        local hero_match = string.match(class_name, "(hero_%w+)")
        if hero_match and HERO_SPEEDS[hero_match] then
            return hero_match
        end
    end
    
    local success, hero_data = pcall(function()
        local hero_comp = ent["m_CCitadelHeroComponent"]
        if hero_comp then
            local spawned_hero = hero_comp["m_spawnedHero"]
            if spawned_hero then
                local hero_data_ptr = spawned_hero["m_pHeroData"]
                if hero_data_ptr then
                    return hero_data_ptr["m_pszHeroId"]
                end
            end
        end
        return nil
    end)
    
    if success and hero_data then
        return hero_data
    end
    
    local vdata_name = ent:get_vdata_class_name()
    if vdata_name then
        local hero_match = string.match(vdata_name, "(hero_%w+)")
        if hero_match then
            return hero_match
        end
    end
    
    return nil
end

local function get_spirit_power(ent)
    if not ent or not ent:valid() then return 0 end
    local success, spirit = pcall(function()
        return ent:get_modifier_value(EModifierValue.MODIFIER_VALUE_TECH_POWER, 0)
    end)
    if success and spirit then return spirit end
    return 0
end

local function get_hero_speeds(ent)
    local hero_name = get_hero_name(ent)
    local speeds = HERO_SPEEDS[hero_name] or MEAN_HERO_SPEEDS
    
    local base_speed = speeds.move
    local sprint_speed = speeds.total
    
    if hero_name and SPIRIT_SCALING[hero_name] then
        local spirit = get_spirit_power(ent)
        local bonus = spirit * SPIRIT_SCALING[hero_name]
        base_speed = base_speed + bonus
        sprint_speed = sprint_speed + bonus
    end
    
    return {
        base = base_speed,
        sprint = sprint_speed,
        crouch = CROUCH.BASE
    }
end

-- Determines if an entity is the local player
---@param ent entity
---@return boolean
local function is_local_player(ent)
    if not ent or not ent:valid() then return false end
    local local_pawn = entity_list.local_pawn()
    if not local_pawn or not local_pawn:valid() then return false end
    return ent:get_handle() == local_pawn:get_handle()
end

local function pred_clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function pred_len2d(v)
    if not v then return 0 end
    local x = tonumber(v.x) or 0
    local y = tonumber(v.y) or 0
    return math.sqrt(x * x + y * y)
end

local function pred_count_tracking_samples(ent)
    if not ent or not ent:valid() then return 0 end
    local handle = ent:get_handle()
    local data = entity_tracking[handle]
    if not data or type(data.positions) ~= "table" then
        return 0
    end
    local n = 0
    for i = 1, VELOCITY_CONFIG.HISTORY_SIZE do
        if data.positions[i] then
            n = n + 1
        end
    end
    return n
end

local function pred_get_native_velocity(ent)
    if not ent or not ent:valid() then
        return Vector(0, 0, 0)
    end
    local ok, vel = pcall(function() return ent:get_velocity() end)
    if ok and vel then
        return vel
    end
    return Vector(0, 0, 0)
end

local function pred_get_velocity_and_accel(ent)
    local zero = Vector(0, 0, 0)
    if not ent or not ent:valid() then
        return zero, zero
    end

    if is_local_player(ent) then
        return pred_get_native_velocity(ent), zero
    end

    local tracked_vel, tracked_accel = Prediction.GetTrackedVelocity(ent)
    tracked_vel = tracked_vel or zero
    tracked_accel = tracked_accel or zero

    local sample_count = pred_count_tracking_samples(ent)
    local native_vel = pred_get_native_velocity(ent)

    if sample_count < 2 then
        return native_vel, tracked_accel
    end

    if pred_len2d(tracked_vel) < 1.0 and pred_len2d(native_vel) > 3.0 then
        return native_vel, tracked_accel
    end

    return tracked_vel, tracked_accel
end

local function pred_resolve_aim_offset(ent, current_origin, aim_mode)
    local target_bone = "spine_0"
    if type(aim_mode) == "string" and aim_mode ~= "" then
        if aim_mode == "spine" then
            target_bone = "spine_0"
        else
            target_bone = aim_mode
        end
    end

    local aim_offset = Vector(0, 0, 0)
    local ok, bone_pos = pcall(function() return ent:get_bone_pos(target_bone) end)
    if (not ok) or (not bone_pos) then
        if target_bone ~= "spine_0" then
            local ok_spine, spine = pcall(function() return ent:get_bone_pos("spine_0") end)
            if ok_spine and spine then
                bone_pos = spine
            end
        end
    end

    if bone_pos and current_origin then
        aim_offset = bone_pos - current_origin
    end
    return aim_offset
end

local function pred_apply_2d_speed_cap(vel, max_speed)
    if not vel then
        return Vector(0, 0, 0)
    end
    local cap = tonumber(max_speed) or 0
    if cap <= 0 then
        return vel
    end
    local spd = vel:Length2D()
    if spd <= cap or spd <= 0.001 then
        return vel
    end
    local scale = cap / spd
    return Vector(vel.x * scale, vel.y * scale, vel.z)
end

local function pred_apply_accel_cap(accel, max_accel)
    if not accel then
        return Vector(0, 0, 0)
    end
    local cap = tonumber(max_accel) or 0
    if cap <= 0 then
        return accel
    end
    local ax = tonumber(accel.x) or 0
    local ay = tonumber(accel.y) or 0
    local az = tonumber(accel.z) or 0
    local len = math.sqrt(ax * ax + ay * ay + az * az)
    if len <= cap or len <= 0.001 then
        return accel
    end
    local s = cap / len
    return Vector(ax * s, ay * s, az * s)
end

local function pred_compute_displacement(vel, accel, dt, use_acceleration, max_lead_distance)
    local d
    if use_acceleration and accel then
        d = vel * dt + accel * (0.5 * dt * dt)
    else
        d = vel * dt
    end

    local lead_cap = tonumber(max_lead_distance) or 0
    if lead_cap > 0 then
        local dx = tonumber(d.x) or 0
        local dy = tonumber(d.y) or 0
        local len2d = math.sqrt(dx * dx + dy * dy)
        if len2d > lead_cap and len2d > 0.001 then
            local s = lead_cap / len2d
            d = Vector(dx * s, dy * s, tonumber(d.z) or 0)
        end
    end

    return d
end

local function pred_apply_wall_clip(start_pos, predicted_pos, displacement, ent)
    local final_pos = predicted_pos
    local clip_ok, clip_tr = pcall(function()
        return trace.line(
            start_pos,
            predicted_pos,
            0, 0, 0,
            MASK_SOLID,
            0,
            function(e)
                return e and e:valid() and e:get_index() == ent:get_index()
            end
        )
    end)

    if clip_ok and clip_tr and clip_tr.fraction and clip_tr.fraction < 1.0 then
        final_pos = start_pos + (displacement * clip_tr.fraction * 0.95)
    end
    return final_pos
end

---@endsection

---@section Main Predictor

---@param ent entity
---@param time number
---@param cmd_buttons any (unused, kept for API compatibility)
---@param cmd_move_x any (unused, kept for API compatibility)
---@param cmd_move_y any (unused, kept for API compatibility)
---@param cmd_yaw any (unused, kept for API compatibility)
---@param aim_mode string|nil "head" or nil for spine
---@param use_acceleration boolean|nil whether to factor in acceleration
---@return Vector
function Prediction.PredictPlayer(ent, time, cmd_buttons, cmd_move_x, cmd_move_y, cmd_yaw, aim_mode, use_acceleration)
    if not ent or not ent:valid() then return Vector(0, 0, 0) end

    local current_origin = ent:get_origin()
    if not current_origin then return Vector(0, 0, 0) end

    local dt = pred_clamp(tonumber(time) or 0, 0.0, 1.35)
    local aim_offset = pred_resolve_aim_offset(ent, current_origin, aim_mode)
    local vel, accel = pred_get_velocity_and_accel(ent)
    local displacement = pred_compute_displacement(vel, accel, dt, use_acceleration == true, 0)
    local predicted_pos = current_origin + displacement
    local final_pos = pred_apply_wall_clip(current_origin, predicted_pos, displacement, ent)
    return final_pos + aim_offset
end

-- Extended prediction that considers hero movement capabilities
---@param ent entity
---@param time number
---@param aim_mode string|nil
---@param options table|nil {use_acceleration: boolean, clamp_to_max_speed: boolean}
---@return Vector
function Prediction.PredictPlayerAdvanced(ent, time, aim_mode, options)
    if not ent or not ent:valid() then return Vector(0, 0, 0) end

    if type(aim_mode) == "table" and options == nil then
        options = aim_mode
        aim_mode = nil
    end

    options = options or {}
    local use_acceleration = options.use_acceleration ~= false
    local clamp_to_max_speed = options.clamp_to_max_speed or false
    local max_accel = tonumber(options.max_accel) or 2200.0
    local max_lead_distance = tonumber(options.max_lead_distance) or 0.0
    local multi_sample = options.multi_sample == true
    local sample_spread = pred_clamp(tonumber(options.sample_spread) or 0.045, 0.0, 0.18)
    local sample_count = math.floor(pred_clamp(tonumber(options.sample_count) or 3, 1, 5))
    local blend = pred_clamp(tonumber(options.blend) or 0.0, 0.0, 1.0)
    local max_time = pred_clamp(tonumber(options.max_time) or 1.35, 0.05, 2.0)
    local min_time = pred_clamp(tonumber(options.min_time) or 0.0, 0.0, max_time)
    local forward_time = pred_clamp(tonumber(options.forward_time) or 0.0, 0.0, 0.30)
    local dt = pred_clamp((tonumber(time) or 0) + forward_time, min_time, max_time)
    
    local current_origin = ent:get_origin()
    if not current_origin then return Vector(0, 0, 0) end

    local aim_offset = pred_resolve_aim_offset(ent, current_origin, aim_mode)
    local vel, accel = pred_get_velocity_and_accel(ent)
    accel = pred_apply_accel_cap(accel, max_accel)
    
    if clamp_to_max_speed then
        local speeds = get_hero_speeds(ent)
        local max_speed = tonumber(speeds and speeds.sprint) or 0.0
        local scale = tonumber(options.max_speed_scale) or 1.0
        if max_speed > 0 then
            vel = pred_apply_2d_speed_cap(vel, max_speed * scale)
        end
    end

    local displacement = pred_compute_displacement(vel, accel, dt, use_acceleration, max_lead_distance)

    if multi_sample and dt > 0.02 and sample_count > 1 and sample_spread > 0.001 then
        local accum = displacement
        local weight = 1.0
        local half = math.floor(sample_count / 2)
        for i = 1, sample_count do
            local k = i - 1 - half
            if k ~= 0 then
                local t_i = pred_clamp(dt + k * sample_spread, 0.0, max_time)
                local d_i = pred_compute_displacement(vel, accel, t_i, use_acceleration, max_lead_distance)
                local w = 1.0 - (math.abs(k) / (half + 1))
                accum = accum + d_i * w
                weight = weight + w
            end
        end
        if weight > 0 then
            local blended = accum / weight
            displacement = displacement * (1.0 - blend) + blended * blend
        else
            displacement = accum
        end
    end

    local predicted_pos = current_origin + displacement
    local final_pos = pred_apply_wall_clip(current_origin, predicted_pos, displacement, ent)
    return final_pos + aim_offset
end

---@param ent entity
---@param options table|nil {max_time:number,sample_dt:number,z_offset:number,trace_up:number,trace_down:number,touch_epsilon:number,airborne_vz:number,gravity:number}
---@return table|nil {pos:Vector,time:number,airborne:boolean,grounded:boolean}
function Prediction.PredictLandingPoint(ent, options)
    if not ent or not ent:valid() then
        return nil
    end

    options = options or {}
    local origin = ent:get_origin()
    if not origin then
        return nil
    end

    local z_offset = tonumber(options.z_offset) or 12
    local max_time = pred_clamp(tonumber(options.max_time) or 1.2, 0.1, 3.0)
    local sample_dt = pred_clamp(tonumber(options.sample_dt) or 0.08, 0.01, 0.2)
    local trace_up = tonumber(options.trace_up) or 68
    local trace_down = tonumber(options.trace_down) or 760
    local touch_epsilon = tonumber(options.touch_epsilon) or 20
    local airborne_vz = tonumber(options.airborne_vz) or 70
    local gravity = tonumber(options.gravity) or 980
    if gravity < 0 then
        gravity = -gravity
    end

    local vel, accel = pred_get_velocity_and_accel(ent)
    local on_ground = Prediction.IsOnGround(ent)
    local vz = tonumber(vel and vel.z) or 0.0
    local airborne = (not on_ground) or math.abs(vz) >= airborne_vz

    if not airborne then
        return {
            pos = Vector(origin.x, origin.y, origin.z + z_offset),
            time = 0.0,
            airborne = false,
            grounded = true,
        }
    end

    local vx = tonumber(vel.x) or 0.0
    local vy = tonumber(vel.y) or 0.0
    local vz0 = tonumber(vel.z) or 0.0
    local ax = tonumber(accel and accel.x) or 0.0
    local ay = tonumber(accel and accel.y) or 0.0
    local az = tonumber(accel and accel.z) or 0.0

    local fallback_pos = Vector(origin.x, origin.y, origin.z + z_offset)
    local fallback_t = 0.0

    local t = sample_dt
    while t <= max_time + 0.0001 do
        local px = origin.x + vx * t + 0.5 * ax * t * t
        local py = origin.y + vy * t + 0.5 * ay * t * t
        local pz = origin.z + vz0 * t + 0.5 * (az - gravity) * t * t

        local probe_top = Vector(px, py, pz + trace_up)
        local probe_bottom = Vector(px, py, pz - trace_down)
        local landed = false
        local land_pos = nil

        local ok, tr = pcall(function()
            return trace.line(probe_top, probe_bottom, 0, 0, 0, MASK_SOLID, 0, nil)
        end)
        if ok and tr and tr.fraction and tr.fraction < 0.995 and tr.fraction > 0.0 then
            local hz = probe_top.z + (probe_bottom.z - probe_top.z) * tr.fraction
            if pz <= (hz + touch_epsilon) then
                landed = true
                land_pos = Vector(px, py, hz + z_offset)
            end
        end

        fallback_pos = Vector(px, py, pz + z_offset)
        fallback_t = t

        if landed then
            return {
                pos = land_pos,
                time = t,
                airborne = true,
                grounded = true,
            }
        end

        t = t + sample_dt
    end

    return {
        pos = fallback_pos,
        time = fallback_t,
        airborne = true,
        grounded = false,
    }
end

---@endsection

-- Public API
function Prediction.GetHeroSpeeds(ent) return get_hero_speeds(ent) end
function Prediction.GetHeroName(ent) return get_hero_name(ent) end
function Prediction.GetAllHeroSpeeds() return HERO_SPEEDS end
function Prediction.GetMeanSpeeds() return MEAN_HERO_SPEEDS end
function Prediction.GetDashStats(hero_name) return get_dash_stats(hero_name) end

-- ═══════════════════════════════════════════════════════════════
-- New stuff below here
-- ═══════════════════════════════════════════════════════════════

-- ═══════ Arc Projectile Prediction ═══════

function Prediction.PredictArc(source_pos, target, speed, gravity, aim_bone)
    if not target or not target:valid() then return nil, 0 end
    gravity  = gravity or 800
    aim_bone = aim_bone or "spine_0"

    if speed <= 0 then
        return target:get_bone_pos(aim_bone) or target:get_origin(), 0
    end

    local predicted_pos = Prediction.PredictPlayer(target, 0, nil, nil, nil, nil, aim_bone)
    local t = 0.0

    for i = 1, 6 do
        local dx = math.sqrt(
            (predicted_pos.x - source_pos.x) * (predicted_pos.x - source_pos.x) +
            (predicted_pos.y - source_pos.y) * (predicted_pos.y - source_pos.y)
        )
        local new_t = dx / speed
        if math.abs(new_t - t) < 0.005 then break end
        t = new_t
        predicted_pos = Prediction.PredictPlayer(target, t, nil, nil, nil, nil, aim_bone)
    end

    -- Compensate for gravity drop: aim higher by 0.5 * g * t^2
    local gravity_comp = 0.5 * gravity * t * t
    local arc_pos = Vector(predicted_pos.x, predicted_pos.y, predicted_pos.z + gravity_comp)

    return arc_pos, t
end

-- ═══════ Wall Check ═══════

function Prediction.WillHitWall(start_pos, direction, max_distance)
    local z_offset = 20  -- Avoid ground clipping
    local trace_start = Vector(start_pos.x, start_pos.y, start_pos.z + z_offset)
    local dir = Vector(direction.x, direction.y, 0):Normalized()
    local trace_end = Vector(
        trace_start.x + dir.x * max_distance,
        trace_start.y + dir.y * max_distance,
        trace_start.z  -- Same Z = horizontal trace
    )

    local ok, tr = pcall(function()
        return trace.line(trace_start, trace_end, 0, 0, 0, MASK_SOLID, 0, nil)
    end)

    if ok and tr then
        return tr.fraction < 0.99, tr
    end
    return false, nil
end

-- ═══════ Knockback Prediction ═══════

function Prediction.PredictKnockback(source_pos, target, knockback_metres, options)
    if not target or not target:valid() then
        return { will_hit_wall = false }
    end
    options = options or {}

    local UNIT_METER = 37.7358490566
    local knockback_dist = knockback_metres * UNIT_METER
    local target_pos = target:get_origin()

    -- Direction: from source toward target (enemy gets pushed away)
    local dir = Vector(
        target_pos.x - source_pos.x,
        target_pos.y - source_pos.y,
        0
    ):Normalized()

    local will_hit, tr = Prediction.WillHitWall(target_pos, dir, knockback_dist)

    local result = {
        will_hit_wall  = will_hit,
        direction      = dir,
        knockback_dist = knockback_dist,
    }

    if will_hit and tr then
        result.wall_dist = knockback_dist * tr.fraction
        result.wall_pos = Vector(
            target_pos.x + dir.x * knockback_dist * tr.fraction,
            target_pos.y + dir.y * knockback_dist * tr.fraction,
            target_pos.z
        )
        result.final_pos = result.wall_pos
    else
        result.wall_dist = knockback_dist
        result.final_pos = Vector(
            target_pos.x + dir.x * knockback_dist,
            target_pos.y + dir.y * knockback_dist,
            target_pos.z
        )
    end

    return result
end

-- ═══════ Movement State Estimation ═══════
-- Estimates whether an entity is idle, crouching, walking, sprinting, or dashing.
-- Also detects if airborne using m_fFlags (FL_ONGROUND) and modifier states.
-- Returns: { state, speed, velocity, hero_speeds, airborne, on_ground, cc_state }

function Prediction.EstimateMovementState(entity)
    if not entity or not entity:valid() then
        return { state = "unknown", speed = 0, airborne = false, on_ground = false, cc_state = "none" }
    end

    local vel, _ = Prediction.GetTrackedVelocity(entity)
    local speed_2d = vel:Length2D()

    local hero_name = get_hero_name(entity)
    local speeds = HERO_SPEEDS[hero_name] or MEAN_HERO_SPEEDS

    -- Ground state: prefer m_fFlags bit 0 (FL_ONGROUND), fallback to vel.z heuristic
    local on_ground = false
    local ok_flags, flags = pcall(function() return entity.m_fFlags end)
    if ok_flags and flags then
        on_ground = (flags % 2) == 1
    else
        on_ground = math.abs(vel.z) < 10
    end

    -- CC state detection (useful for prediction accuracy — CC'd targets are predictable)
    local cc_state = "none"
    if Utils then
        if Utils.IsStunned(entity) then
            cc_state = "stunned"
        elseif Utils.IsImmobilized(entity) then
            cc_state = "immobilized"
        end
    end

    local result = {
        speed       = speed_2d,
        velocity    = vel,
        hero_speeds = speeds,
        airborne    = not on_ground,
        on_ground   = on_ground,
        cc_state    = cc_state,
    }

    -- CC'd targets are effectively idle for prediction purposes
    if cc_state == "stunned" then
        result.state = "stunned"
        return result
    elseif cc_state == "immobilized" then
        result.state = "immobilized"
        return result
    end

    if speed_2d < 10 then
        result.state = "idle"
    elseif speed_2d < CROUCH.BASE + 20 then
        result.state = "crouching"
    elseif speed_2d < speeds.move + 20 then
        result.state = "walking"
    elseif speed_2d < speeds.total + 50 then
        result.state = "sprinting"
    else
        result.state = "dashing"
    end

    return result
end

-- ═══════ Bounce simulation ═══════

function Prediction.SimulateBounce(start_pos, direction, max_bounces, max_range_metres, options)
    options = options or {}
    local UNIT_METER = 37.7358490566
    local max_range  = (max_range_metres or 100) * UNIT_METER
    max_bounces = max_bounces or 3

    local positions   = { start_pos }
    local current_pos = start_pos
    local current_dir = Vector(direction.x, direction.y, direction.z):Normalized()
    local total_dist  = 0

    for i = 1, max_bounces do
        local remaining = max_range - total_dist
        if remaining <= 0 then break end

        local trace_start = Vector(current_pos.x, current_pos.y, current_pos.z + 10)
        local trace_end   = Vector(
            trace_start.x + current_dir.x * remaining,
            trace_start.y + current_dir.y * remaining,
            trace_start.z + current_dir.z * remaining
        )

        local ok, tr = pcall(function()
            return trace.line(trace_start, trace_end, 0, 0, 0, MASK_SOLID, 0,
                options.ignore_filter or nil)
        end)

        if ok and tr and tr.fraction < 0.99 then
            local hit_pos = Vector(
                trace_start.x + (trace_end.x - trace_start.x) * tr.fraction,
                trace_start.y + (trace_end.y - trace_start.y) * tr.fraction,
                trace_start.z + (trace_end.z - trace_start.z) * tr.fraction
            )
            positions[#positions + 1] = hit_pos
            total_dist = total_dist + remaining * tr.fraction

            -- Reflect direction off surface normal if available
            if tr.normal then
                local dot = current_dir.x * tr.normal.x
                          + current_dir.y * tr.normal.y
                          + current_dir.z * tr.normal.z
                current_dir = Vector(
                    current_dir.x - 2 * dot * tr.normal.x,
                    current_dir.y - 2 * dot * tr.normal.y,
                    current_dir.z - 2 * dot * tr.normal.z
                ):Normalized()
            else
                -- Fallback: reverse horizontal direction
                current_dir = Vector(-current_dir.x, -current_dir.y, current_dir.z):Normalized()
            end

            -- Small offset to avoid re-hitting same surface
            current_pos = Vector(
                hit_pos.x + current_dir.x * 2,
                hit_pos.y + current_dir.y * 2,
                hit_pos.z + current_dir.z * 2
            )
        else
            local end_pos = Vector(
                current_pos.x + current_dir.x * remaining,
                current_pos.y + current_dir.y * remaining,
                current_pos.z + current_dir.z * remaining
            )
            positions[#positions + 1] = end_pos
            break
        end
    end

    return positions
end

-- ═══════ Raycasting Utilities ═══════

--- Check line-of-sight between two world positions.
--- Returns true if the path is mostly unobstructed (fraction > threshold).
---@param from_pos Vector
---@param to_pos Vector
---@param threshold number|nil fraction threshold (default 0.95)
---@return boolean
function Prediction.IsPositionVisible(from_pos, to_pos, threshold)
    if not from_pos or not to_pos then return false end
    threshold = threshold or 0.95
    local ok, tr = pcall(function()
        return trace.line(from_pos, to_pos, 0, 0, 0, 0, 0, function() return false end)
    end)
    if ok and tr and tr.fraction then
        return tr.fraction > threshold
    end
    return false
end

--- Check if a specific entity is visible from a position.
--- Uses trace.line + is_visible_entity, falls back to trace.bullet.
---@param from_pos Vector
---@param to_pos Vector
---@param target_entity entity
---@param max_dist number|nil
---@return boolean
function Prediction.IsEntityVisible(from_pos, to_pos, target_entity, max_dist)
    if not from_pos or not to_pos or not target_entity then return false end
    max_dist = max_dist or from_pos:Distance(to_pos)

    local visible = false
    pcall(function()
        local local_pawn = entity_list.local_pawn()
        local tr = trace.line(from_pos, to_pos, 0x4001, 0, 0, 0, 0, function(ent)
            if local_pawn and ent == local_pawn then return true end
            return false
        end)
        if tr then
            visible = tr:is_visible_entity(target_entity, max_dist)
        end
    end)
    if visible then return true end

    pcall(function()
        visible = trace.bullet(from_pos, to_pos, 1.0, target_entity)
    end)
    return visible
end

---@param origin Vector center position to scan from
---@param max_distance number max ray length (world units)
---@param num_rays number|nil number of rays in circle (default 16)
---@param z_offset number|table|nil vertical offset from origin (default 60), can be array of layers
---@return table[] array of { pos, distance, normal, angle_rad, layer_offset }
function Prediction.FindNearbyWalls(origin, max_distance, num_rays, z_offset)
    if not origin then return {} end
    num_rays = math.max(8, tonumber(num_rays) or 16)
    max_distance = tonumber(max_distance) or 420

    local layers = {}
    if type(z_offset) == "table" then
        for i = 1, #z_offset do
            layers[#layers + 1] = tonumber(z_offset[i]) or 60
        end
    else
        layers[1] = tonumber(z_offset) or 60
    end
    if #layers == 0 then
        layers = { 60 }
    end

    local walls = {}
    for li = 1, #layers do
        local layer = layers[li]
        local trace_origin = Vector(origin.x, origin.y, origin.z + layer)

        for i = 0, num_rays - 1 do
            local angle = (i / num_rays) * math.pi * 2
            local dir_x = math.cos(angle)
            local dir_y = math.sin(angle)

            local trace_end = Vector(
                trace_origin.x + dir_x * max_distance,
                trace_origin.y + dir_y * max_distance,
                trace_origin.z
            )

            local ok, tr = pcall(function()
                return trace.line(trace_origin, trace_end, 0, 0, 0, MASK_SOLID, 0, nil)
            end)

            if ok and tr and tr.fraction and tr.fraction < 0.995 and tr.fraction > 0.04 then
                local hit_dist = tr.fraction * max_distance
                if hit_dist > 18 then
                    local hit_pos = Vector(
                        trace_origin.x + dir_x * hit_dist,
                        trace_origin.y + dir_y * hit_dist,
                        trace_origin.z
                    )

                    local normal
                    if tr.normal then
                        normal = tr.normal
                    else
                        normal = Vector(-dir_x, -dir_y, 0)
                    end

                    walls[#walls + 1] = {
                        pos = hit_pos,
                        distance = hit_dist,
                        normal = normal,
                        angle_rad = angle,
                        layer_offset = layer,
                    }
                end
            end
        end
    end

    table.sort(walls, function(a, b) return a.distance < b.distance end)
    return walls
end

--- Find the closest wall to a position.
--- Convenience wrapper around FindNearbyWalls.
---@param origin Vector
---@param max_distance number
---@param num_rays number|nil (default 16)
---@return Vector|nil hit_pos
---@return Vector|nil normal
---@return number|nil distance
function Prediction.FindClosestWall(origin, max_distance, num_rays)
    local walls = Prediction.FindNearbyWalls(origin, max_distance, num_rays)
    if #walls == 0 then return nil, nil, nil end
    local w = walls[1]
    return w.pos, w.normal, w.distance
end

local function pred_point_to_segment_dist(point, seg_a, seg_b)
    local ax, ay, az = seg_a.x, seg_a.y, seg_a.z
    local bx, by, bz = seg_b.x, seg_b.y, seg_b.z
    local px, py, pz = point.x, point.y, point.z
    local abx, aby, abz = bx - ax, by - ay, bz - az
    local apx, apy, apz = px - ax, py - ay, pz - az
    local ab_len_sq = abx * abx + aby * aby + abz * abz
    if ab_len_sq <= 0.000001 then
        local dx, dy, dz = px - ax, py - ay, pz - az
        return math.sqrt(dx * dx + dy * dy + dz * dz)
    end
    local t = (apx * abx + apy * aby + apz * abz) / ab_len_sq
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local cx, cy, cz = ax + abx * t, ay + aby * t, az + abz * t
    local dx, dy, dz = px - cx, py - cy, pz - cz
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Prediction.FindBestWallTargetAdvanced(origin, max_wall_dist, camera_pos, camera_angles, options)
    if not (origin and camera_pos and camera_angles) then return nil end
    options = options or {}
    local rays = tonumber(options.rays) or 20
    local max_fov = tonumber(options.max_fov) or 35
    local z_base = tonumber(options.z_offset) or 0
    local focus = options.focus_pos or origin
    local max_focus_distance = tonumber(options.max_focus_distance)
    local layers = options.layers
    if type(layers) ~= "table" or #layers == 0 then
        layers = { 28, 52, 76, 98 }
    end
    local scan_layers = {}
    for i = 1, #layers do
        scan_layers[#scan_layers + 1] = (tonumber(layers[i]) or 60) + z_base
    end

    local walls = Prediction.FindNearbyWalls(origin, max_wall_dist, rays, scan_layers)
    if #walls == 0 then return nil end

    local cam_to_enemy_len_sq = (origin.x - camera_pos.x) * (origin.x - camera_pos.x)
        + (origin.y - camera_pos.y) * (origin.y - camera_pos.y)
        + (origin.z - camera_pos.z) * (origin.z - camera_pos.z)
    if cam_to_enemy_len_sq <= 0.0001 then
        cam_to_enemy_len_sq = 1.0
    end

    local best = nil
    local best_score = nil
    for _, wall in ipairs(walls) do
        if Prediction.IsPositionVisible(camera_pos, wall.pos) then
            local aim_angle = utils.calc_angle(camera_pos, wall.pos)
            local fov = tonumber(utils.get_fov(camera_angles, aim_angle)) or 999.0
            if fov <= max_fov then
                local focus_dx = (tonumber(wall.pos.x) or 0.0) - (tonumber(focus.x) or 0.0)
                local focus_dy = (tonumber(wall.pos.y) or 0.0) - (tonumber(focus.y) or 0.0)
                local focus_dist = math.sqrt(focus_dx * focus_dx + focus_dy * focus_dy)
                local focus_ok = (not max_focus_distance) or (focus_dist <= max_focus_distance)
                if focus_ok then
                    local line_dist = pred_point_to_segment_dist(wall.pos, camera_pos, origin)
                    local to_cam_x, to_cam_y = camera_pos.x - origin.x, camera_pos.y - origin.y
                    local to_hit_x, to_hit_y = wall.pos.x - origin.x, wall.pos.y - origin.y
                    local side_bonus = (to_cam_x * to_hit_x + to_cam_y * to_hit_y) / math.sqrt(cam_to_enemy_len_sq)
                    local layer_pen = math.abs((tonumber(wall.layer_offset) or 60) - (60 + z_base))
                    local score = fov * 4.8 + line_dist * 0.32 + (tonumber(wall.distance) or 0) * 0.06 + focus_dist * 1.15 - side_bonus * 0.08 + layer_pen * 0.04
                    if (best_score == nil) or (score < best_score) then
                        best_score = score
                        best = {
                            pos = wall.pos,
                            distance = wall.distance,
                            normal = wall.normal,
                            fov = fov,
                            score = score,
                            layer_offset = wall.layer_offset,
                        }
                    end
                end
            end
        end
    end
    return best
end

function Prediction.FindBestWallTarget(origin, max_wall_dist, camera_pos, camera_angles, num_rays)
    return Prediction.FindBestWallTargetAdvanced(origin, max_wall_dist, camera_pos, camera_angles, {
        rays = num_rays or 16,
        max_fov = 180,
    })
end

-- ═══════ Engine-Backed Movement Simulation ═══════
-- Uses pawn:simulate_movement() for engine-accurate prediction.
-- Only works on enemy pawn entities. Falls back to PredictPlayer on failure.
-- The callback receives (simulated_pos, simulated_vel) per tick.
--
---@param ent entity Target pawn to simulate
---@param time number Duration to simulate (seconds)
---@param aim_mode string|nil "head" or nil for spine
---@return Vector predicted position
function Prediction.SimulateMovementPredict(ent, time, aim_mode)
    if not ent or not ent:valid() then return Vector(0, 0, 0) end

    -- Get aim offset from bone
    local aim_offset = Vector(0, 0, 0)
    local target_bone = (aim_mode == "head") and "head" or "spine_0"
    local bone_pos = ent:get_bone_pos(target_bone)
    local current_origin = ent:get_origin()
    if bone_pos and current_origin then
        aim_offset = bone_pos - current_origin
    end

    -- Try engine-backed simulate_movement
    local ok, sim_pos = pcall(function()
        local final_pos = nil
        ent:simulate_movement(function(pos, vel)
            final_pos = pos
        end)
        return final_pos
    end)

    if ok and sim_pos then
        return sim_pos + aim_offset
    end

    -- Fallback to our custom prediction
    return Prediction.PredictPlayer(ent, time, nil, nil, nil, nil, aim_mode)
end

-- ═══════ Speed Modifier Reading ═══════
-- Read current move speed modifier value from entity (accounts for slows/haste)
-- Returns the actual speed multiplier if available.

function Prediction.GetSpeedModifier(ent)
    if not ent or not ent:valid() then return 1.0 end
    -- MODIFIER_VALUE_BASE_MOVE_SPEED_PERCENT reads any speed modifiers applied
    local ok, val = pcall(function()
        return ent:get_modifier_value(EModifierValue.MODIFIER_VALUE_BASE_MOVE_SPEED_PERCENT, 100)
    end)
    if ok and val and val ~= 100 then
        return val / 100.0  -- Convert percentage to multiplier
    end
    return 1.0
end

-- ═══════ Is Entity Airborne (engine-backed) ═══════
-- Checks FL_ONGROUND flag from m_fFlags. More reliable than vel.z heuristic.

function Prediction.IsOnGround(ent)
    if not ent or not ent:valid() then return false end
    local ok, flags = pcall(function() return ent.m_fFlags end)
    if ok and flags then
        return (flags % 2) == 1
    end
    return false
end

return Prediction
