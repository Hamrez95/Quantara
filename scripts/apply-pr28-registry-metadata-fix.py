from pathlib import Path

REGISTRY_PATH = Path("docs/research/source-registry.v1.yaml")
OLD_URL = (
    "https://www.penguinrandomhouse.com/books/341282/"
    "technical-analysis-of-the-financial-markets-by-john-j-murphy/"
)
NEW_URL = (
    "https://www.penguinrandomhouse.com/books/350647/"
    "technical-analysis-of-the-financial-markets-by-john-j-murphy/"
)

content = REGISTRY_PATH.read_text(encoding="utf-8")
if content.count(OLD_URL) != 1:
    raise RuntimeError("Expected exactly one outdated Murphy publisher URL.")
REGISTRY_PATH.write_text(content.replace(OLD_URL, NEW_URL, 1), encoding="utf-8")
