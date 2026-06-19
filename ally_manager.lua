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
    error("[libs.ally_manager] failed to load utils module")
end

local AM = {}

-- ═══════ Basic Ally Access ═══════

function AM.GetAllies(pawn)
    return Utils.GetAllies(pawn)
end

-- ═══════ Lowest HP Ally ═══════

function AM.GetLowestHPAlly(config)
    config = config or {}
    local pawn = config.pawn or Utils.GetLocalPawn()
    if not pawn then return nil, 1.0 end

    local range     = (config.range or 50) * Utils.UNIT_METER
    local threshold = config.hp_threshold or 1.0
    local my_origin = pawn:get_origin()

    local best, best_hp = nil, threshold
    for _, ally in ipairs(Utils.GetAllies(pawn)) do
        local dist = my_origin:Distance(ally:get_origin())
        if dist <= range then
            local hp_pct = Utils.GetHPPercent(ally)
            if hp_pct < best_hp then
                best_hp = hp_pct
                best    = ally
            end
        end
    end
    return best, best_hp
end

-- ═══════ Danger Detection ═══════

function AM.IsInDanger(ally, config)
    config = config or {}
    if not Utils.IsAlive(ally) then return false, "dead", 0 end

    local hp_threshold = (config.hp_threshold or 40) / 100.0
    local enemy_prox   = (config.enemy_proximity or 12) * Utils.UNIT_METER
    local enemies      = config.enemies or Utils.GetEnemies()

    local hp_pct = Utils.GetHPPercent(ally)

    -- CC'd allies are in immediate danger regardless of HP
    if Utils.IsStunned(ally) then
        return true, "stunned", hp_pct
    end

    if hp_pct < hp_threshold then
        return true, "low_hp", hp_pct
    end

    local origin = ally:get_origin()
    for _, enemy in ipairs(enemies) do
        if enemy:valid() and enemy:is_alive() then
            if origin:Distance(enemy:get_origin()) <= enemy_prox then
                return true, "enemy_near", hp_pct
            end
        end
    end

    return false, "safe", hp_pct
end

-- ═══════ Best Save Target ═══════

function AM.GetBestSaveTarget(config)
    config = config or {}
    local pawn = config.pawn or Utils.GetLocalPawn()
    if not pawn then return nil end

    local range       = (config.range or 30) * Utils.UNIT_METER
    local hp_threshold = config.hp_threshold or 40
    local enemy_prox   = config.enemy_proximity or 12
    local enemies      = config.enemies or Utils.GetEnemies(pawn)
    local my_origin    = pawn:get_origin()

    local best, best_score = nil, -1
    for _, ally in ipairs(Utils.GetAllies(pawn)) do
        local dist = my_origin:Distance(ally:get_origin())
        if dist <= range then
            local in_danger, reason, hp_pct = AM.IsInDanger(ally, {
                hp_threshold    = hp_threshold,
                enemy_proximity = enemy_prox,
                enemies         = enemies,
            })
            if in_danger then
                local score = (1.0 - hp_pct) * 100
                if reason == "low_hp" then score = score + 20 end
                if reason == "stunned" then score = score + 40 end  -- Stunned allies are highest priority
                score = score + (1.0 - dist / range) * 10
                if score > best_score then
                    best_score = score
                    best       = ally
                end
            end
        end
    end
    return best
end

-- ═══════ Shield Target Selection ═══════
-- Returns: target, is_self_cast, reason

