--[[
	The course visuals, built locally on each client from CourseLayout.

	RunSim (shared) decides what gets hit; this module only draws it:
	  * Only the stretch of course near the player is parented to Workspace
	    (SetView). Everything else waits with Parent = nil, which keeps the part
	    count and render cost low, especially on phones.
	  * Smashed blocks are flung with real physics, but only up to the quality
	    budget (Quality.Current.MaxDebris); beyond that they just vanish.
	  * Moving hazards are animated from the same time functions RunSim uses.
	Reset() puts everything back for the next launch.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local CourseLayout = require(ReplicatedStorage.Shared.CourseLayout)
local Quality = require(script.Parent.Quality)
local Widgets = require(script.Parent.Widgets)

local Course = {}
Course.__index = Course

local H = Config.Hazards
local UP = CFrame.Angles(0, 0, math.pi / 2) -- turns a cylinder's axis upright

local rng = Random.new()

local bucketOf = CourseLayout.BucketOf

local function newPart(props): BasePart
	local p = Instance.new(props.ClassName or "Part") :: BasePart
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		if key ~= "ClassName" and key ~= "Parent" then
			(p :: any)[key] = value
		end
	end
	p.Parent = props.Parent
	return p
end

local function cylinderBetween(a: Vector3, b: Vector3): CFrame
	local dir = (b - a).Unit
	local up = if math.abs(dir.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis
	local side = up:Cross(dir).Unit
	return CFrame.fromMatrix((a + b) / 2, dir, dir:Cross(side))
end

local function tntLabel(part: BasePart)
	-- One label on the face that looks back at the slingshot.
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 25
	gui.Parent = part
	Widgets.Label({
		Text = "TNT",
		Size = UDim2.fromScale(1, 0.5),
		Position = UDim2.fromScale(0, 0.25),
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromRGB(245, 245, 245),
		TextColor3 = Color3.fromRGB(30, 30, 30),
		StrokeThickness = 0,
		Parent = gui,
	})
end

function Course.new()
	local self = setmetatable({}, Course)
	self.Layout = CourseLayout.Get()
	self.Folder = Instance.new("Folder")
	self.Folder.Name = "LocalCourse"
	self.Folder.Parent = Workspace
	self.Blocks = {} -- [blockId] = entry
	self.BlockList = {}
	self.BlockBuckets = {} -- [bucket] = { entry }
	self.ItemBuckets = {} -- [bucket] = { item }
	self.Items = {} -- every item, for Reset
	self.Stars = {} -- [id] = item
	self.Rings = {}
	self.Pickups = {}
	self.Barriers = {}
	self.Pads = {}
	self.Flung = {}
	self.Flashing = {} -- [entry] = true while a block shows a flash colour
	self.Ready = false
	self.ViewLow = nil
	self.ViewHigh = nil
	self.ViewCenter = 0
	Quality.OnChanged(function()
		self:_applyQuality()
	end)
	return self
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

function Course:_buildBlock(data)
	local zone = Config.Zones[data.Zone]
	local size = Config.BlockSize - 0.08
	local part = newPart({
		Name = data.Kind,
		Size = Vector3.new(size, size, size),
		CFrame = CFrame.new(data.Position),
		CanCollide = true,
		CastShadow = Quality.Current.BlockShadows,
	})

	if data.Kind == "Gold" then
		part.Color = Color3.fromRGB(255, 196, 40)
		part.Material = Enum.Material.Neon
	elseif data.Kind == "TNT" then
		part.Color = Color3.fromRGB(220, 40, 40)
		tntLabel(part)
	elseif data.Kind == "Armor" then
		part.Color = Color3.fromRGB(74, 78, 92)
		part.Material = Enum.Material.DiamondPlate
		part.Reflectance = 0.12
	elseif data.Kind == "Ice" then
		part.Color = Color3.fromRGB(176, 226, 255)
		part.Material = Enum.Material.Glass
		part.Transparency = 0.25
		part.Reflectance = 0.15
	else
		local base = zone.BlockColors[data.ColorIndex] or zone.BlockColors[1]
		-- Deterministic per-block shade so walls look hand-built.
		local shade = ((data.Id * 37) % 11 - 5) / 60
		part.Color = if shade >= 0 then Widgets.Lighten(base, shade) else Widgets.Darken(base, -shade)
		part.Material = zone.BlockMaterial
	end

	local entry = {
		Data = data,
		Part = part,
		CFrame = part.CFrame,
		Color = part.Color,
		Transparency = part.Transparency,
		Broken = false,
		Hidden = false,
		Bucket = bucketOf(-data.Position.Z),
	}
	self.Blocks[data.Id] = entry
	table.insert(self.BlockList, entry)
	local list = self.BlockBuckets[entry.Bucket]
	if not list then
		list = {}
		self.BlockBuckets[entry.Bucket] = list
	end
	table.insert(list, entry)
end

-- Registers an item (a Model or Part) to be shown when its spot is in view.
function Course:_addItem(kind: string, instance: Instance, position: Vector3, extra: { [string]: any }?)
	local item = extra or {}
	item.Kind = kind
	item.Instance = instance
	item.Position = position
	item.Hidden = false
	item.Bucket = bucketOf(-position.Z)
	local list = self.ItemBuckets[item.Bucket]
	if not list then
		list = {}
		self.ItemBuckets[item.Bucket] = list
	end
	table.insert(list, item)
	table.insert(self.Items, item)
	return item
end

function Course:_buildStar(data)
	local ball = newPart({
		Name = "Star",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3, 3, 3),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 214, 40),
		CFrame = CFrame.new(data.Position),
	})
	local billboard = Widgets.new("BillboardGui", {
		Size = UDim2.new(8, 0, 8, 0),
		LightInfluence = 0,
		MaxDistance = 400,
		Parent = ball,
	})
	Widgets.Label({ Text = "⭐", Size = UDim2.fromScale(1, 1), StrokeThickness = 0, Parent = billboard })
	self.Stars[data.Id] = self:_addItem("Star", ball, data.Position, { Part = ball })
end

function Course:_buildRing(data)
	local model = Instance.new("Model")
	model.Name = if data.Big then "Gate" else "Ring"
	local radius = if data.Big then Config.BigRingRadius else Config.RingRadius
	local count = if data.Big then 18 else 14
	local chord = 2 * radius * math.sin(math.pi / count) + 0.4
	local segments = {}
	for i = 1, count do
		local angle = (i / count) * math.pi * 2
		local color = if data.Big
			then (if i % 2 == 0 then Color3.fromRGB(255, 60, 200) else Color3.fromRGB(0, 230, 255))
			else Color3.fromRGB(0, 230, 255)
		local segment = newPart({
			Name = "RingSegment",
			Material = Enum.Material.Neon,
			Color = color,
			Size = Vector3.new(1.2, chord, 1.2),
			CFrame = CFrame.new(data.Position + Vector3.new(math.cos(angle) * radius, math.sin(angle) * radius, 0)) * CFrame.Angles(0, 0, angle),
			Parent = model,
		})
		table.insert(segments, { Part = segment, Color = color })
	end
	self.Rings[data.Id] = self:_addItem("Ring", model, data.Position, { Segments = segments })
end

function Course:_buildPickup(data)
	local ability = Config.Abilities[data.Kind]
	local model = Instance.new("Model")
	model.Name = "PowerUp_" .. data.Kind
	local core = newPart({
		Name = "Core",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.6, 2.6, 2.6),
		Material = Enum.Material.Neon,
		Color = ability.Color,
		CFrame = CFrame.new(data.Position),
		Parent = model,
	})
	local shell = newPart({
		Name = "Shell",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(5.4, 5.4, 5.4),
		Material = Enum.Material.ForceField,
		Color = ability.Color,
		CFrame = CFrame.new(data.Position),
		Parent = model,
	})
	local light = Instance.new("PointLight")
	light.Color = ability.Color
	light.Range = 12
	light.Brightness = 2
	light.Parent = core
	local billboard = Widgets.new("BillboardGui", {
		Size = UDim2.new(5, 0, 5, 0),
		StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0),
		LightInfluence = 0,
		MaxDistance = 260,
		Parent = core,
	})
	Widgets.Label({ Text = ability.Icon, Size = UDim2.fromScale(1, 1), StrokeThickness = 0, Parent = billboard })
	self.Pickups[data.Id] = self:_addItem("Pickup", model, data.Position, { Core = core, Shell = shell, Phase = rng:NextNumber(0, 6) })
