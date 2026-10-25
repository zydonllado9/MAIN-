-- Slingshot setup for the Slingshot Phase 1 kit. Run it once in Roblox Studio:
--   1. Import Slingshot.fbx (Home -> Import 3D) and click the model so it's selected.
--   2. Paste this whole file into the Command Bar (View -> Command Bar) and press Enter.
-- It names the model "Slingshot", gives each piece its Roblox colour and material,
-- and adds the LaunchPoint part and LeftTip / RightTip band attachments.

local Selection = game:GetService("Selection")

local model = Selection:Get()[1]
if model and not model:IsA("Model") then
	model = model:FindFirstAncestorOfClass("Model")
end
model = model or workspace:FindFirstChild("Slingshot")
if not model then
	error("Select the imported slingshot model first, then run this again.")
end

local parts = {}
for _, d in model:GetDescendants() do
	if d:IsA("BasePart") and d.Name ~= "LaunchPoint" then
		parts[d.Name:lower()] = d
	end
end
local function find(key: string): BasePart?
	for name, part in parts do
		if string.find(name, key, 1, true) then
			return part
		end
	end
	return nil
end

-- Leather only exists in newer Studio versions; Fabric is the fallback.
local leather = Enum.Material.Fabric
pcall(function()
	leather = (Enum.Material :: any).Leather
end)

local looks = {
	base = { Enum.Material.Slate, Color3.fromRGB(128, 128, 136) },
	rocks = { Enum.Material.Rock, Color3.fromRGB(100, 102, 108) },
	stem = { Enum.Material.Wood, Color3.fromRGB(140, 90, 52) },
	fork = { Enum.Material.Wood, Color3.fromRGB(140, 90, 52) },
	grip = { leather, Color3.fromRGB(120, 34, 28) },
	binding = { Enum.Material.Fabric, Color3.fromRGB(214, 186, 130) },
	tipleft = { Enum.Material.Metal, Color3.fromRGB(255, 190, 60) },
	tipright = { Enum.Material.Metal, Color3.fromRGB(255, 190, 60) },
}
for key, look in looks do
	local part = find(key)
	if part then
		part.Material = look[1]
		part.Color = look[2]
	end
end
for _, part in parts do
	part.Anchored = true
end

-- Band attachments at the centre of each gold ring.
local tips = {}
for _, info in { { "tipleft", "LeftTip" }, { "tipright", "RightTip" } } do
	local ring = find(info[1])
	if not ring then
		error(`Couldn't find the {info[1]} piece. Re-import with "Merge Meshes" turned off.`)
	end
	local attachment = ring:FindFirstChild(info[2]) or Instance.new("Attachment")
	attachment.Name = info[2]
	attachment.Position = Vector3.zero
	attachment.Parent = ring
	table.insert(tips, ring.Position)
end

-- Ammo rests between the rings. Forward is "up x (left -> right)", so the
-- LaunchPoint's front face points where the slingshot shoots.
local left, right = tips[1], tips[2]
local across = Vector3.new(right.X - left.X, 0, right.Z - left.Z).Unit
local forward = Vector3.yAxis:Cross(across)
local rest = (left + right) / 2 - Vector3.new(0, 0.3, 0)

local old = model:FindFirstChild("LaunchPoint")
if old then
	old:Destroy()
end
local launchPoint = Instance.new("Part")
launchPoint.Name = "LaunchPoint"
launchPoint.Size = Vector3.new(0.5, 0.5, 0.5)
launchPoint.CFrame = CFrame.lookAt(rest, rest + forward)
launchPoint.Transparency = 1
launchPoint.Anchored = true
launchPoint.CanCollide = false
launchPoint.CanQuery = false
launchPoint.CanTouch = false
launchPoint.Parent = model

model.Name = "Slingshot"
model.PrimaryPart = find("base") or model.PrimaryPart
model.Parent = workspace
Selection:Set({ model })
print("Slingshot is ready. Move or rotate it where you want it, then press Play.")
