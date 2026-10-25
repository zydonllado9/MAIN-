--[[
	Sling Smash - shared configuration.

	Every tunable number in the game lives here so it can be balanced without
	touching gameplay code. Both the server and the client require this module.
]]

local Config = {}

Config.GameName = "SLING SMASH"
Config.DataStoreName = "SlingSmash_PlayerData_v1"
Config.AutosaveInterval = 120

--------------------------------------------------------------------------------
-- World layout
--------------------------------------------------------------------------------

Config.GroundY = 0
Config.Forward = Vector3.new(0, 0, -1) -- launch direction (down the lane)
Config.Right = Vector3.new(1, 0, 0)
Config.LaneWidth = 80
Config.LaneLength = 3000
Config.LobbySpawn = Vector3.new(0, 0.5, 70)
Config.ReturnPoint = Vector3.new(0, 4, 32)
Config.LeaderboardPosition = Vector3.new(-30, 0, 46) -- "Top Launches" board
Config.HowToPlayPosition = Vector3.new(30, 0, 46) -- "How to Play" sign
Config.LeaderboardStoreName = "SlingSmash_BestDistance_v1"

-- The slingshot stands at the origin and fires towards Config.Forward.
Config.SlingshotPosition = Vector3.new(0, 0, 0)
Config.SlingshotArmTip = 12.8 -- height of the band anchor points
Config.SlingshotArmSpread = 2.96 -- half distance between the two arm tips
Config.PouchHeight = 11 -- character height while sitting in the pouch
Config.PouchRestOffset = 3 -- studs behind the slingshot at 0% power
Config.PouchPullDistance = 8 -- extra studs pulled back at 100% power

Config.BlockSize = 4
Config.CourseSeed = 1337
Config.CourseStart = 50

