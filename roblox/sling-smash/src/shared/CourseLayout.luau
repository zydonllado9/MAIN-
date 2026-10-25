--[[
	Deterministic obstacle course layout.

	The client builds its own copy of the course from this data (so every player
	gets a fresh, smashable course for each launch) and the server uses the same
	data to sanity-check launch reports. RunSim simulates flights against it.

	Each row of the course sits at a distance d down the lane:
	  d        smashable structures (walls, towers, pyramids)
	  d + 10   stars and power-up orbs (in the air)
	  d + 20   floating walls (from the Jungle on)
	  d + 24   hazards: swinging logs (Jungle), laser barriers (Neon)
	  d + 28   boost rings
	  d + 32   ground helpers: bounce pads, geysers (Volcanic), updrafts (Sky)
	Rows are 40-60 studs apart, so nothing from one row overlaps the next.
]]

local Config = require(script.Parent.Config)

local CourseLayout = {}

CourseLayout.Bucket = 16 -- studs per distance bucket for fast lookups

-- The distance bucket a spot belongs to (shared by RunSim and the visuals).
function CourseLayout.BucketOf(distance: number): number
	return math.floor(distance / CourseLayout.Bucket)
end

local cached = nil

function CourseLayout.ZoneIndexAt(distance: number): number
	for index, zone in Config.Zones do
		if distance < zone.EndsAt then
			return index
		end
	end
	return #Config.Zones
end

-- Chance of each special block kind per biome (by Zone.Key).
local KIND_CHANCES = {
	Sky = { TNT = 0.045, Gold = 0.03, Armor = 0, Ice = 0 },
	Jungle = { TNT = 0.04, Gold = 0.03, Armor = 0.08, Ice = 0 },
	Volcanic = { TNT = 0.07, Gold = 0.03, Armor = 0.09, Ice = 0 },
	Frozen = { TNT = 0.04, Gold = 0.03, Armor = 0.04, Ice = 0.55 },
	Neon = { TNT = 0.05, Gold = 0.035, Armor = 0.11, Ice = 0 },
}

-- Each biome opens with the power-up that suits it best.
local SIGNATURE = {
	Jungle = "Meteor", -- armored ruins
	Volcanic = "Shockwave",
	Frozen = "Rift",
	Neon = "Phase", -- laser barriers
}

-- Power-up weights per biome.
local PICKUP_WEIGHTS = {
	Sky = { Meteor = 3, Rift = 3, Phase = 1, Shockwave = 1 },
	Jungle = { Meteor = 3, Rift = 1, Phase = 3, Shockwave = 2 },
	Volcanic = { Meteor = 3, Rift = 2, Phase = 1, Shockwave = 3 },
	Frozen = { Meteor = 2, Rift = 3, Phase = 1, Shockwave = 3 },
	Neon = { Meteor = 2, Rift = 1, Phase = 4, Shockwave = 2 },
}

local function pickKind(rng: Random, zoneKey: string, allowArmor: boolean): string
	local chances = KIND_CHANCES[zoneKey] or KIND_CHANCES.Sky
	local roll = rng:NextNumber()
	if roll < chances.TNT then
		return "TNT"
	end
	roll -= chances.TNT
	if roll < chances.Gold then
		return "Gold"
	end
	roll -= chances.Gold
	if roll < chances.Armor then
		return if allowArmor then "Armor" else "Block"
	end
	roll -= chances.Armor
	if roll < chances.Ice then
		return "Ice"
	end
	return "Block"
end

local function pickWeighted(rng: Random, weights: { [string]: number }): string
	local total = 0
	for _, key in Config.AbilityOrder do
		total += weights[key] or 0
	end
	local roll = rng:NextNumber() * total
	for _, key in Config.AbilityOrder do
		roll -= weights[key] or 0
		if roll <= 0 then
			return key
		end
	end
	return Config.AbilityOrder[1]
end

