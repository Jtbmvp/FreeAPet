-- Layout: ScreenGui + Stage em unidades de design (750x369 = área segura do 844x390 com notch).
--
-- ScreenGui principal:
--   ScreenInsets = DeviceSafeInsets  (respeita notch / barra inferior)
--   IgnoreGuiInset = true            (o design reserva a zona da topbar: gear Settings no canto sup. direito)
-- Se preferires que o HUD comece ABAIXO da topbar do Roblox, põe USE_CORE_INSETS = true
-- (ScreenInsets = CoreUISafeInsets, IgnoreGuiInset = false).
--
-- Stage: Frame com UIScale = min(largura/750, altura/369) e Size = 1/scale, por isso
-- 1 unidade = 1 px do design no telemóvel de referência. Posições usam Scale + AnchorPoint
-- (encostam aos cantos); tamanhos usam Offset e o UIScale adapta a outros telemóveis.
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local Theme = require(script.Parent.Theme)

local Layout = { USE_CORE_INSETS = false, EDGE = 8 }

-- Touch only: phones and bare tablets. Desktops, laptops (touch screen or not) and TVs are not.
function Layout.isMobile()
	if GuiService:IsTenFootInterface() then
		return false
	end
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.MouseEnabled
end

local function newGui(name, order)
	local g = Instance.new("ScreenGui")
	g.Name = name
	g.ResetOnSpawn = false
	g.DisplayOrder = order
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	return g
end

function Layout.mount(options)
	options = options or {}
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Backdrop: cobre o ecrã inteiro (inclui notch) para o escurecimento
	local bd = newGui(options.Name and (options.Name .. "Backdrop") or "FreeAPetBackdrop", options.Order or 9)
	bd.IgnoreGuiInset = true
	pcall(function() bd.ScreenInsets = Enum.ScreenInsets.None end)
	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.BorderSizePixel = 0
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.Size = UDim2.fromScale(1, 1)
	dim.Visible = false
	dim.Parent = bd
	bd.Parent = pg

	local gui = newGui(options.Name or "FreeAPet", options.Order or 10)
	if options.Canvas then
		-- The HTML canvas: fixed size, centred, one global scale, over the whole viewport.
		gui.IgnoreGuiInset = true
		gui.ScreenInsets = Enum.ScreenInsets.None
	elseif Layout.USE_CORE_INSETS then
		gui.IgnoreGuiInset = false
		pcall(function() gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets end)
	else
		gui.IgnoreGuiInset = true
		pcall(function() gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)
	end

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui

	local stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.BackgroundTransparency = 1
	stage.BorderSizePixel = 0
	stage.Parent = root
	local us = Instance.new("UIScale")
	us.Parent = stage

	local env
	local function fit()
		local a = root.AbsoluteSize
		if a.X <= 0 or a.Y <= 0 then return end
		if options.Canvas then
			local c = options.Canvas
			local s = math.min(a.X / c.X, a.Y / c.Y)
			us.Scale = s
			stage.AnchorPoint = Vector2.new(0.5, 0.5)
			stage.Position = UDim2.fromScale(0.5, 0.5)
			stage.Size = UDim2.fromOffset(c.X, c.Y)
			if env then
				env.OverX = (a.X / s - c.X) / 2
				env.OverY = (a.Y / s - c.Y) / 2
				if env.OnFit then env.OnFit(env.OverX, env.OverY) end
			end
			return
		end
		local s = math.min(a.X / Theme.REF.X, a.Y / Theme.REF.Y)
		us.Scale = s
		stage.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	gui.Parent = pg
	env = { Gui = gui, Root = root, Stage = stage, Scale = us, Dim = dim, BackdropGui = bd, OverX = 0, OverY = 0 }
	fit()

	return env
end

-- Tamanho do Stage em unidades de design (>= 750x369 em ecrãs mais largos)
function Layout.stageSize(env)
	return env.Root.AbsoluteSize / env.Scale.Scale
end

return Layout
