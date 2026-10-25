--[[
	Builds the static world on the server: the Sky Kingdom lobby, the slingshot,
	and five biomes along the launch lane (terrain, scenery, gates, lighting).

	Landscape is Roblox Terrain (cheap to render, looks rich); props are Parts.
	The lane floor is always flat at Config.GroundY because flight physics
	assumes it. Hills, water and mountains stay well outside the lane.

	The smashable obstacles are NOT built here; each client builds its own copy
	(see Client/Course) so smashing is instant and resets for every launch.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local CourseLayout = require(ReplicatedStorage.Shared.CourseLayout)

local WorldBuilder = {}

local LANE_GROUND_HALF = 68 -- lane material reaches out to x = +-68
local OUTER_HALF = 480 -- side terrain reaches out to x = +-480
local TERRAIN_DEPTH = 16
local LOBBY_BACK = 220 -- terrain behind the slingshot (towards +Z)
local LANE_END = Config.LaneLength + 260

local rng = Random.new(42)

-- Waterfalls pour from floating islands into the Sky Kingdom river.
local WATERFALLS = {
	{ Top = Vector3.new(-150, 76, -20), Height = 77 },
	{ Top = Vector3.new(-148, 84, -200), Height = 85 },
	{ Top = Vector3.new(-152, 90, -380), Height = 91 },
}

--------------------------------------------------------------------------------
-- Part helpers
--------------------------------------------------------------------------------

local function part(props): BasePart
	local className = props.ClassName or "Part"
	local p = Instance.new(className) :: BasePart
	p.Anchored = true
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

-- Decorations never need collisions, queries or touch events.
local function prop(props): BasePart
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	return part(props)
end

-- Upright cylinder (Roblox cylinders lie along X, so rotate them).
local function pillar(parent: Instance, base: Vector3, height: number, radius: number, color: Color3, material: Enum.Material?, name: string?): BasePart
	return prop({
		Name = name or "Pillar",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Parent = parent,
	})
end

-- Cylinder between two points.
local function beamPart(parent: Instance, a: Vector3, b: Vector3, radius: number, color: Color3, material: Enum.Material?, name: string?): BasePart
	local length = (b - a).Magnitude
	local dir = (b - a).Unit
	local up = if math.abs(dir.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis
	local side = up:Cross(dir).Unit
	return prop({
		Name = name or "Beam",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length, radius * 2, radius * 2),
		CFrame = CFrame.fromMatrix((a + b) / 2, dir, dir:Cross(side)),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Parent = parent,
	})
end

local function ball(parent: Instance, center: Vector3, size: Vector3, color: Color3, material: Enum.Material?, name: string?): BasePart
	return prop({
		Name = name or "Ball",
		Shape = Enum.PartType.Ball,
		Size = size,
		CFrame = CFrame.new(center),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		CastShadow = false,
		Parent = parent,
	})
end

-- A flat ring of neon segments (rings, holograms, gate frames).
local function ring(parent: Instance, cframe: CFrame, radius: number, thickness: number, color: Color3, segments: number?)
	local count = segments or 16
	local chord = 2 * radius * math.sin(math.pi / count) + thickness * 0.5
	for i = 1, count do
		local angle = (i / count) * math.pi * 2
		prop({
			Name = "RingSegment",
			Size = Vector3.new(thickness, chord, thickness),
			CFrame = cframe * CFrame.new(math.cos(angle) * radius, math.sin(angle) * radius, 0) * CFrame.Angles(0, 0, angle),
			Color = color,
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = parent,
		})
	end
end

local function emitter(parent: Instance, props): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

local function sign(parent: Instance, size: Vector3, cframe: CFrame, text: string, color: Color3, textColor: Color3?, material: Enum.Material?)
	local board = prop({
		Name = "Sign",
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- the +Z face, which faces the lobby
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = board

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = textColor or Color3.new(1, 1, 1)
	label.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = Color3.fromRGB(20, 14, 10)
	stroke.Parent = label

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.08, 0)
	padding.PaddingBottom = UDim.new(0.08, 0)
	padding.PaddingLeft = UDim.new(0.03, 0)
	padding.PaddingRight = UDim.new(0.03, 0)
	padding.Parent = label
	return board
end

local function zoneRange(index: number): (number, number)
	local from = if index == 1 then -LOBBY_BACK else Config.Zones[index - 1].EndsAt
	local to = if index == #Config.Zones then LANE_END else Config.Zones[index].EndsAt
	return from, math.min(to, LANE_END)
end

-- Random x outside the lane, on either side.
local function sideX(minX: number, maxX: number): number
	local side = if rng:NextNumber() < 0.5 then -1 else 1
	return side * rng:NextNumber(minX, maxX)
end

--------------------------------------------------------------------------------
-- Terrain
--------------------------------------------------------------------------------

local terrain: Terrain = Workspace.Terrain

local function fillBlock(cframe: CFrame, size: Vector3, material: Enum.Material)
	terrain:FillBlock(cframe, size, material)
end

-- Fills a slab from x1..x2, distance d1..d2, with its top at `top`, in chunks.
local function slab(x1: number, x2: number, d1: number, d2: number, top: number, depth: number, material: Enum.Material)
	local chunk = 512
	local d = d1
	while d < d2 do
		local length = math.min(chunk, d2 - d)
		fillBlock(
			CFrame.new((x1 + x2) / 2, top - depth / 2, -(d + length / 2)),
			Vector3.new(x2 - x1, depth, length),
			material
		)
		d += length
	end
end

local HILL_MATERIAL = {
	Sky = Enum.Material.Grass,
	Jungle = Enum.Material.LeafyGrass,
	Volcanic = Enum.Material.Basalt,
	Frozen = Enum.Material.Snow,
}
local MOUNTAIN_MATERIAL = {
	Sky = Enum.Material.Rock,
	Jungle = Enum.Material.Rock,
	Volcanic = Enum.Material.Basalt,
	Frozen = Enum.Material.Glacier,
}

-- Flat lane and side ground for every biome. If even this fails, the world
-- falls back to plain parts so nobody falls through the floor.
local function buildBaseTerrain()
	terrain:Clear()
	terrain.WaterColor = Color3.fromRGB(40, 150, 200)
	terrain.WaterTransparency = 0.6
	terrain.WaterWaveSize = 0.12
	terrain.WaterWaveSpeed = 8
	terrain.WaterReflectance = 0.5
	terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(128, 122, 116))
	for _, zone in Config.Zones do
		for materialName, color in zone.TerrainColors do
			terrain:SetMaterialColor((Enum.Material :: any)[materialName], color)
		end
	end

	for index, zone in Config.Zones do
		local from, to = zoneRange(index)
		-- Lane and shoulders, then the wider sides.
		slab(-LANE_GROUND_HALF, LANE_GROUND_HALF, from, to, Config.GroundY, TERRAIN_DEPTH, zone.LaneMaterial)
		slab(-OUTER_HALF, -LANE_GROUND_HALF, from, to, Config.GroundY, TERRAIN_DEPTH, zone.SideMaterial)
		slab(LANE_GROUND_HALF, OUTER_HALF, from, to, Config.GroundY, TERRAIN_DEPTH, zone.SideMaterial)
	end
end

-- Plain-part ground, only used if terrain can't be built.
local function buildFallbackGround(map: Folder)
	local ground = Instance.new("Folder")
	ground.Name = "FallbackGround"
	ground.Parent = map
	for index, zone in Config.Zones do
		local from, to = zoneRange(index)
		local d = from
		while d < to do
			local length = math.min(1000, to - d)
			part({
				Name = "Ground",
				Size = Vector3.new(LANE_GROUND_HALF * 4, 2, length),
				CFrame = CFrame.new(0, Config.GroundY - 1, -(d + length / 2)),
				Color = zone.BannerColor:Lerp(Color3.new(0.3, 0.3, 0.3), 0.5),
				Material = Enum.Material.SmoothPlastic,
				CastShadow = false,
				Parent = ground,
			})
			d += length
		end
	end
end

-- Hills, mountains, water, volcanoes and islands. Each piece is optional.
local function buildTerrainFeatures()
	for index, zone in Config.Zones do
		local from, to = zoneRange(index)
		local key = zone.Key

		-- Rolling hills beside the lane and mountains on the horizon.
		local hillMaterial = HILL_MATERIAL[key]
		local mountainMaterial = MOUNTAIN_MATERIAL[key]
		local length = to - from
		if hillMaterial then
			for _ = 1, math.floor(length / 70) do
				local radius = rng:NextNumber(18, 42)
				local x = sideX(LANE_GROUND_HALF + radius * 0.6 + 20, 230)
				-- Keep the Sky Kingdom river (x = -170..-130) and its banks clear.
				local overRiver = key == "Sky" and x - radius < -120 and x + radius > -180
				if not overRiver then
					terrain:FillBall(Vector3.new(x, Config.GroundY - radius * 0.45, -rng:NextNumber(from, to)), radius, hillMaterial)
				end
			end
		end
		if mountainMaterial then
			for _ = 1, math.max(2, math.floor(length / 160)) do
				local radius = rng:NextNumber(60, 110)
				local x = sideX(300, 440)
				local center = Vector3.new(x, Config.GroundY - radius * 0.25, -rng:NextNumber(from, to))
				terrain:FillBall(center, radius, mountainMaterial)
				-- Snowy or grassy caps.
				local cap = if key == "Frozen" or key == "Sky" then Enum.Material.Snow else hillMaterial
				if cap then
					terrain:FillBall(center + Vector3.new(0, radius * 0.55, 0), radius * 0.5, cap)
				end
			end
		end
	end

	-- Sky Kingdom river beside the lane, flowing past the lobby.
	local riverFrom, riverTo = -LOBBY_BACK + 20, Config.Zones[1].EndsAt - 20
	slab(-170, -130, riverFrom, riverTo, Config.GroundY, 10, Enum.Material.Air)
	slab(-170, -130, riverFrom, riverTo, Config.GroundY - 6, 4, Enum.Material.Sand)
	slab(-170, -130, riverFrom, riverTo, Config.GroundY - 1.5, 4.5, Enum.Material.Water)

	-- Jungle swamp pools.
	local jFrom, jTo = zoneRange(2)
	for _ = 1, 4 do
		local x = sideX(100, 200)
		local d = rng:NextNumber(jFrom + 40, jTo - 40)
		local radius = rng:NextNumber(16, 26)
		terrain:FillCylinder(CFrame.new(x, Config.GroundY - 2, -d), 6, radius, Enum.Material.Air)
		terrain:FillCylinder(CFrame.new(x, Config.GroundY - 3, -d), 4, radius, Enum.Material.Water)
	end

	-- Volcanoes: stacked cylinders make a cone; the crater is hollow.
	local vFrom, vTo = zoneRange(3)
	for i, info in { { -420, 0.35 }, { 460, 0.75 } } do
		local x, d = info[1], vFrom + (vTo - vFrom) * info[2]
		local size = if i == 1 then 1 else 0.7
		for level = 0, 8 do
			local radius = (150 - level * 16) * size
			terrain:FillCylinder(CFrame.new(x, Config.GroundY + level * 14 * size + 7, -d), 14 * size + 2, radius, Enum.Material.Basalt)
		end
		terrain:FillCylinder(CFrame.new(x, Config.GroundY + 9 * 14 * size, -d), 20 * size, 18 * size, Enum.Material.CrackedLava)
	end

	-- Frozen lake.
	local fFrom, fTo = zoneRange(4)
	terrain:FillCylinder(CFrame.new(-150, Config.GroundY - 1, -(fFrom + fTo) / 2), 2.5, 55, Enum.Material.Ice)

	-- Islands the waterfalls pour from, then more floating islands around the Sky Kingdom.
	for _, fall in WATERFALLS do
		local top = fall.Top + Vector3.new(0, 2, -8)
		terrain:FillBall(top - Vector3.new(0, 12, 0), 18, Enum.Material.Rock)
		terrain:FillCylinder(CFrame.new(top), 5, 17, Enum.Material.Grass)
	end
	for _ = 1, 9 do
		local radius = rng:NextNumber(14, 26)
		local top = Vector3.new(sideX(70, 260), rng:NextNumber(55, 110), -rng:NextNumber(-180, Config.Zones[1].EndsAt + 100))
		terrain:FillBall(top - Vector3.new(0, radius * 0.55, 0), radius, Enum.Material.Rock)
		terrain:FillCylinder(CFrame.new(top), 5, radius * 0.95, Enum.Material.Grass)
	end
end

--------------------------------------------------------------------------------
-- Lane rails, markers, gates, finish
--------------------------------------------------------------------------------

local RAIL_COLORS = {
	Sky = { Color3.fromRGB(255, 206, 46), Color3.fromRGB(245, 245, 245) },
	Jungle = { Color3.fromRGB(110, 170, 70), Color3.fromRGB(190, 170, 120) },
	Volcanic = { Color3.fromRGB(255, 110, 30), Color3.fromRGB(50, 44, 46) },
	Frozen = { Color3.fromRGB(120, 210, 255), Color3.fromRGB(245, 250, 255) },
	Neon = { Color3.fromRGB(0, 230, 255), Color3.fromRGB(255, 60, 200) },
}

local GATE_STYLE = {
	Sky = { Pillar = Color3.fromRGB(236, 228, 210), Material = Enum.Material.Limestone, Sign = Color3.fromRGB(120, 70, 220), Text = Color3.fromRGB(255, 230, 90), Accent = Color3.fromRGB(255, 206, 46) },
	Jungle = { Pillar = Color3.fromRGB(110, 120, 96), Material = Enum.Material.Cobblestone, Sign = Color3.fromRGB(40, 90, 40), Text = Color3.fromRGB(200, 255, 140), Accent = Color3.fromRGB(80, 160, 60) },
	Volcanic = { Pillar = Color3.fromRGB(46, 40, 42), Material = Enum.Material.Basalt, Sign = Color3.fromRGB(70, 20, 14), Text = Color3.fromRGB(255, 170, 60), Accent = Color3.fromRGB(255, 100, 20) },
	Frozen = { Pillar = Color3.fromRGB(180, 225, 255), Material = Enum.Material.Glass, Sign = Color3.fromRGB(40, 90, 150), Text = Color3.fromRGB(220, 245, 255), Accent = Color3.fromRGB(240, 250, 255) },
	Neon = { Pillar = Color3.fromRGB(24, 24, 36), Material = Enum.Material.SmoothPlastic, Sign = Color3.fromRGB(16, 14, 30), Text = Color3.fromRGB(120, 240, 255), Accent = Color3.fromRGB(0, 230, 255) },
}

local function buildLane(map: Folder)
	local lane = Instance.new("Folder")
	lane.Name = "Lane"
	lane.Parent = map

	-- Rails in 32-stud segments, coloured per biome.
	local railX = Config.LaneWidth / 2 + 0.6
	local segment = 32
	local index = 0
	for d = 8, Config.LaneLength, segment do
		local zone = Config.Zones[CourseLayout.ZoneIndexAt(d + segment / 2)]
		local colors = RAIL_COLORS[zone.Key]
		for _, side in { -1, 1 } do
			prop({
				Name = "Rail",
				Size = Vector3.new(0.9, 0.9, segment),
				CFrame = CFrame.new(side * railX, Config.GroundY + 0.45, -(d + segment / 2)),
				Color = colors[(index % 2) + 1],
				Material = if zone.Key == "Neon" then Enum.Material.Neon else Enum.Material.SmoothPlastic,
				CastShadow = false,
				Parent = lane,
			})
		end
		index += 1
	end

	-- Distance markers every 250 studs.
	for d = 250, Config.LaneLength - 50, 250 do
		for _, side in { -1, 1 } do
			local x = side * (railX + 5)
			prop({
				Name = "MarkerPost",
				Size = Vector3.new(0.8, 6, 0.8),
				CFrame = CFrame.new(x, Config.GroundY + 3, -d),
				Color = Color3.fromRGB(90, 60, 40),
				Parent = lane,
			})
			sign(lane, Vector3.new(8, 4, 0.6), CFrame.new(x, Config.GroundY + 7.5, -d), tostring(d), Color3.fromRGB(255, 196, 40))
		end
	end

	-- Themed gate at the start of each biome.
	local gateStart = 0
	for zoneIndex, zone in Config.Zones do
		local d = if zoneIndex == 1 then 14 else gateStart
		local style = GATE_STYLE[zone.Key]
		local pillarX = Config.LaneWidth / 2 + 4
		local gate = Instance.new("Model")
		gate.Name = "Gate_" .. zone.Key
		gate.Parent = lane
		for _, side in { -1, 1 } do
			local base = Vector3.new(side * pillarX, Config.GroundY, -d)
			local column = pillar(gate, base, 30, 2.2, style.Pillar, style.Material, "GatePillar")
			if zone.Key == "Frozen" then
				column.Transparency = 0.25
			end
			prop({
				Name = "GateCap",
				Size = Vector3.new(6, 2, 6),
				CFrame = CFrame.new(base + Vector3.new(0, 30.5, 0)),
				Color = style.Accent,
				Material = if zone.Key == "Neon" or zone.Key == "Volcanic" then Enum.Material.Neon else Enum.Material.SmoothPlastic,
				Parent = gate,
			})
			if zone.Key == "Neon" or zone.Key == "Volcanic" then
				-- Glowing strips up the pillars.
				prop({
					Name = "GateGlow",
					Size = Vector3.new(0.5, 26, 0.5),
					CFrame = CFrame.new(base + Vector3.new(-side * 2.3, 14, 0)),
					Color = style.Accent,
					Material = Enum.Material.Neon,
					CastShadow = false,
					Parent = gate,
				})
			elseif zone.Key == "Jungle" then
				for v = 1, 3 do
					beamPart(gate, base + Vector3.new(side * (v - 2) * 0.8, 29, 2.3), base + Vector3.new(side * (v - 2), 29 - rng:NextNumber(8, 16), 2.4), 0.25, Color3.fromRGB(70, 140, 50), Enum.Material.LeafyGrass, "Vine")
				end
			end
		end
		local title = if zoneIndex == 1 then Config.GameName else string.upper(zone.Name)
		sign(gate, Vector3.new(pillarX * 2 + 4, 7, 2), CFrame.new(0, Config.GroundY + 33, -d), title, style.Sign, style.Text)
		gateStart = zone.EndsAt
	end

	-- Finish: a glowing wall between two flaming pillars.
	local finishD = Config.LaneLength + 6
	prop({
		Name = "FinishWall",
		Size = Vector3.new(Config.LaneWidth + 12, 40, 4),
		CFrame = CFrame.new(0, Config.GroundY + 20, -finishD),
		Color = Color3.fromRGB(255, 200, 40),
		Material = Enum.Material.Neon,
		Parent = lane,
	})
	sign(lane, Vector3.new(60, 12, 1), CFrame.new(0, Config.GroundY + 20, -(finishD - 2.6)), "🏆 FINISH 🏆", Color3.fromRGB(120, 70, 220))
	for _, side in { -1, 1 } do
		local base = Vector3.new(side * (Config.LaneWidth / 2 + 10), Config.GroundY, -(finishD - 4))
		pillar(lane, base, 44, 3, Color3.fromRGB(60, 40, 90), Enum.Material.SmoothPlastic, "FinishPillar")
		local top = prop({
			Name = "FinishFlame",
			Size = Vector3.new(4, 2, 4),
			CFrame = CFrame.new(base + Vector3.new(0, 45, 0)),
			Color = Color3.fromRGB(255, 160, 40),
			Material = Enum.Material.Neon,
			Parent = lane,
		})
		emitter(top, {
			Rate = 24,
			Lifetime = NumberRange.new(0.6, 1.1),
			Speed = NumberRange.new(10, 18),
			SpreadAngle = Vector2.new(12, 12),
			EmissionDirection = Enum.NormalId.Top,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 0.5) }),
			Transparency = NumberSequence.new(0.1, 1),
			Color = ColorSequence.new(Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 70, 20)),
			LightEmission = 1,
		})
	end
