"""進入點：由 ibus-daemon 以 --ibus 啟動。"""
import logging
import os
import sys
from pathlib import Path

import gi

gi.require_version("IBus", "1.0")
from gi.repository import GLib, IBus  # noqa: E402

from .engine import Factory  # noqa: E402

BUS_NAME = "org.freedesktop.IBus.CangjieLearn"


def main():
    log_dir = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "cangjie-learn"
    log_dir.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(filename=log_dir / "engine.log", level=logging.INFO,
                        format="%(asctime)s %(levelname)s %(message)s")
    IBus.init()
    bus = IBus.Bus()
    if not bus.is_connected():
        logging.error("連不上 ibus-daemon")
        sys.exit(1)
    loop = GLib.MainLoop()
    bus.connect("disconnected", lambda *_: loop.quit())
    factory = Factory(bus)  # noqa: F841  保留參照
    bus.request_name(BUS_NAME, 0)
    logging.info("cangjie-learn 啟動")
    loop.run()


if __name__ == "__main__":
    main()
