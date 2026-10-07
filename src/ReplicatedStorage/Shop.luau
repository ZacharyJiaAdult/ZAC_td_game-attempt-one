-- The lobby shop: one-use abilities you can bring into a match, and the potato summon machine.
-- Everything here is paid for with Spud Coins, which you earn by playing matches (no real money involved).
local Shop = {}

Shop.Abilities = {
	{
		id = "meteor",
		name = "Meteor Mash",
		price = 80,
		color = Color3.fromRGB(255, 120, 60),
		desc = "Smashes every zombie on the road for heavy damage.",
	},
	{
		id = "freeze",
		name = "Freeze Fry",
		price = 60,
		color = Color3.fromRGB(110, 200, 255),
		desc = "Slows every zombie to a crawl for 8 seconds.",
	},
	{
		id = "coinrain",
		name = "Coin Rain",
		price = 50,
		color = Color3.fromRGB(255, 220, 90),
		desc = "Instantly gives you coins to build with.",
	},
	{
		id = "shield",
		name = "Base Shield",
		price = 70,
		color = Color3.fromRGB(120, 230, 150),
		desc = "Repairs 40% of your base.",
	},
}
-- Abilities that are never sold: only admins can hand them out (see the admin panel).
Shop.AdminAbilities = {
	{
		id = "nuke",
		name = "SUPER NUKE",
		price = 0,
		adminOnly = true,
		color = Color3.fromRGB(255, 60, 60),
		desc = "Wipes out every zombie on the battlefield, bosses included.",
	},
}

-- everything that can be used in a match: the shop's abilities, then the admin-only ones
Shop.AllAbilities = table.clone(Shop.Abilities)
for _, ability in Shop.AdminAbilities do
	table.insert(Shop.AllAbilities, ability)
end
Shop.AbilityById = {}
for _, ability in Shop.AllAbilities do
	Shop.AbilityById[ability.id] = ability
end
Shop.AbilityCooldown = 6 -- seconds before the same ability can be used again in a match
Shop.FreezeSeconds = 8

-- Summoning. The odds shown to players are computed from these weights, so what is displayed is what is rolled.
Shop.SummonCost = 200
Shop.SummonTenCost = 1800 -- ten summons for the price of nine
Shop.DuplicateRefund = 0.5 -- a potato you already own gives back this share of the price
Shop.Rarities = {
	{ id = "rare", name = "Rare", weight = 60, color = Color3.fromRGB(110, 170, 255) },
	{ id = "epic", name = "Epic", weight = 28, color = Color3.fromRGB(190, 110, 255) },
	{ id = "legendary", name = "Legendary", weight = 10, color = Color3.fromRGB(255, 190, 50) },
	{ id = "mythic", name = "Mythic", weight = 2, color = Color3.fromRGB(255, 90, 110) },
}
Shop.RarityById = {}
for _, rarity in Shop.Rarities do
	Shop.RarityById[rarity.id] = rarity
end

return Shop