-- Five biomes along the lane. Each one has its own look, lighting, weather,
-- ground rule and obstacle mix (see CourseLayout). Index ids "ZoneN" follow
-- the order here.
Config.Zones = {
	{
		Name = "Sky Kingdom",
		Key = "Sky",
		Icon = "🏰",
		EndsAt = 550,
		ValueMult = 1,
		Ground = "Grass", -- ground rule, see Config.GroundRules
		Weather = "Wisps",
		BannerColor = Color3.fromRGB(255, 226, 120),
		LaneMaterial = Enum.Material.Grass,
		SideMaterial = Enum.Material.LeafyGrass,
		TerrainColors = { Grass = Color3.fromRGB(106, 190, 76), LeafyGrass = Color3.fromRGB(88, 160, 66) },
		BlockMaterial = Enum.Material.WoodPlanks,
		BlockFx = "Wood",
		BlockColors = {
			Color3.fromRGB(196, 132, 78),
			Color3.fromRGB(170, 104, 62),
			Color3.fromRGB(214, 160, 96),
			Color3.fromRGB(150, 96, 60),
		},
		Lighting = {
			ClockTime = 15.6,
			Brightness = 2.6,
			Ambient = Color3.fromRGB(120, 115, 125),
			OutdoorAmbient = Color3.fromRGB(160, 150, 150),
			Density = 0.3,
			Haze = 1.4,
			Glare = 0.25,
			AtmosphereColor = Color3.fromRGB(210, 225, 255),
			Decay = Color3.fromRGB(150, 180, 235),
			Tint = Color3.fromRGB(255, 248, 240),
			Saturation = 0.2,
			Contrast = 0.08,
			Bloom = 0.6,
		},
	},
	{
		Name = "Ancient Jungle",
		Key = "Jungle",
		Icon = "🌴",
		EndsAt = 1150,
		ValueMult = 2.5,
		Ground = "Grass",
		Weather = "Leaves",
		BannerColor = Color3.fromRGB(140, 255, 120),
		LaneMaterial = Enum.Material.LeafyGrass,
		SideMaterial = Enum.Material.Mud,
		TerrainColors = { Mud = Color3.fromRGB(92, 72, 50) },
		BlockMaterial = Enum.Material.Cobblestone,
		BlockFx = "Stone",
		BlockColors = {
			Color3.fromRGB(128, 140, 112),
			Color3.fromRGB(104, 122, 92),
			Color3.fromRGB(150, 150, 128),
			Color3.fromRGB(96, 110, 88),
		},
		Lighting = {
			ClockTime = 9.2,
			Brightness = 2.2,
			Ambient = Color3.fromRGB(100, 120, 95),
			OutdoorAmbient = Color3.fromRGB(130, 150, 120),
			Density = 0.42,
			Haze = 2.6,
			Glare = 0.1,
			AtmosphereColor = Color3.fromRGB(200, 230, 190),
			Decay = Color3.fromRGB(110, 150, 110),
			Tint = Color3.fromRGB(235, 255, 230),
			Saturation = 0.25,
			Contrast = 0.05,
			Bloom = 0.5,
		},
	},
	{
		Name = "Volcanic Wasteland",
		Key = "Volcanic",
		Icon = "🌋",
		EndsAt = 1800,
		ValueMult = 5,
		Ground = "Lava",
		Weather = "Embers",
		BannerColor = Color3.fromRGB(255, 140, 60),
		LaneMaterial = Enum.Material.Basalt,
		SideMaterial = Enum.Material.CrackedLava,
		TerrainColors = { Basalt = Color3.fromRGB(56, 50, 52), CrackedLava = Color3.fromRGB(232, 92, 30) },
		BlockMaterial = Enum.Material.Basalt,
		BlockFx = "Stone",
		BlockColors = {
			Color3.fromRGB(70, 60, 62),
			Color3.fromRGB(96, 70, 60),
			Color3.fromRGB(120, 72, 50),
			Color3.fromRGB(58, 52, 56),
		},
		Lighting = {
			ClockTime = 17.9,
			Brightness = 1.9,
			Ambient = Color3.fromRGB(130, 70, 60),
			OutdoorAmbient = Color3.fromRGB(150, 80, 60),
			Density = 0.5,
			Haze = 3,
			Glare = 0.4,
			AtmosphereColor = Color3.fromRGB(255, 150, 110),
			Decay = Color3.fromRGB(120, 40, 30),
			Tint = Color3.fromRGB(255, 215, 195),
			Saturation = 0.15,
			Contrast = 0.15,
			Bloom = 0.9,
		},
	},
	{
		Name = "Frozen Frontier",
		Key = "Frozen",
		Icon = "❄️",
		EndsAt = 2400,
		ValueMult = 10,
		Ground = "Ice",
		Weather = "Snow",
		BannerColor = Color3.fromRGB(170, 230, 255),
		LaneMaterial = Enum.Material.Ice, -- the lane is slippery, so it looks it
		SideMaterial = Enum.Material.Snow,
		TerrainColors = {
			Ice = Color3.fromRGB(176, 218, 245),
			Snow = Color3.fromRGB(236, 244, 255),
			Glacier = Color3.fromRGB(150, 206, 236),
		},
		BlockMaterial = Enum.Material.Snow,
		BlockFx = "Snow",
		BlockColors = {
			Color3.fromRGB(226, 240, 255),
			Color3.fromRGB(190, 220, 245),
			Color3.fromRGB(160, 200, 240),
			Color3.fromRGB(210, 230, 250),
		},
		Lighting = {
			ClockTime = 19.2,
			Brightness = 1.6,
			Ambient = Color3.fromRGB(110, 125, 160),
			OutdoorAmbient = Color3.fromRGB(120, 140, 180),
			Density = 0.36,
			Haze = 1.6,
			Glare = 0.05,
			AtmosphereColor = Color3.fromRGB(200, 220, 255),
			Decay = Color3.fromRGB(90, 120, 200),
			Tint = Color3.fromRGB(225, 240, 255),
			Saturation = 0.05,
			Contrast = 0.1,
			Bloom = 0.8,
		},
	},
	{
		Name = "Neon Velocity",
		Key = "Neon",
		Icon = "⚡",
		EndsAt = math.huge,
		ValueMult = 20,
		Ground = "Grass",
		Weather = "Data",
		BannerColor = Color3.fromRGB(120, 240, 255),
		LaneMaterial = Enum.Material.Asphalt,
		SideMaterial = Enum.Material.Pavement,
		TerrainColors = { Asphalt = Color3.fromRGB(30, 30, 42), Pavement = Color3.fromRGB(44, 42, 60) },
		BlockMaterial = Enum.Material.Neon,
		BlockFx = "Energy",
		BlockColors = {
			Color3.fromRGB(60, 255, 130),
			Color3.fromRGB(0, 210, 255),
			Color3.fromRGB(190, 90, 255),
			Color3.fromRGB(255, 70, 190),
		},
		Lighting = {
			ClockTime = 24.2, -- just after midnight (kept above 24 so blends go forwards)
			Brightness = 1.2,
			Ambient = Color3.fromRGB(80, 70, 120),
			OutdoorAmbient = Color3.fromRGB(80, 70, 120),
			Density = 0.32,
			Haze = 1,
			Glare = 0,
			AtmosphereColor = Color3.fromRGB(120, 90, 200),
			Decay = Color3.fromRGB(40, 20, 90),
			Tint = Color3.fromRGB(230, 220, 255),
			Saturation = 0.35,
			Contrast = 0.2,
			Bloom = 1.4,
		},
	},
}

