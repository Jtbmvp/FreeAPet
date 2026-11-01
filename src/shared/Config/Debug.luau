--!strict
-- Debug commands (give money, force day reset, set growth, free teleport).
-- Only ever active in Studio; set enabled = false to turn them off there too.

local RunService = game:GetService("RunService")

local Debug = {
	enabled = RunService:IsStudio(),
}

return Debug
