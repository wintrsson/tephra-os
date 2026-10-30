extends RefCounted
## QR codes: text in, a square of dark and light modules out (byte mode, error correction level M, versions 1 to 10, so
## up to 213 bytes). Used for the phone link: the phone scans it to open Tephra's small web page. Written for the
## standard (ISO 18004) layout: finder, alignment and timing patterns, Reed-Solomon codewords, the best of 8 masks.

## For each version 1..10 at level M: [error correction codewords per block, [[blocks, data codewords per block], ...]]
const BLOCKS := [
	[],
	[10, [[1, 16]]], [16, [[1, 28]]], [26, [[1, 44]]], [18, [[2, 32]]], [24, [[2, 43]]],
	[16, [[4, 27]]], [18, [[4, 31]]], [22, [[2, 38], [2, 39]]], [22, [[3, 36], [2, 37]]], [26, [[4, 43], [1, 44]]],
]
const ALIGN := [[], [], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34], [6, 22, 38], [6, 24, 42], [6, 26, 46], [6, 28, 50]]

static var _exp: PackedInt32Array
static var _log: PackedInt32Array

static func _tables() -> void:
	if _exp.size() > 0:
		return
	_exp.resize(512)
	_log.resize(256)
	var x := 1
	for i in 255:
		_exp[i] = x
		_log[x] = i
		x <<= 1
		if x & 0x100:
			x ^= 0x11D
	for i in range(255, 512):
		_exp[i] = _exp[i - 255]

static func _mul(a: int, b: int) -> int:
	if a == 0 or b == 0:
		return 0
	return _exp[_log[a] + _log[b]]

## The error correction codewords for one block of data codewords.
static func _rs(data: PackedByteArray, ec_len: int) -> PackedByteArray:
	_tables()
	var gen := PackedInt32Array([1])
	for i in ec_len:
		var next := PackedInt32Array()
		next.resize(gen.size() + 1)
		for j in gen.size():
			next[j] ^= gen[j]
			next[j + 1] ^= _mul(gen[j], _exp[i])
		gen = next
	var rem := PackedInt32Array()
	rem.resize(ec_len)
	for b in data:
		var factor: int = b ^ rem[0]
		for j in ec_len - 1:
			rem[j] = rem[j + 1]
		rem[ec_len - 1] = 0
		for j in ec_len:
			rem[j] ^= _mul(gen[j + 1], factor)
	var out := PackedByteArray()
	for v in rem:
		out.append(v)
	return out

static func _data_capacity(version: int) -> int:
	var total := 0
	for g in BLOCKS[version][1]:
		total += int(g[0]) * int(g[1])
	return total

## The smallest version (1 to 10) whose room fits this many bytes, or 0 when it is too long.
static func _version_for(n: int) -> int:
	for v in range(1, 11):
		var cc_bits := 8 if v < 10 else 16
		if 4 + cc_bits + 8 * n <= _data_capacity(v) * 8:
			return v
	return 0

static func _bit(v: int, i: int) -> bool:
	return ((v >> i) & 1) != 0

## The modules of the code as rows of booleans (true = dark), or an empty array when the text is too long.
static func matrix(text: String) -> Array:
	var bytes := text.to_utf8_buffer()
	var version := _version_for(bytes.size())
	if version == 0:
		return []
	var size := 17 + 4 * version
	var cap := _data_capacity(version)
	# 1. The data bits: mode (byte), length, the bytes, a terminator, padding.
	var bits: Array = []
	var put := func(value: int, count: int) -> void:
		for i in range(count - 1, -1, -1):
			bits.append((value >> i) & 1)
	put.call(4, 4)
	put.call(bytes.size(), 8 if version < 10 else 16)
	for b in bytes:
		put.call(b, 8)
	for i in mini(4, cap * 8 - bits.size()):
		bits.append(0)
	while bits.size() % 8 != 0:
		bits.append(0)
	var data := PackedByteArray()
	for i in range(0, bits.size(), 8):
		var v := 0
		for j in 8:
			v = (v << 1) | int(bits[i + j])
		data.append(v)
	var pad := 0xEC
	while data.size() < cap:
		data.append(pad)
		pad = 0x11 if pad == 0xEC else 0xEC
	# 2. Blocks, their error correction, interleaved.
	var ec_len: int = BLOCKS[version][0]
	var blocks: Array = []
	var ecs: Array = []
	var pos := 0
	for g in BLOCKS[version][1]:
		for k in int(g[0]):
			var blk := data.slice(pos, pos + int(g[1]))
			pos += int(g[1])
			blocks.append(blk)
			ecs.append(_rs(blk, ec_len))
	var final := PackedByteArray()
	var longest := 0
	for blk in blocks:
		longest = maxi(longest, blk.size())
	for i in longest:
		for blk in blocks:
			if i < blk.size():
				final.append(blk[i])
	for i in ec_len:
		for ec in ecs:
			final.append(ec[i])
	# 3. The grid: function patterns first.
	var mod: Array = []
	var fn: Array = []
	for y in size:
		var r: Array = []
		var f: Array = []
		r.resize(size)
		f.resize(size)
		r.fill(false)
		f.fill(false)
		mod.append(r)
		fn.append(f)
	var set_fn := func(x: int, y: int, dark: bool) -> void:
		if x >= 0 and x < size and y >= 0 and y < size:
			mod[y][x] = dark
			fn[y][x] = true
	for i in size:
		set_fn.call(6, i, i % 2 == 0)
		set_fn.call(i, 6, i % 2 == 0)
	for c in [[3, 3], [size - 4, 3], [3, size - 4]]:
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				var dist := maxi(absi(dx), absi(dy))
				set_fn.call(int(c[0]) + dx, int(c[1]) + dy, dist != 2 and dist != 4)
	var al: Array = ALIGN[version]
	for i in al.size():
		for j in al.size():
			if (i == 0 and j == 0) or (i == 0 and j == al.size() - 1) or (i == al.size() - 1 and j == 0):
				continue
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					set_fn.call(int(al[i]) + dx, int(al[j]) + dy, maxi(absi(dx), absi(dy)) != 1)
	_format_bits(set_fn, size, 0)  # reserves the format areas (the real bits come with the mask)
	if version >= 7:
		var rem := version
		for i in 12:
			rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
		var vbits := (version << 12) | rem
		for i in 18:
			var dark := _bit(vbits, i)
			var a := size - 11 + i % 3
			var b := i / 3
			set_fn.call(a, b, dark)
			set_fn.call(b, a, dark)
	# 4. The data, zig-zagging up and down two columns at a time from the bottom right.
	var total_bits := final.size() * 8
	var idx := 0
	var right := size - 1
	while right >= 1:
		if right == 6:
			right = 5
		for vert in size:
			for j in 2:
				var x := right - j
				var upward := ((right + 1) & 2) == 0
				var y := size - 1 - vert if upward else vert
				if not fn[y][x] and idx < total_bits:
					mod[y][x] = _bit(final[idx >> 3], 7 - (idx & 7))
					idx += 1
		right -= 2
	# 5. The best of the 8 masks.
	var best_mask := 0
	var best_score := 1 << 30
	for m in 8:
		_apply_mask(mod, fn, size, m)
		_format_bits(set_fn, size, m)
		var score := _penalty(mod, size)
		if score < best_score:
			best_score = score
			best_mask = m
		_apply_mask(mod, fn, size, m)  # undone
	_apply_mask(mod, fn, size, best_mask)
	_format_bits(set_fn, size, best_mask)
	return mod

