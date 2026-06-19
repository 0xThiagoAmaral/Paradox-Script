---@diagnostic disable

local Utils = require("utils")
local TS    = require("target_selector")

local pcall      = pcall
local type       = type
local ipairs     = ipairs
local string_find  = string.find
local string_lower = string.lower
local math_max   = math.max
local math_min   = math.min

local DC = {}

DC.MYSTIC_BURST_THRESHOLD = 80
DC.TANK_BUSTER_THRESHOLD  = 165
DC.EE_PER_STACK           = 4.5
DC.EE_MAX_STACKS          = 12
DC.RESIST_MIN_MULT        = 0.05
DC.RESIST_MAX_MULT        = 2.00

local EV_TECH_POWER         = EModifierValue.MODIFIER_VALUE_TECH_POWER
local EV_TECH_POWER_PCT     = EModifierValue.MODIFIER_VALUE_TECH_POWER_PERCENT
local EV_TECH_DMG_PCT       = EModifierValue.MODIFIER_VALUE_TECH_DAMAGE_PERCENT
local EV_DMG_PCT            = EModifierValue.MODIFIER_VALUE_DAMAGE_PERCENT
local EV_TA_DMG_RESIST      = EModifierValue.MODIFIER_VALUE_TECH_ARMOR_DAMAGE_RESIST
local EV_DMG_RESIST         = EModifierValue.MODIFIER_VALUE_DAMAGE_RESIST
local EV_DMG_TAKEN_INC_PCT  = EModifierValue.MODIFIER_VALUE_DAMAGE_TAKEN_INCREASE_PERCENT
local EV_ABT_INC_PCT        = EModifierValue.MODIFIER_VALUE_ABILITY_DAMAGE_TAKEN_INCREASE_PERCENT
local EV_BASE_BULLET_DMG_PCT = EModifierValue.MODIFIER_VALUE_BASE_BULLET_DAMAGE_PERCENT
local EV_WEAPON_POWER       = EModifierValue.MODIFIER_VALUE_WEAPON_POWER

local HL_HSR = HERO_LIB and HERO_LIB.handle_spirit_resist or nil
local HL_HSB = HERO_LIB and HERO_LIB.handle_spellbreaker_reduction or nil

local function rmod(ent, ev)
    if not ent or not ent:valid() then return 0 end
    local ok, v = pcall(ent.get_sum_modifier_value, ent, ev, 0)
    return (ok and v) or 0
end

local function norm_pct(v)
    if not v or v == 0 then return 0 end
    if v > -2 and v < 2 then return v * 100.0 end
    return v
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function read_scaled(ability, key)
    if not ability or not ability:valid() then return nil end
    local ok, v = pcall(ability.get_scaled_property, ability, key)
    if ok and type(v) == "number" and v > 0 then return v end
    return nil
end

local DAMAGE_KEYS = {
    "Damage", "m_flDamage", "m_flTechDamage", "m_flImpactDamage", "m_flAreaDamage",
    "DamagePerTick", "DamagePerHit", "BaseDamage", "AbilityDamage",
    "TotalDamage", "BonusSpiritDamage", "ExplosionDamage",
}
local CURRENT_HP_KEYS    = { "CurrentHealthDamage", "CurrentHealthDamagePercentage", "BonusCurrentHealthDamagePercentage" }
local MAX_HP_KEYS        = { "MaxHealthDamage", "MaxHealthDamagePercent", "MaxHealthDamagePercentage" }
local BONUS_SPIRIT_KEYS  = { "ImbuedTechPower", "TechPower", "ActiveTechPower", "UltimateTechPower" }
local PROC_THRESHOLD_KEYS = { "MinimumDamage", "DamageThreshold", "BuildupSpiritDamageThreshold", "ProcDamageThreshold" }

local function read_first(ability, keys)
    for i = 1, #keys do
        local v = read_scaled(ability, keys[i])
        if v then return v end
    end
    return nil
end

local function read_ability_damage(ability) return read_first(ability, DAMAGE_KEYS) or 0 end

