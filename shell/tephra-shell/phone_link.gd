extends Node
## Phone link: a small web server on the local network, so a phone can type into Tephra's on-screen keyboard and save
## screenshots and recordings. Nothing runs until a screen asks for it (phone_screen.gd shows the QR code), it stops by
## itself, and every request needs the random code that is in the QR code's address (kept in a cookie after the first
## page). Only the Album's two folders can be read, and nothing can be written except the keyboard's text.
##
##   GET  /            the page (typing box, captures)
##   GET  /state       what the keyboard is asking for: {typing: {open, title, text, secret, max}}
##   POST /text        {text, done}: sets the keyboard's text, and presses Done when done is true
##   POST /cancel      closes the keyboard without a result
##   GET  /captures    the screenshots and recordings, newest first
##   GET  /thumb/NAME  a small picture of a screenshot
##   GET  /f/NAME      the file itself (?dl=1 to save it); ranges are supported so videos play on the phone

signal phone_connected   # the first request that carried the right code

const Album = preload("res://album.gd")
const PORTS := [8765, 8766, 8767, 8768, 8769, 8770, 8771, 8772]
const IDLE_STOP := 900.0       # seconds without any request before it switches itself off
const MAX_BODY := 65536
const CHUNK := 262144
const THUMB_W := 360
const COOKIE := "tephra_phone"

var running := false
var port := 0
var token := ""
var seen_phone := false
var for_typing := false
var _home
var _server: TCPServer
var _clients: Array = []
var _idle := 0.0
var _stop_in := -1.0           # seconds until it stops after the typing is over (a reply in flight still gets out)
var _thumbs := {}              # file name -> jpeg bytes

func setup(home) -> void:
	_home = home

# ---------- Start and stop ----------
func start(typing: bool) -> bool:
	if running:
		for_typing = for_typing or typing
		return true
	_server = TCPServer.new()
	port = 0
	for p in PORTS:
		if _server.listen(p, "*") == OK:
			port = p
			break
	if port == 0:
		_server = null
		return false
	token = Crypto.new().generate_random_bytes(8).hex_encode()
	running = true
	seen_phone = false
	for_typing = typing
	_idle = 0.0
	_stop_in = -1.0
	return true

func stop() -> void:
	for c in _clients:
		_close_client(c)
	_clients.clear()
	if _server != null:
		_server.stop()
	_server = null
	running = false
	for_typing = false
	_thumbs.clear()

## The typing side is done (the keyboard closed): the server goes too, unless captures are being shared.
func stop_typing() -> void:
	if running and for_typing and not _home.phone_screen.sharing_captures():
		_stop_in = 1.5

func _exit_tree() -> void:
	stop()

# ---------- Addresses ----------
## This PC's address on the home network ("" when there is none): 192.168.x.x first, then 10.x.x.x, then 172.16-31.
static func lan_ip() -> String:
	var forced := OS.get_environment("TEPHRA_PHONE_IP")  # for testing, or a network with an unusual address
	if forced != "":
		return forced
	var best := ""
	var rank := 9
	for a in IP.get_local_addresses():
		var s := str(a)
		if s.contains(":"):
			continue
		var r := 9
		if s.begins_with("192.168."):
			r = 0
		elif s.begins_with("10."):
			r = 1
		elif s.begins_with("172."):
			var second := int(s.split(".")[1])
			if second >= 16 and second <= 31 and second != 17:  # 172.17 is Docker's own network
				r = 2
		if r < rank:
			rank = r
			best = s
	return best

func base_url() -> String:
	var ip := lan_ip()
	return "" if ip == "" or not running else "http://%s:%d/?t=%s" % [ip, port, token]

func file_url(name: String) -> String:
	var u := base_url()
	return "" if u == "" else u + "&view=" + name.uri_encode()

# ---------- The loop ----------
func _process(delta: float) -> void:
	if not running:
		return
	_idle += delta
	if _idle > IDLE_STOP:
		stop()
		return
	if _stop_in >= 0.0:
		_stop_in -= delta
		if _stop_in < 0.0:
			stop()
			return
	while _server.is_connection_available():
		_clients.append({"peer": _server.take_connection(), "in": PackedByteArray(), "out": PackedByteArray(), "age": 0.0,
			"busy": false, "file": null, "left": 0})
	for c in _clients.duplicate():
		_service(c, delta)

