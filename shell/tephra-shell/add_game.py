#!/usr/bin/env python3
"""Tephra: add a game's program to Steam as a non-Steam game (Library > Add a game).

  add_game.py guess <program>            -> {"title": "Hollow Knight"}
  add_game.py add <program> <title>      -> {"id": 3123456789, "title": ..., "proton": "proton_9", "exists": false}

"add" writes the game into Steam's own list of non-Steam games (userdata/<you>/config/shortcuts.vdf), exactly as
Steam's "Add a Non-Steam Game" does, so Steam starts it, tracks it and gives it its controller layout like any other
game. A Windows program (.exe) is also set to run with Proton (config/config.vdf, CompatToolMapping), using the same
Proton version Steam uses for all other titles ("Steam Play" setting), or Proton Experimental if none is set.

Steam must NOT be running: it reads both files when it starts and writes them back when it closes. Each file is
copied to <name>.tephra-backup first and is only written if this script can write back exactly what it read
(shortcuts.vdf), or only gets the new lines added in place (config.vdf), so nothing else in it can change.
Prints one line of JSON; on a problem {"error": "..."} and nothing is changed.
"""
import json
import os
import re
import shutil
import stat
import struct
import sys
import zlib

HOME = os.path.expanduser("~")
STEAM_ROOTS = [os.path.join(HOME, ".local/share/Steam"), os.path.join(HOME, ".steam/steam")]
EXTS = ("exe", "sh", "appimage", "x86_64")  # what can be added (keep in step with home.gd ADD_EXTS)


# ---------- A good name from the program's path ----------
# Folders that say nothing about the game (an Unreal game's program sits in Game/Binaries/Win64, for example).
GENERIC_DIRS = {"bin", "bin32", "bin64", "x64", "x86", "win64", "win32", "binaries", "game", "games", "launcher",
                "common", "steamapps", "drive_c", "program files", "program files (x86)", "downloads", "desktop",
                "app", "apps", "release", "build", "builds", "windows", "pc", "data", "content", "files", "linux"}
# Program names that say nothing about the game.
GENERIC_STEMS = {"game", "launcher", "start", "play", "run", "setup", "main", "client", "app", "launch", "default",
                 "bin", "start_game", "game_launcher", "playgame", "rungame", "application", "nw", "electron"}


def norm(s):
    """'Hollow_Knight v1.5 (GOG)' -> 'hollowknight': lower case, letters and digits only."""
    s = re.sub(r"\([^)]*\)|\[[^\]]*\]", " ", s)
    return re.sub(r"[^a-z0-9]", "", s.lower())


def tidy(name):
    """A file or folder name as a game title: no brackets, versions or build words, spaces between words."""
    t = re.sub(r"\([^)]*\)|\[[^\]]*\]|\{[^}]*\}", " ", name)
    t = t.replace("_", " ")
    if " " not in t.strip() and re.search(r"[A-Za-z0-9]{2,}\.[A-Za-z0-9]{2,}", t):
        t = t.replace(".", " ")  # "Some.Game" -> "Some Game" (but "P.T." stays)
    t = re.sub(r"(?i)[-\s]*(win(64|32)?|x64|x86|64bit|32bit)?[-\s]*shipping$", "", t)  # Unreal: "Game-Win64-Shipping"
    t = re.sub(r"(?i)\b(v|ver|version)\s?\d+(\.\d+)*[a-z]?\b", " ", t)  # v1.2, version 3
    t = re.sub(r"\b\d+\.\d+(\.\d+)*\b", " ", t)  # 1.0.4
    t = re.sub(r"(?i)\b(x64|x86|win64|win32|64bit|32bit|portable|repack|setup|gog|steam|drm free|drm-free)\b", " ", t)
    if " " not in t.strip() and re.search(r"[a-z][A-Z]", t):
        t = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", " ", t)  # "HollowKnight" -> "Hollow Knight"
    t = re.sub(r"\s+", " ", t).strip(" -.")
    if t and t == t.lower():
        t = " ".join(w[:1].upper() + w[1:] for w in t.split(" "))  # "hollow knight" -> "Hollow Knight"
    return t