function DC.ReadCurrentHealthPct(ability) return read_first(ability, CURRENT_HP_KEYS)    or 0 end
function DC.ReadMaxHealthPct(ability)     return read_first(ability, MAX_HP_KEYS)        or 0 end
function DC.ReadBonusSpirit(ability)      return read_first(ability, BONUS_SPIRIT_KEYS)  or 0 end
function DC.ReadProcThreshold(ability)    return read_first(ability, PROC_THRESHOLD_KEYS) end

DC.HIDDEN_SPIRIT_ITEM_PATTERNS = {
    "ethereal_bullets",
    "quicksilver_reload",
    "mercurial_magnum",
}

DC.STACKED_SPIRIT_ITEMS = {
    { name_pat = "tech_overflow",       max_bonus = 40, stack_mod_pat = "techoverflow" },
    { name_pat = "spiritual_overflow",  max_bonus = 40, stack_mod_pat = "techoverflow" },
}

local function caster_has_stack_modifier(caster, pat)
    local ok, mods = pcall(caster.get_modifiers, caster)
    if not ok or not mods then return 0 end
    for i = 1, #mods do
        local m = mods[i]
        if m then
            local nok, n = pcall(m.get_class_name, m)
            if not nok or not n then nok, n = pcall(m.get_name, m) end
            if n and string_find(string_lower(n), pat, 1, true) then
                local stacks = m.m_iStackCount or m.m_nStackCount or m.m_nStacks or 0
                if type(stacks) == "number" and stacks > 0 then return stacks end
            end
        end
    end
    return 0
end

local SPIRIT_PROP_KEYS = { "TechPower", "BonusSpirit", "BonusSpiritPower", "BonusTechPower" }

local function read_item_spirit(item)
    for i = 1, #SPIRIT_PROP_KEYS do
        local ok, v = pcall(item.get_scaled_property, item, SPIRIT_PROP_KEYS[i])
        if ok and type(v) == "number" and v > 0 then return v end
    end
    return 0
end

local function sum_hidden_spirit_bonuses(caster)
    local ok, abs = pcall(caster.get_abilities, caster)
    if not ok or not abs then return 0 end
    local total = 0
    local matched_stacks = {}
    for i = 1, #abs do
        local it = abs[i]
        if it and it:valid() then
            local nok, n = pcall(it.get_name, it)
            if nok and n then
                local ln = string_lower(n)
                for _, pat in ipairs(DC.HIDDEN_SPIRIT_ITEM_PATTERNS) do
                    if string_find(ln, pat, 1, true) then
                        total = total + read_item_spirit(it)
                        break
                    end
                end
                for _, spec in ipairs(DC.STACKED_SPIRIT_ITEMS) do
                    if string_find(ln, spec.name_pat, 1, true) and not matched_stacks[spec.stack_mod_pat] then
                        matched_stacks[spec.stack_mod_pat] = true
                        local stacks = caster_has_stack_modifier(caster, spec.stack_mod_pat)
                        if stacks > 0 then
                            local item_bonus = read_item_spirit(it)
                            local cap = item_bonus > 0 and item_bonus or spec.max_bonus
                            total = total + cap * math_min(stacks, 6) / 6
                        end
                    end
                end
            end
        end
    end
    return total
end

function DC.GetSpiritPower(caster)
    if not caster or not caster:valid() then return 0 end
    local native_keys = { "get_tech_power", "get_spirit_power", "get_ability_power" }
    for i = 1, #native_keys do
        local fn = caster[native_keys[i]]
        if type(fn) == "function" then
            local ok, v = pcall(fn, caster)
            if ok and type(v) == "number" and v > 0 then return v end
        end
    end
    local flat = rmod(caster, EV_TECH_POWER) + sum_hidden_spirit_bonuses(caster)
    local pct  = rmod(caster, EV_TECH_POWER_PCT)
    return flat * (1.0 + pct / 100.0)
end

DC.ESCALATING_EXPOSURE_PER_STACK = 0.045
DC.ESCALATING_EXPOSURE_MAX_STACKS = 12

