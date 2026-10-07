local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Towers = require(ReplicatedStorage:WaitForChild("Towers"))
local Path = require(ReplicatedStorage:WaitForChild("Path"))
local Shop = require(ReplicatedStorage:WaitForChild("Shop"))

local stateEvent = remotes:WaitForChild("State")
local readyEvent = remotes:WaitForChild("Ready")
local startEvent = remotes:WaitForChild("StartMatch")
local leaveEvent = remotes:WaitForChild("Leave")
local placeEvent = remotes:WaitForChild("Place")
local upgradeEvent = remotes:WaitForChild("Upgrade")
local sellEvent = remotes:WaitForChild("Sell")
local barricadeEvent = remotes:WaitForChild("Barricade")
local abilityEvent = remotes:WaitForChild("UseAbility")
local buyEvent = remotes:WaitForChild("BuyAbility")
local summonEvent = remotes:WaitForChild("Summon")
local summonResultEvent = remotes:WaitForChild("SummonResult")
local resultEvent = remotes:WaitForChild("Result")
local noticeEvent = remotes:WaitForChild("Notice")
local partyInviteEvent = remotes:WaitForChild("PartyInvite")
local partyRespondEvent = remotes:WaitForChild("PartyRespond")
local partyLeaveEvent = remotes:WaitForChild("PartyLeave")

local function make(class, props, parent)
	local inst = Instance.new(class)
	for key, value in props do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

-- 1234567 -> "1.23M", 12345 -> "12.3K", 999 -> "999"
local function short(n)
	n = math.floor(n)
	if n >= 1e9 then
		return string.format("%.2fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.2fM", n / 1e6)
	elseif n >= 1e4 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(n)
end

local function colorTag(color, text)
	return `<font color="rgb({math.floor(color.R * 255)},{math.floor(color.G * 255)},{math.floor(color.B * 255)})">{text}</font>`
end

-- The two places ---------------------------------------------------------------------------------------
-- The lobby is built far away from the battlefield, so the two never overlap. Everything is drawn locally.

local currentMode = nil -- "lobby", "match" or "result"
local currentMap = nil -- the Path map being drawn on the battlefield
local LOBBY = Vector3.new(1000, 0, 0)

local world = make("Folder", { Name = "Battlefield" }, workspace)
local lobbyWorld = make("Folder", { Name = "Lobby" }, workspace)
local groundFolder = make("Folder", { Name = "Ground" }, world)

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		p[key] = value
	end
	p.Parent = props.Parent or world
	return p
end

-- Daylight, with natural colours -----------------------------------------------------------------

Lighting.ClockTime = 14
Lighting.Brightness = 2.4
Lighting.Ambient = Color3.fromRGB(110, 110, 110)
Lighting.OutdoorAmbient = Color3.fromRGB(125, 125, 125)
Lighting.ColorShift_Top = Color3.new(0, 0, 0)
Lighting.ColorShift_Bottom = Color3.new(0, 0, 0)
Lighting.EnvironmentDiffuseScale = 0.4
Lighting.EnvironmentSpecularScale = 0.2
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or make("Atmosphere", {}, Lighting)
atmosphere.Density = 0.12
atmosphere.Offset = 0
atmosphere.Color = Color3.fromRGB(199, 215, 235)
atmosphere.Decay = Color3.fromRGB(180, 190, 200)
atmosphere.Glare = 0
atmosphere.Haze = 0.4

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

local baseplate = workspace:FindFirstChild("Baseplate")
if baseplate then
	for _, child in baseplate:GetChildren() do
		if child:IsA("Texture") or child:IsA("Decal") then
			child:Destroy()
		end
	end
end

-- The battlefield: ground, road, base wall, graveyard, trees. Rebuilt whenever a match on a new map starts. ----

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local baseWall, baseColor, baseEnd, baseDir
local fence = nil
local fenceCount = 0

-- barricade fence: one more post for every barricade you build
local function setFence(count)
	if count == fenceCount or not fence then
		return
	end
	fenceCount = count
	fence:ClearAllChildren()
	local shown = math.min(count, 10)
	local across = Vector3.new(-baseDir.Z, 0, baseDir.X)
	for i = 1, shown do
		local offset = -8 + (i - 0.5) * (16 / shown)
		part({
			Name = "FencePost",
			Size = Vector3.new(1, 5, 1),
			Position = baseEnd + baseDir * 1.2 + across * offset + Vector3.new(0, 2.5, 0),
			Material = Enum.Material.Wood,
			Color = Color3.fromRGB(139, 94, 60),
			Parent = fence,
		})
	end
end

local function buildBattlefield(map)
	world:ClearAllChildren()
	groundFolder = make("Folder", { Name = "Ground" }, world)
	rayParams.FilterDescendantsInstances = { groundFolder }
	fence = make("Folder", { Name = "Fence" }, world)
	fenceCount = 0

	part({
		Name = "Lawn",
		Size = Vector3.new(900, 1, 900),
		Position = Vector3.new(0, -0.45, 0),
		Material = map.lawnMaterial,
		Color = map.lawn,
		CanCollide = true,
		CanQuery = true,
		Parent = groundFolder,
	})

	-- the road: one flat strip per straight section, each a little long so the corners fill in
	for i = 1, #map.points - 1 do
		local a, b = map.points[i], map.points[i + 1]
		local length = (b - a).Magnitude
		local mid = (a + b) / 2 + Vector3.new(0, 0.1, 0)
		part({
			Name = "Road",
			Size = Vector3.new(length + Path.HalfWidth * 2, 0.2, Path.HalfWidth * 2),
			CFrame = CFrame.lookAt(mid, mid + (b - a)) * CFrame.Angles(0, math.pi / 2, 0),
			Material = map.roadMaterial,
			Color = map.road,
			CanQuery = true,
			Parent = groundFolder,
		})
	end

	-- the base: a stone wall just past the end of the road, with a sign
	local last = #map.points
	baseEnd = map.points[last]
	baseDir = (map.points[last] - map.points[last - 1]).Unit
	local center = baseEnd + baseDir * 4.5 + Vector3.new(0, 4.5, 0)
	baseWall = part({
		Name = "BaseWall",
		Size = Vector3.new(18, 9, 3),
		CFrame = CFrame.lookAt(center, center + baseDir),
		Material = Enum.Material.Brick,
		Color = Color3.fromRGB(176, 150, 130),
		CanCollide = true,
	})
	local baseSign = make("BillboardGui", {
		Size = UDim2.fromOffset(180, 40),
		StudsOffset = Vector3.new(0, 7.5, 0),
		AlwaysOnTop = false,
	}, baseWall)
	make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(255, 220, 120),
		TextStrokeTransparency = 0,
		Text = "YOUR BASE",
	}, baseSign)
	baseColor = baseWall.Color

	-- the graveyard where zombies come from
	local rng = Random.new(map.seed)
	local graveyard = map.points[1]
	for _ = 1, 16 do
		local height = rng:NextNumber(3, 6)
		part({
			Name = "Tombstone",
			Size = Vector3.new(rng:NextNumber(2, 3), height, 0.8),
			Position = Vector3.new(graveyard.X + rng:NextNumber(6, 22), height / 2, graveyard.Z + rng:NextNumber(-16, 16)),
			Orientation = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-25, 25), rng:NextNumber(-6, 6)),
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(150, 155, 160),
		})
	end
	part({
		Name = "GraveyardEarth",
		Size = Vector3.new(30, 0.15, 36),
		Position = Vector3.new(graveyard.X + 14, 0.08, graveyard.Z),
		Material = Enum.Material.Mud,
		Color = Color3.fromRGB(105, 80, 60),
	})

	-- trees around the edge
	for _ = 1, 40 do
		local x = rng:NextNumber(-130, 130)
		local z = rng:NextNumber(-90, 90)
		if math.abs(x) > 70 or math.abs(z) > 46 then
			local height = rng:NextNumber(10, 22)
			part({
				Name = "TreeTrunk",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(height, 1.6, 1.6),
				CFrame = CFrame.new(x, height / 2, z) * CFrame.Angles(0, 0, math.pi / 2),
				Material = Enum.Material.Wood,
				Color = Color3.fromRGB(110, 78, 52),
				CanCollide = true,
			})
			local d = rng:NextNumber(8, 13)
			part({
				Name = "TreeCrown",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(d, d, d),
				Position = Vector3.new(x, height + d * 0.25, z),
				Material = Enum.Material.Grass,
				Color = Color3.fromHSV(rng:NextNumber(map.treeHue[1], map.treeHue[2]), 0.62, rng:NextNumber(0.5, 0.65)),
			})
		end
	end
end

-- Camera: in the lobby, and by default in a match, it follows your avatar. In a match you can switch to a
-- fixed bird's-eye view, which shakes a little when the base is hit. ----------------------------------------

local camera = workspace.CurrentCamera
local shakeUntil = 0
local mapView = workspace:GetAttribute("StartMapView") == true -- false: walk around with your avatar; true: the fixed bird's-eye view
player.CameraMaxZoomDistance = 90
local function holdCamera()
	camera = workspace.CurrentCamera
	if currentMode ~= "match" or not mapView then
		if camera.CameraType == Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Custom
			local character = player.Character
			if character then
				camera.CameraSubject = character:FindFirstChildOfClass("Humanoid")
			end
		end
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 60
	local look = CFrame.lookAt(Vector3.new(4, 108, 64), Vector3.new(4, 0, 4))
	if os.clock() < shakeUntil then
		local strength = (shakeUntil - os.clock()) * 1.2
		look = look * CFrame.new(math.random() * strength - strength / 2, math.random() * strength - strength / 2, 0)
	end
	camera.CFrame = look
end

-- Screens ------------------------------------------------------------------------------------------------
-- gui: the HUD during a match.  lobbyGui: the lobby menus.  topGui: messages and the results screen, over both.

local playerGui = player:WaitForChild("PlayerGui")
local gui = make("ScreenGui", { Name = "MatchHUD", ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false }, playerGui)
local lobbyGui = make("ScreenGui", { Name = "LobbyHUD", ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false }, playerGui)
local topGui = make("ScreenGui", { Name = "Overlay", ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 10 }, playerGui)

local topShade = make("Frame", {
	Size = UDim2.new(1, 0, 0, 156),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.35,
	BorderSizePixel = 0,
}, gui)
make("UIGradient", {
	Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
	Rotation = 90,
}, topShade)

make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 6),
	Size = UDim2.fromOffset(700, 32),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextSize = 26,
	TextColor3 = Color3.fromRGB(190, 255, 150),
	TextStrokeTransparency = 0.3,
	Text = "SPUD DEFENCE",
}, gui)

local coinsLabel = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 38),
	Size = UDim2.fromOffset(500, 36),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextSize = 30,
	TextColor3 = Color3.fromRGB(255, 235, 140),
	TextStrokeTransparency = 0.3,
	Text = "0 coins",
}, gui)

local statsLabel = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 74),
	Size = UDim2.fromOffset(780, 20),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	TextColor3 = Color3.new(1, 1, 1),
	TextStrokeTransparency = 0.4,
	Text = "",
}, gui)

