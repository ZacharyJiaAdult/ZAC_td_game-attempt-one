local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Towers = require(ReplicatedStorage:WaitForChild("Towers"))
local Path = require(ReplicatedStorage:WaitForChild("Path"))
local Shop = require(ReplicatedStorage:WaitForChild("Shop"))

local TICK = 0.1
local MAX_TOWERS = 80 -- per battlefield, shared by everyone in it
local INVITE_SECONDS = 30
local MAX_AMOUNT = 1e63 -- the biggest amount of anything a player can hold: 1 vigintillion
local LOBBY_SPAWN = Vector3.new(1000, 5, 14) -- the lobby is built far from the battlefield

-- Admins (by Roblox user id) get the admin panel. The check is done here on the server for every action,
-- so a hacked client cannot give itself anything.
local ADMIN_USER_IDS = {
	[11769949215] = true, -- @bottleo_waer
	[7029100460] = true, -- Boss_zacharys
}

local DIFFICULTY_BY_ID = {}
for _, difficulty in Config.Difficulties do
	DIFFICULTY_BY_ID[difficulty.id] = difficulty
end

-- Players run around as their avatar: in the lobby, and on the battlefield where they click the ground to build.
Players.CharacterAutoLoads = true

-- Remotes ---------------------------------------------------------------------

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local function makeRemote(name)
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = remotes
	return event
end
local stateEvent = makeRemote("State") -- server -> client: everything the client needs to draw, several times a second
local readyEvent = makeRemote("Ready") -- client -> server: the UI is up, send me my state
local startEvent = makeRemote("StartMatch") -- client -> server: (mapId, difficultyId)
local leaveEvent = makeRemote("Leave") -- client -> server: leave the match / leave the results screen
local placeEvent = makeRemote("Place") -- client -> server: (towerId, x, z)
local upgradeEvent = makeRemote("Upgrade") -- client -> server: (tower uid)
local sellEvent = makeRemote("Sell") -- client -> server: (tower uid)
local barricadeEvent = makeRemote("Barricade") -- client -> server: build a barricade
local abilityEvent = makeRemote("UseAbility") -- client -> server: (abilityId)
local buyEvent = makeRemote("BuyAbility") -- client -> server: (abilityId)
local summonEvent = makeRemote("Summon") -- client -> server: (1 or 10)
local summonResultEvent = makeRemote("SummonResult") -- server -> client: list of { id, new, refund }
local resultEvent = makeRemote("Result") -- server -> client: how a match ended
local noticeEvent = makeRemote("Notice") -- server -> client: a short message
local partyInviteEvent = makeRemote("PartyInvite") -- client -> server: (userId of the player to invite)
local partyRespondEvent = makeRemote("PartyRespond") -- client -> server: (accept: boolean)
local partyLeaveEvent = makeRemote("PartyLeave") -- client -> server: leave your party
local adminEvent = makeRemote("AdminAction") -- client -> server: (action, target, a, b), admins only
remotes.Parent = ReplicatedStorage

-- Profiles (saved to a DataStore) ------------------------------------------------
-- Studio needs "Enable Studio Access to API Services" in Game Settings > Security, and the place must be
-- published. If loading fails the profile still works for the session but is not saved, so a failed load
-- can never overwrite someone's saved data with defaults.

local storeOk, store = pcall(function()
	return DataStoreService:GetDataStore("SpudDefenceProfiles_v1")
end)
if not storeOk then
	warn("DataStore unavailable, progress will not be saved: " .. tostring(store))
	store = nil
end

local profiles = {}
local loaded = {}
local ready = {}
local matches = {} -- every running match, as a set

