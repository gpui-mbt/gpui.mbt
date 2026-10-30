import copy
import io
import unittest
from unittest.mock import patch

import host_image_inspect as probe


IMAGE = 'sha256:' + 'a' * 64
CONTAINER = 'b' * 64


def container():
    return [{'Image': IMAGE, 'State': {'Status': 'created', 'Running': False, 'Pid': 0},
             'Config': {'User': '65534:65534', 'Entrypoint': ['/bin/false']},
             'HostConfig': {'NetworkMode': 'none', 'ReadonlyRootfs': True, 'Privileged': False,
                            'CapDrop': ['ALL'], 'SecurityOpt': ['no-new-privileges'],
                            'Binds': None, 'Devices': []}, 'Mounts': []}]


class HostImageInspectTests(unittest.TestCase):
    def test_created_container_is_bound_to_image_and_isolated(self):
        probe.check_container(container(), IMAGE)
        mutations = [
            ('Image', 'sha256:' + 'c' * 64),
            ('State.Status', 'running'), ('State.Running', True), ('State.Pid', 42),
            ('Config.User', '0:0'), ('Config.Entrypoint', ['/bin/sh']),
            ('Config.Volumes', {'/tmp': {}}),
            ('HostConfig.NetworkMode', 'host'), ('HostConfig.ReadonlyRootfs', False),
            ('HostConfig.Privileged', True), ('HostConfig.CapDrop', []),
            ('HostConfig.SecurityOpt', []), ('HostConfig.Binds', ['/host:/tmp']),
            ('HostConfig.Devices', [{'PathOnHost': '/dev/null'}]), ('Mounts', [{'Source': '/host'}]),
        ]
        for dotted, value in mutations:
            with self.subTest(field=dotted):
                item = copy.deepcopy(container())
                target = item[0]
                keys = dotted.split('.')
                for key in keys[:-1]:
                    target = target[key]
                target[keys[-1]] = value
                with self.assertRaises(ValueError):
                    probe.check_container(item, IMAGE)

    def test_empty_or_multiple_inspections_rejected(self):
        for data in ([], container() * 2, {}, [None]):
            with self.subTest(data=data), self.assertRaises(ValueError):
                probe.check_container(data, IMAGE)

    def test_load_create_inspect_remove_never_start(self):
        candidate = {'approved_for_execution': False, 'image_id': IMAGE, 'image_tar_sha256': 'c' * 64}
        commands = []

        def docker(args, *, stdin=None):
            commands.append(args)
            if args == ['load']:
                self.assertIsNotNone(stdin)
                return ''
            if args[:2] == ['image', 'inspect']:
                return IMAGE
            if args[0] == 'create':
                return CONTAINER
            if args[0] == 'inspect':
                return __import__('json').dumps(container())
            if args == ['rm', '-v', CONTAINER]:
                return CONTAINER
            self.fail('unexpected Docker operation: ' + repr(args))

        with patch.object(probe.identity, 'read_checked', return_value=b'{}'), \
             patch.object(probe.identity, 'json_bytes', side_effect=[candidate, container()]), \
             patch.object(probe.identity, 'open_regular', return_value=io.BytesIO(b'image')), \
             patch.object(probe.identity, 'check_image'), \
             patch.object(probe.identity, 'stream_digest', return_value='c' * 64), \
             patch.object(probe, 'run_docker', side_effect=docker):
            result = probe.inspect_image('/unused')
        self.assertEqual(result['native_status'], 'NOT_RUN')
        self.assertIs(result['approved_for_execution'], False)
        self.assertEqual([x[0] for x in commands], ['load', 'image', 'create', 'inspect', 'rm'])
        self.assertEqual(commands[2][-1], IMAGE)

    def test_unapproved_boundary_and_cleanup_on_inspection_failure(self):
        candidate = {'approved_for_execution': False, 'image_id': IMAGE, 'image_tar_sha256': 'c' * 64}
        outputs = ['', IMAGE, CONTAINER, '[]', CONTAINER]
        with patch.object(probe.identity, 'read_checked', return_value=b'{}'), \
             patch.object(probe.identity, 'json_bytes', side_effect=[candidate, []]), \
             patch.object(probe.identity, 'open_regular', return_value=io.BytesIO(b'image')), \
             patch.object(probe.identity, 'check_image'), \
             patch.object(probe.identity, 'stream_digest', return_value='c' * 64), \
             patch.object(probe, 'run_docker', side_effect=outputs) as docker:
            with self.assertRaises(ValueError):
                probe.inspect_image('/unused')
        self.assertEqual(docker.call_args_list[-1].args[0], ['rm', '-v', CONTAINER])
        with patch.object(probe.identity, 'read_checked', return_value=b'{}'), \
             patch.object(probe.identity, 'json_bytes', return_value=dict(candidate, approved_for_execution=True)), \
             patch.object(probe, 'run_docker') as docker:
            with self.assertRaises(ValueError):
                probe.inspect_image('/unused')
            docker.assert_not_called()


if __name__ == '__main__':
    unittest.main()