local waveLabel = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 96),
	Size = UDim2.fromOffset(780, 20),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	TextColor3 = Color3.fromRGB(190, 255, 170),
	TextStrokeTransparency = 0.4,
	Text = "",
}, gui)

local baseBarBack = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 122),
	Size = UDim2.fromOffset(460, 24),
	BackgroundColor3 = Color3.fromRGB(15, 25, 20),
	BorderSizePixel = 0,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, baseBarBack)
make("UIStroke", { Color = Color3.fromRGB(120, 200, 110), Thickness = 2 }, baseBarBack)
local baseBar = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(90, 220, 110),
	BorderSizePixel = 0,
}, baseBarBack)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, baseBar)
local baseText = make("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextSize = 15,
	TextColor3 = Color3.new(1, 1, 1),
	TextStrokeTransparency = 0.4,
	ZIndex = 2,
	Text = "",
}, baseBarBack)


-- Towers (3D) ------------------------------------------------------------------------------------------

local towerModels = {} -- [uid] = { model, id, level }
local currentTowers = {} -- [uid] = { id, level, x, z }

local function addEyes(model, center, radius)
	for _, side in { -1, 1 } do
		part({
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * radius * 0.5,
			Position = center + Vector3.new(radius * 0.8, radius * 0.25, side * radius * 0.38),
			Color = Color3.new(1, 1, 1),
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
		part({
			Name = "Pupil",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * radius * 0.22,
			Position = center + Vector3.new(radius * 0.99, radius * 0.25, side * radius * 0.38),
			Color = Color3.new(0, 0, 0),
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
	end
end

local function addAccessory(model, def, top, radius)
	local id = def.style
	if id == "Verity" then
		part({ Name = "Crown", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, radius, radius),
			CFrame = CFrame.new(top + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = Color3.fromRGB(255, 215, 60), Material = Enum.Material.Metal, Parent = model })
		for i = 0, 2 do
			local a = i / 3 * math.pi * 2
			part({ Name = "CrownJewel", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.6,
				Position = top + Vector3.new(math.cos(a) * radius * 0.35, 0.9, math.sin(a) * radius * 0.35),
				Color = Color3.fromRGB(255, 240, 120), Material = Enum.Material.Neon, Parent = model })
		end
	elseif id == "Lovity" then
		for _, side in { -1, 1 } do
			part({ Name = "HeartLobe", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.3,
				Position = top + Vector3.new(0, 1.1, side * 0.55), Color = Color3.fromRGB(255, 70, 120),
				Material = Enum.Material.Neon, Parent = model })
		end
		part({ Name = "HeartPoint", Size = Vector3.new(1, 1, 1.3),
			CFrame = CFrame.new(top + Vector3.new(0, 0.6, 0)) * CFrame.Angles(math.rad(45), 0, 0),
			Color = Color3.fromRGB(255, 70, 120), Material = Enum.Material.Neon, Parent = model })
	elseif id == "Falsity" then
		part({ Name = "HatBrim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, radius * 1.3, radius * 1.3),
			CFrame = CFrame.new(top + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = Color3.fromRGB(80, 50, 120), Parent = model })
		part({ Name = "HatTop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.8, 1.4, 1.4),
			CFrame = CFrame.new(top + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = Color3.fromRGB(80, 50, 120), Parent = model })
	elseif id == "Gaiety" then
		local hat = Instance.new("WedgePart")
		hat.Name = "PartyHat"
		hat.Anchored = true
		hat.CanCollide = false
		hat.CanQuery = false
		hat.Size = Vector3.new(1.6, 2.6, 1.6)
		hat.CFrame = CFrame.new(top + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, math.rad(90), 0)
		hat.Color = Color3.fromRGB(255, 90, 160)
		hat.Material = Enum.Material.SmoothPlastic
		hat.Parent = model
		part({ Name = "HatBall", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.7,
			Position = top + Vector3.new(0, 2.6, 0), Color = Color3.fromRGB(255, 240, 120),
			Material = Enum.Material.Neon, Parent = model })
	elseif id == "Vanity" then
		part({ Name = "Mirror", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, radius * 1.5, radius * 1.5),
			CFrame = CFrame.new(top + Vector3.new(-radius * 0.9, -radius * 0.3, 0)) * CFrame.Angles(0, math.pi / 2, 0),
			Color = Color3.fromRGB(220, 235, 255), Material = Enum.Material.Glass, Reflectance = 0.5, Parent = model })
	elseif id == "Gravity" then
		part({ Name = "Orbit", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.35, radius * 2.4, radius * 2.4),
			CFrame = CFrame.new(top - Vector3.new(0, radius * 0.9, 0)) * CFrame.Angles(math.rad(20), 0, math.pi / 2),
			Color = Color3.fromRGB(110, 255, 190), Material = Enum.Material.Neon, Transparency = 0.25, Parent = model })
	elseif id == "Hot" then
		part({ Name = "FlameBase", Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.8, 1.6),
			Position = top + Vector3.new(0, 0.8, 0), Color = Color3.fromRGB(255, 110, 30), Material = Enum.Material.Neon, Parent = model })
		part({ Name = "FlameTip", Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 1.5, 0.9),
			Position = top + Vector3.new(0, 1.9, 0), Color = Color3.fromRGB(255, 220, 70), Material = Enum.Material.Neon, Parent = model })
	elseif id == "Gold" then
		part({ Name = "Coin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 2, 2),
			CFrame = CFrame.new(top + Vector3.new(0, 1.3, 0)) * CFrame.Angles(0, math.rad(90), math.rad(90)),
			Color = Color3.fromRGB(255, 215, 60), Material = Enum.Material.Metal, Parent = model })
	elseif id == "Fry" then
		part({ Name = "PaperCone", Size = Vector3.new(1.8, 0.8, 1.8), Position = top + Vector3.new(0, 0.3, 0),
			Color = Color3.fromRGB(235, 225, 200), Parent = model })
		for i = -2, 2 do
			part({ Name = "Fry", Size = Vector3.new(0.3, 1.5, 0.3),
				CFrame = CFrame.new(top + Vector3.new(0, 1.3, i * 0.35)) * CFrame.Angles(i * 0.3, 0, (i % 2) * 0.25),
				Color = Color3.fromRGB(245, 205, 90), Parent = model })
		end
		part({ Name = "Barrel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 0.7, 0.7),
			Position = top - Vector3.new(0, radius * 0.5, 0) + Vector3.new(radius + 0.8, 0, 0),
			Color = Color3.fromRGB(70, 70, 80), Material = Enum.Material.Metal, Parent = model })
	elseif id == "Sniper" then
		part({ Name = "LongBarrel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(6, 0.5, 0.5),
			Position = top - Vector3.new(0, radius * 0.45, 0) + Vector3.new(radius + 2.4, 0, 0),
			Color = Color3.fromRGB(45, 45, 55), Material = Enum.Material.Metal, Parent = model })
		part({ Name = "Scope", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.8, 0.55, 0.55),
			Position = top - Vector3.new(0, radius * 0.1, 0) + Vector3.new(radius * 0.9, 0.0, 0),
			Color = Color3.fromRGB(30, 30, 40), Material = Enum.Material.Metal, Parent = model })
		part({ Name = "Cap", Size = Vector3.new(radius * 1.4, 0.5, radius * 1.4), Position = top + Vector3.new(0, 0.1, 0),
			Color = Color3.fromRGB(60, 80, 55), Parent = model })
	end
end


-- `parent` is where the model goes: the battlefield by default, or the lobby for the statues in the Hall of Spuds
local function buildTower(uid, x, z, def, level, parent, ownerName)
	local base = Vector3.new(x, 0.2, z)
	local model = Instance.new("Model")
	model.Name = `Tower{uid}`
	local radius = 2 + (level - 1) * 0.3
	part({
		Name = "Pedestal",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 5.2, 5.2),
		CFrame = CFrame.new(base + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(70, 70, 82),
		Material = Enum.Material.Slate,
		Parent = model,
	})
	-- unique (summoned) potatoes stand in a glowing ring in their rarity colour
	local rarity = def.rarity and Shop.RarityById[def.rarity]
	if rarity then
		part({
			Name = "RarityRing",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.15, 7.4, 7.4),
			CFrame = CFrame.new(base + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = rarity.color,
			Material = Enum.Material.Neon,
			Parent = model,
		})
	end
	local center = base + Vector3.new(0, 0.8 + radius, 0)
	part({
		Name = "Body",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(radius * 2.2, radius * 1.9, radius * 2),
		Position = center,
		Color = Color3.fromRGB(205, 160, 100):Lerp(def.color, 0.3), -- a potato, tinted with the defender's colour
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	addEyes(model, center, radius)
	addAccessory(model, def, center + Vector3.new(0, radius, 0), radius)

	local tag = make("BillboardGui", {
		Size = UDim2.fromOffset(150, 34),
		StudsOffset = Vector3.new(0, radius + 4.2, 0),
		AlwaysOnTop = true,
		MaxDistance = 140,
	}, model:FindFirstChild("Body"))
	make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = rarity and rarity.color or Color3.new(1, 1, 1),
		TextStrokeTransparency = 0,
		Text = `{def.id} {string.rep("*", level)}` .. (ownerName and `  ({ownerName})` or ""),
	}, tag)
	model.Parent = parent or world
	return model
end

local zombieViews = {} -- [id] = { model, torsoParts, x, targetX, z, hpFill, hp, colors }

local ZOMBIE_GREEN = Color3.fromRGB(110, 170, 90)
local zombieKinds = {}
for _, kind in Config.ZombieTypes do
	zombieKinds[kind.kind] = kind
end
local ZOMBIE_SLOWED = Color3.fromRGB(110, 150, 230)

local function buildZombie(zombie)
	local model = Instance.new("Model")
	model.Name = `Zombie{zombie.id}`
	local kind = zombieKinds[zombie.kind]
	local tint = zombie.boss and Color3.fromRGB(170, 70, 100) or (kind and kind.color or ZOMBIE_GREEN)
	local shirt = zombie.boss and Color3.fromRGB(70, 30, 60) or Color3.fromRGB(80, 70, 110)
	local colored = {}

	local function limb(props, isSkin)
		local p = part(props)
		p.Parent = model
		table.insert(colored, { part = p, skin = isSkin })
		return p
	end

	-- the model is built around (0, 0, 0) and moved with PivotTo; it faces -X, toward your base
	local torso = limb({ Name = "Torso", Size = Vector3.new(1.4, 2.4, 2), Position = Vector3.new(0, 2.6, 0), Color = shirt }, false)
	limb({ Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.8, Position = Vector3.new(-0.1, 4.5, 0), Color = tint }, true)
	for _, side in { -1, 1 } do
		limb({ Name = "Arm", Size = Vector3.new(2.2, 0.7, 0.7), Position = Vector3.new(-1.6, 3.2, side * 1.2), Color = tint }, true)
		limb({ Name = "Leg", Size = Vector3.new(0.8, 1.9, 0.8), Position = Vector3.new(0, 0.95, side * 0.55), Color = Color3.fromRGB(60, 60, 80) }, false)
		part({ Name = "Eye", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.55,
			Position = Vector3.new(-0.85, 4.7, side * 0.4), Color = Color3.fromRGB(255, 240, 120),
			Material = Enum.Material.Neon, Parent = model })
	end
	model.PrimaryPart = torso
	if zombie.boss then
		for _, side in { -1, 1 } do
			part({ Name = "Horn", Size = Vector3.new(0.5, 1.4, 0.5),
				CFrame = CFrame.new(-0.1, 5.7, side * 0.7) * CFrame.Angles(side * 0.4, 0, 0),
				Color = Color3.fromRGB(240, 230, 200), Parent = model })
		end
	end

	-- health bar above the head
	local gui3d = make("BillboardGui", {
		Size = UDim2.fromOffset(70, 9),
		StudsOffset = Vector3.new(0, 4.2, 0),
		AlwaysOnTop = true,
		MaxDistance = 160,
	}, torso)
	local back = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0 }, gui3d)
	local fill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 80, 80), BorderSizePixel = 0 }, back)

	model.Parent = world
	local scale = zombie.boss and 1.8 or (kind and kind.scale or 1)
	if scale ~= 1 then
		model:ScaleTo(scale)
	end
	return { model = model, fill = fill, colored = colored, tint = tint, hp = zombie.hp }
