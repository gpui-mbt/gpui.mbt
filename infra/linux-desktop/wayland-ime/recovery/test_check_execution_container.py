import copy
import json
import unittest
from pathlib import Path
import check_execution_container as check

HERE = Path(__file__).resolve().parent


class ExecutionContainerTest(unittest.TestCase):
    def setUp(self):
        self.review = (HERE/'image.review.candidate.json').read_bytes()
        self.receipt = json.loads((HERE/'execution-container.candidate.json').read_text())
        self.plan = {'container_id': 'a' * 64, 'user': '1001:1001', 'entrypoint': ['/bin/false'], 'cmd': ['test'],
                     'env': {'HOME': '/owned'}, 'network': 'none',
                     'mounts': [{'source': '/host/owned', 'destination': '/owned', 'writable': True}]}
        self.receipt['plan'] = self.plan
        self.obj = {'Id': 'a' * 64, 'Image': self.receipt['image_id'],
                    'State': {'Status': 'created', 'Running': False, 'Pid': 0},
                    'Config': {'User': '1001:1001', 'Entrypoint': ['/bin/false'], 'Cmd': ['test'],
                               'Env': ['HOME=/owned'], 'Volumes': None},
                    'HostConfig': {'NetworkMode': 'none', 'ReadonlyRootfs': True, 'Privileged': False,
                                   'CapDrop': ['ALL'], 'CapAdd': None, 'SecurityOpt': ['no-new-privileges'],
                                   'PidMode': '', 'IpcMode': 'private', 'UTSMode': '', 'Devices': None,
                                   'DeviceRequests': None, 'VolumesFrom': None, 'Tmpfs': None},
                    'Mounts': [{'Type': 'bind', 'Source': '/host/owned', 'Destination': '/owned',
                                'RW': True, 'Propagation': 'rprivate'}]}

    def test_incomplete_real_candidate_rejects(self):
        self.receipt['plan'] = None
        with self.assertRaisesRegex(ValueError, 'incomplete'):
            check.check([self.obj], self.receipt, self.review)

    def test_fixture_match_does_not_approve(self):
        result = check.check([self.obj], self.receipt, self.review)
        self.assertFalse(result['approved_for_execution'])
        self.assertEqual(result['native_status'], 'NOT_RUN')

    def test_invalid_candidate_and_receipt_reject(self):
        for change in ('image_id', 'approved_for_execution', 'candidate_review_sha256', 'native_status'):
            receipt = copy.deepcopy(self.receipt)
            receipt[change] = True if change == 'approved_for_execution' else 'changed'
            with self.subTest(change=change), self.assertRaises(ValueError):
                check.check([self.obj], receipt, self.review)
        with self.assertRaises(ValueError):
            check.check([self.obj], self.receipt, self.review+b' ')

    def test_identity_command_and_state_reject(self):
        for key, value in (('Id', 'b' * 64), ('Image', 'sha256:bad'), ('State', {'Status': 'running', 'Running': True, 'Pid': 2}),
                           ('Config', dict(self.obj['Config'], User='0')),
                           ('Config', dict(self.obj['Config'], Cmd=['other']))):
            obj = copy.deepcopy(self.obj); obj[key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                check.check([obj], self.receipt, self.review)

    def test_environment_and_isolation_reject(self):
        for env in (['HOME=/owned', 'HTTP_PROXY=secret'], ['HOME=/owned', 'HOME=other'], ['HOME=other']):
            obj = copy.deepcopy(self.obj); obj['Config']['Env'] = env
            with self.subTest(case='environment'), self.assertRaises(ValueError):
                check.check([obj], self.receipt, self.review)
        for key, value in (('NetworkMode', 'host'), ('ReadonlyRootfs', False), ('Privileged', True),
                           ('CapDrop', []), ('SecurityOpt', []), ('PidMode', 'host'),
                           ('Devices', [{'PathOnHost':'/dev/example'}])):
            obj = copy.deepcopy(self.obj); obj['HostConfig'][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                check.check([obj], self.receipt, self.review)

    def test_missing_isolation_field_rejects(self):
        obj = copy.deepcopy(self.obj); del obj['HostConfig']['PidMode']
        with self.assertRaisesRegex(ValueError, 'incomplete container inspection'):
            check.check([obj], self.receipt, self.review)

    def test_foreign_or_unsafe_mounts_reject(self):
        for key, value in (('Source', '/host/other'), ('Destination', '/different'), ('RW', False),
                           ('Type', 'volume'), ('Propagation', 'shared')):
            obj = copy.deepcopy(self.obj); obj['Mounts'][0][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                check.check([obj], self.receipt, self.review)
        obj = copy.deepcopy(self.obj); obj['Mounts'].append(copy.deepcopy(obj['Mounts'][0]))
        with self.assertRaises(ValueError):
            check.check([obj], self.receipt, self.review)
        self.plan['mounts'].append({'source': '/host/owned/nested', 'destination': '/another', 'writable': False})
        with self.assertRaisesRegex(ValueError, 'overlapping'):
            check.check([self.obj], self.receipt, self.review)

    def test_token_or_proxy_in_plan_rejects(self):
        for key in ('GH_TOKEN', 'GITHUB_TOKEN', 'HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY'):
            self.plan['env'][key] = 'not-a-secret'
            with self.subTest(key=key), self.assertRaises(ValueError):
                check.check([self.obj], self.receipt, self.review)
            del self.plan['env'][key]


if __name__ == '__main__':
    unittest.main()
