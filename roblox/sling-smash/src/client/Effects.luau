--[[
	Client-only juice: sound, camera shake, speed lines, flashes, floating
	numbers, impacts, shockwave rings, lightning, the slingshot charge-up and
	power-up auras.

	Performance rules:
	  * Everything that repeats is pooled (emitters, rings, lightning bolts,
	    afterimages) and nothing is created per frame.
	  * Amounts and caps come from Quality.Current, so phones and Performance
	    Mode do less work.
	  * Only the sparkle texture every ParticleEmitter ships with is used, plus
	    Roblox's built-in Fire and Smoke objects, so nothing needs uploading.
	Everything respects the player's settings (SFX, Camera Effects, Speed Lines).
]]

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Quality = require(script.Parent.Quality)
local Widgets = require(script.Parent.Widgets)

local Effects = {}

Effects.Settings = table.clone(Config.DefaultSettings)

local rng = Random.new()
local fxFolder: Folder? = nil

local function folder(): Folder
	if fxFolder and fxFolder.Parent then
		return fxFolder
	end
	local created = Instance.new("Folder")
	created.Name = "SlingFX"
	created.Parent = Workspace
	fxFolder = created
	return created
end

local function fxPart(props): BasePart
	local p = Instance.new(props.ClassName or "Part") :: BasePart
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		if key ~= "ClassName" and key ~= "Parent" then
			(p :: any)[key] = value
		end
	end
	p.Parent = props.Parent or folder()
	return p
end

local function emitter(parent: Instance, props): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

local function cameraEffectsOn(): boolean
	return Effects.Settings.CameraShake ~= false
end

--------------------------------------------------------------------------------
-- Sound
--------------------------------------------------------------------------------

-- name = { template, pitch, volume, minGap (seconds between plays) }
local SOUND_EVENTS = {
	Launch = { "Launch", 0.9, 0.8, 0 },
	Smash = { "Smash", 1, 0.45, 0.05 },
	Coin = { "Coin", 1, 0.35, 0.03 },
	Click = { "Click", 1.2, 0.25, 0 },
	Nitro = { "Launch", 1.6, 0.9, 0.1 },
	Boom = { "Smash", 0.42, 1, 0.08 },
	Shatter = { "Splash", 1.7, 0.55, 0.06 },
	Clang = { "Smash", 2.1, 0.6, 0.08 },
	Zap = { "Click", 0.45, 0.7, 0.1 },
	Pickup = { "Coin", 0.75, 0.6, 0.1 },
	PowerDown = { "Coin", 0.5, 0.3, 0.1 },
	Eruption = { "Splash", 0.45, 0.9, 0.2 },
	Pad = { "Launch", 1.9, 0.7, 0.1 },
	Shockwave = { "Smash", 0.32, 1, 0.1 },
	Thud = { "Smash", 0.7, 0.55, 0.1 },
	Victory = { "Coin", 1.25, 0.6, 0 },
	GetUp = { "GetUp", 1, 0.5, 0 },
}

local templates = {} -- [templateName] = Sound
local lastPlayed = {} -- [eventName] = os.clock()
local recentVoices = {} -- start times of sounds in the last half second
local MAX_VOICES = 10
local sfxGroup: SoundGroup? = nil
local wind: Sound? = nil
local music: Sound? = nil
local chargeHum: Sound? = nil

local function makeSound(name: string, id: string, volume: number, looped: boolean?, group: SoundGroup?): Sound?
	if id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = "Sling_" .. name
	sound.SoundId = id
	sound.Volume = volume
	sound.Looped = looped == true
	sound.SoundGroup = group
	sound.Parent = SoundService
	return sound
end

-- Checks every built-in sound loads; swaps in a fallback (or silence) if not.
local function preloadSounds(list: { Sound })
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(list, function(contentId: string, status: Enum.AssetFetchStatus)
				if status == Enum.AssetFetchStatus.Success then
					return
				end
				for name, sound in templates do
					if sound.SoundId == contentId then
						local fallback = Config.SoundFallbacks[name]
						sound.SoundId = fallback or ""
					end
				end
			end)
		end)
	end)
end

-- Plays a named sound event. pitchScale and volumeScale tweak it per call.
function Effects.Play(name: string, pitchScale: number?, volumeScale: number?, priority: boolean?)
	if not Effects.Settings.SFX then
		return
	end
	local event = SOUND_EVENTS[name]
	if not event then
		return
	end
	local template = templates[event[1]]
	if not template or template.SoundId == "" then
		return
	end
	local now = os.clock()
	local gap = event[4]
	if gap > 0 and lastPlayed[name] and now - lastPlayed[name] < gap then
		return
	end
	-- Never stack too many sounds at once (protects ears and phones).
	for i = #recentVoices, 1, -1 do
		if now - recentVoices[i] > 0.5 then
			table.remove(recentVoices, i)
		end
	end
	if #recentVoices >= MAX_VOICES and not priority then
		return
	end
	table.insert(recentVoices, now)
	lastPlayed[name] = now

	local sound = template:Clone()
	sound.PlaybackSpeed = event[2] * (pitchScale or 1)
	sound.Volume = event[3] * (volumeScale or 1)
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 3)
end

-- Looping wind while flying; louder and higher pitched when fast.
function Effects.SetWind(speedFraction: number)
	if not wind then
		return
	end
	if speedFraction <= 0 or not Effects.Settings.SFX then
		if wind.IsPlaying then
			wind:Stop()
		end
		return
	end
	if not wind.IsPlaying then
		wind:Play()
	end
	wind.Volume = math.clamp(speedFraction, 0, 1) * 0.5
	wind.PlaybackSpeed = 0.8 + math.clamp(speedFraction, 0, 1.5) * 0.5