end

-- Effects: shots and coin pops ---------------------------------------------------------------------------

local function playShot(event)
	local def = Towers.ById[event.id]
	local from = Vector3.new(event.fromX, 4, event.fromZ)
	local to = Vector3.new(event.toX, 3, event.toZ)
	local bolt = part({
		Name = "Bolt",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1.1,
		Position = from,
		Color = def and def.color or Color3.new(1, 1, 1),
		Material = Enum.Material.Neon,
	})
	local tween = TweenService:Create(bolt, TweenInfo.new(0.16, Enum.EasingStyle.Linear), { Position = to })
	tween.Completed:Connect(function()
		bolt:Destroy()
	end)
	tween:Play()
end

local function playPulse(event)
	local def = Towers.ById[event.id]
	local ring = part({
		Name = "Pulse",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 2, 2),
		CFrame = CFrame.new(event.x, 0.5, event.z) * CFrame.Angles(0, 0, math.pi / 2),
		Color = def and def.color or Color3.new(1, 1, 1),
		Material = Enum.Material.Neon,
		Transparency = 0.4,
	})
	local d = event.range * 2
	local tween = TweenService:Create(ring, TweenInfo.new(0.4), { Size = Vector3.new(0.3, d, d), Transparency = 1 })
	tween.Completed:Connect(function()
		ring:Destroy()
	end)
	tween:Play()
end

local function playCoin(event)
	local center = Vector3.new(event.x, 0, event.z)
	local anchor = part({ Name = "CoinPop", Size = Vector3.one * 0.2, Position = center + Vector3.new(0, 7, 0), Transparency = 1 })
	local label = make("BillboardGui", { Size = UDim2.fromOffset(90, 34), StudsOffset = Vector3.new(0, 0, 0), AlwaysOnTop = true }, anchor)
	local text = make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(255, 235, 120),
		TextStrokeTransparency = 0.1,
		Text = `+{event.amount}`,
	}, label)
	TweenService:Create(label, TweenInfo.new(0.9), { StudsOffset = Vector3.new(0, 4, 0) }):Play()
	local fade = TweenService:Create(text, TweenInfo.new(0.9), { TextTransparency = 1, TextStrokeTransparency = 1 })
	fade.Completed:Connect(function()
		anchor:Destroy()
	end)
	fade:Play()
end


-- Match controls (2D over the scene) -------------------------------------------------------------------------

local shopButtons = {} -- [towerId] = { button, cost, lock, stroke }
local armed = nil -- the tower type picked in the shop, waiting for a spot on the ground
local selectedUid = nil -- a placed tower you clicked, for upgrade / sell
local upgradeButton, sellButton, barricadeButton, refreshSelection -- defined below

-- the defender shop: your default potatoes, then any unique potatoes you have summoned. It scrolls.
local shopScroll = make("ScrollingFrame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -14),
	Size = UDim2.fromOffset(5 * 112 + 8, 3 * 74),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
}, gui)
make("UIGridLayout", {
	CellSize = UDim2.fromOffset(104, 66),
	CellPadding = UDim2.fromOffset(8, 8),
	FillDirectionMaxCells = 5,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Top,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, shopScroll)

local rarityRank = {}
for index, rarity in Shop.Rarities do
	rarityRank[rarity.id] = index
end

local shopSignature = nil
local function buildShop(ownedList)
	local signature = table.concat(ownedList, ",")
	if signature == shopSignature then
		return
	end
	shopSignature = signature
	for _, child in shopScroll:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	table.clear(shopButtons)
	if armed and not Towers.ById[armed] then
		armed = nil
	end

	local defs = {}
	for _, def in Towers.List do
		table.insert(defs, def)
	end
	local uniques = {}
	for _, id in ownedList do
		if Towers.ById[id] then
			table.insert(uniques, Towers.ById[id])
		end
	end
	table.sort(uniques, function(a, b)
		if rarityRank[a.rarity] ~= rarityRank[b.rarity] then
			return rarityRank[a.rarity] < rarityRank[b.rarity]
		end
		return a.id < b.id
	end)
	for _, def in uniques do
		table.insert(defs, def)
	end

	for order, def in defs do
		local rarity = def.rarity and Shop.RarityById[def.rarity]
		local accent = rarity and rarity.color or def.color
		local button = make("TextButton", {
			LayoutOrder = order,
			BackgroundColor3 = def.color:Lerp(Color3.fromRGB(20, 25, 22), 0.55),
			Text = "",
			AutoButtonColor = false,
		}, shopScroll)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, button)
		local stroke = make("UIStroke", { Thickness = 2, Color = accent }, button)
		make("TextLabel", {
			Position = UDim2.fromOffset(0, 4),
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			TextScaled = true,
			TextColor3 = rarity and rarity.color or Color3.new(1, 1, 1),
			Text = def.id,
		}, button)
		make("TextLabel", {
			Position = UDim2.fromOffset(0, 24),
			Size = UDim2.new(1, 0, 0, 16),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextScaled = true,
			TextColor3 = Color3.fromRGB(215, 225, 215),
			Text = def.role,
		}, button)
		local costLabel = make("TextLabel", {
			Position = UDim2.fromOffset(0, 42),
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			TextSize = 16,
			TextColor3 = Color3.fromRGB(255, 235, 140),
			Text = `{def.cost} coins`,
		}, button)
		local lock = make("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(10, 14, 12),
			BackgroundTransparency = 0.2,
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			TextColor3 = Color3.fromRGB(200, 200, 200),
			Text = `Unlocks at\nwave {def.unlockWave}`,
			Visible = false,
			ZIndex = 4,
		}, button)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, lock)
		button.Activated:Connect(function()
			if lock.Visible then
				return
			end
			armed = if armed == def.id then nil else def.id
			selectedUid = nil
			refreshSelection()
		end)
		shopButtons[def.id] = { button = button, cost = costLabel, lock = lock, stroke = stroke }
	end
end

-- one-use abilities bought in the lobby shop
local abilityButtons = {} -- [abilityId] = button
for index, ability in Shop.AllAbilities do
	local button = make("TextButton", {
		Position = UDim2.fromOffset(14, 70 + (index - 1) * 54),
		Size = UDim2.fromOffset(210, 48),
		BackgroundColor3 = ability.color:Lerp(Color3.fromRGB(20, 25, 22), 0.5),
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = Color3.new(1, 1, 1),
		Text = ability.name,
		AutoButtonColor = false,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, button)
	make("UIStroke", { Thickness = 2, Color = ability.color }, button)
	button.Activated:Connect(function()
		abilityEvent:FireServer(ability.id)
	end)
	abilityButtons[ability.id] = button
end

local function bigButton(text, color, anchorX, xOffset, yOffset)
	local button = make("TextButton", {
		AnchorPoint = Vector2.new(anchorX, 1),
		Position = UDim2.new(anchorX == 1 and 1 or 0.5, xOffset, 1, yOffset),
		Size = UDim2.fromOffset(250, 52),
		BackgroundColor3 = color,
		Font = Enum.Font.GothamBlack,
		TextSize = 17,
		TextColor3 = Color3.new(1, 1, 1),
		Text = text,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 14) }, button)
	return button
end
upgradeButton = bigButton("UPGRADE", Color3.fromRGB(70, 130, 220), 0.5, -130, -244)
sellButton = bigButton("SELL", Color3.fromRGB(200, 60, 80), 0.5, 130, -244)
barricadeButton = bigButton("BARRICADE", Color3.fromRGB(70, 130, 90), 1, -14, -244)
upgradeButton.Visible = false
sellButton.Visible = false


local viewButton = make("TextButton", {
	Position = UDim2.fromOffset(14, 14),
	Size = UDim2.fromOffset(210, 44),
	BackgroundColor3 = Color3.fromRGB(60, 90, 160),
	Font = Enum.Font.GothamBlack,
	TextSize = 16,
	TextColor3 = Color3.new(1, 1, 1),
	Text = mapView and "WALK AROUND  (M)" or "MAP VIEW  (M)",
	ZIndex = 5,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, viewButton)
local function toggleView()
	mapView = not mapView
	viewButton.Text = mapView and "WALK AROUND  (M)" or "MAP VIEW  (M)"
end
viewButton.Activated:Connect(toggleView)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.M and currentMode == "match" then
		toggleView()
	end
end)

local leaveButton = make("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 14),
	Size = UDim2.fromOffset(170, 44),
	BackgroundColor3 = Color3.fromRGB(170, 60, 70),
	Font = Enum.Font.GothamBlack,
	TextSize = 16,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "LEAVE MATCH",
	ZIndex = 5,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, leaveButton)
leaveButton.Activated:Connect(function()
	leaveEvent:FireServer()
end)

-- messages float over everything, in the lobby too
local toast = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 160),
	Size = UDim2.fromOffset(720, 44),
	BackgroundColor3 = Color3.fromRGB(15, 28, 22),
	BackgroundTransparency = 0.1,
	Font = Enum.Font.GothamBold,
	TextSize = 17,
	TextWrapped = true,
	TextColor3 = Color3.new(1, 1, 1),
	Visible = false,
	ZIndex = 10,
}, topGui)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, toast)
local toastToken = 0
local function showToast(text, isGood, seconds)
	toastToken += 1
	local token = toastToken
	toast.Text = text
	toast.TextColor3 = isGood and Color3.fromRGB(140, 240, 160) or Color3.fromRGB(255, 130, 130)
	toast.Visible = true
	task.delay(seconds or 3.5, function()
		if toastToken == token then
			toast.Visible = false
		end
	end)
end
noticeEvent.OnClientEvent:Connect(showToast)

-- Selection markers and mouse picking -------------------------------------------------------------------------

local markers = make("Folder", { Name = "Markers" }, workspace)

-- flat discs on the ground: one shows the range of the tower you selected, one previews where a new tower would go
local function makeDisc(name, color)
	return part({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, 2, 2),
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = 1,
		Parent = markers,
	})
end
local function placeDisc(disc, x, z, radius, transparency)
	disc.Size = Vector3.new(0.12, radius * 2, radius * 2)
	disc.CFrame = CFrame.new(x, 0.35, z) * CFrame.Angles(0, 0, math.pi / 2)
	disc.Transparency = transparency
