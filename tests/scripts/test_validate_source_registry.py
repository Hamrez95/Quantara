from __future__ import annotations

import copy
import importlib.util
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
VALIDATOR_PATH = REPOSITORY_ROOT / "scripts" / "validate_source_registry.py"
REGISTRY_PATH = REPOSITORY_ROOT / "docs" / "research" / "source-registry.v1.yaml"

SPEC = importlib.util.spec_from_file_location(
    "validate_source_registry",
    VALIDATOR_PATH,
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Unable to load source-registry validator module.")

VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


class SourceRegistryValidatorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.registry = VALIDATOR.load_registry(REGISTRY_PATH)

    def assert_error_contains(self, registry: object, expected: str) -> None:
        errors = VALIDATOR.validate_registry(registry)
        self.assertTrue(
            any(expected in error for error in errors),
            msg=f"Expected error containing {expected!r}, got: {errors}",
        )

    def test_valid_registry_passes(self) -> None:
        self.assertEqual([], VALIDATOR.validate_registry(self.registry))

    def test_duplicate_source_id_is_rejected(self) -> None:
        mutated = copy.deepcopy(self.registry)
        mutated["sources"][1]["id"] = mutated["sources"][0]["id"]

        self.assert_error_contains(mutated, "Duplicate source id")

    def test_embedded_full_text_field_is_rejected(self) -> None:
        mutated = copy.deepcopy(self.registry)
        mutated["sources"][0]["full_text"] = "embedded corpus"

        self.assert_error_contains(mutated, "forbidden embedded-corpus field")

    def test_creator_cannot_be_promoted_to_direct_fact(self) -> None:
        mutated = copy.deepcopy(self.registry)
        creator = next(
            source
            for source in mutated["sources"]
            if source["authority_tier"] == "creator_hypothesis"
        )
        creator["decision_role"] = "direct_fact"

        self.assert_error_contains(
            mutated,
            "creator_hypothesis may only have hypothesis_only decision role",
        )

    def test_noncommercial_source_cannot_be_enabled(self) -> None:
        mutated = copy.deepcopy(self.registry)
        source = next(
            item
            for item in mutated["sources"]
            if item["access_class"] == "community_noncommercial"
        )
        source["enabled"] = True
        source["commercial_use_status"] = "approved_subject_to_terms"

        self.assert_error_contains(
            mutated,
            "community_noncommercial must be blocked_pending_license",
        )
        self.assert_error_contains(
            mutated,
            "community_noncommercial must remain disabled for production",
        )

    def test_api_source_requires_terms_url(self) -> None:
        mutated = copy.deepcopy(self.registry)
        source = next(
            item
            for item in mutated["sources"]
            if item["ingestion_mode"] == "api"
        )
        source["terms_urls"] = []

        self.assert_error_contains(
            mutated,
            "API ingestion requires at least one terms URL",
        )

    def test_execution_authority_cannot_be_enabled(self) -> None:
        mutated = copy.deepcopy(self.registry)
        mutated["execution_authority"] = "model"

        self.assert_error_contains(mutated, "execution_authority must remain none")

    def test_non_https_url_is_rejected(self) -> None:
        mutated = copy.deepcopy(self.registry)
        mutated["sources"][0]["canonical_url"] = "http://example.com/resource"

        self.assert_error_contains(
            mutated,
            "canonical_url must be a credential-free HTTPS URL",
        )

    def test_restricted_source_cannot_use_api_ingestion(self) -> None:
        mutated = copy.deepcopy(self.registry)
        source = next(
            item
            for item in mutated["sources"]
            if item["access_class"] == "copyrighted_reference"
        )
        source["ingestion_mode"] = "api"
        source["terms_urls"] = ["https://example.com/terms"]

        self.assert_error_contains(
            mutated,
            "copyrighted or restricted sources cannot use automated ingestion",
        )

    def test_scraping_flag_cannot_be_enabled(self) -> None:
        mutated = copy.deepcopy(self.registry)
        mutated["sources"][0]["automated_scraping_allowed"] = True

        self.assert_error_contains(
            mutated,
            "automated_scraping_allowed must remain false",
        )


if __name__ == "__main__":
    unittest.main()