end

--------------------------------------------------------------------------------
-- Camera shake, flash, speed lines
--------------------------------------------------------------------------------

local shakeAmount = 0
local speedGui: ScreenGui? = nil
local speedLines = {}
local flashFrame: Frame? = nil
local abilityTint: ColorCorrectionEffect? = nil

function Effects.Shake(amount: number)
	if cameraEffectsOn() then
		shakeAmount = math.max(shakeAmount, amount)
	end
end

-- Returns a CFrame offset to multiply onto the camera this frame.
function Effects.ShakeOffset(dt: number): CFrame
	if shakeAmount < 0.01 then
		shakeAmount = 0
		return CFrame.identity
	end
	local a = shakeAmount
	shakeAmount *= math.exp(-9 * dt)
	return CFrame.new(rng:NextNumber(-a, a), rng:NextNumber(-a, a), 0) * CFrame.Angles(0, 0, rng:NextNumber(-a, a) * 0.02)
end

-- intensity 0..1 controls how visible the speed lines are.
function Effects.UpdateSpeedLines(dt: number, intensity: number)
	local gui = speedGui
	if not gui then
		return
	end
	if not Effects.Settings.SpeedLines or intensity <= 0.05 then
		gui.Enabled = false
		return
	end
	gui.Enabled = true
	local active = Quality.Current.SpeedLines
	for index, line in speedLines do
		if index > active then
			line.Frame.Visible = false
			continue
		end
		line.Frame.Visible = true
		line.Radius += dt * line.Speed * (0.6 + intensity * 1.4)
		if line.Radius > 0.9 then
			line.Radius = rng:NextNumber(0.25, 0.45)
			line.Angle = rng:NextNumber(0, math.pi * 2)
		end
		local x = 0.5 + math.cos(line.Angle) * line.Radius * 0.62
		local y = 0.5 + math.sin(line.Angle) * line.Radius * 0.62
		line.Frame.Position = UDim2.fromScale(x, y)
		line.Frame.Rotation = math.deg(line.Angle) + 90
		line.Frame.BackgroundColor3 = line.Color
		line.Frame.BackgroundTransparency = 1 - math.clamp(intensity, 0, 1) * 0.55 * math.clamp((line.Radius - 0.2) * 2, 0, 1)
	end
end

-- Tints the speed lines (cyan for Nitro, orange for Meteor...).
function Effects.SetSpeedLineColor(color: Color3)
	for _, line in speedLines do
		line.Color = color
	end
end

function Effects.HideSpeedLines()
	if speedGui then
		speedGui.Enabled = false
	end
end

function Effects.Flash(color: Color3, strength: number?)
	local frame = flashFrame
	if not frame then
		return
	end
	local s = strength or 0.4
	if not cameraEffectsOn() then
		s *= 0.4
	end
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 1 - s
	TweenService:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
end

-- A screen-wide colour grade while a power-up is active.
function Effects.SetAbilityTint(color: Color3?, saturation: number?)
	local tint = abilityTint
	if not tint then
		return
	end
	TweenService:Create(tint, TweenInfo.new(0.3), {
		TintColor = color or Color3.new(1, 1, 1),
		Saturation = saturation or 0,
	}):Play()
end

--------------------------------------------------------------------------------
-- Floating text
--------------------------------------------------------------------------------

local floatingCount = 0
local anchorPart: BasePart? = nil
local function floatAnchor(): BasePart
	if anchorPart and anchorPart.Parent then
		return anchorPart
	end
	local created = fxPart({
		Name = "SlingFloatAnchor",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Transparency = 1,
		CFrame = CFrame.new(),
	})
	anchorPart = created
	return created
end