end
local selectionMarker = makeDisc("SelectionMarker", Color3.fromRGB(255, 240, 120))
local hoverMarker = makeDisc("HoverMarker", Color3.fromRGB(150, 255, 150))
local hoverFootprint = makeDisc("HoverFootprint", Color3.fromRGB(150, 255, 150))

-- the point on the ground under a screen position
local function groundAt(position)
	local ray = workspace.CurrentCamera:ViewportPointToRay(position.X, position.Y)
	local result = workspace:Raycast(ray.Origin, ray.Direction * 600, rayParams)
	return result and result.Position or nil
end

local function towerNear(point)
	local best, bestDistance = nil, 3.5
	for uid, tower in currentTowers do
		local distance = (Vector3.new(tower.x, 0, tower.z) - Vector3.new(point.X, 0, point.Z)).Magnitude
		if distance < bestDistance then
			best, bestDistance = uid, distance
		end
	end
	return best
end

local function towerList()
	local list = {}
	for _, tower in currentTowers do
		table.insert(list, tower)
	end
	return list
end

function refreshSelection()
	for id, entry in shopButtons do
		entry.stroke.Thickness = id == armed and 5 or 2
	end
	local tower = selectedUid and currentTowers[selectedUid]
	-- you can look at a teammate's potato (to see its range) but only upgrade or sell your own
	upgradeButton.Visible = tower ~= nil and tower.mine == true
	sellButton.Visible = tower ~= nil and tower.mine == true
	if tower then
		local def = Towers.ById[tower.id]
		local cost = Towers.upgradeCost(def, tower.level)
		upgradeButton.Text = cost and `UPGRADE to Lv {tower.level + 1} ({short(cost)})` or `{def.id} is max level`
		sellButton.Text = `SELL (+{short(Towers.invested(def, tower.level) * Config.SellRefund)})`
		if def.range > 0 then
			placeDisc(selectionMarker, tower.x, tower.z, def.range * (1 + 0.1 * (tower.level - 1)), 0.7)
		else
			selectionMarker.Transparency = 1
		end
	else
		selectionMarker.Transparency = 1
	end
end

local function onGroundClicked(point)
	local near = towerNear(point)
	if near then
		selectedUid = if selectedUid == near then nil else near
		armed = nil
	elseif armed then
		placeEvent:FireServer(armed, point.X, point.Z)
	else
		selectedUid = nil
	end
	refreshSelection()
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or currentMode ~= "match" then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local point = groundAt(UserInputService:GetMouseLocation())
		if point then
			onGroundClicked(point)
		end
	elseif input.UserInputType == Enum.UserInputType.Touch then
		local inset = GuiService:GetGuiInset()
		local point = groundAt(Vector2.new(input.Position.X, input.Position.Y + inset.Y))
		if point then
			onGroundClicked(point)
		end
	end
end)

upgradeButton.Activated:Connect(function()
	if selectedUid then
		upgradeEvent:FireServer(selectedUid)
	end
end)
sellButton.Activated:Connect(function()
	if selectedUid then
		sellEvent:FireServer(selectedUid)
		selectedUid = nil
		refreshSelection()
	end
end)
barricadeButton.Activated:Connect(function()
	barricadeEvent:FireServer()
end)


-- The lobby (3D) ---------------------------------------------------------------------------------------------
-- A plaza with three stations (play gate, ability shop, summon machine) and a hall showing every potato.

local openPanel -- defined with the lobby menus below

local function lobbyPart(props)
	props.Parent = props.Parent or lobbyWorld
	return part(props)
end

local function sign(target, text, color, width, offsetY)
	local board = make("BillboardGui", {
		Size = UDim2.fromOffset(width or 280, 56),
		StudsOffset = Vector3.new(0, offsetY or 6, 0),
		AlwaysOnTop = false,
		MaxDistance = 220,
	}, target)
	make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = color or Color3.fromRGB(255, 235, 140),
		TextStrokeTransparency = 0,
		Text = text,
	}, board)
end

local function station(target, action, object, panelName)
	local prompt = make("ProximityPrompt", {
		ActionText = action,
		ObjectText = object,
		HoldDuration = 0,
		MaxActivationDistance = 18,
		RequiresLineOfSight = false,
	}, target)
	prompt.Triggered:Connect(function()
		openPanel(panelName)
	end)
end

local uniqueHall = make("Folder", { Name = "UniqueHall" }, lobbyWorld)
local hallSignature = nil
-- the second row of the hall: the unique potatoes you have summoned
local function refreshUniqueHall(ownedList)
	local signature = table.concat(ownedList, ",")
	if signature == hallSignature then
		return
	end
	hallSignature = signature
	uniqueHall:ClearAllChildren()
	local defs = {}
	for _, id in ownedList do
		if Towers.ById[id] then
			table.insert(defs, Towers.ById[id])
		end
	end
	table.sort(defs, function(a, b)
		if rarityRank[a.rarity] ~= rarityRank[b.rarity] then
			return rarityRank[a.rarity] < rarityRank[b.rarity]
		end
		return a.id < b.id
	end)
	for index, def in defs do
		local x = -45 + (index - 1) * (90 / math.max(1, #Towers.Unique - 1))
		buildTower(`unique{index}`, LOBBY.X + x, LOBBY.Z + 52, def, 1, uniqueHall)
	end
end

local function buildLobby()
	local center = LOBBY
	lobbyPart({
		Name = "LobbyGround",
		Size = Vector3.new(300, 1, 300),
		Position = center + Vector3.new(0, -0.5, 0),
		Material = Enum.Material.Grass,
		Color = Color3.fromRGB(110, 172, 92),
		CanCollide = true,
		CanQuery = true,
	})
	lobbyPart({
		Name = "Plaza",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 120, 120),
		CFrame = CFrame.new(center + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Material = Enum.Material.Cobblestone,
		Color = Color3.fromRGB(196, 186, 170),
		CanCollide = true,
	})

	local title = lobbyPart({ Name = "Title", Size = Vector3.one, Position = center + Vector3.new(0, 30, -30), Transparency = 1 })
	sign(title, "SPUD DEFENCE", Color3.fromRGB(190, 255, 150), 520, 0)

	-- PLAY: a glowing gate on the left
	local gate = center + Vector3.new(-44, 0, -6)
	for _, z in { -8, 8 } do
		lobbyPart({ Name = "GatePillar", Size = Vector3.new(3, 16, 3), Position = gate + Vector3.new(0, 8, z),
			Material = Enum.Material.Slate, Color = Color3.fromRGB(120, 125, 140), CanCollide = true })
	end
	local lintel = lobbyPart({ Name = "GateTop", Size = Vector3.new(3, 3, 19), Position = gate + Vector3.new(0, 17.5, 0),
		Material = Enum.Material.Slate, Color = Color3.fromRGB(120, 125, 140), CanCollide = true })
	sign(lintel, "PLAY", Color3.fromRGB(150, 220, 255), 240, 4)
	local portal = lobbyPart({ Name = "Portal", Size = Vector3.new(1, 15, 13), Position = gate + Vector3.new(0, 8, 0),
		Material = Enum.Material.Neon, Color = Color3.fromRGB(110, 200, 255), Transparency = 0.35 })
	station(portal, "Choose a battle", "Battle Gate", "play")

	-- ABILITY SHOP: a stall on the right
	local stall = center + Vector3.new(44, 0, -6)
	local counter = lobbyPart({ Name = "Counter", Size = Vector3.new(5, 4, 20), Position = stall + Vector3.new(0, 2, 0),
		Material = Enum.Material.Wood, Color = Color3.fromRGB(139, 94, 60), CanCollide = true })
	lobbyPart({ Name = "StallBack", Size = Vector3.new(1, 13, 20), Position = stall + Vector3.new(4, 6.5, 0),
		Material = Enum.Material.Wood, Color = Color3.fromRGB(110, 76, 50), CanCollide = true })
	local awning = lobbyPart({ Name = "Awning", Size = Vector3.new(11, 0.6, 22), Position = stall + Vector3.new(1, 13, 0),
		Material = Enum.Material.Fabric, Color = Color3.fromRGB(220, 70, 70) })
	sign(awning, "ABILITY SHOP", Color3.fromRGB(255, 200, 120), 300, 4)
	for _, z in { -10, 10 } do
		lobbyPart({ Name = "StallPost", Size = Vector3.new(1, 13, 1), Position = stall + Vector3.new(-3.5, 6.5, z),
			Material = Enum.Material.Wood, Color = Color3.fromRGB(139, 94, 60), CanCollide = true })
	end
	for index, ability in Shop.Abilities do
		lobbyPart({ Name = "ShopItem", Shape = Enum.PartType.Ball, Size = Vector3.one * 2.2,
			Position = stall + Vector3.new(0, 5.3, -7.5 + (index - 1) * 5), Material = Enum.Material.Neon, Color = ability.color })
	end
	station(counter, "Browse abilities", "Ability Shop", "shop")

	-- SUMMON: a golden machine at the back
	local machine = center + Vector3.new(0, 0, -50)
	lobbyPart({ Name = "MachineBase", Size = Vector3.new(14, 3, 14), Position = machine + Vector3.new(0, 1.5, 0),
		Material = Enum.Material.Slate, Color = Color3.fromRGB(90, 90, 110), CanCollide = true })
	local orb = lobbyPart({ Name = "SummonOrb", Shape = Enum.PartType.Ball, Size = Vector3.one * 10,
		Position = machine + Vector3.new(0, 9, 0), Material = Enum.Material.Metal, Color = Color3.fromRGB(255, 205, 60) })
	lobbyPart({ Name = "OrbRingA", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 15, 15),
		CFrame = CFrame.new(machine + Vector3.new(0, 9, 0)) * CFrame.Angles(0, 0, math.pi / 2 + 0.4),
		Material = Enum.Material.Neon, Color = Color3.fromRGB(120, 230, 255), Transparency = 0.3 })
	lobbyPart({ Name = "OrbRingB", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 15, 15),
		CFrame = CFrame.new(machine + Vector3.new(0, 9, 0)) * CFrame.Angles(0, 0, math.pi / 2 - 0.4),
		Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 120, 220), Transparency = 0.3 })
	sign(orb, "SUMMON POTATOES", Color3.fromRGB(255, 230, 120), 360, 9)
	station(orb, "Summon potatoes", "Summon Machine", "summon")

	-- the hall: every default potato in a row
	local hall = lobbyPart({ Name = "HallSign", Size = Vector3.one, Position = center + Vector3.new(0, 14, 34), Transparency = 1 })
	sign(hall, "THE HALL OF SPUDS", Color3.fromRGB(255, 255, 255), 340, 0)
	for index, def in Towers.List do
		local x = -45 + (index - 1) * (90 / (#Towers.List - 1))
		buildTower(`hall{index}`, center.X + x, center.Z + 34, def, 1, lobbyWorld)
	end
	local uniqueSign = lobbyPart({ Name = "UniqueSign", Size = Vector3.one, Position = center + Vector3.new(0, 14, 52), Transparency = 1 })
	sign(uniqueSign, "YOUR SUMMONED POTATOES", Color3.fromRGB(255, 220, 130), 380, 0)

	-- a ring of trees round the edge
	local rng = Random.new(5)
	for index = 1, 22 do
		local angle = index / 22 * math.pi * 2
		local radius = rng:NextNumber(85, 110)
		local x, z = center.X + math.cos(angle) * radius, center.Z + math.sin(angle) * radius
		local height = rng:NextNumber(12, 20)
		lobbyPart({ Name = "TreeTrunk", Shape = Enum.PartType.Cylinder, Size = Vector3.new(height, 1.8, 1.8),
			CFrame = CFrame.new(x, height / 2, z) * CFrame.Angles(0, 0, math.pi / 2),
			Material = Enum.Material.Wood, Color = Color3.fromRGB(110, 78, 52), CanCollide = true })
		local d = rng:NextNumber(9, 14)
		lobbyPart({ Name = "TreeCrown", Shape = Enum.PartType.Ball, Size = Vector3.one * d,
			Position = Vector3.new(x, height + d * 0.25, z), Material = Enum.Material.Grass,
			Color = Color3.fromHSV(rng:NextNumber(0.28, 0.36), 0.62, rng:NextNumber(0.5, 0.65)) })
	end
end
buildLobby()


-- The lobby menus (2D) ---------------------------------------------------------------------------------------

-- the latest lobby data from the server
local lobby = { spuds = 0, owned = {}, ownedList = {}, abilities = {}, best = {} }

local function addCorner(instance, radius)
	make("UICorner", { CornerRadius = UDim.new(0, radius or 10) }, instance)
end

local function textLabel(parent, props)
	local defaults = {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 16,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}
	for key, value in props do
		defaults[key] = value
	end
	return make("TextLabel", defaults, parent)
end

local function textButton(parent, props)
	local defaults = {
		Font = Enum.Font.GothamBlack,
		TextSize = 17,
		TextColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = true,
	}
	for key, value in props do
		defaults[key] = value
	end
	local button = make("TextButton", defaults, parent)
	addCorner(button, 12)
	return button
end

local spudsLabel = textLabel(lobbyGui, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 10),
	Size = UDim2.fromOffset(520, 44),
	Font = Enum.Font.GothamBlack,
	TextSize = 30,
	TextColor3 = Color3.fromRGB(255, 235, 140),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextStrokeTransparency = 0.3,
	Text = "SPUD COINS: 0",
})
textLabel(lobbyGui, {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -12),
	Size = UDim2.fromOffset(900, 22),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextStrokeTransparency = 0.4,
	TextSize = 15,
	Text = "Walk up to the glowing PLAY gate, the ABILITY SHOP or the SUMMON machine - or use the buttons on the left. Win matches to earn Spud Coins!",
})

