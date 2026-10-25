--[[
	Sling Smash - client entry point.

	Game loop:  Lobby -> Aiming (in the slingshot) -> Charging (hold) -> Flying
	            -> Results -> Retry / Return

	The rules of a flight live in Shared/RunSim; this script steps it every
	frame and turns its events into visuals, sound and camera moves. The
	character is put in PlatformStand and its root part follows the simulation,
	which replicates to other players because each client owns its character.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Physics = require(Shared:WaitForChild("Physics"))
local RunSim = require(Shared:WaitForChild("RunSim"))

local Atmosphere = require(script.Atmosphere)
local Course = require(script.Course)
local Effects = require(script.Effects)
local FlightEvents = require(script.FlightEvents)
local Quality = require(script.Quality)
local UI = require(script.UI)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local GetDataRemote = remotes:WaitForChild("GetData") :: RemoteFunction
local DataChangedRemote = remotes:WaitForChild("DataChanged") :: RemoteEvent
local StartLaunchRemote = remotes:WaitForChild("StartLaunch") :: RemoteFunction
local FinishLaunchRemote = remotes:WaitForChild("FinishLaunch") :: RemoteFunction
local UpdateSettingRemote = remotes:WaitForChild("UpdateSetting") :: RemoteEvent

local HOLD_STEP = "SlingSmashHold"
local FLIGHT_STEP = "SlingSmashFlight"
local BAND_STEP = "SlingSmashBands"
local FINISH_STEP = "SlingSmashFinish"
local CHARGE_ACTION = "SlingSmashCharge"
local BOOST_ACTION = "SlingSmashBoost"
local SUBSTEP = 1 / 120
local F = Config.Flight

local rng = Random.new()

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local state = "Lobby" -- Lobby | Aiming | Charging | Flying | Results
local data = nil
local stats = Config.ComputeStats({}, 0)
local power = 0
local chargeStart = 0
local chargeInput: InputObject? = nil
local maxAnnounced = false
local aim = { Angle = F.LaunchAngle, Yaw = 0 }
local drag = nil -- { Start: Vector2, Angle, Yaw } while charging with a pointer
local run = nil -- RunSim for the current launch
local flight = nil -- client-side presentation state for the current launch

local character: Model? = nil
local humanoid: Humanoid? = nil
local root: BasePart? = nil
local savedGroups = {} -- [BasePart] = original CollisionGroup

local course = Course.new()
task.spawn(function()
	course:Build()
end)

local controls = nil
task.spawn(function()
	local playerScripts = player:WaitForChild("PlayerScripts")
	local module = playerScripts:WaitForChild("PlayerModule", 10)
	if module then
		local ok, playerModule = pcall(require, module)
		if ok and playerModule then
			controls = (playerModule :: any):GetControls()
		end
	end
end)

-- Render-step bindings, tracked so cleanup never unbinds something unbound.
local boundSteps = {}
local function bindStep(name: string, callback: (number) -> ())
	if boundSteps[name] then
		RunService:UnbindFromRenderStep(name)
	end
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, callback)
	boundSteps[name] = true
end
local function unbindStep(name: string)
	if boundSteps[name] then
		boundSteps[name] = nil
		RunService:UnbindFromRenderStep(name)
	end
end

local function camera(): Camera
	return Workspace.CurrentCamera :: Camera
end

local function cameraEffectsOn(): boolean
	return data == nil or data.Settings.CameraShake ~= false
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- Movement input as (x = right, z = back). Works with keyboard, sticks and touch.
local function moveInput(): Vector3
	if controls then
		local ok, move = pcall(function()
			return controls:GetMoveVector()
		end)
		if ok and typeof(move) == "Vector3" and move.Magnitude > 0.05 then
			return move
		end
	end
	local x, z = 0, 0
	if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
		x -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
		x += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
		z -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
		z += 1
	end
	return Vector3.new(x, 0, z)
end

-- -1 (left) .. 1 (right).
local function steerInput(): number
	return math.clamp(moveInput().X, -1, 1)
end

local function setFlyerMode(enabled: boolean)
	if enabled then
		if humanoid then
			humanoid.PlatformStand = true
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		end
		if character then
			for _, descendant in character:GetDescendants() do
				if descendant:IsA("BasePart") then
					if savedGroups[descendant] == nil then
						savedGroups[descendant] = descendant.CollisionGroup
					end
					descendant.CollisionGroup = "Flyer"
				end
			end
		end
	else
		for part, group in savedGroups do
			if part.Parent then
				part.CollisionGroup = group
			end
		end
		table.clear(savedGroups)
		if humanoid then
			humanoid.PlatformStand = false
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		end
	end
end

local function restoreCamera()
	local cam = camera()
	cam.CameraType = Enum.CameraType.Custom
	if humanoid then
		cam.CameraSubject = humanoid
	end
	cam.FieldOfView = 70
end

-- The player list covers the distance counter, so hide it while flying.
local function setPlayerListVisible(visible: boolean)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, visible)
	end)