-- Floating text in the world (e.g. "+1.4K") that rises and fades.
function Effects.FloatText(position: Vector3, text: string, color: Color3, size: number?)
	if floatingCount >= Quality.Current.FloatText then
		return
	end
	floatingCount += 1

	local attachment = Instance.new("Attachment")
	attachment.Position = position
	attachment.Parent = floatAnchor()

	local scale = size or 1
	local billboard = Widgets.new("BillboardGui", {
		Size = UDim2.fromOffset(170 * scale, 54 * scale),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 400,
		Adornee = attachment,
		Parent = attachment,
	})
	local label = Widgets.Label({
		Text = text,
		Size = UDim2.fromScale(1, 1),
		TextColor3 = color,
		StrokeThickness = 3,
		Parent = billboard,
	})

	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(billboard, info, { StudsOffsetWorldSpace = Vector3.new(0, 6, 0) }):Play()
	local fade = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
	end

	task.delay(0.95, function()
		floatingCount -= 1
		attachment:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Particles: coloured chips and material impacts
--------------------------------------------------------------------------------

-- Coloured chips. One emitter per colour key so recolouring never repaints
-- sparks that are already flying.
local burstEmitters = {} -- [key] = { Part, Emitter }
local MAX_BURST_EMITTERS = 32

local function burstEmitter(key: string, color: Color3)
	local existing = burstEmitters[key]
	if existing and existing.Part.Parent then
		return existing
	end
	local count = 0
	for _ in burstEmitters do
		count += 1
	end
	if count >= MAX_BURST_EMITTERS then
		return nil
	end
	local holder = fxPart({ Name = "SlingBurst", Size = Vector3.new(1, 1, 1), Transparency = 1 })
	local e = emitter(holder, {
		Lifetime = NumberRange.new(0.35, 0.7),
		Speed = NumberRange.new(16, 34),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 3,
		Acceleration = Vector3.new(0, -40, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0, 0.4),
		LightEmission = 0.7,
		Color = ColorSequence.new(color),
	})
	local entry = { Part = holder, Emitter = e }
	burstEmitters[key] = entry
	return entry
end

function Effects.Burst(position: Vector3, key: string, color: Color3, amount: number)
	local entry = burstEmitter(key, color)
	if not entry then
		return
	end
	entry.Part.CFrame = CFrame.new(position)
	entry.Emitter:Emit(Quality.Amount(amount))
end

local FX_DEFS = {
	Dust = {
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(6, 14),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(1, 4.5) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }),
		Drag = 4,
		Acceleration = Vector3.new(0, 4, 0),
		RotSpeed = NumberRange.new(-60, 60),
		Rotation = NumberRange.new(0, 360),
		Color = ColorSequence.new(Color3.fromRGB(196, 186, 170)),
	},
	Sparks = {
		Lifetime = NumberRange.new(0.2, 0.45),
		Speed = NumberRange.new(30, 60),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) }),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Squash = NumberSequence.new(-1.8),
		LightEmission = 1,
		Acceleration = Vector3.new(0, -60, 0),
		Color = ColorSequence.new(Color3.fromRGB(255, 230, 120), Color3.fromRGB(255, 120, 30)),
	},
	Shards = {
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(18, 34),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0.25) }),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-400, 400),
		LightEmission = 0.6,
		Acceleration = Vector3.new(0, -50, 0),
		Color = ColorSequence.new(Color3.fromRGB(240, 250, 255), Color3.fromRGB(140, 220, 255)),
	},
	Splinters = {
		Lifetime = NumberRange.new(0.4, 0.8),
		Speed = NumberRange.new(16, 30),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0.2) }),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Squash = NumberSequence.new(-2),
		Acceleration = Vector3.new(0, -55, 0),
		Color = ColorSequence.new(Color3.fromRGB(196, 140, 86), Color3.fromRGB(120, 80, 46)),
	},
	Snow = {
		Lifetime = NumberRange.new(0.6, 1.1),
		Speed = NumberRange.new(8, 18),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 3) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		Drag = 3,
		LightEmission = 0.2,
		Color = ColorSequence.new(Color3.fromRGB(250, 252, 255)),
	},
	Energy = {
		Lifetime = NumberRange.new(0.3, 0.6),
		Speed = NumberRange.new(20, 40),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.3), NumberSequenceKeypoint.new(1, 0) }),
		LightEmission = 1,
		Drag = 2,
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(160, 230, 255)),
	},
	Sparkle = {
		Lifetime = NumberRange.new(0.6, 1),
		Speed = NumberRange.new(8, 20),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0) }),
		LightEmission = 1,
		Drag = 2,
		Color = ColorSequence.new(Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 190, 40)),
	},
	Fire = {
		Lifetime = NumberRange.new(0.3, 0.6),
		Speed = NumberRange.new(14, 30),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.4), NumberSequenceKeypoint.new(1, 0.4) }),
		Transparency = NumberSequence.new(0.1, 1),
		LightEmission = 1,
		Drag = 3,
		Acceleration = Vector3.new(0, 16, 0),
		Color = ColorSequence.new(Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 60, 20)),
	},
	Streaks = {
		Lifetime = NumberRange.new(0.15, 0.3),
		Speed = NumberRange.new(60, 110),
		SpreadAngle = Vector2.new(14, 14),
		EmissionDirection = Enum.NormalId.Front,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Squash = NumberSequence.new(-2.5),
		LightEmission = 1,
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(120, 230, 255)),
	},
}

-- Which particle layers each material uses, with relative amounts.
local FX_RECIPES = {
	Wood = { { "Splinters", 1 }, { "Dust", 0.5 } },
	Stone = { { "Dust", 1 }, { "Sparks", 0.25 } },
	Snow = { { "Snow", 1.2 } },
	Glass = { { "Shards", 1.3 }, { "Sparkle", 0.3 } },
	Energy = { { "Energy", 1 }, { "Sparks", 0.5 } },
	Metal = { { "Sparks", 1.5 }, { "Shards", 0.3 } },
	Gold = { { "Sparkle", 1.2 }, { "Sparks", 0.4 } },
	Explosive = { { "Fire", 1 }, { "Sparks", 1 }, { "Dust", 0.8 } },
}
local TIER_COUNT = { 4, 8, 14, 22 }

local fxEmitters = {} -- [name] = { Part, Emitter }
local function fxEmitter(name: string)
	local existing = fxEmitters[name]
	if existing and existing.Part.Parent then
		return existing
	end
	local holder = fxPart({ Name = "SlingFx_" .. name, Size = Vector3.new(1, 1, 1), Transparency = 1 })
	local entry = { Part = holder, Emitter = emitter(holder, FX_DEFS[name]) }
	fxEmitters[name] = entry
	return entry
end

local function emitFx(name: string, cframe: CFrame, count: number)
	if count <= 0 then
		return
	end
	local entry = fxEmitter(name)
	entry.Part.CFrame = cframe
	entry.Emitter:Emit(count)
end

--------------------------------------------------------------------------------
-- Pooled rings, pulses and lightning
--------------------------------------------------------------------------------

local RING_SEGMENTS = 12
local rings = {} -- pool: { Parts, Active, Start, Duration, CFrame, R0, R1, Thickness }
local pulses = {} -- pool: { Part, Active, Start, Duration, S0, S1 }
local bolts = {} -- pool: { Parts, Active, Start, Duration }

local function ringPoolSize(): number
	local q = Quality.Current.Name
	return if q == "High" then 10 elseif q == "Medium" then 6 else 4
end

