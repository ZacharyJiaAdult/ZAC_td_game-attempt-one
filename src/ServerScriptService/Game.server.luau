local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Towers = require(ReplicatedStorage:WaitForChild("Towers"))

local Path = require(ReplicatedStorage:WaitForChild("Path"))

local TICK = 0.1
local MAX_TOWERS = 60

-- Players run around the map as their avatar and click the ground to build.
Players.CharacterAutoLoads = true
-- start every avatar on the grass between the road's rows, not on the road itself
local function placeAvatar(player)
	player.CharacterAdded:Connect(function(character)
		task.defer(function()
			character:PivotTo(CFrame.new(math.random(-6, 6), 5, -7.5))
		end)
	end)
end
Players.PlayerAdded:Connect(placeAvatar)
for _, player in Players:GetPlayers() do
	placeAvatar(player)
end

-- Remotes ---------------------------------------------------------------------

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local function makeRemote(name)
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = remotes
	return event
end
local stateEvent = makeRemote("State") -- server -> client: the whole battlefield, five times a second
local readyEvent = makeRemote("Ready") -- client -> server: the UI is up, send me my state
local placeEvent = makeRemote("Place") -- client -> server: (towerId, x, z)
local upgradeEvent = makeRemote("Upgrade") -- client -> server: (tower uid)
local sellEvent = makeRemote("Sell") -- client -> server: (tower uid)
local barricadeEvent = makeRemote("Barricade") -- client -> server: build a barricade
local noticeEvent = makeRemote("Notice") -- server -> client: a short message
remotes.Parent = ReplicatedStorage

-- Profiles (saved to a DataStore) ------------------------------------------------
-- Studio needs "Enable Studio Access to API Services" in Game Settings > Security, and the place must be
-- published. If loading fails the profile still works for the session but is not saved, so a failed load
-- can never overwrite someone's saved data with defaults.

local storeOk, store = pcall(function()
	return DataStoreService:GetDataStore("ZombiesVsVerityProfiles_v1")
end)
if not storeOk then
	warn("DataStore unavailable, progress will not be saved: " .. tostring(store))
	store = nil
end

local profiles = {}
local loaded = {}
local ready = {}

local function newProfile()
	return {
		-- saved
		coins = Config.StartingCoins,
		towers = {}, -- [uid] = { id = "Verity", level = 1, x = 0, z = 0 }
		nextTowerId = 1,
		wave = 1,
		bestWave = 0,
		barricades = 0,

		-- this session only
		baseHp = Config.BaseHealth,
		phase = "break", -- "break" (calm) or "fight"
		breakUntil = os.clock() + Config.FirstWaveDelay,
		zombies = {},
		toSpawn = 0,
		nextZombieAt = 0,
		zombieCounter = 0,
		isBossWave = false,
		towerNext = {}, -- [uid] = when that tower may act again
		trickle = 0,
		events = {}, -- shots and coin payouts since the last update, for the client to animate
	}
end

local function getProfile(player)
	local profile = profiles[player]
	if not profile then
		profile = newProfile()
		profiles[player] = profile
	end
	return profile
end

local function keyOf(player)
	return `player_{player.UserId}`
end

local function saveProfile(player)
	local profile = profiles[player]
	if not profile or profile.noSave or not store then
		return false
	end
	local towerList = {}
	for _, tower in profile.towers do
		table.insert(towerList, { x = tower.x, z = tower.z, id = tower.id, level = tower.level })
	end
	local ok, err = pcall(function()
		store:SetAsync(keyOf(player), {
			coins = math.floor(profile.coins),
			towers = towerList,
			wave = profile.wave,
			bestWave = profile.bestWave,
			barricades = profile.barricades,
		})
	end)
	if not ok then
		warn(`Saving {player.Name} failed: {err}`)
	end
	return ok
end

local function loadProfile(player)
	local ok, data = pcall(function()
		if not store then
			error("no DataStore")
		end
		return store:GetAsync(keyOf(player))
	end)
	if loaded[player] or player.Parent ~= Players then
		return
	end
	local profile = getProfile(player)
	if ok then
		if typeof(data) == "table" then
			profile.coins = tonumber(data.coins) or profile.coins
			profile.wave = math.max(1, math.floor(tonumber(data.wave) or 1))
			profile.bestWave = math.max(0, math.floor(tonumber(data.bestWave) or 0))
			profile.barricades = math.max(0, math.floor(tonumber(data.barricades) or 0))
			profile.baseHp = Config.BaseHealth + profile.barricades * Config.BarricadeHp
			if typeof(data.towers) == "table" then
				for _, entry in data.towers do
					local x = typeof(entry) == "table" and tonumber(entry.x)
					local z = typeof(entry) == "table" and tonumber(entry.z)
					local def = typeof(entry) == "table" and Towers.ById[entry.id]
					-- (older saves used grid cells and have no x/z: those towers are simply skipped)
					if x and z and def and Path.canPlace(x, z) then
						local level = math.clamp(math.floor(tonumber(entry.level) or 1), 1, Towers.MaxLevel)
						profile.towers[profile.nextTowerId] = { id = def.id, level = level, x = x, z = z }
						profile.nextTowerId += 1
					end
				end
			end
		end
	else
		profile.noSave = true
		warn(`Loading {player.Name} failed, their progress will not be saved: {data}`)
	end
	loaded[player] = true
