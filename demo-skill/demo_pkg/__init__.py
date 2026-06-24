"""
demo_pkg - A demo Python package for the AgentSkills plugin.

This __init__.py demonstrates relative imports by importing
`generate_fake_data` from the sibling module `.helper`.
"""

from .helper import generate_fake_data

__all__ = ["generate_fake_data"]
