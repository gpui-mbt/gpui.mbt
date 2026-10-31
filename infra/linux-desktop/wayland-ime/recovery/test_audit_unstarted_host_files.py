import hashlib
import io
from pathlib import Path
import tarfile
import unittest
from unittest.mock import patch

import audit_unstarted_host_files as audit


def tar_bytes(entries):
    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode='w') as archive:
        for name, value, kind in entries:
            item = tarfile.TarInfo(name)
            item.type = kind
            item.size = len(value) if item.isfile() else 0
            archive.addfile(item, io.BytesIO(value) if item.isfile() else None)
    stream.seek(0)
    return stream


class HostAuditTests(unittest.TestCase):
    def setUp(self):
        self.recipe = {'host_executables': {'/usr/bin/convert': 'a' * 64},
                       'build_tools': {'cc': {'location': 'host', 'path': '/usr/bin/cc', 'sha256': 'b' * 64},
                                       'moonc': {'location': 'profile', 'sha256': 'c' * 64}}}

    def test_host_recipe_collects_only_host_paths_and_rejects_conflicting_or_unsafe(self):
        self.assertEqual(audit.expected_host_files(self.recipe), {'/usr/bin/convert': 'a'*64, '/usr/bin/cc': 'b'*64})
        self.recipe['build_tools']['cc'].update(path='/usr/bin/convert')
        with self.assertRaisesRegex(ValueError, 'conflicting'):
            audit.expected_host_files(self.recipe)
        self.recipe['build_tools']['cc'].update(path='/usr/bin/../x')
        with self.assertRaisesRegex(ValueError, 'invalid'):
            audit.expected_host_files(self.recipe)

    def test_archive_one_regular_file_can_be_resolved_symlink_target(self):
        stream = tar_bytes([('convert-im6.q16', b'bytes', tarfile.REGTYPE)])
        self.assertEqual(audit.digest_single_tar(stream), hashlib.sha256(b'bytes').hexdigest())

    def test_archive_rejects_links_paths_and_multiple_members(self):
        for entries in [[], [('x', b'', tarfile.SYMTYPE)], [('../escape', b'x', tarfile.REGTYPE)],
                        [('a', b'x', tarfile.REGTYPE), ('b', b'y', tarfile.REGTYPE)]]:
            with self.subTest(entries=entries), self.assertRaises(ValueError):
                audit.digest_single_tar(tar_bytes(entries))

    def test_mismatch_is_reported_and_container_is_removed_without_start(self):
        cid = 'c'*64
        image_id = 'sha256:'+'d'*64
        fake = lambda command, **kwargs: ({'load':'', 'image':image_id, 'create':cid,
                                            'inspect':'[{"Id": "'+cid+'"}]', 'rm':''}[command[0]])
        candidate = {'image_id': image_id, 'image_tar_sha256':'e'*64, 'approved_for_execution':False}
        with patch.object(audit.gate, 'check_image'), patch.object(audit.gate, 'stream_digest', return_value='e'*64), \
             patch.object(audit.inspect, 'run_docker', side_effect=fake) as docker, \
             patch.object(audit.inspect, 'check_container'), patch.object(audit, 'copy_digest', return_value='f'*64):
            result = audit.audit(io.BytesIO(b'image'), candidate, self.recipe)
        self.assertEqual(result['status'], 'mismatch')
        self.assertFalse(result['approved_for_execution'])
        self.assertEqual(result['native_status'], 'NOT_RUN')
        self.assertEqual(len(result['host_files']), 2)
        self.assertEqual(docker.call_args_list[-1].args[0], ['rm', '-v', cid])
        self.assertNotIn('start', [c.args[0][0] for c in docker.call_args_list])

    def test_inspection_must_return_created_container_id(self):
        with patch.object(audit.inspect, 'run_docker', return_value='[{"Id":"other"}]'), \
             patch.object(audit.inspect, 'check_container') as check:
            with self.assertRaisesRegex(ValueError, 'identity changed'):
                audit.check_own_container('c'*64, 'sha256:' + 'd'*64)
        check.assert_not_called()

    def test_copy_uses_same_explicit_daemon_and_clears_context(self):
        class Result:
            returncode = 0
        payload = tar_bytes([('target', b'bytes', tarfile.REGTYPE)]).getvalue()
        def fake_run(command, **kwargs):
            self.assertEqual(command[:2], ['docker', '--host=unix:///var/run/docker.sock'])
            self.assertNotIn('DOCKER_HOST', kwargs['env'])
            self.assertNotIn('DOCKER_CONTEXT', kwargs['env'])
            kwargs['stdout'].write(payload)
            return Result()
        with patch.dict('os.environ', {'DOCKER_HOST': 'tcp://bad', 'DOCKER_CONTEXT':'bad'}), \
             patch.object(audit.subprocess, 'run', side_effect=fake_run):
            self.assertEqual(audit.copy_digest('c'*64, '/usr/bin/alias'), hashlib.sha256(b'bytes').hexdigest())

    def test_copy_failure_still_removes_created_container(self):
        cid = 'c'*64
        image_id = 'sha256:'+'d'*64
        fake = lambda command, **kwargs: ({'load':'', 'image':image_id, 'create':cid,
                                            'inspect':'[{"Id": "'+cid+'"}]', 'rm':''}[command[0]])
        candidate = {'image_id': image_id, 'image_tar_sha256':'e'*64, 'approved_for_execution':False}
        with patch.object(audit.gate, 'check_image'), patch.object(audit.gate, 'stream_digest', return_value='e'*64), \
             patch.object(audit.inspect, 'run_docker', side_effect=fake) as docker, \
             patch.object(audit.inspect, 'check_container'), patch.object(audit, 'copy_digest', side_effect=ValueError('copy')):
            with self.assertRaisesRegex(ValueError, 'copy'):
                audit.audit(io.BytesIO(b'image'), candidate, self.recipe)
        self.assertEqual(docker.call_args_list[-1].args[0], ['rm', '-v', cid])


if __name__ == '__main__':
    unittest.main()
