return {
	-- Two kinds of coins: "coins" are earned and spent inside one match; "Spud Coins" are your permanent
	-- balance, earned by finishing matches and spent in the lobby shop.
	StartSpuds = 250, -- Spud Coins a new player starts with (enough for one summon, so they can try it)
	TrickleCoins = 1, -- free match coins per second, so a stuck player can always recover
	AutosaveSeconds = 60,
	SellRefund = 0.6, -- share of everything you spent on a tower that you get back when you sell it

	-- A match is one run: pick a map and a difficulty, survive `waves` waves to win. If zombies destroy your
	-- base the match ends. Either way you keep the Spud Coins you earned.
	-- hp / speed multiply zombie health and speed; reward multiplies match coins; spud multiplies Spud Coins.
	Difficulties = {
		{ id = "easy", name = "Easy", blurb = "Relaxed zombies and a sturdy base.", hp = 0.75, speed = 0.9, reward = 1.1,
			baseHp = 150, waves = 12, startCoins = 220, spud = 1, color = Color3.fromRGB(110, 210, 120) },
		{ id = "normal", name = "Normal", blurb = "The intended challenge.", hp = 1, speed = 1, reward = 1,
			baseHp = 100, waves = 20, startCoins = 150, spud = 1.6, color = Color3.fromRGB(240, 200, 80) },
		{ id = "hard", name = "Hard", blurb = "Tough, fast zombies and a fragile base.", hp = 1.6, speed = 1.15, reward = 1.1,
			baseHp = 75, waves = 25, startCoins = 130, spud = 2.6, color = Color3.fromRGB(240, 90, 90) },
	},
	-- Co-op: up to MaxParty players share one battlefield, one base and one set of waves. Each keeps their own
	-- coins and defenders. Every extra player makes zombies tougher, but earns everyone a Spud Coin bonus.
	MaxParty = 4,
	PartyHpPerExtraPlayer = 0.5, -- zombies have this much more health for each player beyond the first
	PartySpudBonus = 0.1, -- Spud Coin bonus for each player beyond the first

	-- Inviting friends: when someone brand new joins through your invite link, you both get Spud Coins.
	ReferralJoinerSpuds = 100,
	ReferralInviterSpuds = 150,
	ReferralInviterMaxPerSession = 5,

	SpudsPerWave = 6, -- Spud Coins per wave cleared (times the difficulty's spud multiplier)
	SpudsVictoryBonus = 80, -- extra Spud Coins for winning (times the difficulty's spud multiplier)

	-- Zombies walk the map's road from the graveyard (position 0) to your base (position 1).
	BarricadeHp = 25, -- each barricade you build adds this much base health
	BarricadeBaseCost = 150,
	BarricadeCostGrowth = 1.6, -- each barricade costs this many times the one before
	FirstWaveDelay = 30, -- seconds before the first wave, so there is time to set up
	WaveBreakSeconds = 20, -- calm time between waves
	ZombiesBase = 2, -- wave n sends ZombiesBase + n * ZombiesPerWave zombies
	ZombiesPerWave = 2,
	ZombieSpawnGap = 2.2, -- seconds between zombies within a wave
	ZombieHpBase = 30, -- wave n zombies have ZombieHpBase * ZombieHpGrowth ^ (n - 1) health
	ZombieHpGrowth = 1.22,
	ZombieStudSpeed = 4.3, -- studs per second along the road
	BossEvery = 5, -- every 5th wave ends with a boss
	BossHpMultiplier = 12,
	ZombieRewardRate = 0.35, -- coins per zombie = its health times this
	WaveClearBonus = 40, -- clearing wave n pays n times this

	-- Enemy types. Each zombie is picked at random (by weight) from the types whose `from` wave has been reached.
	-- hp / speed / damage are multipliers on the normal zombie; scale is how big it is drawn.
	ZombieTypes = {
		{ kind = "walker", from = 1, weight = 10, hp = 1, speed = 1, damage = 1, scale = 1, color = Color3.fromRGB(110, 170, 90),
			names = { "Stale Crust Walker", "Moldy Meatballer", "Sauce Shambler", "Soggy Noodle Crawler" } },
		{ kind = "runner", from = 3, weight = 5, hp = 0.45, speed = 1.9, damage = 1, scale = 0.85, color = Color3.fromRGB(205, 200, 80),
			names = { "Breadstick Sprinter", "Fast Food Fiend" } },
		{ kind = "tank", from = 5, weight = 3, hp = 3.5, speed = 0.6, damage = 2, scale = 1.4, color = Color3.fromRGB(120, 130, 150),
			names = { "Lasagna Brute", "Casserole Crusher" } },
		{ kind = "swarmer", from = 7, weight = 4, hp = 0.25, speed = 1.3, damage = 0.5, scale = 0.6, color = Color3.fromRGB(190, 110, 150),
			names = { "Crumb Critter", "Noodle Nibbler" } },
	},
}
