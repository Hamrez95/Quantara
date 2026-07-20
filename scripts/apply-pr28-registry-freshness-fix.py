from pathlib import Path

VALIDATOR_PATH = Path("scripts/validate_source_registry.py")


def replace_once(content: str, old: str, new: str) -> str:
    count = content.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one validator block, found {count}.")
    return content.replace(old, new, 1)


content = VALIDATOR_PATH.read_text(encoding="utf-8")
content = replace_once(
    content,
    "from datetime import date\n",
    "from datetime import date, datetime, timezone\n",
)
content = replace_once(
    content,
    "def validate_registry(registry: object) -> list[str]:\n"
    "    \"\"\"Return deterministic validation errors for a registry object.\"\"\"\n",
    "def validate_registry(\n"
    "    registry: object,\n"
    "    *,\n"
    "    today: date | None = None,\n"
    ") -> list[str]:\n"
    "    \"\"\"Return deterministic validation errors for a registry object.\"\"\"\n",
)
content = replace_once(
    content,
    "    if reviewed_at and review_due_at:\n"
    "        if review_due_at < reviewed_at:\n"
    "            errors.append(\"review_due_at must not precede reviewed_at.\")\n"
    "        if (review_due_at - reviewed_at).days > 180:\n"
    "            errors.append(\"Registry review interval must not exceed 180 days.\")\n",
    "    if reviewed_at and review_due_at:\n"
    "        if review_due_at < reviewed_at:\n"
    "            errors.append(\"review_due_at must not precede reviewed_at.\")\n"
    "        if (review_due_at - reviewed_at).days > 180:\n"
    "            errors.append(\"Registry review interval must not exceed 180 days.\")\n"
    "\n"
    "    effective_today = today or datetime.now(timezone.utc).date()\n"
    "    if review_due_at and review_due_at < effective_today:\n"
    "        errors.append(\"Registry review is overdue and must be renewed.\")\n",
)
VALIDATOR_PATH.write_text(content, encoding="utf-8")
