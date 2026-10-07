-- The road the zombies walk, and the rules for where defenders may stand. Shared by the server (which enforces
-- the rules) and the client (which draws the road and previews placement). Defenders can go ANYWHERE on the
-- field except on the road itself; a zombie's `pos` is how far along the road it is, from 0 (graveyard) to 1 (base).
local Path = {}

Path.Points = {
	Vector3.new(50, 0, -15),
	Vector3.new(-18, 0, -15),
	Vector3.new(-18, 0, 0),
	Vector3.new(18, 0, 0),
	Vector3.new(18, 0, 15),
	Vector3.new(-44, 0, 15),
}
Path.HalfWidth = 4 -- the road is 8 studs wide
Path.TowerRadius = 2.5 -- how much room a defender needs, so none can overlap the road
Path.TowerSpacing = 5.5 -- minimum distance between two defenders
Path.FieldX = 140 -- defenders may be placed within +-FieldX and +-FieldZ of the centre (basically the whole map)
Path.FieldZ = 100

local lengths = {}
Path.Length = 0
for i = 1, #Path.Points - 1 do
	lengths[i] = (Path.Points[i + 1] - Path.Points[i]).Magnitude
	Path.Length += lengths[i]
end

function Path.pointAt(t)
	local distance = math.clamp(t, 0, 1) * Path.Length
	for i = 1, #lengths do
		if distance <= lengths[i] or i == #lengths then
			local a, b = Path.Points[i], Path.Points[i + 1]
			return a:Lerp(b, math.min(1, distance / lengths[i])), (b - a).Unit
		end
		distance -= lengths[i]
	end
end

local function distanceToSegment(p, a, b)
	local ab = b - a
	local t = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
	return (p - (a + ab * t)).Magnitude
end

function Path.distanceToRoad(x, z)
	local p = Vector3.new(x, 0, z)
	local best = math.huge
	for i = 1, #Path.Points - 1 do
		best = math.min(best, distanceToSegment(p, Path.Points[i], Path.Points[i + 1]))
	end
	return best
end

-- true if a defender may stand here (on the field, off the road). `others` is an optional list of {x, z} to keep clear of.
function Path.canPlace(x, z, others)
	if math.abs(x) > Path.FieldX or math.abs(z) > Path.FieldZ then
		return false, "That is outside the field."
	end
	if Path.distanceToRoad(x, z) < Path.HalfWidth + Path.TowerRadius then
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
