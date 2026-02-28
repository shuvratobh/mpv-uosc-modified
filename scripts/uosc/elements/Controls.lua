local Element = require('elements/Element')
local Button = require('elements/Button')
local CycleButton = require('elements/CycleButton')
local ManagedButton = require('elements/ManagedButton')
local Speed = require('elements/Speed')

-- sizing:
--   static - shrink, have highest claim on available space, disappear when there's not enough of it
--   dynamic - shrink to make room for static elements until they reach their ratio_min, then disappear
--   gap - shrink if there's no space left
--   space - expands to fill available space, shrinks as needed
-- scale - `options.controls_size` scale factor.
-- ratio - Width/height ratio of a static or dynamic element.
-- ratio_min Min ratio for 'dynamic' sized element.
---@alias ControlItem {element?: Element; kind: string; sizing: 'space' | 'static' | 'dynamic' | 'gap'; scale: number; ratio?: number; ratio_min?: number; hide: boolean; dispositions?: {[string]: boolean}[]}

---@class Controls : Element
local Controls = class(Element)

function Controls:new() return Class.new(self) --[[@as Controls]] end
function Controls:init()
	Element.init(self, 'controls', {render_order = 6})
	---@type ControlItem[] All control elements serialized from `options.controls`.
	self.controls = {}
	---@type ControlItem[] Only controls that match current dispositions.
	self.layout = {}

	self:init_options()
end

function Controls:destroy()
	self:destroy_elements()
	Element.destroy(self)
end

