class_name WorldMeshBuilder
extends RefCounted
## Builds the wall mesh from a World: one quad per exposed wall face, 1 cell = 1 m.
## Vertex data used by sonar_wall.gdshader:
##   UV    = (u along the face 0..1, v height 0..1 where 0 is the floor edge)
##   COLOR = (r: line strength at u=0, g: line strength at u=1, b: tile char code / 255, a: 1)
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


static func build(world: World) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for cy in world.height:
		for cx in world.width:
			if not _solid(world, cx, cy):
				continue
			var code: float = float(world.tile_at(cx + 0.5, cy + 0.5).unicode_at(0)) / 255.0
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
					cols.append(Color(s0, s1, code, 1.0))
				idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	if verts.size() > 0:
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
