#!/usr/bin/env python3
"""Tephra: games get Steam's "Gamepad" layout without the touchpad click.

Steam's own PlayStation layouts send the touchpad click to games as Select (left half) and Start (right half), which
Create and Options already do. In Tephra the touchpad click is the screenshot / record button, so this keeps it out of
games. Editing Steam's own templates does not last (Steam puts its files back), so instead, the way EmuDeck does it:
  1. Tephra's own template is written next to Steam's: controller_base/templates/tephra_controller_ps5.vdf (and _ps4),
     a copy of Steam's current "Gamepad" template with only the touchpad CLICK emptied. Steam leaves files it did not
     ship alone.
  2. Every game is pointed at it in Steam's index of layouts (Steam Controller Configs/<you>/config/
     configset_controller_ps5.vdf), as  "<game>" { "template" "tephra_controller_ps5.vdf" }:
       - every installed Steam game (by its number), whatever layout it had before,
       - non-Steam games (listed there by their name in lower case) that had none, or had Steam's plain Gamepad
         template. Ones set to another template (EmuDeck's emulator layouts) are left as they are.
Every entry that is changed or added is remembered first (~/.config/tephra/steam_pads_orig.json), and the index is
copied to <name>.tephra-backup before each write, so --restore puts back exactly what was there.

Steam must NOT be running: it reads the index when it starts and writes it back when it closes.

  steam_pads.py                  apply (prints what it changed, last line "done: N layout(s) changed")
  steam_pads.py --restore        undo: every remembered entry back, Tephra's templates removed
  steam_pads.py --check KEY      prints "ok" if game KEY (a Steam number or a non-Steam name) uses Tephra's layout
"""
import glob
import json
import os
import re
import shutil
import sys

HOME = os.path.expanduser("~")
ROOTS = [os.path.join(HOME, ".local/share/Steam"), os.path.join(HOME, ".steam/steam"),
         os.path.join(HOME, ".var/app/com.valvesoftware.Steam/.local/share/Steam")]
KINDS = {"ps5": "controller_ps5_gamepad_joystick.vdf", "ps4": "controller_ps4_gamepad_joystick.vdf"}
OURS = "tephra_controller_%s.vdf"
ORIG = os.path.join(HOME, ".config/tephra/steam_pads_orig.json")
PAD_TYPES = ("controller_ps4", "controller_ps5")
BACKUP = ".tephra-orig"  # left over from the old way (edited Steam's own templates): put back by --restore

# ---------- A small reader and writer for Valve's KeyValues text (.vdf) ----------
# Keys can repeat (a layout has many "group" blocks), so a block is a list of [key, value] pairs, where value is
# a string or another list. Quoted strings are kept exactly as written (escapes included), so nothing changes
# except what this script means to change.
BOM = "﻿"  # some of Steam's files start with this invisible mark


def parse(text):
    i, n = (1 if text.startswith(BOM) else 0), len(text)

    def skip():
        nonlocal i
        while i < n:
            c = text[i]
            if c in " \t\r\n":
                i += 1
            elif text.startswith("//", i):
                j = text.find("\n", i)
                i = n if j < 0 else j + 1
            else:
                return

    def token():
        nonlocal i
        skip()
        if i >= n:
            return None
        c = text[i]
        if c in "{}":
            i += 1
            return c
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            s = text[i + 1:j]
            i = j + 1
            return ("s", s)
        j = i
        while j < n and text[j] not in " \t\r\n{}\"":
            j += 1
        s = text[i:j]
        i = j
        return ("s", s)

    def block(top):
        pairs = []
        while True:
            t = token()
            if t is None:
                if top:
                    return pairs
                raise ValueError("file ends inside a block")
            if t == "}":
                if top:
                    raise ValueError("unexpected }")
                return pairs
            if t == "{":
                raise ValueError("block without a key")
            key = t[1]
            v = token()
            if v == "{":
                pairs.append([key, block(False)])
            elif isinstance(v, tuple):
                skip()
                if text.startswith("[", i):
                    # A platform condition like [$WIN32]. Steam's layouts don't use them; a file that does is left alone.
                    raise ValueError("platform conditions are not handled")
                pairs.append([key, v[1]])
            else:
                raise ValueError("key %r has no value" % key)

    return block(True)


def dump(pairs, depth=0):
    out = []
    pad = "\t" * depth
    for k, v in pairs:
        if isinstance(v, list):
            out.append('%s"%s"\n%s{\n' % (pad, k, pad))
            out.append(dump(v, depth + 1))
            out.append("%s}\n" % pad)
        else:
            out.append('%s"%s"\t\t"%s"\n' % (pad, k, v))
    return "".join(out)


def get(pairs, key):
    for k, v in pairs:
        if k.lower() == key.lower():
            return v
    return None


def all_of(pairs, key):
    return [v for k, v in pairs if k.lower() == key.lower() and isinstance(v, list)]