end

-- "Press E to launch" prompts only make sense while standing around.
local function setPromptsEnabled(enabled: boolean)
	ProximityPromptService.Enabled = enabled
end

local function aimFlat(): Vector3
	return Physics.AimDirection(0, aim.Yaw)
end

local function pouchCFrame(amount: number): CFrame
	local position = Physics.PouchPosition(amount)
	return CFrame.lookAt(position, position + aimFlat())
end

--------------------------------------------------------------------------------
-- Slingshot bands: stretch, heat up and vibrate with tension; snap back after
--------------------------------------------------------------------------------

local bands: { BasePart } = {}
local hiddenSlingParts: { BasePart } = {}
local recoil = nil -- { Start, From }
local BAND_REST = Config.SlingshotPosition + Vector3.new(0, Config.SlingshotArmTip - 0.6, 0.3)

local function makeBand(): BasePart
	local band = Instance.new("Part")
	band.Name = "SlingBand"
	band.Anchored = true
	band.CanCollide = false
	band.CanQuery = false
	band.CanTouch = false
	band.CastShadow = false
	band.Material = Enum.Material.SmoothPlastic
	band.Color = Color3.fromRGB(255, 120, 60)
	band.Size = Vector3.new(0.45, 0.45, 1)
	band.Transparency = 1
	band.Parent = course.Folder
	return band
end

local function setBandsVisible(visible: boolean)
	if #bands == 0 then
		bands = { makeBand(), makeBand() }
	end
	for _, band in bands do
		band.Transparency = if visible then 0 else 1
	end
	-- Hide the server's resting band locally while our stretched bands show.
	local map = Workspace:FindFirstChild("Map")
	local slingshot = map and map:FindFirstChild("Slingshot")
	if slingshot and #hiddenSlingParts == 0 then
		for _, name in { "RestBand", "Pouch" } do
			local partInstance = slingshot:FindFirstChild(name)
			if partInstance and partInstance:IsA("BasePart") then
				table.insert(hiddenSlingParts, partInstance)
			end
		end
	end
	for _, slingPart in hiddenSlingParts do
		slingPart.Transparency = if visible then 1 else 0
	end
end

local BAND_COLD = Color3.fromRGB(255, 120, 60)
local BAND_TENSE = Color3.fromRGB(255, 40, 40)
local BAND_HOT = Color3.fromRGB(255, 240, 200)

local function updateBands(pouch: Vector3, tension: number)
	local base = Config.SlingshotPosition
	local tipY = Config.SlingshotArmTip - 0.6
	-- Shiver at high tension.
	if tension > 0.6 then
		local amount = (tension - 0.6) / 0.4 * 0.09
		pouch += Vector3.new(rng:NextNumber(-amount, amount), rng:NextNumber(-amount, amount), 0)
	end
	local color = if tension < 0.7
		then BAND_COLD:Lerp(BAND_TENSE, tension / 0.7)
		else BAND_TENSE:Lerp(BAND_HOT, (tension - 0.7) / 0.3)
	local width = 0.45 - 0.22 * math.clamp(tension, 0, 1)
	for i, side in { -1, 1 } do
		local band = bands[i]
		if band then
			local tip = base + Vector3.new(side * Config.SlingshotArmSpread, tipY, 0)
			local length = (pouch - tip).Magnitude
			band.Size = Vector3.new(width, width, math.max(0.1, length))
			band.CFrame = CFrame.lookAt((tip + pouch) / 2, pouch)
			band.Color = color
		end
	end
end