end

--------------------------------------------------------------------------------
-- Slingshot + lobby
--------------------------------------------------------------------------------

local function buildSlingshot(map: Folder)
	local model = Instance.new("Model")
	model.Name = "Slingshot"
	model.Parent = map

	local base = Config.SlingshotPosition
	local wood = Color3.fromRGB(140, 90, 52)
	local stone = Color3.fromRGB(128, 128, 136)
	local gold = Color3.fromRGB(255, 190, 60)

	-- Round launch platform with a gold rim and arrows pointing down the lane.
	part({
		Name = "Pad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 28, 28),
		CFrame = CFrame.new(base + Vector3.new(0, 0.4, 9)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(70, 80, 120),
		Material = Enum.Material.Slate,
		Parent = model,
	})
	prop({
		Name = "PadRim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 30, 30),
		CFrame = CFrame.new(base + Vector3.new(0, 0.3, 9)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = gold,
		Material = Enum.Material.Metal,
		Parent = model,
	})
	for i = 1, 3 do
		for _, side in { -1, 1 } do
			prop({
				Name = "PadArrow",
				Size = Vector3.new(0.5, 0.2, 4),
				CFrame = CFrame.new(base + Vector3.new(side * 1.3, 0.85, 18 - i * 4.5)) * CFrame.Angles(0, side * math.rad(35), 0),
				Color = Color3.fromRGB(80, 230, 255),
				Material = Enum.Material.Neon,
				CastShadow = false,
				Parent = model,
			})
		end
	end

	-- Stone base with rocks.
	part({
		Name = "Base",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.6, 6.4, 6.4),
		CFrame = CFrame.new(base + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = stone,
		Material = Enum.Material.Slate,
		Parent = model,
	})
	for _, angle in { 30, 150, 250, 320 } do
		local a = math.rad(angle)
		ball(model, base + Vector3.new(math.cos(a) * 3.4, 0.8, math.sin(a) * 3.4), Vector3.new(1.8, 1.3, 1.6), Color3.fromRGB(100, 102, 108), Enum.Material.Rock, "Rock")
	end

	-- Trunk, with an "E to launch" prompt for players who walk up to it.
	local trunk = part({
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(5.4, 2.3, 2.3),
		CFrame = CFrame.new(base + Vector3.new(0, 4.6, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = wood,
		Material = Enum.Material.Wood,
		Parent = model,
	})
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SlingLaunchPrompt"
	prompt.ActionText = "Launch"
	prompt.ObjectText = "Slingshot"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 18
	prompt.RequiresLineOfSight = false
	prompt.Parent = trunk

	-- Leather grip and rope binding.
	for i = 0, 4 do
		pillar(model, base + Vector3.new(0, 2.5 + i * 0.5, 0), 0.32, 1.25, Color3.fromRGB(120, 34, 28), Enum.Material.Leather, "Grip")
	end
	for i = 0, 2 do
		pillar(model, base + Vector3.new(0, 6.25 + i * 0.25, 0), 0.2, 1.2, Color3.fromRGB(214, 186, 130), Enum.Material.Fabric, "Binding")
	end

	-- Two arms angled 25 degrees outwards, with knobs and gold band rings.
	local angle = math.rad(25)
	local armLength = 7
	local root = base + Vector3.new(0, 6.5, 0)
	for _, side in { -1, 1 } do
		local dir = Vector3.new(side * math.sin(angle), math.cos(angle), 0)
		beamPart(model, root - dir * 0.6, root + dir * armLength, 0.9, wood, Enum.Material.Wood, "Arm")
		ball(model, root + dir * (armLength + 0.3), Vector3.new(2.2, 2, 2.2), Color3.fromRGB(150, 98, 58), Enum.Material.Wood, "Knob")
		beamPart(model, root + dir * (armLength - 1), root + dir * (armLength - 0.6), 1.05, gold, Enum.Material.Metal, "BandRing")
	end

	-- Energy core between the arms; the client makes it pulse while charging.
	local core = prop({
		Name = "Core",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.6, 1.6, 1.6),
		CFrame = CFrame.new(root + Vector3.new(0, 0.9, 0)),
		Color = Color3.fromRGB(90, 230, 255),
		Material = Enum.Material.Neon,
		CastShadow = false,
		Parent = model,
	})
	local light = Instance.new("PointLight")
	light.Name = "CoreLight"
	light.Color = Color3.fromRGB(90, 230, 255)
	light.Range = 10
	light.Brightness = 1.2
	light.Parent = core

	-- Resting band between the arm tips (the client hides it while aiming).
	local spread = Config.SlingshotArmSpread
	local tipY = Config.SlingshotArmTip
	prop({
		Name = "RestBand",
		Size = Vector3.new(spread * 2, 0.5, 0.5),
		CFrame = CFrame.new(base + Vector3.new(0, tipY - 0.6, 0)),
		Color = Color3.fromRGB(255, 120, 60),
		Parent = model,
	})
	prop({
		Name = "Pouch",
		Size = Vector3.new(2.4, 1, 1),
		CFrame = CFrame.new(base + Vector3.new(0, tipY - 0.6, 0.3)),
		Color = Color3.fromRGB(110, 70, 40),
		Material = Enum.Material.Leather,
		Parent = model,
	})

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(Config.LobbySpawn)
	spawn.Color = Color3.fromRGB(255, 206, 46)
	spawn.Material = Enum.Material.Plastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = map

	-- Stone plaza under the lobby so it reads as a place, not just grass.
	part({
		Name = "Plaza",
		Size = Vector3.new(96, 1, 120),
		CFrame = CFrame.new(0, Config.GroundY - 0.45, 70),
		Color = Color3.fromRGB(214, 206, 190),
		Material = Enum.Material.Limestone,
		CastShadow = false,
		Parent = map,
	})
end

--------------------------------------------------------------------------------
-- How to play sign
--------------------------------------------------------------------------------

local HOW_TO_PLAY = {
	"1. Press 🎯 LAUNCH (or E at the slingshot)",
	"2. W / S aim up and down, A / D left and right",
	"3. HOLD to charge, RELEASE to fly",
	"4. Steer with A / D • CLICK or SPACE for ⚡ NITRO",
	"5. Fly through glowing orbs for POWER-UPS",
	"6. Smash blocks for ⭐ and buy ⬆️ UPGRADES!",
}

-- A signboard on two golden posts, turned to face the lobby spawn. Returns the
-- board part and a SurfaceGui with padding and a vertical list layout.
function WorldBuilder.Signboard(parent: Instance, name: string, position: Vector3, size: Vector2, spacing: number?)
	local spawn = Config.LobbySpawn
	local lift = 3 -- gap between the ground and the bottom of the board
	local center = position + Vector3.new(0, lift + size.Y / 2, 0)

	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	local board = part({
		Name = "Board",
		Size = Vector3.new(size.X, size.Y, 1),
		CFrame = CFrame.lookAt(center, Vector3.new(spawn.X, center.Y, spawn.Z)),
		Color = Color3.fromRGB(70, 46, 32),
		Parent = model,
	})
	local postHeight = lift + size.Y
	for _, side in { -1, 1 } do
		part({
			Name = "Post",
			Size = Vector3.new(1.4, postHeight, 1.4),
			CFrame = board.CFrame * CFrame.new(side * (size.X / 2 + 0.7), postHeight / 2 - (lift + size.Y / 2), 0),
			Color = Color3.fromRGB(255, 196, 40),
			Parent = model,
		})
	end

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front -- lookAt points the front face at the spawn
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 25
	gui.LightInfluence = 0
	gui.Parent = board

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 16)
	padding.PaddingBottom = UDim.new(0, 16)
	padding.PaddingLeft = UDim.new(0, 22)
	padding.PaddingRight = UDim.new(0, 22)
	padding.Parent = gui

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, spacing or 8)
	list.Parent = gui

	return board, gui
end

-- Outlined cartoon text for signboards.
function WorldBuilder.SignLabel(props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	for key, value in props do
		if key ~= "Parent" then
			(label :: any)[key] = value
		end
	end
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(30, 18, 10)
	stroke.Parent = label
	label.Parent = props.Parent
	return label
end

local function buildHowToPlay(map: Folder)
	local _, gui = WorldBuilder.Signboard(map, "HowToPlay", Config.HowToPlayPosition, Vector2.new(22, 17))
	WorldBuilder.SignLabel({
		Text = "HOW TO PLAY",
		Size = UDim2.new(1, 0, 0, 62),
		TextColor3 = Color3.fromRGB(255, 214, 60),
		LayoutOrder = 0,
		Parent = gui,
	})
	for i, text in HOW_TO_PLAY do
		WorldBuilder.SignLabel({
			Text = text,
			Size = UDim2.new(1, 0, 0, 40),
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = i,
			Parent = gui,
		})
	end
end

--------------------------------------------------------------------------------
-- Scenery pieces
--------------------------------------------------------------------------------

local function giantTree(parent: Instance, base: Vector3, height: number, leafColor: Color3, vines: boolean)
	local tree = Instance.new("Model")
	tree.Name = "GiantTree"
	tree.Parent = parent
	local trunkRadius = height * 0.07
	local trunkColor = Color3.fromRGB(110, 76, 50)
	pillar(tree, base - Vector3.new(0, 1, 0), height + 1, trunkRadius, trunkColor, Enum.Material.Wood, "Trunk")
	-- Buttress roots.
	for i = 1, 3 do
		local a = math.rad(i * 120 + rng:NextNumber(-20, 20))
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		beamPart(tree, base + Vector3.new(0, height * 0.18, 0), base + out * trunkRadius * 3 - Vector3.new(0, 0.5, 0), trunkRadius * 0.45, trunkColor, Enum.Material.Wood, "Root")
	end
	-- Canopy.
	local top = base + Vector3.new(0, height, 0)
	for i = 1, 4 do
		local a = math.rad(i * 90 + rng:NextNumber(-25, 25))
		local r = height * rng:NextNumber(0.24, 0.34)
		local offset = Vector3.new(math.cos(a) * r * 0.7, rng:NextNumber(-2, 3), math.sin(a) * r * 0.7)
		local leaf = ball(tree, top + offset, Vector3.new(r * 2, r * 1.4, r * 2), leafColor, Enum.Material.LeafyGrass, "Leaves")
		leaf.CastShadow = true
		if vines and i % 2 == 0 then
			local hang = top + offset - Vector3.new(0, r * 0.6, 0)
			beamPart(tree, hang, hang - Vector3.new(0, rng:NextNumber(8, 16), 0), 0.22, Color3.fromRGB(60, 130, 50), Enum.Material.LeafyGrass, "Vine")
		end
	end
	local crown = ball(tree, top + Vector3.new(0, height * 0.18, 0), Vector3.new(height * 0.5, height * 0.36, height * 0.5), leafColor:Lerp(Color3.new(1, 1, 1), 0.12), Enum.Material.LeafyGrass, "Leaves")
	crown.CastShadow = true
end

local function ruins(parent: Instance, center: Vector3, color: Color3, material: Enum.Material)
	local model = Instance.new("Model")
	model.Name = "Ruins"
	model.Parent = parent
	for i = 1, rng:NextInteger(3, 6) do
		local offset = Vector3.new(rng:NextNumber(-12, 12), 0, rng:NextNumber(-12, 12))
		local height = rng:NextNumber(6, 18)
		local column = pillar(model, center + offset, height, 1.5, color, material, "Column")
		if rng:NextNumber() < 0.3 then
			-- Toppled column.
			column.CFrame = CFrame.new(center + offset + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
		end
		if i == 1 then
			prop({
				Name = "Lintel",
				Size = Vector3.new(10, 1.6, 3),
				CFrame = CFrame.new(center + offset + Vector3.new(3, height + 0.8, 0)) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-8, 8))),
				Color = color,
				Material = material,
				Parent = model,
			})
		end
	end
	for _ = 1, 3 do
		prop({
			Name = "Rubble",
			Size = Vector3.new(rng:NextNumber(2, 4), rng:NextNumber(1.5, 3), rng:NextNumber(2, 4)),
			CFrame = CFrame.new(center + Vector3.new(rng:NextNumber(-14, 14), 1, rng:NextNumber(-14, 14))) * CFrame.Angles(0, rng:NextNumber(0, 3), rng:NextNumber(-0.3, 0.3)),
			Color = color,
			Material = material,
			Parent = model,
		})
	end
