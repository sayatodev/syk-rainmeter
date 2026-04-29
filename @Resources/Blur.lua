local state = {
    tick = 0,
    x = nil,
    y = nil,
    w = nil,
    h = nil
}

local function current_geometry()
    return tonumber(SKIN:GetVariable('VSCREENAREAX', '0')) or 0,
        tonumber(SKIN:GetVariable('VSCREENAREAY', '0')) or 0,
        tonumber(SKIN:GetVariable('ScreenWidth', '0')) or 0,
        tonumber(SKIN:GetVariable('ScreenHeight', '0')) or 0
end

local function apply_window_geometry(x, y)
    SKIN:Bang('!Move', tostring(x), tostring(y))
    SKIN:Bang('!UpdateMeter', 'MeterBackground')
    SKIN:Bang('!UpdateMeasure', 'FrostedGlass')
    SKIN:Bang('!Redraw')
end

function Initialize()
    state.tick = 0
    state.x, state.y, state.w, state.h = current_geometry()
    apply_window_geometry(state.x, state.y)
end

function Update()
    state.tick = state.tick + 1

    local x, y, w, h = current_geometry()
    if x ~= state.x or y ~= state.y or w ~= state.w or h ~= state.h then
        state.x, state.y, state.w, state.h = x, y, w, h
        apply_window_geometry(x, y)
        return ''
    end

    -- Retry shortly after load and then occasionally to recover from DWM / desktop state changes.
    if state.tick == 2 or state.tick == 10 or state.tick % 300 == 0 then
        SKIN:Bang('!UpdateMeasure', 'FrostedGlass')
    end

    return ''
end