-- How the ground behaves in each biome.
Config.GroundRules = {
	Grass = {},
	-- The floor is lava: fast landings bounce you back up instead of sliding.
	Lava = { BounceSpeed = 26, MinSpeed = 25, Keep = 0.9 },
	-- Slippery: you slide much further.
	Ice = { DecelMult = 0.25, DragMult = 0.3 },
}

--------------------------------------------------------------------------------
-- Smashing, combos and coins
--------------------------------------------------------------------------------

-- Durability scales impact tiers. Armor only breaks above BreakSpeed (or with
-- Meteor Breaker, TNT and shockwaves); slower hits bounce you off it.
Config.Blocks = {
	Block = { Value = 10, Slowdown = 0.035, Durability = 1 },
	Ice = { Value = 6, Slowdown = 0.006, Durability = 0.4 },
	Gold = { Value = 150, Slowdown = 0.02, Durability = 1.2 },
	TNT = { Value = 25, Slowdown = 0, Durability = 1, BlastRadius = 13, Boost = 22, Lift = 32 },
	Armor = { Value = 60, Slowdown = 0.14, Durability = 3, BreakSpeed = 120 },
}

-- Impact effect tier (1 light .. 4 maximum) from speed and durability.
function Config.ImpactTier(speed: number, durability: number, bonus: number?): number
	local power = speed / (math.max(0.1, durability) * 45)
	local tier = if power < 1.8 then 1 elseif power < 2.8 then 2 elseif power < 4 then 3 else 4
	return math.clamp(tier + (bonus or 0), 1, 4)
end

Config.CritChance = 0.08
Config.CritMultiplier = 3
Config.ComboStep = 6 -- smashes in a chain needed for each +1 multiplier
Config.BaseComboWindow = 1.0
Config.BaseMaxComboMult = 5
Config.StarValue = 300
Config.StarRadius = 3.5
Config.RingRadius = 7
Config.RingBoost = 35
Config.RingLift = 28
Config.BigRingRadius = 9.5 -- Neon Velocity accelerator gates
Config.BigRingBoost = 50
Config.CoinsPerStud = 2
Config.PickupRadius = 4

-- Nitro Overdrive: the mid-air boost (click / Space / A button / NITRO button).
-- An instant kick plus a short burst of thrust.
Config.Boost = {
	BaseCharges = 1, -- everyone gets one; Rocket Fuel adds more
	Impulse = 20, -- studs/s added along the lane instantly
	Thrust = 40, -- studs/s^2 along the lane while thrusting
	ThrustTime = 0.5,
	Lift = 26, -- minimum upward speed after boosting
	Cooldown = 0.35,
}

