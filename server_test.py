import datetime as dt
import unittest
from unittest.mock import patch
import server

class ActivityTests(unittest.TestCase):
    def test_date_validation(self):
        for value in ['2026-02-30','2026-1-1','2026-10-26;whoami','--all']:
            with self.assertRaises(ValueError):
                server.day_bounds(value)

    def test_day_bounds_include_dst_transition(self):
        start, end = server.day_bounds('2026-10-25')
        self.assertEqual(end.timestamp() - start.timestamp(), 25 * 3600)
        self.assertEqual(start.utcoffset(), dt.timedelta(hours=2))
        self.assertEqual(end.utcoffset(), dt.timedelta(hours=1))

    @patch('server.AUTHOR', 'Max Mustermann')
    @patch('server.REPOS', [server.Path('/tmp/a'), server.Path('/tmp/b')])
    @patch('server.run_git', return_value={'text':'a commit','truncated':False})
    def test_activity_is_limited_to_fixed_repos_and_own_authorship(self, git):
        result = server.activity('2026-10-26')
        self.assertEqual(len(result['repositories']),2)
        self.assertEqual(git.call_count,4)
        args = git.call_args_list[0].args[1]
        self.assertIn('--author=^Max Mustermann <',args)
        self.assertIn('--until=2026-10-26T23:59:59+01:00',args)
        self.assertEqual(git.call_args_list[0].args[0],server.REPOS[0])

if __name__ == '__main__':
    unittest.main()