-- After release the bands snap forward, overshoot and settle.
local function bandRecoilStep(_dt: number)
	local r = recoil
	if not r then
		unbindStep(BAND_STEP)
		return
	end
	local t = os.clock() - r.Start
	if t > 0.6 then
		recoil = nil
		unbindStep(BAND_STEP)
		setBandsVisible(false)
		return
	end
	local offset = (r.From - BAND_REST) * math.exp(-7 * t) * math.cos(t * 26)
	updateBands(BAND_REST + offset, 0)
end

local function startBandRecoil(from: Vector3)
	recoil = { Start = os.clock(), From = from }
	bindStep(BAND_STEP, bandRecoilStep)
end

--------------------------------------------------------------------------------
-- Trajectory preview: marching dots along the predicted arc
--------------------------------------------------------------------------------

local DOTS = 26
local aimFolder = Instance.new("Folder")
aimFolder.Name = "SlingAim"
aimFolder.Parent = Workspace
local dots: { BasePart } = {}
local landing: BasePart? = nil
local predicted: { Vector3 } = {}
local predictedKey = ""
local landingVisible = false

local function aimPart(props): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = aimFolder
	return p
end

local function setTrajectoryVisible(visible: boolean)
	if #dots == 0 then
		for i = 1, DOTS do
			local size = 0.75 - 0.45 * (i - 1) / (DOTS - 1)
			table.insert(dots, aimPart({ Name = "AimDot", Shape = Enum.PartType.Ball, Size = Vector3.new(size, size, size), Transparency = 1 }))
		end
		landing = aimPart({
			Name = "AimLanding",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.2, 6, 6),
			Transparency = 1,
		})
	end
	if not visible then
		for _, dot in dots do
			dot.Transparency = 1
		end
		if landing then
			landing.Transparency = 1
		end
	end
end

local function updateTrajectory(launchPower: number)
	local key = string.format("%.3f:%.1f:%.1f", launchPower, aim.Angle, aim.Yaw)
	if key ~= predictedKey then
		predictedKey = key
		local velocity = Physics.LaunchVelocity(stats, launchPower, aim.Angle, aim.Yaw)
		local points, land, landed = Physics.Predict(stats, Physics.PouchPosition(launchPower), velocity, 10, 1 / 30)
		predicted = points
		landingVisible = landed
		if landing then
			landing.CFrame = CFrame.new(Vector3.new(land.X, Config.GroundY + 0.12, land.Z)) * CFrame.Angles(0, 0, math.pi / 2)
		end
	end
	-- Dots march outward along the arc.
	local count = #predicted
	local phase = (os.clock() * 2.5) % 1
	local hot = Color3.fromRGB(255, 255, 255):Lerp(Color3.fromRGB(255, 220, 90), launchPower)
	for i, dot in dots do
		local index = math.floor((i - 1 + phase) * 1.5) + 1
		local point = predicted[index]
		if point and index <= count then
			dot.CFrame = CFrame.new(point)
			dot.Color = hot
			dot.Transparency = 0.15 + 0.6 * (i / DOTS)
		else
			dot.Transparency = 1
		end
	end
	if landing then
		landing.Color = hot
		landing.Transparency = if landingVisible then 0.45 + 0.2 * math.sin(os.clock() * 6) else 1
	end
end

--------------------------------------------------------------------------------
-- Aiming + charging
--------------------------------------------------------------------------------

local enterAiming, startFlight, returnToLobby, boost

local function updateAim(dt: number)
	local move = moveInput()
	aim.Angle = math.clamp(aim.Angle - move.Z * F.AimRate * dt, F.MinAngle, F.MaxAngle)
	aim.Yaw = math.clamp(aim.Yaw + move.X * F.AimRate * 0.6 * dt, -F.MaxYaw, F.MaxYaw)
end

local function aimCamera(amount: number, dt: number)
	local pouch = Physics.PouchPosition(amount)
	local flat = aimFlat()
	local position = pouch - flat * (14 + amount * 3) + Vector3.new(0, 5 + amount + (aim.Angle - F.LaunchAngle) * 0.08, 0)
	local target = pouch + Physics.AimDirection(aim.Angle * 0.45, aim.Yaw) * 40 + Vector3.new(0, 2, 0)
	local cam = camera()
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = CFrame.lookAt(position, target) * Effects.ShakeOffset(dt)
	cam.FieldOfView = 70 + amount * (if cameraEffectsOn() then 6 else 3)