end

function Course:_buildBarrier(data)
	local model = Instance.new("Model")
	model.Name = "LaserBarrier"
	local base = data.Position
	local wall = newPart({
		Name = "Wall",
		Size = Vector3.new(data.Width, data.Height, 0.3),
		CFrame = CFrame.new(base + Vector3.new(0, data.Height / 2, 0)),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 40, 70),
		Transparency = 0.6,
		Parent = model,
	})
	local lines = {}
	for i = 1, 3 do
		table.insert(lines, newPart({
			Name = "Laser",
			Size = Vector3.new(data.Width, 0.25, 0.25),
			CFrame = CFrame.new(base + Vector3.new(0, data.Height * i / 4, 0)),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 120, 140),
			Parent = model,
		}))
	end
	for _, side in { -1, 1 } do
		newPart({
			Name = "Post",
			Size = Vector3.new(1.2, data.Height + 1.5, 1.2),
			CFrame = CFrame.new(base + Vector3.new(side * data.Width / 2, (data.Height + 1.5) / 2, 0)),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(40, 40, 52),
			CastShadow = true,
			Parent = model,
		})
	end
	self.Barriers[data.Id] = self:_addItem("Barrier", model, base, { Wall = wall, Lines = lines, Data = data, Down = false })
end

function Course:_buildLog(data)
	local model = Instance.new("Model")
	model.Name = "SwingingLog"
	local pivot = data.Pivot
	local wood = Color3.fromRGB(110, 76, 50)
	local frameX = Config.LaneWidth / 2 + 3
	newPart({
		Name = "Crossbar",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(frameX * 2 + 2, 1.8, 1.8),
		CFrame = CFrame.new(0, pivot.Y + 0.9, pivot.Z),
		Material = Enum.Material.Wood,
		Color = wood,
		CastShadow = true,
		Parent = model,
	})
	for _, side in { -1, 1 } do
		newPart({
			Name = "Post",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(pivot.Y + 1, 2, 2),
			CFrame = CFrame.new(side * frameX, (pivot.Y + 1) / 2, pivot.Z) * UP,
			Material = Enum.Material.Wood,
			Color = wood,
			CastShadow = true,
			Parent = model,
		})
	end
	local rope = newPart({
		Name = "Rope",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(data.Length, 0.5, 0.5),
		Material = Enum.Material.Fabric,
		Color = Color3.fromRGB(200, 170, 110),
		Parent = model,
	})
	local log = newPart({
		Name = "Log",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(8, H.Log.Radius * 2, H.Log.Radius * 2),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(130, 90, 56),
		CastShadow = true,
		Parent = model,
	})
	local item = self:_addItem("Log", model, pivot, { Data = data, Rope = rope, Log = log })
	self:_poseLog(item, 0)
