-- Draggable HUD panels (Paradox combo, Auto Defense, Build Guide)
HudDrag = HudDrag or {}

local HEADER_H = 22
local active_id = nil
local drag_off = nil

db.paradox_hud_pos = db.paradox_hud_pos or {}

local function is_locked()
    return db.paradox_hud_drag_lock == true
end

function HudDrag.set_locked(v)
    db.paradox_hud_drag_lock = v and true or false
end

function HudDrag.is_locked()
    return is_locked()
end

function HudDrag.clear_all()
    db.paradox_hud_pos = {}
    active_id = nil
    drag_off = nil
end

local function clamp(px, py, pw, ph)
    local scr = Render.ScreenSize()
    local max_x = math.max(0, (scr.x or 1920) - pw)
    local max_y = math.max(0, (scr.y or 1080) - ph)
    if px < 0 then px = 0 end
    if py < 0 then py = 0 end
    if px > max_x then px = max_x end
    if py > max_y then py = max_y end
    return px, py
end

local function get_pos(id, dx, dy)
    local p = db.paradox_hud_pos[id]
    if p and p.x ~= nil and p.y ~= nil then
        return p.x, p.y
    end
    db.paradox_hud_pos[id] = Vec2(dx, dy)
    return dx, dy
end

local function set_pos(id, px, py)
    local p = db.paradox_hud_pos[id]
    if not p then
        db.paradox_hud_pos[id] = Vec2(px, py)
    else
        p.x = px
        p.y = py
    end
end

local function menu_open()
    return Menu and Menu.Opened and Menu.Opened()
end

function HudDrag.can_drag()
    return menu_open() and not is_locked()
end

function HudDrag.apply(id, default_px, default_py, panel_w, panel_h)
    local px, py = get_pos(id, default_px, default_py)
    px, py = clamp(px, py, panel_w, panel_h)
    set_pos(id, px, py)

    if not HudDrag.can_drag() then
        return math.floor(px + 0.5), math.floor(py + 0.5)
    end

    local cur = input.cursor_pos()
    if not active_id then
        if input.cursor_in_bounds(Vec2(px, py), Vec2(px + panel_w, py + HEADER_H))
            and input.is_pressed(Enum.ButtonCode.KEY_MOUSE1) then
            active_id = id
            drag_off = cur - Vec2(px, py)
        end
    elseif active_id == id then
        if input.is_down(Enum.ButtonCode.KEY_MOUSE1) and drag_off then
            px = cur.x - drag_off.x
            py = cur.y - drag_off.y
            px, py = clamp(px, py, panel_w, panel_h)
            set_pos(id, px, py)
        else
            active_id = nil
            drag_off = nil
        end
    end

    return math.floor(px + 0.5), math.floor(py + 0.5)
end

function HudDrag.draw_header_hint(px, py, panel_w)
    if not HudDrag.can_drag() then return end
    if not input.cursor_in_bounds(Vec2(px, py), Vec2(px + panel_w, py + HEADER_H)) then
        return
    end
    if Render.FilledRect then
        Render.FilledRect(Vec2(px + 2, py + 2), Vec2(px + panel_w - 2, py + HEADER_H - 1),
            Color(255, 255, 255, 14), 4)
    end
end
