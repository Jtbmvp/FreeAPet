--!strict
-- Stable hit rectangles; native input state drives a restrained face tint and lip.
-- No looping effects, moving targets, gameplay callbacks or reward assertions.
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local Feedback = {}
local ENTER = 0.10
local RELEASE = 0.14
function Feedback.Bind(button: GuiButton, face: Frame, lip: Frame)
	local alive = true
	local tween: Tween? = nil
	local connections: { RBXScriptConnection } = {}
	local function render()
		if not alive then
			return
		end
		if tween then
			tween:Cancel()
			tween:Destroy()
			tween = nil
		end
		local pressed = button.Interactable and button.GuiState == Enum.GuiState.Press
		local highlighted = button.Interactable
			and (button.GuiState == Enum.GuiState.Hover or GuiService.SelectedObject == button)
		face.BackgroundColor3 = if pressed then Color3.new(0, 0, 0) else Color3.new(1, 1, 1)
		lip.BackgroundTransparency = if pressed then 0.35 else 0.7
		local alpha = if not button.Interactable
			then 0.92
			elseif pressed then 0.84
			elseif highlighted then 0.93
			else 1
		-- Colour-only feedback also serves reduced motion; no scale/lift needs cancelling.
		local duration = if pressed or highlighted then ENTER else RELEASE
		tween = TweenService:Create(
			face,
			TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = alpha }
		)
		tween:Play()
	end
	for _, property in { "GuiState", "Interactable" } do
		table.insert(connections, button:GetPropertyChangedSignal(property):Connect(render))
	end
	table.insert(connections, button.SelectionGained:Connect(render))
	table.insert(connections, button.SelectionLost:Connect(render))
	-- The engine handles supported devices and the player's haptic preference.
	-- Older clients without this optional API keep the same visual/interaction path.
	local effect: HapticEffect? = nil
	local ok = pcall(function()
		effect = Instance.new("HapticEffect")
		local haptic = effect :: HapticEffect
		haptic.Name = "ClickFeedback"
		haptic.Type = Enum.HapticEffectType.UIClick
		haptic.Looped = false
		haptic.Parent = button
		button.PressHapticEffect = haptic
	end)
	if not ok and effect then
		effect:Destroy()
		effect = nil
	end
	button.Destroying:Connect(function()
		alive = false
		if tween then
			tween:Cancel()
			tween:Destroy()
			tween = nil
		end
		for _, connection in connections do
			connection:Disconnect()
		end
	end)
	render()
end
return Feedback
