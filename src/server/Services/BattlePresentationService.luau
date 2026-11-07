--!strict
-- Replicate one reviewed capsule template independently of map streaming.
-- No asset fetch, animation upload, gameplay state or original geometry edits.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Service = {}
function Service.Start()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets and assets:FindFirstChild("BattleCapsule") then
		return
	end
	local imports = ServerStorage:FindFirstChild("MapV3Imports")
	local source = imports and imports:FindFirstChild("asset_82152145130743")
	if
		not source
		or not source:IsA("Model")
		or source:GetAttribute("FaP_SourceAssetId") ~= "82152145130743"
		or source:GetAttribute("FaP_SourceSHA256") ~= "3f08246c02d7f763f128918a11b128172522762938da57f6b15f220fe2092808"
		or source:GetAttribute("FaP_OriginalLogicalJointsRestored") ~= 5
	then
		warn("[BattlePresentation] Reviewed original capsule unavailable; client fallback stays explicit")
		return
	end
	local copy = source:Clone()
	for _, item in copy:GetDescendants() do
		if item:IsA("LuaSourceContainer") or item:IsA("PackageLink") then
			item:Destroy()
		end
	end
	copy.Name = "BattleCapsule"
	if not assets then
		assets = Instance.new("Folder")
		assets.Name = "Assets"
		assets.Parent = ReplicatedStorage
	end
	copy.Parent = assets
end
return Service
