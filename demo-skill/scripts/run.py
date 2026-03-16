"""
scripts/run.py — Entry point for the Python demo.

The AgentSkills Python interpreter sets PYTHONPATH to the skill root directory,
so `demo_pkg` (located at the skill root) is importable as a top-level package.

`demo_pkg/__init__.py` uses a relative import:
    from .helper import generate_fake_data

This script simply invokes that function.
"""

from demo_pkg import generate_fake_data

if __name__ == "__main__":
    generate_fake_data(count=3)