end

local function cloud(parent: Instance, center: Vector3)
	for _ = 1, rng:NextInteger(3, 4) do
		local size = rng:NextNumber(14, 30)
		ball(parent, center + Vector3.new(rng:NextNumber(-16, 16), rng:NextNumber(-3, 3), rng:NextNumber(-10, 10)), Vector3.new(size * 1.4, size * 0.6, size), Color3.fromRGB(250, 251, 255), Enum.Material.SmoothPlastic, "Cloud")
	end
end

local function waterfall(parent: Instance, top: Vector3, height: number)
	local fall = prop({
		Name = "Waterfall",
		Size = Vector3.new(8, height, 1.5),
		CFrame = CFrame.new(top - Vector3.new(0, height / 2, 0)),
		Color = Color3.fromRGB(150, 210, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.35,
		CastShadow = false,
		Parent = parent,
	})
	emitter(fall, {
		Rate = 14,
		Lifetime = NumberRange.new(1, 1.6),
		Speed = NumberRange.new(20, 28),
		EmissionDirection = Enum.NormalId.Bottom,
		Size = NumberSequence.new(1.5, 3),
		Transparency = NumberSequence.new(0.4, 1),
		Color = ColorSequence.new(Color3.fromRGB(230, 245, 255)),
	})
	local mist = prop({
		Name = "Mist",
		Size = Vector3.new(10, 1, 10),
		CFrame = CFrame.new(top - Vector3.new(0, height, 0)),
		Transparency = 1,
		Parent = parent,
	})
	emitter(mist, {
		Rate = 10,
		Lifetime = NumberRange.new(1.5, 2.5),
		Speed = NumberRange.new(3, 6),
		SpreadAngle = Vector2.new(80, 80),
		EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 10) }),
		Transparency = NumberSequence.new(0.6, 1),
		Color = ColorSequence.new(Color3.fromRGB(240, 250, 255)),
	})