end

function Course:_poseLog(item, t: number)
	local data = item.Data
	local angle = CourseLayout.LogAngle(data, t)
	local head = CourseLayout.LogHead(data, t)
	item.Rope.CFrame = cylinderBetween(data.Pivot, head)
	-- The log lies front-to-back so it sweeps across the lane.
	item.Log.CFrame = CFrame.new(head) * CFrame.Angles(0, 0, angle) * CFrame.Angles(0, math.pi / 2, 0)
end

function Course:_buildGeyser(data)
	local model = Instance.new("Model")
	model.Name = "Geyser"
	local base = data.Position
	newPart({
		Name = "Rim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.4, H.Geyser.Radius * 2 + 2, H.Geyser.Radius * 2 + 2),
		CFrame = CFrame.new(base + Vector3.new(0, 0.5, 0)) * UP,
		Material = Enum.Material.Basalt,
		Color = Color3.fromRGB(46, 40, 42),
		Parent = model,
	})
	local pool = newPart({
		Name = "Pool",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, H.Geyser.Radius * 2 - 1, H.Geyser.Radius * 2 - 1),
		CFrame = CFrame.new(base + Vector3.new(0, 1.15, 0)) * UP,
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 120, 30),
		Parent = model,
	})
	local column = newPart({
		Name = "Column",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 7, 7),
		CFrame = CFrame.new(base) * UP,
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 150, 50),
		Transparency = 1,
		Parent = model,
	})
	local fire = Instance.new("Fire")
	fire.Size = 3
	fire.Heat = 6
	fire.Color = Color3.fromRGB(255, 140, 40)
	fire.SecondaryColor = Color3.fromRGB(255, 50, 20)
	fire.Parent = pool
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 120, 40)
	light.Range = 16
	light.Brightness = 1
	light.Parent = pool
	self:_addItem("Geyser", model, base, { Data = data, Column = column, Fire = fire, Light = light })
end

