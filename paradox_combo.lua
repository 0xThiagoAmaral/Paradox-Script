-- Paradox — Full Combo + Ability Assists
-- Combo: Q↓ → restore → F → E (track) → [itens] → C (headshot)
-- Assists: uso individual por habilidade (tab Ability Assists)

local PC = ParadoxCombo
if not PC then
    error("[Paradox Combo] 1_paradox_combo_core.lua failed to load — check console")
end
local COMBO_ITEMS = PC.COMBO_ITEMS

-- ─── Menu ───────────────────────────────────────────────────────────────────

local tab = Menu.Create("Heroes", "Hero List", "Paradox", "\u{f017} Paradox Combo", "\u{f0e7} Full Combo")

local ui = {
    enable        = tab:Switch("Enable Combo", true, "\u{f011}"),
    test_key      = tab:Bind("Combo Key (tap)", Enum.ButtonCode.KEY_G),
    auto_acquire  = tab:Switch("Snap to Target First", true),
    draw_hud      = tab:Switch("Show HUD", true),
    track_fov     = tab:Slider("Target FOV", 1, 180, 30, "%d°"),
    show_fov_combo = tab:Switch("Draw FOV Circle", true),
}

local gear_steps = ui.enable:Gear("Combo Steps")
ui.use_wall    = gear_steps:Switch("Time Wall (F)", true)
ui.use_swap    = gear_steps:Switch("Swap (E)", true)
ui.use_carbine = gear_steps:Switch("Carbine Headshot (C)", true)

local gear_timing = ui.enable:Gear("Timing")
ui.acquire_delay_ms   = gear_timing:Slider("Acquire Aim Delay (ms)", 0, 150, 40, "%d ms")
ui.acquire_timeout_ms = gear_timing:Slider("Acquire Timeout (ms)", 50, 500, 250, "%d ms")
ui.aim_delay_ms       = gear_timing:Slider("Grenade Aim Delay (ms)", 0, 400, 120, "%d ms")
ui.wall_delay_ms      = gear_timing:Slider("Wall Aim Delay (ms)", 0, 300, 80, "%d ms")
ui.wall_confirm_ms    = gear_timing:Slider("Wall Confirm Delay (ms)", 50, 250, 100, "%d ms")
ui.wall_ready_wait_ms = gear_timing:Slider("Wall Ready Timeout (ms)", 100, 800, 350, "%d ms")
ui.swap_delay_ms      = gear_timing:Slider("Swap Aim Delay (ms)", 0, 300, 50, "%d ms")
ui.swap_hold_ms       = gear_timing:Slider("Swap Button Hold (ms)", 50, 400, 100, "%d ms")
ui.swap_ready_wait_ms = gear_timing:Slider("Swap Ready Timeout (ms)", 100, 800, 300, "%d ms")
ui.swap_track_ms      = gear_timing:Slider("Swap Track Duration (ms)", 200, 1500, 1100, "%d ms")
ui.carbine_charge_ms  = gear_timing:Slider("Carbine Charge Time (ms)", 200, 3500, 3500, "%d ms")
ui.carbine_fire_ms    = gear_timing:Slider("Carbine Fire Hold (ms)", 30, 250, 80, "%d ms")
ui.carbine_ready_ms   = gear_timing:Slider("Carbine Ready Timeout (ms)", 100, 1200, 400, "%d ms")

local gear_aim = ui.enable:Gear("Aim")
ui.acquire_tol  = gear_aim:Slider("Acquire Settle FOV", 3, 20, 8, "%d°")
ui.max_pitch    = gear_aim:Slider("Max Pitch Down", 70.0, 89.0, 89.0, "%.1f°")
ui.restore_tol  = gear_aim:Slider("Restore Aim Tolerance (°)", 1, 15, 5, "%d°")
ui.swap_psilent = gear_aim:Switch("Swap Psilent", true)
ui.carbine_psilent = gear_aim:Switch("Carbine Psilent (head)", true)
ui.ray_dist_m   = gear_aim:Slider("Ray Trace Dist (m)", 1.0, 8.0, 4.0, "%.1fm")
ui.below_m      = gear_aim:Slider("Aim Below Ground (m)", 0.0, 1.5, 0.0, "%.2fm")