local function read_max_stacks(caster, fallback)
    local ok, abs = pcall(caster.get_abilities, caster)
    if not ok or not abs then return fallback end
    for i = 1, #abs do
        local it = abs[i]
        if it and it:valid() then
            local _, n = pcall(it.get_name, it)
            if n and string_find(string_lower(n), "escalating_exposure", 1, true) then
                local _, v = pcall(it.get_scaled_property, it, "MaxStacks")
                if type(v) == "number" and v > 0 then return v end
            end
        end
    end
    return fallback
end

function DC.GetEscalatingExposureMult(caster)
    if not caster or not caster:valid() then return 1.0 end
    local ok, mods = pcall(caster.get_modifiers, caster)
    if not ok or not mods then return 1.0 end
    local max_stacks = read_max_stacks(caster, DC.ESCALATING_EXPOSURE_MAX_STACKS)
    for i = 1, #mods do
        local m = mods[i]
        if m then
            local nok, n = pcall(m.get_class_name, m)
            if not nok or not n then nok, n = pcall(m.get_name, m) end
            if n then
                local ln = string_lower(n)
                if string_find(ln, "escalatingexposure", 1, true) or
                   string_find(ln, "escalating_exposure", 1, true) then
                    local s = m.m_iStackCount or m.m_nStackCount or m.m_nStacks or 0
                    if type(s) == "number" and s > 0 then
                        local clamped = math_min(s, max_stacks)
                        return 1.0 + clamped * DC.ESCALATING_EXPOSURE_PER_STACK
                    end
                end
            end
        end
    end
    return 1.0
end

DC.MYSTIC_VULNERABILITY_RESIST_REDUCTION = 8

function DC.HasMysticVulnerability(caster)
    if not caster or not caster:valid() then return false end
    local ok, abs = pcall(caster.get_abilities, caster)
    if not ok or not abs then return false end
    for i = 1, #abs do
        local it = abs[i]
        if it and it:valid() then
            local _, n = pcall(it.get_name, it)
            if n then
                local ln = string_lower(n)
                if string_find(ln, "mystic_vulnerability", 1, true) or
                   string_find(ln, "escalating_exposure", 1, true) then
                    return true
                end
            end
        end
    end
    return false
end

function DC.TargetHasMysticVulnerability(target)
    if not target or not target:valid() then return false end
    local ok, native = pcall(target.get_tech_resist, target)
    if ok and type(native) == "number" and native < 0 then return true end
    local mok, mods = pcall(target.get_modifiers, target)
    if not mok or not mods then return false end
    for i = 1, #mods do
        local m = mods[i]
        if m then
            local nok, n = pcall(m.get_class_name, m)
            if not nok or not n then nok, n = pcall(m.get_name, m) end
            if n then
                local ln = string_lower(n)
                if string_find(ln, "mysticvulnerability", 1, true) or
                   string_find(ln, "mystic_vulnerability", 1, true) or
                   string_find(ln, "escalatingexposure", 1, true) or
                   string_find(ln, "escalating_exposure", 1, true) then
                    return true
                end
            end
        end
    end
    return false
end

function DC.GetTechAmpMult(caster)
    local base = 1.0 + rmod(caster, EV_TECH_DMG_PCT) / 100.0
    return base * DC.GetEscalatingExposureMult(caster)
end

function DC.GetGenericOutMult(caster)
    return 1.0 + rmod(caster, EV_DMG_PCT) / 100.0
end

function DC.GetWeaponOutMult(caster)
    local pct = norm_pct(rmod(caster, EV_BASE_BULLET_DMG_PCT))
    local wp  = rmod(caster, EV_WEAPON_POWER)
    return (1.0 + pct / 100.0) * (1.0 + wp / 100.0)
end

