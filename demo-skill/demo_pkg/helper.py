"""
demo_pkg/helper.py

Generates fake user data using the `faker` third-party library.
This module is imported by __init__.py via a relative import:
    from .helper import generate_fake_data
"""

from faker import Faker

def generate_fake_data(count: int = 3) -> None:
    fake = Faker()
    for i in range(1, count + 1):
        print(f"{i}. {fake.name()} | {fake.email()} | {fake.company()}")