local gear_wall_combo = ui.use_wall:Gear("Wall Placement")
ui.wall_offensive_pct = gear_wall_combo:Slider("Offensive Placement %", 35, 75, 55, "%d%%")
ui.wall_height_m      = gear_wall_combo:Slider("Wall Height (m)", 0.5, 3.0, 1.75, "%.2f m")
ui.wall_use_solver    = gear_wall_combo:Switch("Use Wall Solver (no LoS)", false)

local gear_fov_combo = ui.track_fov:Gear("FOV Visual")
ui.fov_combo_color = gear_fov_combo:ColorPicker("Circle Color", Color(0, 220, 255, 90))
ui.fov_combo_thick = gear_fov_combo:Slider("Line Width", 1, 4, 1, "%d px")
ui.fov_step        = gear_fov_combo:Slider("Adjust Step", 1, 15, 5, "%d°")
ui.fov_inc         = gear_fov_combo:Bind("FOV +", Enum.ButtonCode.KEY_NONE)
ui.fov_dec         = gear_fov_combo:Bind("FOV -", Enum.ButtonCode.KEY_NONE)

local gear_debug = ui.enable:Gear("Debug")
ui.draw_debug = gear_debug:Switch("Draw Debug Markers", false, "\u{f06e}")

local gear_hud_layout = ui.draw_hud:Gear("HUD Layout")
gear_hud_layout:Label("Open the cheat menu, then drag any panel title bar.")
ui.hud_drag_lock = gear_hud_layout:Switch("Lock HUD Positions", false)
ui.hud_reset_pos = gear_hud_layout:Button("Reset HUD Positions", function()
    if HudDrag and HudDrag.clear_all then
        HudDrag.clear_all()
        print("[Paradox] HUD positions reset to defaults")
    end
end)

ui.enable:ToolTip("Full combo: Q at feet → aim at enemy → F → E → C (headshot).")
ui.test_key:ToolTip("Tap near an enemy to start the full combo. Default: G.")
ui.auto_acquire:ToolTip("If enemy is in FOV but off crosshair, snap aim before starting.")
ui.draw_hud:ToolTip("Shows current combo phase on screen.")
ui.hud_drag_lock:ToolTip("Locks Paradox, Auto Defense, and Build HUD panels in place.")
ui.hud_reset_pos:ToolTip("Clears saved positions; panels return to default layout on next draw.")
ui.track_fov:ToolTip("Enemy search radius (combo + acquire). Use FOV +/- or slider.")
ui.fov_inc:ToolTip("Increase combo FOV by configured step.")
ui.fov_dec:ToolTip("Decrease combo FOV by configured step.")
ui.swap_track_ms:ToolTip("Keep tracking the enemy during Swap.")
ui.aim_delay_ms:ToolTip("Time on ground aim before pressing Q (needed for instant cast).")
ui.carbine_charge_ms:ToolTip("Time holding C + LMB after ready, with head aim.")

-- ─── Combo Items tab ────────────────────────────────────────────────────────

local items_tab = Menu.Create("Heroes", "Hero List", "Paradox", "\u{f0c0} Combo Items")
local items_root = items_tab:Create("General")

local ui_i = {
    enable          = items_root:Switch("Use Items in Combo", true, "\u{f0c0}"),
    show_loadout_hud = items_root:Switch("Show Loadout HUD", true),
    post_swap_delay_ms = items_root:Slider("Post-Swap Delay (ms)", 0, 1500, 350, "%d ms"),
    item_hold_ms    = items_root:Slider("Item Cast Hold (ms)", 30, 400, 100, "%d ms"),
    pre_carbine_delay_ms = items_root:Slider("Pre-Carbine Delay (ms)", 0, 500, 60, "%d ms"),
}