local panels = {}
local function newPanel(name, title, height)
	local frame = make("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(720, height),
		BackgroundColor3 = Color3.fromRGB(28, 38, 32),
		BackgroundTransparency = 0.03,
		ZIndex = 5,
		Visible = false,
	}, lobbyGui)
	addCorner(frame, 16)
	make("UIStroke", { Color = Color3.fromRGB(120, 200, 110), Thickness = 2 }, frame)
	textLabel(frame, {
		Position = UDim2.fromOffset(20, 14),
		Size = UDim2.new(1, -80, 0, 38),
		Font = Enum.Font.GothamBlack,
		TextSize = 26,
		TextColor3 = Color3.fromRGB(190, 255, 150),
		Text = title,
	})
	local close = textButton(frame, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = Color3.fromRGB(170, 60, 70),
		Text = "X",
	})
	close.Activated:Connect(function()
		frame.Visible = false
	end)
	panels[name] = frame
	return frame
end

function openPanel(name)
	local wasOpen = panels[name] and panels[name].Visible
	for _, frame in panels do
		frame.Visible = false
	end
	if panels[name] and not wasOpen then
		panels[name].Visible = true
	end
end

for index, entry in { { "play", "PLAY" }, { "shop", "ABILITY SHOP" }, { "summon", "SUMMON" } } do
	local button = textButton(lobbyGui, {
		Position = UDim2.fromOffset(14, 14 + (index - 1) * 54),
		Size = UDim2.fromOffset(190, 46),
		BackgroundColor3 = Color3.fromRGB(60, 90, 160),
		Text = entry[2],
	})
	button.Activated:Connect(function()
		openPanel(entry[1])
	end)
end

-- PLAY: choose a map and a difficulty -------------------------------------------------------------------------

local playPanel = newPanel("play", "CHOOSE YOUR BATTLE", 520)
local selMapId, selDiffId = "meadow", "normal"
local mapCards, diffCards = {}, {}
local playInfo

local function refreshPlay()
	for id, card in mapCards do
		card.stroke.Thickness = id == selMapId and 5 or 1
		card.button.BackgroundColor3 = id == selMapId and card.base:Lerp(Color3.new(1, 1, 1), 0.25) or card.base
		card.stroke.Color = id == selMapId and Color3.fromRGB(255, 240, 120) or Color3.fromRGB(90, 110, 100)
	end
	for id, card in diffCards do
		card.stroke.Thickness = id == selDiffId and 5 or 1
		card.button.BackgroundColor3 = id == selDiffId and card.base:Lerp(Color3.new(1, 1, 1), 0.25) or card.base
		card.stroke.Color = id == selDiffId and Color3.fromRGB(255, 240, 120) or Color3.fromRGB(90, 110, 100)
	end
	local map = Path.Maps[selMapId]
	local diff
	for _, d in Config.Difficulties do
		if d.id == selDiffId then
			diff = d
		end
	end
	local best = lobby.best[`{selMapId}|{selDiffId}`] or 0
	playInfo.Text = `<b>{map.name}</b> on <b>{colorTag(diff.color, diff.name)}</b>\n`
		.. `Your best: wave {best} of {diff.waves}     Earn {math.floor(Config.SpudsPerWave * diff.spud)} Spud Coins per wave cleared, `
		.. `+{math.floor(Config.SpudsVictoryBonus * diff.spud)} for winning.`
end

for index, map in Path.List do
	local card = make("TextButton", {
		Position = UDim2.fromOffset(20 + (index - 1) * 232, 64),
		Size = UDim2.fromOffset(220, 170),
		BackgroundColor3 = map.lawn:Lerp(Color3.fromRGB(25, 30, 28), 0.5),
		Text = "",
		AutoButtonColor = false,
	}, playPanel)
	addCorner(card, 12)
	local stroke = make("UIStroke", { Thickness = 1 }, card)
	-- a little picture: grass with a road stripe through it
	local swatch = make("Frame", { Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 0, 52), BackgroundColor3 = map.lawn, BorderSizePixel = 0 }, card)
	addCorner(swatch, 8)
	make("Frame", { Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 16), BackgroundColor3 = map.road, BorderSizePixel = 0 }, swatch)
	textLabel(card, { Position = UDim2.fromOffset(12, 68), Size = UDim2.new(1, -24, 0, 24), Font = Enum.Font.GothamBlack, TextSize = 19, Text = map.name })
	textLabel(card, { Position = UDim2.fromOffset(12, 94), Size = UDim2.new(1, -24, 0, 44), TextSize = 14, TextWrapped = true, Text = map.blurb })
	textLabel(card, { Position = UDim2.fromOffset(12, 142), Size = UDim2.new(1, -24, 0, 20), TextSize = 13, TextColor3 = Color3.fromRGB(200, 215, 200), Text = `Road: {math.floor(map.length)} studs long` })
	card.Activated:Connect(function()
		selMapId = map.id
		refreshPlay()
	end)
	mapCards[map.id] = { stroke = stroke, button = card, base = card.BackgroundColor3 }
end

for index, diff in Config.Difficulties do
	local card = make("TextButton", {
		Position = UDim2.fromOffset(20 + (index - 1) * 232, 250),
		Size = UDim2.fromOffset(220, 96),
		BackgroundColor3 = diff.color:Lerp(Color3.fromRGB(25, 30, 28), 0.7),
		Text = "",
		AutoButtonColor = false,
	}, playPanel)
	addCorner(card, 12)
	local stroke = make("UIStroke", { Thickness = 1 }, card)
	textLabel(card, { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 26), Font = Enum.Font.GothamBlack, TextSize = 22, TextColor3 = diff.color, Text = diff.name })
	textLabel(card, { Position = UDim2.fromOffset(12, 36), Size = UDim2.new(1, -24, 0, 22), TextSize = 13, TextWrapped = true, Text = diff.blurb })
	textLabel(card, {
		Position = UDim2.fromOffset(12, 62), Size = UDim2.new(1, -24, 0, 30), TextSize = 13, TextWrapped = true,
		TextColor3 = Color3.fromRGB(200, 215, 200), Text = `{diff.waves} waves  |  base {diff.baseHp} HP  |  rewards x{diff.spud}`,
	})
	card.Activated:Connect(function()
		selDiffId = diff.id
		refreshPlay()
	end)
	diffCards[diff.id] = { stroke = stroke, button = card, base = card.BackgroundColor3 }
end

playInfo = textLabel(playPanel, {
	Position = UDim2.fromOffset(20, 360),
	Size = UDim2.new(1, -40, 0, 64),
	RichText = true,
	TextSize = 17,
	TextWrapped = true,
	Text = "",
})
local startButton = textButton(playPanel, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 438),
	Size = UDim2.fromOffset(340, 58),
	BackgroundColor3 = Color3.fromRGB(70, 160, 90),
	TextSize = 22,
	Text = "START BATTLE",
})
startButton.Activated:Connect(function()
	panels.play.Visible = false
	startEvent:FireServer(selMapId, selDiffId)
end)
refreshPlay()

-- ABILITY SHOP ----------------------------------------------------------------------------------------------

local shopPanel = newPanel("shop", "ABILITY SHOP", 470)
local abilityRows = {} -- [id] = { owned, buy }
textLabel(shopPanel, {
	Position = UDim2.fromOffset(20, 52),
	Size = UDim2.new(1, -40, 0, 22),
	TextSize = 14,
	TextColor3 = Color3.fromRGB(200, 215, 200),
	Text = "One-use abilities. Buy them here, then tap them on the left of the screen during a battle.",
})
for index, ability in Shop.Abilities do
	local row = make("Frame", {
		Position = UDim2.fromOffset(20, 84 + (index - 1) * 88),
		Size = UDim2.new(1, -40, 0, 80),
		BackgroundColor3 = ability.color:Lerp(Color3.fromRGB(25, 30, 28), 0.75),
		BorderSizePixel = 0,
	}, shopPanel)
	addCorner(row, 12)
	make("UIStroke", { Color = ability.color, Thickness = 2 }, row)
	textLabel(row, { Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -240, 0, 26), Font = Enum.Font.GothamBlack, TextSize = 21, TextColor3 = ability.color, Text = ability.name })
	textLabel(row, { Position = UDim2.fromOffset(14, 36), Size = UDim2.new(1, -240, 0, 40), TextSize = 14, TextWrapped = true, Text = ability.desc })
	local owned = textLabel(row, {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -150, 0, 28), Size = UDim2.fromOffset(80, 24),
		Font = Enum.Font.GothamBold, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Center, Text = "x0",
	})
	local buy = textButton(row, {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(128, 52),
		BackgroundColor3 = Color3.fromRGB(70, 160, 90), TextSize = 16, Text = `BUY  {ability.price}`,
	})
	buy.Activated:Connect(function()
		buyEvent:FireServer(ability.id)
	end)
	abilityRows[ability.id] = { owned = owned, buy = buy, price = ability.price }