func _service(c: Dictionary, delta: float) -> void:
	var p: StreamPeerTCP = c["peer"]
	p.poll()
	var st := p.get_status()
	if st != StreamPeerTCP.STATUS_CONNECTED:
		if st == StreamPeerTCP.STATUS_ERROR or st == StreamPeerTCP.STATUS_NONE:
			_drop(c)
		return
	c["age"] += delta
	if not c["busy"]:
		var n := p.get_available_bytes()
		if n > 0:
			var got := p.get_data(n)
			if got[0] == OK:
				var inb: PackedByteArray = c["in"]  # packed arrays are copied out of a dictionary: put the longer one back
				inb.append_array(got[1])
				c["in"] = inb
		if (c["in"] as PackedByteArray).size() > MAX_BODY + 8192:
			_drop(c)
			return
		_try_request(c)
		if c["age"] > 20.0 and not c["busy"]:
			_drop(c)
			return
	# Sending: what is queued, then the next piece of a file.
	var out: PackedByteArray = c["out"]
	if out.is_empty() and c["file"] != null and int(c["left"]) > 0:
		var f: FileAccess = c["file"]
		var take := mini(CHUNK, int(c["left"]))
		out = f.get_buffer(take)
		c["left"] = int(c["left"]) - take
		c["out"] = out
	if not out.is_empty():
		var sent := p.put_partial_data(out)
		if sent[0] != OK:
			_drop(c)
			return
		c["out"] = out.slice(int(sent[1]))
		_idle = 0.0
	elif c["busy"] and (c["file"] == null or int(c["left"]) <= 0):
		_drop(c)  # everything is sent

func _close_client(c: Dictionary) -> void:
	if c["file"] != null:
		(c["file"] as FileAccess).close()
		c["file"] = null
	(c["peer"] as StreamPeerTCP).disconnect_from_host()

func _drop(c: Dictionary) -> void:
	_close_client(c)
	_clients.erase(c)

# ---------- Requests ----------
func _try_request(c: Dictionary) -> void:
	var buf: PackedByteArray = c["in"]
	var end := -1
	for i in range(0, buf.size() - 3):
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			end = i
			break
	if end < 0:
		return
	var head := buf.slice(0, end).get_string_from_utf8().split("\r\n")
	var line := str(head[0]).split(" ")
	if line.size() < 2:
		_drop(c)
		return
	var headers := {}
	for i in range(1, head.size()):
		var kv := str(head[i]).split(":", true, 1)
		if kv.size() == 2:
			headers[kv[0].strip_edges().to_lower()] = kv[1].strip_edges()
	var length := int(headers.get("content-length", "0"))
	if length > MAX_BODY:
		_reply(c, 413, "text/plain", "Too much".to_utf8_buffer())
		return
	if buf.size() < end + 4 + length:
		return  # the rest of the body is still coming
	var body := buf.slice(end + 4, end + 4 + length)
	var target := str(line[1])
	var path := target.get_slice("?", 0)
	var query := {}
	if target.contains("?"):
		for pair in target.get_slice("?", 1).split("&", false):
			query[pair.get_slice("=", 0)] = pair.get_slice("=", 1).uri_decode() if pair.contains("=") else ""
	c["busy"] = true
	c["in"] = PackedByteArray()
	_route(c, str(line[0]), path, query, headers, body)

func _cookie(headers: Dictionary) -> String:
	for part in str(headers.get("cookie", "")).split(";", false):
		var kv := part.strip_edges().split("=", true, 1)
		if kv.size() == 2 and kv[0] == COOKIE:
			return kv[1]
	return ""