function Course:_buildUpdraft(data)
	local model = Instance.new("Model")
	model.Name = "Updraft"
	local base = data.Position
	local disc = newPart({
		Name = "Base",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, H.Updraft.Radius * 2, H.Updraft.Radius * 2),
		CFrame = CFrame.new(base + Vector3.new(0, 0.2, 0)) * UP,
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(150, 230, 255),
		Transparency = 0.4,
		Parent = model,
	})
	newPart({
		Name = "Column",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(H.Updraft.Height, H.Updraft.Radius * 2, H.Updraft.Radius * 2),
		CFrame = CFrame.new(base + Vector3.new(0, H.Updraft.Height / 2, 0)) * UP,
		Material = Enum.Material.Glass,
		Color = Color3.fromRGB(200, 240, 255),
		Transparency = 0.88,
		Parent = model,
	})
	local streaks = Instance.new("ParticleEmitter")
	streaks.Rate = 14
	streaks.Lifetime = NumberRange.new(1.8, 2.4)
	streaks.Speed = NumberRange.new(34, 44)
	streaks.EmissionDirection = Enum.NormalId.Right -- the base's axis points up
	streaks.Orientation = Enum.ParticleOrientation.VelocityParallel
	streaks.Squash = NumberSequence.new(-1.5)
	streaks.Size = NumberSequence.new(0.5, 0.2)
	streaks.Transparency = NumberSequence.new(0.3, 1)
	streaks.Color = ColorSequence.new(Color3.fromRGB(230, 250, 255))
	streaks.LightEmission = 0.5
	streaks.Parent = disc
	self:_addItem("Updraft", model, base, {})
end

function Course:_buildPad(data)
	local model = Instance.new("Model")
	model.Name = "BouncePad"
	local base = data.Position
	newPart({
		Name = "Rim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, H.Pad.Radius * 2 + 1, H.Pad.Radius * 2 + 1),
		CFrame = CFrame.new(base + Vector3.new(0, 0.3, 0)) * UP,
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(50, 52, 64),
		Parent = model,
	})
	local top = newPart({
		Name = "Top",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, H.Pad.Radius * 2 - 1, H.Pad.Radius * 2 - 1),
		CFrame = CFrame.new(base + Vector3.new(0, 0.6, 0)) * UP,
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(120, 255, 120),
		Parent = model,
	})
	for _, side in { -1, 1 } do
		newPart({
			Name = "Arrow",
			Size = Vector3.new(0.4, 0.2, 3.2),
			CFrame = CFrame.new(base + Vector3.new(side * 1, 0.9, 0)) * CFrame.Angles(0, side * math.rad(35), 0),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 255, 255),
			Parent = model,
		})
	end
	self.Pads[data.Id] = self:_addItem("Pad", model, base, { Top = top, BouncedAt = -10, Base = base })
end

-- Builds everything, yielding now and then so joining doesn't hitch.
function Course:Build()
	local layout = self.Layout
	for index, data in layout.Blocks do
		self:_buildBlock(data)
		if index % 300 == 0 then
			task.wait()
		end
	end
	for _, data in layout.Stars do
		self:_buildStar(data)
	end
	for _, data in layout.Rings do
		self:_buildRing(data)
	end
	for _, data in layout.Pickups do
		self:_buildPickup(data)
	end
	for _, data in layout.Barriers do
		self:_buildBarrier(data)
	end
	for _, data in layout.Logs do
		self:_buildLog(data)
	end
	for _, data in layout.Geysers do
		self:_buildGeyser(data)
	end
	for _, data in layout.Updrafts do
		self:_buildUpdraft(data)
	end
	for _, data in layout.Pads do
		self:_buildPad(data)
	end
	self.Ready = true
	self:SetView(self.ViewCenter)
end

--------------------------------------------------------------------------------
-- View window
--------------------------------------------------------------------------------

function Course:_setBucketVisible(b: number, visible: boolean)
	local parent = if visible then self.Folder else nil
	local blocks = self.BlockBuckets[b]
	if blocks then
		for _, entry in blocks do
			if not entry.Hidden then
				entry.Part.Parent = parent
			end
		end
	end
	local items = self.ItemBuckets[b]
	if items then
		for _, item in items do
			if not item.Hidden then
				item.Instance.Parent = parent
			end
		end
	end
end

function Course:_inView(b: number): boolean
	return self.ViewLow ~= nil and b >= self.ViewLow and b <= self.ViewHigh
end

