--[[
	Per-biome lighting and weather, on this client only.

	As you fly (or walk) down the lane, the time of day, fog, colour grade and
	bloom blend smoothly from one biome's preset to the next (Config.Zones[i]
	.Lighting), and a single weather emitter in front of the camera switches
	between wisps, leaves, embers, snow and neon motes. The Volcanic Wasteland
	adds distant lightning.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local CourseLayout = require(ReplicatedStorage.Shared.CourseLayout)
local Effects = require(script.Parent.Effects)
local Quality = require(script.Parent.Quality)

local Atmosphere = {}

local BLEND = 70 -- studs either side of a biome edge to blend over
local rng = Random.new()

local holder: BasePart? = nil
local weather = {} -- [name] = { Emitter, Rate }
local lastKey = ""
local currentWeather = nil
local nextLightning = 0

local WEATHER = {
	Wisps = {
		Rate = 3,
		Lifetime = NumberRange.new(4, 6),
		Speed = NumberRange.new(2, 4),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 9) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.8), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
		Acceleration = Vector3.new(1, 0, 0),
	},
	Leaves = {
		Rate = 10,
		Lifetime = NumberRange.new(3, 5),
		Speed = NumberRange.new(2, 5),
		Size = NumberSequence.new(0.5),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-120, 120),
		Color = ColorSequence.new(Color3.fromRGB(110, 190, 70), Color3.fromRGB(200, 170, 60)),
		Acceleration = Vector3.new(3, -3, 0),
	},
	Embers = {
		Rate = 18,
		Lifetime = NumberRange.new(2, 4),
		Speed = NumberRange.new(1, 4),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }),
		LightEmission = 1,
		Color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 70, 20)),
		Acceleration = Vector3.new(2, 4, 0),
	},
	Snow = {
		Rate = 34,
		Lifetime = NumberRange.new(3, 5),
		Speed = NumberRange.new(6, 10),
		Size = NumberSequence.new(0.45),
		Transparency = NumberSequence.new(0.1, 0.4),
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
		Acceleration = Vector3.new(4, -2, 0),
	},
	Data = {
		Rate = 12,
		Lifetime = NumberRange.new(2, 4),
		Speed = NumberRange.new(1, 3),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 0.3), NumberSequenceKeypoint.new(1, 0) }),
		LightEmission = 1,
		Color = ColorSequence.new(Color3.fromRGB(0, 230, 255), Color3.fromRGB(255, 60, 200)),
		Acceleration = Vector3.new(0, 1, 0),
	},
}

local function ensureHolder(): BasePart
	if holder and holder.Parent then
		return holder
	end
	local part = Instance.new("Part")
	part.Name = "SlingWeather"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(90, 1, 90)
	part.Parent = Workspace
	for name, props in WEATHER do
		local e = Instance.new("ParticleEmitter")
		e.Name = name
		e.EmissionDirection = Enum.NormalId.Bottom
		e.SpreadAngle = Vector2.new(25, 25)
		for key, value in props do
			if key ~= "Rate" then
				(e :: any)[key] = value
			end
		end
		e.Rate = 0
		e.Parent = part
		weather[name] = { Emitter = e, Rate = props.Rate }
	end
	holder = part
	return part
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- The preset for a distance, blended near biome edges.
local function presetAt(distance: number)
	local index = CourseLayout.ZoneIndexAt(distance)
	local zone = Config.Zones[index]
	local nextZone = Config.Zones[index + 1]
	local previousZone = Config.Zones[index - 1]
	local a, b, t = zone.Lighting, zone.Lighting, 0
	if nextZone and distance > zone.EndsAt - BLEND then
		a, b = zone.Lighting, nextZone.Lighting
		t = math.clamp((distance - (zone.EndsAt - BLEND)) / (BLEND * 2), 0, 0.5)
	elseif previousZone and distance < previousZone.EndsAt + BLEND then
		a, b = previousZone.Lighting, zone.Lighting
		t = math.clamp((distance - (previousZone.EndsAt - BLEND)) / (BLEND * 2), 0.5, 1)
	end
	return a, b, t, index
end

local function apply(a, b, t: number)
	Lighting.ClockTime = lerp(a.ClockTime, b.ClockTime, t) % 24
	Lighting.Brightness = lerp(a.Brightness, b.Brightness, t)
	Lighting.Ambient = a.Ambient:Lerp(b.Ambient, t)
	Lighting.OutdoorAmbient = a.OutdoorAmbient:Lerp(b.OutdoorAmbient, t)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density = lerp(a.Density, b.Density, t)
		atmosphere.Haze = lerp(a.Haze, b.Haze, t)
		atmosphere.Glare = lerp(a.Glare, b.Glare, t)
		atmosphere.Color = a.AtmosphereColor:Lerp(b.AtmosphereColor, t)
		atmosphere.Decay = a.Decay:Lerp(b.Decay, t)
	end
	for _, child in Lighting:GetChildren() do
		if child:IsA("ColorCorrectionEffect") and child.Name ~= "SlingAbilityTint" then
			child.TintColor = a.Tint:Lerp(b.Tint, t)
			child.Saturation = lerp(a.Saturation, b.Saturation, t)
			child.Contrast = lerp(a.Contrast, b.Contrast, t)
		elseif child:IsA("BloomEffect") then
			child.Intensity = lerp(a.Bloom, b.Bloom, t)
		end
	end
end

local function lightningStrike(cameraCFrame: CFrame)
	local ahead = cameraCFrame.Position + cameraCFrame.LookVector * rng:NextNumber(250, 450)
	local top = ahead + Vector3.new(rng:NextNumber(-250, 250), 220, 0)
	local bottom = Vector3.new(top.X + rng:NextNumber(-40, 40), Config.GroundY, top.Z + rng:NextNumber(-40, 40))
	Effects.Lightning(top, bottom, Color3.fromRGB(255, 230, 200), 0.25, 9)
	Lighting.ExposureCompensation = 0.9
	TweenService:Create(Lighting, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { ExposureCompensation = 0 }):Play()
	task.delay(rng:NextNumber(0.3, 0.9), function()
		Effects.Play("Boom", 0.35, 0.5)
	end)
end

-- distance: how far down the lane the player (or camera) is.
function Atmosphere.Update(distance: number, cameraCFrame: CFrame?)
	local a, b, t, index = presetAt(math.max(0, distance))
	local key = string.format("%d:%.2f", index, t)
	if key ~= lastKey then
		lastKey = key
		apply(a, b, t)
	end

	local zone = Config.Zones[index]
	local part = ensureHolder()
	if cameraCFrame then
		part.CFrame = CFrame.new(cameraCFrame.Position + cameraCFrame.LookVector * 35 + Vector3.new(0, 22, 0))
	end
	local scale = Quality.Current.Weather
	if currentWeather ~= zone.Weather or weather[zone.Weather].Applied ~= scale then
		currentWeather = zone.Weather
		for name, entry in weather do
			local on = name == zone.Weather
			entry.Emitter.Rate = if on then entry.Rate * scale else 0
			entry.Applied = if on then scale else nil
		end
	end

	-- Distant lightning over the volcanoes.
	if zone.Key == "Volcanic" and cameraCFrame and Quality.Current.Lightning then
		local now = os.clock()
		if now >= nextLightning then
			if nextLightning > 0 then
				lightningStrike(cameraCFrame)
			end
			nextLightning = now + rng:NextNumber(4, 9)
		end
	end
end

return Atmosphere