ui_i.enable:ToolTip("Runs enabled items automatically at the right combo phases.")
ui_i.post_swap_delay_ms:ToolTip("Wait after swap before first item (enemy lands on grenade).")
ui_i.item_hold_ms:ToolTip("Key hold time for each active item.")
ui_i.pre_carbine_delay_ms:ToolTip("Short pause before Infuser/Unstoppable.")

local ui_item = {}
for _, def in ipairs(COMBO_ITEMS) do
    if not def or not def.id or not def.name then
        print("[Paradox Combo] skip invalid COMBO_ITEMS entry")
    else
        local ok_item, err_item = pcall(function()
            local grp = items_tab:Create(def.name)
            ui_item[def.id] = {}
            if def.cast then
                ui_item[def.id].use = grp:Switch("Use in Combo", def.default_on)
                ui_item[def.id].use:ToolTip(def.desc or "")
            elseif def.weapon_finisher then
                ui_item[def.id].track = grp:Switch("Include in Killsteal", def.default_on ~= false)
                ui_item[def.id].track:ToolTip(def.desc or "")
            else
                grp:Label("Automatic proc (no combo cast)")
            end
            grp:Label("When: " .. (def.timing or ""))
            grp:Label(def.desc or "")
        end)
        if not ok_item then
            print("[Paradox Combo] menu failed for " .. tostring(def.id) .. ": " .. tostring(err_item))
        end
    end
end

-- ─── Ability Assists (uso individual) ───────────────────────────────────────

local assist_tab = Menu.Create("Heroes", "Hero List", "Paradox", "\u{f05b} Ability Assists")
local assist_root = assist_tab:Create("General")

local ui_a = {
    show_hud = assist_root:Switch("Show Assist HUD", true),
}

local grp_carbine = assist_tab:Create("Kinetic Carbine (C)")
ui_a.carbine_enable = grp_carbine:Switch("Auto Charge + Headshot", true, "\u{f05b}")
ui_a.carbine_mode   = grp_carbine:Combo("Activation", { "On C Press", "Assist Key" }, 0)
ui_a.carbine_key    = grp_carbine:Bind("Assist Key", Enum.ButtonCode.KEY_NONE)
ui_a.carbine_fov    = grp_carbine:Slider("Target FOV", 1, 180, 30, "%d°")
ui_a.show_fov_carbine = grp_carbine:Switch("Draw FOV Circle", true)

local gear_ca = ui_a.carbine_enable:Gear("Aim")
ui_a.carbine_psilent = gear_ca:Switch("Psilent (head)", true)

local gear_fov_carbine = ui_a.carbine_fov:Gear("FOV Visual")
ui_a.fov_carbine_color = gear_fov_carbine:ColorPicker("Circle Color", Color(255, 200, 60, 90))
ui_a.fov_carbine_thick = gear_fov_carbine:Slider("Line Width", 1, 4, 1, "%d px")
ui_a.fov_step          = gear_fov_carbine:Slider("Adjust Step", 1, 15, 5, "%d°")
ui_a.fov_inc           = gear_fov_carbine:Bind("FOV +", Enum.ButtonCode.KEY_NONE)
ui_a.fov_dec           = gear_fov_carbine:Bind("FOV -", Enum.ButtonCode.KEY_NONE)

local gear_ct = ui_a.carbine_enable:Gear("Timing")
ui_a.carbine_charge_ms = gear_ct:Slider("Charge Time (ms)", 200, 3500, 3500, "%d ms")
ui_a.carbine_fire_ms   = gear_ct:Slider("Fire Hold (ms)", 30, 250, 80, "%d ms")

