import unittest
from release_version import next_version


class VersionTests(unittest.TestCase):
    def test_stable_bumps(self):
        self.assertEqual('1.0.1', next_version('1.0.0', 'patch', 'stable'))
        self.assertEqual('1.1.0', next_version('1.0.0', 'minor', 'stable'))
        self.assertEqual('2.0.0', next_version('1.0.0', 'major', 'stable'))

    def test_beta_increment_is_immutable(self):
        self.assertEqual('1.0.1-beta.1', next_version('1.0.0', 'patch', 'beta'))
        self.assertEqual('1.0.1-beta.2', next_version('1.0.1-beta.1', 'patch', 'beta'))

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
