--[[
	The Index: a collection book of things to discover. Each entry unlocks once,
	the first time a launch meets its goal, and pays a one-time coin reward.

	The server evaluates entries against its own validated launch numbers; the
	client only uses this module to draw the Index panel.
]]

local Config = require(script.Parent.Config)

local Index = {}

-- Goal types match the fields of a launch summary:
--   Distance, Smashes, Stars, Rings, Gold, TNT, MaxCombo
Index.Entries = {
	{
		Id = "Zone1",
		Name = "Green Meadows",
		Icon = "🌳",
		Hint = "Launch for the first time",
		Goal = "Distance",
		Value = 1,
		Reward = 100,
	},
	{
		Id = "Zone2",
		Name = "Sky City",
		Icon = "🏙️",
		Hint = "Fly " .. Config.Zones[1].EndsAt .. " studs",
		Goal = "Distance",
		Value = Config.Zones[1].EndsAt,
		Reward = 1500,
	},
	{
		Id = "Zone3",
		Name = "Neon Grid",
		Icon = "💠",
		Hint = "Fly " .. Config.Zones[2].EndsAt .. " studs",
		Goal = "Distance",
		Value = Config.Zones[2].EndsAt,
		Reward = 6000,
	},
	{
		Id = "Zone4",
		Name = "Candy Peaks",
		Icon = "🍭",
		Hint = "Fly " .. Config.Zones[3].EndsAt .. " studs",
		Goal = "Distance",
		Value = Config.Zones[3].EndsAt,
		Reward = 25000,
	},
	{
		Id = "Finish",
		Name = "Finish Line",
		Icon = "🏆",
		Hint = "Reach the end of the lane",
		Goal = "Distance",
		Value = Config.LaneLength - 5,
		Reward = 100000,
	},
	{
		Id = "Gold",
		Name = "Gold Rush",
		Icon = "💛",
		Hint = "Smash a gold block",
		Goal = "Gold",
		Value = 1,
		Reward = 400,
	},
	{
		Id = "TNT",
		Name = "Kaboom",
		Icon = "💣",
		Hint = "Smash a TNT block",
		Goal = "TNT",
		Value = 1,
		Reward = 400,
	},
	{
		Id = "Star",
		Name = "Star Catcher",
		Icon = "⭐",
		Hint = "Grab a floating star",
		Goal = "Stars",
		Value = 1,
		Reward = 600,
	},
	{
		Id = "Ring",
		Name = "Ring Runner",
		Icon = "🌀",
		Hint = "Fly through a boost ring",
		Goal = "Rings",
		Value = 1,
		Reward = 600,
	},
	{
		Id = "Stars3",
		Name = "Star Shower",
		Icon = "🌟",
		Hint = "Grab 3 stars in one launch",
		Goal = "Stars",
		Value = 3,
		Reward = 4000,
	},
	{
		Id = "Combo25",
		Name = "Combo Master",
		Icon = "🔥",
		Hint = "Chain a 25-smash combo",
		Goal = "MaxCombo",
		Value = 25,
		Reward = 2500,
	},
	{
		Id = "Smash100",
		Name = "Wrecking Crew",
		Icon = "🔨",
		Hint = "Smash 100 blocks in one launch",
		Goal = "Smashes",
		Value = 100,
		Reward = 5000,
	},
}

Index.ById = {}
for _, entry in Index.Entries do
	Index.ById[entry.Id] = entry
end

-- Entries this launch summary unlocks that aren't in `discovered` yet.
function Index.Evaluate(summary, discovered)
	local unlocked = {}
	for _, entry in Index.Entries do
		local value = summary[entry.Goal]
		if not discovered[entry.Id] and type(value) == "number" and value >= entry.Value then
			table.insert(unlocked, entry)
		end
	end
	return unlocked
end

function Index.Count(discovered): number
	local count = 0
	for _, entry in Index.Entries do
		if discovered[entry.Id] then
			count += 1
		end
	end
	return count
end

return Index
