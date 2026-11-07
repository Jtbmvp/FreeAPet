-- Signal mínimo: o UI dispara sinais, a lógica (Demo ou o teu código) liga-se a eles.
local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _h = {} }, Signal)
end

function Signal:Connect(fn)
	local c = { fn = fn, on = true }
	table.insert(self._h, c)
	return {
		Disconnect = function()
			c.on = false
			local i = table.find(self._h, c)
			if i then table.remove(self._h, i) end
		end,
	}
end

function Signal:Fire(...)
	for _, c in ipairs(table.clone(self._h)) do
		if c.on then task.spawn(c.fn, ...) end
	end
end

function Signal:Destroy() table.clear(self._h) end

return Signal
