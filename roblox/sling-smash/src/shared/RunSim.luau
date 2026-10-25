--[[
	RunSim: the rules of one launch, with no Instances or effects.

	The client steps it every frame and turns its events into visuals and
	sound; the tests step it in plain Luau to check balance. Everything that
	changes the flight (smashing, combos, armor, power-ups, hazards, biome
	ground rules) lives here so the game and the tests can never disagree.

	Events (all optional callbacks in opts.Events):
	  OnSmash(block, info)        info = { Coins, Crit, Tier, Cause, Velocity }
	                              Cause: "hit" | "tnt" | "shockwave" | "slam" | "rift"
	  OnBonk(block, speed)        bounced off armor
	  OnPhase(block)              phased through armor
	  OnExplode(position, chainIndex)
	  OnStar(star, coins)         OnRing(ring)
	  OnPickup(pickup)            OnAbility(kind)        OnAbilityEnd(kind)
	  OnShockwave(position, radius, cause)
	  OnBoost()                   OnBounce(speed)        OnLava(position)
	  OnPad(pad)                  OnGeyser(geyser)       OnUpdraft(updraft)
	  OnBarrier(barrier, phased)  OnLog(log, phased)
	  OnSlowMo(duration)          OnZone(index)
]]

local Config = require(script.Parent.Config)
local CourseLayout = require(script.Parent.CourseLayout)
local Physics = require(script.Parent.Physics)

local RunSim = {}
RunSim.__index = RunSim

local BLOCK_HIT_RADIUS = Config.BlockSize * 0.55
local H = Config.Hazards