end

local function pine(parent: Instance, base: Vector3, height: number)
	local tree = Instance.new("Model")
	tree.Name = "Pine"
	tree.Parent = parent
	pillar(tree, base, height * 0.3, height * 0.05, Color3.fromRGB(90, 62, 44), Enum.Material.Wood, "Trunk")
	for tier = 0, 2 do
		local radius = height * (0.32 - tier * 0.08)
		local y = height * (0.25 + tier * 0.22)
		pillar(tree, base + Vector3.new(0, y, 0), height * 0.18, radius, Color3.fromRGB(40, 100, 70), Enum.Material.LeafyGrass, "Needles")
		pillar(tree, base + Vector3.new(0, y + height * 0.18, 0), 0.6, radius * 0.85, Color3.fromRGB(245, 250, 255), Enum.Material.Snow, "Snow")
	end
end

local function iceCrystals(parent: Instance, base: Vector3)
	for _ = 1, rng:NextInteger(3, 5) do
		local height = rng:NextNumber(8, 22)
		local tilt = CFrame.Angles(rng:NextNumber(-0.35, 0.35), rng:NextNumber(0, math.pi), rng:NextNumber(-0.35, 0.35))
		local crystal = prop({
			Name = "IceCrystal",
			Size = Vector3.new(2.4, height, 2.4),
			CFrame = CFrame.new(base + Vector3.new(rng:NextNumber(-4, 4), height * 0.4, rng:NextNumber(-4, 4))) * tilt,
			Color = Color3.fromRGB(160, 220, 255),
			Material = Enum.Material.Glass,
			Transparency = 0.2,
			Reflectance = 0.2,
			Parent = parent,
		})
		crystal.CastShadow = false
	end
