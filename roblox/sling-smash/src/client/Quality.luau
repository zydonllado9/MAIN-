--[[
	Picks an effects budget (Config.Quality.High / Medium / Low) for this
	device. Performance Mode in Settings always means Low; otherwise phones and
	low graphics settings get a lighter budget automatically.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local Quality = {}

Quality.Current = Config.Quality.High
local listeners: { (any) -> () } = {}

-- The player's Roblox graphics level (1-10), or nil when it's "Automatic".
local function graphicsLevel(): number?
	local ok, level = pcall(function()
		local setting = (UserSettings() :: any).GameSettings.SavedQualityLevel
		return tonumber(string.match(setting.Name, "%d+"))
	end)
	return if ok then level else nil
end

function Quality.Detect(): string
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local level = graphicsLevel()
	if level and level <= 3 then
		return "Low"
	elseif touchOnly or (level and level <= 6) then
		return "Medium"
	end
	return "High"
end

-- Re-picks the budget from the player's settings; tells listeners if it changed.
function Quality.Apply(settings)
	local name = if settings and settings.Performance then "Low" else Quality.Detect()
	local profile = Config.Quality[name] or Config.Quality.High
	if profile ~= Quality.Current then
		Quality.Current = profile
		for _, listener in listeners do
			task.spawn(listener, profile)
		end
	end
end

function Quality.OnChanged(listener: (any) -> ())
	table.insert(listeners, listener)
end

-- Scales a particle count by the budget, never below `minimum`.
function Quality.Amount(count: number, minimum: number?): number
	return math.max(minimum or 1, math.floor(count * Quality.Current.Particles + 0.5))
end

return Quality