static func _format_bits(set_fn: Callable, size: int, mask: int) -> void:
	var data := mask  # level M is 00
	var rem := data
	for i in 10:
		rem = (rem << 1) ^ ((rem >> 9) * 0x537)
	var bits := ((data << 10) | rem) ^ 0x5412
	for i in 6:
		set_fn.call(8, i, _bit(bits, i))
	set_fn.call(8, 7, _bit(bits, 6))
	set_fn.call(8, 8, _bit(bits, 7))
	set_fn.call(7, 8, _bit(bits, 8))
	for i in range(9, 15):
		set_fn.call(14 - i, 8, _bit(bits, i))
	for i in 8:
		set_fn.call(size - 1 - i, 8, _bit(bits, i))
	for i in range(8, 15):
		set_fn.call(8, size - 15 + i, _bit(bits, i))
	set_fn.call(8, size - 8, true)  # the one module that is always dark

static func _apply_mask(mod: Array, fn: Array, size: int, m: int) -> void:
	for y in size:
		for x in size:
			if fn[y][x]:
				continue
			var flip := false
			match m:
				0: flip = (x + y) % 2 == 0
				1: flip = y % 2 == 0
				2: flip = x % 3 == 0
				3: flip = (x + y) % 3 == 0
				4: flip = (x / 3 + y / 2) % 2 == 0
				5: flip = (x * y) % 2 + (x * y) % 3 == 0
				6: flip = ((x * y) % 2 + (x * y) % 3) % 2 == 0
				7: flip = ((x + y) % 2 + (x * y) % 3) % 2 == 0
			if flip:
				mod[y][x] = not mod[y][x]

static func _penalty(mod: Array, size: int) -> int:
	var score := 0
	var dark := 0
	for y in size:
		for x in size:
			if mod[y][x]:
				dark += 1
	# Runs of the same colour (rows, then columns) and finder-like patterns.
	for pass_i in 2:
		for a in size:
			var run := 1
			var line := ""
			for b in size:
				var cur: bool = mod[a][b] if pass_i == 0 else mod[b][a]
				line += "1" if cur else "0"
				if b > 0:
					var prev: bool = mod[a][b - 1] if pass_i == 0 else mod[b - 1][a]
					if cur == prev:
						run += 1
						if run == 5:
							score += 3
						elif run > 5:
							score += 1
					else:
						run = 1
			var from := 0
			while true:
				var p := line.find("10111010000", from)
				if p < 0:
					break
				score += 40
				from = p + 1
			from = 0
			while true:
				var p2 := line.find("00001011101", from)
				if p2 < 0:
					break
				score += 40
				from = p2 + 1
	for y in size - 1:
		for x in size - 1:
			var c: bool = mod[y][x]
			if c == mod[y][x + 1] and c == mod[y + 1][x] and c == mod[y + 1][x + 1]:
				score += 3
	var total := size * size
	var k := int(ceil(absf(float(dark) * 20.0 - float(total) * 10.0) / float(total))) - 1
	score += maxi(k, 0) * 10
	return score

## The code as a picture: black modules on white with a quiet border (4 modules), `px` pixels per module.
static func texture(text: String, px := 8, quiet := 4) -> ImageTexture:
	var m := matrix(text)
	if m.is_empty():
		return null
	var n := m.size()
	var side := (n + quiet * 2) * px
	var img := Image.create(side, side, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	for y in n:
		for x in n:
			if m[y][x]:
				img.fill_rect(Rect2i((x + quiet) * px, (y + quiet) * px, px, px), Color.BLACK)
	return ImageTexture.create_from_image(img)