local function getRing()
	for _, ring in rings do
		if not ring.Active then
			return ring
		end
	end
	if #rings < ringPoolSize() then
		local ring = { Parts = {}, Active = false }
		for _ = 1, RING_SEGMENTS do
			table.insert(ring.Parts, fxPart({ Name = "RingFx", Size = Vector3.new(0.5, 1, 0.5), Transparency = 1 }))
		end
		table.insert(rings, ring)
		return ring
	end
	-- Reuse the oldest ring.
	local oldest = rings[1]
	for _, ring in rings do
		if ring.Start < oldest.Start then
			oldest = ring
		end
	end
	return oldest
end

-- An expanding, fading ring in the plane of `cframe` (its local X/Y).
function Effects.Ring(cframe: CFrame, color: Color3, startRadius: number, endRadius: number, duration: number, thickness: number?)
	local ring = getRing()
	ring.Active = true
	ring.Start = os.clock()
	ring.Duration = duration
	ring.CFrame = cframe
	ring.R0 = startRadius
	ring.R1 = endRadius
	ring.Thickness = thickness or 0.8
	for _, segment in ring.Parts do
		segment.Color = color
	end
end

-- Flat ring on the ground.
function Effects.GroundRing(position: Vector3, color: Color3, startRadius: number, endRadius: number, duration: number)
	Effects.Ring(CFrame.new(position) * CFrame.Angles(math.pi / 2, 0, 0), color, startRadius, endRadius, duration, 1)
end

-- An expanding energy bubble.
function Effects.Pulse(position: Vector3, color: Color3, startSize: number, endSize: number, duration: number)
	local pulse = nil
	for _, candidate in pulses do
		if not candidate.Active then
			pulse = candidate
			break
		end
	end
	if not pulse then
		if #pulses >= 4 then
			pulse = pulses[1]
		else
			pulse = {
				Part = fxPart({
					Name = "PulseFx",
					Shape = Enum.PartType.Ball,
					Material = Enum.Material.ForceField,
					Size = Vector3.new(1, 1, 1),
					Transparency = 1,
				}),
			}
			table.insert(pulses, pulse)
		end
	end
	pulse.Active = true
	pulse.Start = os.clock()
	pulse.Duration = duration
	pulse.S0 = startSize
	pulse.S1 = endSize
	pulse.Position = position
	pulse.Part.Color = color
	pulse.Part.Transparency = 0
end

-- A jagged lightning bolt between two points that flickers out.
function Effects.Lightning(from: Vector3, to: Vector3, color: Color3, duration: number?, segments: number?)
	if not Quality.Current.Lightning then
		return
	end
	local count = segments or 6
	local bolt = nil
	for _, candidate in bolts do
		if not candidate.Active and #candidate.Parts >= count then
			bolt = candidate
			break
		end
	end
	if not bolt then
		if #bolts >= 10 then
			return
		end
		bolt = { Parts = {}, Active = false }
		for _ = 1, count do
			table.insert(bolt.Parts, fxPart({ Name = "BoltFx", Size = Vector3.new(0.25, 0.25, 1), Transparency = 1 }))
		end
		table.insert(bolts, bolt)
	end
	local length = (to - from).Magnitude
	local jitter = length * 0.12
	local previous = from
	for i = 1, #bolt.Parts do
		local segment = bolt.Parts[i]
		if i > count then
			segment.Transparency = 1
			continue
		end
		local target = if i == count
			then to
			else from + (to - from) * (i / count) + Vector3.new(rng:NextNumber(-jitter, jitter), rng:NextNumber(-jitter, jitter), rng:NextNumber(-jitter, jitter))
		local span = (target - previous).Magnitude
		segment.Size = Vector3.new(0.22, 0.22, math.max(0.1, span))
		segment.CFrame = CFrame.lookAt((previous + target) / 2, target)
		segment.Color = color
		segment.Transparency = 0
		previous = target
	end
	bolt.Active = true
	bolt.Start = os.clock()
	bolt.Duration = duration or 0.12
	bolt.Count = count
end

local function updatePools()
	local now = os.clock()
	for _, ring in rings do
		if ring.Active then
			local alpha = (now - ring.Start) / ring.Duration
			if alpha >= 1 then
				ring.Active = false
				for _, segment in ring.Parts do
					segment.Transparency = 1
				end
			else
				local eased = 1 - (1 - alpha) ^ 3
				local radius = ring.R0 + (ring.R1 - ring.R0) * eased
				local chord = 2 * radius * math.sin(math.pi / RING_SEGMENTS) + ring.Thickness * 0.5
				local thickness = ring.Thickness * (1 - alpha * 0.5)
				for i, segment in ring.Parts do
					local angle = (i / RING_SEGMENTS) * math.pi * 2
					segment.Size = Vector3.new(thickness, chord, thickness)
					segment.CFrame = ring.CFrame * CFrame.new(math.cos(angle) * radius, math.sin(angle) * radius, 0) * CFrame.Angles(0, 0, angle)
					segment.Transparency = alpha ^ 1.5
				end
			end
		end
	end
	for _, pulse in pulses do
		if pulse.Active then
			local alpha = (now - pulse.Start) / pulse.Duration
			if alpha >= 1 then
				pulse.Active = false
				pulse.Part.Transparency = 1
			else
				local size = pulse.S0 + (pulse.S1 - pulse.S0) * (1 - (1 - alpha) ^ 2)
				pulse.Part.Size = Vector3.new(size, size, size)
				pulse.Part.CFrame = CFrame.new(pulse.Position)
				pulse.Part.Transparency = alpha
			end
		end
	end
	for _, bolt in bolts do
		if bolt.Active then
			local alpha = (now - bolt.Start) / bolt.Duration
			local transparency = if alpha >= 1 then 1 else alpha * 0.8 + (if rng:NextNumber() < 0.3 then 0.3 else 0)
			for i, segment in bolt.Parts do
				if i <= bolt.Count then
					segment.Transparency = math.min(1, transparency)
				end
			end
			if alpha >= 1 then
				bolt.Active = false
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Impacts, shockwaves, launches, explosions
--------------------------------------------------------------------------------

