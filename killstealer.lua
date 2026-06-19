---@diagnostic disable

local Utils = require("utils")
local DC    = require("damage_calc")
local TS    = require("target_selector")

local pcall    = pcall
local type     = type
local ipairs   = ipairs
local tostring = tostring
local mhuge    = math.huge
local entity_list_local_pawn = entity_list.local_pawn

local KS = {}

local registry          = {}
local global_enabled    = true
local global_blacklist  = {}
local last_cast_time    = 0
local CAST_COOLDOWN     = 0.10
local LETHAL_NOTIFY_TTL = 4.0
local skip_counterspell = true
local lethal_notified   = {}

function KS.Register(spec)
    assert(type(spec) == "table" and type(spec.hero_name) == "string",
           "[KS.Register] spec.hero_name required")
    assert(type(spec.abilities) == "table" and #spec.abilities > 0,
           "[KS.Register] spec.abilities must be non-empty list")
    registry[spec.hero_name] = spec
end

function KS.Unregister(hero_name)        registry[hero_name] = nil end
function KS.SetEnabled(b)                global_enabled = b and true or false end
function KS.IsEnabled()                  return global_enabled end
function KS.AddBlacklist(name)           global_blacklist[name] = true end
function KS.RemoveBlacklist(name)        global_blacklist[name] = nil end
function KS.SetCounterspellGuard(b)      skip_counterspell = b and true or false end
function KS.IsCounterspellGuarded()      return skip_counterspell end

function KS.HasReadyCounterspell(target)
    if not target or not target.valid or not target:valid() then return false end
    local ok, cs = pcall(target.get_ability, target, "upgrade_counterspell")
    if not ok or not cs or not cs.valid or not cs:valid() then return false end
    local cd_ok, cd = pcall(cs.get_cooldown, cs)
    if not cd_ok or type(cd) ~= "number" then return false end
    return cd <= 0.05
end

local function safe_call(fn, ...)
    local ok, v = pcall(fn, ...)
    return ok and v or nil
end

local function find_ability(pawn, ability_spec)
    if ability_spec.name then
        local ok, v = pcall(pawn.get_ability, pawn, ability_spec.name)
        return ok and v or nil
    end
    if ability_spec.slot ~= nil then
        local ok, v = pcall(pawn.get_ability_by_slot, pawn, ability_spec.slot)
        return ok and v or nil
    end
    return nil
end

local function ability_ready(ab, ab_spec, caster)
    if type(ab_spec.is_ready) == "function" then
        local ok, v = pcall(ab_spec.is_ready, caster, ab)
        return ok and v and true or false
    end
    if not ab or not ab:valid() then return false end
    local ok, exec = pcall(ab.can_be_executed, ab)
    return ok and exec == 0
end

local function dist_units(a, b)
    if not a or not b then return mhuge end
    return a:Distance(b)
end

local function in_cone(caster, target, cone_deg)
    if not cone_deg then return true end
    local cam_pos    = utils.get_camera_pos()
    local cam_angles = utils.get_camera_angles()
    local ok, tgt_pos = pcall(target.get_origin, target)
    if not ok or not tgt_pos then return false end
    local aim = utils.calc_angle(cam_pos, tgt_pos)
    local fov = utils.get_fov(cam_angles, aim)
    return fov <= cone_deg / 2
end

local function los_ok(caster, target, requires_los)
    if not requires_los then return true end
    local ok_c, cp = pcall(caster.get_origin, caster)
    local ok_t, tp = pcall(target.get_origin, target)
    if not ok_c or not ok_t or not cp or not tp then return false end
    local ok, hit = pcall(trace.bullet, cp, tp, 0, target)
    return ok and hit and true or false
end

