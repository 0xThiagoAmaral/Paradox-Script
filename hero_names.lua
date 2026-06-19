---@diagnostic disable
-- hero_names.lua — internal hero name → display name resolver.
--
-- Strategy:
--   1. Cache lookup (per-internal-name).
--   2. GameLocalizer.Find with multiple Source 2 token conventions.
--   3. Static NAMES table fallback (kept for known heroes — survives
--      localization gaps and works offline / without VPK).
--   4. Heuristic fallback: strip "hero_" prefix, uppercase first char.
--
-- Backward-compatible API:
--   M.Get(internal)             — returns best display name (string)
--   M.GetFromEntity(ent)        — resolves through entity name / vdata class
--   M.NAMES                     — static fallback table (unchanged)
--
-- New helpers:
--   M.GetLocalized(internal)    — explicit GameLocalizer try (no static fallback)
--   M.GetLocalizedRaw(token)    — direct token query, returns "" on miss
--   M.ResetCache()              — clear resolution cache (call after locale change)
--   M.ListKnown()               — array of all internal names from NAMES

local M = {}

-- ═══════ Static fallback (kept in sync manually for known heroes) ═══════
local NAMES = {
    hero_atlas       = "Abrams",
    hero_bull        = "Abrams",
    hero_astro       = "Holliday",
    hero_bebop       = "Bebop",
    hero_bookworm    = "Paige",
    hero_celestial   = "Celeste",
    hero_chrono      = "Paradox",
    hero_digger      = "Viscous",
    hero_doorman     = "Doorman",
    hero_drifter     = "Drifter",
    hero_dynamo      = "Dynamo",
    hero_familiar    = "Rem",
    hero_fathom      = "Fathom",
    hero_fencer      = "Fencer",
    hero_forge       = "Forge",
    hero_frank       = "Victor",
    hero_ghost       = "Lady Geist",
    hero_gigawatt    = "Seven",
    hero_gunslinger  = "Gunslinger",
    hero_haze        = "Haze",
    hero_hornet      = "Vindicta",
    hero_inferno     = "Infernus",
    hero_ivy         = "Ivy",
    hero_kali        = "Shiv",
    hero_kelvin      = "Kelvin",
    hero_krill       = "Mo & Krill",
    hero_lash        = "Lash",
    hero_magician    = "Sinclair",
    hero_mcginnis    = "McGinnis",
    hero_mina        = "Mina",
    hero_mirage      = "Mirage",
    hero_nano        = "Calico",
    hero_orion       = "Grey Talon",
    hero_priest      = "Venator",
    hero_punkgoat    = "Billy",
    hero_rutger      = "Holliday",
    hero_shiv        = "Shiv",
    hero_shrike      = "Shrike",
    hero_slork       = "Slork",
    hero_synth       = "Pocket",
    hero_targetdummy = "Dummy",
    hero_tengu       = "Ivy",
    hero_vampirebat  = "Mina",
    hero_viper       = "Vyper",
    hero_viscous     = "Viscous",
    hero_warden      = "Warden",
    hero_werewolf    = "Werewolf",
    hero_wraith      = "Wraith",
    hero_wrecker     = "Wrecker",
    hero_yakuza      = "Yamato",
    hero_yamato      = "Yamato",
}

-- ═══════ Resolution cache ═══════
-- key: internal name, value: resolved display name (string).
-- Cleared via M.ResetCache(). Cache is small (<100 entries) so no LRU needed.
local cache = {}

-- ═══════ Token format candidates ═══════
-- Source 2 builds vary in localization token convention. Try each in order
-- until GameLocalizer returns a non-empty string.
local function build_token_candidates(internal)
    local stripped = internal:gsub("^hero_", "")
    local capitalized = stripped:sub(1, 1):upper() .. stripped:sub(2)
    return {
        "#" .. internal,                          -- "#hero_atlas"
        "#" .. internal .. "_name",               -- "#hero_atlas_name"
        "#Citadel_Hero_" .. capitalized,          -- "#Citadel_Hero_Atlas"
        "#citadel_hero_" .. stripped,             -- "#citadel_hero_atlas"
        "#Hero_" .. capitalized,                  -- "#Hero_Atlas"
        "#hero_" .. stripped .. "_name",          -- "#hero_atlas_name"
    }
end

-- Direct GameLocalizer query (no caching, no fallback). Returns localized string
-- or empty string if token not found. Wrapped in pcall — GameLocalizer may not
-- exist in some Umbrella builds.
function M.GetLocalizedRaw(token)
    if not token or token == "" then return "" end
    if not _G.GameLocalizer or type(GameLocalizer.Find) ~= "function" then return "" end
    local ok, val = pcall(GameLocalizer.Find, token)
    if not ok or type(val) ~= "string" then return "" end
    return val
end

-- Try every token candidate. Returns first non-empty result, or "" if none hit.
function M.GetLocalized(internal)
    if not internal or internal == "" then return "" end
    for _, tok in ipairs(build_token_candidates(internal)) do
        local v = M.GetLocalizedRaw(tok)
        if v and v ~= "" then return v end
    end
    return ""
end

-- Heuristic fallback: "hero_someName" → "SomeName"
local function heuristic(internal)
    local stripped = internal:gsub("^hero_", "")
    if stripped == "" then return internal end
    return stripped:sub(1, 1):upper() .. stripped:sub(2)
end

-- ═══════ Public resolver ═══════
function M.Get(internal)
    if not internal or internal == "" then return "?" end
    local cached = cache[internal]
    if cached then return cached end

    -- Try GameLocalizer first (always-fresh from game data on patches)
    local loc = M.GetLocalized(internal)
    if loc ~= "" then
        cache[internal] = loc
        return loc
    end

    -- Static fallback
    local mapped = NAMES[internal]
    if mapped then
        cache[internal] = mapped
        return mapped
    end

    -- Heuristic
    local h = heuristic(internal)
    cache[internal] = h
    return h
end

function M.GetFromEntity(ent)
    if not ent or not ent:valid() then return "?" end
    local ok, n = pcall(ent.get_name, ent)
    if ok and n and n ~= "" then return M.Get(n) end
    local ok2, vd = pcall(ent.get_vdata_class_name, ent)
    if ok2 and vd then
        local match = vd:match("(hero_%w+)")
        if match then return M.Get(match) end
    end
    return "?"
end

-- ═══════ Cache management ═══════
function M.ResetCache()
    cache = {}
end

-- Returns array of all known internal names (from static NAMES).
function M.ListKnown()
    local arr = {}
    for k, _ in pairs(NAMES) do arr[#arr + 1] = k end
    table.sort(arr)
    return arr
end

M.NAMES = NAMES

return M
