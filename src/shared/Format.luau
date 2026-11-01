--!strict
-- Number formatting shared by server labels and client UI.

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

-- 950 -> "950", 1234 -> "1.23K", 0.25 -> "0.25"
function Format.Short(value: number): string
	if value < 10 then
		return (string.format("%.2f", value):gsub("%.?0+$", ""))
	end
	local index = 1
	while value >= 1000 and index < #SUFFIXES do
		value /= 1000
		index += 1
	end
	local text = if value >= 100 then string.format("%d", value) else string.format("%.3g", value)
	return text .. SUFFIXES[index]
end

-- 45 -> "45s", 90 -> "1m 30s", 300 -> "5m", 4500 -> "1h 15m"
function Format.Duration(seconds: number): string
	local total = math.max(0, math.ceil(seconds))
	local hours, minutes, secs = total // 3600, (total % 3600) // 60, total % 60
	if hours > 0 then
		return if minutes > 0 then `{hours}h {minutes}m` else `{hours}h`
	elseif minutes > 0 then
		return if secs > 0 then `{minutes}m {secs}s` else `{minutes}m`
	end
	return `{secs}s`
end

return Format