-- Power-up orbs on the course. Flying through one activates it.
Config.Abilities = {
	Meteor = {
		Name = "METEOR BREAKER",
		Icon = "☄️",
		Duration = 4,
		Color = Color3.fromRGB(255, 120, 40),
		RadiusBonus = 3, -- extra smash radius
	},
	Rift = {
		Name = "GRAVITY RIFT",
		Icon = "🌌",
		Duration = 5,
		Color = Color3.fromRGB(170, 90, 255),
		GravityMult = 0.35,
		PullRadius = 22,
		PullInterval = 0.12,
		PullMax = 8, -- blocks pulled in per tick
	},
	Phase = {
		Name = "PHASE OVERDRIVE",
		Icon = "👻",
		Duration = 4.5,
		Color = Color3.fromRGB(120, 255, 255),
	},
	Shockwave = {
		Name = "DEVASTATION",
		Icon = "💥",
		Duration = 0, -- instant
		Color = Color3.fromRGB(255, 70, 70),
		Radius = 26,
		Lift = 34,
		Boost = 18,
		MaxBlocks = 80,
	},
}
Config.AbilityOrder = { "Meteor", "Rift", "Phase", "Shockwave" }

-- Falling this fast onto the ground triggers a small shockwave.
Config.Slam = { MinSpeed = 85, Radius = 12, Cooldown = 1 }

-- Course hazards and helpers (placed by CourseLayout, simulated by RunSim).
Config.Hazards = {
	Barrier = { SpeedKeep = 0.45 }, -- Neon laser walls
	Log = { Radius = 3.2, Push = 45, Cooldown = 1 }, -- Jungle swinging logs
	Geyser = { Radius = 6, Height = 70, Lift = 75, Push = 8, Cooldown = 0.8 }, -- Volcanic
	Updraft = { Radius = 9, Height = 90, Accel = 150, Drift = 14, MaxTime = 2.5 }, -- Sky Kingdom air columns
	Pad = { Radius = 6, Lift = 80, Push = 15, Cooldown = 0.5 }, -- bounce pads
	BodyRadius = 2, -- flyer size for hazards
	MinExitSpeed = 30, -- pads and geysers always send you forward at least this fast
}

-- Slow motion for TNT and maximum-tier impacts.
Config.SlowMo = {
	Duration = 0.35, -- real seconds
	TimeScale = 0.3,
}

--------------------------------------------------------------------------------
-- Flight physics (custom, simulated on the client)
--------------------------------------------------------------------------------

Config.Flight = {
	BaseSpeed = 95, -- launch speed at 100% power with no upgrades
	MinPower = 0.3, -- a quick tap still launches at 30%
	LaunchAngle = 24, -- default aim, degrees above the horizon
	MinAngle = 10, -- aim limits while in the slingshot
	MaxAngle = 45,
	MaxYaw = 15, -- degrees left/right of the lane
	AimRate = 45, -- degrees per second with keys or a stick
	ChargeTime = 1.3, -- seconds to charge from 0% to 100%
	Gravity = 70,
	AirDrag = 0.05, -- fraction of speed lost per second in the air
	GroundDecel = 40, -- studs/s^2 lost while sliding
	GroundDrag = 0.5, -- extra fraction of speed lost per second while sliding
	Bounce = 0.45, -- vertical speed kept on a bounce
	BounceKeep = 0.88, -- horizontal speed kept on a bounce
	MinBounceSpeed = 14,
	StopSpeed = 5,
	CrawlSpeed = 10, -- slower than this for CrawlTime seconds ends the launch
	CrawlTime = 3.5,
	BodyHeight = 1.3, -- root part height above ground while sliding
	SteerAccel = 60,
	MaxSideSpeed = 40,
	SideDamping = 2,
	MaxFlightTime = 90,
}

--------------------------------------------------------------------------------
-- Upgrade tree (hex grid, axial coordinates, "Start" sits at 0,0)
--------------------------------------------------------------------------------

Config.Roman = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII" }

Config.StartNode = {
	Id = "Start",
	Name = "Start",
	Icon = "🎯",
	Q = 0,
	R = 0,
}