local gear_ck = ui_a.carbine_enable:Gear("Killsteal")
ui_a.carbine_killsteal    = gear_ck:Switch("Auto Cast When Lethal", false)
ui_a.carbine_fire_lethal  = gear_ck:Switch("Fire Early When Lethal", true)
ui_a.carbine_kill_safety  = gear_ck:Slider("Damage Safety %", 50, 100, 92, "%d%%")
ui_a.carbine_kill_min_chg = gear_ck:Slider("Min Charge To Fire %", 0, 100, 25, "%d%%")
ui_a.carbine_kill_hud     = gear_ck:Switch("Show Kill Prediction HUD", true)

local grp_grenade = assist_tab:Create("Pulse Grenade (Q)")
ui_a.grenade_enable = grp_grenade:Switch("Grenade Auto Aim + Cast", true)
ui_a.grenade_mode   = grp_grenade:Combo("Grenade Activation", { "On Q Press", "Assist Key" }, 0)
ui_a.grenade_key    = grp_grenade:Bind("Grenade Assist Key", Enum.ButtonCode.KEY_NONE)
ui_a.grenade_fov    = grp_grenade:Slider("Grenade Target FOV", 1, 180, 30, "%d°")
ui_a.show_fov_grenade = grp_grenade:Switch("Grenade Draw FOV Circle", true)

local gear_ga = ui_a.grenade_enable:Gear("Grenade Aim")
ui_a.grenade_aim_mode   = gear_ga:Combo("Grenade Aim Mode", { "Psilent", "Smooth", "Hybrid" }, 2)
ui_a.grenade_smooth     = gear_ga:Slider("Grenade Smooth", 1, 40, 15, "%d")
ui_a.grenade_psilent_fov = gear_ga:Slider("Grenade Psilent FOV", 1, 180, 30, "%d°")
ui_a.grenade_predict    = gear_ga:Switch("Grenade Movement Predict", true)
ui_a.grenade_lead_ms    = gear_ga:Slider("Grenade Extra Lead (ms)", 0, 500, 120, "%d ms")
ui_a.grenade_restore    = gear_ga:Switch("Grenade Restore Aim", true)
ui_a.grenade_aim_tol    = gear_ga:Slider("Grenade Aim Settle FOV", 3, 20, 8, "%d°")
ui_a.grenade_below_m    = gear_ga:Slider("Grenade Below Feet (m)", 0.0, 1.5, 0.0, "%.2fm")
ui_a.grenade_restore_tol = gear_ga:Slider("Grenade Restore Tol (°)", 1, 15, 5, "%d°")

local gear_gt = ui_a.grenade_enable:Gear("Grenade Timing")
ui_a.grenade_aim_delay_ms  = gear_gt:Slider("Grenade Aim Delay (ms)", 0, 400, 120, "%d ms")
ui_a.grenade_cast_hold_ms  = gear_gt:Slider("Grenade Cast Hold (ms)", 30, 250, 80, "%d ms")
ui_a.grenade_ready_wait_ms = gear_gt:Slider("Grenade Ready Timeout (ms)", 100, 800, 350, "%d ms")

local gear_gf = ui_a.grenade_fov:Gear("Grenade FOV Visual")
ui_a.fov_grenade_color = gear_gf:ColorPicker("Grenade Circle Color", Color(255, 120, 60, 90))
ui_a.fov_grenade_thick = gear_gf:Slider("Grenade Line Width", 1, 4, 1, "%d px")
ui_a.grenade_fov_step  = gear_gf:Slider("Grenade FOV Step", 1, 15, 5, "%d°")
ui_a.grenade_fov_inc   = gear_gf:Bind("Grenade FOV +", Enum.ButtonCode.KEY_NONE)
ui_a.grenade_fov_dec   = gear_gf:Bind("Grenade FOV -", Enum.ButtonCode.KEY_NONE)

local grp_wall = assist_tab:Create("Time Wall (F)")
ui_a.wall_enable = grp_wall:Switch("Wall Auto Aim + Cast", true, "\u{f0c8}")
ui_a.wall_mode   = grp_wall:Combo("Wall Activation", { "On F Press", "Assist Key" }, 0)
ui_a.wall_key    = grp_wall:Bind("Wall Assist Key", Enum.ButtonCode.KEY_NONE)
ui_a.wall_fov    = grp_wall:Slider("Wall Target FOV", 1, 180, 30, "%d°")
ui_a.show_fov_wall = grp_wall:Switch("Wall Draw FOV Circle", true)