end

local function holdStep(dt: number)
	if state == "Charging" then
		power = math.min(1, (os.clock() - chargeStart) / F.ChargeTime)
		if power >= 1 and not maxAnnounced then
			maxAnnounced = true
			UI.Pop("MAX POWER!", "max")
			Effects.Overcharge(Physics.PouchPosition(1))
		end
		if power > 0.6 then
			Effects.Shake(0.08 * power)
		end
	end
	if not drag then
		updateAim(dt)
	end
	local cf = pouchCFrame(power)
	if root then
		root.CFrame = cf
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	updateBands(cf.Position + aimFlat() * 1.2, if state == "Charging" then power else 0)
	aimCamera(power, dt)
	updateTrajectory(if state == "Charging" then power else 1)
	if state == "Charging" then
		Effects.UpdateCharge(cf.Position, power)
	end
	UI.SetPower(power, if state == "Charging" then "charging" else "aim", aim.Angle, aim.Yaw)
end

local function unbindAiming()
	unbindStep(HOLD_STEP)
	ContextActionService:UnbindAction(CHARGE_ACTION)
	Effects.StopCharge()
	setTrajectoryVisible(false)
	drag = nil
end

local function isPointerInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function startCharging(input: InputObject?)
	if state ~= "Aiming" then
		return
	end
	state = "Charging"
	chargeStart = os.clock()
	chargeInput = input
	maxAnnounced = false
	if input and isPointerInput(input) then
		drag = { Start = Vector2.new(input.Position.X, input.Position.Y), Angle = aim.Angle, Yaw = aim.Yaw }
	end
	Effects.StartCharge(Physics.PouchPosition(0))
	Effects.Play("Click", 0.7)
end

local function releaseCharge()
	if state ~= "Charging" then
		return
	end
	local launchPower = power
	local pouch = pouchCFrame(launchPower).Position + aimFlat() * 1.2
	unbindAiming()
	startBandRecoil(pouch)
	startFlight(launchPower)
end

local function chargeAction(_actionName: string, inputState: Enum.UserInputState, input: InputObject)
	if inputState == Enum.UserInputState.Begin then
		startCharging(input)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		if chargeInput and chargeInput.KeyCode == input.KeyCode then
			releaseCharge()
		end
	end
	return Enum.ContextActionResult.Sink
end

enterAiming = function()
	if state == "Aiming" or state == "Charging" or state == "Flying" then
		return
	end
	if not (root and humanoid and humanoid.Health > 0) then
		return
	end
	if not course.Ready then
		UI.Toast("The course is still loading...")
		return
	end

	UI.ClosePanels()
	UI.HideResults()
	unbindStep(FINISH_STEP)
	course:Reset()
	course:SetView(0)
	setFlyerMode(true)

	state = "Aiming"
	power = 0
	chargeInput = nil
	drag = nil
	predictedKey = ""
	setPromptsEnabled(false)
	recoil = nil
	unbindStep(BAND_STEP)
	setBandsVisible(true)
	setTrajectoryVisible(true)
	bindStep(HOLD_STEP, holdStep)
	ContextActionService:BindActionAtPriority(
		CHARGE_ACTION,
		chargeAction,
		false,
		Enum.ContextActionPriority.High.Value + 10,
		Enum.KeyCode.Space,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.ButtonR2
	)

	UI.SetMode("Aiming")
	UI.SetPower(0, "aim", aim.Angle, aim.Yaw)
	UI.SetRunCoins(0, true)
	Effects.Play("Click", 1)
end

local function cancelAim()
	if state ~= "Aiming" and state ~= "Charging" then
		return
	end
	unbindAiming()
	setBandsVisible(false)
	returnToLobby()
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not isPointerInput(input) then
		return
	end
	if state == "Aiming" then
		startCharging(input)
	elseif state == "Flying" and input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- Mouse clicks boost; phones use the NITRO button so stray taps don't waste charges.
		boost()
	end
end)