end

local function cityTower(parent: Instance, base: Vector3, width: number, height: number)
	local tower = Instance.new("Model")
	tower.Name = "Tower"
	tower.Parent = parent
	prop({
		Name = "Body",
		Size = Vector3.new(width, height, width),
		CFrame = CFrame.new(base + Vector3.new(0, height / 2, 0)),
		Color = Color3.fromRGB(22, 22, 34),
		Material = Enum.Material.Glass,
		Reflectance = 0.15,
		Parent = tower,
	})
	local accent = if rng:NextNumber() < 0.5 then Color3.fromRGB(0, 230, 255) else Color3.fromRGB(255, 60, 200)
	for _, corner in { Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1) } do
		prop({
			Name = "Trim",
			Size = Vector3.new(0.5, height, 0.5),
			CFrame = CFrame.new(base + Vector3.new(corner.X * width / 2, height / 2, corner.Z * width / 2)),
			Color = accent,
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = tower,
		})
	end
	local band = rng:NextNumber(0.4, 0.8)
	prop({
		Name = "Band",
		Size = Vector3.new(width + 0.3, 0.6, width + 0.3),
		CFrame = CFrame.new(base + Vector3.new(0, height * band, 0)),
		Color = accent,
		Material = Enum.Material.Neon,
		CastShadow = false,
		Parent = tower,
	})