local gear_wm = ui_a.wall_enable:Gear("Wall Placement")
ui_a.wall_mode_placement = gear_wm:Combo("Placement Mode", { "Offensive", "Defensive" }, 0)
ui_a.wall_offensive_pct  = gear_wm:Slider("Offensive Placement %", 35, 75, 55, "%d%%")
ui_a.wall_defensive_pct  = gear_wm:Slider("Defensive Placement %", 15, 50, 30, "%d%%")
ui_a.wall_height_m       = gear_wm:Slider("Wall Height (m)", 0.5, 3.0, 1.75, "%.2f m")
ui_a.wall_use_solver     = gear_wm:Switch("Use Wall Solver (no LoS)", false)
ui_a.wall_solver_dist_m  = gear_wm:Slider("Solver Search Dist (m)", 8, 30, 18, "%.0f m")

local gear_wa = ui_a.wall_enable:Gear("Wall Aim")
ui_a.wall_aim_mode    = gear_wa:Combo("Wall Aim Mode", { "Psilent", "Smooth", "Hybrid" }, 2)
ui_a.wall_smooth      = gear_wa:Slider("Wall Smooth", 1, 40, 15, "%d")
ui_a.wall_psilent_fov = gear_wa:Slider("Wall Psilent FOV", 1, 180, 30, "%d°")
ui_a.wall_restore     = gear_wa:Switch("Wall Restore Aim", true)
ui_a.wall_aim_tol     = gear_wa:Slider("Wall Aim Settle FOV", 3, 20, 8, "%d°")
ui_a.wall_restore_tol = gear_wa:Slider("Wall Restore Tol (°)", 1, 15, 5, "%d°")

local gear_wt = ui_a.wall_enable:Gear("Wall Timing")
ui_a.wall_aim_delay_ms  = gear_wt:Slider("Wall Aim Delay (ms)", 0, 300, 80, "%d ms")
ui_a.wall_confirm_ms    = gear_wt:Slider("Wall Confirm Delay (ms)", 50, 250, 100, "%d ms")
ui_a.wall_ready_wait_ms = gear_wt:Slider("Wall Ready Timeout (ms)", 100, 800, 350, "%d ms")

local gear_wd = ui_a.wall_enable:Gear("Auto Defense Wall")
ui_a.wall_def_enable        = gear_wd:Switch("Auto Wall on Low HP", false)
ui_a.wall_def_hp            = gear_wd:Slider("HP Threshold %", 5, 60, 40, "%d%%")
ui_a.wall_def_radius_m      = gear_wd:Slider("Threat Radius (m)", 5, 30, 18, "%.0f m")
ui_a.wall_def_min_enemies   = gear_wd:Slider("Min Nearby Enemies", 1, 4, 1, "%d")
ui_a.wall_def_require_threat = gear_wd:Switch("Require Nearby Threat", true)
ui_a.wall_def_panic_key     = gear_wd:Bind("Panic Wall Key", Enum.ButtonCode.KEY_NONE)
ui_a.wall_def_cooldown_ms   = gear_wd:Slider("Defense Cooldown (ms)", 500, 3000, 1200, "%d ms")

local gear_wf = ui_a.wall_fov:Gear("Wall FOV Visual")
ui_a.fov_wall_color = gear_wf:ColorPicker("Wall Circle Color", Color(80, 220, 255, 90))
ui_a.fov_wall_thick = gear_wf:Slider("Wall Line Width", 1, 4, 1, "%d px")