func _route(c: Dictionary, method: String, path: String, query: Dictionary, headers: Dictionary, body: PackedByteArray) -> void:
	var ok := str(query.get("t", "")) == token or _cookie(headers) == token
	if not ok:
		_reply(c, 403, "text/plain; charset=utf-8", "Scan the code on the screen again.".to_utf8_buffer())
		return
	_idle = 0.0
	if not seen_phone:
		seen_phone = true
		phone_connected.emit()
	if method == "GET" and path == "/":
		_reply(c, 200, "text/html; charset=utf-8", _page().to_utf8_buffer(),
			{"Set-Cookie": "%s=%s; Path=/; SameSite=Strict" % [COOKIE, token]})
	elif method == "GET" and path == "/state":
		_json(c, {"typing": _home.keyboard.phone_state()})
	elif method == "POST" and path == "/text":
		var d = JSON.parse_string(body.get_string_from_utf8())
		if not d is Dictionary:
			_json(c, {"ok": false, "error": "Bad request"}, 400)
			return
		_home.keyboard.phone_set(str(d.get("text", "")))
		var err := ""
		if bool(d.get("done", false)):
			err = _home.keyboard.phone_submit()
		_json(c, {"ok": err == "", "error": err})
	elif method == "POST" and path == "/cancel":
		if _home.keyboard.is_open:
			_home.keyboard.close(false)
		_json(c, {"ok": true})
	elif method == "GET" and path == "/captures":
		_json(c, _captures())
	elif method == "GET" and path.begins_with("/thumb/"):
		_thumb(c, path.substr(7).uri_decode())
	elif method == "GET" and path.begins_with("/f/"):
		_file(c, path.substr(3).uri_decode(), headers, str(query.get("dl", "")) == "1")
	else:
		_reply(c, 404, "text/plain; charset=utf-8", "Not found".to_utf8_buffer())

# ---------- Replies ----------
func _reply(c: Dictionary, code: int, ctype: String, body: PackedByteArray, extra := {}) -> void:
	c["busy"] = true
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\nCache-Control: no-store\r\n" \
		% [code, _status_text(code), ctype, body.size()]
	for k in extra:
		head += "%s: %s\r\n" % [k, str(extra[k])]
	c["out"] = (head + "\r\n").to_utf8_buffer() + body

func _json(c: Dictionary, data, code := 200) -> void:
	_reply(c, code, "application/json; charset=utf-8", JSON.stringify(data).to_utf8_buffer())

static func _status_text(code: int) -> String:
	match code:
		200: return "OK"
		206: return "Partial Content"
		400: return "Bad Request"
		403: return "Forbidden"
		404: return "Not Found"
		413: return "Payload Too Large"
		416: return "Range Not Satisfiable"
	return "OK"

# ---------- Captures ----------
func _list() -> Array:
	var out: Array = []
	for d in [[Album.folder(), Album.EXTENSIONS, "image"], [Album.video_folder(), Album.VIDEO_EXTENSIONS, "video"]]:
		var dir := DirAccess.open(d[0])
		if dir == null:
			continue
		for f in dir.get_files():
			if f.get_extension().to_lower() in d[1]:
				var p: String = str(d[0]) + "/" + f
				out.append({"name": f, "kind": d[2], "path": p, "time": FileAccess.get_modified_time(p)})
	out.sort_custom(func(a, b): return a["time"] > b["time"])
	return out

func _captures() -> Array:
	var out: Array = []
	for e in _list().slice(0, 200):
		var f := FileAccess.open(str(e["path"]), FileAccess.READ)
		var size := f.get_length() if f != null else 0
		out.append({"name": e["name"], "kind": e["kind"], "time": e["time"], "size": size})
	return out

## The path of a capture by its file name, only from the Album's two folders ("" otherwise).
func _find(name: String) -> String:
	if name == "" or name != name.get_file() or name.begins_with("."):
		return ""
	for e in _list():
		if e["name"] == name:
			return str(e["path"])
	return ""

func _thumb(c: Dictionary, name: String) -> void:
	var path := _find(name)
	if path == "" or not name.get_extension().to_lower() in Album.EXTENSIONS:
		_reply(c, 404, "text/plain", "Not found".to_utf8_buffer())
		return
	if not _thumbs.has(name):
		var img := Image.load_from_file(path)
		if img == null or img.is_empty():
			_reply(c, 404, "text/plain", "Not found".to_utf8_buffer())
			return
		if img.get_width() > THUMB_W:
			img.resize(THUMB_W, maxi(1, img.get_height() * THUMB_W / img.get_width()), Image.INTERPOLATE_BILINEAR)
		if _thumbs.size() > 80:
			_thumbs.clear()
		_thumbs[name] = img.save_jpg_to_buffer(0.8)
	_reply(c, 200, "image/jpeg", _thumbs[name], {"Cache-Control": "max-age=3600"})