# ---------- The change ----------
def free_touchpad_click(root):
    """Empties the click of every group the touchpad uses. Returns how many bindings were removed."""
    mappings = get(root, "controller_mappings")
    if not isinstance(mappings, list):
        return 0
    ctype = str(get(mappings, "controller_type") or "").lower()
    if not ctype.startswith(PAD_TYPES):
        return 0
    # Which groups sit on the touchpad: every preset (action set) names them in "group_source_bindings".
    pad_groups = set()
    for preset in all_of(mappings, "preset"):
        for src in all_of(preset, "group_source_bindings"):
            for gid, where in src:
                if isinstance(where, str) and "trackpad" in where.lower():
                    pad_groups.add(gid.strip())
    removed = 0
    for group in all_of(mappings, "group"):
        if str(get(group, "id") or "").strip() not in pad_groups:
            continue
        inputs = get(group, "inputs")
        if not isinstance(inputs, list):
            continue
        for click in all_of(inputs, "click"):
            for acts in all_of(click, "activators"):
                removed += sum(1 for _ in acts)
                acts.clear()  # "activators" stays, empty: the click does nothing in the game
    return removed


def layout_dirs():
    """The only folders Steam keeps controller layouts in. Never the whole Steam folder: game prefixes (compatdata)
    hold a link back to / (dosdevices/z:), and a search through them never ends."""
    for root in ROOTS:
        if not os.path.isdir(root):
            continue
        yield os.path.join(root, "controller_base/templates")
        yield os.path.join(root, "steamapps/common/Steam Controller Configs")
        for d in glob.glob(os.path.join(root, "userdata/*/241100")):
            yield d


def files_in(suffix):
    """Every file ending in suffix under the layout folders. Links to folders are not followed."""
    seen = set()
    for top in layout_dirs():
        for d, _, names in os.walk(top, followlinks=False):
            for name in names:
                if name.endswith(suffix):
                    real = os.path.realpath(os.path.join(d, name))
                    if real not in seen:
                        seen.add(real)
                        yield real




# ---------- Where things are ----------
def steam_roots():
    out = []
    for r in ROOTS:
        if os.path.isdir(os.path.join(r, "controller_base")):
            real = os.path.realpath(r)
            if real not in out:
                out.append(real)
    return out


def read_text(path):
    with open(path, encoding="utf-8", errors="surrogateescape", newline="") as h:  # newline="": keep \r\n as it is
        return h.read()


def write_text(path, text):
    tmp = path + ".tephra-tmp"
    with open(tmp, "w", encoding="utf-8", errors="surrogateescape", newline="") as h:
        h.write(text)
    os.replace(tmp, path)


def dump_like(pairs, original):
    """dump(), with the original file's line endings and its invisible start mark."""
    out = dump(pairs)
    if not original.endswith(("\n", "\r")):
        out = out.rstrip("\n")  # the original had no line break at the very end
    if "\r\n" in original:
        out = out.replace("\n", "\r\n")
    return (BOM if original.startswith(BOM) else "") + out


def installed_appids(root):
    """Numbers of the installed Steam games (not Proton or Steam's own runtimes), from every library folder."""
    libs = [root]
    try:
        for m in re.finditer(r'"path"\s+"([^"]+)"', read_text(os.path.join(root, "steamapps/libraryfolders.vdf"))):
            p = m.group(1).replace("\\\\", "\\")
            if os.path.realpath(p) not in [os.path.realpath(x) for x in libs]:
                libs.append(p)
    except OSError:
        pass
    ids = []
    for lib in libs:
        for f in glob.glob(os.path.join(lib, "steamapps/appmanifest_*.acf")):
            try:
                text = read_text(f)
            except OSError:
                continue
            m = re.search(r'"appid"\s+"(\d+)"', text)
            n = re.search(r'"name"\s+"([^"]*)"', text)
            name = n.group(1) if n else ""
            if m and not re.search(r"(?i)^proton|steam linux runtime|steamworks common|steamvr", name):
                if m.group(1) not in ids:
                    ids.append(m.group(1))
    return ids


def shortcut_names(root):
    """Lower-case names of the non-Steam games (how Steam lists them in the layout index)."""
    names = []
    for path in glob.glob(os.path.join(root, "userdata/*/config/shortcuts.vdf")):
        try:
            b = open(path, "rb").read()
        except OSError:
            continue
        # Each entry holds  01 'AppName' 00 <name> 00  (the key's case varies between Steam versions).
        for m in re.finditer(rb"\x01appname\x00([^\x00]*)\x00", b, re.I):
            n = m.group(1).decode("utf-8", "replace").strip().lower()
            if n and n not in names:
                names.append(n)
    return names


# ---------- 1. Tephra's template ----------
def make_template(root, kind):
    """Writes tephra_controller_<kind>.vdf from Steam's current Gamepad template. Returns True if it is there."""
    tdir = os.path.join(root, "controller_base/templates")
    base = os.path.join(tdir, KINDS[kind])
    if not os.path.exists(base):
        return False
    text = read_text(base)
    pairs = parse(text)
    free_touchpad_click(pairs)
    m = get(pairs, "controller_mappings")
    if not isinstance(m, list):
        return False
    # Its own name in Steam's layout list, instead of Steam's translated "Gamepad".
    keep = []
    for k, v in m:
        kl = k.lower()
        if kl == "localization":
            continue
        if kl == "title":
            v = "Tephra: Gamepad"
        elif kl == "description":
            v = "Steam's Gamepad layout without the touchpad click (the touchpad takes Tephra's screenshots). Create and Options stay Select and Start."
        keep.append([k, v])
    m[:] = keep
    out = dump_like(pairs, text)
    path = os.path.join(tdir, OURS % kind)
    if not os.path.exists(path) or read_text(path) != out:
        write_text(path, out)
        print("wrote " + path)
    return True