function CourseLayout.Get()
	if cached then
		return cached
	end

	local rng = Random.new(Config.CourseSeed)
	local size = Config.BlockSize
	local halfLane = Config.LaneWidth / 2 - 2
	local blocks = {}
	local stars = {}
	local rings = {}
	local pickups = {}
	local barriers = {}
	local logs = {}
	local geysers = {}
	local updrafts = {}
	local pads = {}

	-- x is the block centre, level counts blocks up from the ground.
	local function addBlock(x: number, level: number, distance: number, kind: string, zone: number, colorIndex: number)
		table.insert(blocks, {
			Id = #blocks + 1,
			Position = Vector3.new(x, Config.GroundY + size / 2 + level * size, -distance),
			Kind = kind,
			Zone = zone,
			ColorIndex = colorIndex,
		})
	end

	local function wall(cx: number, distance: number, width: number, height: number, baseLevel: number, zone: number, allowArmor: boolean)
		local colorIndex = rng:NextInteger(1, 4)
		local key = Config.Zones[zone].Key
		for i = 0, width - 1 do
			for j = 0, height - 1 do
				addBlock(cx + (i - (width - 1) / 2) * size, baseLevel + j, distance, pickKind(rng, key, allowArmor), zone, colorIndex)
			end
		end
	end

	local function tower(cx: number, distance: number, height: number, zone: number)
		local colorIndex = rng:NextInteger(1, 4)
		local key = Config.Zones[zone].Key
		-- Jungle and Volcanic towers often stand on armored foundations.
		local foundation = (key == "Jungle" or key == "Volcanic") and rng:NextNumber() < 0.45
		for i = 0, 1 do
			for k = 0, 1 do
				for j = 0, height - 1 do
					local kind = if foundation and j < 2 then "Armor" else pickKind(rng, key, true)
					addBlock(cx + (i - 0.5) * size, j, distance + k * size, kind, zone, colorIndex)
				end
			end
		end
	end

	local function pyramid(cx: number, distance: number, base: number, zone: number)
		local colorIndex = rng:NextInteger(1, 4)
		local key = Config.Zones[zone].Key
		for level = 0, base - 1 do
			local count = base - level
			for i = 0, count - 1 do
				addBlock(cx + (i - (count - 1) / 2) * size, level, distance, pickKind(rng, key, true), zone, colorIndex)
			end
		end
	end

	-- Picks a centre so a structure of halfWidth fits between minX and maxX.
	local function centerIn(minX: number, maxX: number, halfWidth: number): number
		local low, high = minX + halfWidth, maxX - halfWidth
		if low >= high then
			return (minX + maxX) / 2
		end
		return rng:NextNumber(low, high)
	end

	local function addPickup(kind: string, position: Vector3, zone: number)
		table.insert(pickups, { Id = #pickups + 1, Kind = kind, Position = position, Zone = zone })
	end

	-- The first wall sits right in front of the slingshot so even a weak
	-- first launch smashes something, and a Shockwave orb waits just after it
	-- to show new players what power-ups do.
	wall(0, Config.CourseStart, 5, 5, 0, 1, false)
	addPickup("Shockwave", Vector3.new(0, Config.GroundY + 8, -(Config.CourseStart + 25)), 1)

	local distance = Config.CourseStart + 45
	local row = 0
	local previousZone = 1
	while distance < Config.LaneLength - 60 do
		row += 1
		local zone = CourseLayout.ZoneIndexAt(distance)
		local key = Config.Zones[zone].Key
		local firstRowOfBiome = zone ~= previousZone
		previousZone = zone
		local fullWall = row % 9 == 0
		local hasLog = false
		-- Hazards and helpers sit a little further down the lane than the row,
		-- so only place them if that spot is still in the same biome.
		local function sameBiome(offset: number): boolean
			return CourseLayout.ZoneIndexAt(distance + offset) == zone
		end

		if fullWall then
			-- Full-width wall: you can't steer around this one (so no armor in it).
			local width = math.floor((Config.LaneWidth - 4) / size)
			wall(0, distance, width, rng:NextInteger(2, 3), 0, zone, false)
		else
			local count = if rng:NextNumber() < 0.55 then 2 else 1
			for n = 1, count do
				local minX, maxX = -halfLane, halfLane
				if count == 2 then
					if n == 1 then
						maxX = -3
					else
						minX = 3
					end
				end

				local roll = rng:NextNumber()
				if roll < 0.5 then
					local width = rng:NextInteger(3, 7)
					local height = rng:NextInteger(3, 6)
					wall(centerIn(minX, maxX, width * size / 2), distance, width, height, 0, zone, true)
				elseif roll < 0.78 then
					tower(centerIn(minX, maxX, size), distance, rng:NextInteger(6, 12), zone)
				else
					local base = rng:NextInteger(3, 5)
					pyramid(centerIn(minX, maxX, base * size / 2), distance, base, zone)
				end
			end

			-- Hazards never share a row with a full-width wall.
			if key == "Jungle" and rng:NextNumber() < 0.55 and sameBiome(30) then
				hasLog = true
				table.insert(logs, {
					Id = #logs + 1,
					Pivot = Vector3.new(rng:NextNumber(-18, 18), Config.GroundY + 27, -(distance + 24)),
					Length = 22,
					Swing = math.rad(rng:NextNumber(45, 60)),
					Period = rng:NextNumber(2.2, 3),
					Offset = rng:NextNumber(0, math.pi * 2),
					Zone = zone,
				})
			elseif key == "Neon" and rng:NextNumber() < 0.6 and sameBiome(30) then
				-- Either a low full-width laser (fly over it) or a tall narrow one (steer around it).
				if rng:NextNumber() < 0.5 then
					table.insert(barriers, {
						Id = #barriers + 1,
						Position = Vector3.new(0, Config.GroundY, -(distance + 24)),
						Width = Config.LaneWidth,
						Height = 9,
						Zone = zone,
					})
				else
					local width = rng:NextInteger(14, 24)
					table.insert(barriers, {
						Id = #barriers + 1,
						Position = Vector3.new(centerIn(-halfLane, halfLane, width / 2), Config.GroundY, -(distance + 24)),
						Width = width,
						Height = 42,
						Zone = zone,
					})
				end
			end
		end

		-- Floating walls reward high launches later in the course.
		if zone >= 2 and not hasLog and rng:NextNumber() < 0.25 then
			local width = rng:NextInteger(3, 6)
			wall(
				centerIn(-halfLane, halfLane, width * size / 2),
				distance + 20,
				width,
				2,
				rng:NextInteger(6, 13),
				zone,
				true
			)
		end

		if rng:NextNumber() < 0.6 then
			table.insert(stars, {
				Id = #stars + 1,
				Position = Vector3.new(
					rng:NextNumber(-halfLane + 10, halfLane - 10),
					Config.GroundY + rng:NextNumber(6, 34),
					-(distance + rng:NextNumber(10, 25))
				),
				Zone = zone,
			})
		end

		if firstRowOfBiome and SIGNATURE[key] then
			addPickup(SIGNATURE[key], Vector3.new(0, Config.GroundY + 9, -(distance + 12)), zone)
		elseif rng:NextNumber() < 0.25 then
			addPickup(
				pickWeighted(rng, PICKUP_WEIGHTS[key] or PICKUP_WEIGHTS.Sky),
				Vector3.new(rng:NextNumber(-halfLane + 8, halfLane - 8), Config.GroundY + rng:NextNumber(5, 16), -(distance + 12)),
				zone
			)
		end

		local ringChance = if key == "Neon" then 0.55 else 0.3
		if rng:NextNumber() < ringChance then
			table.insert(rings, {
				Id = #rings + 1,
				Position = Vector3.new(rng:NextNumber(-18, 18), Config.GroundY + rng:NextNumber(6, 22), -(distance + 28)),
				Zone = zone,
				Big = key == "Neon",
			})
		end

		-- Ground helpers.
		local groundD = distance + 32
		if not sameBiome(40) then
			-- Too close to the next biome for ground helpers.
		elseif key == "Volcanic" then
			local count = if rng:NextNumber() < 0.5 then 2 else 1
			for n = 1, count do
				local x = if count == 2 then (if n == 1 then rng:NextNumber(-30, -8) else rng:NextNumber(8, 30)) else rng:NextNumber(-24, 24)
				table.insert(geysers, {
					Id = #geysers + 1,
					Position = Vector3.new(x, Config.GroundY, -groundD),
					Period = rng:NextNumber(2.6, 3.6),
					Active = 1.2,
					Offset = rng:NextNumber(0, 3),
					Zone = zone,
				})
			end
		elseif key == "Sky" and rng:NextNumber() < 0.35 then
			local x = (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(12, 28)
			table.insert(updrafts, {
				Id = #updrafts + 1,
				Position = Vector3.new(x, Config.GroundY, -groundD),
				Zone = zone,
			})
			-- A star waits at the top of each updraft.
			table.insert(stars, {
				Id = #stars + 1,
				Position = Vector3.new(x, Config.GroundY + rng:NextNumber(46, 60), -groundD),
				Zone = zone,
			})
		elseif key ~= "Frozen" and rng:NextNumber() < (if key == "Neon" then 0.2 else 0.28) then
			table.insert(pads, {
				Id = #pads + 1,
				Position = Vector3.new(rng:NextNumber(-26, 26), Config.GroundY, -groundD),
				Zone = zone,
			})
		end

		distance += rng:NextNumber(40, 60)
	end

	cached = {
		Blocks = blocks,
		Stars = stars,
		Rings = rings,
		Pickups = pickups,
		Barriers = barriers,
		Logs = logs,
		Geysers = geysers,
		Updrafts = updrafts,
		Pads = pads,
		TotalBlocks = #blocks,
	}
	return cached
end

--------------------------------------------------------------------------------
-- Moving hazards. Both the simulation and the visuals use these, so what you
-- see is exactly what you hit.
--------------------------------------------------------------------------------

-- Swing angle of a log at time t (radians, 0 = hanging straight down).
function CourseLayout.LogAngle(log, t: number): number
	return log.Swing * math.sin(t * math.pi * 2 / log.Period + log.Offset)
end

-- Centre of the log's heavy end at time t.
function CourseLayout.LogHead(log, t: number): Vector3
	local angle = CourseLayout.LogAngle(log, t)
	return log.Pivot + Vector3.new(math.sin(angle) * log.Length, -math.cos(angle) * log.Length, 0)
end

-- Whether a geyser is erupting at time t, and how far into the eruption (0..1).
function CourseLayout.GeyserState(geyser, t: number): (boolean, number)
	local phase = (t + geyser.Offset) % geyser.Period
	if phase < geyser.Active then
		return true, phase / geyser.Active
	end
	return false, 0
end

return CourseLayout
