-- Sling Smash logic tests. Run with: python3 tests/run.py
-- (Config, CourseLayout, Format, Index, Daily and Codes are injected by run.py.)

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

local blank = { Distance = 0, Smashes = 0, Stars = 0, Rings = 0, Gold = 0, TNT = 0, MaxCombo = 0 }
check(#Index.Evaluate(blank, {}) == 0, "a zero-distance launch discovers nothing")

local run = table.clone(blank)
run.Distance = 600
run.Gold = 1
local found = ids(Index.Evaluate(run, {}))
check(found.Zone1 and found.Zone2 and found.Gold, "600 studs with a gold block finds Meadows, Sky City and Gold Rush")
check(not found.Zone3 and not found.Finish and not found.TNT, "nothing beyond what the launch reached")
check(not ids(Index.Evaluate(run, { Zone2 = true })).Zone2, "already discovered entries don't pay twice")

run = table.clone(blank)
run.Distance = Config.LaneLength
check(ids(Index.Evaluate(run, {})).Finish, "reaching the end of the lane finds the Finish Line")

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
print(string.format("Course: %d blocks, %d stars, %d rings", layout.TotalBlocks, #layout.Stars, #layout.Rings))
local positions = {}
local overlaps = 0
local kinds = {}
for _, block in layout.Blocks do
	local p = block.Position
	check(math.abs(p.X) <= Config.LaneWidth / 2, "block outside lane x=" .. p.X)
	check(-p.Z >= Config.CourseStart - 1 and -p.Z <= Config.LaneLength, "block outside lane z=" .. p.Z)
	check(p.Y >= Config.GroundY + Config.BlockSize / 2 - 0.01, "block below ground y=" .. p.Y)
	local key = string.format("%.1f,%.1f,%.1f", p.X, p.Y, p.Z)
	if positions[key] then
		overlaps += 1
	end
	positions[key] = true
	kinds[block.Kind] = (kinds[block.Kind] or 0) + 1
end
check(overlaps == 0, overlaps .. " blocks overlap")
check((kinds.Gold or 0) > 0 and (kinds.TNT or 0) > 0, "course has gold and TNT")
check(CourseLayout.Get() == layout, "layout is cached")

--------------------------------------------------------------------------------
-- Flight simulation (mirrors simulate() in src/client/init.client.luau)
--------------------------------------------------------------------------------

local BUCKET = 16
local function bucketOf(d)
	return math.floor(d / BUCKET)
end
local function distanceToSegment(point, a, b)
	local ab = b - a
	local lengthSquared = ab:Dot(ab)
	if lengthSquared < 1e-6 then
		return (point - a).Magnitude
	end
	local t = math.clamp((point - a):Dot(ab) / lengthSquared, 0, 1)
	return (a + ab * t - point).Magnitude
end

local function runFlight(stats, launchPower, steerFn, boostFn)
	local rng = Random.new(7)
	local buckets, broken = {}, {}
	for _, block in layout.Blocks do
		local k = bucketOf(-block.Position.Z)
		buckets[k] = buckets[k] or {}
		table.insert(buckets[k], block)
	end
	local starsUsed, ringsUsed = {}, {}
	local F = Config.Flight
	local angle = math.rad(F.LaunchAngle)
	local speed = stats.LaunchSpeed * (F.MinPower + (1 - F.MinPower) * launchPower)
	local f = {
		Position = Vector3.new(
			0,
			Config.PouchHeight - launchPower * 1.2,
			Config.PouchRestOffset + Config.PouchPullDistance * launchPower
		),
		Velocity = (Config.Forward * math.cos(angle) + Vector3.yAxis * math.sin(angle)) * speed,
		Time = 0,
		Grounded = false,
		Combo = 0,
		ComboTimer = 0,
		MaxCombo = 0,
		RunCoins = 0,
		Smashes = 0,
		Stars = 0,
		Rings = 0,
		Gold = 0,
		TNT = 0,
		Boosts = stats.BoostCharges,
		Apex = 0,
	}
	local function registerSmash(block)
		local info = Config.Blocks[block.Kind]
		f.Smashes += 1
		if block.Kind == "Gold" then
			f.Gold += 1
		elseif block.Kind == "TNT" then
			f.TNT += 1
		end
		f.Combo = if f.ComboTimer > 0 then f.Combo + 1 else 1
		f.ComboTimer = stats.ComboWindow
		f.MaxCombo = math.max(f.MaxCombo, f.Combo)
		local mult = Config.ComboMultiplier(f.Combo, stats.MaxComboMult)
		local crit = rng:NextNumber() < Config.CritChance
		f.RunCoins += math.floor(
			info.Value
				* Config.Zones[block.Zone].ValueMult
				* stats.SmashCoinMult
				* mult
				* (if crit then Config.CritMultiplier else 1)
				* stats.CoinMult
		)
	end
	local function near(center, radius)
		local found = {}
		local d = -center.Z
		for k = bucketOf(d - radius - BUCKET), bucketOf(d + radius + BUCKET) do
			for _, block in buckets[k] or {} do
				if not broken[block] and (block.Position - center).Magnitude <= radius then
					table.insert(found, block)
				end
			end
		end
		return found
	end
	local function onBlock(block)
		if broken[block] then
			return
		end
		broken[block] = true
		registerSmash(block)
		f.Velocity = f.Velocity * (1 - Config.Blocks[block.Kind].Slowdown * stats.SmashSlow)
		if block.Kind == "TNT" then
			local queue = { block }
			while #queue > 0 do
				local e = table.remove(queue, 1)
				for _, other in near(e.Position, Config.Blocks.TNT.BlastRadius) do
					broken[other] = true
					registerSmash(other)
					if other.Kind == "TNT" then
						table.insert(queue, other)
					end
				end
			end
			f.Velocity = f.Velocity + Config.Forward * Config.Blocks.TNT.Boost
			f.Velocity = Vector3.new(f.Velocity.X, math.max(f.Velocity.Y, Config.Blocks.TNT.Lift), f.Velocity.Z)
			f.Grounded = false
		end
	end

	local h = 1 / 120
	while not f.Done do
		if boostFn and f.Boosts > 0 and boostFn(f) then
			f.Boosts -= 1
			f.Velocity = f.Velocity + Config.Forward * Config.Boost.Forward
			f.Velocity = Vector3.new(f.Velocity.X, math.max(f.Velocity.Y, Config.Boost.Lift), f.Velocity.Z)
			f.Grounded = false
		end
		local steer = if steerFn then steerFn(f) else 0
		local previous = f.Position
		local velocity = f.Velocity
		f.Time += h
		local vx = velocity.X + steer * stats.Steer * h
		if steer == 0 then
			vx -= vx * math.min(1, F.SideDamping * h)
		end
		vx = math.clamp(vx, -F.MaxSideSpeed, F.MaxSideSpeed)
		velocity = Vector3.new(vx, velocity.Y, velocity.Z)
		if f.Grounded then
			local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
			local s = horizontal.Magnitude
			if s > 1e-3 then
				horizontal = horizontal * (math.max(0, s - F.GroundDecel * h) * (1 - math.min(1, F.GroundDrag * h)) / s)
			end
			velocity = Vector3.new(horizontal.X, math.max(0, velocity.Y), horizontal.Z)
			if velocity.Y > 0 then
				f.Grounded = false
			end
		else
			velocity = velocity * (1 - math.min(1, F.AirDrag * h))
			velocity = velocity - Vector3.new(0, stats.Gravity * h, 0)
		end
		local position = previous + velocity * h
		local limit = Config.LaneWidth / 2 - 1.5
		if math.abs(position.X) > limit then
			position = Vector3.new(math.sign(position.X) * limit, position.Y, position.Z)
			velocity = Vector3.new(-velocity.X * 0.4, velocity.Y, velocity.Z)
		end
		local floor = Config.GroundY + F.BodyHeight
		if position.Y <= floor then
			position = Vector3.new(position.X, floor, position.Z)
			if velocity.Y < -F.MinBounceSpeed then
				velocity = Vector3.new(velocity.X * F.BounceKeep, -velocity.Y * F.Bounce, velocity.Z * F.BounceKeep)
			elseif velocity.Y <= 0 then
				velocity = Vector3.new(velocity.X, 0, velocity.Z)
				f.Grounded = true
			end
		end
		f.Apex = math.max(f.Apex, position.Y)
		if -position.Z >= Config.LaneLength then
			f.Position = Vector3.new(position.X, position.Y, -Config.LaneLength)
			f.Done = "finish"
			break
		end
		f.Position = position
		f.Velocity = velocity

		local radius = stats.HitRadius
		local d1, d2 = -previous.Z, -position.Z
		for k = bucketOf(math.min(d1, d2) - radius - BUCKET), bucketOf(math.max(d1, d2) + radius + BUCKET) do
			for _, block in buckets[k] or {} do
				if not broken[block] and distanceToSegment(block.Position, previous, position) <= radius + Config.BlockSize * 0.55 then
					onBlock(block)
				end
			end
		end
		for _, star in layout.Stars do
			if not starsUsed[star] and distanceToSegment(star.Position, previous, position) <= radius + Config.StarRadius then
				starsUsed[star] = true
				f.Stars += 1
				f.RunCoins += math.floor(Config.StarValue * Config.Zones[star.Zone].ValueMult * stats.CoinMult)
			end
		end
		for _, ring in layout.Rings do
			if not ringsUsed[ring] and distanceToSegment(ring.Position, previous, position) <= Config.RingRadius then
				ringsUsed[ring] = true
				f.Rings += 1
				f.Velocity = f.Velocity + Config.Forward * Config.RingBoost
				f.Velocity = Vector3.new(f.Velocity.X, math.max(f.Velocity.Y, Config.RingLift), f.Velocity.Z)
				f.Grounded = false
			end
		end
		if f.ComboTimer > 0 then
			f.ComboTimer -= h
			if f.ComboTimer <= 0 then
				f.Combo = 0
			end
		end
		local horizontalSpeed = Vector3.new(f.Velocity.X, 0, f.Velocity.Z).Magnitude
		if f.Grounded and horizontalSpeed < F.StopSpeed then
			f.Done = "stopped"
		elseif f.Time > F.MaxFlightTime then
			f.Done = "timeout"
		end
	end
	local distance = math.max(0, -f.Position.Z)
	local coins = f.RunCoins + math.floor(distance * Config.CoinsPerStud * stats.CoinMult)
	return distance, coins, f
end

local function report(label, stats, launchPower, steerFn, boostFn)
	local distance, coins, f = runFlight(stats, launchPower, steerFn, boostFn)
	print(string.format(
		"%-32s dist %5.0f  time %4.1fs  apex %4.1f  smashes %4d  stars %d  rings %d  maxCombo %3d  coins %s",
		label,
		distance,
		f.Time,
		f.Apex,
		f.Smashes,
		f.Stars,
		f.Rings,
		f.MaxCombo,
		Format.Commas(coins)
	))
	return distance, coins, f
end

-- Boost whenever we're falling back towards the ground.
local function boostWhenFalling(f)
	return f.Velocity.Y < -5 and f.Position.Y < 8
end
local weave = function(f)
	return math.sin(f.Time * 1.3)
end

local tapDistance = report("base, 30% (tap)", none, 0)
local baseDistance, baseCoins = report("base, 100%", none, 1)
local boostedDistance = report("base, 100%, using the boost", none, 1, nil, boostWhenFalling)
report("early upgrades, 100%", Config.ComputeStats({ LaunchPower1 = true, LaunchPower2 = true, HangTime1 = true }, 0), 1)
local maxDistance = report("all upgrades, 100%", maxed, 1)
report("all upgrades, weaving + boosts", maxed, 1, weave, boostWhenFalling)

check(tapDistance > 20, "a tap launch still goes somewhere")
check(baseDistance > 80 and baseDistance < 600, "base full-power distance is modest")
check(baseCoins >= 100, "the first full launch affords the cheapest upgrade")
check(boostedDistance > baseDistance, "boosting carries you further")
check(maxDistance > baseDistance * 2, "maxed upgrades at least double the distance")

print(if failures == 0 then "ALL CHECKS PASSED" else failures .. " CHECK(S) FAILED")
