local State = {
	last_fetch_at = 0,
	cache_path = nil,
	fetch_script_path = nil
}

local function trim(s)
	return (s or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function log(message)
	SKIN:Bang('!Log', 'NotionAssignments: ' .. message)
end

local function quoted_path(path)
	return '"' .. tostring(path or '') .. '"'
end

local function file_exists(path)
	local handle = io.open(path, 'rb')
	if handle then
		handle:close()
		return true
	end
	return false
end

local function read_file(path)
	local handle = io.open(path, 'rb')
	if not handle then
		return nil
	end

	local content = handle:read('*a')
	handle:close()
	if not content then
		return nil
	end

	if content:sub(1, 3) == string.char(239, 187, 191) then
		content = content:sub(4)
	end

	return content
end

local function set_loading()
	SKIN:Bang('!SetVariable', 'VisibleItems', '1')
	SKIN:Bang('!SetVariable', 'Item1Title', 'Loading assignments...')
	SKIN:Bang('!SetVariable', 'Item1Meta', '')
	SKIN:Bang('!SetVariable', 'Item1Color', SKIN:GetVariable('ColorText', '255,255,255'))
	SKIN:Bang('!SetVariable', 'Item1Url', '')
	SKIN:Bang('!UpdateMeterGroup', 'AssignmentData')
	SKIN:Bang('!Redraw')
end

local function clear_items(max_items)
	for i = 1, max_items do
		SKIN:Bang('!SetVariable', 'Item' .. i .. 'Title', '')
		SKIN:Bang('!SetVariable', 'Item' .. i .. 'Meta', '')
		SKIN:Bang('!SetVariable', 'Item' .. i .. 'Color', SKIN:GetVariable('ColorText', '255,255,255'))
		SKIN:Bang('!SetVariable', 'Item' .. i .. 'Url', '')
	end
end

local function apply_cache()
	local raw = read_file(State.cache_path)
	if not raw or trim(raw) == '' then
		set_loading()
		return
	end

	local vars = {}
	for line in raw:gmatch('[^\r\n]+') do
		local key, value = line:match('^([^=]+)=(.*)$')
		if key then
			vars[trim(key)] = value or ''
		end
	end

	local max_items = tonumber(SKIN:GetVariable('NumOfItems', '12')) or 12
	clear_items(max_items)

	local status = trim(vars.Status or '')
	if status == 'OK' then
		local visible = tonumber(vars.VisibleItems or '0') or 0
		if visible < 1 then
			visible = 1
		end
		SKIN:Bang('!SetVariable', 'VisibleItems', tostring(visible))

		for i = 1, max_items do
			local title = vars['Item' .. i .. 'Title']
			if title then
				SKIN:Bang('!SetVariable', 'Item' .. i .. 'Title', title)
				SKIN:Bang('!SetVariable', 'Item' .. i .. 'Meta', vars['Item' .. i .. 'Meta'] or '')
				SKIN:Bang('!SetVariable', 'Item' .. i .. 'Color', vars['Item' .. i .. 'Color'] or SKIN:GetVariable('ColorText', '255,255,255'))
				SKIN:Bang('!SetVariable', 'Item' .. i .. 'Url', vars['Item' .. i .. 'Url'] or '')
			end
		end
	elseif status == 'ERROR' then
		SKIN:Bang('!SetVariable', 'VisibleItems', '1')
		SKIN:Bang('!SetVariable', 'Item1Title', vars.ErrorMessage or 'Could not fetch assignments.')
		SKIN:Bang('!SetVariable', 'Item1Meta', '')
		SKIN:Bang('!SetVariable', 'Item1Color', SKIN:GetVariable('ColorText', '255,255,255'))
		SKIN:Bang('!SetVariable', 'Item1Url', '')
	else
		set_loading()
		return
	end

	SKIN:Bang('!UpdateMeterGroup', 'AssignmentData')
	SKIN:Bang('!Redraw')
end

local function fetch_assignments()
	local token = trim(SKIN:GetVariable('NotionIntegrationToken', ''))
	local data_source_id = trim(SKIN:GetVariable('NotionDataSourceId', ''))
	local notion_version = trim(SKIN:GetVariable('NotionVersion', '2026-03-11'))
	local page_size = tonumber(SKIN:GetVariable('NumOfItems', '12')) or 12

	if token == '' or data_source_id == '' then
		log('Missing Notion token or data source ID.')
		return false
	end

	local command = table.concat({
		'powershell.exe',
		'-NoProfile',
		'-ExecutionPolicy', 'Bypass',
		'-File', quoted_path(State.fetch_script_path),
		'-Token', quoted_path(token),
		'-DataSourceId', quoted_path(data_source_id),
		'-OutFile', quoted_path(State.cache_path),
		'-NotionVersion', quoted_path(notion_version),
		'-PageSize', tostring(page_size)
	}, ' ')

	local ok = os.execute(command)
	if ok == 0 or ok == true then
		State.last_fetch_at = os.time()
		return true
	end

	log('Fetch command failed: ' .. tostring(ok))
	return false
end

function Initialize()
	local resources_path = SKIN:GetVariable('@')
	State.cache_path = resources_path .. 'Cache\\AssignmentsCache.txt'
	State.fetch_script_path = resources_path .. 'Measures\\FetchAssignments.ps1'
	set_loading()

	if file_exists(State.fetch_script_path) then
		fetch_assignments()
	end
	apply_cache()
end

function Update()
	local interval = tonumber(SKIN:GetVariable('RefreshIntervalSeconds', '900')) or 900
	if State.last_fetch_at == 0 or (os.time() - State.last_fetch_at) >= interval then
		if file_exists(State.fetch_script_path) and fetch_assignments() then
			apply_cache()
		elseif file_exists(State.cache_path) then
			apply_cache()
		end
	end

	return 'Assignments'
end

function Refresh()
	if file_exists(State.fetch_script_path) and fetch_assignments() then
		apply_cache()
	else
		apply_cache()
	end
end