# ---------- 2. The layout index ----------
def configsets(root, kind):
    return glob.glob(os.path.join(root, "steamapps/common/Steam Controller Configs/*/config/configset_controller_%s.vdf" % kind))


def load_orig():
    try:
        return json.load(open(ORIG))
    except (OSError, ValueError):
        return {}


def save_orig(d):
    os.makedirs(os.path.dirname(ORIG), exist_ok=True)
    tmp = ORIG + ".tmp"
    json.dump(d, open(tmp, "w"), indent=1)
    os.replace(tmp, ORIG)


def entry_template(entry):
    return str(get(entry, "template") or "") if isinstance(entry, list) else ""


def point_games(path, kind, appids, names, orig):
    """Points the games at Tephra's template in one index file. Returns how many entries changed."""
    text = read_text(path)
    pairs = parse(text)  # anything it can't read (raises) leaves the file untouched; Steam rewrites this file in
    cc = get(pairs, "controller_config")  # this same format itself, so only the entries change
    if not isinstance(cc, list):
        print("skipped %s: unknown layout" % path)
        return 0
    ours = OURS % kind
    steam_default = KINDS[kind]
    have = {k.lower(): i for i, (k, v) in enumerate(cc)}
    saved = orig.setdefault(path, {})
    changed = 0

    def set_ours(key):
        nonlocal changed
        i = have.get(key.lower())
        if i is not None and entry_template(cc[i][1]) == ours:
            return
        if key not in saved:
            saved[key] = cc[i][1] if i is not None else None  # None: there was no entry
        if i is None:
            cc.append([key, [["template", ours]]])
            have[key.lower()] = len(cc) - 1
        else:
            cc[i][1] = [["template", ours]]
        changed += 1

    for a in appids:
        set_ours(a)  # every installed Steam game, whatever it had
    for n in names:
        i = have.get(n)
        if i is None or entry_template(cc[i][1]).lower() in ("", steam_default):
            set_ours(n)  # non-Steam games with no layout or Steam's plain Gamepad; others (EmuDeck's) stay
    if changed:
        shutil.copyfile(path, path + ".tephra-backup")
        write_text(path, dump_like(pairs, text))
        print("pointed %d game(s) at %s in %s" % (changed, ours, path))
    return changed


def apply():
    total = 0
    orig = load_orig()
    for root in steam_roots():
        appids, names = installed_appids(root), shortcut_names(root)
        for kind in KINDS:
            sets = configsets(root, kind)
            if not sets or not make_template(root, kind):
                continue
            for path in sets:
                try:
                    total += point_games(path, kind, appids, names, orig)
                except (OSError, ValueError) as e:
                    print("skipped %s: %s" % (path, e))
    save_orig(orig)
    print("done: %d layout(s) changed" % total)


def restore():
    n = 0
    orig = load_orig()
    for path, saved in list(orig.items()):
        if not os.path.exists(path):
            continue
        text = read_text(path)
        pairs = parse(text)
        cc = get(pairs, "controller_config")
        if not isinstance(cc, list):
            continue
        for key, entry in saved.items():
            idx = [i for i, (k, v) in enumerate(cc) if k.lower() == key.lower()]
            if not idx:
                if entry is not None:
                    cc.append([key, entry])
                    n += 1
                continue
            if entry is None:
                del cc[idx[0]]
            else:
                cc[idx[0]][1] = entry
            n += 1
        shutil.copyfile(path, path + ".tephra-backup")
        write_text(path, dump_like(pairs, text))
        del orig[path]
        print("restored the layouts in " + path)
    save_orig(orig)
    for root in steam_roots():
        for kind in KINDS:
            p = os.path.join(root, "controller_base/templates", OURS % kind)
            if os.path.exists(p):
                os.remove(p)
    # The old way edited Steam's own files and left <name>.tephra-orig next to them: those go back too.
    for b in list(files_in(BACKUP)):
        os.replace(b, b[:-len(BACKUP)])
        n += 1
        print("restored " + b[:-len(BACKUP)])
    print("done: %d layout(s) restored" % n)


def check(key):
    for root in steam_roots():
        for kind in ("ps5",):
            for path in configsets(root, kind):
                try:
                    cc = get(parse(read_text(path)), "controller_config") or []
                except (OSError, ValueError):
                    continue
                for k, v in cc:
                    if k.lower() == key.lower() and entry_template(v) == OURS % kind:
                        return "ok"
    return "missing"


if __name__ == "__main__":
    if "--restore" in sys.argv:
        restore()
    elif "--check" in sys.argv and sys.argv.index("--check") + 1 < len(sys.argv):
        print(check(sys.argv[sys.argv.index("--check") + 1]))
    else:
        apply()
