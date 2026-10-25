--[[
	Turns RunSim events into visuals, sound, camera kicks and HUD pops.

	The flight script owns the state; this module just reacts. Kept separate so
	the smoke test can run whole flights through it outside Roblox.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Effects = require(script.Parent.Effects)
local Quality = require(script.Parent.Quality)
local UI = require(script.Parent.UI)

local FlightEvents = {}

local rng = Random.new()

--[[
	ctx = {
		Course: the client Course,
		GetRun: () -> RunSim?,
		GetFlight: () -> flight presentation state? (FovKick, SlowMo, HitStop...),
		GetCharacter: () -> Model?,
		CameraEffectsOn: () -> boolean,
	}
]]
function FlightEvents.new(ctx)
	local course = ctx.Course

	-- Adds a field-of-view kick to the current flight.
	local function kick(amount: number)
		local f = ctx.GetFlight()
		if f then
			f.FovKick = math.max(f.FovKick, amount)
		end
	end

	local FX_BY_KIND = { Gold = "Gold", Ice = "Glass", Armor = "Metal", TNT = "Explosive" }
	local POP_BY_ABILITY = { Meteor = "meteor", Rift = "rift", Phase = "phase", Shockwave = "shock" }

	local lastPop = 0
	-- Pop text, but never more than a few per second.
	local function pop(text: string, style: string, force: boolean?)
		local now = os.clock()
		if force or now - lastPop > 0.35 then
			lastPop = now
			UI.Pop(text, style)
		end
	end

	local function hitStop(duration: number)
		local f = ctx.GetFlight()
		if not f or not Quality.Current.HitStop or not ctx.CameraEffectsOn() then
			return
		end
		local now = os.clock()
		if now - f.LastHitStop > 0.8 then
			f.LastHitStop = now
			f.HitStop = math.max(f.HitStop, duration)
		end
	end

	local events = {}

	function events.OnSmash(block, info)
		local f = ctx.GetFlight()
		course:Smash(block, info.Velocity)
		local entry = course.Blocks[block.Id]
		local color = if entry then entry.Color else Color3.new(1, 1, 1)
		local zone = Config.Zones[block.Zone]
		local fx = FX_BY_KIND[block.Kind] or zone.BlockFx
		local tier = info.Tier
		Effects.Impact(block.Position, fx, tier, color)
		local chipKey = if block.Kind == "Block" then "Block:" .. block.Zone .. ":" .. block.ColorIndex else block.Kind
		Effects.Burst(block.Position, chipKey, color, 3 + tier * 2)

		if fx == "Glass" then
			Effects.Play("Shatter", rng:NextNumber(0.85, 1.2))
		elseif fx == "Metal" then
			Effects.Play("Clang", rng:NextNumber(0.9, 1.1))
		else
			Effects.Play("Smash", rng:NextNumber(0.85, 1.35) * (if tier >= 3 then 0.8 else 1), 0.8 + tier * 0.1)
		end

		local textColor = if info.Cause == "rift" then Color3.fromRGB(210, 170, 255) else Color3.fromRGB(220, 150, 255)
		if info.Crit then
			pop("CRITICAL!", "crit")
			Effects.FloatText(block.Position + Vector3.new(0, 3, 0), "+" .. Format.Short(info.Coins), Color3.fromRGB(255, 170, 40), 1.4)
		else
			Effects.FloatText(block.Position + Vector3.new(0, 2, 0), "+" .. Format.Short(info.Coins), textColor, 1)
		end

		if info.Cause == "hit" then
			if tier >= 4 then
				Effects.Shake(1.6)
				hitStop(0.05)
				if f and os.clock() - f.LastBigPop > 2 then
					f.LastBigPop = os.clock()
					pop("DEVASTATING!", "shock")
				end
			elseif tier >= 3 then
				Effects.Shake(0.9)
			else
				Effects.Shake(0.3)
			end
		end
		if block.Kind == "Armor" and info.Cause == "hit" then
			pop("🛡️ ARMOR BROKEN!", "crit", true)
		end
	end

	function events.OnBonk(block, _speed)
		course:FlashBlock(block, Color3.new(1, 1, 1))
		Effects.Impact(block.Position, "Metal", 3, Color3.fromRGB(170, 170, 190))
		Effects.Play("Clang", 0.8, 1, true)
		Effects.Shake(1.4)
		pop("🛡️ ARMORED! NEED SPEED", "zap", true)
		local f = ctx.GetFlight()
		if f and not f.BonkTipShown then
			f.BonkTipShown = true
			UI.Toast("Armor breaks at high speed, with ☄️ Meteor, TNT or 💥 shockwaves")
		end
	end

	function events.OnPhase(block)
		course:FlashBlock(block, Color3.fromRGB(120, 255, 255), 0.7)
		Effects.Burst(block.Position, "phase", Color3.fromRGB(120, 255, 255), 4)
	end

	function events.OnExplode(position: Vector3, chain: number)
		if chain <= 4 then
			Effects.Explosion(position, Config.Blocks.TNT.BlastRadius)
			Effects.Play("Boom", rng:NextNumber(0.9, 1.1), 1, chain == 1)
		end
		if chain == 1 then
			Effects.Shake(2.2)
			Effects.Flash(Color3.fromRGB(255, 170, 60), 0.35)
			pop("BOOM!", "crit", true)
			kick(10)
		end
	end

	function events.OnStar(star, coins: number)
		course:CollectStar(star.Id)
		Effects.Play("Coin", 1.25)
		Effects.Flash(Color3.fromRGB(255, 225, 90), 0.25)
		Effects.Impact(star.Position, "Gold", 2, Color3.fromRGB(255, 214, 40))
		Effects.FloatText(star.Position, "⭐ +" .. Format.Short(coins), Color3.fromRGB(255, 220, 60), 1.6)
	end

	function events.OnRing(ring)
		course:UseRing(ring.Id)
		local radius = if ring.Big then Config.BigRingRadius else Config.RingRadius
		kick(if ring.Big then 18 else 14)
		pop(if ring.Big then "⚡ ACCELERATE!" else "BOOST!", "boost", true)
		Effects.Ring(CFrame.lookAt(ring.Position, ring.Position + Config.Forward), Color3.fromRGB(120, 240, 255), radius, radius * 1.9, 0.35, 1)
		Effects.Flash(Color3.fromRGB(80, 230, 255), 0.3)
		Effects.Play("Launch", 1.55)
		Effects.Shake(0.8)
	end

	function events.OnPickup(pickup)
		course:TakePickup(pickup.Id)
		local ability = Config.Abilities[pickup.Kind]
		Effects.Play("Pickup", 1, 1, true)
		Effects.Pulse(pickup.Position, ability.Color, 3, 14, 0.35)
		Effects.Ring(CFrame.lookAt(pickup.Position, pickup.Position + Config.Forward), ability.Color, 2, 10, 0.35, 0.8)
		pop(ability.Icon .. " " .. ability.Name .. "!", POP_BY_ABILITY[pickup.Kind] or "boost", true)
	end

	function events.OnAbility(kind: string)
		Effects.StartAura(kind, ctx.GetCharacter())
		UI.SetAbility(kind, 1)
		kick(10)
	end

	function events.OnAbilityEnd(_kind: string)
		Effects.StopAura()
		UI.SetAbility(nil)
		Effects.Play("PowerDown")
	end

	function events.OnShockwave(position: Vector3, radius: number, cause: string)
		local color = if cause == "slam" then Color3.fromRGB(255, 170, 70) else Config.Abilities.Shockwave.Color
		Effects.Shockwave(position, radius, color)
		if cause == "slam" then
			pop("GROUND SLAM!", "crit", true)
		else
			pop("💥 DEVASTATION!", "shock", true)
		end
		hitStop(0.07)
		kick(12)
	end

	function events.OnBoost()
		local r = ctx.GetRun()
		if not r then
			return
		end
		local direction = if r.Velocity.Magnitude > 1 then r.Velocity.Unit else Config.Forward
		Effects.NitroBurst(r.Position, direction)
		UI.SetBoosts(r.Boosts)
		pop("⚡ NITRO!", "nitro", true)
		kick(14)
	end

	local lastBounceFx = 0
	function events.OnBounce(speed: number)
		local r = ctx.GetRun()
		local now = os.clock()
		if not r or now - lastBounceFx < 0.15 then
			return
		end
		lastBounceFx = now
		local zone = Config.Zones[r.Zone]
		local fx = if zone.Key == "Frozen" then "Snow" else "Stone"
		local tier = if speed > 60 then 3 elseif speed > 35 then 2 else 1
		Effects.Impact(Vector3.new(r.Position.X, Config.GroundY + 0.5, r.Position.Z), fx, tier, Color3.fromRGB(200, 190, 170))
		Effects.Play("Thud", math.clamp(1.2 - speed / 120, 0.6, 1.2))
		Effects.Shake(math.clamp(speed / 60, 0.3, 1.2))
	end

	function events.OnLava(position: Vector3)
		Effects.Impact(position, "Explosive", 2, Color3.fromRGB(255, 120, 30))
		Effects.Play("Eruption", 1.7, 0.4)
		pop("🔥 HOT FLOOR!", "meteor")
	end

	function events.OnPad(pad)
		course:BouncePad(pad.Id)
		Effects.GroundRing(pad.Position + Vector3.new(0, 0.8, 0), Color3.fromRGB(140, 255, 140), 2, 11, 0.35)
		Effects.Play("Pad")
		pop("BOING!", "max", true)
		kick(10)
	end

	function events.OnGeyser(geyser)
		Effects.Impact(geyser.Position + Vector3.new(0, 4, 0), "Explosive", 3, Color3.fromRGB(255, 130, 40))
		Effects.Play("Eruption", 1, 1, true)
		pop("🌋 ERUPTION!", "meteor", true)
		Effects.Shake(1.2)
		kick(14)
	end

	function events.OnUpdraft(_updraft)
		Effects.Play("Launch", 0.6, 0.5)
		pop("🌬️ UPDRAFT!", "boost")
	end

	function events.OnBarrier(barrier, phased: boolean)
		course:HitBarrier(barrier.Id, phased)
		local r = ctx.GetRun()
		if phased then
			pop("👻 PHASED!", "phase", true)
			Effects.Play("Zap", 1.8)
			if r then
				Effects.Ring(CFrame.lookAt(r.Position, r.Position + Config.Forward), Color3.fromRGB(120, 255, 255), 2, 10, 0.3, 0.6)
			end
		else
			pop("⚡ ZAPPED!", "zap", true)
			Effects.Play("Zap", 1, 1, true)
			Effects.Flash(Color3.fromRGB(255, 60, 80), 0.35)
			Effects.Shake(1.5)
			if r then
				for _ = 1, 3 do
					local offset = Vector3.new(rng:NextNumber(-4, 4), rng:NextNumber(-2, 4), rng:NextNumber(-2, 2))
					Effects.Lightning(r.Position + offset, r.Position - offset, Color3.fromRGB(255, 120, 140), 0.15, 4)
				end
			end
		end
	end

	function events.OnLog(log, phased: boolean)
		if phased then
			pop("👻 PHASED!", "phase", true)
			Effects.Play("Zap", 1.8)
			return
		end
		local r = ctx.GetRun()
		pop("🪵 WHACK!", "crit", true)
		Effects.Play("Thud", 0.55, 1, true)
		Effects.Shake(1.6)
		if r then
			Effects.Impact(r.Position, "Wood", 3, Color3.fromRGB(130, 90, 56))
		end
		kick(8)
	end

	function events.OnSlowMo(duration: number)
		local f = ctx.GetFlight()
		if f then
			f.SlowMo = math.max(f.SlowMo, duration)
		end
	end

	function events.OnZone(index: number)
		local zone = Config.Zones[index]
		UI.Banner(zone.Icon .. " " .. string.upper(zone.Name), zone.BannerColor)
		Effects.Flash(zone.BannerColor, 0.15)
		Effects.Play("Victory", 0.9, 0.5)
	end

	return events
end

return FlightEvents
