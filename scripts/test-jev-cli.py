"""Exercise credential selection without sending requests (hello only prints)."""
import os
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
base = {k: v for k, v in os.environ.items() if k not in {
    "JEV_API_KEY", "TYPESAFE_API_KEY", "JEV_MODEL"
}}
cases = [
    ({}, 1, "Live mode needs JEV_API_KEY"),
    ({"JEV_API_KEY": "placeholder"}, 0, "Hello, uncertainty."),
    ({"TYPESAFE_API_KEY": "placeholder"}, 0, "Hello, uncertainty."),
    ({"JEV_API_KEY": "", "TYPESAFE_API_KEY": "placeholder"}, 1, "JEV API key is missing"),
    ({"JEV_API_KEY": "placeholder", "JEV_MODEL": ""}, 1, "JEV model is missing"),
]
for extra, code, expected in cases:
    result = subprocess.run(
        [str(root / ".build/release/maybe"), "run", "Examples/Programs/hello.prob", "--live"],
        cwd=root, env={**base, **extra}, capture_output=True, text=True, timeout=10,
    )
    assert result.returncode == code and expected in result.stdout + result.stderr, result
print(f"{len(cases)} JEV CLI configuration checks passed; no network calls.")