def guess_title(path):
    path = os.path.realpath(path)
    stem = os.path.splitext(os.path.basename(path))[0] if path.lower().endswith(tuple("." + e for e in EXTS)) \
        else os.path.basename(path)
    folder = ""
    d = os.path.dirname(path)
    # Unreal games: <Game>/<Project>/Binaries/Win64/<Project>-Win64-Shipping.exe. The folder above the project is the
    # game's own folder ("Silent Hill f"); the project's name is often a short code ("SHf").
    parts = d.split(os.sep)
    low = [p.lower() for p in parts]
    if "binaries" in low:
        i = len(low) - 1 - low[::-1].index("binaries")
        if i >= 2:
            d = os.sep.join(parts[:i - 1])
    for _ in range(6):
        n = os.path.basename(d)
        if not n or d in (HOME, "/"):
            break
        if n.lower() not in GENERIC_DIRS:
            folder = n
            break
        d = os.path.dirname(d)
    s_t, f_t = tidy(stem), tidy(folder)
    generic = norm(s_t) in {norm(g) for g in GENERIC_STEMS} or len(norm(s_t)) <= 1
    if f_t and (generic or not s_t):
        return f_t
    if f_t and norm(s_t) and norm(f_t) and (norm(s_t) in norm(f_t) or norm(f_t) in norm(s_t)):
        # The folder and the program say the same thing: the folder is the nicer of the two ("Hollow Knight" rather
        # than "hollow_knight", "PT Remake" rather than "PT").
        return f_t
    if f_t and "binaries" in path.lower().split(os.sep):
        return f_t  # Unreal: the game's folder, never the project's short code
    return s_t or f_t or "Game"


# ---------- Finding the Steam account ----------
def steam_root():
    for r in STEAM_ROOTS:
        if os.path.isdir(os.path.join(r, "userdata")):
            return os.path.realpath(r)
    return ""


def account_dir(root):
    """userdata/<the account that used Steam last> (loginusers.vdf: MostRecent), else the only one there."""
    users = [u for u in os.listdir(os.path.join(root, "userdata")) if u.isdigit() and u != "0"]
    try:
        text = open(os.path.join(root, "config/loginusers.vdf"), encoding="utf-8", errors="replace").read()
        for m in re.finditer(r'"(7656\d{13})"\s*\{([^}]*)\}', text):
            if re.search(r'"MostRecent"\s*"1"', m.group(2)):
                acc = str(int(m.group(1)) - 76561197960265728)
                if acc in users:
                    return os.path.join(root, "userdata", acc)
    except OSError:
        pass
    if len(users) == 1:
        return os.path.join(root, "userdata", users[0])
    return ""


# ---------- shortcuts.vdf (Steam's binary list) ----------
# A map is a run of: type byte, name (ends with a zero byte), value; type 8 ends the map. Types: 0 nested map,
# 1 text (zero-terminated), 2 32-bit number, 7 64-bit number. Kept as an ordered list of (type, name, value).
def bin_parse(b, pos=0):
    items = []
    while pos < len(b):
        t = b[pos]
        pos += 1
        if t == 8:
            return items, pos
        end = b.index(0, pos)
        name = b[pos:end]
        pos = end + 1
        if t == 0:
            sub, pos = bin_parse(b, pos)
            items.append((0, name, sub))
        elif t == 1:
            end = b.index(0, pos)
            items.append((1, name, b[pos:end]))
            pos = end + 1
        elif t == 2:
            items.append((2, name, b[pos:pos + 4]))
            pos += 4
        elif t == 7:
            items.append((7, name, b[pos:pos + 8]))
            pos += 8
        else:
            raise ValueError("unknown entry type %d in shortcuts.vdf" % t)
    raise ValueError("shortcuts.vdf ends early")