local lastImpactRing = 0

-- A material-specific impact. tier: 1 light, 2 heavy, 3 critical, 4 maximum.
function Effects.Impact(position: Vector3, fx: string, tier: number, color: Color3)
	local recipe = FX_RECIPES[fx] or FX_RECIPES.Stone
	local base = TIER_COUNT[math.clamp(tier, 1, 4)]
	local cframe = CFrame.new(position)
	for _, layer in recipe do
		emitFx(layer[1], cframe, Quality.Amount(base * layer[2], 0))
	end
	local now = os.clock()
	if tier >= 3 and Quality.Current.Name ~= "Low" and now - lastImpactRing > 0.12 then
		lastImpactRing = now
		Effects.Ring(CFrame.lookAt(position, position + Vector3.new(0, 0, 1)), color:Lerp(Color3.new(1, 1, 1), 0.4), 1, 5 + tier * 2, 0.3, 0.5)
	end
	if tier >= 4 then
		Effects.Pulse(position, color, 2, 14, 0.35)
	end
end

-- Layered rings, a bubble, dust and sparks: the Devastation look.
function Effects.Shockwave(position: Vector3, radius: number, color: Color3)
	local ground = Vector3.new(position.X, Config.GroundY + 0.5, position.Z)
	Effects.GroundRing(ground, color, 2, radius, 0.45)
	Effects.GroundRing(ground, Color3.new(1, 1, 1), 1, radius * 0.7, 0.35)
	task.delay(0.08, function()
		Effects.GroundRing(ground, color, 1, radius * 1.15, 0.55)
	end)
	Effects.Pulse(position, color, 3, radius * 1.6, 0.4)
	local cframe = CFrame.new(position)
	emitFx("Dust", CFrame.new(ground), Quality.Amount(26))
	emitFx("Sparks", cframe, Quality.Amount(30))
	emitFx("Energy", cframe, Quality.Amount(14))
	Effects.Flash(color, 0.35)
	Effects.Shake(2)
	Effects.Play("Shockwave", 1, 1, true)
end

-- Launch burst scaled by power: rings, sparks and speed streaks.
function Effects.Launch(position: Vector3, direction: Vector3, power: number)
	local facing = CFrame.lookAt(position, position + direction)
	local cyan = Color3.fromRGB(140, 240, 255)
	Effects.Ring(facing, cyan, 1, 5 + power * 9, 0.35, 0.9)
	Effects.GroundRing(Config.SlingshotPosition + Vector3.new(0, 0.9, 0), Color3.fromRGB(255, 226, 120), 3, 8 + power * 14, 0.5)
	emitFx("Sparks", CFrame.new(position), Quality.Amount(8 + power * 22))
	emitFx("Streaks", facing, Quality.Amount(10 + power * 30))
	if power >= 0.99 then
		task.delay(0.07, function()
			Effects.Ring(facing * CFrame.new(0, 0, -4), Color3.new(1, 1, 1), 1, 16, 0.4, 1.2)
		end)
		Effects.Pulse(position, cyan, 2, 14, 0.3)
		Effects.Flash(Color3.fromRGB(200, 250, 255), 0.45)
	else
		Effects.Flash(Color3.fromRGB(255, 255, 255), 0.12 + power * 0.18)
	end
	Effects.Shake(0.4 + power * 1.2)
end

-- Nitro activation: rings and a bubble along the direction of travel.
function Effects.NitroBurst(position: Vector3, direction: Vector3)
	local facing = CFrame.lookAt(position, position + direction)
	local cyan = Color3.fromRGB(80, 230, 255)
	Effects.Ring(facing, cyan, 2, 12, 0.35, 0.9)
	task.delay(0.06, function()
		Effects.Ring(facing * CFrame.new(0, 0, 5), Color3.new(1, 1, 1), 1.5, 9, 0.3, 0.6)
	end)
	Effects.Pulse(position, cyan, 2, 10, 0.25)
	emitFx("Energy", CFrame.new(position), Quality.Amount(18))
	emitFx("Streaks", facing, Quality.Amount(24))
	Effects.Flash(cyan, 0.25)
	Effects.Play("Nitro", 1, 1, true)
	Effects.Shake(1)
end

-- Client-side explosion: purely visual, never hurts anyone.
function Effects.Explosion(position: Vector3, radius: number)
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = radius
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.Parent = Workspace
	Effects.Impact(position, "Explosive", 3, Color3.fromRGB(255, 140, 40))
	Effects.GroundRing(Vector3.new(position.X, Config.GroundY + 0.4, position.Z), Color3.fromRGB(255, 150, 50), 2, radius * 1.3, 0.4)
end

--------------------------------------------------------------------------------
-- Slingshot charge-up
--------------------------------------------------------------------------------

local charge = nil -- { Holder, Emitter, Light, Core, CoreLight, CoreSize, CoreColor }

local function slingCore(): (BasePart?, PointLight?)
	local map = Workspace:FindFirstChild("Map")
	local slingshot = map and map:FindFirstChild("Slingshot")
	local core = slingshot and slingshot:FindFirstChild("Core")
	if core and core:IsA("BasePart") then
		local light = core:FindFirstChildOfClass("PointLight")
		return core, light
	end
	return nil, nil
end