end

-- Helpers -----------------------------------------------------------------------------

local function baseMax(profile)
	return Config.BaseHealth + profile.barricades * Config.BarricadeHp
end

local function barricadeCost(profile)
	return math.floor(Config.BarricadeBaseCost * Config.BarricadeCostGrowth ^ profile.barricades)
end

local function coinsPerSecond(profile)
	local total = Config.TrickleCoins
	for _, tower in profile.towers do
		local def = Towers.ById[tower.id]
		if def.kind == "coins" then
			total += def.damage * Towers.LevelMultiplier[tower.level] / def.interval
		end
	end
	return total
end

local function notice(player, text, isGood)
	noticeEvent:FireClient(player, text, isGood ~= false)
end

-- Zombie waves --------------------------------------------------------------------------------

local ZOMBIE_NAMES = { "Stale Crust Walker", "Moldy Meatballer", "Sauce Shambler", "Soggy Noodle Crawler" }

local function startWave(profile)
	profile.phase = "fight"
	profile.zombies = {}
	profile.zombieCounter = 0
	profile.isBossWave = profile.wave % Config.BossEvery == 0
	profile.toSpawn = Config.ZombiesBase + profile.wave * Config.ZombiesPerWave
	if profile.isBossWave then
		profile.toSpawn += 1 -- the boss comes last
	end
	profile.nextZombieAt = os.clock() + 1
end