Config.Branches = {
	{
		Key = "LaunchPower",
		Name = "Launch Power",
		Icon = "🚀",
		Description = "+20% launch speed per level.",
		Tiers = 5,
		Origin = { 0, 0 },
		Dir = { 1, -1 },
		Requires = "Start",
		Costs = { 100, 500, 1800, 6000, 20000 },
	},
	{
		Key = "HangTime",
		Name = "Hang Time",
		Icon = "🎈",
		Description = "-12% gravity per level. Stay in the air longer!",
		Tiers = 3,
		Origin = { 0, 0 },
		Dir = { 0, -1 },
		Requires = "Start",
		Costs = { 250, 1500, 8000 },
	},
	{
		Key = "AirControl",
		Name = "Air Control",
		Icon = "💨",
		Description = "+35% steering strength per level.",
		Tiers = 3,
		Origin = { 0, 0 },
		Dir = { -1, 0 },
		Requires = "Start",
		Costs = { 150, 900, 4000 },
	},
	{
		Key = "ComboTime",
		Name = "Combo Time",
		Icon = "🔥",
		Description = "+0.3s to keep your combo alive per level.",
		Tiers = 5,
		Origin = { 0, 0 },
		Dir = { -1, 1 },
		Requires = "Start",
		Costs = { 200, 800, 2500, 7500, 22000 },
	},
	{
		Key = "CoinBonus",
		Name = "Coin Bonus",
		Icon = "💰",
		Description = "+25% coins from everything per level.",
		Tiers = 6,
		Origin = { 0, 0 },
		Dir = { 0, 1 },
		Requires = "Start",
		Costs = { 150, 600, 2000, 6500, 18000, 50000 },
	},
	{
		Key = "SmashPower",
		Name = "Smash Power",
		Icon = "💥",
		Description = "+20% smash coins and -12% slowdown per level.",
		Tiers = 6,
		Origin = { 0, 0 },
		Dir = { 1, 0 },
		Requires = "Start",
		Costs = { 120, 500, 1600, 5000, 15000, 45000 },
	},
	{
		Key = "WreckingBall",
		Name = "Wrecking Ball",
		Icon = "💣",
		Description = "+1.5 studs smash radius per level.",
		Tiers = 3,
		Origin = { 2, 0 },
		Dir = { 1, -1 },
		Requires = "SmashPower2",
		Costs = { 3000, 12000, 40000 },
	},
	{
		Key = "ComboKing",
		Name = "Combo King",
		Icon = "👑",
		Description = "+3 max combo multiplier per level.",
		Tiers = 2,
		Origin = { -3, 3 },
		Dir = { -1, 0 },
		Requires = "ComboTime3",
		Costs = { 10000, 60000 },
	},
	{
		Key = "RocketFuel",
		Name = "Rocket Fuel",
		Icon = "⛽",
		Description = "+1 mid-air rocket boost per launch per level.",
		Tiers = 3,
		Origin = { 2, -2 },
		Dir = { 0, -1 },
		Requires = "LaunchPower2",
		Costs = { 2000, 9000, 30000 },
	},
}

Config.Nodes = {}
Config.NodesById = {}

for _, branch in Config.Branches do
	for tier = 1, branch.Tiers do
		local node = {
			Id = branch.Key .. tier,
			Branch = branch.Key,
			Tier = tier,
			Name = branch.Name .. " " .. Config.Roman[tier],
			Icon = branch.Icon,
			Description = branch.Description,
			Cost = branch.Costs[tier],
			Requires = if tier == 1 then branch.Requires else branch.Key .. (tier - 1),
			Q = branch.Origin[1] + branch.Dir[1] * tier,
			R = branch.Origin[2] + branch.Dir[2] * tier,
		}
		table.insert(Config.Nodes, node)
		Config.NodesById[node.Id] = node
	end
end

-- Returns { [branchKey] = level } for a set of owned node ids.
function Config.GetLevels(upgrades)
	local levels = {}
	for _, branch in Config.Branches do
		local level = 0
		for tier = 1, branch.Tiers do
			if upgrades and upgrades[branch.Key .. tier] then
				level = tier
			else
				break
			end
		end
		levels[branch.Key] = level
	end
	return levels
end

function Config.RebirthMultiplier(rebirths)
	return 1 + Config.Rebirth.BonusPerRebirth * (rebirths or 0)
end

