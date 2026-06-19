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
if not Utils then
    error("[libs.target_selector] failed to load utils module")
end

local TS = {}

-- Priority modes
TS.PRIORITY_CROSSHAIR  = 0
TS.PRIORITY_DISTANCE   = 1
TS.PRIORITY_LOWEST_HP  = 2
TS.PRIORITY_HIGHEST_HP = 3

-- ═══════ Filtered Enemy List ═══════

function TS.GetEnemies(config)
    config = config or {}
    local pawn = config.pawn or Utils.GetLocalPawn()
    if not pawn then return {} end

    local my_team         = pawn.m_iTeamNum
    local my_origin       = pawn:get_origin()
    local max_range       = config.range and (config.range * Utils.UNIT_METER) or nil
    local require_visible = config.require_visible ~= false
    local skip_wasted     = config.skip_wasted or false       -- Skip parrying/invulnerable targets
    local heroes_only     = config.heroes_only ~= false       -- Exclude towers/minions (default true)
    local filter_fn       = config.filter

    local result = {}
    for _, p in ipairs(Utils.GetPlayers()) do
        if p and p:valid() and p:is_alive() and p.m_iTeamNum ~= my_team then
            if not heroes_only or Utils.IsHero(p) then
                if not require_visible or p:is_visible() then
                    if not max_range or my_origin:Distance(p:get_origin()) <= max_range then
                        if not skip_wasted or not Utils.IsWastedTarget(p) then
                            if not filter_fn or filter_fn(p) then
                                result[#result + 1] = p
                            end
                        end
                    end
                end
            end
        end
    end
    return result
end

-- ═══════ Priority-Based Target Selection ═══════

function TS.GetBestEnemy(config)
    config = config or {}
    local pawn = config.pawn or Utils.GetLocalPawn()
    if not pawn then return nil end

    local priority        = config.priority or TS.PRIORITY_CROSSHAIR
    local fov_limit       = config.fov or 180
    local range_units     = (config.range or 100) * Utils.UNIT_METER
    local require_visible = config.require_visible ~= false
    local skip_wasted     = config.skip_wasted or false
    local filter_fn       = config.filter

    local my_origin = pawn:get_origin()
    local my_team   = pawn.m_iTeamNum
    local candidates = {}

    for _, enemy in ipairs(Utils.GetPlayers()) do
        if enemy and enemy:valid() and enemy:is_alive() and enemy.m_iTeamNum ~= my_team then
            if not require_visible or enemy:is_visible() then
                if not skip_wasted or not Utils.IsWastedTarget(enemy) then
                    local pos  = enemy:get_origin()
                    local dist = my_origin:Distance(pos)

                    if dist <= range_units then
                        local fov = Utils.GetFOVTo(pos)

                        if fov <= fov_limit then
                            if not filter_fn or filter_fn(enemy) then
                                candidates[#candidates + 1] = {
                                    entity = enemy,
                                    dist   = dist,
                                    fov    = fov,
                                    hp_pct = Utils.GetHPPercent(enemy),
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    if #candidates == 0 then return nil end

    if priority == TS.PRIORITY_CROSSHAIR then
        table.sort(candidates, function(a, b) return a.fov < b.fov end)
    elseif priority == TS.PRIORITY_DISTANCE then
        table.sort(candidates, function(a, b) return a.dist < b.dist end)
    elseif priority == TS.PRIORITY_LOWEST_HP then
        table.sort(candidates, function(a, b) return a.hp_pct < b.hp_pct end)
    elseif priority == TS.PRIORITY_HIGHEST_HP then
        table.sort(candidates, function(a, b) return a.hp_pct > b.hp_pct end)
    end

    if config.return_info then
        return candidates[1]
    end
    return candidates[1].entity
end

-- ═══════ Cone Scanning ═══════

function TS.CountEnemiesInCone(config)
    config = config or {}
    local pawn = config.pawn or Utils.GetLocalPawn()
    if not pawn then return 0, {} end

    local range     = (config.range or 25) * Utils.UNIT_METER
    local cone_fov  = config.cone_fov or 60
    local my_origin = pawn:get_origin()
    local cam_pos   = utils.get_camera_pos()
    local cam_angles = utils.get_camera_angles()

    local count   = 0
    local in_cone = {}

    for _, enemy in ipairs(Utils.GetEnemies(pawn)) do
        local pos  = enemy:get_origin()
        local dist = my_origin:Distance(pos)

        if dist <= range then
            local aim_angle = utils.calc_angle(cam_pos, pos)
            local fov       = utils.get_fov(cam_angles, aim_angle)

            if fov <= cone_fov / 2 then
                count = count + 1
                in_cone[#in_cone + 1] = enemy
            end
        end
    end

    return count, in_cone
end

-- ═══════ Damage / Resistance Info ═══════

function TS.GetSpiritPower(ent)
    if not Utils.IsValid(ent) then return 0 end
    local ok, val = pcall(function()
        return ent:get_modifier_value(EModifierValue.MODIFIER_VALUE_TECH_POWER, 0)
    end)
    return (ok and val) or 0
end

function TS.GetResistInfo(ent)
    if not Utils.IsValid(ent) then return { bullet = 1.0, spirit = 1.0 } end
    local info = { bullet = 1.0, spirit = 1.0 }

    -- MODIFIER_VALUE_*_ARMOR_DAMAGE_PERCENT returns the damage multiplier
    -- after armor as a percentage (e.g. 75 = you deal 75% dmg = 25% resist).
    -- A value in 0-2 range is already a fraction; >2 is a percentage.
    local function parse_resist(v)
        if not v then return 1.0 end
        if v > 2.0 then
            return math.max(v / 100.0, 0.01)   -- percentage → fraction
        elseif v > 0 then
            return math.max(v, 0.01)            -- already a fraction
        end
        return 1.0  -- 0 or negative = no resist / error
    end

    pcall(function()
        local v = ent:get_modifier_value(EModifierValue.MODIFIER_VALUE_BULLET_ARMOR_DAMAGE_PERCENT, 0)
        info.bullet = parse_resist(v)
    end)

    pcall(function()
        local v = ent:get_modifier_value(EModifierValue.MODIFIER_VALUE_TECH_ARMOR_DAMAGE_PERCENT, 0)
        info.spirit = parse_resist(v)
    end)

    return info
end

function TS.GetEffectiveHP(ent, damage_type)
    if not Utils.IsValid(ent) then return 0 end
    local hp     = ent.m_iHealth or 0
    local resist = TS.GetResistInfo(ent)

    -- resist.bullet/spirit is the damage multiplier (e.g. 0.75 = 75% damage gets through)
    -- effective HP = hp / multiplier (takes MORE raw damage to kill if they have resist)
    if damage_type == "bullet" then
        return hp / math.max(resist.bullet, 0.01)
    elseif damage_type == "spirit" then
        return hp / math.max(resist.spirit, 0.01)
    end
    return hp
end

-- ═══════ Raw Armor Values ═══════
-- Reads actual armor numbers (useful for UI display or advanced calculations)

function TS.GetBulletArmor(ent)
    if not Utils.IsValid(ent) then return 0 end
    local ok, val = pcall(function()
        return ent:get_modifier_value(EModifierValue.MODIFIER_VALUE_BULLET_ARMOR, 0)
    end)
    return (ok and val) or 0
end

function TS.GetSpiritArmor(ent)
    if not Utils.IsValid(ent) then return 0 end
    local ok, val = pcall(function()
        return ent:get_modifier_value(EModifierValue.MODIFIER_VALUE_TECH_ARMOR, 0)
    end)
    return (ok and val) or 0
end

-- ═══════ Target Viability Check ═══════
-- Quick check: is this target worth spending an ability on?
-- Returns false for parrying, invulnerable, intangible, or dead targets.

function TS.IsTargetDamageable(ent)
    if not Utils.IsAlive(ent) then return false end
    return not Utils.IsWastedTarget(ent)
end

-- ═══════ CC State Check ═══════
-- Returns true if target is CC'd (stunned, immobilized) — good time to land skillshots

function TS.IsTargetCCd(ent)
    if not Utils.IsValid(ent) then return false end
    return Utils.IsStunned(ent) or Utils.IsImmobilized(ent)
end

return TS
