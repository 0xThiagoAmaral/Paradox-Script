local Utils = {}

Utils.UNIT_METER = 37.7358490566

-- ═══════ Modifier State IDs ═══════
-- Sourced from debug_logger VData analysis. Use with pawn:has_modifier_state(id)

Utils.ModifierState = {
    STUNNED         = 18,   -- Target is stunned (can't act)
    INVULNERABLE    = 19,   -- Target is invulnerable (damage immune)
    SILENCED        = 27,   -- Target is silenced (no abilities)
    DISARMED        = 28,   -- Target is disarmed (no weapon)
    IMMOBILIZED     = 30,   -- Target is rooted (can't move)
    AIRBORNE        = 209,  -- In-air state (ground flag)
    PARRY_ACTIVE    = 217,  -- Target is actively parrying
    ULTING          = 286,  -- Target is in ultimate cast
    INTANGIBLE      = 1302, -- Target is intangible (e.g. Viscous ball)
}

-- ═══════ Ability Status Codes ═══════
-- Return values from ability:can_be_executed()

Utils.AbilityStatus = {
    READY    = 0,   -- Ability can be cast right now
    COOLDOWN = 2,   -- On cooldown
    PASSIVE  = 3,   -- Passive ability (never manually castable)
    UNKNOWN  = 7,   -- Unknown state
    BUSY     = 10,  -- Ability busy (casting / channeling)
}

-- ═══════ Safe Wrappers ═══════
-- pcall-wrapped entity method calls to prevent crashes from invalid entities

function Utils.SafeCall(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

function Utils.SafeGetVelocity(ent)
    if not ent or not ent:valid() then return nil end
    local ok, vel = pcall(function() return ent:get_velocity() end)
    return ok and vel or nil
end

function Utils.SafeGetName(ent)
    if not ent or not ent:valid() then return nil end
    local ok, name = pcall(function() return ent:get_name() end)
    return ok and name or nil
end

function Utils.SafeGetClassName(ent)
    if not ent or not ent:valid() then return nil end
    local ok, name = pcall(function() return ent:get_class_name() end)
    return ok and name or nil
end

function Utils.SafeGetVDataClassName(ent)
    if not ent or not ent:valid() then return nil end
    local ok, name = pcall(function() return ent:get_vdata_class_name() end)
    return ok and name or nil
end

function Utils.SafeGetOwner(ent)
    if not ent or not ent:valid() then return nil end
    local ok, owner = pcall(function() return ent:get_owner() end)
    return ok and owner or nil
end

-- ═══════ Entity Checks ═══════

function Utils.IsValid(ent)
    return ent ~= nil and ent:valid()
end

function Utils.IsAlive(ent)
    return ent ~= nil and ent:valid() and ent:is_alive()
end

function Utils.GetLocalPawn()
    local pawn = entity_list.local_pawn()
    if not pawn or not pawn:valid() then return nil end
    return pawn
end

-- ═══════ Entity State Checks ═══════
-- Uses modifier states to check entity conditions

function Utils.HasModifierState(ent, state_id)
    if not ent or not ent:valid() then return false end
    local ok, result = pcall(function() return ent:has_modifier_state(state_id) end)
    return ok and result or false
end

function Utils.IsParrying(ent)
    return Utils.HasModifierState(ent, Utils.ModifierState.PARRY_ACTIVE)
end

function Utils.IsStunned(ent)
    return Utils.HasModifierState(ent, Utils.ModifierState.STUNNED)
end

function Utils.IsInvulnerable(ent)
    return Utils.HasModifierState(ent, Utils.ModifierState.INVULNERABLE)
end

function Utils.IsSilenced(ent)
    return Utils.HasModifierState(ent, Utils.ModifierState.SILENCED)
end

function Utils.IsImmobilized(ent)
    return Utils.HasModifierState(ent, Utils.ModifierState.IMMOBILIZED)
end

function Utils.IsUlting(ent)
    return Utils.HasModifierState(ent, Utils.ModifierState.ULTING)
end

--- Returns true if the target should NOT be hit (parrying, invulnerable, intangible)
function Utils.IsWastedTarget(ent)
    if not ent or not ent:valid() then return true end
    return Utils.IsParrying(ent) or Utils.IsInvulnerable(ent)
        or Utils.HasModifierState(ent, Utils.ModifierState.INTANGIBLE)
end

--- Returns true if entity is on the ground (m_fFlags bit 0 = FL_ONGROUND)
function Utils.IsOnGround(ent)
    if not ent or not ent:valid() then return false end
    local ok, flags = pcall(function() return ent.m_fFlags end)
    if ok and flags then
        return (flags % 2) == 1  -- bit 0 check
    end
    return false
end

-- ═══════ Entity Classification ═══════
-- Detect towers, bosses, and minions by class name patterns

function Utils.IsTower(ent)
    if not ent or not ent:valid() then return false end
    local class = Utils.SafeGetClassName(ent)
    if not class then return false end
    return string.find(class, "Sentry") ~= nil or string.find(class, "Tower") ~= nil
end

function Utils.IsMinion(ent)
    if not ent or not ent:valid() then return false end
    local class = Utils.SafeGetClassName(ent)
    if not class then return false end
    return string.find(class, "Trooper") ~= nil or string.find(class, "Creep") ~= nil
end

function Utils.IsHero(ent)
    if not ent or not ent:valid() then return false end
    local class = Utils.SafeGetClassName(ent)
    return class == "C_CitadelPlayerPawn"
end

-- ═══════ VData Helpers ═══════
-- Read ability properties directly from VData (avoids hardcoded constants)

--- Get projectile speed from an ability's VData weapon info
---@param ability entity The ability entity
---@return number|nil speed in units/s, or nil if not found
function Utils.GetAbilityProjectileSpeed(ability)
    if not ability or not ability:valid() then return nil end
    local ok, speed = pcall(function()
        return ability:get_vdata().m_WeaponInfo.m_flBulletSpeed
    end)
    if ok and speed and speed > 0 then return speed end
    -- Fallback: try projectileInfo path
    local ok2, speed2 = pcall(function()
        return ability:get_vdata().m_projectileInfo.m_flSpeed
    end)
    if ok2 and speed2 and speed2 > 0 then return speed2 end
    return nil
end

--- Get bullet gravity scale from an ability's VData
---@param ability entity The ability entity
---@return number gravity scale (0.0 = no gravity, 1.0 = normal)
function Utils.GetAbilityGravityScale(ability)
    if not ability or not ability:valid() then return 1.0 end
    local ok, grav = pcall(function()
        return ability:get_vdata().m_WeaponInfo.m_flBulletGravityScale
    end)
    return (ok and grav) or 1.0
end

--- Get a scaled property value from an ability (reads current scaled value)
---@param ability entity The ability entity
---@param property_name string The property to read
---@return number|nil
function Utils.GetAbilityScaledProperty(ability, property_name)
    if not ability or not ability:valid() then return nil end
    local ok, val = pcall(function()
        return ability:get_scaled_property(property_name)
    end)
    return ok and val or nil
end

-- ═══════ Health ═══════

function Utils.GetHPPercent(ent)
    if not ent or not ent:valid() then return 1.0 end
    local hp     = ent.m_iHealth or 0
    local max_hp = ent:get_max_health() or 1
    if max_hp <= 0 then return 1.0 end
    return hp / max_hp
end

function Utils.GetHP(ent)
    if not ent or not ent:valid() then return 0, 0 end
    local hp     = ent.m_iHealth or 0
    local max_hp = ent:get_max_health() or 1
    return hp, max_hp
end

-- ═══════ Bones ═══════

function Utils.GetBonePos(ent, bone_name)
    if not ent or not ent:valid() then return nil end
    local ok, pos = pcall(function() return ent:get_bone_pos(bone_name) end)
    if ok and pos then return pos end
    return nil
end

function Utils.SafeBonePos(ent, primary_bone, fallback_bone)
    local pos = Utils.GetBonePos(ent, primary_bone)
    if pos then return pos end
    if fallback_bone then
        pos = Utils.GetBonePos(ent, fallback_bone)
        if pos then return pos end
    end
    if ent and ent:valid() then return ent:get_origin() end
    return nil
end

-- ═══════ Distance / Range ═══════

function Utils.Distance(a, b)
    if not a or not b then return 999999 end
    return a:Distance(b)
end

function Utils.DistanceMetres(pos_a, pos_b)
    return Utils.Distance(pos_a, pos_b) / Utils.UNIT_METER
end

function Utils.IsInRange(ent_a, ent_b, range_metres)
    if not Utils.IsValid(ent_a) or not Utils.IsValid(ent_b) then return false end
    return ent_a:get_origin():Distance(ent_b:get_origin()) <= range_metres * Utils.UNIT_METER
end

function Utils.IsInRangeUnits(ent_a, ent_b, range_units)
    if not Utils.IsValid(ent_a) or not Utils.IsValid(ent_b) then return false end
    return ent_a:get_origin():Distance(ent_b:get_origin()) <= range_units
end

-- ═══════ Camera / FOV ═══════

function Utils.GetFOVTo(pos)
    local cam_angles = utils.get_camera_angles()
    local cam_pos    = utils.get_camera_pos()
    local aim_angle  = utils.calc_angle(cam_pos, pos)
    return utils.get_fov(cam_angles, aim_angle), aim_angle
end

-- ═══════ Entity Lists ═══════

function Utils.GetPlayers()
    return entity_list.by_class_name("C_CitadelPlayerPawn")
end

function Utils.GetEnemies(pawn)
    pawn = pawn or Utils.GetLocalPawn()
    if not pawn then return {} end
    local my_team = pawn.m_iTeamNum
    local result  = {}
    for _, p in ipairs(Utils.GetPlayers()) do
        if p and p:valid() and p:is_alive() and p.m_iTeamNum ~= my_team then
            result[#result + 1] = p
        end
    end
    return result
end

function Utils.GetAllies(pawn)
    pawn = pawn or Utils.GetLocalPawn()
    if not pawn then return {} end
    local my_team   = pawn.m_iTeamNum
    local my_handle = pawn:get_handle()
    local result    = {}
    for _, p in ipairs(Utils.GetPlayers()) do
        if p and p:valid() and p:is_alive()
           and p.m_iTeamNum == my_team
           and p:get_handle() ~= my_handle then
            result[#result + 1] = p
        end
    end
    return result
end

-- ═══════ Abilities ═══════

function Utils.GetAbility(pawn, slot)
    if not pawn then return nil end
    return pawn:get_ability_by_slot(slot)
end

function Utils.IsAbilityReady(pawn, slot)
    local ability = Utils.GetAbility(pawn, slot)
    if not ability or not ability:valid() then return false, nil end
    return ability:can_be_executed() == 0, ability
end

-- ═══════ Enemy Proximity ═══════

function Utils.AnyEnemyNear(entity, enemies, dist_metres)
    if not Utils.IsValid(entity) then return false end
    local origin   = entity:get_origin()
    local max_dist = dist_metres * Utils.UNIT_METER
    for _, enemy in ipairs(enemies) do
        if enemy:valid() and enemy:is_alive() then
            if origin:Distance(enemy:get_origin()) <= max_dist then
                return true
            end
        end
    end
    return false
end

function Utils.ClosestEnemy(entity, enemies)
    if not Utils.IsValid(entity) then return nil, 999999 end
    local origin = entity:get_origin()
    local best, best_dist = nil, 999999
    for _, enemy in ipairs(enemies) do
        if enemy:valid() and enemy:is_alive() then
            local d = origin:Distance(enemy:get_origin())
            if d < best_dist then
                best_dist = d
                best = enemy
            end
        end
    end
    return best, best_dist
end

-- ═══════ Math Helpers ═══════

function Utils.Clamp(val, min_val, max_val)
    if val < min_val then return min_val end
    if val > max_val then return max_val end
    return val
end

function Utils.Lerp(a, b, t)
    return a + (b - a) * t
end

function Utils.MetresToUnits(metres)
    return metres * Utils.UNIT_METER
end

function Utils.UnitsToMetres(units)
    return units / Utils.UNIT_METER
end

-- ═══════ Self-Cast ═══════

function Utils.SelfCast(cmd, ability_button)
    cmd:add_buttonstate1(ability_button)
    cmd:add_buttonstate1(InputBitMask_t.IN_ALT_CAST)
end

return Utils
