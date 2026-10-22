--[[
	Daily reward with a 7-day streak, based on UTC calendar days.

	Claim on consecutive days to climb the streak; miss a day and it restarts at
	day 1. After day 7 the streak stays on the day-7 reward.
]]

local Config = require(script.Parent.Config)

local Daily = {}

Daily.Rewards = { 250, 500, 1000, 2000, 4000, 7500, 15000 }
Daily.DaySeconds = 86400

function Daily.DayNumber(now: number): number
	return math.floor(now / Daily.DaySeconds)
end

-- daily = { Day = last claimed day number, Streak = streak at that claim }
-- Returns canClaim, the streak the next claim gives, seconds until next claim.
function Daily.Status(daily, now: number): (boolean, number, number)
	local today = Daily.DayNumber(now)
	local lastDay = daily and daily.Day or 0
	local streak = daily and daily.Streak or 0
	if lastDay >= today then
		return false, math.max(1, streak), (today + 1) * Daily.DaySeconds - now
	end
	local nextStreak = if lastDay == today - 1 then streak + 1 else 1
	return true, nextStreak, 0
end

function Daily.Reward(streak: number, rebirths: number?): number
	local index = math.clamp(streak, 1, #Daily.Rewards)
	return math.floor(Daily.Rewards[index] * Config.RebirthMultiplier(rebirths or 0))
end

return Daily