end

-- SUMMON: unique potatoes ------------------------------------------------------------------------------------

local summonPanel = newPanel("summon", "SUMMON POTATOES", 640)

-- the odds shown here are computed from the very weights the server rolls with
local function oddsText()
	local total = 0
	local perRarity = {}
	for _, def in Towers.Unique do
		perRarity[def.rarity] = (perRarity[def.rarity] or 0) + 1
	end
	for _, rarity in Shop.Rarities do
		if perRarity[rarity.id] then
			total += rarity.weight
		end
	end
	local lines = { "<b>ODDS (per summon)</b>" }
	for _, rarity in Shop.Rarities do
		local count = perRarity[rarity.id]
		if count then
			local chance = rarity.weight / total * 100
			table.insert(lines, `{colorTag(rarity.color, `<b>{rarity.name}</b>`)}  {string.format("%.0f", chance)}%  ({string.format("%.1f", chance / count)}% each, {count} potato{count == 1 and "" or "es"})`)
		end
	end
	table.insert(lines, "")
	table.insert(lines, `Summoning a potato you already own refunds {math.floor(Shop.DuplicateRefund * 100)}% of the price. Spud Coins are earned by playing - there is no real money here.`)
	return table.concat(lines, "\n")
end
textLabel(summonPanel, {
	Position = UDim2.fromOffset(20, 60), Size = UDim2.fromOffset(330, 230), RichText = true, TextSize = 15, TextWrapped = true, Text = oddsText(),
})
textLabel(summonPanel, {
	Position = UDim2.fromOffset(370, 60), Size = UDim2.fromOffset(330, 24), Font = Enum.Font.GothamBold, TextSize = 16, Text = "LAST SUMMON",
})
local summonResults = textLabel(summonPanel, {
	Position = UDim2.fromOffset(370, 86), Size = UDim2.fromOffset(330, 206), RichText = true, TextSize = 14, TextWrapped = true,
	Text = "Nothing yet - give the machine a spin!",
})
local summonOne = textButton(summonPanel, {
	Position = UDim2.fromOffset(20, 304), Size = UDim2.fromOffset(330, 56), BackgroundColor3 = Color3.fromRGB(190, 120, 40),
	TextSize = 20, Text = `SUMMON x1   ({Shop.SummonCost})`,
})
local summonTen = textButton(summonPanel, {
	Position = UDim2.fromOffset(370, 304), Size = UDim2.fromOffset(330, 56), BackgroundColor3 = Color3.fromRGB(160, 80, 190),
	TextSize = 20, Text = `SUMMON x10   ({Shop.SummonTenCost})`,
})
summonOne.Activated:Connect(function()
	summonEvent:FireServer(1)
end)
summonTen.Activated:Connect(function()
	summonEvent:FireServer(10)
end)

local collectionTitle = textLabel(summonPanel, {
	Position = UDim2.fromOffset(20, 376), Size = UDim2.new(1, -40, 0, 24), Font = Enum.Font.GothamBold, TextSize = 17, Text = "YOUR COLLECTION",
})
local collection = make("Frame", { Position = UDim2.fromOffset(20, 404), Size = UDim2.new(1, -40, 0, 220), BackgroundTransparency = 1 }, summonPanel)
make("UIGridLayout", { CellSize = UDim2.fromOffset(160, 50), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, collection)
local collectionTiles = {} -- [id] = { frame, name }
local sortedUniques = table.clone(Towers.Unique)
table.sort(sortedUniques, function(a, b)
	if rarityRank[a.rarity] ~= rarityRank[b.rarity] then
		return rarityRank[a.rarity] > rarityRank[b.rarity] -- rarest first
	end
	return a.id < b.id
end)
for order, def in sortedUniques do
	local rarity = Shop.RarityById[def.rarity]
	local tile = make("Frame", { LayoutOrder = order, BackgroundColor3 = Color3.fromRGB(35, 45, 40), BorderSizePixel = 0 }, collection)
	addCorner(tile, 8)
	local stroke = make("UIStroke", { Color = rarity.color, Thickness = 2 }, tile)
	local name = textLabel(tile, {
		Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -16, 0, 22), Font = Enum.Font.GothamBold, TextSize = 14, TextScaled = true, Text = "???",
	})
	textLabel(tile, {
		Position = UDim2.fromOffset(8, 28), Size = UDim2.new(1, -16, 0, 18), TextSize = 13, TextColor3 = rarity.color, Text = rarity.name,
	})
	collectionTiles[def.id] = { frame = tile, name = name, stroke = stroke, def = def }
end

local function refreshLobbyUi()
	spudsLabel.Text = `SPUD COINS: {short(lobby.spuds)}`
	for id, row in abilityRows do
		row.owned.Text = `x{lobby.abilities[id] or 0}`
		row.buy.BackgroundColor3 = lobby.spuds >= row.price and Color3.fromRGB(70, 160, 90) or Color3.fromRGB(90, 90, 90)
	end
	summonOne.BackgroundColor3 = lobby.spuds >= Shop.SummonCost and Color3.fromRGB(190, 120, 40) or Color3.fromRGB(90, 90, 90)
	summonTen.BackgroundColor3 = lobby.spuds >= Shop.SummonTenCost and Color3.fromRGB(160, 80, 190) or Color3.fromRGB(90, 90, 90)
	local count = 0
	for id, tile in collectionTiles do
		local have = lobby.owned[id] == true
		count += have and 1 or 0
		tile.name.Text = have and id or "???"
		tile.frame.BackgroundColor3 = have and Color3.fromRGB(45, 62, 52) or Color3.fromRGB(30, 34, 32)
		tile.stroke.Transparency = have and 0 or 0.65
	end
	collectionTitle.Text = `YOUR COLLECTION   ({count} / {#Towers.Unique})`
	refreshPlay()
	refreshUniqueHall(lobby.ownedList)
end

summonResultEvent.OnClientEvent:Connect(function(results)
	local lines = {}
	for _, entry in results do
		local def = Towers.ById[entry.id]
		local rarity = def and Shop.RarityById[def.rarity]
		if def and rarity then
			if entry.new then
				table.insert(lines, `<b>NEW!</b> {colorTag(rarity.color, `<b>{def.id}</b> ({rarity.name})`)}`)
			else
				table.insert(lines, `{colorTag(rarity.color, `{def.id} ({rarity.name})`)} - duplicate, +{entry.refund}`)
			end
		end
	end
	summonResults.Text = table.concat(lines, "\n")
end)

-- The results screen after a match ------------------------------------------------------------------------------

local resultFrame = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(520, 340),
	BackgroundColor3 = Color3.fromRGB(24, 34, 28),
	Visible = false,
	ZIndex = 20,
}, topGui)
addCorner(resultFrame, 18)
make("UIStroke", { Color = Color3.fromRGB(255, 235, 140), Thickness = 3 }, resultFrame)
local resultTitle = textLabel(resultFrame, {
	Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 56), Font = Enum.Font.GothamBlack, TextSize = 44,
	TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 21, Text = "",
})
local resultBody = textLabel(resultFrame, {
	Position = UDim2.fromOffset(30, 96), Size = UDim2.new(1, -60, 0, 140), TextSize = 20, RichText = true, TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 21, Text = "",
})
local resultButton = textButton(resultFrame, {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -26), Size = UDim2.fromOffset(320, 58),
	BackgroundColor3 = Color3.fromRGB(70, 160, 90), TextSize = 22, ZIndex = 21, Text = "BACK TO LOBBY",
})
resultButton.Activated:Connect(function()
	resultFrame.Visible = false
	leaveEvent:FireServer()
end)

resultEvent.OnClientEvent:Connect(function(result)
	local titles = {
		victory = { "VICTORY!", Color3.fromRGB(140, 240, 160) },
		defeat = { "DEFEAT", Color3.fromRGB(255, 130, 130) },
		left = { "BATTLE ENDED", Color3.fromRGB(255, 235, 140) },
	}
	local title = titles[result.outcome] or titles.left
	resultTitle.Text = title[1]
	resultTitle.TextColor3 = title[2]
	resultBody.Text = `{result.mapName} - {result.difficultyName}\n`
		.. `Waves cleared: <b>{result.wavesCleared}</b> of {result.wavesTotal}\n`
		.. `You earned <b>{colorTag(Color3.fromRGB(255, 235, 140), `{result.reward} Spud Coins`)}</b>`
		.. (result.partySize > 1 and `\nCo-op battle with {result.partySize} players: bonus included!` or "")
		.. (result.newBest and "\n<b>New personal best!</b>" or "")
	resultFrame.Visible = true
end)


-- Co-op: parties, invitations, and inviting friends ------------------------------------------------------------

local SocialService = game:GetService("SocialService")

local partyPanel = newPanel("party", "PARTY  (CO-OP)", 590)
textLabel(partyPanel, {
	Position = UDim2.fromOffset(20, 52), Size = UDim2.new(1, -40, 0, 44), TextSize = 14, TextWrapped = true,
	TextColor3 = Color3.fromRGB(200, 215, 200),
	Text = `Team up with up to {Config.MaxParty} players: you share one base and one set of waves, but each of you keeps your own coins and potatoes. Zombies get tougher with each extra player, and everyone earns a Spud Coin bonus. The party leader picks the battle and starts it for the whole party.`,
})
local partyMembersLabel = textLabel(partyPanel, {
	Position = UDim2.fromOffset(20, 108), Size = UDim2.new(1, -210, 0, 90), RichText = true, TextSize = 16, TextWrapped = true, Text = "",
})
local leavePartyButton = textButton(partyPanel, {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 112), Size = UDim2.fromOffset(160, 44),
	BackgroundColor3 = Color3.fromRGB(170, 60, 70), TextSize = 15, Text = "LEAVE PARTY",
})
leavePartyButton.Activated:Connect(function()
	partyLeaveEvent:FireServer()
end)
textLabel(partyPanel, {
	Position = UDim2.fromOffset(20, 206), Size = UDim2.new(1, -40, 0, 24), Font = Enum.Font.GothamBold, TextSize = 17, Text = "PLAYERS IN THE GAME",
})
local playerList = make("ScrollingFrame", {
	Position = UDim2.fromOffset(20, 236), Size = UDim2.new(1, -40, 0, 336), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 6, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, partyPanel)
make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, playerList)

