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

local stateEvent = remotes:WaitForChild("State")
local readyEvent = remotes:WaitForChild("Ready")
local placeEvent = remotes:WaitForChild("Place")
local upgradeEvent = remotes:WaitForChild("Upgrade")
local sellEvent = remotes:WaitForChild("Sell")
local barricadeEvent = remotes:WaitForChild("Barricade")
local noticeEvent = remotes:WaitForChild("Notice")

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

-- World layout -------------------------------------------------------------------------------------
-- Defenders can stand anywhere on the field except the zombies' road (rules in the shared Path module).
-- Zombies walk the road from the graveyard (right) to your base (left). The camera looks from +Z toward -Z.

local FIELD_X, FIELD_Z = Path.FieldX, Path.FieldZ

local world = make("Folder", { Name = "Battlefield" }, workspace)
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

-- Ground, road, base wall, graveyard, trees -------------------------------------------------------------

local baseplate = workspace:FindFirstChild("Baseplate")
if baseplate then
	for _, child in baseplate:GetChildren() do
		if child:IsA("Texture") or child:IsA("Decal") then
			child:Destroy()
		end
	end
end
part({
	Name = "Lawn",
	CanCollide = true,
	Size = Vector3.new(900, 1, 900),
	Position = Vector3.new(0, -0.5, 0),
	Material = Enum.Material.Grass,
	Color = Color3.fromRGB(98, 160, 74),
	CanQuery = true,
	Parent = groundFolder,
})

-- the road: one flat strip per straight section, each a little long so the corners fill in
for i = 1, #Path.Points - 1 do
	local a, b = Path.Points[i], Path.Points[i + 1]
	local length = (b - a).Magnitude
	local mid = (a + b) / 2
	part({
		Name = "Road",
		Size = Vector3.new(length + Path.HalfWidth * 2, 0.2, Path.HalfWidth * 2),
		CFrame = CFrame.lookAt(mid + Vector3.new(0, 0.1, 0), mid + Vector3.new(0, 0.1, 0) + (b - a)) * CFrame.Angles(0, math.pi / 2, 0),
		Material = Enum.Material.Ground,
		Color = Color3.fromRGB(176, 140, 96),
		CanQuery = true,
		Parent = groundFolder,
	})
end