function Controls:init_options()
	-- Serialize control elements
	-- Fluent System Icons codepoints (matching modernz.lua's icon_theme["fluent"])
	local ic = string.char
	local fi = {
		play         = ic(238,166,143),
		pause        = ic(238,163,140),
		prev         = ic(239,152,167),
		next         = ic(239,149,168),
		first        = ic(238,168,158),  -- rewind (skip to start equivalent)
		last         = ic(238,152,135),  -- forward (skip to end equivalent)
		subtitles    = ic(238,175,141),
		audio        = ic(238,175,139),
		playlist     = ic(238,161,159),
		menu         = ic(238,160,170),
		chapters     = ic(239,133,156),  -- calendar_ltr (bookmark equivalent)
		editions     = ic(239,133,156),  -- same
		stream       = ic(239,160,177),  -- gauge (stream quality)
		open_file    = ic(238,183,182),  -- folder_open
		loop_off     = ic(239,133,178),
		loop_on      = ic(239,133,181),
		shuffle_off  = ic(238,188,188),
		shuffle_on   = ic(238,188,184),
		fullscreen   = ic(239,133,160),
		fullscreen_x = ic(239,133,166),
		speed        = ic(239,160,177),
		jump_back    = ic(238,171,188),  -- jump_10_back
		jump_fwd     = ic(238,172,129),  -- jump_10_forward
		speaker      = ic(238,173,130),  -- volume_high
		hdr          = ic(239,160,177),  -- speed (autoload)
	}

	local shorthands = {
		['play-pause'] = 'cycle:' .. fi.pause .. ':pause:no/yes=' .. fi.play .. '?' .. t('Play/Pause'),
		menu = 'command:' .. fi.menu .. ':script-binding uosc/menu-blurred?' .. t('Menu'),
		subtitles = 'command:' .. fi.subtitles .. ':script-binding uosc/subtitles#sub>0?' .. t('Subtitles'),
		audio = 'command:' .. fi.audio .. ':script-binding uosc/audio#audio>1?' .. t('Audio'),
		['audio-device'] = 'command:' .. fi.speaker .. ':script-binding uosc/audio-device?' .. t('Audio device'),
		video = 'command:' .. fi.stream .. ':script-binding uosc/video#video>1?' .. t('Video'),
		playlist = 'command:' .. fi.playlist .. ':script-binding uosc/playlist?' .. t('Playlist'),
		chapters = 'command:' .. fi.chapters .. ':script-binding uosc/chapters#chapters>0?' .. t('Chapters'),
		['editions'] = 'command:' .. fi.editions .. ':script-binding uosc/editions#editions>1?' .. t('Editions'),
		['stream-quality'] = 'command:' .. fi.stream .. ':script-binding uosc/stream-quality?' .. t('Stream quality'),
		['open-file'] = 'command:' .. fi.open_file .. ':script-binding uosc/open-file?' .. t('Open file'),
		['items'] = 'command:' .. fi.playlist .. ':script-binding uosc/items?' .. t('Playlist/Files'),
		prev = 'command:' .. fi.prev .. ':script-binding uosc/prev?' .. t('Previous'),
		next = 'command:' .. fi.next .. ':script-binding uosc/next?' .. t('Next'),
		first = 'command:' .. fi.first .. ':script-binding uosc/first?' .. t('First'),
		last = 'command:' .. fi.last .. ':script-binding uosc/last?' .. t('Last'),
		['loop-playlist'] = 'cycle:' .. fi.loop_off .. ':loop-playlist:no/inf=' .. fi.loop_on .. '?' .. t('Loop playlist'),
		['loop-file'] = 'cycle:' .. fi.loop_off .. ':loop-file:no/inf=' .. fi.loop_on .. '?' .. t('Loop file'),
		shuffle = 'toggle:' .. fi.shuffle_off .. ':shuffle?' .. t('Shuffle'),
		autoload = 'toggle:' .. fi.hdr .. ':autoload@uosc?' .. t('Autoload'),
		fullscreen = 'cycle:' .. fi.fullscreen .. ':fullscreen:no/yes=' .. fi.fullscreen_x .. '?' .. t('Fullscreen'),
		-- Custom jump shorthands (used in uosc.conf controls line)
		replay_10 = 'command:' .. fi.jump_back .. ':seek -10?-10s',
		forward_10 = 'command:' .. fi.jump_fwd .. ':seek +10?+10s',
	}

	-- Helper: cycle an mpv track forward/backward with wraparound
	local function cycle_track(type, direction)
		local track_list = mp.get_property_native('track-list', {})
		local tracks = {}
		for _, track in ipairs(track_list) do
			if track.type == type then
				tracks[#tracks + 1] = track
			end
		end
		if #tracks == 0 then
			mp.osd_message('No ' .. type .. ' tracks available', 2)
			return
		end
		local current = mp.get_property_number(type, 0) or 0
		local idx = 0
		for i, t in ipairs(tracks) do
			if t.id == current then idx = i; break end
		end
		local new_idx = ((idx - 1 + direction + #tracks) % #tracks) + 1
		local new_track = tracks[new_idx]
		mp.set_property_number(type, new_track.id)
		-- Build display name for OSD
		local label = new_track.title or new_track.lang or ('Track ' .. new_track.id)
		if new_track.lang and new_track.title then
			label = new_track.title .. ' [' .. new_track.lang .. ']'
		end
		local icon = type == 'sub' and '🔤' or '🔊'
		mp.osd_message(icon .. ' ' .. label .. '  (' .. new_idx .. '/' .. #tracks .. ')', 2)
	end

	-- Parse out disposition/config pairs
	local items = {}
	local in_disposition = false
	local current_item = nil
	for c in options.controls:gmatch('.') do
		if not current_item then current_item = {disposition = '', config = ''} end
		if c == '<' and #current_item.config == 0 then
			in_disposition = true
		elseif c == '>' and #current_item.config == 0 then
			in_disposition = false
		elseif c == ',' and not in_disposition then
			items[#items + 1] = current_item
			current_item = nil
		else
			local prop = in_disposition and 'disposition' or 'config'
			current_item[prop] = current_item[prop] .. c
		end
	end
	items[#items + 1] = current_item

	-- Create controls
	self.controls = {}
	for i, item in ipairs(items) do
		local config = shorthands[item.config] and shorthands[item.config] or item.config
		local config_tooltip = split(config, ' *%? *')
		local tooltip = config_tooltip[2]
		config = shorthands[config_tooltip[1]]
			and split(shorthands[config_tooltip[1]], ' *%? *')[1] or config_tooltip[1]
		local config_badge = split(config, ' *# *')
		config = config_badge[1]
		local badge = config_badge[2]
		local parts = split(config, ' *: *')
		local kind, params = parts[1], itable_slice(parts, 2)

		-- Serialize dispositions into OR groups of AND conditions
		---@type {[string]: boolean}[]
		local dispositions = {}
		---@type string[]
		local disposition_props = {}
		for _, or_group in ipairs(comma_split(item.disposition)) do
			local group = {}
			for _, condition in ipairs(split(or_group, ' *+ *')) do
				if #condition > 0 then
					local value = condition:sub(1, 1) ~= '!'
					local name = not value and condition:sub(2) or condition
					if name:sub(1, 4) == 'has_' or itable_has({'idle', 'image', 'audio', 'video', 'stream'}, name) then
						local prop = name:sub(1, 4) == 'has_' and name or 'is_' .. name
						group[prop] = value
					else
						disposition_props[#disposition_props + 1] = name
						group[name] = value
					end
				end
			end
			dispositions[#dispositions + 1] = group
		end

		-- Convert toggles into cycles
		if kind == 'toggle' then
			kind = 'cycle'
			params[#params + 1] = 'no/yes!'
		end

		-- Create a control element
		local control = {dispositions = dispositions, kind = kind}

		if kind == 'space' then
			control.sizing = 'space'
		elseif kind == 'gap' then
			table_assign(control, {sizing = 'gap', scale = 1, ratio = params[1] or 0.3, ratio_min = 0})
		elseif kind == 'command' then
			if #params ~= 2 then
				mp.error(string.format(
					'command button needs 2 parameters, %d received: %s', #params, table.concat(params, '/')
				))
			else
				-- Special handling: subtitle and audio buttons use click/scroll-to-cycle
				local icon = params[1]
				local on_click_fn, on_wheel_up_fn, on_wheel_down_fn
				if icon == fi.subtitles then
					-- Left click: cycle to next subtitle track
					on_click_fn = function() cycle_track('sub', 1) end
					on_wheel_up_fn = function() cycle_track('sub', 1) end
					on_wheel_down_fn = function() cycle_track('sub', -1) end
				elseif icon == fi.audio then
					-- Left click: cycle to next audio track
					on_click_fn = function() cycle_track('audio', 1) end
					on_wheel_up_fn = function() cycle_track('audio', 1) end
					on_wheel_down_fn = function() cycle_track('audio', -1) end
				else
					on_click_fn = function() mp.command(params[2]) end
				end
				local element = Button:new('control_' .. i, {
					render_order = self.render_order,
					icon = icon,
					anchor_id = 'controls',
					on_click = on_click_fn,
					on_wheel_up = on_wheel_up_fn,
					on_wheel_down = on_wheel_down_fn,
					tooltip = tooltip,
					count_prop = 'sub',
				})
				table_assign(control, {element = element, sizing = 'static', scale = 1, ratio = 1})
				if badge then self:register_badge_updater(badge, element) end
			end
		elseif kind == 'cycle' then
			if #params ~= 3 then
				mp.error(string.format(
					'cycle button needs 3 parameters, %d received: %s',
					#params, table.concat(params, '/')
				))
			else
				local state_configs = split(params[3], ' */ *')
				local states = {}

				for _, state_config in ipairs(state_configs) do
					local active = false
					if state_config:sub(-1) == '!' then
						active = true
						state_config = state_config:sub(1, -2)
					end
					local state_params = split(state_config, ' *= *')
					local value, icon = state_params[1], state_params[2] or params[1]
					states[#states + 1] = {value = value, icon = icon, active = active}
				end

				local element = CycleButton:new('control_' .. i, {
					render_order = self.render_order,
					prop = params[2],
					anchor_id = 'controls',
					states = states,
					tooltip = tooltip,
				})
				table_assign(control, {element = element, sizing = 'static', scale = 1, ratio = 1})
				if badge then self:register_badge_updater(badge, element) end
			end
		elseif kind == 'button' then
			if #params ~= 1 then
				mp.error(string.format(
					'managed button needs 1 parameter, %d received: %s', #params, table.concat(params, '/')
				))
			else
				local element = ManagedButton:new('control_' .. i, {
					name = params[1],
					render_order = self.render_order,
					anchor_id = 'controls',
					on_hide = function() self:reflow() end,
				})
				table_assign(control, {element = element, sizing = 'static', scale = 1, ratio = 1})
			end
		elseif kind == 'speed' then
			if not Elements.speed then
				local element = Speed:new({anchor_id = 'controls', render_order = self.render_order})
				local scale = tonumber(params[1]) or 1.0
				table_assign(control, {
					element = element, sizing = 'static', scale = scale, ratio = 1.8,
				})
			else
				msg.error('there can only be 1 speed slider')
			end
		else
			msg.error('unknown element kind "' .. kind .. '"')
			break
		end

		if control.element then
			for _, prop in ipairs(disposition_props) do
				control.element:observe_mp_property(prop, function() self:reflow() end)
			end
		end
		self.controls[#self.controls + 1] = control
	end

	self:reflow()
end

function Controls:reflow()
	-- Populate the layout only with items that are not hidden and match current disposition
	self.layout = {}
	for _, control in ipairs(self.controls) do
		local matches = false
		local conditions_num = 0

		-- Check against OR groups of AND conditions
		for _, group in pairs(control.dispositions) do
			local group_matches = true
			for prop, value in pairs(group) do
				conditions_num = conditions_num + 1
				---@type boolean
				local current_value
				if prop:sub(1, 4) == 'has_' or prop:sub(1, 3) == 'is_' then
					current_value = state[prop]
				else
					current_value = mp.get_property_bool(prop, false)
				end
				if current_value ~= value then
					group_matches = false
					break
				end
			end
			if group_matches then
				matches = true
				break
			end
		end

		if conditions_num == 0 then matches = true end
		local show = matches and (not control.element or control.element.hide ~= true)
		if control.element then control.element.enabled = show end
		if show then self.layout[#self.layout + 1] = control end
	end

	self:update_dimensions()
	Elements:trigger('controls_reflow')
end

---@param badge string
---@param element Element An element that supports `badge` property.
function Controls:register_badge_updater(badge, element)
	local prop_and_limit = split(badge, ' *> *')
	local prop, limit = prop_and_limit[1], tonumber(prop_and_limit[2] or -1)
	local observable_name, serializer, is_external_prop = prop, nil, false

	if itable_index_of({'sub', 'audio', 'video'}, prop) then
		observable_name = 'track-list'
		serializer = function(value)
			local count = 0
			for _, track in ipairs(value) do if track.type == prop then count = count + 1 end end
			return count
		end
	else
		local parts = split(prop, '@')
		-- Support both new `prop@owner` and old `@prop` syntaxes
		if #parts > 1 then prop, is_external_prop = parts[1] ~= '' and parts[1] or parts[2], true end
		serializer = function(value) return value and (type(value) == 'table' and #value or tostring(value)) or nil end
	end

	local function handler(_, value)
		local new_value = serializer(value) --[[@as nil|string|integer]]
		local value_number = tonumber(new_value)
		if value_number then new_value = value_number > limit and value_number or nil end
		element.badge = new_value
		request_render()
	end

	if is_external_prop then
		element['on_external_prop_' .. prop] = function(_, value) handler(prop, value) end
	else
		element:observe_mp_property(observable_name, handler)
	end
end

function Controls:get_visibility()
	return Elements:v('speed', 'dragging') and 1 or Elements:maybe('timeline', 'get_is_hovered')
		and -1 or Element.get_visibility(self)
end

function Controls:update_dimensions()
	local window_border = Elements:v('window_border', 'size', 0)
	local size = round(options.controls_size * state.scale)
	local spacing = round(options.controls_spacing * state.scale)
	local margin = round(options.controls_margin * state.scale)
	self.size = size
	self.margin = margin

	-- Disable when not enough space
	local available_space = display.height - window_border * 2 - Elements:v('top_bar', 'size', 0)
		- Elements:v('timeline', 'size', 0)
	self.enabled = available_space > size + 10

	-- Reset hide/enabled flags
	for c, control in ipairs(self.layout) do
		control.hide = false
		if control.element then control.element.enabled = self.enabled end
	end

	if not self.enabled then return end

	-- Container
	self.bx = display.width - window_border - margin
	self.by = display.height - window_border - margin
	self.ax, self.ay = window_border + margin, self.by - size - margin

	-- Controls
	local available_width, statics_width = self.bx - self.ax, 0
	local min_content_width = statics_width
	local max_dynamics_width, dynamic_units, spaces, gaps = 0, 0, 0, 0

	-- Calculate statics_width, min_content_width, and count spaces & gaps
	for c, control in ipairs(self.layout) do
		if control.sizing == 'space' then
			spaces = spaces + 1
		elseif control.sizing == 'gap' then
			gaps = gaps + control.scale * control.ratio
		elseif control.sizing == 'static' then
			local width = size * control.scale * control.ratio + (c ~= #self.layout and spacing or 0)
			statics_width = statics_width + width
			min_content_width = min_content_width + width
		elseif control.sizing == 'dynamic' then
			local spacing = (c ~= #self.layout and spacing or 0)
			statics_width = statics_width + spacing
			min_content_width = min_content_width + size * control.scale * control.ratio_min + spacing
			max_dynamics_width = max_dynamics_width + size * control.scale * control.ratio
			dynamic_units = dynamic_units + control.scale * control.ratio
		end
	end

	-- Hide & disable elements in the middle until we fit into available width
	if min_content_width > available_width then
		local i = math.ceil(#self.layout / 2 + 0.1)
		for a = 0, #self.layout - 1, 1 do
			i = i + (a * (a % 2 == 0 and 1 or -1))
			local control = self.layout[i]

			if control.sizing ~= 'gap' and control.sizing ~= 'space' then
				control.hide = true
				if control.element then control.element.enabled = false end
				if control.sizing == 'static' then
					local width = size * control.scale * control.ratio
					min_content_width = min_content_width - width - spacing
					statics_width = statics_width - width - spacing
				elseif control.sizing == 'dynamic' then
					statics_width = statics_width - spacing
					min_content_width = min_content_width - size * control.scale * control.ratio_min - spacing
					max_dynamics_width = max_dynamics_width - size * control.scale * control.ratio
					dynamic_units = dynamic_units - control.scale * control.ratio
				end

				if min_content_width < available_width then break end
			end
		end
	end

	-- Lay out the elements
	local current_x = self.ax
	local width_for_dynamics = available_width - statics_width
	local empty_space_width = width_for_dynamics - max_dynamics_width
	local width_for_gaps = math.min(empty_space_width, size * gaps)
	local individual_space_width = spaces > 0 and ((empty_space_width - width_for_gaps) / spaces) or 0

	for c, control in ipairs(self.layout) do
		if not control.hide then
			local sizing, element, scale, ratio = control.sizing, control.element, control.scale, control.ratio
			local width, height = 0, 0

			if sizing == 'space' then
				if individual_space_width > 0 then width = individual_space_width end
			elseif sizing == 'gap' then
				if width_for_gaps > 0 then width = width_for_gaps * (ratio / gaps) end
			elseif sizing == 'static' then
				height = size * scale
				width = height * ratio
			elseif sizing == 'dynamic' then
				height = size * scale
				width = max_dynamics_width < width_for_dynamics
					and height * ratio or width_for_dynamics * ((scale * ratio) / dynamic_units)
			end

			local bx = current_x + width
			if element then element:set_coordinates(round(current_x), round(self.by - height), bx, self.by) end
			current_x = element and bx + spacing or bx
		end
	end

	Elements:update_proximities()
	request_render()
end

function Controls:on_dispositions() self:reflow() end
function Controls:on_display() self:update_dimensions() end
function Controls:on_prop_border() self:update_dimensions() end
function Controls:on_prop_title_bar() self:update_dimensions() end
function Controls:on_prop_fullormaxed() self:update_dimensions() end
function Controls:on_timeline_enabled() self:update_dimensions() end

function Controls:destroy_elements()
	for _, control in ipairs(self.controls) do
		if control.element then control.element:destroy() end
	end
end

function Controls:on_options()
	self:destroy_elements()
	self:init_options()
end

return Controls