-- Dragging while charging aims like pulling a real slingshot: drag down to
-- aim higher, drag left to aim right.
UserInputService.InputChanged:Connect(function(input)
	local d = drag
	if state ~= "Charging" or not d or not chargeInput then
		return
	end
	local matches = input == chargeInput
		or (chargeInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)
	if not matches then
		return
	end
	local viewport = camera().ViewportSize
	local delta = Vector2.new(input.Position.X, input.Position.Y) - d.Start
	aim.Angle = math.clamp(d.Angle + delta.Y / math.max(1, viewport.Y) * 70, F.MinAngle, F.MaxAngle)
	aim.Yaw = math.clamp(d.Yaw - delta.X / math.max(1, viewport.X) * 40, -F.MaxYaw, F.MaxYaw)
end)

UserInputService.InputEnded:Connect(function(input)
	if state ~= "Charging" or not chargeInput or not isPointerInput(input) then
		return
	end
	-- Touches must match the finger that started the charge; mouse just needs the button.
	if input == chargeInput or input.UserInputType == Enum.UserInputType.MouseButton1 then
		if chargeInput.UserInputType == input.UserInputType then
			releaseCharge()
		end
	end
end)

--------------------------------------------------------------------------------
-- Flight events: RunSim decides, this makes it look and sound right
--------------------------------------------------------------------------------

local finishFlight

local events = FlightEvents.new({
	Course = course,
	GetRun = function()
		return run
	end,
	GetFlight = function()
		return flight
	end,
	GetCharacter = function()
		return character
	end,
	CameraEffectsOn = cameraEffectsOn,
})

--------------------------------------------------------------------------------
-- Flight loop
--------------------------------------------------------------------------------

local function flightCamera(dt: number, speed: number, steer: number)
	local f = flight
	local r = run
	local camFx = cameraEffectsOn()
	local velocity = r.Velocity
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local lookAhead = if flat.Magnitude > 1 then flat.Unit else Config.Forward
	local back = -Config.Forward
	local desired = r.Position
		+ Vector3.new(0, 7 + math.min(speed, 200) * 0.02, 0)
		+ back * (20 + math.min(speed, 220) * 0.03)
		- Vector3.new(velocity.X * 0.06, 0, 0)
	-- A little lag sells momentum without losing the flyer.
	f.CameraPosition = f.CameraPosition:Lerp(desired, 1 - math.exp(-10 * dt))
	local look = r.Position + Config.Forward * 14 + lookAhead * math.min(speed, 160) * 0.05 + Vector3.new(0, 1.5, 0)
	local targetRoll = if camFx then -steer * 0.05 else 0
	f.Roll += (targetRoll - f.Roll) * math.min(1, dt * 5)

	local cam = camera()
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = CFrame.lookAt(f.CameraPosition, look) * CFrame.Angles(0, 0, f.Roll) * Effects.ShakeOffset(dt)
	f.FovKick = math.max(0, f.FovKick - dt * 25)
	local fovScale = if camFx then 1 else 0.4
	cam.FieldOfView = 70 + (math.clamp(speed * 0.1, 0, 22) + f.FovKick) * fovScale
end

local function flightStep(dt: number)
	local f = flight
	local r = run
	if not f or not r then
		return
	end
	dt = math.min(dt, 0.1)

	-- Hit-stop freezes the world for a heartbeat; slow motion stretches it.
	local simDt = dt
	if f.HitStop > 0 then
		f.HitStop -= dt
		simDt = 0
	elseif f.SlowMo > 0 then
		f.SlowMo -= dt
		simDt = dt * Config.SlowMo.TimeScale
	end
	local steer = steerInput()
	if simDt > 0 then
		local steps = math.max(1, math.ceil(simDt / SUBSTEP))
		local h = simDt / steps
		for _ = 1, steps do
			r:Step(h, steer)
			if r.Done then
				break
			end
		end
	end

	local velocity = r.Velocity
	local speed = velocity.Magnitude

	-- Pose: superman-style, head first, rolling into turns.
	local direction = velocity + Config.Forward * 2
	if direction.Magnitude < 1e-3 then
		direction = Config.Forward
	end
	direction = direction.Unit
	local wobble = if r.Grounded then 0 else math.sin(r.Time * 7) * 0.12
	local pose = CFrame.lookAt(r.Position, r.Position + direction)
		* CFrame.Angles(-math.pi / 2, 0, 0)
		* CFrame.Angles(0, -steer * 0.5 + wobble, 0)
	if root then
		root.CFrame = pose
		root.AssemblyLinearVelocity = velocity
		root.AssemblyAngularVelocity = Vector3.zero
	end

	flightCamera(dt, speed, steer)

	-- HUD + effects.
	local distance = r:Distance()
	UI.SetDistance(math.floor(distance))
	UI.SetRunCoins(r.RunCoins)
	local multiplier = Config.ComboMultiplier(r.Combo, stats.MaxComboMult)
	UI.SetCombo(multiplier, r.ComboTimer / stats.ComboWindow, multiplier >= 2 and r.ComboTimer > 0)
	if r.Ability then
		UI.SetAbility(r.Ability.Kind, r.Ability.TimeLeft / r.Ability.Duration)
	end
	local thrusting = r.Thrust > 0
	Effects.UpdateFlight(pose, velocity, dt, thrusting)
	Effects.UpdateSpeedLines(dt, math.clamp((speed - 50) / 120, 0, 1) + (if thrusting then 0.5 else 0))
	Effects.SetWind(speed / 150)
	course:Update(dt, r.Position, r.Time)
	Atmosphere.Update(distance, camera().CFrame)

	if r.Done then
		finishFlight(r.Done)
	end