static func _mime(ext: String) -> String:
	match ext.to_lower():
		"png": return "image/png"
		"jpg", "jpeg": return "image/jpeg"
		"webp": return "image/webp"
		"mp4": return "video/mp4"
		"webm": return "video/webm"
		"mkv": return "video/x-matroska"
		"mov": return "video/quicktime"
	return "application/octet-stream"

func _file(c: Dictionary, name: String, headers: Dictionary, download: bool) -> void:
	var path := _find(name)
	var f := FileAccess.open(path, FileAccess.READ) if path != "" else null
	if f == null:
		_reply(c, 404, "text/plain", "Not found".to_utf8_buffer())
		return
	var total := f.get_length()
	var start := 0
	var last := total - 1
	var code := 200
	var rng := str(headers.get("range", ""))
	if rng.begins_with("bytes="):
		var spec := rng.substr(6).get_slice(",", 0)
		var a := spec.get_slice("-", 0)
		var b := spec.get_slice("-", 1)
		if a == "":
			start = maxi(0, total - int(b))  # the last N bytes
		else:
			start = int(a)
			if b != "":
				last = mini(int(b), total - 1)
		if start > last or start >= total:
			f.close()
			_reply(c, 416, "text/plain", "Bad range".to_utf8_buffer(), {"Content-Range": "bytes */%d" % total})
			return
		code = 206
	var length := last - start + 1
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nAccept-Ranges: bytes\r\nConnection: close\r\n" \
		% [code, _status_text(code), _mime(name.get_extension()), length]
	if code == 206:
		head += "Content-Range: bytes %d-%d/%d\r\n" % [start, last, total]
	if download:
		head += "Content-Disposition: attachment; filename=\"%s\"\r\n" % name.replace("\"", "")
	c["busy"] = true
	c["out"] = (head + "\r\n").to_utf8_buffer()
	f.seek(start)
	c["file"] = f
	c["left"] = length

# ---------- The page ----------
func _page() -> String:
	return PAGE

