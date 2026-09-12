"""Textual TUI for fft_iso_patcher.

Wraps the existing patcher with a guided "vanilla ISO in -> patched ISO
+ recipe out" flow. Music slots only in v1. Entry point:

    python -m fft_iso_patcher tui
"""

from .app import PatcherApp

__all__ = ["PatcherApp"]