end

startFlight = function(launchPower: number)
	local start = Physics.PouchPosition(launchPower)
	local velocity = Physics.LaunchVelocity(stats, launchPower, aim.Angle, aim.Yaw)
	run = RunSim.new(stats, start, velocity, { Rng = Random.new(), Events = events })
	local f = {
		CameraPosition = camera().CFrame.Position,
		FovKick = 6 + launchPower * 6,
		SlowMo = 0,
		HitStop = 0,
		LastHitStop = 0,
		LastBigPop = 0,
		Roll = 0,
		LaunchId = nil,
		IdReady = false,
		BonkTipShown = false,
	}
	flight = f
	state = "Flying"

	task.spawn(function()
		local ok, launchId = pcall(function()
			return StartLaunchRemote:InvokeServer()
		end)
		if ok then
			f.LaunchId = launchId
		end
		f.IdReady = true
	end)

	UI.SetMode("Flying")
	UI.SetBoosts(run.Boosts)
	UI.SetAbility(nil)
	setPlayerListVisible(false)
	ContextActionService:BindActionAtPriority(
		BOOST_ACTION,
		function(_actionName, inputState)
			if inputState == Enum.UserInputState.Begin then
				boost()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value + 10,
		Enum.KeyCode.Space,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.ButtonR2
	)
	UI.Pop(if launchPower >= 0.99 then "PERFECT!" else "LAUNCH!", "max")
	Effects.Launch(start, velocity.Unit, launchPower)
	Effects.Play("Launch", 0.85 + launchPower * 0.25, 0.8 + launchPower * 0.4, true)
	bindStep(FLIGHT_STEP, flightStep)
end

-- Mid-air Nitro; limited charges per launch (Rocket Fuel adds more).
boost = function()
	if run then
		run:Boost()
	end
end

-- A short orbit around the flyer when they reach the finish line.
local function finishCinematic(position: Vector3)
	local start = os.clock()
	local cam = camera()
	cam.CameraType = Enum.CameraType.Scriptable
	bindStep(FINISH_STEP, function(_dt)
		local t = os.clock() - start
		if t > 2.4 or state ~= "Results" then
			unbindStep(FINISH_STEP)
			if state == "Results" then
				restoreCamera()
			end
			return
		end
		local angle = t * 1.1
		local offset = Vector3.new(math.sin(angle) * 22, 9 + t * 2, math.cos(angle) * 22)
		cam.CFrame = CFrame.lookAt(position + offset, position + Vector3.new(0, 3, 0))
		cam.FieldOfView = 60
	end)
end

local function cleanupFlightVisuals()
	Effects.EndFlight()
	Effects.SetWind(0)
	Effects.HideSpeedLines()
	UI.SetAbility(nil)
end

