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