local grp_swap = assist_tab:Create("Paradoxical Swap (E)")
ui_a.swap_enable = grp_swap:Switch("Swap Auto Aim + Cast", true, "\u{f0ec}")
ui_a.swap_mode   = grp_swap:Combo("Swap Activation", { "On E Press", "Assist Key" }, 0)
ui_a.swap_key    = grp_swap:Bind("Swap Assist Key", Enum.ButtonCode.KEY_NONE)
ui_a.swap_fov    = grp_swap:Slider("Swap Target FOV", 1, 180, 30, "%d°")
ui_a.show_fov_swap = grp_swap:Switch("Swap Draw FOV Circle", true)

local gear_sa = ui_a.swap_enable:Gear("Swap Aim")
ui_a.swap_aim_mode    = gear_sa:Combo("Swap Aim Mode", { "Psilent", "Smooth", "Hybrid" }, 0)
ui_a.swap_smooth      = gear_sa:Slider("Swap Smooth", 1, 40, 15, "%d")
ui_a.swap_psilent_fov = gear_sa:Slider("Swap Psilent FOV", 1, 180, 30, "%d°")
ui_a.swap_bone        = gear_sa:Combo("Aim Bone", { "Chest (spine_2)", "Pelvis", "Head" }, 0)
ui_a.swap_predict     = gear_sa:Switch("Swap Movement Predict", true)
ui_a.swap_lead_ms     = gear_sa:Slider("Swap Extra Lead (ms)", 0, 300, 60, "%d ms")
ui_a.swap_restore     = gear_sa:Switch("Swap Restore Aim", true)
ui_a.swap_aim_tol     = gear_sa:Slider("Swap Aim Settle FOV", 3, 20, 10, "%d°")
ui_a.swap_restore_tol = gear_sa:Slider("Swap Restore Tol (°)", 1, 15, 5, "%d°")
ui_a.swap_max_range_m = gear_sa:Slider("Max Swap Range (m)", 5, 30, 25, "%.0f m")

local gear_st = ui_a.swap_enable:Gear("Swap Timing")
ui_a.swap_aim_delay_ms  = gear_st:Slider("Swap Aim Delay (ms)", 0, 300, 50, "%d ms")
ui_a.swap_cast_hold_ms  = gear_st:Slider("Swap Cast Hold (ms)", 30, 400, 100, "%d ms")
ui_a.swap_ready_wait_ms = gear_st:Slider("Swap Ready Timeout (ms)", 100, 800, 300, "%d ms")
ui_a.swap_track_enable  = gear_st:Switch("Post-Cast Tracking", true)
ui_a.swap_track_ms      = gear_st:Slider("Track Duration (ms)", 200, 1500, 1100, "%d ms")

local gear_sf = ui_a.swap_fov:Gear("Swap FOV Visual")
ui_a.fov_swap_color = gear_sf:ColorPicker("Swap Circle Color", Color(200, 100, 255, 90))
ui_a.fov_swap_thick = gear_sf:Slider("Swap Line Width", 1, 4, 1, "%d px")

