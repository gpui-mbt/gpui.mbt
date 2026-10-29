"""Exact manifest extension uses the existing pure owner receipt validator."""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parent))
import gpui_evidence as e
from recovery import baseline_utilities as b

class OwnerManifestTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        owner=dict(schema_version=1,kind=b.OWNER_KIND,pid=100,uid=1000,starttime=1000,exe='/usr/bin/python3')
        self.snapshot=self.root/'task-owner.snapshot.json';self.snapshot.write_text(json.dumps(owner))
        roles=['xvfb','session-bus','mozc-server','ibus-daemon','weston-stdio','ibus-unix-peer','ibus-wayland','gpui']
        self.report=dict(evidence_schema_version=2,status='error',task_owner=owner,
            evidence_inputs={name:'0'*64 for name in e.INPUT_FILES},
            peer_ledger=[dict(pid=200+i,uid=1000,starttime=1001+i,exe='/owned/peer',role=role) for i,role in enumerate(roles)])
        self.report['evidence_inputs'][self.snapshot.name]=hashlib.sha256(self.snapshot.read_bytes()).hexdigest()
        self.deployment={'kind':'native-ime-recovery-baseline'}

    def test_exact_owned_manifest_uses_pure_receipt(self):
        with patch.object(b,'stat_identity',side_effect=AssertionError('no live PID')):
            self.assertEqual(e.validate_input_manifest(self.root,self.report,self.deployment),2)

    def test_missing_extra_invalid_owner_and_receipt_rejected(self):
        mutations=[lambda r:r['evidence_inputs'].pop(self.snapshot.name),
            lambda r:r['evidence_inputs'].update({'extra.json':'0'*64}),
            lambda r:r.pop('task_owner'),lambda r:r.update(task_owner=None),
            lambda r:r['task_owner'].update(uid=True),lambda r:r['task_owner'].update(starttime=999),
            lambda r:r['evidence_inputs'].update({self.snapshot.name:'f'*64}),
            lambda r:r.update(peer_ledger=[])]
        for mutate in mutations:
            with self.subTest(mutate=mutate):
                report=deepcopy(self.report);mutate(report)
                with self.assertRaises(ValueError):e.validate_input_manifest(self.root,report,self.deployment)

    def test_body_tamper_and_symlink_rejected(self):
        self.snapshot.write_text('{}')
        with self.assertRaises(ValueError):e.validate_input_manifest(self.root,self.report,self.deployment)
        target=self.root/'other';self.snapshot.rename(target);self.snapshot.symlink_to(target)
        with self.assertRaises(ValueError):e.validate_input_manifest(self.root,self.report,self.deployment)

    def test_success_replay_requires_cleanup(self):
        for status in ('passed','qualified-partial'):
            report=deepcopy(self.report);report['status']=status
            with self.assertRaises(ValueError):e.validate_input_manifest(self.root,report,self.deployment)

    def test_legacy_exact_set_unchanged_owner_cannot_be_smuggled(self):
        for version,names in ((1,e.HISTORICAL_INPUT_FILES),(2,e.INPUT_FILES)):
            report=dict(evidence_schema_version=version,evidence_inputs={n:'0'*64 for n in names})
            self.assertEqual(e.validate_input_manifest(self.root,report,{}),version)
            report['evidence_inputs'][self.snapshot.name]='0'*64
            with self.assertRaises(ValueError):e.validate_input_manifest(self.root,report,{})

if __name__=='__main__':unittest.main()