-- Shows the course from a little behind `distance` to well ahead of it.
function Course:SetView(distance: number)
	self.ViewCenter = distance
	if not self.Ready then
		return
	end
	local q = Quality.Current
	local low = bucketOf(distance - q.ViewBehind)
	local high = bucketOf(distance + q.ViewAhead)
	if low == self.ViewLow and high == self.ViewHigh then
		return
	end
	local oldLow, oldHigh = self.ViewLow, self.ViewHigh
	if oldLow then
		for b = oldLow, oldHigh do
			if b < low or b > high then
				self:_setBucketVisible(b, false)
			end
		end
	end
	for b = low, high do
		if not oldLow or b < oldLow or b > oldHigh then
			self:_setBucketVisible(b, true)
		end
	end
	self.ViewLow, self.ViewHigh = low, high
end

function Course:_applyQuality()
	local shadows = Quality.Current.BlockShadows
	for _, entry in self.BlockList do
		if not entry.Broken then
			entry.Part.CastShadow = shadows
		end
	end
	if self.Ready and self.ViewLow then
		-- Clear the old window, then let SetView draw it at the new distance.
		for b = self.ViewLow, self.ViewHigh do
			self:_setBucketVisible(b, false)
		end
		self.ViewLow, self.ViewHigh = nil, nil
		self:SetView(self.ViewCenter)
	end
end

--------------------------------------------------------------------------------
-- Reacting to RunSim events
--------------------------------------------------------------------------------

function Course:_hideBlock(entry)
	entry.Hidden = true
	entry.Part.Parent = nil
end

-- Flings a smashed block. Returns false when the debris budget was full and
-- the block simply vanished instead.
function Course:Smash(data, velocity: Vector3): boolean
	local entry = self.Blocks[data.Id]
	if not entry or entry.Broken then
		return false
	end
	entry.Broken = true
	local part = entry.Part
	if part.Parent == nil or #self.Flung >= Quality.Current.MaxDebris then
		self:_hideBlock(entry)
		return false
	end
	part.CollisionGroup = "Debris"
	part.CastShadow = false
	part.Anchored = false
	part.AssemblyLinearVelocity = velocity * 0.55
		+ Vector3.new(rng:NextNumber(-18, 18), rng:NextNumber(14, 36), rng:NextNumber(-12, 12))
	part.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-12, 12), rng:NextNumber(-12, 12))
	table.insert(self.Flung, { Entry = entry, Time = os.clock() })
	return true
end

-- Brief colour flash on a block (armor bonks and phasing).
function Course:FlashBlock(data, color: Color3, transparency: number?)
	local entry = self.Blocks[data.Id]
	if not entry or entry.Broken then
		return
	end
	entry.Part.Color = color
	entry.Part.Transparency = transparency or entry.Transparency
	entry.FlashUntil = os.clock() + 0.18
	self.Flashing[entry] = true
end

function Course:CollectStar(id: number)
	local item = self.Stars[id]
	if item then
		item.Hidden = true
		item.Instance.Parent = nil
	end
end

function Course:UseRing(id: number)
	local item = self.Rings[id]
	if item then
		for _, segment in item.Segments do
			segment.Part.Color = Color3.fromRGB(255, 220, 60)
			segment.Part.Transparency = 0.6
		end
	end
end

function Course:TakePickup(id: number)
	local item = self.Pickups[id]
	if item then
		item.Hidden = true
		item.Instance.Parent = nil
	end
end

function Course:HitBarrier(id: number, phased: boolean)
	local item = self.Barriers[id]
	if not item then
		return
	end
	item.Down = true
	item.Wall.Color = if phased then Color3.fromRGB(120, 255, 255) else Color3.fromRGB(90, 20, 30)
	item.Wall.Transparency = 0.85
	for _, line in item.Lines do
		line.Transparency = 1
	end
end

function Course:BouncePad(id: number)
	local item = self.Pads[id]
	if item then
		item.BouncedAt = os.clock()
	end
end

--------------------------------------------------------------------------------
-- Per-frame animation
--------------------------------------------------------------------------------