ui_a.carbine_enable:ToolTip("Press C once: auto charge + headshot with psilent.")
ui_a.carbine_mode:ToolTip("On C Press = when ability is pressed. Assist Key = extra bind.")
ui_a.carbine_charge_ms:ToolTip("Auto charge time before firing.")
ui_a.carbine_fov:ToolTip("Target search radius for headshot. Use FOV +/- or slider.")
ui_a.fov_inc:ToolTip("Increase carbine FOV by configured step.")
ui_a.fov_dec:ToolTip("Decrease carbine FOV by configured step.")
ui_a.carbine_killsteal:ToolTip("Without pressing C: auto-starts if max carbine damage kills target in FOV.")
ui_a.carbine_fire_lethal:ToolTip("During charge, fires as soon as current damage is lethal (does not wait for 100%).")
ui_a.carbine_kill_safety:ToolTip("Safety margin in damage calculation (same as killstealer).")
ui_a.carbine_kill_min_chg:ToolTip("Minimum charge before allowing early lethal fire.")
ui_a.grenade_enable:ToolTip("Press Q once: aim at enemy feet and cast grenade.")
ui_a.grenade_mode:ToolTip("On Q Press = when ability is pressed. Assist Key = extra bind.")
ui_a.grenade_aim_delay_ms:ToolTip("Time aiming at feet before pressing Q.")
ui_a.grenade_fov:ToolTip("Target search radius. Use FOV +/- or slider.")
ui_a.grenade_aim_mode:ToolTip("Psilent = psilent only. Smooth = smooth camera. Hybrid = smooth until inside psilent FOV.")
ui_a.grenade_smooth:ToolTip("Camera smoothing in Smooth/Hybrid mode.")
ui_a.grenade_psilent_fov:ToolTip("Max FOV to apply psilent on target.")
ui_a.grenade_predict:ToolTip("Predicts enemy movement before casting grenade.")
ui_a.grenade_lead_ms:ToolTip("Extra lead beyond estimated travel time.")
ui_a.grenade_restore:ToolTip("Restore original aim after casting grenade.")
ui_a.grenade_below_m:ToolTip("Fine adjustment below foot bone (same as combo).")
ui_a.wall_enable:ToolTip("Press F once: aim at wall placement point, select, then confirm with LMB.")
ui_a.wall_mode:ToolTip("On F Press = when ability is pressed. Assist Key = extra bind.")
ui_a.wall_mode_placement:ToolTip("Offensive = wall between you and enemy. Defensive = closer to you.")
ui_a.wall_offensive_pct:ToolTip("How far along the line to enemy (higher = closer to enemy).")
ui_a.wall_defensive_pct:ToolTip("How far along the threat line (lower = closer to you).")
ui_a.wall_use_solver:ToolTip("Uses prediction solver when placement needs cover angle.")
ui_a.wall_confirm_ms:ToolTip("Delay after wall is selected before LMB confirm.")
ui_a.wall_def_enable:ToolTip("Auto-casts defensive wall when HP is low or panic key is pressed.")
ui_a.wall_def_panic_key:ToolTip("Instant defensive wall toward nearest threat.")
ui_a.swap_enable:ToolTip("Press E once: predict + aim at enemy, cast swap, optional track.")
ui_a.swap_mode:ToolTip("On E Press = when ability is pressed. Assist Key = extra bind.")
ui_a.swap_aim_mode:ToolTip("Psilent = only fires when pSilent works (best accuracy). Hybrid = smooth fallback.")
ui_a.swap_psilent_fov:ToolTip("Max FOV to apply pSilent. Use 180 for widest window.")
ui_a.swap_predict:ToolTip("Predicts enemy movement using swap projectile speed (~3500).")
ui_a.swap_track_enable:ToolTip("Keep tracking the enemy after swap (like combo track phase).")
ui_a.swap_track_ms:ToolTip("How long to keep aim on target after swap lands.")
ui_a.swap_max_range_m:ToolTip("Max cast range (ability is 25m).")

local ui_b = {}
if ParadoxBuild and ParadoxBuild.create_menu then
    local ok, result = pcall(ParadoxBuild.create_menu)
    if ok and type(result) == "table" then
        ui_b = result
    else
        print("[Paradox Build] menu create failed: " .. tostring(result))
    end
end

PC.bind_menu(ui, ui_i, ui_a, ui_item, ui_b)

callback.on_createmove:set(PC.on_createmove)
callback.on_draw:set(PC.on_draw)

print("[Paradox Combo] Full combo: Q↓ → restore → F → E → items → C (carbine)")
print("[Paradox Combo] Ability Assists: grenade, wall, swap, carbine")
print("[Paradox Combo] Combo Items tab: loadout HUD + automatic item queue")
print("[Paradox Combo] Menu: Paradox Combo / Combo Items / Ability Assists / Build Guide")
if not PC.DC then
    print("[Paradox Combo] WARN: damage_calc.lua failed to load — carbine killsteal disabled")
end
PC.init()
