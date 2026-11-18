"""The shelves over FTP (needs pyftpdlib): anonymous, read-only, passive only.

DOSINST, the DOS store client, lists and downloads its programs over FTP; this serves
the folder the engine writes the shelves into (APPS, C64, PLUS4).

Settings come from the environment:

    FTP_ROOT          the folder to serve; waited for, the engine makes it with
                      its first shelf                       (default: /shelves)
    FTP_HOST          address to listen on                  (default: 0.0.0.0)
    FTP_PORT          control port                          (default: 2121)
    FTP_PASSIVE       passive port range, "first-last"      (default: 30000-30009)
    FTP_MASQUERADE    the address to announce in PASV replies: the one the machines
                      reach this computer at (default: none, the container's own)
"""
import os
import time

from pyftpdlib.authorizers import DummyAuthorizer
from pyftpdlib.handlers import FTPHandler
from pyftpdlib.servers import FTPServer


class PassiveOnlyHandler(FTPHandler):
    banner = "WarpEngine shelves ready."

    def ftp_PORT(self, line):
        self.respond("502 Active mode is disabled, use PASV.")

    def ftp_EPRT(self, line):
        self.respond("502 Active mode is disabled, use EPSV or PASV.")


def make_server(env=os.environ):
    root = os.path.abspath(env.get("FTP_ROOT", "/shelves"))
    first, last = (int(p) for p in env.get("FTP_PASSIVE", "30000-30009").split("-"))

    authorizer = DummyAuthorizer()
    authorizer.add_anonymous(root, perm="elr")

    handler = type("Handler", (PassiveOnlyHandler,), {})
    handler.authorizer = authorizer
    handler.passive_ports = range(first, last + 1)
    handler.masquerade_address = env.get("FTP_MASQUERADE") or None
    handler.timeout = 120

    return FTPServer((env.get("FTP_HOST", "0.0.0.0"), int(env.get("FTP_PORT", "2121"))), handler)


def main():
    root = os.environ.get("FTP_ROOT", "/shelves")
    while not os.path.isdir(root):
        time.sleep(5)
    make_server().serve_forever()


if __name__ == "__main__":
    main()
