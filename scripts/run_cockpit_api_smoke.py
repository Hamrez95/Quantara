#!/usr/bin/env python3

import os
import subprocess
import sys
import time
from pathlib import Path
from urllib.error import URLError
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
API_URL = "http://127.0.0.1:5081"


def main() -> None:
    environment = os.environ.copy()
    environment["ASPNETCORE_URLS"] = API_URL
    log_path = ROOT / "api.log"

    with log_path.open("w", encoding="utf-8") as log_file:
        process = subprocess.Popen(
            [
                "dotnet",
                "run",
                "--project",
                "src/backend/Quantara.Api/Quantara.Api.csproj",
                "--configuration",
                "Release",
                "--no-build",
            ],
            cwd=ROOT,
            env=environment,
            stdout=log_file,
            stderr=subprocess.STDOUT,
            text=True,
        )

        try:
            for _ in range(30):
                if process.poll() is not None:
                    raise RuntimeError("API stopped before becoming ready")
                try:
                    with urlopen(f"{API_URL}/health", timeout=1) as response:
                        if response.status == 200:
                            break
                except (URLError, TimeoutError):
                    time.sleep(1)
            else:
                raise RuntimeError("API did not become ready")

            subprocess.run(
                [
                    sys.executable,
                    "scripts/validate-cockpit-api.py",
                    f"{API_URL}/api/v1/cockpit",
                ],
                cwd=ROOT,
                check=True,
            )
        except Exception:
            log_file.flush()
            print(log_path.read_text(encoding="utf-8"), file=sys.stderr)
            raise
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)


if __name__ == "__main__":
    main()
