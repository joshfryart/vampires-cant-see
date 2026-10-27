class_name WorldMeshBuilder
extends RefCounted
## Builds the wall mesh from a World: one quad per exposed wall face, 1 cell = 1 m.
## Vertex data used by sonar_wall.gdshader:
##   UV    = (u along the face 0..1, v height 0..1 where 0 is the floor edge)
##   COLOR = (r: line strength at u=0, g: line strength at u=1, b: tile char code / 255, a: 1 for a link door, else 0)
##   NORMAL = (nx, 0, ny): the face normal in world xz (points into the open cell); the wall cell is floor(p - 0.01 n)
## Line strength is 1 at a real corner (convex or concave) and 0.35 where the face continues flush
## into the next cell, mirroring the vertical lines in js/render.js drawWalls.

const FLUSH := 0.35
## Face normals in JS (x, y) space: north, south, west, east.
const SIDES := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]


static func _solid(world: World, cx: int, cy: int) -> bool:
	return world.is_solid(cx + 0.5, cy + 0.5)


## Strength of the vertical line at the end of a face whose neighbour along the tangent is (nx, ny).
static func _corner(world: World, nx: int, ny: int, n: Vector2i) -> float:
	if _solid(world, nx, ny) and not _solid(world, nx + n.x, ny + n.y):
		return FLUSH
	return 1.0


## Master switch of the contour (ink) wall mesh. Off until the wall shader understands it (docs/STYLE.md S3): the contour path then runs only when a world
## also has a non-empty wall_style. Tests call build_contour directly.
static var contour_enabled: bool = false