def bin_dump(items):
    out = bytearray()
    for t, name, v in items:
        out.append(t)
        out += name + b"\0"
        if t == 0:
            out += bin_dump(v) + b"\x08"
        elif t == 1:
            out += v + b"\0"
        else:
            out += v
    return bytes(out)


def bin_text(s):
    return s.encode("utf-8")


def bin_int(n):
    return struct.pack("<I", n & 0xFFFFFFFF)


def field(entry, name):
    for t, k, v in entry:
        if k.decode("utf-8", "replace").lower() == name.lower():
            return t, v
    return None, None


def shortcut_id(exe_quoted, title):
    """Steam's number for a non-Steam game: crc32 of the quoted program path and the name, top bit set."""
    return (zlib.crc32((exe_quoted + title).encode("utf-8")) | 0x80000000) & 0xFFFFFFFF


def write_shortcut(cfg, program, title):
    path = os.path.join(cfg, "shortcuts.vdf")
    if os.path.exists(path):
        data = open(path, "rb").read()
        root, end = bin_parse(data) if data else ([(0, b"shortcuts", [])], 0)
        if data and (bin_dump(root) + b"\x08" != data):
            return None, "Steam's list of non-Steam games has parts Tephra can't copy safely, so nothing was changed. Add the game in Steam instead."
    else:
        data, root = b"", [(0, b"shortcuts", [])]
    lists = [it for it in root if it[0] == 0 and it[1].lower() == b"shortcuts"]
    if not lists:
        return None, "Steam's list of non-Steam games has an unknown layout, so nothing was changed."
    entries = lists[0][2]
    exe_q = '"%s"' % program
    for _, key, e in entries:
        _, exe = field(e, "exe")
        if exe is not None and exe.decode("utf-8", "replace").strip('"') == program:
            _, name = field(e, "appname")
            t, raw = field(e, "appid")
            sid = struct.unpack("<I", raw)[0] if t == 2 else shortcut_id(exe.decode("utf-8", "replace"), name.decode("utf-8", "replace") if name else "")
            return {"id": sid, "title": name.decode("utf-8", "replace") if name else title, "exists": True}, ""
    sid = shortcut_id(exe_q, title)
    nxt = max([int(k) for _, k, _ in entries if k.isdigit()] + [-1]) + 1
    entry = [
        (2, b"appid", bin_int(sid)),
        (1, b"AppName", bin_text(title)),
        (1, b"Exe", bin_text(exe_q)),
        (1, b"StartDir", bin_text('"%s"' % os.path.dirname(program))),
        (1, b"icon", b""),
        (1, b"ShortcutPath", b""),
        (1, b"LaunchOptions", b""),
        (2, b"IsHidden", bin_int(0)),
        (2, b"AllowDesktopConfig", bin_int(1)),
        (2, b"AllowOverlay", bin_int(1)),
        (2, b"OpenVR", bin_int(0)),
        (2, b"Devkit", bin_int(0)),
        (1, b"DevkitGameID", b""),
        (2, b"DevkitOverrideAppID", bin_int(0)),
        (2, b"LastPlayTime", bin_int(0)),
        (1, b"FlatpakAppID", b""),
        (0, b"tags", []),
    ]
    entries.append((0, str(nxt).encode(), entry))
    if data:
        shutil.copyfile(path, path + ".tephra-backup")
    os.makedirs(cfg, exist_ok=True)
    tmp = path + ".tephra-tmp"
    with open(tmp, "wb") as h:
        h.write(bin_dump(root) + b"\x08")
    os.replace(tmp, path)
    return {"id": sid, "title": title, "exists": False}, ""


