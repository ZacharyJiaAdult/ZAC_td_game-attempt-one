-- The battlefield maps: the road the zombies walk, and the rules for where defenders may stand. Shared by the
-- server (which enforces the rules) and the client (which draws the map and previews placement). Defenders can
-- go ANYWHERE on the field except on the road itself. A zombie's `pos` is how far along the road it is,
-- from 0 (graveyard) to 1 (your base). Every road starts at the right edge (x = 50) heading left.
local Path = {}

Path.HalfWidth = 4 -- the road is 8 studs wide
Path.TowerRadius = 2.5 -- how much room a defender needs, so none can overlap the road
Path.TowerSpacing = 5.5 -- minimum distance between two defenders
Path.FieldX = 140 -- defenders may be placed within +-FieldX and +-FieldZ of the centre (basically the whole map)
Path.FieldZ = 100

Path.Maps = {} -- by id
Path.List = {} -- in menu order

local function addMap(def)
	def.lengths = {}
	def.length = 0
	for i = 1, #def.points - 1 do
		def.lengths[i] = (def.points[i + 1] - def.points[i]).Magnitude
		def.length += def.lengths[i]
	end
	Path.Maps[def.id] = def
	table.insert(Path.List, def)
end

addMap({
	id = "meadow",
	name = "Spud Meadow",
	blurb = "A friendly S-shaped road. Great for learning.",
	points = {
		Vector3.new(50, 0, -15),
		Vector3.new(-18, 0, -15),
		Vector3.new(-18, 0, 0),
		Vector3.new(18, 0, 0),
		Vector3.new(18, 0, 15),
		Vector3.new(-44, 0, 15),
	},
	spawn = Vector3.new(0, 5, -7.5),
	lawn = Color3.fromRGB(98, 160, 74),
	lawnMaterial = Enum.Material.Grass,
	road = Color3.fromRGB(176, 140, 96),
	roadMaterial = Enum.Material.Ground,
	treeHue = { 0.28, 0.36 },
	seed = 7,
})

addMap({
	id = "farm",
	name = "Windy Wheat Farm",
	blurb = "Long, twisty rows: lots of road to shoot at.",
	points = {
		Vector3.new(50, 0, -30),
		Vector3.new(-30, 0, -30),
		Vector3.new(-30, 0, -12),
		Vector3.new(30, 0, -12),
		Vector3.new(30, 0, 6),
		Vector3.new(-30, 0, 6),
		Vector3.new(-30, 0, 24),
		Vector3.new(-46, 0, 24),
	},
	spawn = Vector3.new(0, 5, -21),
	lawn = Color3.fromRGB(176, 168, 78),
	lawnMaterial = Enum.Material.Grass,
	road = Color3.fromRGB(128, 100, 74),
	roadMaterial = Enum.Material.Ground,
	treeHue = { 0.1, 0.16 },
	seed = 21,
})

addMap({
	id = "frost",
	name = "Frosty Spiral",
	blurb = "The road spirals in to the base at the centre.",
	points = {
		Vector3.new(50, 0, -30),
		Vector3.new(-45, 0, -30),
		Vector3.new(-45, 0, 30),
		Vector3.new(45, 0, 30),
		Vector3.new(45, 0, -14),
		Vector3.new(-27, 0, -14),
		Vector3.new(-27, 0, 14),
		Vector3.new(27, 0, 14),
		Vector3.new(27, 0, 0),
		Vector3.new(4, 0, 0),
	},
	spawn = Vector3.new(0, 5, -22),
	lawn = Color3.fromRGB(226, 236, 242),
	lawnMaterial = Enum.Material.Snow,
	road = Color3.fromRGB(120, 124, 134),
	roadMaterial = Enum.Material.Slate,
	treeHue = { 0.33, 0.45 },
	seed = 99,
})

-- the point on the road `t` of the way along it (0..1), and the direction of travel there
function Path.pointAt(map, t)
	local distance = math.clamp(t, 0, 1) * map.length
	for i = 1, #map.lengths do
		if distance <= map.lengths[i] or i == #map.lengths then
			local a, b = map.points[i], map.points[i + 1]
			return a:Lerp(b, math.min(1, distance / map.lengths[i])), (b - a).Unit
		end
		distance -= map.lengths[i]
	end
end

local function distanceToSegment(p, a, b)
	local ab = b - a
	local t = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
	return (p - (a + ab * t)).Magnitude
end

function Path.distanceToRoad(map, x, z)
	local p = Vector3.new(x, 0, z)
	local best = math.huge
	for i = 1, #map.points - 1 do
		best = math.min(best, distanceToSegment(p, map.points[i], map.points[i + 1]))
	end
	return best
end

-- true if a defender may stand here (on the field, off the road). `others` is an optional list of {x, z} to keep clear of.
function Path.canPlace(map, x, z, others)
	if math.abs(x) > Path.FieldX or math.abs(z) > Path.FieldZ then
		return false, "That is outside the field."
	end
	if Path.distanceToRoad(map, x, z) < Path.HalfWidth + Path.TowerRadius then
		return false, "You can't build on the zombies' road!"
	end
	if others then
		for _, other in others do
			if (Vector3.new(x, 0, z) - Vector3.new(other.x, 0, other.z)).Magnitude < Path.TowerSpacing then
				return false, "Too close to another defender."
			end
		end
	end
	return true
end

return Path