-- t is the hazard clock: the launch's RunSim time while flying, so what you
-- see matches what you hit.
function Course:Update(_dt: number, focus: Vector3?, t: number)
	local now = os.clock()
	local debrisTime = Quality.Current.DebrisTime
	for i = #self.Flung, 1, -1 do
		local flung = self.Flung[i]
		if now - flung.Time > debrisTime then
			local part = flung.Entry.Part
			part.Anchored = true
			self:_hideBlock(flung.Entry)
			table.remove(self.Flung, i)
		end
	end

	if focus then
		self:SetView(math.max(0, -focus.Z))
	end
	if not self.ViewLow then
		return
	end

	-- Only the few flashing blocks are checked, not every block in view.
	for entry in self.Flashing do
		if now > (entry.FlashUntil or 0) then
			self.Flashing[entry] = nil
			entry.FlashUntil = nil
			if not entry.Broken then
				entry.Part.Color = entry.Color
				entry.Part.Transparency = entry.Transparency
			end
		end
	end

	local bob = math.sin(now * 3)
	for b = self.ViewLow, self.ViewHigh do
		local items = self.ItemBuckets[b]
		if items then
			for _, item in items do
				if not item.Hidden then
					self:_animate(item, t, now, bob)
				end
			end
		end
	end
end

function Course:_animate(item, t: number, now: number, bob: number)
	local kind = item.Kind
	if kind == "Star" then
		item.Part.CFrame = CFrame.new(item.Position + Vector3.new(0, bob * 0.8, 0))
	elseif kind == "Pickup" then
		local offset = Vector3.new(0, math.sin(now * 2.4 + item.Phase) * 0.9, 0)
		local spin = CFrame.Angles(0, now * 1.6 + item.Phase, 0)
		item.Core.CFrame = CFrame.new(item.Position + offset) * spin
		item.Shell.CFrame = CFrame.new(item.Position + offset) * spin:Inverse()
	elseif kind == "Log" then
		self:_poseLog(item, t)
	elseif kind == "Geyser" then
		local active, progress = CourseLayout.GeyserState(item.Data, t)
		local column = item.Column
		if active then
			-- Shoots up fast, then thins out.
			local height = H.Geyser.Height * math.min(1, progress * 4)
			column.Size = Vector3.new(math.max(1, height), 7 - progress * 2, 7 - progress * 2)
			column.CFrame = CFrame.new(item.Position + Vector3.new(0, height / 2, 0)) * UP
			column.Transparency = 0.35 + progress * 0.4
			item.Fire.Size = 22
			item.Fire.Heat = 25
			item.Light.Brightness = 4
		else
			-- Bubbling, and a warning flare just before it erupts.
			local phase = (t + item.Data.Offset) % item.Data.Period
			local warning = phase > item.Data.Period - 0.6
			column.Transparency = 1
			item.Fire.Size = if warning then 9 else 3
			item.Fire.Heat = if warning then 14 else 6
			item.Light.Brightness = if warning then 2.5 else 1
		end
	elseif kind == "Barrier" then
		if not item.Down then
			item.Wall.Transparency = 0.55 + 0.12 * math.sin(now * 23 + item.Position.X)
		end
	elseif kind == "Pad" then
		local since = now - item.BouncedAt
		local squash = if since < 0.35 then math.sin(since / 0.35 * math.pi) * 0.5 else 0
		local glow = 0.5 + 0.5 * math.sin(now * 5 + item.Position.X)
		item.Top.Color = Color3.fromRGB(120, 255, 120):Lerp(Color3.fromRGB(240, 255, 140), glow)
		item.Top.CFrame = CFrame.new(item.Base + Vector3.new(0, 0.6 - squash * 0.4, 0)) * UP
	end
end

--------------------------------------------------------------------------------
-- Reset for the next launch
--------------------------------------------------------------------------------

function Course:Reset()
	local shadows = Quality.Current.BlockShadows
	for _, entry in self.BlockList do
		if entry.Broken or entry.Hidden or entry.FlashUntil then
			local part = entry.Part
			part.Anchored = true
			part.CFrame = entry.CFrame
			part.Color = entry.Color
			part.Transparency = entry.Transparency
			part.CollisionGroup = "Default"
			part.CastShadow = shadows
			entry.Broken = false
			entry.Hidden = false
			entry.FlashUntil = nil
			part.Parent = if self:_inView(entry.Bucket) then self.Folder else nil
		end
	end
	table.clear(self.Flung)
	table.clear(self.Flashing)

	for _, item in self.Items do
		if item.Hidden then
			item.Hidden = false
			item.Instance.Parent = if self:_inView(item.Bucket) then self.Folder else nil
		end
		if item.Kind == "Ring" then
			for _, segment in item.Segments do
				segment.Part.Color = segment.Color
				segment.Part.Transparency = 0
			end
		elseif item.Kind == "Barrier" then
			item.Down = false
			item.Wall.Color = Color3.fromRGB(255, 40, 70)
			for _, line in item.Lines do
				line.Transparency = 0
			end
		end
	end
end

return Course
