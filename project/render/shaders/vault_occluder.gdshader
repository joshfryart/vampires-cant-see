shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
// The dark body of the ink cave's stalactites (0.21.9): the same cone mesh as the ink pass (VaultMesh.build_stalactites), drawn opaque black a
// hair inside the ink surface. It writes depth, so the walls, floor rings and vault lines behind a cone (and the cone's own far side) are hidden:
// the cones read as solid rock and only their ping-lit near edges show. Drip beads (COLOR.a = 1) get no body: their vertices collapse onto
// one vertical line, so their triangles have no area.

const float INSET = 0.012;   // cells the body sits inside the ink surface (no depth fight with the additive ink pass)

void vertex() {
	if (COLOR.a > 0.75) {
		VERTEX = vec3(UV2.x, VERTEX.y, UV2.y);
	} else {
		VERTEX -= NORMAL * INSET;
	}
}

void fragment() {
	ALBEDO = vec3(0.0);
}
