-- Sling Smash logic tests. Run with: python3 tests/run.py
-- (Config, CourseLayout, Physics, RunSim, Format, Index, Daily and Codes are injected by run.py.)

local failures = 0
local function check(condition: boolean, message: string)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

--------------------------------------------------------------------------------
-- Format
--------------------------------------------------------------------------------

check(Format.Commas(7880) == "7,880", "Commas 7880 -> " .. Format.Commas(7880))
check(Format.Commas(123) == "123", "Commas 123")
check(Format.Commas(1234567) == "1,234,567", "Commas 1234567")
check(Format.Commas(-4500) == "-4,500", "Commas negative -> " .. Format.Commas(-4500))
check(Format.Short(1400) == "1.4K", "Short 1400 -> " .. Format.Short(1400))
check(Format.Short(25000) == "25K", "Short 25000 -> " .. Format.Short(25000))
check(Format.Short(999) == "999", "Short 999")
check(Format.Short(150000) == "150K", "Short 150000 -> " .. Format.Short(150000))
check(Format.Short(2500000) == "2.5M", "Short 2.5M -> " .. Format.Short(2500000))
check(Format.Coins(99999) == "99,999", "Coins below 100K use commas")
check(Format.Coins(250000) == "250K", "Coins above 100K use short form")

--------------------------------------------------------------------------------
-- Upgrade tree
--------------------------------------------------------------------------------

local seen = { ["0,0"] = "Start" }
for _, node in Config.Nodes do
	local key = node.Q .. "," .. node.R
	check(seen[key] == nil, "hex collision at " .. key .. " between " .. node.Id .. " and " .. tostring(seen[key]))
	seen[key] = node.Id
	check(node.Requires == "Start" or Config.NodesById[node.Requires] ~= nil, node.Id .. " requires unknown node")
	check(type(node.Cost) == "number" and node.Cost > 0, node.Id .. " has no cost")
	local parent = Config.NodesById[node.Requires] or Config.StartNode
	local dq, dr = node.Q - parent.Q, node.R - parent.R
	check(math.max(math.abs(dq), math.abs(dr), math.abs(-dq - dr)) == 1, node.Id .. " is not next to its parent")
