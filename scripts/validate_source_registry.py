#!/usr/bin/env python3
"""Validate Quantara's provenance-first source registry without external packages."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import date
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

DEFAULT_REGISTRY_PATH = Path("docs/research/source-registry.v1.yaml")

TOP_LEVEL_FIELDS = {
    "schema_version",
    "registry_version",
    "reviewed_at",
    "review_due_at",
    "execution_authority",
    "sources",
}

SOURCE_FIELDS = {
    "id",
    "title",
    "publisher",
    "canonical_url",
    "terms_urls",
    "source_class",
    "authority_tier",
    "access_class",
    "ingestion_mode",
    "decision_role",
    "commercial_use_status",
    "update_cadence",
    "domains",
    "permitted_uses",
    "prohibited_uses",
    "validation_requirements",
    "attribution_required",
    "automated_scraping_allowed",
    "retention_policy",
    "revision_policy",
    "enabled",
    "notes",
}

ALLOWED_SOURCE_CLASSES = {
    "official_event_data",
    "live_market_data",
    "research_evidence",
    "educational_hypothesis",
    "compliance_policy",
}
ALLOWED_AUTHORITY_TIERS = {
    "official_primary",
    "professional_standard",
    "peer_reviewed_or_scholarly",
    "publisher_reference",
    "vendor_primary",
    "creator_hypothesis",
    "compliance_authority",
}
ALLOWED_ACCESS_CLASSES = {
    "public_api_with_terms",
    "public_web_reference",
    "community_noncommercial",
    "copyrighted_reference",
    "restricted_paid",
    "user_supplied_licensed",
}
ALLOWED_INGESTION_MODES = {
    "api",
    "youtube_api_metadata",
    "manual_metadata",
    "citation_only",
    "no_ingestion",
}
ALLOWED_DECISION_ROLES = {
    "direct_fact",
    "feature_input",
    "validation_method",
    "hypothesis_only",
    "compliance_only",
}
ALLOWED_COMMERCIAL_STATUSES = {
    "approved_subject_to_terms",
    "blocked_pending_license",
    "citation_only",
    "not_applicable",
}

FORBIDDEN_CORPUS_KEYS = {
    "content",
    "raw_content",
    "raw_html",
    "full_text",
    "fulltext",
    "transcript",
    "subtitles",
    "book_pdf",
    "course_files",
    "video_file",
    "audio_file",
    "excerpt",
}

ID_PATTERN = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
VERSION_PATTERN = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
SECRET_PATTERN = re.compile(
    r"(?:api[_-]?key|secret|token|password|authorization)=",
    re.IGNORECASE,
)


def load_registry(path: Path) -> Any:
    """Load the JSON-compatible YAML registry."""
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ValueError(f"Registry file does not exist: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ValueError(
            f"Registry must remain JSON-compatible YAML: {exc.msg} "
            f"at line {exc.lineno}, column {exc.colno}."
        ) from exc


def _is_https_url(value: object) -> bool:
    if not isinstance(value, str):
        return False
    parsed = urlparse(value)
    return (
        parsed.scheme == "https"
        and bool(parsed.netloc)
        and not parsed.username
        and not parsed.password
        and not SECRET_PATTERN.search(value)
    )


def _parse_date(value: object, field_name: str, errors: list[str]) -> date | None:
    if not isinstance(value, str):
        errors.append(f"{field_name} must be an ISO date string.")
        return None
    try:
        return date.fromisoformat(value)
    except ValueError:
        errors.append(f"{field_name} must use YYYY-MM-DD format.")
        return None


def _validate_string(
    value: object,
    path: str,
    errors: list[str],
    *,
    maximum: int,
) -> None:
    if not isinstance(value, str) or not value.strip():
        errors.append(f"{path} must be a non-empty string.")
        return
    if value != value.strip():
        errors.append(f"{path} must not contain leading or trailing whitespace.")
    if len(value) > maximum:
        errors.append(f"{path} exceeds the {maximum}-character limit.")
    if "data:" in value.lower():
        errors.append(f"{path} must not embed a data URI.")
    if SECRET_PATTERN.search(value):
        errors.append(f"{path} appears to contain a credential or secret.")


def _validate_string_list(
    value: object,
    path: str,
    errors: list[str],
    *,
    minimum_items: int = 1,
    maximum_item_length: int = 240,
) -> None:
    if not isinstance(value, list):
        errors.append(f"{path} must be an array.")
        return
    if len(value) < minimum_items:
        errors.append(f"{path} must contain at least {minimum_items} item(s).")
        return

    normalized: set[str] = set()
    for index, item in enumerate(value):
        item_path = f"{path}[{index}]"
        _validate_string(item, item_path, errors, maximum=maximum_item_length)
        if isinstance(item, str):
            key = item.casefold()
            if key in normalized:
                errors.append(f"{path} contains a duplicate item: {item!r}.")
            normalized.add(key)


def _find_forbidden_corpus_keys(
    value: object,
    path: str,
    errors: list[str],
) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            normalized_key = str(key).casefold()
            child_path = f"{path}.{key}"
            if normalized_key in FORBIDDEN_CORPUS_KEYS:
                errors.append(
                    f"{child_path} is a forbidden embedded-corpus field. "
                    "Store metadata, hashes, evidence links, and original Quantara notes only."
                )
            _find_forbidden_corpus_keys(child, child_path, errors)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _find_forbidden_corpus_keys(child, f"{path}[{index}]", errors)


def _validate_url_list(value: object, path: str, errors: list[str]) -> None:
    if not isinstance(value, list):
        errors.append(f"{path} must be an array of HTTPS URLs.")
        return

    seen: set[str] = set()
    for index, url in enumerate(value):
        if not _is_https_url(url):
            errors.append(f"{path}[{index}] must be a credential-free HTTPS URL.")
            continue
        assert isinstance(url, str)
        if url in seen:
            errors.append(f"{path} contains duplicate URL {url!r}.")
        seen.add(url)


def _validate_source(source: object, index: int, errors: list[str]) -> str | None:
    path = f"sources[{index}]"
    if not isinstance(source, dict):
        errors.append(f"{path} must be an object.")
        return None

    missing = sorted(SOURCE_FIELDS - set(source) - {"notes"})
    extra = sorted(set(source) - SOURCE_FIELDS)
    if missing:
        errors.append(f"{path} is missing required fields: {', '.join(missing)}.")
    if extra:
        errors.append(f"{path} has unsupported fields: {', '.join(extra)}.")

    source_id = source.get("id")
    if not isinstance(source_id, str) or not ID_PATTERN.fullmatch(source_id):
        errors.append(f"{path}.id must be a lowercase kebab-case identifier.")
        valid_source_id: str | None = None
    else:
        valid_source_id = source_id

    _validate_string(source.get("title"), f"{path}.title", errors, maximum=200)
    _validate_string(source.get("publisher"), f"{path}.publisher", errors, maximum=160)
    _validate_string(
        source.get("update_cadence"),
        f"{path}.update_cadence",
        errors,
        maximum=100,
    )
    _validate_string(
        source.get("retention_policy"),
        f"{path}.retention_policy",
        errors,
        maximum=300,
    )
    _validate_string(
        source.get("revision_policy"),
        f"{path}.revision_policy",
        errors,
        maximum=300,
    )
    if "notes" in source:
        _validate_string(source.get("notes"), f"{path}.notes", errors, maximum=500)

    canonical_url = source.get("canonical_url")
    if not _is_https_url(canonical_url):
        errors.append(f"{path}.canonical_url must be a credential-free HTTPS URL.")

    _validate_url_list(source.get("terms_urls"), f"{path}.terms_urls", errors)
    _validate_string_list(source.get("domains"), f"{path}.domains", errors)
    _validate_string_list(source.get("permitted_uses"), f"{path}.permitted_uses", errors)
    _validate_string_list(source.get("prohibited_uses"), f"{path}.prohibited_uses", errors)
    _validate_string_list(
        source.get("validation_requirements"),
        f"{path}.validation_requirements",
        errors,
    )

    enum_fields = (
        ("source_class", ALLOWED_SOURCE_CLASSES),
        ("authority_tier", ALLOWED_AUTHORITY_TIERS),
        ("access_class", ALLOWED_ACCESS_CLASSES),
        ("ingestion_mode", ALLOWED_INGESTION_MODES),
        ("decision_role", ALLOWED_DECISION_ROLES),
        ("commercial_use_status", ALLOWED_COMMERCIAL_STATUSES),
    )
    for field_name, allowed_values in enum_fields:
        if source.get(field_name) not in allowed_values:
            errors.append(
                f"{path}.{field_name} must be one of: "
                f"{', '.join(sorted(allowed_values))}."
            )

    for boolean_field in (
        "attribution_required",
        "automated_scraping_allowed",
        "enabled",
    ):
        if not isinstance(source.get(boolean_field), bool):
            errors.append(f"{path}.{boolean_field} must be a boolean.")

    authority_tier = source.get("authority_tier")
    source_class = source.get("source_class")
    access_class = source.get("access_class")
    ingestion_mode = source.get("ingestion_mode")
    decision_role = source.get("decision_role")
    commercial_status = source.get("commercial_use_status")
    terms_urls = source.get("terms_urls")
    enabled = source.get("enabled")

    if source.get("automated_scraping_allowed") is not False:
        errors.append(
            f"{path}.automated_scraping_allowed must remain false; "
            "documented APIs are not classified as scraping."
        )

    if authority_tier == "creator_hypothesis":
        if source_class != "educational_hypothesis":
            errors.append(
                f"{path}: creator_hypothesis must use educational_hypothesis source class."
            )
        if decision_role != "hypothesis_only":
            errors.append(
                f"{path}: creator_hypothesis may only have hypothesis_only decision role."
            )

    if authority_tier == "compliance_authority" or source_class == "compliance_policy":
        if decision_role != "compliance_only":
            errors.append(f"{path}: compliance sources may only have compliance_only role.")

    if decision_role == "direct_fact" and authority_tier != "official_primary":
        errors.append(f"{path}: direct_fact requires official_primary authority.")

    if decision_role == "feature_input" and authority_tier in {
        "creator_hypothesis",
        "publisher_reference",
    }:
        errors.append(
            f"{path}: creator or publisher references cannot directly become feature inputs."
        )

    if access_class in {"copyrighted_reference", "restricted_paid"}:
        if ingestion_mode not in {"citation_only", "manual_metadata", "no_ingestion"}:
            errors.append(
                f"{path}: copyrighted or restricted sources cannot use automated ingestion."
            )
        if commercial_status not in {"citation_only", "blocked_pending_license"}:
            errors.append(
                f"{path}: copyrighted or restricted sources require citation-only or blocked status."
            )

    if access_class == "community_noncommercial":
        if commercial_status != "blocked_pending_license":
            errors.append(
                f"{path}: community_noncommercial must be blocked_pending_license."
            )
        if enabled is not False:
            errors.append(
                f"{path}: community_noncommercial must remain disabled for production."
            )

    if ingestion_mode in {"api", "youtube_api_metadata"}:
        if not isinstance(terms_urls, list) or not terms_urls:
            errors.append(f"{path}: API ingestion requires at least one terms URL.")

    if ingestion_mode == "youtube_api_metadata":
        if authority_tier != "creator_hypothesis":
            errors.append(
                f"{path}: youtube_api_metadata is reserved for approved creator hypotheses."
            )
        if commercial_status != "citation_only":
            errors.append(
                f"{path}: YouTube creator metadata must remain citation_only by default."
            )

    if commercial_status == "blocked_pending_license" and enabled is not False:
        errors.append(f"{path}: blocked sources cannot be enabled.")

    return valid_source_id


def validate_registry(registry: object) -> list[str]:
    """Return deterministic validation errors for a registry object."""
    errors: list[str] = []
    if not isinstance(registry, dict):
        return ["Registry root must be an object."]

    _find_forbidden_corpus_keys(registry, "registry", errors)

    missing = sorted(TOP_LEVEL_FIELDS - set(registry))
    extra = sorted(set(registry) - TOP_LEVEL_FIELDS)
    if missing:
        errors.append(f"Registry is missing required fields: {', '.join(missing)}.")
    if extra:
        errors.append(f"Registry has unsupported fields: {', '.join(extra)}.")

    if registry.get("schema_version") != "source-registry-v1":
        errors.append("schema_version must equal source-registry-v1.")

    registry_version = registry.get("registry_version")
    if not isinstance(registry_version, str) or not VERSION_PATTERN.fullmatch(
        registry_version
    ):
        errors.append("registry_version must use semantic version format X.Y.Z.")

    reviewed_at = _parse_date(registry.get("reviewed_at"), "reviewed_at", errors)
    review_due_at = _parse_date(
        registry.get("review_due_at"), "review_due_at", errors
    )
    if reviewed_at and review_due_at:
        if review_due_at < reviewed_at:
            errors.append("review_due_at must not precede reviewed_at.")
        if (review_due_at - reviewed_at).days > 180:
            errors.append("Registry review interval must not exceed 180 days.")

    if registry.get("execution_authority") != "none":
        errors.append("execution_authority must remain none.")

    sources = registry.get("sources")
    if not isinstance(sources, list) or not sources:
        errors.append("sources must be a non-empty array.")
        return sorted(set(errors))

    seen_ids: set[str] = set()
    for index, source in enumerate(sources):
        source_id = _validate_source(source, index, errors)
        if source_id is None:
            continue
        if source_id in seen_ids:
            errors.append(f"Duplicate source id: {source_id}.")
        seen_ids.add(source_id)

    return sorted(set(errors))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "registry",
        nargs="?",
        type=Path,
        default=DEFAULT_REGISTRY_PATH,
        help="Path to the JSON-compatible YAML registry.",
    )
    args = parser.parse_args()

    try:
        registry = load_registry(args.registry)
    except ValueError as exc:
        print(f"source-registry validation failed: {exc}", file=sys.stderr)
        return 1

    errors = validate_registry(registry)
    if errors:
        print("source-registry validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    sources = registry["sources"]
    print(
        "source-registry validation passed: "
        f"{len(sources)} sources, version {registry['registry_version']}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
