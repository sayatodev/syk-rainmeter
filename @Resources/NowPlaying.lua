local state = {
    snapshot_received_at = 0,
    last_start_attempt_at = 0,
    helper_path = nil,
    cache_path = nil,
    visible = true,
    playback_status = '',
    position_ms = 0,
    duration_ms = 0,
    cache_updated_at_ms = 0
}

local function trim(s)
    return (s or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function contains_ignore_case(haystack, needle)
    return string.find(string.lower(haystack or ''), string.lower(needle or ''), 1, true) ~= nil
end

local function read_file(path)
    local handle = io.open(path, 'rb')
    if not handle then
        return ''
    end

    local content = handle:read('*a') or ''
    handle:close()
    if content:sub(1, 3) == string.char(239, 187, 191) then
        content = content:sub(4)
    end
    return content
end

local function file_exists(path)
    local handle = io.open(path, 'rb')
    if handle then
        handle:close()
        return true
    end
    return false
end

local function parse_cache(raw)
    local values = {}
    for line in raw:gmatch('[^\r\n]+') do
        local key, value = line:match('^([^=]+)=(.*)$')
        if key then
            values[trim(key)] = value or ''
        end
    end
    return values
end

local function read_cache_values()
    local raw = read_file(state.cache_path)
    if trim(raw) == '' then
        return nil
    end

    return parse_cache(raw)
end

local function format_time(milliseconds)
    if not milliseconds or milliseconds <= 0 then
        return ''
    end

    local total_seconds = math.floor((milliseconds + 500) / 1000)
    local hours = math.floor(total_seconds / 3600)
    local minutes = math.floor((total_seconds % 3600) / 60)
    local seconds = total_seconds % 60

    if hours > 0 then
        return string.format('%d:%02d:%02d', hours, minutes, seconds)
    end

    return string.format('%d:%02d', minutes, seconds)
end

local function set_hidden()
    if state.visible then
        SKIN:Bang('!HideMeterGroup', 'NowPlayingData')
        SKIN:Bang('!Redraw')
        state.visible = false
    end
end

local function set_visible()
    if not state.visible then
        SKIN:Bang('!ShowMeterGroup', 'NowPlayingData')
        state.visible = true
    end
end

local function current_position_ms()
    local position = state.position_ms or 0
    if state.playback_status == 'Playing' and state.snapshot_received_at > 0 then
        local elapsed = math.max(0, os.time() - state.snapshot_received_at)
        position = position + (elapsed * 1000)
    end

    if state.duration_ms and state.duration_ms > 0 then
        position = math.min(position, state.duration_ms)
    end

    return math.max(0, position)
end

local function update_progress_ui()
    local duration = state.duration_ms or 0
    local position = current_position_ms()
    local width = 0
    local time_text = ''

    if duration > 0 then
        local progress_width = tonumber(SKIN:GetVariable('ProgressBarWidth', '0')) or 0
        width = math.floor((position / duration) * progress_width + 0.5)
        time_text = format_time(position) .. ' / ' .. format_time(duration)
    end

    SKIN:Bang('!SetVariable', 'NowPlayingProgressWidth', width)
    SKIN:Bang('!SetVariable', 'NowPlayingTimeText', time_text)
    SKIN:Bang('!UpdateMeter', 'MeterLength')
    SKIN:Bang('!UpdateMeter', 'MeterProgressFill')

    if duration > 0 then
        SKIN:Bang('!ShowMeter', 'MeterLength')
        SKIN:Bang('!ShowMeter', 'MeterProgressTrack')
        SKIN:Bang('!ShowMeter', 'MeterProgressFill')
    else
        SKIN:Bang('!HideMeter', 'MeterLength')
        SKIN:Bang('!HideMeter', 'MeterProgressTrack')
        SKIN:Bang('!HideMeter', 'MeterProgressFill')
    end
end

local function update_artist_ui(artist)
    if trim(artist) == '' then
        SKIN:Bang('!HideMeter', 'MeterArtist')
    else
        SKIN:Bang('!ShowMeter', 'MeterArtist')
    end
end

local function apply_cache(values)
    if not values then
        set_hidden()
        return
    end
    if values.Status ~= 'OK' or trim(values.Title or '') == '' then
        set_hidden()
        return
    end

    local source_app = trim(values.SourceAppUserModelId or '')
    if not contains_ignore_case(source_app, 'spotify') then
        set_hidden()
        return
    end

    local updated_at_ms = tonumber(values.UpdatedAtUnixMs or '0') or 0
    if updated_at_ms > 0 and updated_at_ms == state.cache_updated_at_ms then
        return
    end

    state.playback_status = trim(values.PlaybackStatus or '')
    state.position_ms = tonumber(values.PositionMs or '0') or 0
    state.duration_ms = tonumber(values.DurationMs or '0') or 0
    state.cache_updated_at_ms = updated_at_ms
    state.snapshot_received_at = os.time()

    SKIN:Bang('!SetVariable', 'NowPlayingTitle', values.Title or '')
    SKIN:Bang('!SetVariable', 'NowPlayingArtist', values.Artist or '')
    set_visible()
    update_artist_ui(values.Artist or '')
    update_progress_ui()
    SKIN:Bang('!UpdateMeter', 'MeterTitle')
    SKIN:Bang('!UpdateMeter', 'MeterArtist')
    SKIN:Bang('!Redraw')
end

local function maybe_start_helper(force)
    local now = os.time()
    if not force and (now - state.last_start_attempt_at) < 10 then
        return
    end

    state.last_start_attempt_at = now
    SKIN:Bang('!CommandMeasure', 'MeasureNowPlayingStarter', 'Run')
end

local function cache_is_stale()
    if state.cache_updated_at_ms <= 0 then
        return true
    end

    local now_ms = os.time() * 1000
    return (now_ms - state.cache_updated_at_ms) > 10000
end

function Initialize()
    state.cache_path = SKIN:GetVariable('CURRENTPATH') .. 'nowplaying-cache.txt'
    SKIN:Bang('!SetVariable', 'NowPlayingTitle', '')
    SKIN:Bang('!SetVariable', 'NowPlayingArtist', '')
    SKIN:Bang('!SetVariable', 'NowPlayingTimeText', '')
    SKIN:Bang('!SetVariable', 'NowPlayingProgressWidth', '0')

    maybe_start_helper(true)
    apply_cache(read_cache_values())
end

function Update()
    if cache_is_stale() then
        maybe_start_helper(false)
    end

    apply_cache(read_cache_values())
    if state.visible then
        update_progress_ui()
        SKIN:Bang('!Redraw')
    end

    return ''
end

function Refresh()
    maybe_start_helper(true)
    apply_cache(read_cache_values())
end
