extends RefCounted
## Some game covers come with a frame drawn into the picture itself (Portal's has a white line and a
## dark border all the way round). On a tile that frame sits right next to Tephra's own soft edge, so
## the tile looks like it has a flat, blocky line instead of the glossy edge other covers get.
## This finds such a frame (plain, even-coloured rows and columns along all four edges) and cuts it
## off, so every cover fills its tile edge to edge and gets the same shine.

const MAX_FRACTION := 0.08   # never cut more than 8% from each side
const MIN_FRACTION := 0.012  # under this it's not a frame, just the picture's edge
const FLAT := 0.055          # how even a row must be to count as frame (spread of brightness, 0-1)
const PROBE_W := 160         # the check runs on a small copy, so it is quick

## Returns the image with any built-in frame cut away (or the same image when there is none).
static func trim(img: Image) -> Image:
	if img == null or img.is_empty() or img.get_width() < 64 or img.get_height() < 64:
		return img
	var small := img.duplicate() as Image
	if small.is_compressed() and small.decompress() != OK:
		return img
	small.clear_mipmaps()
	small.convert(Image.FORMAT_RGB8)
	var pw := PROBE_W
	var ph := maxi(roundi(float(img.get_height()) * pw / img.get_width()), 16)
	small.resize(pw, ph, Image.INTERPOLATE_BILINEAR)
	# A frame is equally thick on every side, so the thinnest side (in pixels) is the frame.
	var px := 1.0e9
	for side in 4:
		px = minf(px, _frame_depth(small, side))
	var w := img.get_width()
	var h := img.get_height()
	var scale := float(w) / pw
	var cut := (px + 1.0) * scale  # a hair more, so no sliver of the frame's edge is left
	var shortest := float(mini(w, h))
	if px <= 0.0 or cut < shortest * MIN_FRACTION:
		return img
	var c := roundi(minf(cut, shortest * MAX_FRACTION))
	return img.get_region(Rect2i(c, c, w - c * 2, h - c * 2))

## How many pixels in (on the small copy) the plain rows or columns go on one side.
## side: 0 top, 1 bottom, 2 left, 3 right.
static func _frame_depth(img: Image, side: int) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var horizontal := side < 2
	var length := w if horizontal else h # the length of one row / column
	var max_d := int(mini(w, h) * MAX_FRACTION)
	var skip := int(length * 0.12)       # leave out the corners (they are often rounded)
	var depth := 0
	for d in max_d:
		var vals := PackedFloat32Array()
		for k in range(skip, length - skip, 2):
			var x := k if horizontal else (d if side == 2 else w - 1 - d)
			var y := (d if side == 0 else h - 1 - d) if horizontal else k
			vals.append(img.get_pixel(x, y).get_luminance())
		if _spread(vals) > FLAT:
			break
		depth = d + 1
	if depth >= max_d:
		return 0.0  # plain all the way in: a plain background, not a frame, so leave it
	return float(depth)

static func _spread(v: PackedFloat32Array) -> float:
	if v.is_empty():
		return 1.0
	var mean := 0.0
	for x in v:
		mean += x
	mean /= v.size()
	var s := 0.0
	for x in v:
		s += (x - mean) * (x - mean)
	return sqrt(s / v.size())