function Effects.StartCharge(position: Vector3)
	Effects.StopCharge()
	local holder = fxPart({ Name = "ChargeFx", Size = Vector3.new(7, 7, 7), Transparency = 1, CFrame = CFrame.new(position) })
	local swirl = emitter(holder, {
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		Lifetime = NumberRange.new(0.35, 0.55),
		Speed = NumberRange.new(6, 10),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
		LightEmission = 1,
		Color = ColorSequence.new(Color3.fromRGB(120, 230, 255), Color3.fromRGB(255, 255, 255)),
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(120, 230, 255)
	light.Range = 14
	light.Brightness = 0
	light.Parent = holder
	local core, coreLight = slingCore()
	charge = {
		Holder = holder,
		Emitter = swirl,
		Light = light,
		Core = core,
		CoreLight = coreLight,
		CoreSize = if core then core.Size else nil,
		CoreColor = if core then core.Color else nil,
		Overcharged = false,
	}
	if chargeHum and Effects.Settings.SFX then
		chargeHum.Volume = 0
		chargeHum:Play()
	end
end

-- power 0..1. Energy gathers faster and brighter as you pull back.
function Effects.UpdateCharge(position: Vector3, power: number)
	local c = charge
	if not c then
		return
	end
	local pulse = 0.5 + 0.5 * math.sin(os.clock() * (6 + power * 14))
	c.Holder.CFrame = CFrame.new(position)
	c.Emitter.Rate = Quality.Amount(10 + 110 * power * power, 0)
	local hot = Color3.fromRGB(120, 230, 255):Lerp(Color3.fromRGB(255, 240, 160), math.max(0, power - 0.7) / 0.3)
	c.Light.Color = hot
	c.Light.Brightness = power * 3 + pulse * power * 2
	if c.Core and c.CoreSize then
		local grow = 1 + power * 0.7 + pulse * 0.15 * power
		c.Core.Size = c.CoreSize * grow
		c.Core.Color = (c.CoreColor :: Color3):Lerp(hot, power)
		if c.CoreLight then
			c.CoreLight.Brightness = 1.2 + power * 4
		end
	end
	if chargeHum then
		chargeHum.PlaybackSpeed = 0.8 + power
		chargeHum.Volume = 0.15 + power * 0.35
	end
end

-- The burst at 100%: a ring, a bubble and a flash.
function Effects.Overcharge(position: Vector3)
	local gold = Color3.fromRGB(255, 230, 120)
	Effects.Ring(CFrame.lookAt(position, position + Config.Forward), gold, 1, 9, 0.35, 0.8)
	Effects.Pulse(position, gold, 2, 9, 0.3)
	emitFx("Sparkle", CFrame.new(position), Quality.Amount(20))
	Effects.Flash(gold, 0.2)
	Effects.Play("Victory", 1.3, 0.8, true)
	Effects.Shake(0.5)
end

function Effects.StopCharge()
	local c = charge
	if not c then
		return
	end
	charge = nil
	c.Emitter.Rate = 0
	Debris:AddItem(c.Holder, 1)
	if c.Core and c.CoreSize then
		c.Core.Size = c.CoreSize
		c.Core.Color = c.CoreColor :: Color3
		if c.CoreLight then
			c.CoreLight.Brightness = 1.2
		end
	end
	if chargeHum then
		chargeHum:Stop()
	end
end

--------------------------------------------------------------------------------
-- Power-up auras (Meteor / Rift / Phase) and Nitro thrust
--------------------------------------------------------------------------------

local aura = nil -- { Kind, Parts, Spin, Ghosts, Highlight, ... }
local nitroTrail: Trail? = nil
local nitroHolder: BasePart? = nil
local lastBolt = 0

-- Afterimage clones are built once per character and reused for every Phase.
local ghostCache = nil -- { Character, Count, Sets }

local function hideGhosts(sets)
	for _, set in sets do
		set.Born = -10
		for _, entry in set.Parts do
			entry.Ghost.Transparency = 1
		end
	end
end

local function destroyGhosts()
	if ghostCache then
		for _, set in ghostCache.Sets do
			for _, entry in set.Parts do
				entry.Ghost:Destroy()
			end
		end
		ghostCache = nil
	end
end

local function buildGhosts(character: Model, sets: number)
	local sources = {}
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 0.9 then
			table.insert(sources, d)
			if #sources >= 18 then
				break
			end
		end
	end
	local ghosts = {}
	for _ = 1, sets do
		local set = { Parts = {}, Born = -10 }
		for _, source in sources do
			local ok, ghost = pcall(function()
				return source:Clone()
			end)
			if ok and ghost then
				for _, child in ghost:GetChildren() do
					child:Destroy()
				end
				ghost.Anchored = true
				ghost.CanCollide = false
				ghost.CanQuery = false
				ghost.CanTouch = false
				ghost.CastShadow = false
				ghost.Material = Enum.Material.Neon
				ghost.Color = Color3.fromRGB(120, 255, 255)
				ghost.Transparency = 1
				if ghost:IsA("MeshPart") then
					ghost.TextureID = ""
				end
				ghost.Parent = folder()
				table.insert(set.Parts, { Ghost = ghost, Source = source })
			end
		end
		table.insert(ghosts, set)
	end
	return ghosts
end

function Effects.StopAura()
	local a = aura
	if not a then
		return
	end
	aura = nil
	for _, p in a.Parts do
		p:Destroy()
	end
	if a.Highlight then
		a.Highlight:Destroy()
	end
	if a.Ghosts then
		hideGhosts(a.Ghosts)
	end
	Effects.SetAbilityTint(nil)
	Effects.SetSpeedLineColor(Color3.new(1, 1, 1))
end

-- Starts the look for a power-up. kind: "Meteor" | "Rift" | "Phase".
function Effects.StartAura(kind: string, character: Model?)
	Effects.StopAura()
	local ability = Config.Abilities[kind]
	if not ability then
		return
	end
	local color = ability.Color
	local a = { Kind = kind, Parts = {}, Spin = 0, Ghosts = nil, NextGhost = 0, GhostIndex = 1 }
	aura = a

	local function add(p: BasePart): BasePart
		table.insert(a.Parts, p)
		return p
	end

	if kind == "Meteor" then
		local glow = add(fxPart({ Name = "MeteorGlow", Shape = Enum.PartType.Ball, Size = Vector3.new(3.6, 3.6, 3.6), Color = Color3.fromRGB(255, 170, 60), Transparency = 0.35 }))
		add(fxPart({ Name = "MeteorShell", Shape = Enum.PartType.Ball, Material = Enum.Material.ForceField, Size = Vector3.new(6.5, 6.5, 6.5), Color = color }))
		local fire = Instance.new("Fire")
		fire.Size = 7
		fire.Heat = 15
		fire.Color = Color3.fromRGB(255, 160, 40)
		fire.SecondaryColor = Color3.fromRGB(255, 50, 20)
		fire.Parent = glow
		local smoke = Instance.new("Smoke")
		smoke.Color = Color3.fromRGB(60, 50, 50)
		smoke.Opacity = 0.12
		smoke.RiseVelocity = 2
		smoke.Size = 3
		smoke.Parent = glow
		emitter(glow, {
			Rate = Quality.Amount(30, 0),
			Lifetime = NumberRange.new(0.5, 0.9),
			Speed = NumberRange.new(2, 6),
			SpreadAngle = Vector2.new(180, 180),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }),
			LightEmission = 1,
			Color = ColorSequence.new(Color3.fromRGB(255, 230, 120), Color3.fromRGB(255, 80, 20)),
		})
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 18
		light.Brightness = 3
		light.Parent = glow
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(-1.6, 0, 0)
		a0.Parent = glow
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(1.6, 0, 0)
		a1.Parent = glow
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.45
		trail.LightEmission = 1
		trail.FaceCamera = true
		trail.Color = ColorSequence.new(Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 40, 20))
		trail.Transparency = NumberSequence.new(0.1, 1)
		trail.WidthScale = NumberSequence.new(1, 0.1)
		trail.Parent = glow
		Effects.SetAbilityTint(Color3.fromRGB(255, 232, 214), 0.1)
		Effects.SetSpeedLineColor(Color3.fromRGB(255, 190, 120))
	elseif kind == "Rift" then
		add(fxPart({ Name = "RiftShell", Shape = Enum.PartType.Ball, Material = Enum.Material.ForceField, Size = Vector3.new(10, 10, 10), Color = color }))
		-- Glass refracts what's behind it: a cheap, real "warped space" look.
		add(fxPart({ Name = "RiftLens", Shape = Enum.PartType.Ball, Material = Enum.Material.Glass, Size = Vector3.new(7, 7, 7), Color = Color3.fromRGB(200, 170, 255), Transparency = 0.55 }))
		a.RingParts = {}
		for r = 1, 2 do
			for i = 1, RING_SEGMENTS do
				local segment = add(fxPart({ Name = "RiftRing", Size = Vector3.new(0.4, 1.6, 0.4), Color = if r == 1 then color else Color3.fromRGB(90, 160, 255) }))
				table.insert(a.RingParts, { Part = segment, Ring = r, Index = i })
			end
		end
		local well = add(fxPart({ Name = "RiftWell", Size = Vector3.new(22, 22, 22), Transparency = 1 }))
		emitter(well, {
			Rate = Quality.Amount(40, 0),
			Shape = Enum.ParticleEmitterShape.Sphere,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
			ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
			Lifetime = NumberRange.new(0.8, 1.1),
			Speed = NumberRange.new(10, 14),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.5, 0.8), NumberSequenceKeypoint.new(1, 0) }),
			LightEmission = 1,
			Color = ColorSequence.new(Color3.fromRGB(220, 170, 255), color),
		})
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 20
		light.Brightness = 2.5
		light.Parent = well
		Effects.SetAbilityTint(Color3.fromRGB(230, 214, 255), -0.1)
		Effects.SetSpeedLineColor(Color3.fromRGB(200, 160, 255))
	elseif kind == "Phase" then
		add(fxPart({ Name = "PhaseShell", Shape = Enum.PartType.Ball, Material = Enum.Material.ForceField, Size = Vector3.new(7.5, 7.5, 7.5), Color = color }))
		if character then
			local highlight = Instance.new("Highlight")
			highlight.Adornee = character
			highlight.FillColor = color
			highlight.FillTransparency = 0.7
			highlight.OutlineColor = Color3.fromRGB(230, 255, 255)
			highlight.OutlineTransparency = 0
			highlight.DepthMode = Enum.HighlightDepthMode.Occluded
			highlight.Parent = folder()
			a.Highlight = highlight
			local count = Quality.Current.Afterimages
			local cache = ghostCache
			if not cache or cache.Character ~= character or cache.Count ~= count or not character.Parent then
				destroyGhosts()
				cache = { Character = character, Count = count, Sets = buildGhosts(character, count) }
				ghostCache = cache
			end
			a.Ghosts = (cache :: any).Sets
		end
		Effects.SetAbilityTint(Color3.fromRGB(214, 250, 255), -0.15)
		Effects.SetSpeedLineColor(Color3.fromRGB(170, 255, 255))
	end
