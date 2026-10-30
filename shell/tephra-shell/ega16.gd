extends RefCounted
## Turns a picture into the sixteen classic EGA colours with chunky pixels (the Temple theme's game covers):
## the picture is shrunk to a small size, each pixel is moved to the nearest of the 16 colours after an ordered dither
## (so smooth shading becomes a fine pattern, as on an old screen), then blown up 2x with hard edges.

const PALETTE := [
	Color("000000"), Color("0000AA"), Color("00AA00"), Color("00AAAA"), Color("AA0000"), Color("AA00AA"), Color("AA5500"), Color("AAAAAA"),
	Color("555555"), Color("5555FF"), Color("55FF55"), Color("55FFFF"), Color("FF5555"), Color("FF55FF"), Color("FFFF55"), Color("FFFFFF"),
]
const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

static func convert(img: Image, small_w: int) -> Image:
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var sw := mini(small_w, w)
	var sh := maxi(1, int(round(float(h) * float(sw) / float(w))))
	img.resize(sw, sh, Image.INTERPOLATE_BILINEAR)
	var out := Image.create(sw, sh, false, Image.FORMAT_RGBA8)
	var pal: Array = PALETTE
	for y in sh:
		for x in sw:
			var c := img.get_pixel(x, y)
			var d := (float(BAYER[(y & 3) * 4 + (x & 3)]) / 16.0 - 0.47) * 0.40
			var r := c.r + d
			var g := c.g + d
			var b := c.b + d
			var best := 0
			var bd := 1e9
			for i in 16:
				var p: Color = pal[i]
				var dr := r - p.r
				var dg := g - p.g
				var db := b - p.b
				var dist := dr * dr * 0.9 + dg * dg * 1.2 + db * db * 0.7
				if dist < bd:
					bd = dist
					best = i
			var pc: Color = pal[best]
			out.set_pixel(x, y, Color(pc, c.a))
	out.resize(sw * 2, sh * 2, Image.INTERPOLATE_NEAREST)
	return out
