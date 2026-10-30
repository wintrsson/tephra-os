# Tephra: fades Tephra's window into the game. One connection to the session bus, many tiny KWin shortcut calls
# (TephraOp00..TephraOp50 = 0-100 % opacity in 2 % steps) paced to the clock, then TephraFadeDone.
# No D-Bus library is needed: the few messages are written by hand.  Usage: tephra-fade.py <seconds>
import math, os, socket, struct, sys, time

def bus_address():
    for part in os.environ.get("DBUS_SESSION_BUS_ADDRESS", "").split(";"):
        if part.startswith("unix:"):
            kv = dict(x.split("=", 1) for x in part[5:].split(",") if "=" in x)
            if "path" in kv:
                return kv["path"]
            if "abstract" in kv:
                return "\0" + kv["abstract"]
    return "/run/user/%d/bus" % os.getuid()

class Buf:
    def __init__(self):
        self.b = b""
    def align(self, n):
        self.b += b"\0" * ((-len(self.b)) % n)
    def byte(self, v):
        self.b += struct.pack("<B", v)
    def u32(self, v):
        self.align(4)
        self.b += struct.pack("<I", v)
    def string(self, v):
        e = v.encode()
        self.u32(len(e))
        self.b += e + b"\0"
    def signature(self, v):
        e = v.encode()
        self.byte(len(e))
        self.b += e + b"\0"

def message(serial, dest, path, iface, member, args=(), reply=False):
    body = Buf()
    for a in args:
        body.string(a)
    fields = Buf()  # starts at offset 16 of the message, which is 8-aligned like this buffer's start
    def field(code, kind, value):
        fields.align(8)
        fields.byte(code)
        fields.signature(kind)
        if kind == "g":
            fields.signature(value)
        else:
            fields.string(value)
    field(1, "o", path)
    field(2, "s", iface)
    field(3, "s", member)
    field(6, "s", dest)
    if args:
        field(8, "g", "s" * len(args))
    head = Buf()
    head.b = b"l" + bytes([1, 0 if reply else 1, 1])  # little endian, method call, flags (1 = no reply wanted), version
    head.u32(len(body.b))
    head.u32(serial)
    head.u32(len(fields.b))
    head.b += fields.b
    head.align(8)
    return head.b + body.b

def main():
    secs = float(sys.argv[1]) if len(sys.argv) > 1 else 0.36
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(2.0)
    s.connect(bus_address())
    s.sendall(b"\0AUTH EXTERNAL " + str(os.getuid()).encode().hex().encode() + b"\r\n")
    if not s.recv(4096).startswith(b"OK"):
        sys.exit(2)
    s.sendall(b"BEGIN\r\n")
    serial = 1
    s.sendall(message(serial, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "Hello", reply=True))
    s.recv(4096)  # the Hello answer (our name on the bus)
    s.setblocking(False)

    def shortcut(name):
        nonlocal serial
        serial += 1
        s.sendall(message(serial, "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component", "invokeShortcut", [name]))
        try:
            while s.recv(65536):
                pass  # nothing is needed from the bus: anything it sends is thrown away
        except (BlockingIOError, InterruptedError):
            pass

    steps = max(8, int(secs * 120))  # about one step per frame of a 120 Hz screen
    t0 = time.monotonic()
    last = 50
    for k in range(1, steps + 1):
        v = round((0.5 + 0.5 * math.cos(math.pi * k / steps)) * 50)  # eased in and out
        if v != last:
            shortcut("TephraOp%02d" % v)
            last = v
        wait = t0 + secs * k / steps - time.monotonic()
        if wait > 0:
            time.sleep(wait)
    if last != 0:
        shortcut("TephraOp00")
    shortcut("TephraFadeDone")
    time.sleep(0.02)
    s.close()

main()