function Config.RebirthCost(rebirths)
	return math.floor(Config.Rebirth.BaseCost * Config.Rebirth.CostGrowth ^ (rebirths or 0))
end

-- Every gameplay stat derived from upgrades + rebirths.
function Config.ComputeStats(upgrades, rebirths)
	local levels = Config.GetLevels(upgrades)
	local flight = Config.Flight
	return {
		Levels = levels,
		LaunchSpeed = flight.BaseSpeed * (1 + 0.2 * levels.LaunchPower),
		Gravity = flight.Gravity * (1 - 0.12 * levels.HangTime),
		Steer = flight.SteerAccel * (1 + 0.35 * levels.AirControl),
		ComboWindow = Config.BaseComboWindow + 0.3 * levels.ComboTime,
		MaxComboMult = Config.BaseMaxComboMult + 3 * levels.ComboKing,
		SmashCoinMult = 1 + 0.2 * levels.SmashPower,
		SmashSlow = math.max(0.25, 1 - 0.12 * levels.SmashPower),
		HitRadius = 4 + 1.5 * levels.WreckingBall,
		BoostCharges = Config.Boost.BaseCharges + levels.RocketFuel,
		CoinMult = (1 + 0.25 * levels.CoinBonus) * Config.RebirthMultiplier(rebirths),
	}
end

function Config.ComboMultiplier(combo, maxMult)
	if combo <= 0 then
		return 1
	end
	return math.min(maxMult, 1 + math.floor(combo / Config.ComboStep))
end

-- The biggest biome coin multiplier.
function Config.MaxZoneMult(): number
	local best = 0
	for _, zone in Config.Zones do
		best = math.max(best, zone.ValueMult)
	end
	return best
end

-- Highest coin value a single smashed block can have before multipliers.
function Config.MaxBlockValue()
	local best = 0
	for _, block in Config.Blocks do
		best = math.max(best, block.Value)
	end
	return best * Config.MaxZoneMult()
end

-- The server's sanity limits for a launch report, given the seconds it took.
-- Shared so the tests can prove honest flights never hit them.
function Config.LaunchLimits(stats, elapsed: number, totalBlocks: number)
	return {
		MaxDistance = math.min(Config.LaneLength + 20, elapsed * stats.LaunchSpeed * 2.5 + 40),
		-- TNT chains and shockwaves smash dozens at once, but never hundreds per second.
		MaxSmashes = math.min(totalBlocks, math.floor(100 + elapsed * 45)),
	}
end

-- Most coins a launch with this many smashes and stars could possibly earn.
function Config.CoinCeiling(stats, smashes: number, stars: number): number
	return (
		smashes * Config.MaxBlockValue() * stats.SmashCoinMult * stats.MaxComboMult * Config.CritMultiplier
		+ stars * Config.StarValue * Config.MaxZoneMult()
	) * stats.CoinMult
end

--------------------------------------------------------------------------------
-- Rebirth, trails, settings, sounds
--------------------------------------------------------------------------------

-- Upper-cases a typed code and strips spaces; nil if it can't be a code.
function Config.NormalizeCode(text: any): string?
	if type(text) ~= "string" or #text > 40 then
		return nil
	end
	local code = string.upper((string.gsub(text, "%s", "")))
	if code == "" or #code > 20 then
		return nil
	end
	return code
end

Config.Rebirth = {
	BaseCost = 100000,
	CostGrowth = 2,
	BonusPerRebirth = 0.5, -- +50% coins per rebirth
}