DC.WEAPON_FINISHER_ITEMS = {
    {
        id = "glass_cannon",
        patterns = { "glass_cannon" },
        weapon_pct = "BaseAttackDamagePercent",
    },
    {
        id = "headshot_booster",
        patterns = { "headshot_booster" },
        headshot_pct = "HeadshotBonus",
    },
    {
        id = "crippling_headshot",
        patterns = { "crippling_headshot" },
        headshot_pct = "HeadshotBonus",
    },
    {
        id = "hollow_point",
        patterns = { "hollow_point" },
        low_hp_pct = "LowHealthBonusWeaponDamage",
        low_hp_thresh = "LowHealthThresholdPct",
        bonus_dmg = "BonusWeaponDamage",
    },
}

local function item_name_has_pattern(name, patterns)
    if not name or not patterns then return false end
    local ln = string_lower(name)
    for i = 1, #patterns do
        if string_find(ln, patterns[i], 1, true) then return true end
    end
    return false
end

local function read_item_prop(item, key)
    if not key then return nil end
    local ok, v = pcall(item.get_scaled_property, item, key)
    if ok and type(v) == "number" and v ~= 0 then return v end
    return nil
end

local function read_item_first(item, keys)
    if not keys then return nil end
    for i = 1, #keys do
        local v = read_item_prop(item, keys[i])
        if v then return v end
    end
    return nil
end

function DC.FindOwnedWeaponFinisher(caster, item_id)
    if not caster or not caster:valid() or not item_id then return nil end
    local spec
    for i = 1, #DC.WEAPON_FINISHER_ITEMS do
        if DC.WEAPON_FINISHER_ITEMS[i].id == item_id then
            spec = DC.WEAPON_FINISHER_ITEMS[i]
            break
        end
    end
    if not spec then return nil end

    local ok, abs = pcall(caster.get_abilities, caster)
    if not ok or not abs then return nil end
    for i = 1, #abs do
        local it = abs[i]
        if it and it:valid() then
            local nok, n = pcall(it.get_name, it)
            if nok and n and item_name_has_pattern(n, spec.patterns) then
                return it, spec
            end
        end
    end
    return nil
end

