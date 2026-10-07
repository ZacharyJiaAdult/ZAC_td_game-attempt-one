-- The defenders. Every one is an original potato character. `style` picks the hat or prop drawn on it. To change the roster or
-- the balance, edit this list only: the rest of the game reads it.
--   cost         coins to place it
--   unlockWave   you can build it once you have reached this wave
--   range        radius in studs; defenders go anywhere off the road and hit zombies on the road within range
--   kind         "shoot"  hits the zombie furthest along the road within range
--                "pulse"  hits EVERY zombie within range
--                "coins"  makes coins instead of fighting
--   damage / interval   damage per shot, seconds between shots (for "coins": amount per payout)
--   slow / slowSeconds  shots also slow a zombie to this fraction of its speed for this long
-- Upgrading to level 2 and 3 multiplies the numbers by Towers.LevelMultiplier.
local Towers = {}

Towers.List = {
	{
		id = "Potato Gunner",
		style = "Verity",
		range = 20,
		cost = 50,
		unlockWave = 1,
		color = Color3.fromRGB(110, 190, 255),
		role = "Reliable shooter",
		kind = "shoot",
		damage = 10,
		interval = 1.0,
	},
	{
		id = "Money Potato",
		style = "Lovity",
		range = 0,
		cost = 40,
		unlockWave = 1,
		color = Color3.fromRGB(255, 130, 170),
		role = "Makes coins",
		kind = "coins",
		damage = 14, -- coins per payout
		interval = 5,
	},
	{
		id = "Cold Potato",
		style = "Falsity",
		range = 18,
		cost = 90,
		unlockWave = 2,
		color = Color3.fromRGB(190, 120, 255),
		role = "Slows zombies",
		kind = "shoot",
		damage = 4,
		interval = 1.2,
		slow = 0.5,
		slowSeconds = 2.5,
	},
	{
		id = "Rapid Spud",
		style = "Gaiety",
		range = 15,
		cost = 120,
		unlockWave = 3,
		color = Color3.fromRGB(255, 215, 80),
		role = "Rapid fire",
		kind = "shoot",
		damage = 5,
		interval = 0.35,
	},
	{
		id = "Hot Potato",
		style = "Hot",
		range = 11,
		cost = 150,
		unlockWave = 4,
		color = Color3.fromRGB(255, 90, 50),
		role = "Burns nearby",
		kind = "pulse",
		damage = 12,
		interval = 0.9,
	},
	{
		id = "Potato Nuke",
		style = "Vanity",
		range = 30,
		cost = 175,
		unlockWave = 5,
		color = Color3.fromRGB(255, 140, 60),
		role = "Heavy hitter",
		kind = "shoot",
		damage = 55,
		interval = 2.6,
	},
	{
		id = "Golden Potato",
		style = "Gold",
		range = 0,
		cost = 200,
		unlockWave = 6,
		color = Color3.fromRGB(255, 205, 40),
		role = "Big coins",
		kind = "coins",
		damage = 60, -- coins per payout
		interval = 8,
	},
	{
		id = "Mashed Potato",
		style = "Gravity",
		range = 15,
		cost = 250,
		unlockWave = 7,
		color = Color3.fromRGB(110, 230, 170),
		role = "Pulses area",
		kind = "pulse",
		damage = 6,
		interval = 1.5,
		slow = 0.65,
		slowSeconds = 1.5,
	},
	{
		id = "Fry Gatling",
		style = "Fry",
		range = 17,
		cost = 220,
		unlockWave = 8,
		color = Color3.fromRGB(250, 220, 90),
		role = "Machine-gun fries",
		kind = "shoot",
		damage = 3,
		interval = 0.12,
	},
	{
		id = "Sniper Spud",
		style = "Sniper",
		range = 46,
		cost = 300,
		unlockWave = 9,
		color = Color3.fromRGB(120, 120, 140),
		role = "Huge range",
		kind = "shoot",
		damage = 80,
		interval = 3.5,
	},
}

-- Unique potatoes: you get these from the summon machine in the lobby. Once you own one it is available in
-- every match from wave 1. (The default potatoes above are always available, unlocking as waves progress.)
Towers.Unique = {
	{
		id = "Tater Tot Trooper", style = "Gaiety", rarity = "rare", range = 22, cost = 65, unlockWave = 1,
		color = Color3.fromRGB(230, 170, 90), role = "Cheap sharpshooter", kind = "shoot", damage = 14, interval = 0.8,
	},
	{
		id = "Baked Potato Bank", style = "Gold", rarity = "rare", range = 0, cost = 55, unlockWave = 1,
		color = Color3.fromRGB(140, 200, 150), role = "Steady coins", kind = "coins", damage = 22, interval = 5,
	},
	{
		id = "Wasabi Spud", style = "Hot", rarity = "epic", range = 13, cost = 130, unlockWave = 1,
		color = Color3.fromRGB(150, 220, 90), role = "Burning pulse, slows", kind = "pulse", damage = 11, interval = 0.8,
		slow = 0.7, slowSeconds = 1.5,
	},
	{
		id = "Sour Cream Cannon", style = "Sniper", rarity = "epic", range = 30, cost = 160, unlockWave = 1,
		color = Color3.fromRGB(245, 245, 235), role = "Heavy slowing shots", kind = "shoot", damage = 45, interval = 1.6,
		slow = 0.6, slowSeconds = 2,
	},
	{
		id = "Disco Spud", style = "Gaiety", rarity = "legendary", range = 18, cost = 220, unlockWave = 1,
		color = Color3.fromRGB(255, 100, 220), role = "Fast party pulse", kind = "pulse", damage = 22, interval = 0.6,
	},
	{
		id = "King Russet", style = "Verity", rarity = "legendary", range = 36, cost = 260, unlockWave = 1,
		color = Color3.fromRGB(200, 150, 60), role = "Royal long-range hits", kind = "shoot", damage = 140, interval = 2.2,
	},
	{
		id = "Cosmic Tuber", style = "Gravity", rarity = "mythic", range = 26, cost = 380, unlockWave = 1,
		color = Color3.fromRGB(120, 140, 255), role = "Space-time pulse", kind = "pulse", damage = 50, interval = 0.5,
		slow = 0.5, slowSeconds = 1,
	},
}

Towers.ById = {}
for _, tower in Towers.List do
	Towers.ById[tower.id] = tower
end
for _, tower in Towers.Unique do
	Towers.ById[tower.id] = tower
end

Towers.MaxLevel = 3
Towers.LevelMultiplier = { 1, 1.8, 3 }
Towers.UpgradeCostMultiplier = { 0.8, 1.6 } -- cost of going from level 1 to 2, then 2 to 3, as a share of the tower's cost

-- coins to go from `level` to the next one, or nil when it is already at the top
function Towers.upgradeCost(def, level)
	local multiplier = Towers.UpgradeCostMultiplier[level]
	return multiplier and math.floor(def.cost * multiplier) or nil
end

-- everything spent on a tower of this level (placing it plus its upgrades)
function Towers.invested(def, level)
	local total = def.cost
	for l = 1, level - 1 do
		total += Towers.upgradeCost(def, l)
	end
	return total
end

return Towers