local function distanceToSegment(point: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local lengthSquared = ab:Dot(ab)
	if lengthSquared < 1e-6 then
		return (point - a).Magnitude
	end
	local t = math.clamp((point - a):Dot(ab) / lengthSquared, 0, 1)
	return (a + ab * t - point).Magnitude
end
RunSim.DistanceToSegment = distanceToSegment

local bucketOf = CourseLayout.BucketOf

-- Distance buckets for everything in the layout, built once and shared.
local index = nil
local function bucketize(list, key: string)
	local buckets = {}
	for _, item in list do
		local b = bucketOf(-item[key].Z)
		local entries = buckets[b]
		if not entries then
			entries = {}
			buckets[b] = entries
		end
		table.insert(entries, item)
	end
	return buckets
end

function RunSim.Index()
	if index then
		return index
	end
	local layout = CourseLayout.Get()
	local kinds = {}
	for _, block in layout.Blocks do
		kinds[block.Kind] = (kinds[block.Kind] or 0) + 1
	end
	index = {
		Layout = layout,
		Kinds = kinds,
		Blocks = bucketize(layout.Blocks, "Position"),
		Stars = bucketize(layout.Stars, "Position"),
		Rings = bucketize(layout.Rings, "Position"),
		Pickups = bucketize(layout.Pickups, "Position"),
		Barriers = bucketize(layout.Barriers, "Position"),
		Logs = bucketize(layout.Logs, "Pivot"),
		Geysers = bucketize(layout.Geysers, "Position"),
		Updrafts = bucketize(layout.Updrafts, "Position"),
		Pads = bucketize(layout.Pads, "Position"),
	}
	return index
end

-- Calls fn(item) for every item in buckets between distances d1 and d2 (plus margin).
local function forEachNear(buckets, d1: number, d2: number, margin: number, fn: (any) -> ())
	local low = math.min(d1, d2) - margin
	local high = math.max(d1, d2) + margin
	for b = bucketOf(low) - 1, bucketOf(high) + 1 do
		local entries = buckets[b]
		if entries then
			for _, item in entries do
				fn(item)
			end
		end
	end
end

local function horizontalDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

--------------------------------------------------------------------------------

function RunSim.new(stats, start: Vector3, velocity: Vector3, opts: { [string]: any }?)
	local options = opts or {}
	local self = setmetatable({}, RunSim)
	self.Stats = stats
	self.Index = RunSim.Index()
	self.Rng = options.Rng or Random.new()
	self.Events = options.Events or {}

	-- Body (Physics.Step moves these).
	self.Position = start
	self.Velocity = velocity
	self.Grounded = false
	self.Thrust = 0

	self.Time = 0
	self.Combo = 0
	self.ComboTimer = 0
	self.MaxCombo = 0
	self.RunCoins = 0
	self.Smashes = 0
	self.Stars = 0
	self.Rings = 0
	self.Gold = 0
	self.TNT = 0
	self.Armor = 0
	self.Powerups = 0
	self.MaxTier = 0
	self.Boosts = stats.BoostCharges
	self.BoostCooldown = 0
	self.Zone = 1
	self.Ability = nil -- { Kind, TimeLeft, Duration }
	self.PullTimer = 0
	self.SlamCooldown = 0
	self.BonkCooldown = 0
	self.Done = nil -- "finish" | "stopped" | "timeout"

	self.Broken = {} -- [blockId] = true
	self.Phased = {} -- [blockId] = true
	self.Used = {} -- ["Star3"] = true, one-time pickups, rings, barriers
	self.Cooldowns = {} -- ["Log2"] = time it can trigger again
	self.InUpdraft = nil
	self.UpdraftTime = {} -- [updraftId] = seconds spent inside
	self.SlowTime = 0 -- seconds spent crawling (ends stuck runs)
	return self
end

function RunSim:_fire(name: string, ...)
	local callback = self.Events[name]
	if callback then
		callback(...)
	end
end

function RunSim:AbilityKind(): string?
	return if self.Ability then self.Ability.Kind else nil
end

function RunSim:HitRadius(): number
	local radius = self.Stats.HitRadius
	if self:AbilityKind() == "Meteor" then
		radius += Config.Abilities.Meteor.RadiusBonus
	end
	return radius
end

function RunSim:Distance(): number
	return math.max(0, -self.Position.Z)
end

function RunSim:BreakCombo()
	self.Combo = 0
	self.ComboTimer = 0
end

--------------------------------------------------------------------------------
-- Smashing
--------------------------------------------------------------------------------

local CAUSE_TIER = { tnt = 2, shockwave = 3, slam = 2, rift = 1 }

function RunSim:_smash(block, cause: string, fling: Vector3, minTier: number?)
	self.Broken[block.Id] = true
	local info = Config.Blocks[block.Kind] or Config.Blocks.Block
	local stats = self.Stats
	self.Smashes += 1
	if self.ComboTimer > 0 then
		self.Combo += 1
	else
		self.Combo = 1
	end
	self.ComboTimer = stats.ComboWindow
	self.MaxCombo = math.max(self.MaxCombo, self.Combo)

	local multiplier = Config.ComboMultiplier(self.Combo, stats.MaxComboMult)
	local crit = self.Rng:NextNumber() < Config.CritChance
	local zone = Config.Zones[block.Zone]
	local coins = math.floor(
		info.Value
			* zone.ValueMult
			* stats.SmashCoinMult
			* multiplier
			* (if crit then Config.CritMultiplier else 1)
			* stats.CoinMult
	)
	self.RunCoins += coins
	if block.Kind == "Gold" then
		self.Gold += 1
	elseif block.Kind == "TNT" then
		self.TNT += 1
	elseif block.Kind == "Armor" then
		self.Armor += 1
	end

	local tier
	if cause == "hit" then
		local bonus = (if crit then 1 else 0) + (if self:AbilityKind() == "Meteor" then 1 else 0)
		tier = Config.ImpactTier(self.Velocity.Magnitude, info.Durability, bonus)
	else
		tier = CAUSE_TIER[cause] or 1
	end
	tier = math.max(tier, minTier or 1)
	self.MaxTier = math.max(self.MaxTier, tier)

	self:_fire("OnSmash", block, { Coins = coins, Crit = crit, Tier = tier, Cause = cause, Velocity = fling })
end

-- Every unbroken block within radius of a point.
function RunSim:BlocksNear(center: Vector3, radius: number)
	local found = {}
	local d = -center.Z
	forEachNear(self.Index.Blocks, d, d, radius, function(block)
		if not self.Broken[block.Id] and (block.Position - center).Magnitude <= radius then
			table.insert(found, block)
		end
	end)
	return found
end

-- Explodes one or more TNT blocks (already smashed) and everything they chain
-- into. However many TNT go off together, you get one boost.
function RunSim:_explode(sources)
	local queue = table.clone(sources)
	local chain = 0
	local blast = Config.Blocks.TNT
	while #queue > 0 do
		local source = table.remove(queue, 1)
		chain += 1
		self:_fire("OnExplode", source.Position, chain)
		for _, other in self:BlocksNear(source.Position, blast.BlastRadius) do
			local away = other.Position - source.Position
			local push = if away.Magnitude > 0.01 then away.Unit * 45 else Vector3.zero
			self:_smash(other, "tnt", self.Velocity * 0.4 + push)
			if other.Kind == "TNT" then
				table.insert(queue, other)
			end
		end
	end
	self.Velocity += Config.Forward * blast.Boost
	self.Velocity = Vector3.new(self.Velocity.X, math.max(self.Velocity.Y, blast.Lift), self.Velocity.Z)
	self.Grounded = false
	self:_fire("OnSlowMo", Config.SlowMo.Duration)
end

-- Smashes everything nearby (armor too) and pushes it outwards.
function RunSim:_shockwave(center: Vector3, radius: number, cause: string, maxBlocks: number, lift: number?, boost: number?)
	self:_fire("OnShockwave", center, radius, cause)
	local tnt = {}
	local count = 0
	for _, block in self:BlocksNear(center, radius) do
		if count >= maxBlocks then
			break
		end
		count += 1
		local away = block.Position - center
		local push = if away.Magnitude > 0.01 then away.Unit * 70 else Vector3.yAxis * 40
		self:_smash(block, cause, push + Vector3.new(0, 30, 0))
		if block.Kind == "TNT" then
			table.insert(tnt, block)
		end
	end
	if lift then
		self.Velocity = Vector3.new(self.Velocity.X, math.max(self.Velocity.Y, lift), self.Velocity.Z)
		self.Grounded = false
	end
	if boost then
		self.Velocity += Config.Forward * boost
	end
	if #tnt > 0 then
		self:_explode(tnt)
	end
end

function RunSim:_bonk(block, speed: number)
	if self.BonkCooldown > 0 then
		return
	end
	self.BonkCooldown = 0.3
	local v = self.Velocity
	local along = v:Dot(Config.Forward)
	local side = v - Config.Forward * along - Vector3.yAxis * v.Y
	self.Velocity = side * 0.4 - Config.Forward * (math.abs(along) * 0.25) + Vector3.yAxis * math.max(v.Y, 16)
	self.Grounded = false
	self:BreakCombo()
	self:_fire("OnBonk", block, speed)
end

function RunSim:_onBlock(block)
	if self.Broken[block.Id] or self.Phased[block.Id] then
		return
	end
	local info = Config.Blocks[block.Kind] or Config.Blocks.Block
	local ability = self:AbilityKind()
	local speed = self.Velocity.Magnitude

	if block.Kind == "Armor" then
		if ability == "Meteor" or speed >= info.BreakSpeed then
			self:_smash(block, "hit", self.Velocity, 3)
			if ability ~= "Meteor" then
				self.Velocity *= 1 - info.Slowdown * self.Stats.SmashSlow
			end
		elseif ability == "Phase" then
			self.Phased[block.Id] = true
			self:_fire("OnPhase", block)
		else
			self:_bonk(block, speed)
		end
		return
	end

	self:_smash(block, "hit", self.Velocity)
	if ability ~= "Meteor" then
		self.Velocity *= 1 - info.Slowdown * self.Stats.SmashSlow
	end
	if block.Kind == "TNT" then
		self:_explode({ block })
	end
end

--------------------------------------------------------------------------------
-- Power-ups and boosts
--------------------------------------------------------------------------------

function RunSim:Boost(): boolean
	if self.Done or self.Boosts <= 0 or self.BoostCooldown > 0 then
		return false
	end
	local cfg = Config.Boost
	self.Boosts -= 1
	self.BoostCooldown = cfg.Cooldown
	self.Velocity += Config.Forward * cfg.Impulse
	self.Velocity = Vector3.new(self.Velocity.X, math.max(self.Velocity.Y, cfg.Lift), self.Velocity.Z)
	self.Grounded = false
	self.Thrust = cfg.ThrustTime
	self:_fire("OnBoost")
	return true
end

function RunSim:_endAbility()
	local ability = self.Ability
	if ability then
		self.Ability = nil
		self:_fire("OnAbilityEnd", ability.Kind)
	end
end

function RunSim:_activate(pickup)
	self.Used["Pickup" .. pickup.Id] = true
	self.Powerups += 1
	self:_fire("OnPickup", pickup)
	local cfg = Config.Abilities[pickup.Kind]
	if not cfg then
		return
	end
	if pickup.Kind == "Shockwave" then
		self:_shockwave(self.Position, cfg.Radius, "shockwave", cfg.MaxBlocks, cfg.Lift, cfg.Boost)
		return
	end
	self:_endAbility()
	self.Ability = { Kind = pickup.Kind, TimeLeft = cfg.Duration, Duration = cfg.Duration }
	self.PullTimer = 0
	self:_fire("OnAbility", pickup.Kind)
end

function RunSim:_riftPull(h: number)
	local cfg = Config.Abilities.Rift
	self.PullTimer -= h
	if self.PullTimer > 0 then
		return
	end
	self.PullTimer = cfg.PullInterval
	local pulled = 0
	local tnt = {}
	for _, block in self:BlocksNear(self.Position, cfg.PullRadius) do
		if pulled >= cfg.PullMax then
			break
		end
		if block.Kind ~= "Armor" then
			pulled += 1
			local toward = self.Position - block.Position
			local fling = if toward.Magnitude > 0.01 then toward.Unit * 60 else Vector3.zero
			self:_smash(block, "rift", fling)
			if block.Kind == "TNT" then
				table.insert(tnt, block)
			end
		end
	end
	if #tnt > 0 then
		self:_explode(tnt)
	end
end

--------------------------------------------------------------------------------
-- Stepping
--------------------------------------------------------------------------------

-- Makes sure launchers never send you straight up and back onto themselves.
function RunSim:_ensureForward(minimum: number)
	local along = self.Velocity:Dot(Config.Forward)
	if along < minimum then
		self.Velocity += Config.Forward * (minimum - along)
	end
end

function RunSim:_cooldownReady(key: string, duration: number): boolean
	local readyAt = self.Cooldowns[key]
	if readyAt and self.Time < readyAt then
		return false
	end
	self.Cooldowns[key] = self.Time + duration
	return true
end

-- One fixed substep of length h with steering input -1..1.
function RunSim:Step(h: number, steer: number)
	if self.Done then
		return
	end
	local stats = self.Stats
	local idx = self.Index
	local previous = self.Position
	self.Time += h
	self.BoostCooldown = math.max(0, self.BoostCooldown - h)
	self.SlamCooldown = math.max(0, self.SlamCooldown - h)
	self.BonkCooldown = math.max(0, self.BonkCooldown - h)

	if self.Ability then
		self.Ability.TimeLeft -= h
		if self.Ability.TimeLeft <= 0 then
			self:_endAbility()
		end
	end

	local distance = -previous.Z
	local zoneIndex = CourseLayout.ZoneIndexAt(math.max(0, distance))
	local zone = Config.Zones[zoneIndex]
	local rule = Config.GroundRules[zone.Ground] or Config.GroundRules.Grass

	-- Updrafts push up while you're inside the column.
	local extra: Vector3? = nil
	-- Each updraft only carries you for a limited time, so you can't hover forever.
	local inside = nil
	forEachNear(idx.Updrafts, distance, distance, H.Updraft.Radius, function(updraft)
		if
			horizontalDistance(previous, updraft.Position) <= H.Updraft.Radius
			and previous.Y - updraft.Position.Y <= H.Updraft.Height
			and (self.UpdraftTime[updraft.Id] or 0) < H.Updraft.MaxTime
		then
			inside = updraft
		end
	end)
	if inside then
		self.UpdraftTime[inside.Id] = (self.UpdraftTime[inside.Id] or 0) + h
		extra = Vector3.new(0, H.Updraft.Accel, 0) + Config.Forward * H.Updraft.Drift
		if self.InUpdraft ~= inside then
			self:_fire("OnUpdraft", inside)
		end
	end
	self.InUpdraft = inside

	local env = {
		GravityMult = if self:AbilityKind() == "Rift" then Config.Abilities.Rift.GravityMult else 1,
		ExtraAccel = extra,
		DecelMult = rule.DecelMult,
		DragMult = rule.DragMult,
	}
	local contact, bounced = Physics.Step(self, h, steer, stats, env)
	local position = self.Position

	-- End of the lane.
	if -position.Z >= Config.LaneLength then
		self.Position = Vector3.new(position.X, position.Y, -Config.LaneLength)
		self.Velocity = Vector3.zero
		self.Done = "finish"
		return
	end

	-- Ground contact: slams, bounce pads, lava.
	if contact or self.Grounded then
		if contact and contact >= Config.Slam.MinSpeed and self.SlamCooldown <= 0 then
			self.SlamCooldown = Config.Slam.Cooldown
			self:_shockwave(position, Config.Slam.Radius, "slam", 30, nil, nil)
		end
		local pad = nil
		forEachNear(idx.Pads, -position.Z, -position.Z, H.Pad.Radius, function(candidate)
			if horizontalDistance(position, candidate.Position) <= H.Pad.Radius then
				pad = candidate
			end
		end)
		local horizontalSpeed = Vector3.new(self.Velocity.X, 0, self.Velocity.Z).Magnitude
		if pad and self:_cooldownReady("Pad" .. pad.Id, H.Pad.Cooldown) then
			self.Velocity = Vector3.new(self.Velocity.X, H.Pad.Lift, self.Velocity.Z) + Config.Forward * H.Pad.Push
			self:_ensureForward(H.MinExitSpeed)
			self.Grounded = false
			self:_fire("OnPad", pad)
		elseif rule.BounceSpeed and horizontalSpeed > rule.MinSpeed then
			local v = self.Velocity
			self.Velocity = Vector3.new(v.X * rule.Keep, math.max(v.Y, rule.BounceSpeed), v.Z * rule.Keep)
			self.Grounded = false
			self:_fire("OnLava", position)
		elseif contact and bounced then
			self:_fire("OnBounce", contact)
		end
	end

	-- Smashable blocks along this step's path.
	local radius = self:HitRadius()
	local d1, d2 = -previous.Z, -position.Z
	forEachNear(idx.Blocks, d1, d2, radius + BLOCK_HIT_RADIUS, function(block)
		if
			not self.Broken[block.Id]
			and distanceToSegment(block.Position, previous, position) <= radius + BLOCK_HIT_RADIUS
		then
			self:_onBlock(block)
		end
	end)

	forEachNear(idx.Stars, d1, d2, radius + Config.StarRadius, function(star)
		local key = "Star" .. star.Id
		if not self.Used[key] and distanceToSegment(star.Position, previous, position) <= radius + Config.StarRadius then
			self.Used[key] = true
			self.Stars += 1
			local coins = math.floor(Config.StarValue * Config.Zones[star.Zone].ValueMult * stats.CoinMult)
			self.RunCoins += coins
			self:_fire("OnStar", star, coins)
		end
	end)

	forEachNear(idx.Rings, d1, d2, Config.BigRingRadius, function(ring)
		local key = "Ring" .. ring.Id
		local ringRadius = if ring.Big then Config.BigRingRadius else Config.RingRadius
		if not self.Used[key] and distanceToSegment(ring.Position, previous, position) <= ringRadius then
			self.Used[key] = true
			self.Rings += 1
			local push = if ring.Big then Config.BigRingBoost else Config.RingBoost
			self.Velocity += Config.Forward * push
			self.Velocity = Vector3.new(self.Velocity.X, math.max(self.Velocity.Y, Config.RingLift), self.Velocity.Z)
			self.Grounded = false
			self:_fire("OnRing", ring)
		end
	end)

	local pickupReach = Config.PickupRadius + H.BodyRadius
	forEachNear(idx.Pickups, d1, d2, pickupReach, function(pickup)
		if
			not self.Used["Pickup" .. pickup.Id]
			and distanceToSegment(pickup.Position, previous, position) <= pickupReach
		then
			self:_activate(pickup)
		end
	end)

	local phase = self:AbilityKind() == "Phase"

	-- Laser barriers: a vertical wall across part of the lane.
	forEachNear(idx.Barriers, d1, d2, 2, function(barrier)
		local key = "Barrier" .. barrier.Id
		local z = barrier.Position.Z
		if self.Used[key] or (previous.Z - z) * (position.Z - z) > 0 or previous.Z == position.Z then
			return
		end
		local t = (z - previous.Z) / (position.Z - previous.Z)
		local cross = previous + (position - previous) * t
		local withinX = math.abs(cross.X - barrier.Position.X) <= barrier.Width / 2 + H.BodyRadius
		local withinY = cross.Y - barrier.Position.Y <= barrier.Height + H.BodyRadius * 0.5
		if withinX and withinY then
			self.Used[key] = true
			if not phase then
				self.Velocity *= H.Barrier.SpeedKeep
				self:BreakCombo()
			end
			self:_fire("OnBarrier", barrier, phase)
		end
	end)

	-- Swinging logs knock you sideways.
	forEachNear(idx.Logs, d1, d2, H.Log.Radius + H.BodyRadius, function(log)
		local head = CourseLayout.LogHead(log, self.Time)
		if distanceToSegment(head, previous, position) > H.Log.Radius + H.BodyRadius then
			return
		end
		if not self:_cooldownReady("Log" .. log.Id, H.Log.Cooldown) then
			return
		end
		if not phase then
			-- Push the way the log is swinging.
			local swingDirection = math.cos(self.Time * math.pi * 2 / log.Period + log.Offset)
			local push = Config.Right * (if swingDirection >= 0 then 1 else -1) * H.Log.Push
			local v = self.Velocity
			self.Velocity = Vector3.new(v.X, math.max(v.Y, 22), v.Z * 0.55) + push
			self.Grounded = false
			self:BreakCombo()
		end
		self:_fire("OnLog", log, phase)
	end)

	-- Erupting geysers launch you skywards.
	forEachNear(idx.Geysers, d1, d2, H.Geyser.Radius, function(geyser)
		local active = CourseLayout.GeyserState(geyser, self.Time)
		if
			active
			and horizontalDistance(position, geyser.Position) <= H.Geyser.Radius
			and position.Y - geyser.Position.Y <= H.Geyser.Height
			and self:_cooldownReady("Geyser" .. geyser.Id, H.Geyser.Cooldown)
		then
			self.Velocity = Vector3.new(self.Velocity.X, math.max(self.Velocity.Y, H.Geyser.Lift), self.Velocity.Z)
				+ Config.Forward * H.Geyser.Push
			self:_ensureForward(H.MinExitSpeed)
			self.Grounded = false
			self:_fire("OnGeyser", geyser)
		end
	end)

	if self:AbilityKind() == "Rift" then
		self:_riftPull(h)
	end

	if self.ComboTimer > 0 then
		self.ComboTimer -= h
		if self.ComboTimer <= 0 then
			self.Combo = 0
		end
	end

	local newZone = CourseLayout.ZoneIndexAt(self:Distance())
	if newZone > self.Zone then
		self.Zone = newZone
		self:_fire("OnZone", newZone)
	end

	-- Progress is speed along the lane; sliding sideways on ice doesn't count.
	local laneSpeed = math.abs(self.Velocity:Dot(Config.Forward))
	if laneSpeed < Config.Flight.CrawlSpeed and self.Thrust <= 0 then
		self.SlowTime += h
	else
		self.SlowTime = 0
	end
	if self.Grounded and laneSpeed < Config.Flight.StopSpeed and self.Thrust <= 0 then
		self.Done = "stopped"
	elseif self.SlowTime > Config.Flight.CrawlTime then
		-- Barely moving for a while (e.g. bouncing in place): call it.
		self.Done = "stopped"
	elseif self.Time > Config.Flight.MaxFlightTime then
		self.Done = "timeout"
	end
end

-- What the client reports to the server when the launch ends.
function RunSim:Report()
	return {
		Distance = self:Distance(),
		Smashes = self.Smashes,
		Stars = self.Stars,
		Rings = self.Rings,
		Gold = self.Gold,
		TNT = self.TNT,
		Armor = self.Armor,
		Powerups = self.Powerups,
		MaxCombo = self.MaxCombo,
		RunCoins = self.RunCoins,
	}
end

return RunSim