local playerListSignature = nil
local function refreshPartyUi()
	local party = lobby.party
	local others = lobby.others or {}
	local iAmLeader = party == nil or party.leaderId == player.UserId
	local canInvite = iAmLeader and (party == nil or #party.members < Config.MaxParty)

	if party then
		local lines = { `<b>YOUR PARTY</b>  ({#party.members} / {Config.MaxParty})` }
		for _, member in party.members do
			local tags = (member.userId == party.leaderId and "  [leader]" or "") .. (member.mode ~= "lobby" and "  (in a battle)" or "")
			table.insert(lines, `{member.name}{tags}`)
		end
		partyMembersLabel.Text = table.concat(lines, "\n")
	else
		partyMembersLabel.Text = "<b>YOUR PARTY</b>\nYou are not in a party. Invite someone below to start one!"
	end
	leavePartyButton.Visible = party ~= nil

	-- the play menu's start button says what will happen
	if party and not iAmLeader then
		startButton.Text = "WAITING FOR PARTY LEADER"
		startButton.BackgroundColor3 = Color3.fromRGB(90, 90, 90)
	elseif party then
		startButton.Text = `START CO-OP BATTLE ({#party.members} players)`
		startButton.BackgroundColor3 = Color3.fromRGB(70, 160, 90)
	else
		startButton.Text = "START BATTLE"
		startButton.BackgroundColor3 = Color3.fromRGB(70, 160, 90)
	end

	-- rebuild the player list only when something in it changed
	local parts = { tostring(canInvite) }
	for _, other in others do
		table.insert(parts, `{other.userId}:{other.mode}:{tostring(other.sameParty)}`)
	end
	local signature = table.concat(parts, ",")
	if signature == playerListSignature then
		return
	end
	playerListSignature = signature
	for _, child in playerList:GetChildren() do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	if #others == 0 then
		textLabel(playerList, {
			Size = UDim2.new(1, 0, 0, 60), TextSize = 15, TextWrapped = true, TextColor3 = Color3.fromRGB(200, 215, 200),
			Text = "Nobody else is here yet. Use INVITE FRIENDS on the left to bring someone along!",
		})
	end
	for order, other in others do
		local row = make("Frame", { LayoutOrder = order, Size = UDim2.new(1, -8, 0, 46), BackgroundColor3 = Color3.fromRGB(38, 50, 44), BorderSizePixel = 0 }, playerList)
		addCorner(row, 10)
		textLabel(row, { Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -200, 0, 20), Font = Enum.Font.GothamBold, TextSize = 17, Text = other.name })
		local status = other.sameParty and "In your party" or (other.mode == "match" and "In a battle" or "In the lobby")
		textLabel(row, { Position = UDim2.fromOffset(14, 26), Size = UDim2.new(1, -200, 0, 16), TextSize = 13, TextColor3 = Color3.fromRGB(190, 205, 190), Text = status })
		if other.mode == "lobby" and not other.sameParty and canInvite then
			local invite = textButton(row, {
				AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(150, 34),
				BackgroundColor3 = Color3.fromRGB(70, 130, 90), TextSize = 15, Text = "INVITE",
			})
			invite.Activated:Connect(function()
				partyInviteEvent:FireServer(other.userId)
			end)
		end
	end
end

local partyNav = textButton(lobbyGui, {
	Position = UDim2.fromOffset(14, 14 + 3 * 54), Size = UDim2.fromOffset(190, 46), BackgroundColor3 = Color3.fromRGB(60, 90, 160), Text = "PARTY / CO-OP",
})
partyNav.Activated:Connect(function()
	openPanel("party")
end)

-- friends who join from your invite link: both of you get Spud Coins (see ReferralJoinerSpuds in Config)
local inviteFriends = textButton(lobbyGui, {
	Position = UDim2.fromOffset(14, 14 + 4 * 54), Size = UDim2.fromOffset(190, 46), BackgroundColor3 = Color3.fromRGB(190, 120, 40),
	TextSize = 14, Text = `INVITE FRIENDS  (+{Config.ReferralInviterSpuds})`,
})
inviteFriends.Activated:Connect(function()
	local ok, result = pcall(function()
		if SocialService:CanSendGameInviteAsync(player) then
			SocialService:PromptGameInvite(player)
			return true
		end
		return false
	end)
	if not ok or not result then
		showToast("Friend invites aren't available right now.", false)
	end
end)

-- a party invitation waiting for you
local inviteFrame = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 70), Size = UDim2.fromOffset(540, 100),
	BackgroundColor3 = Color3.fromRGB(24, 34, 28), Visible = false, ZIndex = 15,
}, topGui)
addCorner(inviteFrame, 14)
make("UIStroke", { Color = Color3.fromRGB(255, 235, 140), Thickness = 2 }, inviteFrame)
local inviteText = textLabel(inviteFrame, {
	Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -32, 0, 30), Font = Enum.Font.GothamBold, TextSize = 19, ZIndex = 16, Text = "",
})
local acceptButton = textButton(inviteFrame, {
	Position = UDim2.fromOffset(16, 48), Size = UDim2.fromOffset(240, 40), BackgroundColor3 = Color3.fromRGB(70, 160, 90), ZIndex = 16, Text = "JOIN PARTY",
})
local declineButton = textButton(inviteFrame, {
	Position = UDim2.fromOffset(284, 48), Size = UDim2.fromOffset(240, 40), BackgroundColor3 = Color3.fromRGB(170, 60, 70), ZIndex = 16, Text = "NO THANKS",
})
acceptButton.Activated:Connect(function()
	partyRespondEvent:FireServer(true)
	inviteFrame.Visible = false
end)
declineButton.Activated:Connect(function()
	partyRespondEvent:FireServer(false)
	inviteFrame.Visible = false
end)
local function refreshInviteUi()
	local invite = lobby.invite
	inviteFrame.Visible = invite ~= nil and currentMode == "lobby"
	if invite then
		inviteText.Text = `{invite.fromName} invited you to their party!`
	end
end

-- Admin panel -----------------------------------------------------------------------------------------------
-- Only drawn for admins. The buttons just ask the server, which checks the user id itself before doing anything.

local adminEvent = remotes:WaitForChild("AdminAction")

-- the Super Nuke: a huge blast that sweeps over the whole field
local function playNuke()
	shakeUntil = os.clock() + 1.4
	local blast = part({
		Name = "NukeBlast",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 4,
		Position = Vector3.new(0, 8, 0),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 210, 90),
		Transparency = 0.1,
		Parent = markers,
	})
	local tween = TweenService:Create(blast, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * 320,
		Transparency = 1,
		Color = Color3.fromRGB(255, 90, 40),
	})
	tween.Completed:Connect(function()
		blast:Destroy()
	end)
	tween:Play()
	for _, view in zombieViews do
		for _, entry in view.colored do
			entry.part.Color = Color3.new(1, 1, 1)
		end
	end
end

local adminGui = make("ScreenGui", { Name = "AdminPanel", ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 8, Enabled = false }, playerGui)
local adminToggle = textButton(adminGui, {
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -14), Size = UDim2.fromOffset(130, 40),
	BackgroundColor3 = Color3.fromRGB(120, 40, 160), TextSize = 15, Text = "ADMIN",
})
local adminFrame = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(700, 610),
	BackgroundColor3 = Color3.fromRGB(30, 22, 40), Visible = false,
}, adminGui)
addCorner(adminFrame, 16)
make("UIStroke", { Color = Color3.fromRGB(190, 110, 255), Thickness = 2 }, adminFrame)
textLabel(adminFrame, {
	Position = UDim2.fromOffset(20, 12), Size = UDim2.new(1, -80, 0, 36), Font = Enum.Font.GothamBlack, TextSize = 26,
	TextColor3 = Color3.fromRGB(220, 170, 255), Text = "ADMIN PANEL",
})
local adminClose = textButton(adminFrame, {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 12), Size = UDim2.fromOffset(40, 40),
	BackgroundColor3 = Color3.fromRGB(170, 60, 70), Text = "X",
})
adminToggle.Activated:Connect(function()
	adminFrame.Visible = not adminFrame.Visible
end)
adminClose.Activated:Connect(function()
	adminFrame.Visible = false
end)

-- who to give things to
local adminTarget = "me" -- "me", "all", or a user id
textLabel(adminFrame, { Position = UDim2.fromOffset(20, 60), Size = UDim2.fromOffset(190, 22), Font = Enum.Font.GothamBold, Text = "GIVE TO" })
local targetList = make("ScrollingFrame", {
	Position = UDim2.fromOffset(20, 86), Size = UDim2.fromOffset(190, 500), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 5, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, adminFrame)
make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, targetList)

local targetButtons = {}
local function refreshTargetHighlight()
	for key, button in targetButtons do
		button.BackgroundColor3 = key == adminTarget and Color3.fromRGB(150, 70, 200) or Color3.fromRGB(55, 45, 70)
	end
end
local targetSignature = nil
local function refreshTargets()
	local entries = { { key = "me", label = "ME" }, { key = "all", label = "EVERYONE" } }
	for _, other in lobby.others or {} do
		table.insert(entries, { key = other.userId, label = other.name })
	end
	local parts = {}
	for _, entry in entries do
		table.insert(parts, tostring(entry.key))
	end
	local signature = table.concat(parts, ",")
	if signature == targetSignature then
		return
	end
	targetSignature = signature
	for _, child in targetList:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	table.clear(targetButtons)
	local stillThere = false
	for order, entry in entries do
		stillThere = stillThere or entry.key == adminTarget
		local button = textButton(targetList, {
			LayoutOrder = order, Size = UDim2.new(1, -8, 0, 38), BackgroundColor3 = Color3.fromRGB(55, 45, 70),
			TextSize = 15, TextTruncate = Enum.TextTruncate.AtEnd, Text = entry.label,
		})
		button.Activated:Connect(function()
			adminTarget = entry.key
			refreshTargetHighlight()
		end)
		targetButtons[entry.key] = button
	end
	if not stillThere then
		adminTarget = "me"
	end
	refreshTargetHighlight()
end

-- what to give
local amountBox = make("TextBox", {
	Position = UDim2.fromOffset(300, 60), Size = UDim2.fromOffset(180, 36), BackgroundColor3 = Color3.fromRGB(55, 45, 70),
	Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = Color3.new(1, 1, 1), Text = "1000", ClearTextOnFocus = false,
	PlaceholderText = "amount",
}, adminFrame)
addCorner(amountBox, 8)
textLabel(adminFrame, { Position = UDim2.fromOffset(230, 66), Size = UDim2.fromOffset(70, 24), Font = Enum.Font.GothamBold, Text = "AMOUNT" })

local function fireAdmin(action, a, b)
	local target = adminTarget
	if target == "me" then
		target = player.UserId
	end
	adminEvent:FireServer(action, target, a, b)
end
local function amountValue()
	return math.floor(tonumber(amountBox.Text) or 0)
end

local function adminButton(text, position, size, color, callback)
	local button = textButton(adminFrame, { Position = position, Size = size, BackgroundColor3 = color, TextSize = 14, TextWrapped = true, Text = text })
	button.Activated:Connect(callback)
	return button
end

adminButton("GIVE SPUD COINS", UDim2.fromOffset(230, 108), UDim2.fromOffset(222, 44), Color3.fromRGB(190, 140, 40), function()
	fireAdmin("spuds", amountValue())
end)
adminButton("GIVE MATCH COINS", UDim2.fromOffset(464, 108), UDim2.fromOffset(222, 44), Color3.fromRGB(60, 140, 90), function()
	fireAdmin("coins", amountValue())
end)