function DC.GetWeaponFinisherBonus(caster, enabled)
    local out = {
        weapon_pct = 0,
        headshot_pct = 0,
        bullet_bonus = 0,
        low_hp_thresh = 40,
        owned = {},
    }
    if not caster or not caster:valid() then return out end

    local ok, abs = pcall(caster.get_abilities, caster)
    if not ok or not abs then return out end

    for i = 1, #abs do
        local it = abs[i]
        if it and it:valid() then
            local nok, n = pcall(it.get_name, it)
            if nok and n then
                for j = 1, #DC.WEAPON_FINISHER_ITEMS do
                    local spec = DC.WEAPON_FINISHER_ITEMS[j]
                    if item_name_has_pattern(n, spec.patterns) then
                        if enabled and enabled[spec.id] == false then
                            break
                        end
                        out.owned[spec.id] = true
                        if spec.weapon_pct then
                            local v = read_item_prop(it, spec.weapon_pct)
                            if v then out.weapon_pct = out.weapon_pct + v end
                        end
                        if spec.headshot_pct then
                            local v = read_item_prop(it, spec.headshot_pct)
                            if v then out.headshot_pct = out.headshot_pct + v end
                        end
                        if spec.low_hp_thresh then
                            local v = read_item_prop(it, spec.low_hp_thresh)
                            if v then out.low_hp_thresh = v end
                        end
                        if spec.low_hp_pct or spec.bonus_dmg then
                            local keys = {}
                            if spec.low_hp_pct then keys[#keys + 1] = spec.low_hp_pct end
                            if spec.bonus_dmg then keys[#keys + 1] = spec.bonus_dmg end
                            local v = read_item_first(it, keys)
                            if v then out.bullet_bonus = out.bullet_bonus + v end
                        end
                        break
                    end
                end
            end
        end
    end

    return out
end

local function target_hp_pct(target)
    if not target or not target:valid() then return 100 end
    local hp = target.m_iHealth or 0
    local ok, mhp = pcall(target.get_max_health, target)
    if not ok or type(mhp) ~= "number" or mhp <= 0 then return 100 end
    return (hp / mhp) * 100.0
end

function DC.GetSpiritResistMult(target)
    if not target or not target:valid() then return 1.0 end
    local ok, native = pcall(target.get_tech_resist, target)
    if ok and type(native) == "number" and native ~= 0 then
        return clamp(1.0 - native / 100.0, DC.RESIST_MIN_MULT, DC.RESIST_MAX_MULT)
    end
    local tr = rmod(target, EV_TA_DMG_RESIST)
    local gr = rmod(target, EV_DMG_RESIST)
    return clamp(1.0 - (tr + gr) / 100.0, DC.RESIST_MIN_MULT, DC.RESIST_MAX_MULT)
end

function DC.GetBulletResistMult(target)
    if not target or not target:valid() then return 1.0 end
    local ok, native = pcall(target.get_bullet_resist, target)
    if ok and type(native) == "number" and native ~= 0 then
        return clamp(1.0 - native / 100.0, DC.RESIST_MIN_MULT, DC.RESIST_MAX_MULT)
    end
    if TS and TS.GetResistInfo then
        local info = TS.GetResistInfo(target)
        if info and info.bullet then
            return clamp(info.bullet, DC.RESIST_MIN_MULT, DC.RESIST_MAX_MULT)
        end
    end
    return 1.0
end

function DC.GetTakenAmpMult(target, dmg_type)
    if not target or not target:valid() then return 1.0 end
    local sum_pct = norm_pct(rmod(target, EV_DMG_TAKEN_INC_PCT))
    if dmg_type ~= "bullet" then
        sum_pct = sum_pct + norm_pct(rmod(target, EV_ABT_INC_PCT))
    end

    local ok, mods = pcall(target.get_modifiers, target)
    if ok and mods then
        for i = 1, #mods do
            local m = mods[i]
            if m then
                local nok, n = pcall(m.get_class_name, m)
                if not nok or not n then
                    nok, n = pcall(m.get_name, m)
                end
                if n and string_find(string_lower(n), "escalating_exposure", 1, true) then
                    local s = m.m_iStackCount or m.m_nStackCount or m.m_nStacks or 1
                    sum_pct = sum_pct + math_min(s, DC.EE_MAX_STACKS) * DC.EE_PER_STACK
                    break
                end
            end
        end
    end

    return math_max(0, 1.0 + sum_pct / 100.0)
end

function DC.ApplySpiritResistNative(target, raw)
    if HL_HSR then
        local ok, v = pcall(HL_HSR, target, raw)
        if ok and type(v) == "number" then return v end
    end
    return raw * DC.GetSpiritResistMult(target)
end

function DC.ApplySpellbreaker(target, dmg)
    if HL_HSB then
        local ok, v = pcall(HL_HSB, target, dmg)
        if ok and type(v) == "number" then return v end
    end
    return dmg
end

function DC.CalcRawSpiritDamage(caster, ability, opts)
    opts = opts or {}
    local base = opts.base_damage or read_ability_damage(ability)
    if base <= 0 then return 0 end

    local sp    = DC.GetSpiritPower(caster)
    local scale = opts.spirit_scaling
        or read_scaled(ability, "SpiritScaling")
        or read_scaled(ability, "AbilityScaling")
        or 0

    local raw = base + sp * scale
    if not opts.ignore_tech_amp then raw = raw * DC.GetTechAmpMult(caster) end
    return raw
end

function DC.CalcRawBulletDamage(caster, ability, opts)
    opts = opts or {}
    local base = opts.base_damage or read_ability_damage(ability)
    if base <= 0 then return 0 end

    local out = opts.ignore_out_mult and 1.0 or DC.GetGenericOutMult(caster)
    return base * out
end

function DC.ApplySpiritReductions(target, raw_dmg)
    if raw_dmg <= 0 or not target or not target:valid() then return 0 end
    local after_resist = DC.ApplySpiritResistNative(target, raw_dmg)
    local after_sb     = DC.ApplySpellbreaker(target, after_resist)
    return after_sb * DC.GetTakenAmpMult(target, "spirit")
end

function DC.ApplyBulletReductions(target, raw_dmg)
    if raw_dmg <= 0 or not target or not target:valid() then return 0 end
    return raw_dmg * DC.GetBulletResistMult(target) * DC.GetTakenAmpMult(target, "bullet")
end

local function item_off_cd(item)
    local ok, cd = pcall(item.get_cooldown, item)
    return (ok and cd or 1) <= 0
end

local function read_threshold(item, fallback)
    local ok, v = pcall(item.get_scaled_property, item, "MinimumDamage")
    if ok and type(v) == "number" and v > 0 then return v end
    return fallback
end

function DC.GetReadyBurstItems(caster)
    local out = {}
    if not caster or not caster:valid() then return out end
    local ok, abs = pcall(caster.get_abilities, caster)
    if not ok or not abs then return out end
    for i = 1, #abs do
        local it = abs[i]
        if it and it:valid() and item_off_cd(it) then
            local nok, n = pcall(it.get_name, it)
            if nok and n then
                local ln = string_lower(n)
                if string_find(ln, "magic_shock", 1, true) then
                    out[#out+1] = { item = it, name = n, kind = "tank_buster",
                                    threshold = read_threshold(it, DC.TANK_BUSTER_THRESHOLD) }
                elseif string_find(ln, "magic_burst", 1, true) then
                    out[#out+1] = { item = it, name = n, kind = "mystic_burst",
                                    threshold = read_threshold(it, DC.MYSTIC_BURST_THRESHOLD) }
                elseif string_find(ln, "spirit_burn", 1, true) then
                    out[#out+1] = { item = it, name = n, kind = "spirit_burn",
                                    threshold = 0 }
                end
            end
        end
    end
    return out
end

function DC.PredictBurstProc(caster, target, item)
    if not target or not target:valid() then return 0 end
    local base       = read_ability_damage(item)
    local item_bonus = DC.ReadBonusSpirit(item)
    local sp         = DC.GetSpiritPower(caster) + item_bonus
    local scale      = read_scaled(item, "SpiritScaling")
                    or read_scaled(item, "AbilityScaling") or 0
    local cur_pct = DC.ReadCurrentHealthPct(item)
    local mhp_pct = DC.ReadMaxHealthPct(item)

    local cur_hp = target.m_iHealth or 0
    local ok_mhp, mhp = pcall(target.get_max_health, target)
    if not ok_mhp or type(mhp) ~= "number" then mhp = 0 end

    local raw = (base + sp * scale)
              + cur_hp * cur_pct / 100.0
              + mhp    * mhp_pct / 100.0
    return DC.ApplySpiritReductions(target, raw)
end

function DC.PredictCarbineKill(caster, ability, target, opts)
    opts = opts or {}
    local props = opts.carbine_props
    if not props or not target or not target:valid() then
        return { total = 0, total_safe = 0, raw = 0, lethal = false, lethal_safe = false }
    end

    local safety = opts.safety_factor or 1.0
    if safety > 1.0 then safety = 1.0 end
    if safety < 0.0 then safety = 0.0 end

    local frac = opts.charge_frac or 1
    if frac < 0 then frac = 0 end
    if frac > 1 then frac = 1 end

    local headshot = opts.headshot ~= false
    local bonus = props.min_bonus + (props.max_bonus - props.min_bonus) * frac
    local finisher = DC.GetWeaponFinisherBonus(caster, opts.enabled_weapons)

    local hs_mult = 1.0
    if headshot then
        hs_mult = 1.0 + (props.hs_bonus or 0) + finisher.headshot_pct / 100.0
    end

    local bullet_raw = props.base_bullet * hs_mult
    if finisher.weapon_pct > 0 then
        bullet_raw = bullet_raw * (1.0 + finisher.weapon_pct / 100.0)
    end
    if finisher.bullet_bonus > 0 and target_hp_pct(target) <= (finisher.low_hp_thresh + 0.5) then
        bullet_raw = bullet_raw + finisher.bullet_bonus * hs_mult
    end
    bullet_raw = bullet_raw * DC.GetGenericOutMult(caster)

    local spirit_raw = bonus * hs_mult * DC.GetTechAmpMult(caster) * DC.GetGenericOutMult(caster)

    local bullet_dmg = DC.ApplyBulletReductions(target, bullet_raw)
    local spirit_dmg = DC.ApplySpiritReductions(target, spirit_raw)
    local main_dmg = bullet_dmg + spirit_dmg

    local burst_dmg = 0
    if not opts.no_burst then
        local items = DC.GetReadyBurstItems(caster)
        local proc_raw = spirit_raw + bullet_raw
        for i = 1, #items do
            local b = items[i]
            if proc_raw >= b.threshold then
                burst_dmg = burst_dmg + DC.PredictBurstProc(caster, target, b.item)
            end
        end
    end

    local total      = main_dmg + burst_dmg
    local total_safe = total * safety
    local pre        = opts.pre_damage or 0
    local hp         = target.m_iHealth or 0
    local shield     = target.m_iTechShield or target.m_flTechShield or 0
    if type(shield) ~= "number" then shield = 0 end
    local hp_total   = hp + shield

    return {
        total        = total,
        total_safe   = total_safe,
        raw          = bullet_raw + spirit_raw,
        bullet_raw   = bullet_raw,
        spirit_raw   = spirit_raw,
        bullet_dmg   = bullet_dmg,
        spirit_dmg   = spirit_dmg,
        burst_dmg    = burst_dmg,
        lethal       = (total      + pre) >= hp_total,
        lethal_safe  = (total_safe + pre) >= hp_total,
        finisher     = finisher,
    }
end

function DC.PredictAbilityKill(caster, ability, target, opts)
    opts = opts or {}
    local dtype  = opts.damage_type   or "spirit"
    local safety = opts.safety_factor or 1.0
    if safety > 1.0 then safety = 1.0 end
    if safety < 0.0 then safety = 0.0 end

    local raw, main_dmg
    if dtype == "bullet" then
        raw      = DC.CalcRawBulletDamage(caster, ability, opts)
        main_dmg = DC.ApplyBulletReductions(target, raw)
    else
        raw      = DC.CalcRawSpiritDamage(caster, ability, opts)
        main_dmg = DC.ApplySpiritReductions(target, raw)
    end

    local burst_dmg = 0
    if not opts.no_burst then
        local items = DC.GetReadyBurstItems(caster)
        for i = 1, #items do
            local b = items[i]
            if raw >= b.threshold then
                burst_dmg = burst_dmg + DC.PredictBurstProc(caster, target, b.item)
            end
        end
    end

    local total      = main_dmg + burst_dmg
    local total_safe = total * safety

    local pre    = opts.pre_damage or 0
    local hp     = target.m_iHealth or 0
    local shield = target.m_iTechShield or target.m_flTechShield or 0
    if type(shield) ~= "number" then shield = 0 end
    local hp_total = hp + shield

    return {
        total       = total,
        total_safe  = total_safe,
        raw         = raw,
        lethal      = (total      + pre) >= hp_total,
        lethal_safe = (total_safe + pre) >= hp_total,
    }
end

function DC.IsLethal(predicted, target, safe)
    if type(predicted) == "table" then
        return safe and predicted.lethal_safe or predicted.lethal
    end
    if not target or not target:valid() then return false end
    local hp     = target.m_iHealth or 0
    local shield = target.m_iTechShield or target.m_flTechShield or 0
    if type(shield) ~= "number" then shield = 0 end
    return predicted >= (hp + shield)
end

function DC.WouldExecute(predicted, target, exec_pct)
    if type(predicted) == "table" then predicted = predicted.total end
    exec_pct = exec_pct or 0.22
    if not target or not target:valid() then return false end
    local hp = target.m_iHealth or 0
    local ok, mhp = pcall(target.get_max_health, target)
    if not ok or type(mhp) ~= "number" then mhp = hp end
    if mhp <= 0 then return false end
    local hp_after = hp - predicted
    return hp_after > 0 and (hp_after / mhp) <= exec_pct
end

return DC