local function newProfile()
	return {
		-- saved
		spuds = workspace:GetAttribute("StartSpuds") or Config.StartSpuds,
		owned = {}, -- [potato id] = true: unique potatoes you have summoned
		abilities = {}, -- [ability id] = how many you hold
		best = {}, -- ["mapId|difficultyId"] = most waves cleared

		-- this session only
		mode = "lobby", -- "lobby", "match" or "result"
		match = nil, -- the match you are in (shared with your party)
		result = nil,
		party = nil, -- { leader = player, members = { player, ... } }
		invite = nil, -- { from = player, expires = os.clock() time }
		referrals = 0,
		lastSummon = 0,
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
	local ownedList = {}
	for id in profile.owned do
		table.insert(ownedList, id)
	end
	local ok, err = pcall(function()
		store:SetAsync(keyOf(player), {
			spuds = math.floor(profile.spuds),
			owned = ownedList,
			abilities = profile.abilities,
			best = profile.best,
		})
	end)
	if not ok then
		warn(`Saving {player.Name} failed: {err}`)
	end
	return ok
end

local function notice(player, text, isGood)
	noticeEvent:FireClient(player, text, isGood ~= false)
end

-- Friends who join through your invite link: a brand-new player and the person who invited them both get a gift.
local function rewardReferral(player, profile)
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	local referrerId = ok and joinData and joinData.ReferredByPlayerId
	if not referrerId or referrerId == 0 or referrerId == player.UserId then
		return
	end
	profile.spuds += Config.ReferralJoinerSpuds
	notice(player, `Welcome! Your friend invited you - here are {Config.ReferralJoinerSpuds} Spud Coins.`, true)
	local referrer = Players:GetPlayerByUserId(referrerId)
	local referrerProfile = referrer and profiles[referrer]
	if referrerProfile and referrerProfile.referrals < Config.ReferralInviterMaxPerSession then
		referrerProfile.referrals += 1
		referrerProfile.spuds += Config.ReferralInviterSpuds
		notice(referrer, `{player.DisplayName} joined from your invite! +{Config.ReferralInviterSpuds} Spud Coins.`, true)
	end
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
			profile.spuds = math.max(0, math.floor(tonumber(data.spuds) or profile.spuds))
			if typeof(data.owned) == "table" then
				for _, id in data.owned do
					local def = typeof(id) == "string" and Towers.ById[id]
					if def and def.rarity then
						profile.owned[def.id] = true
					end
				end
			end
			if typeof(data.abilities) == "table" then
				for id, count in data.abilities do
					if Shop.AbilityById[id] and tonumber(count) then
						profile.abilities[id] = math.max(0, math.floor(count))
					end
				end
			end
			if typeof(data.best) == "table" then
				for key, wave in data.best do
					if typeof(key) == "string" and tonumber(wave) then
						profile.best[key] = math.max(0, math.floor(wave))
					end
				end
			end
		elseif data == nil then
			rewardReferral(player, profile) -- only brand-new players count as a referral
		end
	else
		profile.noSave = true
		warn(`Loading {player.Name} failed, their progress will not be saved: {data}`)
	end
	loaded[player] = true
end

-- Helpers -----------------------------------------------------------------------------

local function teleport(player, position)
	local character = player.Character
	if character then
		character:PivotTo(CFrame.new(position + Vector3.new(math.random(-6, 6), 0, math.random(-2, 2))))
	end
end

local function baseMax(match)
	return match.diff.baseHp + match.barricades * Config.BarricadeHp
end

local function barricadeCost(match)
	return math.floor(Config.BarricadeBaseCost * Config.BarricadeCostGrowth ^ match.barricades)
end

-- one player's coin income per second: the free trickle plus their own coin-making potatoes
local function coinsPerSecond(match, player)
	local total = Config.TrickleCoins
	for _, tower in match.towers do
		local def = Towers.ById[tower.id]
		if tower.owner == player and def.kind == "coins" then
			total += def.damage * Towers.LevelMultiplier[tower.level] / def.interval
		end
	end
	return total
end

local function zombieHpForWave(wave)
	return Config.ZombieHpBase * Config.ZombieHpGrowth ^ (wave - 1)
end

local function broadcast(match, text, isGood)
	for _, member in match.players do
		notice(member, text, isGood)
	end
end

-- Parties (lobby groups that play one match together) -------------------------------------------------

local function partyMembersIn(party)
	local list = {}
	for _, member in party.members do
		if member.Parent == Players then
			table.insert(list, member)
		end
	end
	return list
end

local push -- defined below

-- everyone who can see the party / player list is told when it changes
local function pushLobby()
	for _, player in Players:GetPlayers() do
		if ready[player] and getProfile(player).mode ~= "match" then
			push(player)
		end
	end
end

local function leaveParty(player)
	local profile = profiles[player]
	local party = profile and profile.party
	if not party then
		return
	end
	profile.party = nil
	table.remove(party.members, table.find(party.members, player))
	if #party.members <= 1 then
		for _, member in party.members do
			getProfile(member).party = nil -- a party of one is just you again
		end
		party.members = {}
	elseif party.leader == player then
		party.leader = party.members[1]
		for _, member in party.members do
			notice(member, `{party.leader.DisplayName} is now the party leader.`, true)
		end
	end
end

-- Starting and ending a match ----------------------------------------------------------

local function newMatch(map, diff, players)
	local partySize = #players
	local match = {
		map = map,
		diff = diff,
		players = players,
		partySize = partySize,
		hpScale = 1 + Config.PartyHpPerExtraPlayer * (partySize - 1),
		coins = {}, -- [player] = their own match coins
		trickle = {},
		abilityReady = {}, -- [player] = { [ability id] = when it may be used again }
		towers = {}, -- [uid] = { id, level, x, z, owner = player }
		nextTowerId = 1,
		towerNext = {}, -- [uid] = when that tower may act again
		wave = workspace:GetAttribute("StartWave") or 1,
		wavesCleared = 0,
		barricades = 0,
		baseHp = diff.baseHp,
		phase = "break", -- "break" (calm) or "fight"
		breakUntil = os.clock() + Config.FirstWaveDelay,
		zombies = {},
		toSpawn = 0,
		nextZombieAt = 0,
		zombieCounter = 0,
		isBossWave = false,
		frozenUntil = 0,
		events = {}, -- shots and coin payouts since the last update, for the clients to animate
	}
	for _, player in players do
		match.coins[player] = workspace:GetAttribute("StartCoins") or diff.startCoins
		match.trickle[player] = 0
		match.abilityReady[player] = {}
	end
	matches[match] = true
	return match
end

local function bestKey(match)
	return `{match.map.id}|{match.diff.id}`
end

-- pay one player for a finished match and send them to their results screen
local function finishPlayer(player, match, outcome)
	local profile = profiles[player]
	if not profile then
		return
	end
	local scale = match.diff.spud * (1 + Config.PartySpudBonus * (match.partySize - 1))
	local reward = math.floor(match.wavesCleared * Config.SpudsPerWave * scale)
	if outcome == "victory" then
		reward += math.floor(Config.SpudsVictoryBonus * scale)
	end
	profile.spuds += reward
	local key = bestKey(match)
	local previousBest = profile.best[key] or 0
	profile.best[key] = math.max(previousBest, match.wavesCleared)
	profile.result = {
		outcome = outcome, -- "victory", "defeat" or "left"
		mapName = match.map.name,
		difficultyName = match.diff.name,
		wavesCleared = match.wavesCleared,
		wavesTotal = match.diff.waves,
		reward = reward,
		newBest = match.wavesCleared > previousBest,
		partySize = match.partySize,
	}
	profile.match = nil
	profile.mode = "result"
	resultEvent:FireClient(player, profile.result)
	task.spawn(saveProfile, player)
end

-- the whole match is over (won or lost): everyone in it gets their results
local function endMatch(match, outcome)
	matches[match] = nil
	for _, player in table.clone(match.players) do
		finishPlayer(player, match, outcome)
		push(player)
	end
	match.players = {}
end

-- one player walks out of a match that carries on without them
local function leaveMatch(player)
	local profile = profiles[player]
	local match = profile and profile.match
	if not match then
		return
	end
	table.remove(match.players, table.find(match.players, player))
	for uid, tower in match.towers do
		if tower.owner == player then
			match.towers[uid] = nil
			match.towerNext[uid] = nil
		end
	end
	finishPlayer(player, match, "left")
	if #match.players == 0 then
		matches[match] = nil
	else
		broadcast(match, `{player.DisplayName} left the battle.`, false)
	end
end

-- Zombie waves --------------------------------------------------------------------------------

-- pick an enemy type at random, by weight, from the types that have appeared by this wave
local function pickType(wave)
	local total = 0
	for _, t in Config.ZombieTypes do
		if t.from <= wave then
			total += t.weight
		end
	end
	local roll = math.random() * total
	for _, t in Config.ZombieTypes do
		if t.from <= wave then
			roll -= t.weight
			if roll <= 0 then
				return t
			end
		end
	end
	return Config.ZombieTypes[1]
end

local function startWave(match)
	match.phase = "fight"
	match.zombies = {}
	match.zombieCounter = 0
	match.isBossWave = match.wave % Config.BossEvery == 0
	match.toSpawn = Config.ZombiesBase + match.wave * Config.ZombiesPerWave
	if match.isBossWave then
		match.toSpawn += 1 -- the boss comes last
	end
	match.nextZombieAt = os.clock() + 1
end

local function spawnZombie(match)
	match.zombieCounter += 1
	local boss = match.isBossWave and match.toSpawn == 1
	match.toSpawn -= 1
	local kind = pickType(match.wave)
	local baseHp = zombieHpForWave(match.wave) * (boss and Config.BossHpMultiplier or kind.hp)
	local hp = math.max(1, math.ceil(baseHp * match.diff.hp * match.hpScale))
	table.insert(match.zombies, {
		id = match.zombieCounter,
		name = boss and "The Doughpocalypse" or kind.names[math.random(#kind.names)],
		kind = boss and "boss" or kind.kind,
		boss = boss,
		hp = hp,
		maxHp = hp,
		pos = 0, -- how far along the road: 0 is the graveyard, 1 is the base
		speed = Config.ZombieStudSpeed / match.map.length
			* math.min(2, 1 + 0.03 * (match.wave - 1))
			* match.diff.speed
			* (boss and 0.6 or kind.speed),
		damage = boss and (40 + match.wave * 2) or math.ceil((10 + match.wave) * kind.damage),
		-- match coins for the kill, shared out between the players in the match
		reward = math.ceil(baseHp * Config.ZombieRewardRate * match.diff.reward),
		slowUntil = 0,
		slowMul = 1,
	})
	match.nextZombieAt = os.clock() + Config.ZombieSpawnGap
end

-- Towers act on their own timers. A shooter waits (without using up its timer) until a zombie is in range.
local function fireTowers(match, now)
	for uid, tower in match.towers do
		if now >= (match.towerNext[uid] or 0) then
			local def = Towers.ById[tower.id]
			local multiplier = Towers.LevelMultiplier[tower.level]
			local range = def.range * (1 + 0.1 * (tower.level - 1))

			if def.kind == "coins" then
				local amount = math.floor(def.damage * multiplier)
				match.coins[tower.owner] = (match.coins[tower.owner] or 0) + amount
				match.towerNext[uid] = now + def.interval
				table.insert(match.events, { kind = "coin", x = tower.x, z = tower.z, amount = amount, owner = tower.owner.UserId })
			else
				local targets = {}
				for _, zombie in match.zombies do
					if zombie.hp > 0 then
						local at = Path.pointAt(match.map, zombie.pos)
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
						local at = Path.pointAt(match.map, zombie.pos)
						table.insert(match.events, {
							kind = "shot",
							id = def.id,
							fromX = tower.x,
							fromZ = tower.z,
							toX = at.X,
							toZ = at.Z,
						})
					end
					if def.kind == "pulse" then
						table.insert(match.events, { kind = "pulse", id = def.id, x = tower.x, z = tower.z, range = range })
					end
					match.towerNext[uid] = now + def.interval
				end
			end
		end
	end
	-- never let a burst of events grow without bound if the clients fall behind
	while #match.events > 90 do
		table.remove(match.events, 1)
	end
end

local function stepMatch(match, dt)
	local now = os.clock()
	local count = #match.players

	-- a small free trickle of coins for everyone
	for _, player in match.players do
		match.trickle[player] += Config.TrickleCoins * dt
		if match.trickle[player] >= 1 then
			local whole = math.floor(match.trickle[player])
			match.coins[player] += whole
			match.trickle[player] -= whole
		end
	end

	if match.phase == "break" then
		if now >= match.breakUntil then
			startWave(match)
		end
	elseif match.toSpawn > 0 and now >= match.nextZombieAt then
		spawnZombie(match)
	end

	fireTowers(match, now)

	-- zombies walk (slowed ones more slowly), die, or reach the base
	local survivors = {}
	for _, zombie in match.zombies do
		if zombie.hp <= 0 then
			local share = zombie.reward * match.hpScale / count
			for _, player in match.players do
				match.coins[player] += share
			end
			if zombie.boss then
				broadcast(match, `You destroyed {zombie.name}!`, true)
			end
		else
			local speed = zombie.speed
			if now < zombie.slowUntil then
				speed *= zombie.slowMul
			end
			if now < match.frozenUntil then
				speed *= 0.2
			end
			zombie.pos += speed * dt
			if zombie.pos >= 1 then
				match.baseHp -= zombie.damage
			else
				table.insert(survivors, zombie)
			end
		end
	end
	match.zombies = survivors

	if match.phase ~= "fight" then
		return
	end
	if match.baseHp <= 0 then
		endMatch(match, "defeat")
	elseif match.toSpawn == 0 and #match.zombies == 0 then
		local bonus = match.wave * Config.WaveClearBonus
		for _, player in match.players do
			match.coins[player] += bonus
		end
		match.wavesCleared = match.wave
		if match.wave >= match.diff.waves then
			endMatch(match, "victory")
			return
		end
		broadcast(match, `WAVE {match.wave} CLEARED!  +{bonus} coins each`, true)
		match.wave += 1
		for _, def in Towers.List do
			if def.unlockWave == match.wave then
				broadcast(match, `New defender unlocked: {def.id}!`, true)
			end
		end
		local max = baseMax(match)
		match.baseHp = math.min(max, match.baseHp + math.ceil(max * 0.3))
		match.phase = "break"
		match.breakUntil = now + Config.WaveBreakSeconds
	end
end

-- What the client draws ----------------------------------------------------------------------

local function ownedList(profile)
	local list = {}
	for id in profile.owned do
		table.insert(list, id)
	end
	table.sort(list)
	return list
end

local function snapshot(player, events)
	local profile = getProfile(player)
	local state = {
		mode = profile.mode,
		spuds = profile.spuds,
		owned = ownedList(profile),
		abilities = profile.abilities,
		best = profile.best,
		isAdmin = ADMIN_USER_IDS[player.UserId] == true,
	}

	-- the lobby: who else is here, your party, and any invitation waiting for you
	local others = {}
	for _, other in Players:GetPlayers() do
		if other ~= player and ready[other] then
			local otherProfile = getProfile(other)
			table.insert(others, {
				userId = other.UserId,
				name = other.DisplayName,
				mode = otherProfile.mode,
				sameParty = profile.party ~= nil and otherProfile.party == profile.party,
			})
		end
	end
	state.others = others
	if profile.party then
		local members = {}
		for _, member in partyMembersIn(profile.party) do
			table.insert(members, { userId = member.UserId, name = member.DisplayName, mode = getProfile(member).mode })
		end
		state.party = { leaderId = profile.party.leader.UserId, members = members }
	end
	local invite = profile.invite
	if invite and invite.from.Parent == Players and os.clock() < invite.expires then
		state.invite = { fromName = invite.from.DisplayName, secondsLeft = math.ceil(invite.expires - os.clock()) }
	end

	local match = profile.match
	if profile.mode == "match" and match then
		local towerList = {}
		for uid, tower in match.towers do
			table.insert(towerList, {
				uid = uid, id = tower.id, level = tower.level, x = tower.x, z = tower.z,
				mine = tower.owner == player, owner = tower.owner.DisplayName,
			})
		end
		local zombieList = {}
		local now = os.clock()
		for _, zombie in match.zombies do
			table.insert(zombieList, {
				id = zombie.id,
				name = zombie.name,
				kind = zombie.kind,
				boss = zombie.boss,
				pos = zombie.pos,
				hp = zombie.hp,
				maxHp = zombie.maxHp,
				slowed = now < zombie.slowUntil or now < match.frozenUntil,
			})
		end
		local teammates = {}
		for _, member in match.players do
			if member ~= player then
				table.insert(teammates, member.DisplayName)
			end
		end
		state.mapId = match.map.id
		state.difficultyId = match.diff.id
		state.coins = math.floor(match.coins[player] or 0)
		state.income = coinsPerSecond(match, player)
		state.towers = towerList
		state.zombies = zombieList
		state.events = events or {}
		state.teammates = teammates
		state.wave = match.wave
		state.wavesTotal = match.diff.waves
		state.phase = match.phase
		state.remaining = match.toSpawn + #match.zombies
		state.breakIn = math.max(0, math.ceil(match.breakUntil - now))
		state.baseHp = math.max(0, match.baseHp)
		state.baseMax = baseMax(match)
		state.barricades = match.barricades
		state.barricadeCost = barricadeCost(match)
	end
	return state
end

function push(player, events)
	if player.Parent == Players then
		stateEvent:FireClient(player, snapshot(player, events))
	end
end

-- Player actions ------------------------------------------------------------------------------

local function asNumber(value)
	return (typeof(value) == "number" and value == value and math.abs(value) < 1e6) and value or nil
end

local function asUid(value)
	return typeof(value) == "number" and math.floor(value) or nil
end

local function activeMatch(player)
	local profile = getProfile(player)
	return profile, (profile.mode == "match" and profile.match or nil)
end

-- pushes the current state of everyone in a match (after any action that changes the shared battlefield)
local function pushMatch(match)
	for _, member in match.players do
		push(member)
	end
end

startEvent.OnServerEvent:Connect(function(player, mapId, difficultyId)
	local profile = getProfile(player)
	local map = typeof(mapId) == "string" and Path.Maps[mapId]
	local diff = typeof(difficultyId) == "string" and DIFFICULTY_BY_ID[difficultyId]
	if profile.mode ~= "lobby" or not map or not diff or not loaded[player] then
		return
	end

	-- a party plays together, and only its leader can start the battle
	local players = { player }
	if profile.party then
		if profile.party.leader ~= player then
			notice(player, "Only the party leader can start the battle.", false)
			return
		end
		players = partyMembersIn(profile.party)
		for _, member in players do
			local memberProfile = getProfile(member)
			if memberProfile.mode ~= "lobby" or not loaded[member] then
				notice(player, `Waiting for {member.DisplayName} to be back in the lobby.`, false)
				return
			end
		end
	end

	local match = newMatch(map, diff, players)
	for _, member in players do
		local memberProfile = getProfile(member)
		memberProfile.match = match
		memberProfile.mode = "match"
		memberProfile.invite = nil
		teleport(member, map.spawn)
	end
	for _, member in players do
		push(member)
	end
	pushLobby() -- the rest of the lobby sees these players are now busy
end)

leaveEvent.OnServerEvent:Connect(function(player)
	local profile = getProfile(player)
	if profile.mode == "match" then
		leaveMatch(player)
	elseif profile.mode == "result" then
		profile.mode = "lobby"
		profile.result = nil
		teleport(player, LOBBY_SPAWN)
	end
	push(player)
	pushLobby()
end)

placeEvent.OnServerEvent:Connect(function(player, towerId, rawX, rawZ)
	local profile, match = activeMatch(player)
	local def = typeof(towerId) == "string" and Towers.ById[towerId]
	local x, z = asNumber(rawX), asNumber(rawZ)
	if not match or not def or not x or not z then
		return
	end
	local others = {}
	local count = 0
	for _, tower in match.towers do
		table.insert(others, tower)
		count += 1
	end
	local fits, why = Path.canPlace(match.map, x, z, others)
	if not fits then
		notice(player, why, false)
	elseif count >= MAX_TOWERS then
		notice(player, `The battlefield can hold at most {MAX_TOWERS} defenders.`, false)
	elseif def.rarity and not profile.owned[def.id] then
		notice(player, `You haven't summoned {def.id} yet.`, false)
	elseif def.unlockWave > match.wave then
		notice(player, `{def.id} unlocks when you reach wave {def.unlockWave}.`, false)
	elseif match.coins[player] < def.cost then
		notice(player, `{def.id} costs {def.cost} coins.`, false)
	else
		match.coins[player] -= def.cost
		local uid = match.nextTowerId
		match.nextTowerId += 1
		match.towers[uid] = { id = def.id, level = 1, x = x, z = z, owner = player }
		match.towerNext[uid] = os.clock() + 0.5
	end
	pushMatch(match)
end)

upgradeEvent.OnServerEvent:Connect(function(player, rawUid)
	local _, match = activeMatch(player)
	local uid = asUid(rawUid)
	local tower = match and uid and match.towers[uid]
	if not tower then
		return
	end
	if tower.owner ~= player then
		notice(player, `That potato belongs to {tower.owner.DisplayName}.`, false)
		return
	end
	local def = Towers.ById[tower.id]
	local cost = Towers.upgradeCost(def, tower.level)
	if not cost then
		notice(player, `{def.id} is already at the top level.`, false)
	elseif match.coins[player] < cost then
		notice(player, `Upgrading {def.id} costs {cost} coins.`, false)
	else
		match.coins[player] -= cost
		tower.level += 1
		notice(player, `{def.id} is now level {tower.level}!`, true)
	end
	pushMatch(match)
end)

sellEvent.OnServerEvent:Connect(function(player, rawUid)
	local _, match = activeMatch(player)
	local uid = asUid(rawUid)
	local tower = match and uid and match.towers[uid]
	if not tower then
		return
	end
	if tower.owner ~= player then
		notice(player, `That potato belongs to {tower.owner.DisplayName}.`, false)
		return
	end
	local def = Towers.ById[tower.id]
	local refund = math.floor(Towers.invested(def, tower.level) * Config.SellRefund)
	match.towers[uid] = nil
	match.towerNext[uid] = nil
	match.coins[player] += refund
	notice(player, `Sold {def.id} for {refund} coins.`, true)
	pushMatch(match)
end)

barricadeEvent.OnServerEvent:Connect(function(player)
	local _, match = activeMatch(player)
	if not match then
		return
	end
	local cost = barricadeCost(match)
	if match.coins[player] < cost then
		notice(player, `A barricade costs {cost} coins.`, false)
		return
	end
	match.coins[player] -= cost
	match.barricades += 1
	match.baseHp += Config.BarricadeHp
	broadcast(match, `{player.DisplayName} built a barricade! Base health is now {baseMax(match)}.`, true)
	pushMatch(match)
end)

-- abilities you bought in the lobby, used during a match (the effect helps everyone in the match)
abilityEvent.OnServerEvent:Connect(function(player, abilityId)
	local profile, match = activeMatch(player)
	local ability = typeof(abilityId) == "string" and Shop.AbilityById[abilityId]
	if not match or not ability then
		return
	end
	local now = os.clock()
	local readyAt = match.abilityReady[player]
	if (profile.abilities[ability.id] or 0) < 1 then
		notice(player, `You don't have any {ability.name}. Buy more in the lobby shop!`, false)
		return
	elseif now < (readyAt[ability.id] or 0) then
		notice(player, `{ability.name} is recharging.`, false)
		return
	elseif match.phase ~= "fight" and ability.id ~= "coinrain" then
		notice(player, `Save {ability.name} for when zombies are on the road.`, false)
		return
	end
	profile.abilities[ability.id] -= 1
	readyAt[ability.id] = now + Shop.AbilityCooldown

	if ability.id == "meteor" then
		local damage = zombieHpForWave(match.wave) * match.diff.hp * match.hpScale * 0.8
		for _, zombie in match.zombies do
			zombie.hp -= damage
		end
		table.insert(match.events, { kind = "meteor" })
	elseif ability.id == "nuke" then
		for _, zombie in match.zombies do
			zombie.hp = 0 -- everything dies on the next step, and pays out its coins as usual
		end
		table.insert(match.events, { kind = "nuke" })
	elseif ability.id == "freeze" then
		match.frozenUntil = now + Shop.FreezeSeconds
	elseif ability.id == "coinrain" then
		local amount = 100 + 15 * match.wave
		match.coins[player] += amount
		notice(player, `Coin Rain! +{amount} coins`, true)
	elseif ability.id == "shield" then
		match.baseHp = math.min(baseMax(match), match.baseHp + baseMax(match) * 0.4)
	end
	if ability.id ~= "coinrain" and #match.players > 1 then
		broadcast(match, `{player.DisplayName} used {ability.name}!`, true)
	end
	pushMatch(match)
end)

-- the lobby shop
buyEvent.OnServerEvent:Connect(function(player, abilityId)
	local profile = getProfile(player)
	local ability = typeof(abilityId) == "string" and Shop.AbilityById[abilityId]
	if profile.mode ~= "lobby" or not ability or ability.adminOnly or not loaded[player] then
		return
	end
	if profile.spuds < ability.price then
		notice(player, `{ability.name} costs {ability.price} Spud Coins.`, false)
	else
		profile.spuds -= ability.price
		profile.abilities[ability.id] = (profile.abilities[ability.id] or 0) + 1
		notice(player, `Bought {ability.name}!`, true)
	end
	push(player)
end)

-- the summon machine: rolls a rarity by the published weights, then a random potato of that rarity
local uniqueByRarity = {}
for _, def in Towers.Unique do
	uniqueByRarity[def.rarity] = uniqueByRarity[def.rarity] or {}
	table.insert(uniqueByRarity[def.rarity], def)
end

local function rollPotato()
	local total = 0
	for _, rarity in Shop.Rarities do
		if uniqueByRarity[rarity.id] then
			total += rarity.weight
		end
	end
	local roll = math.random() * total
	for _, rarity in Shop.Rarities do
		local pool = uniqueByRarity[rarity.id]
		if pool then
			roll -= rarity.weight
			if roll <= 0 then
				return pool[math.random(#pool)]
			end
		end
	end
	return Towers.Unique[1]
end

summonEvent.OnServerEvent:Connect(function(player, rawCount)
	local profile = getProfile(player)
	if profile.mode ~= "lobby" or not loaded[player] or os.clock() - profile.lastSummon < 0.5 then
		return
	end
	local count = rawCount == 10 and 10 or (rawCount == 1 and 1 or nil)
	if not count then
		return
	end
	local cost = count == 10 and Shop.SummonTenCost or Shop.SummonCost
	if profile.spuds < cost then
		notice(player, `Summoning costs {cost} Spud Coins.`, false)
		return
	end
	profile.lastSummon = os.clock()
	profile.spuds -= cost
	local results = {}
	for _ = 1, count do
		local def = rollPotato()
		local isNew = not profile.owned[def.id]
		local refund = 0
		if isNew then
			profile.owned[def.id] = true
		else
			refund = math.floor(Shop.SummonCost * Shop.DuplicateRefund)
			profile.spuds += refund
		end
		table.insert(results, { id = def.id, new = isNew, refund = refund })
	end
	summonResultEvent:FireClient(player, results)
	push(player)
	task.spawn(saveProfile, player)
end)

-- party invitations ----------------------------------------------------------------------------------

partyInviteEvent.OnServerEvent:Connect(function(player, rawUserId)
	local profile = getProfile(player)
	local target = typeof(rawUserId) == "number" and Players:GetPlayerByUserId(rawUserId)
	if not target or target == player or profile.mode ~= "lobby" or not ready[target] then
		return
	end
	local targetProfile = getProfile(target)
	if profile.party and profile.party.leader ~= player then
		notice(player, "Only the party leader can invite people.", false)
	elseif profile.party and #profile.party.members >= Config.MaxParty then
		notice(player, `A party holds at most {Config.MaxParty} players.`, false)
	elseif targetProfile.mode ~= "lobby" then
		notice(player, `{target.DisplayName} is busy in a battle.`, false)
	elseif targetProfile.party and targetProfile.party == profile.party then
		notice(player, `{target.DisplayName} is already in your party.`, false)
	elseif targetProfile.party then
		notice(player, `{target.DisplayName} is already in another party.`, false)
	else
		targetProfile.invite = { from = player, expires = os.clock() + INVITE_SECONDS }
		notice(player, `Invited {target.DisplayName} to your party.`, true)
		push(target)
		-- the invitation fades after INVITE_SECONDS; tell the client then so it can hide the popup
		task.delay(INVITE_SECONDS + 0.5, function()
			if target.Parent == Players and getProfile(target).invite == targetProfile.invite then
				targetProfile.invite = nil
				push(target)
			end
		end)
	end
end)

partyRespondEvent.OnServerEvent:Connect(function(player, accept)
	local profile = getProfile(player)
	local invite = profile.invite
	profile.invite = nil
	if not invite or invite.from.Parent ~= Players or os.clock() > invite.expires then
		push(player)
		return
	end
	local inviter = invite.from
	local inviterProfile = getProfile(inviter)
	if accept ~= true then
		notice(inviter, `{player.DisplayName} declined your invitation.`, false)
		push(player)
		return
	end
	if profile.mode ~= "lobby" or inviterProfile.mode ~= "lobby" then
		notice(player, "That invitation is no longer available.", false)
	elseif profile.party then
		notice(player, "Leave your current party first.", false)
	elseif inviterProfile.party and #inviterProfile.party.members >= Config.MaxParty then
		notice(player, "That party is full.", false)
	else
		local party = inviterProfile.party
		if not party then
			party = { leader = inviter, members = { inviter } }
			inviterProfile.party = party
		end
		table.insert(party.members, player)
		profile.party = party
		for _, member in party.members do
			notice(member, `{player.DisplayName} joined the party!`, true)
		end
	end
	pushLobby()
end)

partyLeaveEvent.OnServerEvent:Connect(function(player)
	leaveParty(player)
	notice(player, "You left the party.", true)
	pushLobby()
end)

-- the admin panel: give Spud Coins, match coins, unique potatoes or abilities (including the Super Nuke) ------------

adminEvent.OnServerEvent:Connect(function(player, action, target, a, b)
	if not ADMIN_USER_IDS[player.UserId] then
		warn(`{player.Name} tried an admin action without being an admin.`)
		return
	end

	local targets = {}
	if target == "all" then
		for _, other in Players:GetPlayers() do
			if loaded[other] then
				table.insert(targets, other)
			end
		end
	elseif typeof(target) == "number" then
		local other = Players:GetPlayerByUserId(target)
		if other and loaded[other] then
			table.insert(targets, other)
		end
	end
	if #targets == 0 then
		notice(player, "Pick someone to give things to.", false)
		return
	end

	-- anything from 0 up to 1 vigintillion (1e63) in one gift; totals are capped at the same number
	local function wholeNumber(value)
		local number = tonumber(value) or 0
		if number ~= number then
			return 0 -- not a number
		end
		return math.clamp(math.floor(number), 0, MAX_AMOUNT)
	end

	local given = 0
	for _, other in targets do
		local otherProfile = profiles[other]
		local message
		if action == "spuds" then
			local amount = wholeNumber(a)
			if amount > 0 then
				otherProfile.spuds = math.min(MAX_AMOUNT, otherProfile.spuds + amount)
				message = `{amount} Spud Coins`
			end
		elseif action == "coins" then
			local amount = wholeNumber(a)
			local match = otherProfile.mode == "match" and otherProfile.match
			if amount > 0 and match then
				match.coins[other] = math.min(MAX_AMOUNT, match.coins[other] + amount)
				message = `{amount} battle coins`
			end
		elseif action == "potato" then
			if a == "all" then
				for _, def in Towers.Unique do
					otherProfile.owned[def.id] = true
				end
				message = "every unique potato"
			else
				local def = typeof(a) == "string" and Towers.ById[a]
				if def and def.rarity then
					otherProfile.owned[def.id] = true
					message = def.id
				end
			end
		elseif action == "ability" then
			local ability = typeof(a) == "string" and Shop.AbilityById[a]
			local amount = wholeNumber(b)
			if ability and amount > 0 then
				otherProfile.abilities[ability.id] = math.min(MAX_AMOUNT, (otherProfile.abilities[ability.id] or 0) + amount)
				message = `{amount} x {ability.name}`
			end
		end
		if message then
			given += 1
			print(`[admin] {player.Name} gave {other.Name}: {message}`)
			if other ~= player then
				notice(other, `An admin gave you {message}!`, true)
			end
			push(other)
			task.spawn(saveProfile, other)
		end
	end
	if given == 0 then
		notice(player, action == "coins" and "Battle coins only go to players who are in a battle." or "Nothing was given - check the amount.", false)
	else
		notice(player, `Gave it to {given} player{given == 1 and "" or "s"}.`, true)
	end
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
	pushLobby() -- so everyone's player list shows the newcomer
end)

-- The game loop: ten steps a second, a snapshot to each player in a match every other step -----------

task.spawn(function()
	local last = os.clock()
	local ticks = 0
	while true do
		task.wait(TICK)
		local now = os.clock()
		local dt = now - last
		last = now
		ticks += 1
		for match in table.clone(matches) do
			if matches[match] then
				stepMatch(match, dt)
			end
			if matches[match] then
				-- everyone in the match is sent the same animation events, then they are cleared
				local events = match.events
				match.events = {}
				if ticks % 2 == 0 then
					for _, member in match.players do
						push(member, events)
					end
				else
					match.events = events -- not sent this step; keep them for the next one
				end
			end
		end
	end
end)

-- Player lifecycle and saving -------------------------------------------------------------

-- every avatar spawns in the lobby, or on the battlefield if it respawns mid-match
local function watchAvatar(player)
	player.CharacterAdded:Connect(function(character)
		task.defer(function()
			local profile = getProfile(player)
			if profile.mode == "match" and profile.match then
				character:PivotTo(CFrame.new(profile.match.map.spawn))
			else
				character:PivotTo(CFrame.new(LOBBY_SPAWN))
			end
		end)
	end)
end

Players.PlayerAdded:Connect(function(player)
	watchAvatar(player)
	task.spawn(loadProfile, player)
end)
for _, player in Players:GetPlayers() do
	watchAvatar(player)
	task.spawn(loadProfile, player)
end

local function farewell(player)
	local profile = profiles[player]
	if profile and profile.mode == "match" then
		leaveMatch(player) -- still pays out what they earned
	end
	leaveParty(player)
	saveProfile(player)
end

Players.PlayerRemoving:Connect(function(player)
	farewell(player)
	profiles[player] = nil
	loaded[player] = nil
	ready[player] = nil
	task.defer(pushLobby)
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
		farewell(player)
	end
end)