finishFlight = function(reason: string)
	local f = flight
	local r = run
	if not f or not r then
		return
	end
	flight = nil
	run = nil
	unbindStep(FLIGHT_STEP)
	ContextActionService:UnbindAction(BOOST_ACTION)
	setPlayerListVisible(true)
	setPromptsEnabled(true)
	cleanupFlightVisuals()
	state = "Results"

	-- Stand back up where we landed.
	if root and humanoid then
		local p = Vector3.new(r.Position.X, Config.GroundY + 3.2, r.Position.Z)
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = CFrame.lookAt(p, p + Config.Forward)
		setFlyerMode(false)
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	UI.SetMode("Results")
	UI.SetCombo(1, 0, false)
	if reason == "finish" then
		UI.Pop("🏆 FINISH!", "best")
		Effects.Play("Victory", 1, 1, true)
		Effects.Flash(Color3.fromRGB(255, 230, 120), 0.4)
		finishCinematic(r.Position)
	else
		restoreCamera()
	end

	local report = r:Report()
	local distance = report.Distance
	local comboMultiplier = Config.ComboMultiplier(r.MaxCombo, stats.MaxComboMult)
	task.spawn(function()
		local waited = 0
		while not f.IdReady and waited < 5 do
			waited += task.wait(0.1)
		end
		local ok, result = pcall(function()
			return FinishLaunchRemote:InvokeServer(f.LaunchId, report)
		end)
		if not ok or type(result) ~= "table" then
			result = {
				Earned = 0,
				Distance = math.floor(distance),
				Smashes = report.Smashes,
				MaxCombo = report.MaxCombo,
				NewBest = false,
				Failed = true,
			}
		end
		if state ~= "Results" then
			return
		end
		if result.NewBest then
			UI.Pop("NEW BEST!", "best")
			Effects.Flash(Color3.fromRGB(255, 200, 255), 0.3)
		end
		local discoveries = result.Discoveries
		if type(discoveries) == "table" and #discoveries > 0 then
			UI.Banner("📖 NEW DISCOVERY: " .. discoveries[1].Icon .. " " .. string.upper(discoveries[1].Name))
		end
		Effects.Play("Coin", 1)
		UI.ShowResults(result, comboMultiplier)
	end)
end

local function resetToLobbyState()
	flight = nil
	run = nil
	unbindStep(FLIGHT_STEP)
	unbindStep(FINISH_STEP)
	unbindAiming()
	recoil = nil
	unbindStep(BAND_STEP)
	setBandsVisible(false)
	ContextActionService:UnbindAction(BOOST_ACTION)
	setPlayerListVisible(true)
	setPromptsEnabled(true)
	cleanupFlightVisuals()
end

returnToLobby = function()
	resetToLobbyState()
	state = "Lobby"
	setFlyerMode(false)
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = CFrame.lookAt(Config.ReturnPoint, Config.ReturnPoint + Config.Forward)
	end
	restoreCamera()
	UI.SetMode("Lobby")
end

--------------------------------------------------------------------------------
-- Character lifecycle
--------------------------------------------------------------------------------

