class_name RandomnessManager
extends RefCounted

# Integer-only counter hash. Explicit wrap keeps CPU initialization portable.
static func hash32(value: int) -> int:
	var x := value & 0xffffffff
	x = (x ^ ((x << 13) & 0xffffffff)) & 0xffffffff
	x = (x ^ (x >> 17)) & 0xffffffff
	x = (x ^ ((x << 5) & 0xffffffff)) & 0xffffffff
	return x

static func initial_state(side: int, seed_value: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(side * side * 4)
	var radius := side - 8
	for y in range(side):
		for x in range(side):
			var dx := 2 * x + 1 - side
			var dy := 2 * y + 1 - side
			var material := 0 # Water is implicit; no bulk fluid solver in M1.
			var h := hash32((y * side + x) ^ seed_value)
			if dx * dx + dy * dy > radius * radius:
				material = 4
			elif y > side * 0.17 and y < side * 0.46 and h % 100 < 88:
				material = 1 + (int(y / 5) + int(h % 3 == 0)) % 3
			data.encode_u32((y * side + x) * 4, material)
	return data

# Gas occupies existing liquid cells; it never replaces sand or wall inventory.
static func liquid_state(side:int,seed_value:int)->PackedByteArray:
	var data:=initial_state(side,seed_value)
	for y in range(side):
		for x in range(side):
			if data.decode_u32((y*side+x)*4)!=0:continue
			for bubble in range(7):
				var h:=hash32(seed_value ^ (bubble*1597334677))
				var cx:=side*(.18+.105*bubble+float((h>>8)%17-8)*.0015)
				var cy:=side*(.51+float((h>>16)%17)*.002)
				var radius:=side*(.023+float(h%9)*.002)
				if Vector2(x-cx,y-cy).length_squared()<radius*radius:
					data.encode_u32((y*side+x)*4,5)
	return data
