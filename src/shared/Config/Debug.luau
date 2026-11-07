--!strict
-- Debug commands (give pets, force day reset, toggle battles).
-- Only ever active in Studio; set enabled = false to turn them off there too.

local RunService = game:GetService("RunService")

local Debug = {
	enabled = RunService:IsStudio(),
}

return Debug
