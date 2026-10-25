--[[
	Smoke test: runs the real Instance-building code outside Roblox with Lune
	(https://lune-org.github.io/docs). Lune checks every property name, type
	and enum against Roblox's API dump, so typos fail here instead of in Studio.

	It builds the server world (terrain calls are recorded, not executed) and
	the client's course, power-up, hazard and effect visuals.

	Usage:  lune run tests/smoke.luau
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Instance = roblox.Instance

local ROOT = "src"
local game = Instance.new("DataModel")
local failures = 0

local emitted, played = 0, 0

local function check(condition: boolean, message: string)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

--------------------------------------------------------------------------------
-- Fake engine pieces Lune doesn't provide
--------------------------------------------------------------------------------

-- Terrain: records calls instead of filling voxels.
local terrainCalls = { FillBlock = 0, FillBall = 0, FillCylinder = 0, FillWedge = 0, SetMaterialColor = 0, Clear = 0 }
local fakeTerrain = setmetatable({}, {
	__index = function(_, key)
		if terrainCalls[key] ~= nil then
			return function(_self, ...)
				terrainCalls[key] += 1
				local args = { ... }
				if key == "FillBlock" or key == "FillBall" or key == "FillCylinder" then
					for _, value in args do
						if typeof(value) == "EnumItem" then
							check(tostring(value):find("Enum.Material.") ~= nil, key .. " needs a material")
						end
					end
				end
			end
		end
		return nil
	end,
	__newindex = function() end,
})

-- Random with Roblox's API shape.
local RandomMeta = {}
RandomMeta.__index = RandomMeta
function RandomMeta:NextNumber(a, b)
	self.s = (self.s * 1103515245 + 12345) % 2147483648
	local f = self.s / 2147483648
	if a == nil then
		return f
	end
	return a + (b - a) * f
end
function RandomMeta:NextInteger(a, b)
	return math.floor(self:NextNumber(a, b + 1 - 1e-9))
end
function RandomMeta:NextUnitVector()
	local v = roblox.Vector3.new(self:NextNumber(-1, 1), self:NextNumber(-1, 1), self:NextNumber(-1, 1))
	return v.Unit
end
local Random = {
	new = function(seed)
		return setmetatable({ s = (seed or 7) % 2147483648 }, RandomMeta)
	end,
}

-- TweenService:Create returns something with :Play() / :Cancel().
local tweens = 0
local fakeTweenService = {
	Create = function(_self, instance, _info, props)
		tweens += 1
		for key in props do
			check(pcall(function()
				return (instance :: any)[key]
			end), "tween targets a real property: " .. tostring(key))
		end
		return { Play = function() end, Cancel = function() end, Completed = { Connect = function() end, Wait = function() end } }
	end,
}

-- Signals that accept connections and never fire.
local fakeSignal = {
	Connect = function()
		return { Disconnect = function() end }
	end,
	Wait = function() end,
}

local fakeServices = {
	TweenService = fakeTweenService,
	Debris = { AddItem = function() end },
	RunService = {
		Heartbeat = fakeSignal,
		RenderStepped = fakeSignal,
		Stepped = fakeSignal,
		IsStudio = function()
			return true
		end,
		BindToRenderStep = function() end,
		UnbindFromRenderStep = function() end,
	},
	ContentProvider = { PreloadAsync = function() end },
	UserInputService = { TouchEnabled = false, KeyboardEnabled = true, GamepadEnabled = false, InputBegan = fakeSignal, InputEnded = fakeSignal, InputChanged = fakeSignal },
}

local gameProxy = setmetatable({}, {
	__index = function(_, key)
		if key == "GetService" then
			return function(_self, name)
				return fakeServices[name] or game:GetService(name)
			end
		end
		return (game :: any)[key]
	end,
})

--------------------------------------------------------------------------------
-- Module loader: ModuleScript instances that load our source files
--------------------------------------------------------------------------------

local sources = {} -- [ModuleScript] = path
local loaded = {} -- [ModuleScript] = result

local function addModules(parent, folder: string)
	for _, file in fs.readDir(folder) do
		local path = folder .. "/" .. file
		if fs.isFile(path) and file:match("%.luau$") and not file:match("%.server%.luau$") and not file:match("%.client%.luau$") then
			local module = Instance.new("ModuleScript")
			module.Name = file:gsub("%.luau$", "")
			module.Parent = parent
			sources[module] = path
		end
	end
end

local shared = Instance.new("Folder")
shared.Name = "Shared"
shared.Parent = game:GetService("ReplicatedStorage")
addModules(shared, ROOT .. "/shared")

local server = Instance.new("Script")
server.Name = "Server"
addModules(server, ROOT .. "/server")

local client = Instance.new("LocalScript")
client.Name = "Client"
addModules(client, ROOT .. "/client")

local requireModule

local function environment(scriptInstance)
	return setmetatable({
		game = gameProxy,
		workspace = game:GetService("Workspace"),
		script = scriptInstance,
		require = requireModule,
		Random = Random,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		NumberRange = roblox.NumberRange,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		TweenInfo = { new = function(...)
			return { ... }
		end },
		Enum = roblox.Enum,
		Instance = Instance,
		typeof = typeof,
		task = { spawn = function() end, delay = function() end, defer = function() end, wait = function()
			return 0
		end },
		os = os,
		warn = function(...)
			print("warn:", ...)
		end,
	}, { __index = _G })
end

requireModule = function(module)
	if typeof(module) ~= "Instance" then
		error("require() needs a ModuleScript, got " .. typeof(module))
	end
	if loaded[module] ~= nil then
		return loaded[module]
	end
	local path = sources[module]
	if not path then
		error("No source for " .. module:GetFullName())
	end
	local source = fs.readFile(path)
	-- Lune has no voxel terrain, so the world builder talks to the recorder.
	source = source:gsub("Workspace%.Terrain", "__fakeTerrain")
	-- Lune Instances have no events; property-changed signals become no-ops.
	source = source:gsub("[%w_%.]+:GetPropertyChangedSignal%b()", "__fakeSignal")
	-- Lune's camera has no viewport; UI code falls back to a default size.
	source = source:gsub("Workspace%.CurrentCamera", "__noCamera")
	-- Engine methods Lune doesn't implement are recorded instead.
	source = source:gsub("([%w_%.%[%]]+):Emit%(", "__emit(%1, ")
	source = source:gsub("([%w_%.]+):Play%(%)", "__play(%1)")
	source = source:gsub("([%w_%.]+):Stop%(%)", "__stop(%1)")
	local env = environment(module)
	env.__emit = function(emitterInstance, count)
		check(typeof(emitterInstance) == "Instance" and emitterInstance:IsA("ParticleEmitter"), "Emit on a ParticleEmitter")
		check(type(count) == "number" and count >= 0 and count == math.floor(count), "Emit count is a whole number: " .. tostring(count))
		emitted += count
	end
	env.__play = function(target)
		if typeof(target) == "Instance" then
			check(target:IsA("Sound"), "Play on a Sound")
			played += 1
		elseif type(target) == "table" and target.Play then
			target.Play(target)
		end
	end
	env.__stop = function() end
	env.__fakeTerrain = fakeTerrain
	env.__fakeSignal = fakeSignal
	local chunk = luau.load(source, { debugName = path, environment = env })
	local result = chunk()
	loaded[module] = result
	return result
end

local function count(root, className: string): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA(className) then
			n += 1
		end
	end
	return n
end

--------------------------------------------------------------------------------
-- Server world
--------------------------------------------------------------------------------

local ok, err = pcall(function()
	local WorldBuilder = requireModule(server:FindFirstChild("WorldBuilder"))
	local map = WorldBuilder.Build()
	local parts = count(map, "BasePart")
	print(string.format(
		"World: %d parts, %d particle emitters, %d beams, %d surface guis",
		parts,
		count(map, "ParticleEmitter"),
		count(map, "Beam"),
		count(map, "SurfaceGui")
	))
	print(string.format(
		"Terrain calls: %d FillBlock, %d FillBall, %d FillCylinder",
		terrainCalls.FillBlock,
		terrainCalls.FillBall,
		terrainCalls.FillCylinder
	))
	check(parts > 500 and parts < 2600, "server world part budget (500..2600), got " .. parts)
	check(terrainCalls.FillBlock > 10, "terrain was built")
	local slingshot = map:FindFirstChild("Slingshot")
	check(slingshot ~= nil, "map has the slingshot")
	if slingshot then
		for _, name in { "RestBand", "Pouch", "Trunk", "Core" } do
			check(slingshot:FindFirstChild(name) ~= nil, "slingshot has " .. name)
		end
		local trunk = slingshot:FindFirstChild("Trunk")
		check(trunk ~= nil and trunk:FindFirstChild("SlingLaunchPrompt") ~= nil, "launch prompt exists")
	end
	local lighting = game:GetService("Lighting")
	for _, className in { "Atmosphere", "BloomEffect", "ColorCorrectionEffect", "Sky" } do
		check(lighting:FindFirstChildOfClass(className) ~= nil, "lighting has " .. className)
	end

	-- Shadows only where they matter: flat ground pieces must not cast them.
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") and (d.Name == "Rail" or d.Name == "GridLine" or d.Name == "Lava") then
			check(not d.CastShadow, d.Name .. " shouldn't cast shadows")
		end
	end

	local Leaderboard = requireModule(server:FindFirstChild("Leaderboard"))
	check(type(Leaderboard.Init) == "function", "leaderboard module loads")
end)
check(ok, "server world builds: " .. tostring(err))

--------------------------------------------------------------------------------
-- Client visuals
--------------------------------------------------------------------------------

local players = game:GetService("Players")
local playerGui = Instance.new("Folder")
playerGui.Name = "PlayerGui"

ok, err = pcall(function()
	local Quality = requireModule(client:FindFirstChild("Quality"))
	Quality.Apply({ Performance = false })

	local Effects = requireModule(client:FindFirstChild("Effects"))
	Effects.Init(playerGui)
	Effects.Burst(roblox.Vector3.new(0, 5, -50), "Block:1:1", roblox.Color3.new(1, 0, 0), 6)
	for _, fx in { "Wood", "Stone", "Snow", "Glass", "Energy", "Metal", "Gold", "Explosive" } do
		for tier = 1, 4 do
			Effects.Impact(roblox.Vector3.new(0, 5, -60), fx, tier, roblox.Color3.new(0.5, 0.5, 0.5))
		end
	end
	Effects.Ring(roblox.CFrame.new(0, 2, -10), roblox.Color3.new(0, 1, 1), 2, 20, 0.5)
	Effects.Shockwave(roblox.Vector3.new(0, 2, -100), 26, roblox.Color3.new(1, 0.3, 0.3))
	Effects.Lightning(roblox.Vector3.new(0, 10, 0), roblox.Vector3.new(0, 10, -30), roblox.Color3.new(0.5, 1, 1))
	Effects.FloatText(roblox.Vector3.new(0, 5, -20), "+10", roblox.Color3.new(1, 1, 1), 1)
	Effects.Flash(roblox.Color3.new(1, 1, 1), 0.3)

	local Course = requireModule(client:FindFirstChild("Course"))
	local course = Course.new()
	course:Build()
	local folder = course.Folder
	print(string.format("Course visuals: %d blocks built, %d parts in view", #course.BlockList, count(folder, "BasePart")))
	print(string.format("Effects: %d particles emitted, %d sounds played", emitted, played))
	check(#course.BlockList > 1000, "course built its blocks")
	course:SetView(0)
	local inView = count(folder, "BasePart")
	check(inView < #course.BlockList, "only part of the course is drawn at once (" .. inView .. ")")
	course:SetView(1500)
	course:SetView(0)
	course:Update(0.016, nil, 1)
	course:Reset()

	-- Charge-up, launch and power-up auras.
	Effects.StartCharge(roblox.Vector3.new(0, 10, 5))
	for i = 0, 10 do
		Effects.UpdateCharge(roblox.Vector3.new(0, 10, 5), i / 10)
	end
	Effects.Overcharge(roblox.Vector3.new(0, 10, 5))
	Effects.StopCharge()
	Effects.Launch(roblox.Vector3.new(0, 10, 5), roblox.Vector3.new(0, 0.4, -1).Unit, 1)
	Effects.NitroBurst(roblox.Vector3.new(0, 10, -40), roblox.Vector3.new(0, 0, -1))
	local fakeCharacter = Instance.new("Model")
	for _, name in { "HumanoidRootPart", "Head", "UpperTorso", "LeftUpperArm", "RightUpperArm" } do
		local part = Instance.new("Part")
		part.Name = name
		part.Parent = fakeCharacter
	end
	local mesh = Instance.new("MeshPart")
	mesh.Name = "LowerTorso"
	mesh.Parent = fakeCharacter
	for _, kind in { "Meteor", "Rift", "Phase" } do
		Effects.StartAura(kind, fakeCharacter)
		for frame = 1, 12 do
			Effects.UpdateFlight(roblox.CFrame.new(0, 10, -frame * 3), roblox.Vector3.new(0, 0, -90), 1 / 60, frame % 2 == 0)
		end
		Effects.StopAura()
	end
	Effects.EndFlight()

	-- Biome lighting and weather across the whole lane.
	local Atmosphere = requireModule(client:FindFirstChild("Atmosphere"))
	for d = 0, 3200, 25 do
		Atmosphere.Update(d, roblox.CFrame.new(0, 10, -d))
	end

	-- Whole flights through the real event handlers, with a stand-in HUD.
	local uiCalls = {}
	local stubUI = setmetatable({}, {
		__index = function(_, name)
			return function()
				uiCalls[name] = (uiCalls[name] or 0) + 1
			end
		end,
	})
	loaded[client:FindFirstChild("UI")] = stubUI
	local FlightEvents = requireModule(client:FindFirstChild("FlightEvents"))
	local Config = requireModule(shared:FindFirstChild("Config"))
	local Physics = requireModule(shared:FindFirstChild("Physics"))
	local RunSim = requireModule(shared:FindFirstChild("RunSim"))
	local all = {}
	for _, node in Config.Nodes do
		all[node.Id] = true
	end
	local fired = {}
	local flightState = nil
	local currentRun = nil
	local handlers = FlightEvents.new({
		Course = course,
		GetRun = function()
			return currentRun
		end,
		GetFlight = function()
			return flightState
		end,
		GetCharacter = function()
			return fakeCharacter
		end,
		CameraEffectsOn = function()
			return true
		end,
	})
	local counting = setmetatable({}, {
		__index = function(_, name)
			local handler = handlers[name]
			check(handler ~= nil, "FlightEvents handles " .. name)
			return function(...)
				fired[name] = (fired[name] or 0) + 1
				if handler then
					handler(...)
				end
			end
		end,
	})
	local flights = 0
	for _, setup in { { {}, 1, 24 }, { all, 1, 30 }, { all, 1, 14 }, { all, 0.7, 40 }, { all, 1, 20 } } do
		course:Reset()
		local stats = Config.ComputeStats(setup[1], 0)
		flightState = { FovKick = 0, SlowMo = 0, HitStop = 0, LastHitStop = 0, LastBigPop = 0 }
		currentRun = RunSim.new(stats, Physics.PouchPosition(setup[2]), Physics.LaunchVelocity(stats, setup[2], setup[3], 0), { Rng = Random.new(5), Events = counting })
		local frames = 0
		while not currentRun.Done and frames < 60 * 120 do
			frames += 1
			if currentRun.Velocity.Y < -5 and currentRun.Position.Y < 8 then
				currentRun:Boost()
			end
			for _ = 1, 2 do
				currentRun:Step(1 / 120, math.sin(currentRun.Time * 1.3))
			end
			local pose = roblox.CFrame.new(currentRun.Position)
			Effects.UpdateFlight(pose, currentRun.Velocity, 1 / 60, currentRun.Thrust > 0)
			course:Update(1 / 60, currentRun.Position, currentRun.Time)
		end
		Effects.EndFlight()
		flights += 1
	end
	-- Handlers the flights above may not have reached.
	local layout = RunSim.Index().Layout
	currentRun = RunSim.new(Config.ComputeStats({}, 0), roblox.Vector3.new(0, 10, -100), roblox.Vector3.new(0, 0, -60), { Rng = Random.new(1) })
	counting.OnPhase(layout.Blocks[1])
	counting.OnShockwave(roblox.Vector3.new(0, 2, -200), 26, "shockwave")
	counting.OnShockwave(roblox.Vector3.new(0, 2, -220), 12, "slam")
	counting.OnLava(roblox.Vector3.new(0, 1, -1300))
	counting.OnPad(layout.Pads[1])
	counting.OnBarrier(layout.Barriers[1], true)
	counting.OnBarrier(layout.Barriers[1], false)
	counting.OnLog(layout.Logs[1], true)
	counting.OnLog(layout.Logs[1], false)
	counting.OnGeyser(layout.Geysers[1])
	counting.OnUpdraft(layout.Updrafts[1])
	counting.OnBounce(70)
	counting.OnRing(layout.Rings[#layout.Rings])
	counting.OnAbility("Phase")
	counting.OnAbilityEnd("Phase")
	course:Reset()

	local names = {}
	for name, n in fired do
		table.insert(names, name .. "=" .. n)
	end
	table.sort(names)
	print(string.format("Flights: %d through FlightEvents (%s)", flights, table.concat(names, " ")))
	check((fired.OnSmash or 0) > 100, "flights smashed blocks through the handlers")
	print(string.format("Effects: %d particles emitted, %d sounds played", emitted, played))
end)
check(ok, "client visuals build: " .. tostring(err))

print(if failures == 0 then "SMOKE OK" else failures .. " SMOKE CHECK(S) FAILED")
process.exit(if failures == 0 then 0 else 1)