static func build(world: World) -> ArrayMesh:
	if contour_enabled and not world.wall_style.is_empty():
		return build_contour(world)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for cy in world.height:
		for cx in world.width:
			if not _solid(world, cx, cy):
				continue
			var code: float = float(world.tile_at(cx + 0.5, cy + 0.5).unicode_at(0)) / 255.0
			var link: float = 1.0 if world.is_link_door(cx, cy) else 0.0
			for n in SIDES:
				if _solid(world, cx + n.x, cy + n.y):
					continue
				var t := Vector2i(-n.y, n.x)
				var f := Vector2(cx + 0.5, cy + 0.5) + Vector2(n) * 0.5
				var p0 := f - Vector2(t) * 0.5
				var p1 := f + Vector2(t) * 0.5
				var s0 := _corner(world, cx - t.x, cy - t.y, n)
				var s1 := _corner(world, cx + t.x, cy + t.y, n)
				var base := verts.size()
				verts.append(Coords.to_view(p0.x, p0.y, 0.0))
				verts.append(Coords.to_view(p1.x, p1.y, 0.0))
				verts.append(Coords.to_view(p1.x, p1.y, 1.0))
				verts.append(Coords.to_view(p0.x, p0.y, 1.0))
				uvs.append(Vector2(0, 0))
				uvs.append(Vector2(1, 0))
				uvs.append(Vector2(1, 1))
				uvs.append(Vector2(0, 1))
				for i in 4:
					cols.append(Color(s0, s1, code, link))
					norms.append(Vector3(n.x, 0.0, n.y))
				idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	if verts.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Smooth-wall mesh (docs/STYLE.md section 2): two vertices per contour vertex (h = 0 and h = 1), one quad per outline segment (4 own vertices, so per-segment
## attributes never interpolate across a style change). Attributes:
##   VERTEX = displaced position, NORMAL = visual normal (the segment's own perpendicular at unrounded corners), UV = (loop base + arc length s, v),
##   UV2 = the grid anchor (JS x, y), COLOR.r = built faces (style 0 and 6-9): 1 at a corner (convex; concave too for style 0), else 0;
##   natural faces: signed curvature 0.5 + 0.5 * clamp(k / CURV_RANGE) (convex > 0.5), COLOR.g = (style * 4 + face code N S W E) / 255,
##   COLOR.b = tile code / 255, COLOR.a = link door.
static func build_contour(world: World) -> ArrayMesh:
	var cf := ContourField.for_world(world)
	var nq := cf.segment_total()
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.resize(nq * 4)
	uvs.resize(nq * 4)
	uv2s.resize(nq * 4)
	cols.resize(nq * 4)
	norms.resize(nq * 4)
	idx.resize(nq * 6)
	var zs: float = Coords.Z_SCALE
	var q := 0
	for L: ContourField.Loop in cf.loops:
		var n := L.pos.size()
		var base_s: float = L.index * ContourField.LOOP_S
		for i in n:
			var j := (i + 1) % n
			var pi: Vector2 = L.pos[i]
			var pj: Vector2 = L.pos[j]
			var dir := pj - pi
			var segn := Vector2(dir.y, -dir.x)
			segn = segn.normalized() if segn.length_squared() > 1e-18 else L.ng[i]
			var ni: Vector2 = segn if L.hard[i] == 1 else L.nrm[i]
			var nj: Vector2 = segn if L.hard[j] == 1 else L.nrm[j]
			var si: float = base_s + L.s[i]
			var sj: float = base_s + (L.s[j] if j > 0 else L.length)
			var st: int = L.style[i]
			var gb: float = float(st * 4 + L.ngcode[i]) / 255.0
			var cb: float = float(L.code[i]) / 255.0
			var lk: float = float(L.link[i])
			var ra: float
			var rb: float
			if st == 0 or st >= 6:
				ra = 1.0 if (L.corner[i] == 1 or (L.corner[i] == 2 and st == 0)) else 0.0
				rb = 1.0 if (L.corner[j] == 1 or (L.corner[j] == 2 and st == 0)) else 0.0
			else:
				ra = 0.5 + 0.5 * clampf(L.curv[i] / ContourField.CURV_RANGE, -1.0, 1.0)
				rb = 0.5 + 0.5 * clampf(L.curv[j] / ContourField.CURV_RANGE, -1.0, 1.0)
			var b := q * 4
			verts[b] = Vector3(pi.x, 0.0, pi.y)
			verts[b + 1] = Vector3(pj.x, 0.0, pj.y)
			verts[b + 2] = Vector3(pj.x, zs, pj.y)
			verts[b + 3] = Vector3(pi.x, zs, pi.y)
			uvs[b] = Vector2(si, 0.0)
			uvs[b + 1] = Vector2(sj, 0.0)
			uvs[b + 2] = Vector2(sj, 1.0)
			uvs[b + 3] = Vector2(si, 1.0)
			var ai: Vector2 = L.anchor[i]
			var aj: Vector2 = L.anchor[j]
			uv2s[b] = ai
			uv2s[b + 1] = aj
			uv2s[b + 2] = aj
			uv2s[b + 3] = ai
			cols[b] = Color(ra, gb, cb, lk)
			cols[b + 1] = Color(rb, gb, cb, lk)
			cols[b + 2] = Color(rb, gb, cb, lk)
			cols[b + 3] = Color(ra, gb, cb, lk)
			norms[b] = Vector3(ni.x, 0.0, ni.y)
			norms[b + 1] = Vector3(nj.x, 0.0, nj.y)
			norms[b + 2] = Vector3(nj.x, 0.0, nj.y)
			norms[b + 3] = Vector3(ni.x, 0.0, ni.y)
			var ib := q * 6
			idx[ib] = b
			idx[ib + 1] = b + 1
			idx[ib + 2] = b + 2
			idx[ib + 3] = b
			idx[ib + 4] = b + 2
			idx[ib + 5] = b + 3
			q += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	if nq > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## One big floor quad over the whole map (y = 0), used by sonar_floor.gdshader.
static func build_floor(world: World) -> ArrayMesh:
	var w: float = world.width
	var h: float = world.height
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(w, 0, 0), Vector3(w, 0, h), Vector3(0, 0, h)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The ceiling plane (wall height 1) over the whole map, for the ceiling pass of sonar_floor.gdshader (is_ceiling).
static func build_ceiling(world: World) -> ArrayMesh:
	var w: float = world.width
	var h: float = world.height
	var y: float = Coords.Z_SCALE
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, y, 0), Vector3(w, y, 0), Vector3(w, y, h), Vector3(0, y, h)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