function AM.GetShieldTarget(config)
    config = config or {}
    local pawn = config.pawn or Utils.GetLocalPawn()
    if not pawn then return nil, false, "" end

    local self_hp_thresh = (config.self_hp_threshold or 50) / 100.0
    local self_prox      = (config.self_enemy_proximity or 10) * Utils.UNIT_METER
    local ally_hp_thresh = (config.ally_hp_threshold or 40) / 100.0
    local ally_prox      = (config.ally_enemy_proximity or 12) * Utils.UNIT_METER
    local ally_range     = (config.ally_range or 30) * Utils.UNIT_METER
    local priority       = config.priority or "self_first"
    local enemies        = config.enemies or Utils.GetEnemies(pawn)

    local my_hp     = Utils.GetHPPercent(pawn)
    local my_origin = pawn:get_origin()

    -- Check self
    local self_needs = false
    if my_hp < self_hp_thresh then
        self_needs = true
    end
    if not self_needs then
        for _, enemy in ipairs(enemies) do
            if enemy:valid() and enemy:is_alive()
               and my_origin:Distance(enemy:get_origin()) <= self_prox then
                self_needs = true
                break
            end
        end
    end

    -- Find best ally
    local best_ally, best_score = nil, -1
    for _, ally in ipairs(Utils.GetAllies(pawn)) do
        if ally:valid() and ally:is_alive() then
            local dist = my_origin:Distance(ally:get_origin())
            if dist <= ally_range then
                local ally_hp = Utils.GetHPPercent(ally)
                local needs, score = false, 0

                if ally_hp < ally_hp_thresh then
                    needs = true
                    score = (1.0 - ally_hp) * 100
                end
                if not needs then
                    local a_origin = ally:get_origin()
                    for _, enemy in ipairs(enemies) do
                        if enemy:valid() and enemy:is_alive()
                           and a_origin:Distance(enemy:get_origin()) <= ally_prox then
                            needs = true
                            score = 30
                            break
                        end
                    end
                end
                if needs and score > best_score then
                    best_score = score
                    best_ally  = ally
                end
            end
        end
    end

    -- Decide based on priority
    if priority == "self_first" then
        if self_needs then return pawn, true, "self" end
        if best_ally then return best_ally, false, "ally" end
    elseif priority == "ally_first" then
        if best_ally then return best_ally, false, "ally" end
        if self_needs then return pawn, true, "self" end
    else -- lowest_hp
        local self_score = self_needs and ((1.0 - my_hp) * 100) or -1
        if best_ally and best_score > self_score then
            return best_ally, false, "ally"
        elseif self_needs then
            return pawn, true, "self"
        end
    end

    return nil, false, ""
end

-- ═══════ Prioritized Ally List ═══════

function AM.PrioritizeAllies(config)
    config = config or {}
    local pawn = config.pawn or Utils.GetLocalPawn()
    if not pawn then return {} end

    local range     = (config.range or 50) * Utils.UNIT_METER
    local enemies   = config.enemies or Utils.GetEnemies(pawn)
    local my_origin = pawn:get_origin()

    local scored = {}
    for _, ally in ipairs(Utils.GetAllies(pawn)) do
        local dist = my_origin:Distance(ally:get_origin())
        if dist <= range then
            local hp_pct    = Utils.GetHPPercent(ally)
            local in_danger = AM.IsInDanger(ally, { enemies = enemies })
            local score     = (1.0 - hp_pct) * 100
            if in_danger then score = score + 50 end
            score = score + (1.0 - dist / range) * 10

            scored[#scored + 1] = {
                ally      = ally,
                score     = score,
                hp_pct    = hp_pct,
                dist      = dist,
                in_danger = in_danger,
            }
        end
    end

    table.sort(scored, function(a, b) return a.score > b.score end)
    return scored
end

-- ═══════ Ally State Checks ═══════
-- Quick checks for ally conditions using modifier states

function AM.IsAllyStunned(ally)
    return Utils.IsStunned(ally)
end

function AM.IsAllyUlting(ally)
    return Utils.IsUlting(ally)
end

--- Returns true if ally is in an un-helpable state (invulnerable/intangible)
--- — no need to shield or heal them
function AM.IsAllyProtected(ally)
    return Utils.IsInvulnerable(ally)
        or Utils.HasModifierState(ally, Utils.ModifierState.INTANGIBLE)
end

--- Count allies in danger within range (useful for AoE heal/shield decisions)
---@param config table { pawn, range, hp_threshold, enemy_proximity, enemies }
---@return number count
---@return table[] danger_allies  Array of { ally, reason, hp_pct }
function AM.CountAlliesInDanger(config)
    config = config or {}
    local pawn = config.pawn or Utils.GetLocalPawn()
    if not pawn then return 0, {} end

    local range   = (config.range or 30) * Utils.UNIT_METER
    local enemies = config.enemies or Utils.GetEnemies(pawn)
    local my_origin = pawn:get_origin()

    local count = 0
    local danger_allies = {}

    for _, ally in ipairs(Utils.GetAllies(pawn)) do
        local dist = my_origin:Distance(ally:get_origin())
        if dist <= range then
            local in_danger, reason, hp_pct = AM.IsInDanger(ally, {
                hp_threshold    = config.hp_threshold or 40,
                enemy_proximity = config.enemy_proximity or 12,
                enemies         = enemies,
            })
            if in_danger and not AM.IsAllyProtected(ally) then
                count = count + 1
                danger_allies[#danger_allies + 1] = {
                    ally   = ally,
                    reason = reason,
                    hp_pct = hp_pct,
                }
            end
        end
    end

    return count, danger_allies
end

return AM