end

--------------------------------------------------------------------------------
-- Biome scenery
--------------------------------------------------------------------------------

local function buildSkyKingdom(deco: Folder, from: number, to: number)
	-- Giant trees and ruins by the lane, clouds and waterfalls overhead.
	for d = math.max(from, -150), to, 70 do
		local x = sideX(LANE_GROUND_HALF + 8, 110)
		giantTree(deco, Vector3.new(x, Config.GroundY, -(d + rng:NextNumber(0, 40))), rng:NextNumber(24, 36), Color3.fromRGB(96, 186, 80), false)
	end
	for _ = 1, 4 do
		ruins(deco, Vector3.new(sideX(60, 100), Config.GroundY, -rng:NextNumber(from + 60, to)), Color3.fromRGB(226, 218, 200), Enum.Material.Limestone)
	end
	for _ = 1, 26 do
		cloud(deco, Vector3.new(rng:NextNumber(-420, 420), rng:NextNumber(70, 140), -rng:NextNumber(from, to + 300)))
	end
	for _, fall in WATERFALLS do
		waterfall(deco, fall.Top, fall.Height)
	end
	-- A wooden bridge over the river.
	local bridgeD = 120
	for i = 0, 9 do
		prop({
			Name = "BridgePlank",
			Size = Vector3.new(4.6, 0.6, 10),
			CFrame = CFrame.new(-172 + i * 4.8, Config.GroundY + 0.8 + math.sin(i / 9 * math.pi) * 2, -bridgeD),
			Color = Color3.fromRGB(150, 100, 60),
			Material = Enum.Material.WoodPlanks,
			Parent = deco,
		})
	end
