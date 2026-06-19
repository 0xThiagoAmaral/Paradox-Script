-- Paradox Build Guide — shop priorities synced with combo / assists / auto defense
ParadoxBuild = ParadoxBuild or {}

local PRIORITY = { CORE = 1, REC = 2, OPT = 3 }
local RANK = { S = 1, A = 2, B = 3, C = 4 }

local PRI_LABEL = {
    [PRIORITY.CORE] = "[Core]",
    [PRIORITY.REC]  = "[Rec]",
    [PRIORITY.OPT]  = "[Opt]",
}

local RANK_LABEL = {
    [RANK.S] = "S",
    [RANK.A] = "A",
    [RANK.B] = "B",
    [RANK.C] = "C",
}

local BUILD = {
    overview = {
        "HUD default: Final 12 Slots — your end-game inventory checklist.",
        "Buy Order = purchase timeline; Sell When Full = replace priority.",
        "Spirit combo: Q at feet -> Wall -> Swap -> items -> Carbine headshot.",
        "Enable combo actives + Glass Cannon / Headshot Booster in Combo Items.",
        "Max 2 saves (Dispel + Healing Rite). Sell extras when slots fill.",
    },

    final_12 = {
        { slot = 1,  name = "Mystic Burst",         tier = "T1", role = "combo",  priority = PRIORITY.CORE, rank = RANK.S,
          script = "Combo Items -> passive proc", why = "Spirit burst on Carbine — killsteal." },
        { slot = 2,  name = "Mystic Vulnerability", tier = "T2", role = "combo",  priority = PRIORITY.CORE, rank = RANK.A,
          script = "Combo Items -> post-Swap", why = "Spirit resist shred before CC." },
        { slot = 3,  name = "Silence Wave",         tier = "T3", role = "combo",  priority = PRIORITY.CORE, rank = RANK.S,
          script = "Combo Items -> post-Swap", why = "Anti-escape after Swap." },
        { slot = 4,  name = "Knockdown",            tier = "T3", role = "combo",  priority = PRIORITY.CORE, rank = RANK.S,
          script = "Combo Items -> on grenade", why = "Locks target in grenade." },
        { slot = 5,  name = "Tankbuster",         tier = "T3", role = "combo",  priority = PRIORITY.REC, rank = RANK.S,
          script = "Combo Items -> passive", why = "Proc vs high-HP on Carbine." },
        { slot = 6,  name = "Spirit Burn",          tier = "T4", role = "combo",  priority = PRIORITY.REC, rank = RANK.A,
          script = "Combo Items -> passive", why = "DoT after big Carbine hit." },
        { slot = 7,  name = "Infuser",              tier = "T4", role = "combo",  priority = PRIORITY.CORE, rank = RANK.S,
          script = "Combo Items -> pre-Carbine", why = "Spirit spike before headshot." },
        { slot = 8,  name = "Mystic Reverb",        tier = "T4", role = "combo",  priority = PRIORITY.REC, rank = RANK.B,
          script = "Manual imbue on Carbine", why = "AoE slow after imbued shot." },
        { slot = 9,  name = "Glass Cannon",         tier = "T4", role = "weapon", priority = PRIORITY.REC, rank = RANK.A,
          script = "Combo Items -> Include in Killsteal", why = "+80% weapon dmg — max Carbine finisher." },
        { slot = 10, name = "Dispel Magic",         tier = "T3", role = "save",   priority = PRIORITY.CORE, rank = RANK.A,
          script = "Auto Defense -> cleanse", why = "Self-cleanse under CC." },
        { slot = 11, name = "Healing Rite",         tier = "T1", role = "save",   priority = PRIORITY.REC, rank = RANK.A,
          script = "Auto Defense -> low HP", why = "Cheap heal after swap-in." },
        { slot = 12, name = "Headshot Booster",     tier = "T1", role = "weapon", priority = PRIORITY.REC, rank = RANK.B,
          script = "Combo Items -> Include in Killsteal", why = "Headshot amp stacks with Glass Cannon." },
    },

    progression = {
        { step = 1,  name = "Mystic Burst",         tier = "T1", priority = PRIORITY.CORE, rank = RANK.S,
          script = "Step 1 — first buy", why = "Cheapest spirit proc for Carbine." },
        { step = 2,  name = "Healing Rite",         tier = "T1", priority = PRIORITY.REC, rank = RANK.A,
          script = "Step 2", why = "Lane save — stays in final 12." },
        { step = 3,  name = "Headshot Booster",     tier = "T1", priority = PRIORITY.REC, rank = RANK.B,
          script = "Step 3", why = "Early headshot amp — stays in final 12." },
        { step = 4,  name = "Mystic Vulnerability", tier = "T2", priority = PRIORITY.CORE, rank = RANK.A,
          script = "Step 4", why = "Post-swap debuff — core combo." },
        { step = 5,  name = "Silence Wave",         tier = "T3", priority = PRIORITY.CORE, rank = RANK.S,
          script = "Step 5", why = "Silence after Swap." },
        { step = 6,  name = "Knockdown",            tier = "T3", priority = PRIORITY.CORE, rank = RANK.S,
          script = "Step 6", why = "Grenade lockdown." },
        { step = 7,  name = "Dispel Magic",         tier = "T3", priority = PRIORITY.REC, rank = RANK.A,
          script = "Step 7", why = "Save slot — stays in final 12." },
        { step = 8,  name = "Tankbuster",           tier = "T3", priority = PRIORITY.REC, rank = RANK.S,
          script = "Step 8", why = "Passive burst proc." },
        { step = 9,  name = "Spirit Burn",          tier = "T4", priority = PRIORITY.REC, rank = RANK.A,
          script = "Step 9 — sell temp items if full", why = "See Sell When Full HUD." },
        { step = 10, name = "Infuser",              tier = "T4", priority = PRIORITY.CORE, rank = RANK.S,
          script = "Step 10 — priority late buy", why = "Required for combo finisher." },
        { step = 11, name = "Mystic Reverb",        tier = "T4", priority = PRIORITY.REC, rank = RANK.B,
          script = "Step 11 — imbue Carbine", why = "Manual imbue before charged shot." },
        { step = 12, name = "Glass Cannon",         tier = "T4", priority = PRIORITY.REC, rank = RANK.A,
          script = "Step 12 — last slot", why = "Max weapon finisher; sell Headhunter first." },
    },

    replacements = {
        { order = 1, name = "Reactive Barrier",  priority = PRIORITY.OPT, rank = RANK.C,
          why = "Temp early save — sell first when slots full." },
        { order = 2, name = "Weapon Shielding",  priority = PRIORITY.OPT, rank = RANK.C,
          why = "Redundant with Dispel + Healing Rite." },
        { order = 3, name = "Headhunter",        priority = PRIORITY.OPT, rank = RANK.C,
          why = "Not in final build — replace with Glass Cannon." },
        { order = 4, name = "Boundless Spirit",  priority = PRIORITY.OPT, rank = RANK.C,
          why = "Cut for Infuser or Glass Cannon." },
        { order = 5, name = "Echo Shard",        priority = PRIORITY.OPT, rank = RANK.C,
          why = "Optional CC echo — not in final 12." },
        { order = 6, name = "Unstoppable",       priority = PRIORITY.OPT, rank = RANK.C,
          why = "Situational — drop before core combo items." },
        { order = 7, name = "Headshot Booster",  priority = PRIORITY.OPT, rank = RANK.C,
          why = "Only sell if Glass Cannon needs the slot (rare)." },
    },

    temp_items = {
        "Reactive Barrier — buy early only if needed, sell first.",
        "Weapon Shielding — never in final 12.",
        "Headhunter — never in final 12 (use Glass Cannon).",
        "Boundless Spirit — cut for Infuser.",
        "Echo Shard — optional, not in final 12.",
    },

    early = {
        { name = "Mystic Burst", tier = "T1", priority = PRIORITY.CORE, rank = RANK.S,
          script = "Combo Items -> passive proc",
          why = "Cheapest spirit burst — included in Carbine killsteal." },
        { name = "Headshot Booster", tier = "T1", priority = PRIORITY.REC, rank = RANK.B,
          script = "Combo Items -> weapon finisher",
          why = "Cheap headshot amp — stays in final slot 12." },
        { name = "Healing Rite", tier = "T1", priority = PRIORITY.REC, rank = RANK.A,
          script = "Auto Defense -> low HP heal",
          why = "Save — stays in final slot 11." },
        { name = "Reactive Barrier", tier = "T1", priority = PRIORITY.OPT, rank = RANK.C,
          script = "Auto Defense -> TEMP — sell first",
          why = "Early buffer only — not in final 12." },
        { name = "Mystic Vulnerability", tier = "T2", priority = PRIORITY.CORE, rank = RANK.A,
          script = "Combo Items -> post-Swap debuff",
          why = "Spirit resist shred — final slot 2." },
    },

    mid = {
        { name = "Silence Wave", tier = "T3", priority = PRIORITY.CORE, rank = RANK.S,
          script = "Combo Items -> post-Swap silence",
          why = "Final slot 3." },
        { name = "Knockdown", tier = "T3", priority = PRIORITY.CORE, rank = RANK.S,
          script = "Combo Items -> delayed stun on grenade",
          why = "Final slot 4." },
        { name = "Dispel Magic", tier = "T3", priority = PRIORITY.REC, rank = RANK.A,
          script = "Auto Defense -> debuff cleanse",
          why = "Final slot 10." },
        { name = "Crippling Headshot", tier = "T4", priority = PRIORITY.OPT, rank = RANK.B,
          script = "Alt weapon finisher (safer than Glass)",
          why = "Not in default final 12 — pick instead of Glass if too fragile." },
        { name = "Spirit Burn", tier = "T4", priority = PRIORITY.REC, rank = RANK.A,
          script = "Combo Items -> passive (killsteal calc)",
          why = "Final slot 6." },
        { name = "Tankbuster", tier = "T3", priority = PRIORITY.REC, rank = RANK.S,
          script = "Combo Items -> passive proc",
          why = "Final slot 5." },
        { name = "Weapon Shielding", tier = "T2", priority = PRIORITY.OPT, rank = RANK.C,
          script = "Auto Defense -> TEMP — sell 2nd",
          why = "Not in final 12." },
    },

    late = {
        { name = "Infuser", tier = "T4", priority = PRIORITY.CORE, rank = RANK.S,
          script = "Combo Items -> auto pre-Carbine",
          why = "Final slot 7 — must have." },
        { name = "Glass Cannon", tier = "T4", priority = PRIORITY.REC, rank = RANK.A,
          script = "Combo Items -> Include in Killsteal",
          why = "Final slot 9 — default weapon finisher." },
        { name = "Mystic Reverb", tier = "T4", priority = PRIORITY.REC, rank = RANK.B,
          script = "Manual imbue on Carbine",
          why = "Final slot 8." },
        { name = "Echo Shard", tier = "T4", priority = PRIORITY.OPT, rank = RANK.B,
          script = "Combo Items -> after Knockdown (optional)",
          why = "Not in final 12 — sell if slots full." },
        { name = "Unstoppable", tier = "T3", priority = PRIORITY.OPT, rank = RANK.B,
          script = "Combo Items -> pre-Carbine OR Auto Defense",
          why = "Not in final 12." },
        { name = "Refresher", tier = "T4", priority = PRIORITY.OPT, rank = RANK.C,
          script = "Manual — not auto-cast",
          why = "Second combo — manual only." },
        { name = "Spellbreaker", tier = "T4", priority = PRIORITY.OPT, rank = RANK.A,
          script = "Auto Defense -> spirit immunity",
          why = "Situational save — not in default final 12." },
        { name = "Boundless Spirit", tier = "T4", priority = PRIORITY.OPT, rank = RANK.C,
          script = "TEMP — sell for Infuser",
          why = "Not in final 12." },
    },

    weapon = {
        { name = "Headshot Booster", tier = "T1", priority = PRIORITY.REC, rank = RANK.B,
          script = "Combo Items -> Include in Killsteal",
          why = "Final slot 12 — bought early." },
        { name = "Glass Cannon", tier = "T4", priority = PRIORITY.REC, rank = RANK.A,
          script = "Combo Items -> Include in Killsteal",
          why = "Final slot 9 — default finisher." },
        { name = "Crippling Headshot", tier = "T4", priority = PRIORITY.OPT, rank = RANK.B,
          script = "Alt — safer than Glass Cannon",
          why = "Swap in mid guide; not default final 12." },
        { name = "Hollow Point", tier = "T2", priority = PRIORITY.OPT, rank = RANK.C,
          script = "Combo Items -> Include in Killsteal",
          why = "Low-HP execute — optional, not in final 12." },
    },

    active = {
        { name = "Mystic Vulnerability", priority = PRIORITY.CORE, rank = RANK.A,
          script = "Post-Swap (before CC)", why = "Final slot 2." },
        { name = "Silence Wave", priority = PRIORITY.CORE, rank = RANK.S,
          script = "Post-Swap", why = "Final slot 3." },
        { name = "Slowing Hex", priority = PRIORITY.OPT, rank = RANK.C,
          script = "Post-Swap (optional)", why = "Not in final 12." },
        { name = "Mystic Slow", priority = PRIORITY.OPT, rank = RANK.C,
          script = "Post-Swap (optional)", why = "Not in final 12." },
        { name = "Knockdown", priority = PRIORITY.CORE, rank = RANK.S,
          script = "Post-Swap (on grenade)", why = "Final slot 4." },
        { name = "Echo Shard", priority = PRIORITY.OPT, rank = RANK.B,
          script = "After Knockdown", why = "Optional — not in final 12." },
        { name = "Infuser", priority = PRIORITY.CORE, rank = RANK.S,
          script = "Pre-Carbine", why = "Final slot 7." },
        { name = "Unstoppable", priority = PRIORITY.OPT, rank = RANK.B,
          script = "Start of Carbine charge", why = "Not in final 12." },
        { name = "Mystic Burst", priority = PRIORITY.REC, rank = RANK.S,
          script = "Passive — on Carbine proc", why = "Final slot 1." },
        { name = "Spirit Burn", priority = PRIORITY.REC, rank = RANK.A,
          script = "Passive — on Carbine proc", why = "Final slot 6." },
        { name = "Tankbuster", priority = PRIORITY.REC, rank = RANK.S,
          script = "Passive — on Carbine proc", why = "Final slot 5." },
    },

    save = {
        { name = "Healing Rite", priority = PRIORITY.CORE, rank = RANK.A,
          script = "Auto Defense -> HP threshold", why = "Final slot 11." },
        { name = "Dispel Magic", priority = PRIORITY.CORE, rank = RANK.A,
          script = "Auto Defense -> debuff detected", why = "Final slot 10." },
        { name = "Reactive Barrier", priority = PRIORITY.OPT, rank = RANK.C,
          script = "TEMP — sell first when full", why = "Not in final 12." },
        { name = "Weapon Shielding", priority = PRIORITY.OPT, rank = RANK.C,
          script = "TEMP — sell 2nd when full", why = "Not in final 12." },
        { name = "Spirit Shielding", priority = PRIORITY.REC, rank = RANK.B,
          script = "Auto Defense -> spirit damage", why = "Situational — not default." },
        { name = "Spellbreaker", priority = PRIORITY.OPT, rank = RANK.A,
          script = "Auto Defense -> spirit immunity", why = "Situational — not default." },
        { name = "Healing Nova", priority = PRIORITY.OPT, rank = RANK.C,
          script = "Auto Defense -> team heal", why = "Not in final 12." },
        { name = "Radiant Regeneration", priority = PRIORITY.OPT, rank = RANK.C,
          script = "Auto Defense -> regen", why = "Not in final 12." },
        { name = "Divine Barrier", priority = PRIORITY.OPT, rank = RANK.B,
          script = "Auto Defense -> team barrier", why = "Not in final 12." },
        { name = "Guardian Ward", priority = PRIORITY.OPT, rank = RANK.B,
          script = "Auto Defense -> ally shield", why = "Not in final 12." },
        { name = "Unstoppable", priority = PRIORITY.OPT, rank = RANK.B,
          script = "Auto Defense OR Combo", why = "Not in final 12." },
        { name = "Arcane Surge", priority = PRIORITY.OPT, rank = RANK.C,
          script = "Auto Defense -> spirit lifesteal", why = "Not in final 12." },
    },
}

