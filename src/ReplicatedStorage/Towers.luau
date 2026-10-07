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
		id = "Mashed Potato",
		style = "Gravity",
		range = 15,
		cost = 250,
		unlockWave = 7,
		color = Color3.fromRGB(110, 230, 170),
		role = "Pulses the area",
		kind = "pulse",
		damage = 6,
		interval = 1.5,
		slow = 0.65,
		slowSeconds = 1.5,
	},
}

Towers.ById = {}
for _, tower in Towers.List do
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