Config.Trails = {
	{ Id = "None", Name = "No Trail", Price = 0 },
	{
		Id = "Ocean",
		Name = "Ocean",
		Price = 2500,
		Colors = { Color3.fromRGB(0, 170, 255), Color3.fromRGB(0, 255, 210) },
	},
	{
		Id = "Fire",
		Name = "Fire",
		Price = 8000,
		Colors = { Color3.fromRGB(255, 220, 60), Color3.fromRGB(255, 70, 30) },
	},
	{
		Id = "Toxic",
		Name = "Toxic",
		Price = 20000,
		Colors = { Color3.fromRGB(190, 255, 60), Color3.fromRGB(40, 200, 80) },
	},
	{
		Id = "Plasma",
		Name = "Plasma",
		Price = 35000,
		Colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(80, 220, 255), Color3.fromRGB(40, 90, 255) },
	},
	{
		Id = "Galaxy",
		Name = "Galaxy",
		Price = 60000,
		Colors = { Color3.fromRGB(120, 60, 255), Color3.fromRGB(255, 80, 200) },
	},
	{
		Id = "Aurora",
		Name = "Aurora",
		Price = 90000,
		Colors = { Color3.fromRGB(80, 255, 170), Color3.fromRGB(60, 200, 255), Color3.fromRGB(190, 90, 255) },
	},
	{
		Id = "Rainbow",
		Name = "Rainbow",
		Price = 150000,
		Colors = {
			Color3.fromRGB(255, 60, 60),
			Color3.fromRGB(255, 200, 40),
			Color3.fromRGB(60, 230, 90),
			Color3.fromRGB(40, 200, 255),
			Color3.fromRGB(170, 80, 255),
		},
	},
}

Config.TrailsById = {}
for _, trail in Config.Trails do
	Config.TrailsById[trail.Id] = trail
end

Config.DefaultSettings = {
	Music = true,
	SFX = true,
	CameraShake = true, -- shown as "Camera Effects": shake, FOV kicks, hit-stop, roll
	SpeedLines = true,
	Hints = true,
	Performance = false, -- fewer particles, debris and shadows
}

Config.SettingsOrder = { "Music", "SFX", "CameraShake", "SpeedLines", "Hints", "Performance" }

Config.SettingLabels = {
	Music = "Music",
	SFX = "SFX",
	CameraShake = "Camera Effects",
	SpeedLines = "Speed Lines",
	Hints = "Hints",
	Performance = "Performance Mode",
}

-- Effect budgets. The client picks one from the device and Performance Mode
-- (see Client/Quality). Everything that can pile up has a cap here.
Config.Quality = {
	High = {
		Name = "High",
		MaxDebris = 80, -- smashed blocks simulated at once
		DebrisTime = 1.8,
		Particles = 1, -- particle amount multiplier
		FloatText = 26,
		BlockShadows = true,
		ViewAhead = 560, -- course drawn this far ahead of you
		ViewBehind = 60,
		SpeedLines = 24,
		Weather = 1,
		Afterimages = 6,
		Lightning = true,
		HitStop = true,
	},
	Medium = {
		Name = "Medium",
		MaxDebris = 45,
		DebrisTime = 1.4,
		Particles = 0.6,
		FloatText = 16,
		BlockShadows = false,
		ViewAhead = 440,
		ViewBehind = 50,
		SpeedLines = 16,
		Weather = 0.6,
		Afterimages = 4,
		Lightning = true,
		HitStop = true,
	},
	Low = {
		Name = "Low",
		MaxDebris = 20,
		DebrisTime = 1,
		Particles = 0.35,
		FloatText = 8,
		BlockShadows = false,
		ViewAhead = 330,
		ViewBehind = 40,
		SpeedLines = 8,
		Weather = 0.3,
		Afterimages = 2,
		Lightning = false,
		HitStop = false,
	},
}

-- Sounds built into the Roblox client work in every place without uploading
-- anything. The client checks each one loads and swaps in the fallback if not.
-- Paste an "rbxassetid://<id>" into Music to add background music.
Config.Sounds = {
	Music = "",
	Launch = "rbxasset://sounds/action_jump.mp3",
	Wind = "rbxasset://sounds/action_falling.ogg",
	Smash = "rbxasset://sounds/action_jump_land.mp3",
	Coin = "rbxasset://sounds/electronicpingshort.wav",
	Click = "rbxasset://sounds/electronicpingshort.wav",
	Charge = "rbxasset://sounds/action_swim.mp3",
	Splash = "rbxasset://sounds/impact_water.mp3",
	GetUp = "rbxasset://sounds/action_get_up.mp3",
}
Config.SoundFallbacks = {
	Coin = "rbxasset://sounds/action_get_up.mp3",
	Click = "rbxasset://sounds/action_get_up.mp3",
}

return Config
