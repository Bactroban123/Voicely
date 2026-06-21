"""Verify the whole runtime import graph loads on Windows (catches missing/lazy deps)."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "app"))

import core  # noqa: F401
import main  # noqa: F401  (defines everything; does not run main())
import pystray._win32  # noqa: F401  (the tray backend PyInstaller can miss)

print("imports OK")
