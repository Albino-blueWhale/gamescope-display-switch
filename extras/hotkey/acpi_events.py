"""Read ACPI/WMI events from the kernel's "acpi_event" generic-netlink channel.

Vendor hotkeys such as Acer's Turbo / PredatorSense key often don't arrive as key presses at all:
the firmware raises a WMI event instead. The kernel broadcasts every such event on this channel
(it's what acpid listens to), and any user may listen, so no root is needed.
"""
import socket
import struct

NETLINK_GENERIC, SOL_NETLINK, NETLINK_ADD_MEMBERSHIP = 16, 270, 1


def _attrs(buf):
    """Parse netlink attributes into {type: [payload, ...]}."""
    out, i = {}, 0
    while i + 4 <= len(buf):
        length, kind = struct.unpack_from("HH", buf, i)
        if length < 4:
            break
        out.setdefault(kind & 0x7FFF, []).append(buf[i + 4:i + length])
        i += (length + 3) & ~3
    return out


def open_socket(timeout=None):
    """Join the acpi_event multicast group and return the socket."""
    s = socket.socket(socket.AF_NETLINK, socket.SOCK_RAW, NETLINK_GENERIC)
    s.bind((0, 0))
    name = b"acpi_event\0"
    attr = struct.pack("HH", 4 + len(name), 2) + name + b"\0" * (-len(name) % 4)  # CTRL_ATTR_FAMILY_NAME
    msg = struct.pack("BBH", 3, 1, 0) + attr                                        # CTRL_CMD_GETFAMILY
    s.send(struct.pack("IHHII", 16 + len(msg), 0x10, 1, 1, 0) + msg)               # GENL_ID_CTRL, NLM_F_REQUEST
    reply = _attrs(s.recv(65536)[20:])
    if 7 not in reply:                                                               # CTRL_ATTR_MCAST_GROUPS
        raise RuntimeError("the kernel has no acpi_event channel")
    group = None
    for g in _attrs(reply[7][0]).values():
        group = struct.unpack("I", _attrs(g[0])[2][0][:4])[0]                      # CTRL_ATTR_MCAST_GRP_ID
    s.setsockopt(SOL_NETLINK, NETLINK_ADD_MEMBERSHIP, group)
    s.settimeout(timeout)
    return s


def read_event(sock):
    """Block until the next event; return (device_class, bus_id, type, data) or None for non-events."""
    data = sock.recv(65536)
    event = _attrs(data[20:]).get(1)                                                 # ACPI_GENL_ATTR_EVENT
    if not event:
        return None
    e = event[0]
    device_class = e[:20].split(b"\0")[0].decode(errors="replace")
    bus_id = e[20:35].split(b"\0")[0].decode(errors="replace")
    kind, value = struct.unpack_from("II", e, 36)
    return device_class, bus_id, kind, value