end
print(string.format("Upgrade nodes: %d", #Config.Nodes))

local none = Config.ComputeStats({}, 0)
local all = {}
for _, node in Config.Nodes do
	all[node.Id] = true
end
local maxed = Config.ComputeStats(all, 0)
check(none.BoostCharges == Config.Boost.BaseCharges, "everyone starts with the base boost charges")
check(maxed.BoostCharges == Config.Boost.BaseCharges + 3, "Rocket Fuel III adds three boosts")
check(Config.GetLevels({ LaunchPower2 = true }).LaunchPower == 0, "tier 2 without tier 1 must not count")
check(
	Config.ComboMultiplier(0, 5) == 1 and Config.ComboMultiplier(6, 5) == 2 and Config.ComboMultiplier(1000, 5) == 5,
	"combo multiplier steps and caps"
)

--------------------------------------------------------------------------------
-- Codes
--------------------------------------------------------------------------------

check(Config.NormalizeCode(" launch ") == "LAUNCH", "codes ignore case and spaces")
check(Config.NormalizeCode("") == nil, "empty code rejected")
check(Config.NormalizeCode(42) == nil, "non-string code rejected")
check(Config.NormalizeCode(string.rep("A", 30)) == nil, "overlong code rejected")
for code, reward in Codes do
	check(Config.NormalizeCode(code) == code, "code " .. code .. " must be upper case with no spaces")
	check(type(reward) == "number" and reward > 0, "code " .. code .. " pays something")
end

--------------------------------------------------------------------------------
-- Daily rewards
--------------------------------------------------------------------------------

local DAY = Daily.DaySeconds
local now = 20000 * DAY + 3600 -- 01:00 on day 20000
local can, streak, wait = Daily.Status({ Day = 0, Streak = 0 }, now)
check(can and streak == 1 and wait == 0, "first ever claim is day 1")
can, streak, wait = Daily.Status({ Day = 20000, Streak = 3 }, now)
check(not can and streak == 3 and wait == DAY - 3600, "can't claim twice in one day; waits until midnight UTC")
can, streak = Daily.Status({ Day = 19999, Streak = 3 }, now)
check(can and streak == 4, "consecutive day continues the streak")
can, streak = Daily.Status({ Day = 19998, Streak = 6 }, now)
check(can and streak == 1, "missing a day restarts the streak")
check(Daily.Reward(1, 0) == Daily.Rewards[1], "day 1 reward")
check(Daily.Reward(30, 0) == Daily.Rewards[#Daily.Rewards], "streaks past day 7 keep the top reward")
check(Daily.Reward(1, 2) == math.floor(Daily.Rewards[1] * Config.RebirthMultiplier(2)), "rebirths boost daily rewards")


--------------------------------------------------------------------------------
-- Index
--------------------------------------------------------------------------------

local function ids(list)
	local out = {}
	for _, entry in list do
		out[entry.Id] = true
	end
	return out
end

local blank = { Distance = 0, Smashes = 0, Stars = 0, Rings = 0, Gold = 0, TNT = 0, Armor = 0, Powerups = 0, MaxCombo = 0 }
check(#Index.Evaluate(blank, {}) == 0, "a zero-distance launch discovers nothing")

local run = table.clone(blank)
run.Distance = Config.Zones[1].EndsAt + 50
run.Gold = 1
local found = ids(Index.Evaluate(run, {}))
check(found.Zone1 and found.Zone2 and found.Gold, "reaching the Jungle with a gold block finds Sky, Jungle and Gold Rush")
check(not found.Zone3 and not found.Finish and not found.TNT, "nothing beyond what the launch reached")
check(not ids(Index.Evaluate(run, { Zone2 = true })).Zone2, "already discovered entries don't pay twice")

run = table.clone(blank)
run.Distance = Config.LaneLength
local finish = ids(Index.Evaluate(run, {}))
check(finish.Finish and finish.Zone5, "reaching the end of the lane finds every biome and the Finish Line")

run = table.clone(blank)
run.Armor, run.Powerups = 1, 3
local special = ids(Index.Evaluate(run, {}))
check(special.Armor and special.Powerup and special.Powerups3, "armor and power-up discoveries")

local entryIds = {}
for _, entry in Index.Entries do
	check(entryIds[entry.Id] == nil, "duplicate index id " .. entry.Id)
	entryIds[entry.Id] = true
	check(blank[entry.Goal] ~= nil, entry.Id .. " uses an unknown goal " .. tostring(entry.Goal))
	check(entry.Reward > 0, entry.Id .. " has a reward")
end
check(Index.Count({ Zone1 = true, Gold = true, Bogus = true }) == 2, "Index.Count ignores unknown ids")

--------------------------------------------------------------------------------
-- Course layout
--------------------------------------------------------------------------------

local layout = CourseLayout.Get()
print(string.format(
	"Course: %d blocks, %d stars, %d rings, %d power-ups, %d barriers, %d logs, %d geysers, %d updrafts, %d pads",
	layout.TotalBlocks,
	#layout.Stars,
	#layout.Rings,
	#layout.Pickups,
	#layout.Barriers,
	#layout.Logs,
	#layout.Geysers,
	#layout.Updrafts,
	#layout.Pads
))
local positions = {}
local overlaps = 0
local kinds = {}
local groundBlocks = {}
for _, block in layout.Blocks do
	local p = block.Position
	check(math.abs(p.X) <= Config.LaneWidth / 2, "block outside lane x=" .. p.X)
	check(-p.Z >= Config.CourseStart - 1 and -p.Z <= Config.LaneLength, "block outside lane z=" .. p.Z)
	check(p.Y >= Config.GroundY + Config.BlockSize / 2 - 0.01, "block below ground y=" .. p.Y)
	check(block.Zone == CourseLayout.ZoneIndexAt(-p.Z) or math.abs(-p.Z - Config.Zones[block.Zone].EndsAt) < 30, "block zone matches its distance")
	local key = string.format("%.1f,%.1f,%.1f", p.X, p.Y, p.Z)
	if positions[key] then
		overlaps += 1
	end
	positions[key] = true
	kinds[block.Kind] = (kinds[block.Kind] or 0) + 1
	if block.Kind == "Armor" then
		check(Config.Zones[block.Zone].Key ~= "Sky", "no armor in the first biome (" .. -p.Z .. ")")
	end
	if block.Kind == "Ice" then
		check(Config.Zones[block.Zone].Key == "Frozen", "ice blocks only in the Frozen Frontier")
	end
	if p.Y < Config.BlockSize then
		table.insert(groundBlocks, block)
	end
end
check(overlaps == 0, overlaps .. " blocks overlap")
for _, kind in { "Block", "Gold", "TNT", "Armor", "Ice" } do
	check((kinds[kind] or 0) > 0, "course has " .. kind .. " blocks")
	check(Config.Blocks[kind] ~= nil, kind .. " has block settings")
end
print(string.format(
	"Block kinds: %d plain, %d ice, %d gold, %d TNT, %d armor",
	kinds.Block or 0,
	kinds.Ice or 0,
	kinds.Gold or 0,
	kinds.TNT or 0,
	kinds.Armor or 0
))
check(CourseLayout.Get() == layout, "layout is cached")

-- Every hazard lives in its own biome and inside the lane.
local function zoneKeyAt(position)
	return Config.Zones[CourseLayout.ZoneIndexAt(-position.Z)].Key
end
for _, log in layout.Logs do
	check(zoneKeyAt(log.Pivot) == "Jungle", "swinging logs only in the Jungle")
	for t = 0, log.Period, log.Period / 16 do
		local head = CourseLayout.LogHead(log, t)
		check(head.Y > Config.GroundY + 3, "log head stays above the ground")
		check(math.abs(head.X) < Config.LaneWidth / 2 + 4, "log head stays near the lane")
	end
end
for _, barrier in layout.Barriers do
	check(zoneKeyAt(barrier.Position) == "Neon", "laser barriers only in Neon Velocity")
	check(math.abs(barrier.Position.X) + barrier.Width / 2 <= Config.LaneWidth / 2 + 0.01, "barrier fits the lane")
end
for _, geyser in layout.Geysers do
	check(zoneKeyAt(geyser.Position) == "Volcanic", "geysers only in the Volcanic Wasteland")
	check(geyser.Active < geyser.Period, "geysers rest between eruptions")
end
for _, updraft in layout.Updrafts do
	check(zoneKeyAt(updraft.Position) == "Sky", "updrafts only in the Sky Kingdom")
end
for _, pad in layout.Pads do
	check(zoneKeyAt(pad.Position) ~= "Frozen", "no bounce pads on the ice")
end
-- Ground helpers never sit inside a ground-level block.
for _, list in { layout.Pads, layout.Geysers, layout.Updrafts } do
	for _, item in list do
		for _, block in groundBlocks do
			local dx, dz = item.Position.X - block.Position.X, item.Position.Z - block.Position.Z
			if math.sqrt(dx * dx + dz * dz) < 5 then
				check(false, "ground helper overlaps a block at " .. -item.Position.Z)
			end
		end
	end
end
local abilityCounts = {}
for _, pickup in layout.Pickups do
	check(Config.Abilities[pickup.Kind] ~= nil, "power-up kind " .. tostring(pickup.Kind) .. " exists")
	check(math.abs(pickup.Position.X) < Config.LaneWidth / 2, "power-up inside the lane")
	abilityCounts[pickup.Kind] = (abilityCounts[pickup.Kind] or 0) + 1
end
for _, kind in Config.AbilityOrder do
	check((abilityCounts[kind] or 0) > 0, "course has a " .. kind .. " power-up")
end
check(layout.Pickups[1].Kind == "Shockwave" and -layout.Pickups[1].Position.Z < 100, "a Shockwave orb waits right after the first wall")
check(#layout.Logs > 0 and #layout.Barriers > 0 and #layout.Geysers > 0 and #layout.Updrafts > 0 and #layout.Pads > 0, "every hazard type appears")

--------------------------------------------------------------------------------
-- Physics and aiming
--------------------------------------------------------------------------------

local none = Config.ComputeStats({}, 0)
local maxedStats = Config.ComputeStats(all, 0)
local start = Physics.PouchPosition(1)

local function airtime(angle)
	local points = Physics.Predict(none, start, Physics.LaunchVelocity(none, 1, angle, 0), 10, 0.05)
	return #points
end
check(airtime(40) > airtime(24) and airtime(24) > airtime(12), "steeper aim keeps you in the air longer")
local _, landRight = Physics.Predict(none, start, Physics.LaunchVelocity(none, 1, 24, 12), 10, 0.05)
check(landRight.X > 5, "aiming right lands to the right")
local _, landStraight = Physics.Predict(none, start, Physics.LaunchVelocity(none, 1, 24, 0), 10, 0.05)
check(math.abs(landStraight.X) < 0.01, "aiming straight stays centred")
check(Physics.LaunchSpeed(none, 0) == none.LaunchSpeed * Config.Flight.MinPower, "a tap launches at minimum power")

-- The preview must match a real flight until the first obstacle.
do
	local velocity = Physics.LaunchVelocity(none, 0.8, 30, -6)
	local points, landing = Physics.Predict(none, start, velocity, 10, 1 / 120)
	local body = Physics.NewBody(start, velocity)
	for _ = 1, #points - 1 do
		Physics.Step(body, 1 / 120, 0, none, nil)
	end
	check((body.Position - points[#points]).Magnitude < 0.01, "preview arc matches the physics step")
	check(landing.Y <= Config.GroundY + Config.Flight.BodyHeight + 0.01, "preview ends on the ground")
end

-- Ice slides further than grass; lava bounces.
do
	local function slide(rule)
		local body = Physics.NewBody(Vector3.new(0, Config.GroundY + Config.Flight.BodyHeight, -100), Config.Forward * 60)
		body.Grounded = true
		local env = { DecelMult = rule.DecelMult, DragMult = rule.DragMult }
		for _ = 1, 600 do
			Physics.Step(body, 1 / 120, 0, none, env)
		end
		return -body.Position.Z - 100
	end
	check(slide(Config.GroundRules.Ice) > slide(Config.GroundRules.Grass) * 1.8, "ice is slippery")
end

--------------------------------------------------------------------------------
-- RunSim scenarios
--------------------------------------------------------------------------------

local function newSim(stats, position, velocity, log)
	log.Smashed = {} -- [blockId] = smash info
	local events = setmetatable({
		OnSmash = function(block, info)
			log.OnSmash = (log.OnSmash or 0) + 1
			log.lastOnSmash = { block, info }
			log.Smashed[block.Id] = info
		end,
	}, {
		__index = function(_, name)
			return function(...)
				log[name] = (log[name] or 0) + 1
				log["last" .. name] = { ... }
			end
		end,
	})
	return RunSim.new(stats, position, velocity, { Rng = Random.new(3), Events = events })
end

local function stepFor(sim, seconds, steer)
	local steps = math.floor(seconds * 120)
	for _ = 1, steps do
		sim:Step(1 / 120, steer or 0)
		if sim.Done then
			break
		end
	end
end

-- Finds an armor block on the ground with open space in front of it.
local function openArmor()
	for _, block in layout.Blocks do
		if block.Kind == "Armor" and block.Position.Y < Config.BlockSize then
			local blocked = false
			for _, other in layout.Blocks do
				local dz = other.Position.Z - block.Position.Z
				if other ~= block and dz > 0.5 and dz < 14 and math.abs(other.Position.X - block.Position.X) < 7 and other.Position.Y < 9 then
					blocked = true
					break
				end
			end
			if not blocked then
				return block
			end
		end
	end
	return nil
end
local armor = openArmor()
check(armor ~= nil, "found an exposed armor block to test with")
if armor then
	local before = armor.Position - Config.Forward * 12

	local log = {}
	local sim = newSim(none, before, Config.Forward * 60, log)
	stepFor(sim, 0.5)
	check(not sim.Broken[armor.Id] and (log.OnBonk or 0) > 0, "a slow hit bounces off armor")
	check(sim.Velocity:Dot(Config.Forward) <= 0.01, "bonking armor knocks you back")

	log = {}
	sim = newSim(none, before, Config.Forward * 150, log)
	stepFor(sim, 0.3)
	check(sim.Broken[armor.Id] == true and sim.Armor >= 1, "a fast hit breaks armor")
	check(log.Smashed[armor.Id] and log.Smashed[armor.Id].Tier >= 3, "breaking armor is at least a critical-tier impact")

	log = {}
	sim = newSim(none, before, Config.Forward * 50, log)
	sim.Ability = { Kind = "Meteor", TimeLeft = 4, Duration = 4 }
	stepFor(sim, 0.4)
	check(sim.Broken[armor.Id] == true, "Meteor Breaker smashes armor at any speed")

	log = {}
	sim = newSim(none, before, Config.Forward * 50, log)
	sim.Ability = { Kind = "Phase", TimeLeft = 4, Duration = 4 }
	stepFor(sim, 0.4)
	check(
		not sim.Broken[armor.Id] and (log.OnPhase or 0) > 0 and (log.OnBonk or 0) == 0,
		string.format(
			"Phase Overdrive passes through armor (broken=%s phase=%d bonk=%d explode=%d)",
			tostring(sim.Broken[armor.Id]),
			log.OnPhase or 0,
			log.OnBonk or 0,
			log.OnExplode or 0
		)
	)
end

-- Laser barriers slow you unless you're phased.
do
	local barrier = layout.Barriers[1]
	local before = Vector3.new(barrier.Position.X, Config.GroundY + 4, barrier.Position.Z) - Config.Forward * 3
	local log = {}
	local sim = newSim(none, before, Config.Forward * 100, log)
	stepFor(sim, 0.06)
	check((log.OnBarrier or 0) == 1 and log.lastOnBarrier[2] == false, "flying into a barrier zaps you")
	check(sim.Velocity.Magnitude < 60, "a barrier zap slows you down")

	log = {}
	sim = newSim(none, before, Config.Forward * 100, log)
	sim.Ability = { Kind = "Phase", TimeLeft = 4, Duration = 4 }
	stepFor(sim, 0.06)
	check(log.lastOnBarrier and log.lastOnBarrier[2] == true and sim.Velocity.Magnitude > 90, "phasing through a barrier keeps your speed")

	local over = Vector3.new(barrier.Position.X, Config.GroundY + barrier.Height + 8, barrier.Position.Z) - Config.Forward * 3
	log = {}
	sim = newSim(none, over, Config.Forward * 100, log)
	stepFor(sim, 0.06)
	check((log.OnBarrier or 0) == 0, "flying over a barrier is safe")
end

-- Geysers launch you while erupting; pads bounce you; updrafts lift you.
do
	local geyser = layout.Geysers[1]
	local log = {}
	local sim = newSim(none, geyser.Position + Vector3.new(0, 8, 0), Config.Forward * 1, log)
	-- Start right at the beginning of an eruption.
	sim.Time = geyser.Period - geyser.Offset % geyser.Period
	stepFor(sim, 1 / 60)
	check((log.OnGeyser or 0) == 1 and sim.Velocity.Y > 60, "an erupting geyser launches you")

	local pad = layout.Pads[1]
	log = {}
	sim = newSim(none, pad.Position + Vector3.new(0, 4, 0), Vector3.new(0, -30, 0), log)
	stepFor(sim, 0.2)
	check((log.OnPad or 0) == 1 and sim.Velocity.Y > 40, "bounce pads launch you upwards")

	local updraft = layout.Updrafts[1]
	log = {}
	sim = newSim(none, updraft.Position + Vector3.new(0, 10, 0), Vector3.new(0, 0, 0), log)
	stepFor(sim, 0.5)
	check((log.OnUpdraft or 0) == 1 and sim.Position.Y > updraft.Position.Y + 10, "updrafts lift you")
end

-- A spot in a biome with nothing nearby, for clean scenario tests.
local function clearSpot(zoneIndex)
	local from = if zoneIndex == 1 then 0 else Config.Zones[zoneIndex - 1].EndsAt
	local to = math.min(Config.Zones[zoneIndex].EndsAt, Config.LaneLength)
	local function near(list, key, point, radius)
		for _, item in list do
			local p = item[key]
			local dx, dz = p.X - point.X, p.Z - point.Z
			if math.sqrt(dx * dx + dz * dz) < radius then
				return true
			end
		end
		return false
	end
	for d = from + 20, to - 40, 4 do
		for x = -28, 28, 14 do
			local point = Vector3.new(x, 0, -d)
			local busy = near(layout.Blocks, "Position", point, 30)
				or near(layout.Pads, "Position", point, 30)
				or near(layout.Geysers, "Position", point, 30)
				or near(layout.Pickups, "Position", point, 30)
				or near(layout.Updrafts, "Position", point, 30)
			if not busy then
				return point
			end
		end
	end
	return nil
end

-- Lava floors bounce fast sliders; slams make shockwaves.
do
	local spot = clearSpot(3)
	check(spot ~= nil, "found a clear spot in the Volcanic Wasteland")
	if spot then
		local floor = Config.GroundY + Config.Flight.BodyHeight
		local log = {}
		local sim = newSim(none, spot + Vector3.new(0, floor + 0.5, 0), Config.Forward * 60 + Vector3.new(0, -5, 0), log)
		stepFor(sim, 0.1)
		check((log.OnLava or 0) >= 1 and sim.Velocity.Y > 0, "the lava floor bounces you back up")

		log = {}
		sim = newSim(none, spot + Vector3.new(0, 20, 0), Vector3.new(0, -100, 0), log)
		stepFor(sim, 0.3)
		check(log.lastOnShockwave and log.lastOnShockwave[3] == "slam", "a hard slam makes a shockwave")
	end
	local iceSpot = clearSpot(4)
	if iceSpot then
		-- Steering hard on ice must not slide forever.
		local sim = newSim(maxedStats, iceSpot + Vector3.new(0, 3, 0), Config.Forward * 40, {})
		stepFor(sim, 30, 1)
		check(sim.Done == "stopped", "sliding sideways on ice still ends the launch")
	end
end

-- Power-ups: Shockwave clears an area, Rift floats and pulls blocks in.
do
	local target = nil
	for _, pickup in layout.Pickups do
		if pickup.Kind == "Shockwave" then
			target = pickup
			break
		end
	end
	if target then
		local log = {}
		local sim = newSim(none, target.Position - Config.Forward * 3, Config.Forward * 40, log)
		stepFor(sim, 0.1)
		check((log.OnPickup or 0) == 1 and sim.Powerups == 1, "flying through an orb picks it up")
		check(log.lastOnShockwave and log.lastOnShockwave[3] == "shockwave" and sim.Velocity.Y > 20, "Devastation lifts you with a shockwave")
	end

	local log = {}
	local sim = newSim(none, Vector3.new(0, 30, -300), Config.Forward * 40, log)
	sim.Ability = { Kind = "Rift", TimeLeft = 5, Duration = 5 }
	local normal = newSim(none, Vector3.new(0, 30, -300), Config.Forward * 40, {})
	stepFor(sim, 0.5)
	stepFor(normal, 0.5)
	check(sim.Position.Y > normal.Position.Y + 2, "Gravity Rift makes you float")

	-- Rift pulls nearby blocks in.
	local wallBlock = layout.Blocks[1]
	log = {}
	sim = newSim(none, wallBlock.Position + Vector3.new(0, 12, 14), Vector3.new(0, 0, -2), log)
	sim.Ability = { Kind = "Rift", TimeLeft = 5, Duration = 5 }
	stepFor(sim, 0.3)
	check(log.lastOnSmash and log.lastOnSmash[2].Cause == "rift", "Gravity Rift pulls blocks in")
	check(sim.Ability == nil or sim.Ability.TimeLeft < 5, "abilities count down")
end

-- Nitro adds roughly Impulse + Thrust * ThrustTime along the lane.
do
	local a = newSim(none, Vector3.new(0, 60, -200), Config.Forward * 50, {})
	local b = newSim(none, Vector3.new(0, 60, -200), Config.Forward * 50, {})
	check(a:Boost(), "boost works with a charge")
	check(not a:Boost(), "boost has a cooldown and limited charges")
	stepFor(a, 0.6)
	stepFor(b, 0.6)
	local gain = a.Velocity:Dot(Config.Forward) - b.Velocity:Dot(Config.Forward)
	local expected = Config.Boost.Impulse + Config.Boost.Thrust * Config.Boost.ThrustTime
	check(gain > expected * 0.9 and gain < expected * 1.05, string.format("nitro gain %.1f vs expected %.1f", gain, expected))
end

-- TNT chains explode, smash and ask for slow motion.
do
	local tnt = nil
	for _, block in layout.Blocks do
		if block.Kind == "TNT" and block.Position.Y < Config.BlockSize then
			tnt = block
			break
		end
	end
	if tnt then
		local log = {}
		local sim = newSim(none, tnt.Position - Config.Forward * 10, Config.Forward * 80, log)
		stepFor(sim, 0.3)
		check((log.OnExplode or 0) >= 1 and (log.OnSlowMo or 0) >= 1, "TNT explodes and asks for slow motion")
	end
end

-- Several TNT going off together give one boost, not one per TNT.
do
	local center = nil
	for _, block in layout.Blocks do
		if block.Kind == "TNT" then
			local nearby = 0
			for _, other in layout.Blocks do
				if other.Kind == "TNT" and (other.Position - block.Position).Magnitude <= 20 then
					nearby += 1
				end
			end
			if nearby >= 3 then
				center = block.Position
				break
			end
		end
	end
	check(center ~= nil, "found a TNT cluster to test with")
	if center then
		local log = {}
		local sim = newSim(none, center + Vector3.new(0, 30, 0), Vector3.zero, log)
		sim:_shockwave(center, 22, "shockwave", 200, nil, nil)
		local gain = sim.Velocity:Dot(Config.Forward)
		check((log.OnExplode or 0) >= 3, "the shockwave set off several TNT")
		check(math.abs(gain - Config.Blocks.TNT.Boost) < 0.01, string.format("one TNT boost for the whole blast (got %.1f)", gain))
		check((log.OnSlowMo or 0) == 1, "one slow motion for the whole blast")
	end
end

-- The aim preview reports a real landing only when the arc touches down.
do
	local _, _, landed = Physics.Predict(maxedStats, start, Physics.LaunchVelocity(maxedStats, 1, Config.Flight.MaxAngle, 0), 10, 0.05)
	check(landed, "even a maxed, steepest launch lands within the preview window")
	local _, _, cut = Physics.Predict(maxedStats, start, Physics.LaunchVelocity(maxedStats, 1, Config.Flight.MaxAngle, 0), 0.5, 0.05)
	check(not cut, "a preview cut short doesn't claim a landing")
end

--------------------------------------------------------------------------------
-- Full flights: balance, and honest flights never hit the server's limits
--------------------------------------------------------------------------------

local function runFlight(stats, power, angle, steerFn, boostFn)
	local log = {}
	local sim = newSim(stats, Physics.PouchPosition(power), Physics.LaunchVelocity(stats, power, angle, 0), log)
	local apex = 0
	while not sim.Done do
		if boostFn and boostFn(sim) then
			sim:Boost()
		end
		sim:Step(1 / 120, if steerFn then steerFn(sim) else 0)
		apex = math.max(apex, sim.Position.Y)
	end
	local distance = sim:Distance()
	local coins = sim.RunCoins + math.floor(distance * Config.CoinsPerStud * stats.CoinMult)

	-- The server must accept everything an honest flight reports.
	local limits = Config.LaunchLimits(stats, sim.Time, layout.TotalBlocks)
	check(distance <= limits.MaxDistance, string.format("honest distance %.0f within server limit %.0f", distance, limits.MaxDistance))
	check(sim.Smashes <= limits.MaxSmashes, string.format("honest smashes %d within server limit %d", sim.Smashes, limits.MaxSmashes))
	check(sim.RunCoins <= Config.CoinCeiling(stats, sim.Smashes, sim.Stars), "honest coins within the server ceiling")
	check(sim.Armor <= (RunSim.Index().Kinds.Armor or 0) and sim.Powerups <= #layout.Pickups, "counts within the layout")
	local brokenCount = 0
	for _ in sim.Broken do
		brokenCount += 1
	end
	check(brokenCount == sim.Smashes, "every smash breaks exactly one block")
	return distance, coins, sim, apex, log
end

local function report(label, stats, power, angle, steerFn, boostFn)
	local distance, coins, sim, apex = runFlight(stats, power, angle, steerFn, boostFn)
	print(string.format(
		"%-34s dist %5.0f  time %4.1fs  apex %5.1f  smashes %4d  armor %2d  orbs %d  stars %2d  rings %2d  combo %3d  coins %s",
		label,
		distance,
		sim.Time,
		apex,
		sim.Smashes,
		sim.Armor,
		sim.Powerups,
		sim.Stars,
		sim.Rings,
		sim.MaxCombo,
		Format.Commas(coins)
	))
	return distance, coins, sim
end

local function boostWhenFalling(sim)
	return sim.Velocity.Y < -5 and sim.Position.Y < 8
end
local weave = function(sim)
	return math.sin(sim.Time * 1.3)
end
local default = Config.Flight.LaunchAngle

local tapDistance = report("base, 30% (tap)", none, 0, default)
local baseDistance, baseCoins = report("base, 100%", none, 1, default)
report("base, 100%, high aim (40)", none, 1, 40)
report("base, 100%, using the boost", none, 1, default, nil, boostWhenFalling)
report("early upgrades, 100%", Config.ComputeStats({ LaunchPower1 = true, LaunchPower2 = true, HangTime1 = true }, 0), 1, default)
local maxDistance = report("all upgrades, 100%", maxedStats, 1, default)
report("all upgrades, weaving + boosts", maxedStats, 1, default, weave, boostWhenFalling)
for angle = 12, 44, 8 do
	report("all upgrades, weaving, aim " .. angle, maxedStats, 1, angle, weave, boostWhenFalling)
end

check(tapDistance > 20, "a tap launch still goes somewhere")
check(baseDistance > 80 and baseDistance < 700, "base full-power distance is modest")
check(baseCoins >= 100, "the first full launch affords the cheapest upgrade")
check(maxDistance > baseDistance * 2, "maxed upgrades at least double the distance")

-- Random steering stress test: lots of flights, no rule ever breaks.
do
	local rng = Random.new(99)
	for i = 1, 40 do
		local stats = if i % 2 == 0 then maxedStats else Config.ComputeStats({ LaunchPower1 = true, SmashPower1 = true }, i % 3)
		local power = rng:NextNumber(0, 1)
		local angle = rng:NextNumber(Config.Flight.MinAngle, Config.Flight.MaxAngle)
		local yaw = rng:NextNumber(-Config.Flight.MaxYaw, Config.Flight.MaxYaw)
		local sim = newSim(stats, Physics.PouchPosition(power), Physics.LaunchVelocity(stats, power, angle, yaw), {})
		local steerSeed = rng:NextNumber(0, 10)
		while not sim.Done do
			if rng:NextNumber() < 0.004 then
				sim:Boost()
			end
			sim:Step(1 / 120, math.sin(sim.Time * 0.9 + steerSeed))
			check(sim.Position.Y >= Config.GroundY + Config.Flight.BodyHeight - 0.001, "never below the floor")
			check(math.abs(sim.Position.X) <= Config.LaneWidth / 2, "never outside the lane")
			if failures > 20 then
				break
			end
		end
		local limits = Config.LaunchLimits(stats, sim.Time, layout.TotalBlocks)
		check(sim:Distance() <= limits.MaxDistance and sim.Smashes <= limits.MaxSmashes, "random flight " .. i .. " within server limits")
	end
end

print(if failures == 0 then "ALL CHECKS PASSED" else failures .. " CHECK(S) FAILED")