ParadoxBuild.BUILD = BUILD

local ui_b
local font_hud = nil
local font_mono = nil

local HUD_LEFT      = 18
local HUD_WIDTH     = 300
local HUD_PAD_X     = 10
local HUD_PAD_Y     = 8
local HUD_OFFSET_Y  = -80
local HUD_ROW_H     = 13
local HUD_LINE_H    = 15
local HUD_SECTION   = 8

local HUD_MODE_KEYS = {
    "final_12", "progression", "replacements",
    "early", "mid", "late", "weapon", "active", "save", "all",
}

function ParadoxBuild.bind_menu(ui_build)
    ui_b = ui_build
end

local function safe(fn)
    local ok, v = pcall(fn)
    return ok and v or nil
end

local function ensure_fonts()
    if not font_hud then
        font_hud = Render.LoadFont("Tahoma", Enum.FontCreate.FONTFLAG_ANTIALIAS)
    end
    if not font_mono then
        font_mono = Render.LoadFont("Consolas", Enum.FontCreate.FONTFLAG_ANTIALIAS)
    end
end

local function hud_text_size(font, size, text)
    if not text or text == "" then return 0 end
    local ts = safe(function() return Render.TextSize(font, size, text) end)
    return ts and ts.x or (#text * size * 0.55)
end

local function truncate_to_width(font, size, text, max_w)
    if not text then return "" end
    if max_w <= 8 then return "..." end
    if hud_text_size(font, size, text) <= max_w then return text end
    local s = text
    while #s > 1 do
        s = string.sub(s, 1, #s - 1)
        local candidate = s .. "..."
        if hud_text_size(font, size, candidate) <= max_w then
            return candidate
        end
    end
    return "..."
end

local function draw_hud_panel_bg(px, py, w, h)
    if Render.FilledRect then
        Render.FilledRect(Vec2(px, py), Vec2(px + w, py + h), Color(6, 8, 14, 165), 6)
    end
    if Render.Rect then
        Render.Rect(Vec2(px, py), Vec2(px + w, py + h), Color(0, 150, 190, 40), 6, nil, 1)
    end
end

local function draw_hud_separator(x, y, w)
    Render.Line(Vec2(x, y), Vec2(x + w, y), Color(55, 75, 95, 90), 1)
end

local function draw_status_dot(px, py, col)
    if Render.FilledCircle then
        Render.FilledCircle(Vec2(px, py), 3.5, col)
    else
        Render.FilledRect(Vec2(px - 3, py - 3), Vec2(px + 3, py + 3), col, 2)
    end
end

local function draw_hud_text_right(font, size, text, right_x, y, col)
    if not text or text == "" then return end
    local w = hud_text_size(font, size, text)
    Render.Text(font, size, text, Vec2(right_x - w, y), col)
end

local function draw_hud_item_row(x, cy, inner_w, name, status_text, tag, dot_col, text_col, tag_col)
    draw_status_dot(x + 4, cy + 6, dot_col)
    local tag_w = 0
    if tag and tag ~= "" then
        tag_w = hud_text_size(font_mono, 9, tag) + 6
        draw_hud_text_right(font_mono, 9, tag, x + inner_w, cy + 1, tag_col)
    end
    local status_w = hud_text_size(font_mono, 10, status_text) + 6
    draw_hud_text_right(font_mono, 10, status_text, x + inner_w - tag_w, cy, text_col)
    local name_max_w = inner_w - tag_w - status_w - 18
    local name_text = truncate_to_width(font_mono, 10, name, name_max_w)
    Render.Text(font_mono, 10, name_text, Vec2(x + 12, cy), text_col)
end

local function priority_dot_color(p)
    if p == PRIORITY.CORE then return Color(70, 230, 110, 240) end
    if p == PRIORITY.REC  then return Color(255, 170, 70, 240) end
    return Color(160, 165, 175, 210)
end

local function priority_tag(p, rank, role, hud_key)
    if hud_key == "replacements" then return "sell" end
    if role then return role end
    if rank and RANK_LABEL[rank] then return RANK_LABEL[rank] end
    if p == PRIORITY.CORE then return "core" end
    if p == PRIORITY.REC  then return "rec" end
    return "opt"
end

local function priority_tag_color(p, rank, role, hud_key)
    if hud_key == "replacements" then return Color(255, 100, 100, 200) end
    if role == "combo"  then return Color(180, 140, 255, 190) end
    if role == "weapon" then return Color(255, 180, 80, 190) end
    if role == "save"   then return Color(80, 220, 140, 190) end
    if rank == RANK.S then return Color(255, 90, 90, 200) end
    if rank == RANK.A then return Color(255, 180, 80, 190) end
    if rank == RANK.B then return Color(120, 200, 255, 180) end
    if rank == RANK.C then return Color(150, 165, 185, 170) end
    if p == PRIORITY.CORE then return Color(80, 255, 140, 170) end
    if p == PRIORITY.REC  then return Color(255, 210, 80, 170) end
    return Color(150, 165, 185, 170)
end

local function priority_text_color(p)
    if p == PRIORITY.CORE then return Color(195, 205, 215, 235) end
    if p == PRIORITY.REC  then return Color(220, 195, 140, 230) end
    return Color(175, 180, 190, 220)
end

local function ascii(s)
    if not s then return "" end
    return s:gsub("\226\128\148", "-"):gsub("\226\128\147", "-"):gsub("\226\134\146", "->")
end

local function section_items(key)
    if key == "all" then
        local out = {}
        local seen = {}
        for _, k in ipairs({ "early", "mid", "late", "weapon" }) do
            local section = BUILD[k]
            if section then
                for i = 1, #section do
                    local item = section[i]
                    local n = item and item.name
                    if n and not seen[n] then
                        seen[n] = true
                        out[#out + 1] = item
                    end
                end
            end
        end
        return out
    end
    return BUILD[key] or {}
end

local function hud_status_text(item, key, compact)
    if key == "final_12" and item.slot then
        return string.format("#%d %s", item.slot, item.tier or "")
    end
    if key == "progression" and item.step then
        return string.format("S%d %s", item.step, item.tier or "")
    end
    if key == "replacements" and item.order then
        return string.format("#%d sell", item.order)
    end
    if compact and item.script then
        return truncate_to_width(font_mono, 10, ascii(item.script), 72)
    end
    return item.tier or ""
end

local function estimate_panel_height(items, compact)
    local content_h = 18 + HUD_SECTION + HUD_LINE_H + 4
    for i = 1, #items do
        content_h = content_h + HUD_ROW_H
        if not compact then
            local item = items[i]
            if item.script then content_h = content_h + 12 end
            if item.why and not item.script then content_h = content_h + 12 end
        end
    end
    return content_h + HUD_PAD_Y * 2
end

function ParadoxBuild.draw_hud()
    if not ui_b or not ui_b.show_hud or not ui_b.show_hud:Get() then return end

    local ok = pcall(function()
        ensure_fonts()

        local mode = ui_b.hud_mode and ui_b.hud_mode:Get() or 0
        local key = HUD_MODE_KEYS[(mode or 0) + 1] or "final_12"
        local items = section_items(key)
        local compact = ui_b.hud_compact and ui_b.hud_compact:Get()

        local title_map = {
            final_12    = "Final 12 Slots",
            progression = "Buy Order (Match)",
            replacements = "Sell When Full",
            early       = "Early Game",
            mid         = "Mid Game",
            late        = "Late Game",
            weapon      = "Weapon Finisher",
            active      = "Active Items",
            save        = "Save / Defense",
            all         = "Full Catalog (unique)",
        }

        local panel_h = estimate_panel_height(items, compact)
        local panel_w = HUD_WIDTH + HUD_PAD_X * 2
        local scr = Render.ScreenSize()
        local default_px = scr.x - panel_w - HUD_LEFT
        local default_py = math.floor((scr.y - panel_h) * 0.5 + HUD_OFFSET_Y)
        local px, py = default_px, default_py
        if HudDrag and HudDrag.apply then
            px, py = HudDrag.apply("build", default_px, default_py, panel_w, panel_h)
        end
        local x = px + HUD_PAD_X
        local inner_w = HUD_WIDTH

        draw_hud_panel_bg(px, py, panel_w, panel_h)
        if HudDrag and HudDrag.draw_header_hint then
            HudDrag.draw_header_hint(px, py, panel_w)
        end

        local cy = py + HUD_PAD_Y
        Render.Text(font_hud, 13, "PARADOX BUILD", Vec2(x, cy), Color(0, 220, 255, 255))
        cy = cy + 18
        cy = cy + 4
        draw_hud_separator(x, cy, inner_w)
        cy = cy + HUD_SECTION

        Render.Text(font_hud, 12, title_map[key] or key, Vec2(x, cy), Color(180, 200, 220, 230))
        cy = cy + HUD_LINE_H

        for i = 1, #items do
            local item = items[i]
            local status_text = hud_status_text(item, key, compact)
            local sub_text = item.script
            if key == "replacements" then
                sub_text = item.why
            end

            draw_hud_item_row(
                x, cy, inner_w,
                item.name,
                status_text,
                priority_tag(item.priority, item.rank, item.role, key),
                priority_dot_color(item.priority),
                priority_text_color(item.priority),
                priority_tag_color(item.priority, item.rank, item.role, key)
            )
            cy = cy + HUD_ROW_H

            if not compact and sub_text then
                Render.Text(font_mono, 10,
                    truncate_to_width(font_mono, 10, ascii(sub_text), inner_w - 8),
                    Vec2(x + 8, cy), Color(120, 200, 255, 210))
                cy = cy + 12
            elseif not compact and item.why and key ~= "replacements" then
                Render.Text(font_mono, 10,
                    truncate_to_width(font_mono, 10, ascii(item.why), inner_w - 8),
                    Vec2(x + 8, cy), Color(150, 165, 180, 200))
                cy = cy + 12
            end
        end
    end)
    if not ok then return end
end

local function menu_line(item, show_tier)
    local pri = PRI_LABEL[item.priority] or "[?]"
    local rank = item.rank and (" " .. (RANK_LABEL[item.rank] or "")) or ""
    local tier = (show_tier and item.tier) and (" " .. item.tier) or ""
    local script = item.script and (" | " .. ascii(item.script)) or ""
    local why = (not item.script and item.why) and (" | " .. ascii(item.why)) or ""
    return pri .. rank .. " " .. item.name .. tier .. script .. why
end

local function menu_line_slot(item)
    local role = item.role and (" [" .. item.role .. "]") or ""
    return string.format("#%d %s%s %s | %s", item.slot, item.tier or "", role, item.name, ascii(item.why or ""))
end

local function menu_line_step(item)
    return string.format("S%d %s %s | %s", item.step, item.tier or "", item.name, ascii(item.why or ""))
end

local function menu_line_sell(item)
    return string.format("#%d SELL %s | %s", item.order, item.name, ascii(item.why or ""))
end

function ParadoxBuild.create_menu()
    local tab = Menu.Create("Heroes", "Hero List", "Paradox", "\u{f0cb} Build Guide")
    local ui = {}

    local hud_grp = tab:Create("HUD")
    ui.show_hud   = hud_grp:Switch("Show Build HUD", true, "\u{f0cb}")
    ui.hud_mode   = hud_grp:Combo("HUD Section", {
        "Final 12 Slots", "Buy Order", "Sell When Full",
        "Early Game", "Mid Game", "Late Game", "Weapon Finisher",
        "Active Items", "Save / Defense", "Full Catalog",
    }, 0)
    ui.hud_compact = hud_grp:Switch("Compact HUD Rows", false)
    hud_grp:Label("Drag: open cheat menu, grab the title bar.")

    local overview = tab:Create("Overview")
    for i = 1, #BUILD.overview do
        overview:Label(BUILD.overview[i])
    end

    local loadout = tab:Create("Match Loadout")
    loadout:Label("=== Final 12 slots (end game) ===")
    for i = 1, #BUILD.final_12 do loadout:Label(menu_line_slot(BUILD.final_12[i])) end
    loadout:Label("=== Buy order (steps 1-12) ===")
    for i = 1, #BUILD.progression do loadout:Label(menu_line_step(BUILD.progression[i])) end
    loadout:Label("=== Sell when ITEM SLOTS FULL ===")
    for i = 1, #BUILD.replacements do loadout:Label(menu_line_sell(BUILD.replacements[i])) end
    loadout:Label("Never sell: Silence, Knockdown, Mystic Vuln, Infuser,")
    loadout:Label("Mystic Reverb, Dispel, Spirit Burn, Tankbuster.")

    local path = tab:Create("Build Path")
    path:Label("Early game purchases:")
    for i = 1, #BUILD.early do path:Label(menu_line(BUILD.early[i], true)) end
    path:Label("Mid game purchases:")
    for i = 1, #BUILD.mid do path:Label(menu_line(BUILD.mid[i], true)) end
    path:Label("Late game purchases:")
    for i = 1, #BUILD.late do path:Label(menu_line(BUILD.late[i], true)) end
    path:Label("Weapon finisher passives:")
    for i = 1, #BUILD.weapon do path:Label(menu_line(BUILD.weapon[i], true)) end

    local active = tab:Create("Combo Actives")
    active:Label("Enable these in Combo Items tab:")
    for i = 1, #BUILD.active do active:Label(menu_line(BUILD.active[i], false)) end

    local save = tab:Create("Save Items")
    save:Label("Configure in Auto Defense script:")
    for i = 1, #BUILD.save do save:Label(menu_line(BUILD.save[i], false)) end

    local slots = tab:Create("Slot Planning")
    slots:Label("Final 12: see Match Loadout tab.")
    for i = 1, #BUILD.final_12 do slots:Label(menu_line_slot(BUILD.final_12[i])) end
    slots:Label("Temp items (sell on the way):")
    for i = 1, #BUILD.temp_items do slots:Label(BUILD.temp_items[i]) end

    ui.show_hud:ToolTip("On-screen build reminder (top-right). Default: Final 12 Slots.")
    ui.hud_mode:ToolTip("Final 12 = end-game checklist. Buy Order = purchase timeline.")
    ui.hud_compact:ToolTip("One line per item in HUD.")

    return ui
end