textLabel(adminFrame, { Position = UDim2.fromOffset(230, 168), Size = UDim2.fromOffset(450, 22), Font = Enum.Font.GothamBold, Text = "GIVE A UNIQUE POTATO" })
local potatoGrid = make("Frame", { Position = UDim2.fromOffset(230, 194), Size = UDim2.fromOffset(456, 190), BackgroundTransparency = 1 }, adminFrame)
make("UIGridLayout", { CellSize = UDim2.fromOffset(146, 40), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, potatoGrid)
local allPotatoes = textButton(potatoGrid, { LayoutOrder = 0, BackgroundColor3 = Color3.fromRGB(150, 70, 200), TextSize = 14, Text = "ALL POTATOES" })
allPotatoes.Activated:Connect(function()
	fireAdmin("potato", "all")
end)
for order, def in sortedUniques do
	local rarity = Shop.RarityById[def.rarity]
	local button = textButton(potatoGrid, {
		LayoutOrder = order, BackgroundColor3 = rarity.color:Lerp(Color3.fromRGB(30, 22, 40), 0.65), TextSize = 12, TextWrapped = true, Text = def.id,
	})
	make("UIStroke", { Color = rarity.color, Thickness = 2 }, button)
	button.Activated:Connect(function()
		fireAdmin("potato", def.id)
	end)
end

textLabel(adminFrame, { Position = UDim2.fromOffset(230, 400), Size = UDim2.fromOffset(450, 22), Font = Enum.Font.GothamBold, Text = "GIVE ABILITIES  (uses the amount above)" })
local abilityGrid = make("Frame", { Position = UDim2.fromOffset(230, 426), Size = UDim2.fromOffset(456, 160), BackgroundTransparency = 1 }, adminFrame)
make("UIGridLayout", { CellSize = UDim2.fromOffset(146, 44), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, abilityGrid)
for order, ability in Shop.AllAbilities do
	local button = textButton(abilityGrid, {
		LayoutOrder = order, BackgroundColor3 = ability.color:Lerp(Color3.fromRGB(30, 22, 40), 0.5), TextSize = 14, TextWrapped = true, Text = ability.name,
	})
	make("UIStroke", { Color = ability.color, Thickness = 2 }, button)
	button.Activated:Connect(function()
		fireAdmin("ability", ability.id, amountValue())
	end)
end

local function refreshAdminUi()
	adminGui.Enabled = lobby.isAdmin == true
	if not lobby.isAdmin then
		adminFrame.Visible = false
		return
	end
	refreshTargets()
end

-- Drawing a snapshot -------------------------------------------------------------------------------------------

local lastBaseHp = nil

local function clearMatchViews()
	for _, entry in towerModels do
		entry.model:Destroy()
	end
	table.clear(towerModels)
	currentTowers = {}
	for _, view in zombieViews do
		view.model:Destroy()
	end
	table.clear(zombieViews)
	selectedUid = nil
	armed = nil
	shopSignature = nil
	refreshSelection()
end

-- the server tells us which place we are in; switch screens when it changes
local function setMode(state)
	if state.mode == currentMode then
		return
	end
	local previous = currentMode
	currentMode = state.mode
	gui.Enabled = state.mode == "match"
	lobbyGui.Enabled = state.mode == "lobby"
	if previous == "match" then
		clearMatchViews()
	end
	if state.mode == "match" then
		clearMatchViews()
		currentMap = Path.Maps[state.mapId]
		buildBattlefield(currentMap)
		lastBaseHp = nil
		showToast(`Pick a defender below, then click anywhere on the grass to place it - just not on the zombies' road! Wave 1 starts in {Config.FirstWaveDelay} seconds.`, true, 10)
	else
		for _, frame in (previous and panels or {}) do
			frame.Visible = false
		end
		if state.mode == "lobby" then
			resultFrame.Visible = false
		end
	end
end

local function renderMatch(state)
	coinsLabel.Text = `{short(state.coins)} coins`
	statsLabel.Text = `+{string.format("%.1f", state.income)} coins / sec     {currentMap.name}`
		.. (#state.teammates > 0 and `     With: {table.concat(state.teammates, ", ")}` or "")
	if state.phase == "fight" then
		waveLabel.Text = `WAVE {state.wave} of {state.wavesTotal}     zombies left: {state.remaining}`
	else
		waveLabel.Text = `WAVE {state.wave} of {state.wavesTotal} starts in {state.breakIn}s  -  build your defence!`
	end

	local ratio = math.clamp(state.baseHp / state.baseMax, 0, 1)
	TweenService:Create(baseBar, TweenInfo.new(0.25), {
		Size = UDim2.fromScale(ratio, 1),
		BackgroundColor3 = Color3.fromHSV(0.33 * ratio, 0.7, 0.85),
	}):Play()
	baseText.Text = `YOUR BASE  {math.ceil(state.baseHp)} / {state.baseMax}`
	barricadeButton.Text = `BARRICADE +{Config.BarricadeHp} HP ({short(state.barricadeCost)})`
	setFence(state.barricades)

	-- the base was hit: shake the camera and flash the wall red
	if lastBaseHp and state.baseHp < lastBaseHp - 0.5 then
		shakeUntil = os.clock() + 0.45
		baseWall.Color = Color3.fromRGB(230, 70, 70)
		TweenService:Create(baseWall, TweenInfo.new(0.4), { Color = baseColor }):Play()
	end
	lastBaseHp = state.baseHp

	for _, ability in Shop.AllAbilities do
		local count = state.abilities[ability.id] or 0
		local button = abilityButtons[ability.id]
		button.Text = `{ability.name}   x{count}`
		button.BackgroundTransparency = count > 0 and 0 or 0.55
		button.Visible = not ability.adminOnly or count > 0 -- admin-only abilities only show up once you hold one
	end

	buildShop(state.owned)
	for id, entry in shopButtons do
		local def = Towers.ById[id]
		entry.lock.Visible = def.unlockWave > state.wave
		entry.cost.TextColor3 = state.coins >= def.cost and Color3.fromRGB(255, 235, 140) or Color3.fromRGB(255, 120, 110)
	end

	-- towers: build, rebuild when upgraded, remove when sold
	local nextTowers = {}
	for _, tower in state.towers do
		nextTowers[tower.uid] = { id = tower.id, level = tower.level, x = tower.x, z = tower.z, mine = tower.mine, owner = tower.owner }
	end
	for uid, entry in towerModels do
		local tower = nextTowers[uid]
		if not tower or tower.id ~= entry.id or tower.level ~= entry.level then
			entry.model:Destroy()
			towerModels[uid] = nil
		end
	end
	for uid, tower in nextTowers do
		if not towerModels[uid] then
			local def = Towers.ById[tower.id]
			towerModels[uid] = { model = buildTower(uid, tower.x, tower.z, def, tower.level, nil, (not tower.mine) and tower.owner or nil), id = tower.id, level = tower.level }
		end
	end
	currentTowers = nextTowers
	if selectedUid and not currentTowers[selectedUid] then
		selectedUid = nil
	end
	refreshSelection()

	-- zombies
	local seen = {}
	for _, zombie in state.zombies do
		seen[zombie.id] = true
		local at, dir = Path.pointAt(currentMap, zombie.pos)
		local view = zombieViews[zombie.id]
		if not view then
			view = buildZombie(zombie)
			view.at = at
			view.dir = dir
			zombieViews[zombie.id] = view
		end
		view.targetAt, view.targetDir = at, dir
		view.fill.Size = UDim2.fromScale(math.clamp(zombie.hp / zombie.maxHp, 0, 1), 1)
		local skin = zombie.slowed and ZOMBIE_SLOWED or view.tint
		for _, entry in view.colored do
			if entry.skin then
				entry.part.Color = skin
			end
		end
		if zombie.hp < view.hp then
			for _, entry in view.colored do
				entry.part.Color = Color3.new(1, 1, 1) -- got shot: flash white
			end
		end
		view.hp = zombie.hp
	end
	for id, view in zombieViews do
		if not seen[id] then
			view.model:Destroy()
			zombieViews[id] = nil
		end
	end

	for _, event in state.events do
		if event.kind == "shot" then
			playShot(event)
		elseif event.kind == "coin" then
			playCoin(event)
		elseif event.kind == "pulse" then
			playPulse(event)
		elseif event.kind == "nuke" then
			playNuke()
		elseif event.kind == "meteor" then
			shakeUntil = os.clock() + 0.5
			for _, view in zombieViews do
				for _, entry in view.colored do
					entry.part.Color = Color3.fromRGB(255, 170, 60)
				end
			end
		end
	end
end

stateEvent.OnClientEvent:Connect(function(state)
	lobby.spuds = state.spuds
	lobby.ownedList = state.owned
	lobby.owned = {}
	for _, id in state.owned do
		lobby.owned[id] = true
	end
	lobby.abilities = state.abilities or {}
	lobby.best = state.best or {}
	lobby.others = state.others or {}
	lobby.party = state.party
	lobby.invite = state.invite
	lobby.isAdmin = state.isAdmin == true
	refreshAdminUi()
	setMode(state)
	refreshInviteUi()
	if state.mode == "match" then
		renderMatch(state)
	else
		refreshLobbyUi()
		refreshPartyUi()
	end
end)

-- every frame: hold the camera, glide zombies along the road, and preview where a new defender would go
RunService.RenderStepped:Connect(function(dt)
	holdCamera()

	local clock = os.clock()
	for id, view in zombieViews do
		view.at = view.at:Lerp(view.targetAt, math.min(1, dt * 10))
		view.dir = view.dir:Lerp(view.targetDir, math.min(1, dt * 6))
		local bob = math.sin(clock * 7 + id) * 0.25
		local sway = math.sin(clock * 5 + id) * 0.08
		-- the model faces -X, so turn it until -X points along the road
		local heading = math.atan2(view.dir.Z, -view.dir.X)
		view.model:PivotTo(CFrame.new(view.at.X, bob, view.at.Z) * CFrame.Angles(0, heading, sway))
		-- fade the white hit flash back to the zombie's own colour
		for _, entry in view.colored do
			local target = entry.skin and view.tint or entry.part.Color
			entry.part.Color = entry.part.Color:Lerp(target, math.min(1, dt * 8))
		end
	end

	if currentMode == "match" and armed and not UserInputService.TouchEnabled then
		local point = groundAt(UserInputService:GetMouseLocation())
		if point then
			local def = Towers.ById[armed]
			local fits = Path.canPlace(currentMap, point.X, point.Z, towerList())
			hoverFootprint.Color = fits and Color3.fromRGB(150, 255, 150) or Color3.fromRGB(255, 90, 90)
			placeDisc(hoverFootprint, point.X, point.Z, Path.TowerRadius + 0.5, 0.35)
			if def.range > 0 then
				hoverMarker.Color = hoverFootprint.Color
				placeDisc(hoverMarker, point.X, point.Z, def.range, 0.8)
			else
				hoverMarker.Transparency = 1
			end
		else
			hoverMarker.Transparency = 1
			hoverFootprint.Transparency = 1
		end
	else
		hoverMarker.Transparency = 1
		hoverFootprint.Transparency = 1
	end
end)

readyEvent:FireServer()

-- (a test hook: set the StartPanel attribute on workspace in Studio to open a lobby menu straight away)
local startPanel = workspace:GetAttribute("StartPanel")
if startPanel then
	task.delay(1.5, function()
		if startPanel == "admin" then
			adminFrame.Visible = true
		else
			openPanel(startPanel)
		end
	end)
end