const PAGE := """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Tephra</title>
<style>
:root{color-scheme:dark;--bg:#0b0f1a;--card:#151b2b;--text:#e8ecf4;--muted:#8d97ad;--accent:#4ea1ff}
*{box-sizing:border-box}
body{margin:0;padding:16px;background:var(--bg);color:var(--text);font:17px/1.4 system-ui,sans-serif}
h1{font-size:26px;margin:4px 0 16px}
h2{font-size:18px;margin:0 0 10px}
section{background:var(--card);border-radius:16px;padding:16px;margin-bottom:16px}
input{width:100%;font:inherit;padding:14px;border-radius:12px;border:2px solid #2a3350;background:#0e1424;color:var(--text)}
input:focus{outline:none;border-color:var(--accent)}
.row{display:flex;gap:10px;margin-top:12px}
button,a.btn{flex:1;font:inherit;padding:12px;border-radius:12px;border:0;background:#2a3350;color:var(--text);text-align:center;text-decoration:none}
button.primary{background:var(--accent);color:#04101f;font-weight:600}
.muted{color:var(--muted)}
.err{color:#ff8b7e;margin-top:8px;min-height:1.2em}
#grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:12px}
.item{background:#0e1424;border-radius:12px;overflow:hidden;border:2px solid transparent}
.item.pick{border-color:var(--accent)}
.item img,.item .vid{display:block;width:100%;aspect-ratio:16/9;object-fit:cover;background:#1b2338}
.item .vid{display:flex;align-items:center;justify-content:center;font-size:34px}
.item .meta{padding:8px 10px;font-size:13px;color:var(--muted)}
.item a.btn{display:block;margin:0 10px 10px;padding:8px;font-size:15px}
#conn{color:#ff8b7e;min-height:1.2em}
</style></head><body>
<h1>Tephra</h1>
<div id="conn"></div>
<section id="type"><h2 id="ttitle">Type</h2>
<div id="tidle" class="muted">Nothing is waiting for text right now. Open a text box in Tephra and it appears here.</div>
<div id="tbox" hidden>
<input id="tin" autocomplete="off" autocapitalize="sentences" spellcheck="false">
<div class="row"><button id="tshow">Show</button><button id="tcancel">Cancel</button><button id="tdone" class="primary">Done</button></div>
<div id="terr" class="err"></div></div></section>
<section><h2>Screenshots and recordings</h2>
<div id="grid"></div><div id="cempty" class="muted" hidden>None yet. Press the capture button on your controller in Tephra.</div></section>
<script>
const $=id=>document.getElementById(id);
const focus=new URLSearchParams(location.search).get('view');
let open=false,showPw=false,secret=false,timer=null,finished=false,doneMsg='';
const IDLE='Nothing is waiting for text right now. Open a text box in Tephra and it appears here.';
function finish(msg){finished=true;doneMsg=msg;open=false;$('tbox').hidden=true;$('tidle').hidden=false;$('tidle').textContent=msg;$('conn').textContent=''}
async function api(path,opt){const r=await fetch(path,opt);if(!r.ok)throw new Error(r.status);return r.json()}
function post(path,data){return api(path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data||{})})}
function fit(){$('tin').type=(secret&&!showPw)?'password':'text';$('tshow').hidden=!secret;$('tshow').textContent=showPw?'Hide':'Show'}
async function poll(){
  try{
    const s=(await api('/state')).typing;
    $('conn').textContent='';
    if(s.open){
      finished=false;
      $('tbox').hidden=false;$('tidle').hidden=true;$('ttitle').textContent=s.title||'Type';
      const inp=$('tin');secret=s.secret;inp.maxLength=s.max;fit();
      if(!open){inp.value=s.text;inp.focus()}
      else if(document.activeElement!==inp&&inp.value!==s.text){inp.value=s.text}
      open=true;
    }else{$('tbox').hidden=true;$('tidle').hidden=false;$('tidle').textContent=finished?doneMsg:IDLE;open=false;$('terr').textContent=''}
  }catch(e){if(!finished)$('conn').textContent='Lost contact with Tephra. Is it still on?'}
  setTimeout(poll,finished?3000:1200);
}
$('tin').addEventListener('input',()=>{clearTimeout(timer);timer=setTimeout(()=>post('/text',{text:$('tin').value}).catch(()=>{}),120)});
$('tshow').onclick=()=>{showPw=!showPw;fit()};
$('tcancel').onclick=()=>post('/cancel').then(()=>finish('Cancelled.')).catch(()=>{});
$('tdone').onclick=async()=>{
  try{const r=await post('/text',{text:$('tin').value,done:true});if(r.ok)finish('Sent to Tephra.');else $('terr').textContent=r.error}
  catch(e){$('terr').textContent='Could not reach Tephra'}
};
function size(n){return n>=1e9?(n/1e9).toFixed(1)+' GB':n>=1e6?(n/1e6).toFixed(1)+' MB':Math.max(1,Math.round(n/1e3))+' KB'}
async function captures(){
  try{
    const list=await api('/captures');const g=$('grid');g.textContent='';
    $('cempty').hidden=list.length>0;
    for(const f of list){
      const d=document.createElement('div');d.className='item'+(f.name===focus?' pick':'');
      const u='/f/'+encodeURIComponent(f.name);
      const top=document.createElement(f.kind==='image'?'a':'div');
      if(f.kind==='image'){top.href=u;const im=document.createElement('img');im.loading='lazy';im.src='/thumb/'+encodeURIComponent(f.name);top.appendChild(im)}
      else{top.className='vid';top.textContent='\\u25B6'}
      d.appendChild(top);
      const m=document.createElement('div');m.className='meta';
      m.textContent=new Date(f.time*1000).toLocaleString([], {month:'short',day:'numeric',hour:'numeric',minute:'2-digit'})+' - '+size(f.size);
      d.appendChild(m);
      const a=document.createElement('a');a.className='btn';a.href=u+'?dl=1';a.textContent='Save';a.setAttribute('download',f.name);
      d.appendChild(a);g.appendChild(d);
      if(f.name===focus)setTimeout(()=>d.scrollIntoView({block:'center'}),50);
    }
  }catch(e){}
}
poll();captures();
</script></body></html>"""
