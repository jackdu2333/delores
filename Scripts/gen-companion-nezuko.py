#!/usr/bin/env python3
"""Compatibility wrapper — walk-cycle slicing lives in gen-companion-petdex.py."""
import runpy
from pathlib import Path

runpy.run_path(str(Path(__file__).resolve().with_name("gen-companion-petdex.py")), run_name="__main__")
