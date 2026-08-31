import unittest

from release_manifest import next_monotonic_build, require_monotonic_build
from release_version import newest_version, next_version


class VersionTests(unittest.TestCase):
    def test_stable_bumps(self):
        self.assertEqual('1.0.1', next_version('1.0.0', 'patch', 'stable'))
        self.assertEqual('1.1.0', next_version('1.0.0', 'minor', 'stable'))
        self.assertEqual('2.0.0', next_version('1.0.0', 'major', 'stable'))

    def test_beta_increment_is_immutable(self):
        self.assertEqual('1.0.1-beta.1', next_version('1.0.0', 'patch', 'beta'))
        self.assertEqual('1.0.1-beta.2', next_version('1.0.1-beta.1', 'patch', 'beta'))

    def test_release_history_advances_stale_pubspec_floor(self):
        self.assertEqual(
            '1.2.1-beta.1',
            newest_version(['1.2.0-rc.3', '1.2.1-beta.1', '1.0.1']),
        )
        self.assertEqual(
            '1.2.1-beta.2',
            next_version('1.2.1-beta.1', 'patch', 'beta'),
        )

    def test_semver_floor_orders_beta_rc_and_stable(self):
        self.assertEqual(
            '1.2.1',
            newest_version(['1.2.1-beta.9', '1.2.1-rc.2', '1.2.1']),
        )
        self.assertEqual(
            '1.2.1-beta.10',
            newest_version(['1.2.1-beta.2', '1.2.1-beta.10']),
        )

    def test_rc_can_promote_to_same_stable_core(self):
        self.assertEqual('1.2.0', next_version('1.2.0-rc.3', 'promote', 'stable'))

    def test_beta_can_promote_to_same_stable_core(self):
        self.assertEqual('1.3.0', next_version('1.3.0-beta.4', 'promote', 'stable'))

    def test_promote_rejects_non_stable_channel(self):
        with self.assertRaisesRegex(ValueError, 'stable channel'):
            next_version('1.2.0-rc.3', 'promote', 'beta')

    def test_promote_rejects_already_stable_version(self):
        with self.assertRaisesRegex(ValueError, 'cannot be promoted'):
            next_version('1.2.0', 'promote', 'stable')

    def test_build_allocator_advances_past_existing_apk(self):
        assets = [
            'Quantara-1.2.1-beta.1+1952-android.apk',
            'Quantara-1.2.1-beta.1+1952-android.aab',
            'Quantara-1.2.1-beta.1-pwa.zip',
        ]
        self.assertEqual((1953, 1952), next_monotonic_build(1952, assets))
        self.assertEqual((2000, 1952), next_monotonic_build(2000, assets))

    def test_strict_build_guard_remains_fail_closed(self):
        assets = ['Quantara-1.2.1-beta.1+1952-android.apk']
        with self.assertRaisesRegex(ValueError, 'must be greater'):
            require_monotonic_build(1952, assets)
        self.assertEqual(1952, require_monotonic_build(1953, assets))