end

local function buildJungle(deco: Folder, from: number, to: number)
	for d = from, to, 46 do
		local x = sideX(LANE_GROUND_HALF + 6, 140)
		giantTree(deco, Vector3.new(x, Config.GroundY, -(d + rng:NextNumber(0, 30))), rng:NextNumber(34, 52), Color3.fromRGB(56, 140, 56), true)
	end
	for _ = 1, 6 do
		ruins(deco, Vector3.new(sideX(56, 120), Config.GroundY, -rng:NextNumber(from + 30, to - 30)), Color3.fromRGB(116, 128, 100), Enum.Material.Cobblestone)
	end
	-- A stepped temple in the distance.
	local templeCenter = Vector3.new(-230, Config.GroundY, -(from + (to - from) * 0.55))
	for step = 0, 5 do
		local size = 70 - step * 11
		part({
			Name = "TempleStep",
			Size = Vector3.new(size, 7, size),
			CFrame = CFrame.new(templeCenter + Vector3.new(0, 3.5 + step * 7, 0)),
			Color = Color3.fromRGB(120 + step * 4, 130 + step * 3, 104),
			Material = Enum.Material.Cobblestone,
			Parent = deco,
		})
	end
	prop({
		Name = "TempleShrine",
		Size = Vector3.new(10, 9, 10),
		CFrame = CFrame.new(templeCenter + Vector3.new(0, 46.5, 0)),
		Color = Color3.fromRGB(90, 200, 120),
		Material = Enum.Material.Neon,
		Parent = deco,
	})
end

local function buildVolcanic(deco: Folder, from: number, to: number)
	-- Basalt spires lean over the lane edges.
	for d = from, to, 26 do
		local height = rng:NextNumber(10, 34)
		local x = sideX(LANE_GROUND_HALF - 10, 120)
		prop({
			Name = "Spire",
			ClassName = "WedgePart",
			Size = Vector3.new(rng:NextNumber(5, 9), height, rng:NextNumber(5, 9)),
			CFrame = CFrame.new(x, Config.GroundY + height / 2 - 1, -(d + rng:NextNumber(0, 20)))
				* CFrame.Angles(rng:NextNumber(-0.15, 0.15), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.15, 0.15)),
			Color = Color3.fromRGB(46, 40, 44),
			Material = Enum.Material.Basalt,
			Parent = deco,
		})
	end
	-- Lava rivers glowing either side of the lane.
	for _, side in { -1, 1 } do
		local d = from
		while d < to do
			local length = math.min(120, to - d)
			prop({
				Name = "Lava",
				Size = Vector3.new(10, 0.4, length),
				CFrame = CFrame.new(side * 84, Config.GroundY + 0.05, -(d + length / 2)),
				Color = Color3.fromRGB(255, 110, 30),
				Material = Enum.Material.Neon,
				CastShadow = false,
				Parent = deco,
			})
			d += length
		end
	end
	-- Glowing cracks across the lane: the floor here is lava.
	for d = from + 10, math.min(to, Config.LaneLength), 22 do
		prop({
			Name = "LavaCrack",
			Size = Vector3.new(rng:NextNumber(10, 26), 0.12, rng:NextNumber(0.5, 1.1)),
			CFrame = CFrame.new(rng:NextNumber(-26, 26), Config.GroundY + 0.04, -(d + rng:NextNumber(0, 12)))
				* CFrame.Angles(0, rng:NextNumber(-0.7, 0.7), 0),
			Color = Color3.fromRGB(255, 120, 30),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = deco,
		})
	end
	-- Dead trees.
	for _ = 1, 10 do
		local base = Vector3.new(sideX(LANE_GROUND_HALF + 4, 130), Config.GroundY, -rng:NextNumber(from, to))
		local height = rng:NextNumber(10, 18)
		pillar(deco, base, height, 0.7, Color3.fromRGB(40, 32, 30), Enum.Material.Wood, "DeadTree")
		for b = 1, 2 do
			local a = rng:NextNumber(0, math.pi * 2)
			local start = base + Vector3.new(0, height * (0.5 + b * 0.18), 0)
			beamPart(deco, start, start + Vector3.new(math.cos(a) * 5, 3, math.sin(a) * 5), 0.35, Color3.fromRGB(40, 32, 30), Enum.Material.Wood, "Branch")
		end
	end
	-- Smoking craters on the volcano tops.
	for i, info in { { -420, 0.35 }, { 460, 0.75 } } do
		local size = if i == 1 then 1 else 0.7
		local top = Vector3.new(info[1], Config.GroundY + 9 * 14 * size + 4, -(from + (to - from) * info[2]))
		local crater = prop({
			Name = "Crater",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2, 34 * size, 34 * size),
			CFrame = CFrame.new(top) * CFrame.Angles(0, 0, math.pi / 2),
			Color = Color3.fromRGB(255, 120, 30),
			Material = Enum.Material.Neon,
			Parent = deco,
		})
		emitter(crater, {
			Rate = 6,
			Lifetime = NumberRange.new(6, 9),
			Speed = NumberRange.new(10, 16),
			SpreadAngle = Vector2.new(15, 15),
			EmissionDirection = Enum.NormalId.Right, -- the cylinder's axis points up
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 14), NumberSequenceKeypoint.new(1, 40) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
			Color = ColorSequence.new(Color3.fromRGB(70, 60, 60), Color3.fromRGB(150, 140, 140)),
			Acceleration = Vector3.new(4, 2, 0),
		})
	end