local function spawnZombie(profile)
	profile.zombieCounter += 1
	local boss = profile.isBossWave and profile.toSpawn == 1
	profile.toSpawn -= 1
	local hp = Config.ZombieHpBase * Config.ZombieHpGrowth ^ (profile.wave - 1)
	if boss then
		hp *= Config.BossHpMultiplier
	end
	hp = math.ceil(hp)
	table.insert(profile.zombies, {
		id = profile.zombieCounter,
		name = boss and "The Doughpocalypse" or ZOMBIE_NAMES[math.random(#ZOMBIE_NAMES)],
		boss = boss,
		hp = hp,
		maxHp = hp,
		pos = 0, -- how far along the road: 0 is the graveyard, 1 is the base
		speed = Config.ZombieSpeed * math.min(2, 1 + 0.03 * (profile.wave - 1)) * (boss and 0.6 or 1),
		damage = boss and (40 + profile.wave * 2) or (10 + profile.wave),
		reward = math.ceil(hp * Config.ZombieRewardRate),
		slowUntil = 0,
		slowMul = 1,
	})
	profile.nextZombieAt = os.clock() + Config.ZombieSpawnGap
end

-- Towers act on their own timers. A shooter waits (without using up its timer) until a zombie is in front of it.
local function fireTowers(profile, now)
	for uid, tower in profile.towers do
		if now >= (profile.towerNext[uid] or 0) then
			local def = Towers.ById[tower.id]
			local multiplier = Towers.LevelMultiplier[tower.level]
			local range = def.range * (1 + 0.1 * (tower.level - 1))

			if def.kind == "coins" then
				local amount = math.floor(def.damage * multiplier)
				profile.coins += amount
				profile.towerNext[uid] = now + def.interval
				table.insert(profile.events, { kind = "coin", x = tower.x, z = tower.z, amount = amount })
			else
				local targets = {}
				for _, zombie in profile.zombies do
					if zombie.hp > 0 then
						local at = Path.pointAt(zombie.pos)
						if (at - Vector3.new(tower.x, 0, tower.z)).Magnitude <= range then
							table.insert(targets, zombie)
						end
					end
				end
				if #targets > 0 then
					table.sort(targets, function(a, b)
						return a.pos > b.pos -- the one furthest along the road (closest to your base) first
					end)
					local hits = def.kind == "pulse" and targets or { targets[1] }
					for _, zombie in hits do
						zombie.hp -= def.damage * multiplier
						if def.slow then
							zombie.slowMul = def.slow
							zombie.slowUntil = now + def.slowSeconds
						end
						local at = Path.pointAt(zombie.pos)
						table.insert(profile.events, {
							kind = "shot",
							id = def.id,
							fromX = tower.x,
							fromZ = tower.z,
							toX = at.X,
							toZ = at.Z,
						})
					end
					if def.kind == "pulse" then
						table.insert(profile.events, { kind = "pulse", id = def.id, x = tower.x, z = tower.z, range = range })
					end
					profile.towerNext[uid] = now + def.interval
				end
			end
		end
	end
	-- never let a burst of events grow without bound if the client falls behind
	while #profile.events > 60 do
		table.remove(profile.events, 1)
	end
end

local function stepGame(player, profile, dt)
	local now = os.clock()

	-- a small free trickle of coins
	profile.trickle += Config.TrickleCoins * dt
	if profile.trickle >= 1 then
		local whole = math.floor(profile.trickle)
		profile.coins += whole
		profile.trickle -= whole
	end

	if profile.phase == "break" then
		if now >= profile.breakUntil then
			startWave(profile)
		end
	elseif profile.toSpawn > 0 and now >= profile.nextZombieAt then
		spawnZombie(profile)
	end

	fireTowers(profile, now)

	-- zombies walk (slowed ones more slowly), die, or reach the base
	local survivors = {}
	for _, zombie in profile.zombies do
		if zombie.hp <= 0 then
			profile.coins += zombie.reward
			if zombie.boss then
				notice(player, `You destroyed {zombie.name}!`, true)
			end
		else
			local speed = zombie.speed
			if now < zombie.slowUntil then
				speed *= zombie.slowMul
			end
			zombie.pos += speed * dt
			if zombie.pos >= 1 then
				profile.baseHp -= zombie.damage
			else
				table.insert(survivors, zombie)
			end
		end
	end
	profile.zombies = survivors

	if profile.phase ~= "fight" then
		return
	end
	local max = baseMax(profile)
	if profile.baseHp <= 0 then
		-- overrun: it costs coins, never towers, and the same wave starts again
		local loss = math.floor(profile.coins * Config.OverrunCoinLoss)
		profile.coins -= loss
		profile.zombies = {}
		profile.toSpawn = 0
		profile.baseHp = max
		profile.phase = "break"
		profile.breakUntil = now + Config.WaveBreakSeconds
		notice(player, `Zombies broke through! You lost {loss} coins. Wave {profile.wave} will try again.`, false)
	elseif profile.toSpawn == 0 and #profile.zombies == 0 then
		local bonus = profile.wave * Config.WaveClearBonus
		profile.coins += bonus
		profile.bestWave = math.max(profile.bestWave, profile.wave)
		notice(player, `WAVE {profile.wave} CLEARED!  +{bonus} coins`, true)
		profile.wave += 1
		for _, def in Towers.List do
			if def.unlockWave == profile.wave then
				notice(player, `New defender unlocked: {def.id}!`, true)
			end
		end
		profile.baseHp = math.min(max, profile.baseHp + math.ceil(max * 0.3))
		profile.phase = "break"
		profile.breakUntil = now + Config.WaveBreakSeconds
	end
end

-- What the client draws ----------------------------------------------------------------------

local function snapshot(profile)
	local towerList = {}
	for uid, tower in profile.towers do
		table.insert(towerList, { uid = uid, id = tower.id, level = tower.level, x = tower.x, z = tower.z })
	end
	local zombieList = {}
	local now = os.clock()
	for _, zombie in profile.zombies do
		table.insert(zombieList, {
			id = zombie.id,
			name = zombie.name,
			boss = zombie.boss,
			pos = zombie.pos,
			hp = zombie.hp,
			maxHp = zombie.maxHp,
			slowed = now < zombie.slowUntil,
		})
	end
	local events = profile.events
	profile.events = {}
	return {
		coins = math.floor(profile.coins),
		income = coinsPerSecond(profile),
		towers = towerList,
		zombies = zombieList,
		events = events,
		wave = profile.wave,
		bestWave = profile.bestWave,
		phase = profile.phase,
		remaining = profile.toSpawn + #profile.zombies,
		breakIn = math.max(0, math.ceil(profile.breakUntil - now)),
		baseHp = math.max(0, profile.baseHp),
		baseMax = baseMax(profile),
		barricadeCost = barricadeCost(profile),
	}
end

local function push(player)
	if player.Parent == Players then
		stateEvent:FireClient(player, snapshot(getProfile(player)))
	end
end

-- Player actions ------------------------------------------------------------------------------

local function asNumber(value)
	return (typeof(value) == "number" and value == value and math.abs(value) < 1e6) and value or nil
end

local function asUid(value)
	return typeof(value) == "number" and math.floor(value) or nil
end

placeEvent.OnServerEvent:Connect(function(player, towerId, rawX, rawZ)
	local def = typeof(towerId) == "string" and Towers.ById[towerId]
	local x, z = asNumber(rawX), asNumber(rawZ)
	if not def or not x or not z then
		return
	end
	local profile = getProfile(player)
	local others = {}
	local count = 0
	for _, tower in profile.towers do
		table.insert(others, tower)
		count += 1
	end
	local fits, why = Path.canPlace(x, z, others)
	if not fits then
		notice(player, why, false)
	elseif count >= MAX_TOWERS then
		notice(player, `You can have at most {MAX_TOWERS} defenders.`, false)
	elseif def.unlockWave > profile.wave then
		notice(player, `{def.id} unlocks when you reach wave {def.unlockWave}.`, false)
	elseif profile.coins < def.cost then
		notice(player, `{def.id} costs {def.cost} coins.`, false)
	else
		profile.coins -= def.cost
		local uid = profile.nextTowerId
		profile.nextTowerId += 1
		profile.towers[uid] = { id = def.id, level = 1, x = x, z = z }
		profile.towerNext[uid] = os.clock() + 0.5
	end
	push(player)
end)

upgradeEvent.OnServerEvent:Connect(function(player, rawUid)
	local uid = asUid(rawUid)
	local profile = getProfile(player)
	local tower = uid and profile.towers[uid]
	if not tower then
		return
	end
	local def = Towers.ById[tower.id]
	local cost = Towers.upgradeCost(def, tower.level)
	if not cost then
		notice(player, `{def.id} is already at the top level.`, false)
	elseif profile.coins < cost then
		notice(player, `Upgrading {def.id} costs {cost} coins.`, false)
	else
		profile.coins -= cost
		tower.level += 1
		notice(player, `{def.id} is now level {tower.level}!`, true)
	end
	push(player)
end)

sellEvent.OnServerEvent:Connect(function(player, rawUid)
	local uid = asUid(rawUid)
	local profile = getProfile(player)
	local tower = uid and profile.towers[uid]
	if not tower then
		return
	end
	local def = Towers.ById[tower.id]
	local refund = math.floor(Towers.invested(def, tower.level) * Config.SellRefund)
	profile.towers[uid] = nil
	profile.towerNext[uid] = nil
	profile.coins += refund
	notice(player, `Sold {def.id} for {refund} coins.`, true)
	push(player)
end)

barricadeEvent.OnServerEvent:Connect(function(player)
	local profile = getProfile(player)
	local cost = barricadeCost(profile)
	if profile.coins < cost then
		notice(player, `A barricade costs {cost} coins.`, false)
		return
	end
	profile.coins -= cost
	profile.barricades += 1
	profile.baseHp += Config.BarricadeHp
	notice(player, `Barricade built! Base health is now {baseMax(profile)}.`, true)
	push(player)
end)

readyEvent.OnServerEvent:Connect(function(player)
	local waited = 0
	while not loaded[player] and waited < 10 and player.Parent == Players do
		task.wait(0.2)
		waited += 0.2
	end
	if not loaded[player] then
		loaded[player] = true
		getProfile(player).noSave = true
	end
	ready[player] = true
	push(player)
end)

-- The game loop: ten steps a second, a snapshot to each player every other step --------------------

task.spawn(function()
	local last = os.clock()
	local ticks = 0
	while true do
		task.wait(TICK)
		local now = os.clock()
		local dt = now - last
		last = now
		ticks += 1
		for _, player in Players:GetPlayers() do
			if ready[player] then
				stepGame(player, getProfile(player), dt)
				if ticks % 2 == 0 then
					push(player)
				end
			end
		end
	end
end)

-- Player lifecycle and saving -------------------------------------------------------------

Players.PlayerAdded:Connect(function(player)
	task.spawn(loadProfile, player)
end)
for _, player in Players:GetPlayers() do
	task.spawn(loadProfile, player)
end

Players.PlayerRemoving:Connect(function(player)
	saveProfile(player)
	profiles[player] = nil
	loaded[player] = nil
	ready[player] = nil
end)

task.spawn(function()
	while true do
		task.wait(Config.AutosaveSeconds)
		for _, player in Players:GetPlayers() do
			saveProfile(player)
		end
	end
end)

game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		saveProfile(player)
	end
end)
