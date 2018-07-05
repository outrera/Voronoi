extends Object

const EPSILON = 0.0000001

var vertices
var edges
var triangles

# Some fields used to track limits
var min_height = INF
var max_height = -INF

# Water flow tree sinks
var non_dependants

class Vertex:
	var pos    # Vector3
	var index

	# parent references
	var edges      # Array of Edge
	var tris       # Array of parent Triangle
	var connectors # Array of connected vertices

	# Water flow tree
	var dependants      # Uphill
	var dependancy      # Downhill

	func _init(vertex):
		pos        = vertex
		edges      = []
		tris       = []
		connectors = []
		dependants = []

	static func sort(a, b):
		# Sort by z then x then y
		if a.pos.z > b.pos.z: 
			return true
		elif a.pos.z == b.pos.z:
			if a.pos.x < b.pos.x:
				return true
			elif a.pos.x == b.pos.x:
				if a.pos.y < b.pos.y:
					return true
		return false
	
	func equals(b):
		return pos.distance_to(b.pos) < EPSILON

	static func make_clockwise(vl):
		assert(len(vl) == 3)
		var area2 = (vl[1].pos.x - vl[0].pos.x) * (vl[2].pos.z - vl[0].pos.z) - (vl[1].pos.z - vl[0].pos.z) * (vl[2].pos.x - vl[0].pos.x)
		if area2 > 0:
			var tmp = vl[2]
			vl[2] = vl[1]
			vl[1] = tmp
	
	func check_for_depency():
		# find the lowest attached vertex, 
		# if lower that this, set as dependancy
		# return true if dependency found
		var min_connected = self

		# Find the lowest
		for v in connectors:
			if v.pos.y < min_connected.pos.y:
				min_connected = v

		# Lower than this?
		if not min_connected.equals(self):
			dependancy = min_connected
			min_connected.dependants = self
			return true
		else:
			return false

class Edge:
	var v1    # Vertex
	var v2    # Vertex

	# parent references
	var tris       # Array of parent Triangle

	func _init(vert1, vert2):
		# Add the vertices in sorted order
		# This simplifies equality test
		if Vertex.sort(vert1, vert2):
			v1 = vert1
			v2 = vert2
		else:
			v1 = vert2
			v2 = vert1

		# Update joined vertices:
		v1.edges.append(self)
		v1.connectors.append(v2)
		v2.edges.append(self)
		v2.connectors.append(v1)

		# Initialise triangle list
		tris = []

	static func sort(a, b):
		# Sort by first vertex first - vertices should already be sorted
		if Vertex.sort(a.v1, b.v1):
			return true
		elif (a.v1.equals(b.v1)):
			if Vertex.sort(a.v2, b.v2):
				return true
		return false
	
	func equals(b):
		# This assumes vertices are in sorted order
		return v1.equals(b.v1) and v2.equals(b.v2)

class Triangle:
	var e1
	var e2
	var e3
	var v1
	var v2
	var v3

	func _init(edge1, edge2, edge3, vert1, vert2, vert3):
		e1 = edge1
		e2 = edge2
		e3 = edge3
		v1 = vert1
		v2 = vert2
		v3 = vert3
		for c in [edge1, edge2, edge3, vert1, vert2, vert3]:
			c.tris.append(self)
	
	static func sort(a, b):
		# Sort by first edge first - edges will already be in order
		if Edge.sort(a.e1, b.e1):
			return true
		elif a.e1.equals(b.e1):
			if Edge.sort(a.e2, b.e2):
				return true
			elif a.e2.equals(b.e2):
				if Edge.sort(a.e3, b.e3):
					return true
		return false

	func equals(b):
		return e1.equals(b.e1) and e2.equals(b.e2) and e3.equals(b.e3)

func _init():
	vertices  = []
	edges     = []
	triangles = []

func clear():
	vertices.clear()
	edges.clear()
	triangles.clear()

func add_triangle(vec1, vec2, vec3):
	# Add vertices, or use existing ones
	var vl = []
	for vector in [Vertex.new(vec1), Vertex.new(vec2), Vertex.new(vec3)]:
		var v = vector
		var v_ind = vertices.bsearch_custom(v, Vertex, "sort")
		if vertices and v_ind >= 0 and v_ind < len(vertices) and v.equals(vertices[v_ind]):
			v = vertices[v_ind]
		else:
			vertices.insert(v_ind, v)
		vl.append(v)
	Vertex.make_clockwise(vl)

	# Add edges, or use existing ones
	var el = []
	for edge in [Edge.new(vl[0], vl[1]), Edge.new(vl[1], vl[2]), Edge.new(vl[2], vl[0])]:
		var e = edge
		var e_ind = edges.bsearch_custom(e, Edge, "sort")
		if edges and e_ind >= 0 and e_ind < len(edges) and e.equals(edges[e_ind]):
			e = edges[e_ind]
		else:
			edges.insert(e_ind, e)
		el.append(e)
	
	# Add triangle
	var tri = Triangle.new(el[0], el[1], el[2], vl[0], vl[1], vl[2])
	var t_ind = triangles.bsearch_custom(tri, Triangle, "sort")
	# Not super worried about duplicates here
	triangles.insert(t_ind, tri)

func create_height_features(hashes, base_height, start_amp, amp_multiplier):
	# This takes an array of hash functions to be accumulated for each vertex
	# The hash instances in hashes need to implement a getHash(x, y) function
	# Each getHash will be call for each vertex and the height added by amplitude
	# Where amplitude is modified for each hashes by the multiplier

	# Reset limits
	min_height = INF
	max_height = -INF

	for v in vertices:
		var new_height = base_height
		var amp = start_amp
		for p in hashes:
			new_height += p.getHash(v.pos.x, v.pos.z) * amp
			amp *= amp_multiplier
		v.pos.y = new_height
		min_height = min(min_height, new_height)
		max_height = max(max_height, new_height)

func update_vertex_indices():
	# Vertices should already be ordered and unique
	# Just update the internal indices
	var ind = 0
	for vert in vertices:
		vert.index = ind
		ind += 1

func create_flow_trees():
	non_dependants = []
	for v in vertices:
		if not v.check_for_depency():
			non_dependants.append(v)

func erode_height_features():
	pass