-- the base: a stone wall where the road ends, with a sign
local baseEnd = Path.Points[#Path.Points]
local baseWall = part({
	Name = "BaseWall",
	CanCollide = true,
	Size = Vector3.new(3, 9, 18),
	Position = baseEnd + Vector3.new(-4.5, 4.5, 0),
	Material = Enum.Material.Brick,
	Color = Color3.fromRGB(176, 150, 130),
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
local baseColor = baseWall.Color

-- barricade fence: one more post for every barricade you build
local fence = make("Folder", { Name = "Fence" }, world)
local fenceCount = 0
local function setFence(count)
	if count == fenceCount then
		return
	end
	fenceCount = count
	fence:ClearAllChildren()
	local shown = math.min(count, 10)
	for i = 1, shown do
		local z = baseEnd.Z - 8 + (i - 0.5) * (16 / shown)
		part({
			Name = "FencePost",
			Size = Vector3.new(1, 5, 1),
			Position = Vector3.new(baseEnd.X - 2.2, 2.5, z),
			Material = Enum.Material.Wood,
			Color = Color3.fromRGB(139, 94, 60),
			Parent = fence,
		})
	end
end

-- the graveyard where zombies come from
local rng = Random.new(7)
local graveyard = Path.Points[1]
for i = 1, 16 do
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
for i = 1, 40 do
	local x = rng:NextNumber(-120, 120)
	local z = rng:NextNumber(-80, 80)
	local insideField = math.abs(x) < FIELD_X + 40 and math.abs(z) < FIELD_Z + 14
	if not insideField then
		local height = rng:NextNumber(10, 22)
		part({
			Name = "TreeTrunk",
			CanCollide = true,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(height, 1.6, 1.6),
			CFrame = CFrame.new(x, height / 2, z) * CFrame.Angles(0, 0, math.pi / 2),
			Material = Enum.Material.Wood,
			Color = Color3.fromRGB(110, 78, 52),
		})
		local d = rng:NextNumber(8, 13)
		part({
			Name = "TreeCrown",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(d, d, d),
			Position = Vector3.new(x, height + d * 0.25, z),
			Material = Enum.Material.Grass,
			Color = Color3.fromHSV(rng:NextNumber(0.28, 0.36), 0.62, rng:NextNumber(0.5, 0.65)),
		})
	end
end

-- Camera: fixed, looking down over the field, with a little shake when the base is hit -----------------

local camera = workspace.CurrentCamera
local shakeUntil = 0
local mapView = false -- false: walk around with your avatar; true: the fixed bird's-eye view
player.CameraMaxZoomDistance = 90
local function holdCamera()
	camera = workspace.CurrentCamera
	if not mapView then
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

-- Screen (HUD over the 3D scene) -------------------------------------------------------------------

local gui = make("ScreenGui", {
	Name = "ZombiesVsVerity",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
}, player:WaitForChild("PlayerGui"))

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

local towerModels = {} -- [cell] = { model, id, level }
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
	end
end

local function buildTower(uid, x, z, def, level)
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
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0,
		Text = `{def.id} {string.rep("*", level)}`,
	}, tag)
	model.Parent = world
	return model
end

-- Zombies (3D) -------------------------------------------------------------------------------------------

local zombieViews = {} -- [id] = { model, torsoParts, x, targetX, z, hpFill, hp, colors }

local ZOMBIE_GREEN = Color3.fromRGB(110, 170, 90)
local ZOMBIE_SLOWED = Color3.fromRGB(110, 150, 230)

local function buildZombie(zombie)
	local model = Instance.new("Model")
	model.Name = `Zombie{zombie.id}`
	local tint = zombie.boss and Color3.fromRGB(170, 70, 100) or ZOMBIE_GREEN
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
	if zombie.boss then
		model:ScaleTo(1.8)
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

-- Shop, selection and messages (2D over the scene) ----------------------------------------------------------

local shopButtons = {} -- [towerId] = { button, cost, lock }
local armed = nil -- the tower type picked in the shop, waiting for a tile
local selectedUid = nil -- a placed tower you tapped, for upgrade / sell
local upgradeButton, sellButton, barricadeButton, refreshSelection -- defined below

local shopRow = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -14),
	Size = UDim2.fromOffset(#Towers.List * 118, 70),
	BackgroundTransparency = 1,
}, gui)
make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, shopRow)