end

-- Called every frame while flying with the flyer's CFrame and velocity.
function Effects.UpdateFlight(cframe: CFrame, velocity: Vector3, dt: number, thrusting: boolean)
	local position = cframe.Position
	local now = os.clock()
	local a = aura
	if a then
		a.Spin += dt
		for _, p in a.Parts do
			if p.Name ~= "RiftRing" then
				p.CFrame = CFrame.new(position)
			end
		end
		if a.RingParts then
			for _, entry in a.RingParts do
				local tilt = if entry.Ring == 1 then CFrame.Angles(math.rad(70), a.Spin * 2.2, 0) else CFrame.Angles(math.rad(-50), -a.Spin * 3, math.rad(40))
				local angle = (entry.Index / RING_SEGMENTS) * math.pi * 2
				local radius = if entry.Ring == 1 then 6.5 else 5
				entry.Part.CFrame = CFrame.new(position) * tilt * CFrame.new(math.cos(angle) * radius, math.sin(angle) * radius, 0) * CFrame.Angles(0, 0, angle)
			end
		end
		if a.Ghosts and #a.Ghosts > 0 then
			if now >= a.NextGhost then
				a.NextGhost = now + 0.07
				local set = a.Ghosts[a.GhostIndex]
				a.GhostIndex = a.GhostIndex % #a.Ghosts + 1
				set.Born = now
				for _, entry in set.Parts do
					if entry.Source.Parent then
						entry.Ghost.Size = entry.Source.Size
						entry.Ghost.CFrame = entry.Source.CFrame
						entry.Ghost.Transparency = 0.45
					end
				end
			end
			for _, set in a.Ghosts do
				local alpha = (now - set.Born) / 0.35
				if alpha <= 1.05 then
					for _, entry in set.Parts do
						entry.Ghost.Transparency = math.min(1, 0.45 + 0.55 * alpha)
					end
				end
			end
		end
	end

	-- Nitro: a cyan trail and crackling bolts while thrusting.
	local holder = nitroHolder
	if not holder or not holder.Parent then
		holder = fxPart({ Name = "NitroFx", Size = Vector3.new(1, 1, 1), Transparency = 1 })
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(-1.4, 0, 0)
		a0.Parent = holder
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(1.4, 0, 0)
		a1.Parent = holder
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.35
		trail.LightEmission = 1
		trail.FaceCamera = true
		trail.Color = ColorSequence.new(Color3.fromRGB(220, 255, 255), Color3.fromRGB(40, 140, 255))
		trail.Transparency = NumberSequence.new(0, 1)
		trail.WidthScale = NumberSequence.new(1, 0.2)
		trail.Enabled = false
		trail.Parent = holder
		nitroHolder = holder
		nitroTrail = trail
	end
	holder.CFrame = cframe
	if nitroTrail then
		nitroTrail.Enabled = thrusting
	end
	if thrusting and now - lastBolt > 0.05 and velocity.Magnitude > 1 then
		lastBolt = now
		local back = -velocity.Unit
		local offset = Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(-2, 2), rng:NextNumber(-2, 2))
		Effects.Lightning(position + offset * 0.5, position + back * rng:NextNumber(6, 11) + offset, Color3.fromRGB(140, 240, 255), 0.1, 5)
	end
