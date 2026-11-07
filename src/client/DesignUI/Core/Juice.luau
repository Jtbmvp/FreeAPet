-- Juice: decorative GUI effects shared by the pop-ups, Research and Pets.
-- Everything here is presentation only and cleans up after itself.
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local Core = script.Parent
local Html = require(Core.Html)
local Motion = require(Core.Motion)
local Icons = Html.Icons

local Juice = {}

local WHITE = Color3.new(1, 1, 1)

local function color(c)
	return Html.color(c or WHITE)
end

function Juice.image(parent, key, o)
	local i = Html.make("ImageLabel", parent, {
		Name = o.name or key,
		Image = Icons[key] or "",
		ImageColor3 = color(o.color),
		ImageTransparency = o.alpha and (1 - o.alpha) or 0,
		AnchorPoint = o.anchor or Vector2.new(0.5, 0.5),
		Position = o.pos or UDim2.fromScale(0.5, 0.5),
		Size = o.size or UDim2.fromOffset(o.w or 100, o.h or o.w or 100),
		ZIndex = o.z or 1,
	})
	return i
end

-- PreloadAsync fetches but does not decode: each image is also drawn once, almost invisible and
-- kept for the session, so a pop-up's icon is already there the first time it appears.
function Juice.preload(parent, keys)
	local holder = Html.make("Frame", parent, { Name = "Preload", Size = UDim2.fromOffset(1, 1) })
	local images = {}
	for _, key in keys do
		if Icons[key] then
			table.insert(images, Html.make("ImageLabel", holder, { Image = Icons[key], Size = UDim2.fromOffset(1, 1), ImageTransparency = 0.99 }))
		end
	end
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(images)
		end)
	end)
end

-- Soft round light; pulses between alpha and alpha - pulse when asked to.
function Juice.glow(parent, o)
	local i = Juice.image(parent, "fx_glow", o)
	if o.pulse then
		Motion.loop(i, { ImageTransparency = 1 - (o.alpha or 1) + o.pulse }, o.period or 1.2)
	end
	return i
end

-- Sun rays turning slowly.
function Juice.rays(parent, o)
	local i = Juice.image(parent, "fx_rays", o)
	Motion.spin(i, o.period or 16)
	return i
end

-- A ring (or hexagon when o.key says so) that grows and fades once.
function Juice.ripple(parent, pos, o)
	if Motion.Reduced then
		return
	end
	local from, to, life = o.from or 40, o.to or 200, o.life or 0.6
	local aspect = o.aspect or 1
	local i = Juice.image(parent, o.key or "fx_ring", {
		pos = pos,
		color = o.color,
		alpha = o.alpha or 0.9,
		z = o.z,
		size = UDim2.fromOffset(from, from * aspect),
	})
	local tw = TweenService:Create(i, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(to, to * aspect),
		ImageTransparency = 1,
	})
	tw.Completed:Once(function()
		i:Destroy()
	end)
	tw:Play()
end

-- Sparkles flying out of a point.
function Juice.burst(parent, pos, o)
	if Motion.Reduced then
		return
	end
	local count, radius, life = o.count or 10, o.radius or 160, o.life or 0.7
	local size = o.spark or 34
	for n = 1, count do
		local angle = (n / count) * math.pi * 2 + math.random() * 0.5
		local reach = radius * (0.6 + math.random() * 0.5)
		local s = size * (0.7 + math.random() * 0.6)
		local i = Juice.image(parent, "fx_sparkle", {
			pos = pos,
			color = o.color,
			z = o.z,
			size = UDim2.fromOffset(s, s),
		})
		i.Rotation = math.random(0, 90)
		local target = pos + UDim2.fromOffset(math.cos(angle) * reach, math.sin(angle) * reach)
		local tw = TweenService:Create(i, TweenInfo.new(life, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = target,
			ImageTransparency = 1,
			Rotation = i.Rotation + 90,
			Size = UDim2.fromOffset(s * 0.4, s * 0.4),
		})
		tw.Completed:Once(function()
			i:Destroy()
		end)
		tw:Play()
	end
end

-- Keeps twinkling sparkles inside parent while keepGoing() is true.
function Juice.twinkle(parent, w, h, o)
	if Motion.Reduced then
		return
	end
	local keepGoing = o.keepGoing or function()
		return true
	end
	task.spawn(function()
		while parent.Parent do
			task.wait((o.every or 0.45) * (0.6 + math.random() * 0.8))
			if keepGoing() then
				local s = (o.spark or 26) * (0.6 + math.random() * 0.8)
				local i = Juice.image(parent, "fx_sparkle", {
					pos = UDim2.fromOffset(math.random(0, w), math.random(0, h)),
					color = o.color,
					alpha = 0,
					z = o.z,
					size = UDim2.fromOffset(s * 0.2, s * 0.2),
				})
				local rise = TweenService:Create(i, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					ImageTransparency = 0.1,
					Size = UDim2.fromOffset(s, s),
					Rotation = 45,
				})
				rise.Completed:Once(function()
					local fall = TweenService:Create(i, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
						ImageTransparency = 1,
						Size = UDim2.fromOffset(s * 0.2, s * 0.2),
						Rotation = 90,
					})
					fall.Completed:Once(function()
						i:Destroy()
					end)
					fall:Play()
				end)
				rise:Play()
			end
		end
	end)
end

return Juice