end

local function buildFrozen(deco: Folder, from: number, to: number)
	for d = from, to, 30 do
		pine(deco, Vector3.new(sideX(LANE_GROUND_HALF + 4, 150), Config.GroundY, -(d + rng:NextNumber(0, 24))), rng:NextNumber(14, 26))
	end
	for d = from + 20, to, 90 do
		iceCrystals(deco, Vector3.new(sideX(50, 90), Config.GroundY, -(d + rng:NextNumber(0, 40))))
	end
	-- Aurora: glowing ribbons across the sky.
	local anchor = prop({
		Name = "AuroraAnchor",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(0, 260, -(from + to) / 2),
		Transparency = 1,
		Parent = deco,
	})
	for i = 1, 4 do
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(-700, rng:NextNumber(-40, 40), (i - 2.5) * 120)
		a0.Parent = anchor
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(700, rng:NextNumber(-40, 40), (i - 2.5) * 120 + rng:NextNumber(-80, 80))
		a1.Parent = anchor
		local beam = Instance.new("Beam")
		beam.Name = "Aurora"
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Width0 = rng:NextNumber(60, 100)
		beam.Width1 = rng:NextNumber(60, 100)
		beam.CurveSize0 = rng:NextNumber(-260, 260)
		beam.CurveSize1 = rng:NextNumber(-260, 260)
		beam.Segments = 24
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(60, 255, 160)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(60, 200, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 90, 255)),
		})
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, 0.55),
			NumberSequenceKeypoint.new(0.8, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		})
		beam.Parent = anchor
	end
end

local function buildNeon(deco: Folder, from: number, to: number)
	for d = from, to, 34 do
		local width = rng:NextNumber(14, 26)
		cityTower(deco, Vector3.new(sideX(LANE_GROUND_HALF + width / 2 + 4, 170), Config.GroundY, -(d + rng:NextNumber(0, 20))), width, rng:NextNumber(40, 140))
	end
	-- Glowing grid across the lane.
	for d = from, math.min(to, Config.LaneLength), 40 do
		prop({
			Name = "GridLine",
			Size = Vector3.new(LANE_GROUND_HALF * 2, 0.15, 0.5),
			CFrame = CFrame.new(0, Config.GroundY + 0.05, -d),
			Color = Color3.fromRGB(60, 120, 255),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = deco,
		})
	end
	for _, x in { -20, 20 } do
		prop({
			Name = "GridLine",
			Size = Vector3.new(0.5, 0.15, to - from),
			CFrame = CFrame.new(x, Config.GroundY + 0.05, -(from + to) / 2),
			Color = Color3.fromRGB(255, 60, 200),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = deco,
		})
	end
	-- Holographic rings floating above the lane.
	for i = 1, 4 do
		local d = from + (to - from) * (i / 5)
		ring(deco, CFrame.new(0, 70 + i * 6, -d), 40 + i * 4, 1.2, if i % 2 == 0 then Color3.fromRGB(0, 230, 255) else Color3.fromRGB(255, 60, 200), 18)
	end
	-- Billboards.
	for i, text in { "OVERDRIVE", "VELOCITY", "MAX SPEED" } do
		local x = if i % 2 == 0 then 90 else -90
		local board = sign(deco, Vector3.new(30, 12, 1), CFrame.new(x, 40, -(from + i * (to - from) / 4)), text, Color3.fromRGB(16, 14, 30), Color3.fromRGB(120, 240, 255), Enum.Material.SmoothPlastic)
		board.CastShadow = false
	end
end

--------------------------------------------------------------------------------
-- Lighting (the client blends per-biome presets on top of this)
--------------------------------------------------------------------------------

local function setupLighting()
	local preset = Config.Zones[1].Lighting
	Lighting.ClockTime = preset.ClockTime
	Lighting.Brightness = preset.Brightness
	Lighting.Ambient = preset.Ambient
	Lighting.OutdoorAmbient = preset.OutdoorAmbient
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.3

	for _, child in Lighting:GetChildren() do
		if child:IsA("Atmosphere") or child:IsA("PostEffect") or child:IsA("Sky") then
			child:Destroy()
		end
	end

	local sky = Instance.new("Sky")
	sky.StarCount = 3000
	sky.CelestialBodiesShown = true
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 9
	sky.Parent = Lighting

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = preset.Density
	atmosphere.Offset = 0.2
	atmosphere.Color = preset.AtmosphereColor
	atmosphere.Decay = preset.Decay
	atmosphere.Glare = preset.Glare
	atmosphere.Haze = preset.Haze
	atmosphere.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = preset.Bloom
	bloom.Size = 28
	bloom.Threshold = 1.4
	bloom.Parent = Lighting

	local color = Instance.new("ColorCorrectionEffect")
	color.Saturation = preset.Saturation
	color.Contrast = preset.Contrast
	color.TintColor = preset.Tint
	color.Brightness = 0.02
	color.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.06
	rays.Spread = 0.6
	rays.Parent = Lighting
end

function WorldBuilder.Build()
	local existing = Workspace:FindFirstChild("Map")
	if existing then
		existing:Destroy()
	end

	local map = Instance.new("Folder")
	map.Name = "Map"

	-- Terrain failing (e.g. an engine limit) must never stop the game loading.
	local ok, err = pcall(buildBaseTerrain)
	if ok then
		local featuresOk, featuresErr = pcall(buildTerrainFeatures)
		if not featuresOk then
			warn("[SlingSmash] Some terrain scenery failed:", featuresErr)
		end
	else
		warn("[SlingSmash] Terrain build failed, using plain ground:", err)
		buildFallbackGround(map)
	end

	buildLane(map)
	buildSlingshot(map)
	buildHowToPlay(map)

	local deco = Instance.new("Folder")
	deco.Name = "Decorations"
	deco.Parent = map
	local builders = { buildSkyKingdom, buildJungle, buildVolcanic, buildFrozen, buildNeon }
	for index, builder in builders do
		local from, to = zoneRange(index)
		local folder = Instance.new("Folder")
		folder.Name = Config.Zones[index].Key
		folder.Parent = deco
		builder(folder, from, to)
	end

	map.Parent = Workspace
	setupLighting()
	return map
end

return WorldBuilder
