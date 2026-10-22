--[[
	Redeemable codes and their coin rewards. Each player can use each code once.
	Keys must be upper case with no spaces (see Config.NormalizeCode).

	This lives on the server, so players can't read it from inside the game.
	Anyone who can read this source code can, though, so treat these as public
	promo codes, not secrets.
]]

return {
	LAUNCH = 500,
	SMASH = 1500,
	KABOOM = 3000,
}