end

function Effects.EndFlight()
	Effects.StopAura()
	if nitroTrail then
		nitroTrail.Enabled = false
	end
end

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

function Effects.Init(playerGui: Instance)
	sfxGroup = Instance.new("SoundGroup")
	local group = sfxGroup :: SoundGroup
	group.Name = "SlingSFX"
	group.Volume = 0.9
	group.Parent = SoundService
	-- Gentle compression keeps big chains from clipping.
	local compressor = Instance.new("CompressorSoundEffect")
	compressor.Threshold = -14
	compressor.Ratio = 3
	compressor.Attack = 0.01
	compressor.Release = 0.15
	compressor.Parent = group

	local list = {}
	for name, id in Config.Sounds do
		if name ~= "Music" and name ~= "Wind" then
			local sound = makeSound(name, id, 0.5, false, group)
			if sound then
				templates[name] = sound
				table.insert(list, sound)
			end
		end
	end
	wind = makeSound("Wind", Config.Sounds.Wind, 0, true, group)
	music = makeSound("Music", Config.Sounds.Music, 0.35, true, nil)
	chargeHum = makeSound("ChargeHum", Config.Sounds.Charge, 0, true, group)
	for _, sound in { wind, chargeHum } do
		if sound then
			table.insert(list, sound)
		end
	end
	preloadSounds(list)

	local gui = Widgets.new("ScreenGui", {
		Name = "SlingEffects",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = -1,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
		Parent = playerGui,
	})
	speedGui = gui
	for i = 1, Config.Quality.High.SpeedLines do
		local line = Widgets.new("Frame", {
			Name = "Line" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(3, rng:NextInteger(70, 180)),
			BackgroundTransparency = 1,
			Parent = gui,
		})
		table.insert(speedLines, {
			Frame = line,
			Angle = rng:NextNumber(0, math.pi * 2),
			Radius = rng:NextNumber(0.2, 0.8),
			Speed = rng:NextNumber(0.9, 1.6),
			Color = Color3.new(1, 1, 1),
		})
	end

	local flashGui = Widgets.new("ScreenGui", {
		Name = "SlingFlash",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 50,
		Parent = playerGui,
	})
	flashFrame = Widgets.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = flashGui,
	})

	local tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "SlingAbilityTint"
	tint.TintColor = Color3.new(1, 1, 1)
	tint.Parent = Lighting
	abilityTint = tint

	RunService.RenderStepped:Connect(updatePools)
	Effects.ApplySettings(Effects.Settings)
end

function Effects.ApplySettings(settings)
	for key, value in settings do
		Effects.Settings[key] = value
	end
	if music then
		if Effects.Settings.Music then
			if not music.IsPlaying then
				music:Play()
			end
		else
			music:Stop()
		end
	end
	if not Effects.Settings.SpeedLines and speedGui then
		speedGui.Enabled = false
	end
end

return Effects