for order, def in Towers.List do
	local button = make("TextButton", {
		LayoutOrder = order,
		Size = UDim2.fromOffset(110, 70),
		BackgroundColor3 = def.color:Lerp(Color3.fromRGB(20, 25, 22), 0.55),
		Text = "",
		AutoButtonColor = false,
	}, shopRow)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, button)
	make("UIStroke", { Thickness = 2, Color = def.color }, button)
	make("TextLabel", {
		Position = UDim2.fromOffset(0, 4),
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		Text = def.id,
	}, button)
	make("TextLabel", {
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 11,
		TextColor3 = Color3.fromRGB(215, 225, 215),
		Text = def.role,
	}, button)
	local costLabel = make("TextLabel", {
		Position = UDim2.fromOffset(0, 44),
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
	shopButtons[def.id] = { button = button, cost = costLabel, lock = lock }
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
upgradeButton = bigButton("UPGRADE", Color3.fromRGB(70, 130, 220), 0.5, -130, -96)
sellButton = bigButton("SELL", Color3.fromRGB(200, 60, 80), 0.5, 130, -96)
barricadeButton = bigButton("BARRICADE", Color3.fromRGB(70, 130, 90), 1, -14, -96)
upgradeButton.Visible = false
sellButton.Visible = false

local viewButton = make("TextButton", {
	Position = UDim2.fromOffset(14, 14),
	Size = UDim2.fromOffset(190, 44),
	BackgroundColor3 = Color3.fromRGB(60, 90, 160),
	Font = Enum.Font.GothamBlack,
	TextSize = 16,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "MAP VIEW",
	ZIndex = 5,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, viewButton)
viewButton.Activated:Connect(function()
	mapView = not mapView
	viewButton.Text = mapView and "WALK AROUND" or "MAP VIEW"
end)

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
}, gui)
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

-- flat discs on the ground: one shows the range of the tower you selected, one previews where a new tower would go
local function makeDisc(name, color)
	return part({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, 2, 2),
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = 1,
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

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { groundFolder }

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
		entry.button.UIStroke.Thickness = id == armed and 5 or 2
	end
	local tower = selectedUid and currentTowers[selectedUid]
	upgradeButton.Visible = tower ~= nil
	sellButton.Visible = tower ~= nil
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
	if processed then
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

-- Drawing a snapshot -------------------------------------------------------------------------------------------

local lastBaseHp = nil

local function render(state)
	coinsLabel.Text = `{short(state.coins)} coins`
	statsLabel.Text = `+{string.format("%.1f", state.income)} coins / sec     wave {state.wave}     best wave cleared: {state.bestWave}`
	if state.phase == "fight" then
		waveLabel.Text = `WAVE {state.wave}     zombies left: {state.remaining}`
	else
		waveLabel.Text = `WAVE {state.wave} starts in {state.breakIn}s  -  build your defence!`
	end

	local ratio = math.clamp(state.baseHp / state.baseMax, 0, 1)
	TweenService:Create(baseBar, TweenInfo.new(0.25), {
		Size = UDim2.fromScale(ratio, 1),
		BackgroundColor3 = Color3.fromHSV(0.33 * ratio, 0.7, 0.85),
	}):Play()
	baseText.Text = `YOUR BASE  {math.ceil(state.baseHp)} / {state.baseMax}`
	barricadeButton.Text = `BARRICADE +{Config.BarricadeHp} HP ({short(state.barricadeCost)})`
	setFence(math.floor((state.baseMax - Config.BaseHealth) / Config.BarricadeHp + 0.5))

	-- the base was hit: shake the camera and flash the wall red
	if lastBaseHp and state.baseHp < lastBaseHp - 0.5 then
		shakeUntil = os.clock() + 0.45
		baseWall.Color = Color3.fromRGB(230, 70, 70)
		TweenService:Create(baseWall, TweenInfo.new(0.4), { Color = baseColor }):Play()
	end
	lastBaseHp = state.baseHp

	for _, def in Towers.List do
		local entry = shopButtons[def.id]
		entry.lock.Visible = def.unlockWave > state.wave
		entry.cost.TextColor3 = state.coins >= def.cost and Color3.fromRGB(255, 235, 140) or Color3.fromRGB(255, 120, 110)
	end

	-- towers: build, rebuild when upgraded, remove when sold
	local nextTowers = {}
	for _, tower in state.towers do
		nextTowers[tower.uid] = { id = tower.id, level = tower.level, x = tower.x, z = tower.z }
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
			towerModels[uid] = { model = buildTower(uid, tower.x, tower.z, def, tower.level), id = tower.id, level = tower.level }
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
		local view = zombieViews[zombie.id]
		if not view then
			view = buildZombie(zombie)
			view.at = Path.pointAt(zombie.pos)
			view.dir = select(2, Path.pointAt(zombie.pos))
			zombieViews[zombie.id] = view
		end
		view.targetAt, view.targetDir = Path.pointAt(zombie.pos)
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
		end
	end
end

stateEvent.OnClientEvent:Connect(render)

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

-- every frame: hold the camera, glide zombies toward where the server says they are, and light the tile under the mouse
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

	if armed and not UserInputService.TouchEnabled then
		local point = groundAt(UserInputService:GetMouseLocation())
		if point then
			local def = Towers.ById[armed]
			local fits = Path.canPlace(point.X, point.Z, towerList())
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

showToast("Pick a defender below, then click anywhere on the grass to place it - just not on the zombies' road! Wave 1 starts in 30 seconds.", true, 10)
readyEvent:FireServer()