function KS.Tick(cmd)
    if not global_enabled then return false end

    local lp = entity_list_local_pawn()
    if not lp or not lp:valid() or not lp:is_alive() then return false end

    local ok_h, hero = pcall(lp.get_name, lp)
    if not ok_h or not hero then return false end
    local spec = registry[hero]
    if not spec then return false end

    if type(spec.enabled) == "function" and not spec.enabled() then return false end

    local now = global_vars.curtime()
    if now - last_cast_time < CAST_COOLDOWN then return false end

    local enemies = Utils.GetEnemies(lp)
    local n_enemies = #enemies
    if n_enemies == 0 then return false end

    local lp_pos = lp:get_origin()

    local abilities = spec.abilities
    for ai = 1, #abilities do
        local ab_spec = abilities[ai]
        local ab = find_ability(lp, ab_spec)
        if ab and ability_ready(ab, ab_spec, lp) then
            local range_units = (ab_spec.range_m or 999) * Utils.UNIT_METER
            local dmg_opts    = ab_spec.opts or {}
            dmg_opts.damage_type   = ab_spec.damage_type or dmg_opts.damage_type or "spirit"
            dmg_opts.safety_factor = ab_spec.safety_factor or 0.92
            local cone_deg = ab_spec.cone_deg
            local req_los  = ab_spec.requires_los
            local filter_fn = type(ab_spec.filter) == "function" and ab_spec.filter or nil
            local lethal_fn = type(ab_spec.lethal_check) == "function" and ab_spec.lethal_check or nil

            for ei = 1, n_enemies do
                local e = enemies[ei]
                local proceed = Utils.IsAlive(e) and not Utils.IsWastedTarget(e)

                if proceed then
                    local ok_n, enemy_hero = pcall(e.get_name, e)
                    if ok_n and enemy_hero and global_blacklist[enemy_hero] then
                        proceed = false
                    end
                end

                if proceed and skip_counterspell and KS.HasReadyCounterspell(e) then
                    proceed = false
                end

                if proceed then
                    local ok_p, ep = pcall(e.get_origin, e)
                    if not ok_p or not ep or dist_units(lp_pos, ep) > range_units then
                        proceed = false
                    end
                end

                if proceed and cone_deg and not in_cone(lp, e, cone_deg) then
                    proceed = false
                end

                if proceed and req_los and not los_ok(lp, e, true) then
                    proceed = false
                end

                if proceed and filter_fn then
                    local ok_f, allow = pcall(filter_fn, lp, ab, e)
                    if not ok_f or not allow then proceed = false end
                end

                if proceed then
                    local r = DC.PredictAbilityKill(lp, ab, e, dmg_opts)
                    local force_lethal = false
                    if lethal_fn then
                        local ok_l, v = pcall(lethal_fn, lp, ab, e, r)
                        force_lethal = ok_l and v and true or false
                    end
                    if r.lethal_safe or force_lethal then
                        if type(spec.on_lethal_detected) == "function" then
                            local th = safe_call(e.get_handle, e) or 0
                            local hp = e.m_iHealth or 0
                            local ab_key = ab_spec.name or ("slot" .. tostring(ab_spec.slot))
                            local key = hero .. "|" .. ab_key .. "|" .. tostring(th)
                            local last = lethal_notified[key]
                            if (not last) or (now - last.time >= LETHAL_NOTIFY_TTL)
                               or (last.hp ~= hp) then
                                lethal_notified[key] = { time = now, hp = hp }
                                pcall(spec.on_lethal_detected, lp, ab, e, r)
                            end
                        end

                        if type(ab_spec.prepare) == "function" then
                            pcall(ab_spec.prepare, cmd, lp, ab, e)
                        end
                        local ok_c = pcall(ab_spec.cast, cmd, lp, ab, e)
                        if ok_c then
                            last_cast_time = now
                            if type(ab_spec.post_cast) == "function" then
                                pcall(ab_spec.post_cast, cmd, lp, ab, e)
                            end
                            if spec.on_killsteal then
                                pcall(spec.on_killsteal, lp, ab, e, r)
                            end
                            return true
                        end
                    end
                end
            end
        end
    end

    return false
end

function KS.GetLethalCandidates()
    local out = {}
    if not global_enabled then return out end

    local lp = entity_list_local_pawn()
    if not lp or not lp:valid() or not lp:is_alive() then return out end
    local ok_h, hero = pcall(lp.get_name, lp)
    if not ok_h then return out end
    local spec = registry[hero]
    if not spec then return out end

    local enemies = Utils.GetEnemies(lp)
    local lp_pos  = lp:get_origin()

    local abilities = spec.abilities
    for ai = 1, #abilities do
        local ab_spec = abilities[ai]
        local ab = find_ability(lp, ab_spec)
        if ab and ability_ready(ab, ab_spec, lp) then
            local range_units = (ab_spec.range_m or 999) * Utils.UNIT_METER
            local dmg_opts    = ab_spec.opts or {}
            dmg_opts.damage_type   = ab_spec.damage_type or dmg_opts.damage_type or "spirit"
            dmg_opts.safety_factor = ab_spec.safety_factor or 0.92

            for ei = 1, #enemies do
                local e = enemies[ei]
                local skip_cs = skip_counterspell and KS.HasReadyCounterspell(e)
                if Utils.IsAlive(e) and not Utils.IsWastedTarget(e) and not skip_cs then
                    local ok_p, ep = pcall(e.get_origin, e)
                    if ok_p and ep and dist_units(lp_pos, ep) <= range_units then
                        local r = DC.PredictAbilityKill(lp, ab, e, dmg_opts)
                        if r.lethal_safe then
                            out[#out+1] = {
                                ability     = ab_spec.name or ("slot " .. tostring(ab_spec.slot)),
                                target      = e,
                                target_name = safe_call(e.get_name, e) or "?",
                                hp          = e.m_iHealth or 0,
                                pred        = r.total,
                                pred_safe   = r.total_safe,
                            }
                        end
                    end
                end
            end
        end
    end
    return out
end

return KS
