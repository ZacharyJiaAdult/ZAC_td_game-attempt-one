return {
	Lanes = 4,
	Columns = 8,

	StartingCoins = 150,
	TrickleCoins = 1, -- free coins per second, so a stuck player can always recover
	AutosaveSeconds = 60,
	SellRefund = 0.6, -- share of everything you spent on a tower that you get back when you sell it

	-- Zombies walk along a lane from the right edge (position 0) to your base on the left (position 1).
	-- A zombie that reaches the base hurts it. A destroyed base costs coins, but never your towers.
	BaseHealth = 100,
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
	ZombieSpeed = 0.022, -- fraction of the lane crossed per second (about 45 seconds end to end)
	BossEvery = 5, -- every 5th wave ends with a boss
	BossHpMultiplier = 12,
	ZombieRewardRate = 0.35, -- coins per zombie = its health times this
	WaveClearBonus = 40, -- clearing wave n pays n times this
	OverrunCoinLoss = 0.25, -- share of your coins lost when zombies destroy the base
}