def remove_shortcut(cfg, appid):
    """Takes the non-Steam game with Steam's number `appid` out of shortcuts.vdf (the program's own files stay)."""
    path = os.path.join(cfg, "shortcuts.vdf")
    if not os.path.exists(path):
        return None, "That game isn't in Steam's list any more."
    data = open(path, "rb").read()
    root, _ = bin_parse(data)
    if bin_dump(root) + b"\x08" != data:
        return None, "Steam's list of non-Steam games has parts Tephra can't copy safely, so nothing was changed. Remove the game in Steam instead."
    lists = [it for it in root if it[0] == 0 and it[1].lower() == b"shortcuts"]
    if not lists:
        return None, "Steam's list of non-Steam games has an unknown layout, so nothing was changed."
    entries = lists[0][2]
    keep, gone = [], []
    for item in entries:
        e = item[2]
        t, raw = field(e, "appid")
        _, exe = field(e, "exe")
        _, name = field(e, "appname")
        exe_s = exe.decode("utf-8", "replace") if exe is not None else ""
        name_s = name.decode("utf-8", "replace") if name is not None else ""
        sid = struct.unpack("<I", raw)[0] if t == 2 else shortcut_id(exe_s, name_s)
        (gone if sid == appid else keep).append((item, name_s))
    if not gone:
        return None, "That game isn't in Steam's list any more."
    entries[:] = [(0, str(i).encode(), it[0][2]) for i, it in enumerate(keep)]  # Steam numbers them 0, 1, 2...
    shutil.copyfile(path, path + ".tephra-backup")
    tmp = path + ".tephra-tmp"
    with open(tmp, "wb") as h:
        h.write(bin_dump(root) + b"\x08")
    os.replace(tmp, path)
    return {"title": gone[0][1], "removed": len(gone)}, ""


# ---------- config.vdf: which Proton runs a game ----------
# Text KeyValues. Only the new lines are added, in place, matching the file's own line endings and tabs.
TOKEN = re.compile(r'"((?:\\.|[^"\\])*)"|(\{)|(\})|(//[^\n]*)|(\s+)', re.S)


def tokens(text):
    """[(kind, value, start, end)], kind: 's' string, '{', '}'."""
    out, pos = [], 0
    while pos < len(text):
        m = TOKEN.match(text, pos)
        if not m:
            raise ValueError("config.vdf: unexpected text at %d" % pos)
        if m.group(1) is not None:
            out.append(("s", m.group(1), m.start(), m.end()))
        elif m.group(2):
            out.append(("{", "{", m.start(), m.end()))
        elif m.group(3):
            out.append(("}", "}", m.start(), m.end()))
        pos = m.end()
    return out


def blocks(toks):
    """{index of a key token: index of the '}' closing its block} for every key followed by '{'."""
    stack, close = [], {}
    for i, (k, v, s, e) in enumerate(toks):
        if k == "{":
            stack.append(i - 1)
        elif k == "}":
            if not stack:
                raise ValueError("config.vdf: unbalanced braces")
            close[stack.pop()] = i
    if stack:
        raise ValueError("config.vdf: unbalanced braces")
    return close


def find_block(toks, close, path):
    """Token index of the key at the end of path (case-insensitive), searched level by level, or -1."""
    lo, hi = 0, len(toks)
    found = -1
    for name in path:
        found = -1
        i = lo
        while i < hi:
            k, v, s, e = toks[i]
            if k == "s" and i + 1 < hi and toks[i + 1][0] == "{":
                if v.lower() == name.lower():
                    found = i
                    break
                i = close[i] + 1  # skip the whole block: only this level counts
            elif k == "s":
                i += 2  # a key and its value
            else:
                i += 1
        if found < 0:
            return -1
        lo, hi = found + 2, close[found]
    return found