local function onCharacterAdded(newCharacter: Model)
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid", 10) :: Humanoid?
	root = newCharacter:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	resetToLobbyState()
	table.clear(savedGroups)
	state = "Lobby"
	UI.SetMode("Lobby")
	restoreCamera()
	if humanoid then
		humanoid.Died:Connect(function()
			if character == newCharacter then
				resetToLobbyState()
				table.clear(savedGroups)
				state = "Lobby"
				UI.SetMode("Lobby")
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- Data + UI wiring
--------------------------------------------------------------------------------

local function applyData(newData)
	if type(newData) ~= "table" then
		return
	end
	data = newData
	stats = Config.ComputeStats(newData.Upgrades, newData.Rebirths)
	predictedKey = "" -- upgrades change the arc
	Quality.Apply(newData.Settings)
	UI.SetData(newData)
	Effects.ApplySettings(newData.Settings)
end

local function invoke(remoteName: string, ...): (boolean, any)
	local args = table.pack(...)
	local remote = remotes:FindFirstChild(remoteName)
	if not remote or not remote:IsA("RemoteFunction") then
		return false, "Missing remote " .. remoteName
	end
	local ok, success, message = pcall(function()
		return remote:InvokeServer(table.unpack(args, 1, args.n))
	end)
	if not ok then
		return false, "Server didn't respond"
	end
	return success == true, message
end

Quality.Apply(nil)
Effects.Init(playerGui)
UI.Init(playerGui, {
	Launch = function()
		enterAiming()
	end,
	Cancel = function()
		cancelAim()
	end,
	Retry = function()
		enterAiming()
	end,
	Return = function()
		returnToLobby()
	end,
	Click = function()
		Effects.Play("Click", 1)
	end,
	BuyUpgrade = function(nodeId: string)
		local node = Config.NodesById[nodeId]
		if not node or not data then
			return
		end
		if data.Upgrades[nodeId] then
			return
		end
		if node.Requires ~= "Start" and not data.Upgrades[node.Requires] then
			UI.Toast("🔒 Unlock " .. Config.NodesById[node.Requires].Name .. " first")
			return
		end
		if data.Coins < node.Cost then
			UI.Toast("Not enough ⭐! Launch to earn more.", Color3.fromRGB(255, 120, 120))
			return
		end
		local ok, message = invoke("BuyUpgrade", nodeId)
		if ok then
			Effects.Play("Coin", 1.4)
			UI.Toast("✅ " .. node.Name .. " unlocked!", Color3.fromRGB(140, 255, 100))
		else
			UI.Toast(message or "Couldn't buy that", Color3.fromRGB(255, 120, 120))
		end
	end,
	Rebirth = function()
		local ok, message = invoke("Rebirth")
		if ok then
			UI.ClosePanels()
			UI.Pop("REBIRTH!", "best")
			Effects.Flash(Color3.fromRGB(200, 140, 255), 0.5)
		else
			UI.Toast(message or "Can't rebirth yet", Color3.fromRGB(255, 120, 120))
		end
	end,
	BuyTrail = function(trailId: string)
		local ok, message = invoke("BuyTrail", trailId)
		if ok then
			Effects.Play("Coin", 1.4)
			UI.Toast("✨ New trail equipped!", Color3.fromRGB(140, 255, 100))
		else
			UI.Toast(message or "Couldn't buy that", Color3.fromRGB(255, 120, 120))
		end
	end,
	EquipTrail = function(trailId: string)
		local ok, message = invoke("EquipTrail", trailId)
		if not ok then
			UI.Toast(message or "Couldn't equip that", Color3.fromRGB(255, 120, 120))
		end
	end,
	Boost = function()
		boost()
	end,
	ClaimDaily = function()
		local ok, result = invoke("ClaimDaily")
		if ok then
			UI.Pop("🎁 DAILY REWARD!", "best")
			UI.Toast("🎁 +" .. Format.Commas(tonumber(result) or 0) .. " coins!", Color3.fromRGB(140, 255, 100))
			Effects.Play("Coin", 1.3)
			Effects.Flash(Color3.fromRGB(255, 225, 90), 0.3)
		else
			UI.Toast(tostring(result or "Can't claim yet"), Color3.fromRGB(255, 120, 120))
		end
	end,
	RedeemCode = function(text: string)
		local ok, result = invoke("RedeemCode", text)
		if ok then
			UI.CodeResult(true, "✅ +" .. Format.Commas(tonumber(result) or 0) .. " coins!")
			Effects.Play("Coin", 1.3)
		else
			UI.CodeResult(false, tostring(result or "Couldn't redeem that"))
		end
	end,
	Setting = function(key: string, value: boolean)
		if not data then
			return
		end
		data.Settings[key] = value
		Quality.Apply(data.Settings)
		Effects.ApplySettings(data.Settings)
		UI.SetData(data)
		UpdateSettingRemote:FireServer(key, value)
	end,
})

-- Walking up to the slingshot and pressing E also works.
ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who == player and prompt.Name == "SlingLaunchPrompt" then
		enterAiming()
	end
end)

-- Holding the power panel itself also charges (handy on phones).
UI.PowerButton().InputBegan:Connect(function(input)
	if state == "Aiming" and isPointerInput(input) then
		startCharging(input)
	end
end)

DataChangedRemote.OnClientEvent:Connect(applyData)
task.spawn(function()
	for _ = 1, 5 do
		local ok, result = pcall(function()
			return GetDataRemote:InvokeServer()
		end)
		if ok and type(result) == "table" then
			applyData(result)
			return
		end
		task.wait(2)
	end
end)

-- While not flying: keep the course, hazards and biome atmosphere around the player.
RunService.Heartbeat:Connect(function(dt)
	if flight then
		return
	end
	local focus = if root then root.Position else Config.LobbySpawn
	course:Update(dt, focus, os.clock())
	Atmosphere.Update(math.max(0, -focus.Z), camera().CFrame)
end)

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end
