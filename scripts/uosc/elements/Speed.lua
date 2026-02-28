local Element = require('elements/Element')

---@class Speed : Element
local Speed = class(Element)

---@param props? ElementProps
function Speed:new(props) return Class.new(self, props) --[[@as Speed]] end
function Speed:init(props)
	Element.init(self, 'speed', props)
	self.width = 0
	self.height = 0
	self.font_size = 0
	---@type false
	self.dragging = false
end

function Speed:get_visibility()
	return Element.get_visibility(self)
end

function Speed:on_coordinates()
	self.height, self.width = self.by - self.ay, self.bx - self.ax
	self.font_size = round(self.height * 0.44 * options.font_scale)
end
function Speed:on_options() self:on_coordinates() end

function Speed:speed_step(speed, up)
	if options.speed_step_is_factor then
		if up then
			return speed * options.speed_step
		else
			return speed * 1 / options.speed_step
		end
	else
		if up then
			return speed + options.speed_step
		else
			return speed - options.speed_step
		end
	end
end

function Speed:handle_wheel_up() mp.set_property_native('speed', self:speed_step(state.speed, true)) end
function Speed:handle_wheel_down() mp.set_property_native('speed', self:speed_step(state.speed, false)) end

function Speed:render()
	local visibility = self:get_visibility()
	local opacity = visibility

	if opacity <= 0 then return end

	-- Left click: increase speed by 0.1x
	cursor:zone('primary_click', self, function()
		mp.set_property_native('speed', self:speed_step(state.speed, true))
	end)
	-- Right click: reset speed to 1x
	cursor:zone('secondary_click', self, function()
		mp.set_property_native('speed', 1)
	end)
	cursor:zone('wheel_down', self, function() self:handle_wheel_down() end)
	cursor:zone('wheel_up', self, function() self:handle_wheel_up() end)

	local ass = assdraw.ass_new()

	-- Button background
	ass:rect(self.ax, self.ay, self.bx, self.by, {
		color = bg,
		radius = state.radius,
		opacity = opacity * math.max(config.opacity.speed, 0.5),
	})

	-- Speed text label
	local speed_text = (round(state.speed * 100) / 100) .. 'x'
	local half_x = self.ax + self.width / 2
	local half_y = self.ay + self.height / 2
	ass:txt(half_x, half_y, 5, speed_text, {
		size = self.font_size,
		color = bgt,
		bold = true,
		border = options.text_border * state.scale,
		border_color = bg,
		opacity = opacity,
	})

	return ass
end

return Speed
