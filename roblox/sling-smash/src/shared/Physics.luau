--[[
	Pure flight physics: no Instances, no effects. The client flies with it,
	the aim preview predicts the arc with it, and the tests run it in plain Luau.

	A body is a table with Position, Velocity, Grounded and Thrust (seconds of
	Nitro thrust left). Step() moves it by one small fixed time step.
]]

local Config = require(script.Parent.Config)

local Physics = {}

export type Body = {
	Position: Vector3,
	Velocity: Vector3,
	Grounded: boolean,
	Thrust: number,
	[string]: any,
}

-- Per-step modifiers from abilities, hazards and the biome's ground.
export type Env = {
	GravityMult: number?,
	ExtraAccel: Vector3?,
	DecelMult: number?,
	DragMult: number?,
}

-- Where the flyer sits in the pouch at a given pull (0..1).
function Physics.PouchPosition(amount: number): Vector3
	local back = Config.PouchRestOffset + Config.PouchPullDistance * amount
	return Config.SlingshotPosition + Vector3.new(0, Config.PouchHeight - amount * 1.2, back)
end

-- Launch direction for an aim (degrees above the horizon, degrees right of the lane).
function Physics.AimDirection(angle: number, yaw: number): Vector3
	local a, y = math.rad(angle), math.rad(yaw)
	local flat = Config.Forward * math.cos(y) + Config.Right * math.sin(y)
	return flat * math.cos(a) + Vector3.yAxis * math.sin(a)
end

function Physics.LaunchSpeed(stats, power: number): number
	local F = Config.Flight
	return stats.LaunchSpeed * (F.MinPower + (1 - F.MinPower) * math.clamp(power, 0, 1))
end

function Physics.LaunchVelocity(stats, power: number, angle: number, yaw: number): Vector3
	return Physics.AimDirection(angle, yaw) * Physics.LaunchSpeed(stats, power)
end

function Physics.NewBody(position: Vector3, velocity: Vector3): Body
	return { Position = position, Velocity = velocity, Grounded = false, Thrust = 0 }
end

-- Moves the body by h seconds. Returns the downward speed if it touched the
-- ground this step (positive number), otherwise nil. `bounced` tells whether
-- it bounced (true) or settled into a slide (false).
function Physics.Step(body: Body, h: number, steer: number, stats, env: Env?): (number?, boolean)
	local F = Config.Flight
	local previous = body.Position
	local velocity = body.Velocity
	local gravityMult = if env and env.GravityMult then env.GravityMult else 1

	-- Steering (sideways only).
	local vx = velocity.X + steer * stats.Steer * h
	if steer == 0 then
		vx -= vx * math.min(1, F.SideDamping * h)
	end
	vx = math.clamp(vx, -F.MaxSideSpeed, F.MaxSideSpeed)
	velocity = Vector3.new(vx, velocity.Y, velocity.Z)

	-- Nitro thrust pushes along the lane.
	if body.Thrust > 0 then
		local dt = math.min(h, body.Thrust)
		body.Thrust -= h
		velocity += Config.Forward * (Config.Boost.Thrust * dt)
	end

	if env and env.ExtraAccel then
		velocity += env.ExtraAccel * h
		if env.ExtraAccel.Y > 0 then
			body.Grounded = false
		end
	end

	if body.Grounded then
		local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
		local speed = horizontal.Magnitude
		if speed > 1e-3 then
			local decel = F.GroundDecel * (if env and env.DecelMult then env.DecelMult else 1)
			local drag = F.GroundDrag * (if env and env.DragMult then env.DragMult else 1)
			local newSpeed = math.max(0, speed - decel * h) * (1 - math.min(1, drag * h))
			horizontal *= newSpeed / speed
		end
		velocity = Vector3.new(horizontal.X, math.max(0, velocity.Y), horizontal.Z)
		if velocity.Y > 0 then
			body.Grounded = false
		end
	else
		velocity *= 1 - math.min(1, F.AirDrag * h)
		velocity -= Vector3.new(0, stats.Gravity * gravityMult * h, 0)
	end

	local position = previous + velocity * h

	-- Bounce off the lane rails.
	local limit = Config.LaneWidth / 2 - 1.5
	if math.abs(position.X) > limit then
		position = Vector3.new(math.sign(position.X) * limit, position.Y, position.Z)
		velocity = Vector3.new(-velocity.X * 0.4, velocity.Y, velocity.Z)
	end

	-- Ground: bounce when falling fast, otherwise start sliding.
	local contact: number? = nil
	local bounced = false
	local floor = Config.GroundY + F.BodyHeight
	if position.Y <= floor then
		position = Vector3.new(position.X, floor, position.Z)
		if velocity.Y < 0 then
			contact = -velocity.Y
		end
		if velocity.Y < -F.MinBounceSpeed then
			velocity = Vector3.new(velocity.X * F.BounceKeep, -velocity.Y * F.Bounce, velocity.Z * F.BounceKeep)
			bounced = true
		elseif velocity.Y <= 0 then
			velocity = Vector3.new(velocity.X, 0, velocity.Z)
			body.Grounded = true
		end
	end

	body.Position = position
	body.Velocity = velocity
	return contact, bounced
end

-- Predicts the arc of a launch until it first touches the ground (or maxTime).
-- Returns points spaced `spacing` seconds apart, the last position, and
-- whether that position is a real landing (false if maxTime ran out first).
function Physics.Predict(stats, start: Vector3, velocity: Vector3, maxTime: number, spacing: number): ({ Vector3 }, Vector3, boolean)
	local body = Physics.NewBody(start, velocity)
	local h = 1 / 120
	local points = { start }
	local t, nextSample = 0, spacing
	local landed = false
	while t < maxTime do
		local contact = Physics.Step(body, h, 0, stats, nil)
		t += h
		if contact then
			landed = true
			break
		end
		if t >= nextSample then
			table.insert(points, body.Position)
			nextSample += spacing
		end
	end
	return points, body.Position, landed
end

return Physics