def set_proton(root, appid):
    path = os.path.join(root, "config/config.vdf")
    if not os.path.exists(path):
        return "", "no config.vdf"
    with open(path, encoding="utf-8", errors="surrogateescape", newline="") as h:  # newline="": keep \r\n as it is
        text = h.read()
    toks = tokens(text)
    close = blocks(toks)
    base = ["InstallConfigStore", "Software", "Valve", "Steam"]
    steam = find_block(toks, close, base)
    if steam < 0:
        return "", "config.vdf has an unknown layout"
    ctm = find_block(toks, close, base + ["CompatToolMapping"])
    nl = "\r\n" if "\r\n" in text else "\n"
    tool = "proton_experimental"
    if ctm >= 0:
        if find_block(toks, close, base + ["CompatToolMapping", str(appid)]) >= 0:
            return "already set", ""
        default = find_block(toks, close, base + ["CompatToolMapping", "0"])
        if default >= 0:
            j = default + 2
            while j < close[default]:
                if toks[j][0] == "s" and toks[j][1].lower() == "name" and toks[j + 1][0] == "s" and toks[j + 1][1]:
                    tool = toks[j + 1][1]
                j += 1
        depth = 5  # inside InstallConfigStore > Software > Valve > Steam > CompatToolMapping
        at = toks[close[ctm]][2]  # just before CompatToolMapping's closing brace
        line_start = text.rfind("\n", 0, at) + 1
        ins = _entry_text(appid, tool, depth, nl)
        new = text[:line_start] + ins + text[line_start:]
    else:
        depth = 4
        at = toks[close[steam]][2]
        line_start = text.rfind("\n", 0, at) + 1
        t = "\t" * depth
        ins = t + '"CompatToolMapping"' + nl + t + "{" + nl + _entry_text(appid, tool, depth + 1, nl) + t + "}" + nl
        new = text[:line_start] + ins + text[line_start:]
    shutil.copyfile(path, path + ".tephra-backup")
    tmp = path + ".tephra-tmp"
    with open(tmp, "w", encoding="utf-8", errors="surrogateescape", newline="") as h:
        h.write(new)
    os.replace(tmp, path)
    return tool, ""


def _entry_text(appid, tool, depth, nl):
    t, t1 = "\t" * depth, "\t" * (depth + 1)
    return (t + '"%d"' % appid + nl + t + "{" + nl +
            t1 + '"name"\t\t"%s"' % tool + nl + t1 + '"config"\t\t""' + nl + t1 + '"priority"\t\t"250"' + nl +
            t + "}" + nl)


# ---------- The two commands ----------
def add(program, title):
    program = os.path.realpath(program)
    if not os.path.isfile(program):
        return {"error": "%s isn't there any more." % os.path.basename(program)}
    root = steam_root()
    acc = account_dir(root) if root else ""
    if not acc:
        return {"error": "Couldn't find your Steam account. Start Steam once and sign in, then try again."}
    res, err = write_shortcut(os.path.join(acc, "config"), program, title)
    if err:
        return {"error": err}
    res["proton"] = ""
    if program.lower().endswith(".exe"):
        try:
            tool, perr = set_proton(root, res["id"])
        except (ValueError, OSError) as e:
            tool, perr = "", str(e)
        res["proton"] = tool
        if perr:
            res["warning"] = "Added, but Proton couldn't be switched on for it (%s). In Steam: the game's Properties > Compatibility." % perr
    else:
        mode = os.stat(program).st_mode
        if not mode & stat.S_IXUSR:
            os.chmod(program, mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)  # a Linux program must be runnable
    return res


def remove(appid):
    root = steam_root()
    acc = account_dir(root) if root else ""
    if not acc:
        return {"error": "Couldn't find your Steam account."}
    res, err = remove_shortcut(os.path.join(acc, "config"), int(appid) & 0xFFFFFFFF)
    return {"error": err} if err else res


if __name__ == "__main__":
    try:
        if len(sys.argv) >= 3 and sys.argv[1] == "guess":
            print(json.dumps({"title": guess_title(sys.argv[2])}))
        elif len(sys.argv) >= 4 and sys.argv[1] == "add":
            print(json.dumps(add(sys.argv[2], sys.argv[3])))
        elif len(sys.argv) >= 3 and sys.argv[1] == "remove":
            print(json.dumps(remove(sys.argv[2])))
        else:
            print(json.dumps({"error": "usage: add_game.py guess <program> | add <program> <title> | remove <appid>"}))
    except Exception as e:  # never a Python traceback on Tephra's screen
        print(json.dumps({"error": "Couldn't add the game: %s" % e}))
