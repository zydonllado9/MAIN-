-- Minimal stand-ins for Roblox datatypes so shared modules run in plain Luau.
local V = {}
V.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	elseif key == "Unit" then
		local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		return Vector3.new(self.X / m, self.Y / m, self.Z / m)
	end
	return V[key]
end
local function vnew(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V)
end
V.__add = function(a, b) return vnew(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V.__sub = function(a, b) return vnew(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V.__mul = function(a, b)
	if type(a) == "number" then a, b = b, a end
	if type(b) == "number" then return vnew(a.X * b, a.Y * b, a.Z * b) end
	return vnew(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V.__div = function(a, b) return vnew(a.X / b, a.Y / b, a.Z / b) end
V.__unm = function(a) return vnew(-a.X, -a.Y, -a.Z) end
V.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V.__tostring = function(a) return string.format("(%.2f, %.2f, %.2f)", a.X, a.Y, a.Z) end
function V.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
function V.Lerp(a, b, t) return a + (b - a) * t end
Vector3 = { new = vnew, zero = vnew(0, 0, 0), yAxis = vnew(0, 1, 0), xAxis = vnew(1, 0, 0) }

local C = {}
C.__index = C
function C.Lerp(a, b, t)
	return setmetatable({ R = a.R + (b.R - a.R) * t, G = a.G + (b.G - a.G) * t, B = a.B + (b.B - a.B) * t }, C)
end
Color3 = {
	new = function(r, g, b) return setmetatable({ R = r, G = g, B = b }, C) end,
	fromRGB = function(r, g, b) return setmetatable({ R = r / 255, G = g / 255, B = b / 255 }, C) end,
}

-- Deterministic PRNG with Roblox's Random API shape.
local R = {}
R.__index = R
function R:NextNumber(a, b)
	self.s = (self.s * 1103515245 + 12345) % 2147483648
	local f = self.s / 2147483648
	if a == nil then return f end
	return a + (b - a) * f
end
function R:NextInteger(a, b) return math.floor(self:NextNumber(a, b + 1 - 1e-9)) end
Random = { new = function(seed) return setmetatable({ s = (seed or 1) % 2147483648 }, R) end }

local enumMeta = {}
enumMeta.__index = function(t, k)
	local child = setmetatable({ Name = k }, enumMeta)
	rawset(t, k, child)
	return child
end
Enum = setmetatable({}, enumMeta)
