--[[
	"Top Launches" board in the lobby.

	Published games keep a global top 10 in an OrderedDataStore. Where
	DataStores aren't available (an unpublished place, or Studio without API
	access) the board shows the best distances of the players in this server.
	Temporary DataStore errors (throttling, outages) only skip one refresh or
	flush; queued bests are kept and retried.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local WorldBuilder = require(script.Parent.WorldBuilder)

local Leaderboard = {}

local ROWS = 10
local GLOBAL_REFRESH = 60
local LOCAL_REFRESH = 5
local FLUSH_INTERVAL = 30

local store: OrderedDataStore? = nil
local warned = false
local flushing = false
local pending = {} -- [userId] = best distance waiting to be written
local nameCache = {} -- [userId] = username (successful lookups only)
local rows = {} -- { { Name: TextLabel, Value: TextLabel } }
local statusLabel: TextLabel? = nil
local getBest: (Player) -> number = function()
	return 0
end

do
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(Config.LeaderboardStoreName)
	end)
	if ok then
		store = result
	end
end

-- Unpublished places and disabled API access never recover; everything else
-- (throttling, outages) is treated as temporary.
local function handleError(err: any)
	local message = tostring(err)
	local permanent = message:find("StudioAccessToApisNotAllowed") ~= nil
		or message:find("publish") ~= nil
		or message:find("403") ~= nil
	if permanent then
		store = nil
	end
	if not warned then
		warned = true
		warn("[SlingSmash] Global leaderboard request failed:", message)
	end
end

local function buildBoard(parent: Instance)
	local _, gui = WorldBuilder.Signboard(parent, "TopLaunchesBoard", Config.LeaderboardPosition, Vector2.new(20, 22), 6)

	WorldBuilder.SignLabel({
		Text = "🏆 TOP LAUNCHES",
		Size = UDim2.new(1, 0, 0, 64),
		TextColor3 = Color3.fromRGB(255, 214, 60),
		LayoutOrder = 0,
		Parent = gui,
	})

	for rank = 1, ROWS do
		local row = Instance.new("Frame")
		row.Name = "Row" .. rank
		row.Size = UDim2.new(1, 0, 0, 38)
		row.BackgroundColor3 = if rank % 2 == 0 then Color3.fromRGB(86, 58, 40) else Color3.fromRGB(100, 68, 46)
		row.BorderSizePixel = 0
		row.LayoutOrder = rank
		row.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = row

		WorldBuilder.SignLabel({
			Text = if rank == 1 then "🥇" elseif rank == 2 then "🥈" elseif rank == 3 then "🥉" else "#" .. rank,
			Position = UDim2.fromOffset(6, 3),
			Size = UDim2.new(0, 50, 1, -6),
			Parent = row,
		})
		local name = WorldBuilder.SignLabel({
			Text = "---",
			Position = UDim2.fromOffset(62, 3),
			Size = UDim2.new(0.62, -62, 1, -6),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		local value = WorldBuilder.SignLabel({
			Text = "",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 3),
			Size = UDim2.new(0.38, -10, 1, -6),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Color3.fromRGB(140, 255, 100),
			Parent = row,
		})
		rows[rank] = { Name = name, Value = value }
	end

	statusLabel = WorldBuilder.SignLabel({
		Text = "",
		Size = UDim2.new(1, 0, 0, 26),
		TextColor3 = Color3.fromRGB(255, 226, 190),
		LayoutOrder = ROWS + 1,
		Parent = gui,
	})
end

-- Usernames everywhere, so a player reads the same online and offline.
local function nameFor(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	if player then
		return player.Name
	end
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(name) == "string" then
		nameCache[userId] = name
		return name
	end
	return "Player" -- not cached: try again on the next refresh
end

local function render(entries, isGlobal: boolean)
	for rank = 1, ROWS do
		local row = rows[rank]
		local entry = entries[rank]
		if row then
			row.Name.Text = if entry then entry.Name else "---"
			row.Value.Text = if entry then Format.Commas(entry.Value) else ""
		end
	end
	local status = statusLabel
	if status then
		status.Text = if isGlobal
			then "🌍 All servers • best distance in studs"
			else "🏠 This server • publish the game for a global board"
	end
end

local function localEntries()
	local entries = {}
	for _, player in Players:GetPlayers() do
		local best = getBest(player)
		if best > 0 then
			table.insert(entries, { Name = player.Name, Value = best })
		end
	end
	table.sort(entries, function(a, b)
		return a.Value > b.Value
	end)
	return entries
end

local function globalEntries()
	local activeStore = store
	if not activeStore then
		return nil
	end
	local ok, pages = pcall(function()
		return activeStore:GetSortedAsync(false, ROWS)
	end)
	if not ok then
		handleError(pages)
		return nil
	end
	local entries = {}
	for _, item in pages:GetCurrentPage() do
		local userId = tonumber(item.key)
		if userId and type(item.value) == "number" then
			table.insert(entries, { Name = nameFor(userId), Value = item.value })
		end
	end
	return entries
end

function Leaderboard.Refresh()
	local entries = globalEntries()
	if entries then
		render(entries, true)
	else
		render(localEntries(), false)
	end
end

-- Remembers a player's new best; written to the global store in batches.
function Leaderboard.Submit(player: Player, best: number)
	if best <= 0 then
		return
	end
	local userId = player.UserId
	pending[userId] = math.max(pending[userId] or 0, math.floor(best))
	if not store then
		render(localEntries(), false)
	end
end

-- Writes queued bests and yields until done. Only ever raises a stored value.
function Leaderboard.Flush()
	-- One flush at a time; a second caller waits for the running one.
	while flushing do
		task.wait(0.1)
	end
	local activeStore = store
	if not activeStore then
		return
	end
	flushing = true

	-- Work from a snapshot: Submit can run while UpdateAsync yields.
	local batch = {}
	for userId, best in pending do
		table.insert(batch, { UserId = userId, Best = best })
	end
	for _, item in batch do
		local ok, err = pcall(function()
			activeStore:UpdateAsync(tostring(item.UserId), function(old)
				if type(old) == "number" and old >= item.Best then
					return nil
				end
				return item.Best
			end)
		end)
		if ok then
			-- Keep anything newer that arrived during the write.
			if pending[item.UserId] == item.Best then
				pending[item.UserId] = nil
			end
		else
			handleError(err)
			break -- try the rest on the next flush
		end
	end
	flushing = false
end

function Leaderboard.Init(parent: Instance, bestForPlayer: (Player) -> number)
	getBest = bestForPlayer
	buildBoard(parent)
	render({}, store ~= nil)

	Players.PlayerRemoving:Connect(function()
		task.spawn(Leaderboard.Flush)
	end)

	task.spawn(function()
		while true do
			Leaderboard.Refresh()
			task.wait(if store then GLOBAL_REFRESH else LOCAL_REFRESH)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(FLUSH_INTERVAL)
			Leaderboard.Flush()
		end
	end)
end

return Leaderboard
