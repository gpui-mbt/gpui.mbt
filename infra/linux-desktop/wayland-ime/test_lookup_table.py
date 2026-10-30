#!/usr/bin/python3
"""Portable GVariant parsing tests; no native GUI or IME is launched."""
import unittest
from gi.repository import GLib
import lookup_table


def update(candidates, *, page_size=2, cursor=0, cursor_visible=True, visible=True, labels=()):
    def text(value):
        attrs = GLib.Variant('(sa{sv}av)', ('IBusAttrList', {}, []))
        return GLib.Variant('(sa{sv}sv)', ('IBusText', {}, value, attrs))
    table = GLib.Variant('(sa{sv}uubbiavav)', ('IBusLookupTable', {}, page_size, cursor,
        cursor_visible, False, 1, [text(v) for v in candidates], [text(v) for v in labels]))
    return GLib.Variant('(vb)', (table, visible))


class LookupTableTests(unittest.TestCase):
    def test_second_page_selection_and_labels(self):
        body = update(['一', '二', '日本', '四', '五'], cursor=3, labels=['1.', '2.'])
        result = lookup_table.decode_update(body)
        self.assertEqual(lookup_table.decode_gdbus_body(body.print_(True)), result)
        self.assertEqual(result['rows'], [
            {'absolute_index': 2, 'page_index': 0, 'text': '日本', 'label': '1.', 'selected': False},
            {'absolute_index': 3, 'page_index': 1, 'text': '四', 'label': '2.', 'selected': True}])
        self.assertTrue(result['visible'])

    def test_hidden_and_invisible_cursor_are_not_selected(self):
        result = lookup_table.decode_update(update(['日本'], cursor_visible=False, visible=False))
        self.assertFalse(result['visible'])
        self.assertFalse(result['rows'][0]['selected'])
        self.assertFalse(lookup_table.decode_update(update(['日本'], visible=False))['rows'][0]['selected'])

    def test_empty_table_and_last_partial_page(self):
        self.assertEqual(lookup_table.decode_update(update([]))['rows'], [])
        self.assertEqual(lookup_table.decode_update(update(['一', '二', '三'], cursor=2))['rows'][0]['text'], '三')

    def test_invalid_signature_and_bounds_fail(self):
        with self.assertRaises(lookup_table.LookupEvidenceError):
            lookup_table.decode_update(GLib.Variant('(s)', ('wrong',)))
        for args in ({'page_size': 0}, {'page_size': 17}, {'cursor': 2}):
            with self.subTest(args=args), self.assertRaises(lookup_table.LookupEvidenceError):
                lookup_table.decode_update(update(['日本'], **args))

    def test_foreign_serialized_object_fails(self):
        table = GLib.Variant('(sa{sv}uubbiavav)', ('Foreign', {}, 2, 0, True, False, 1, [], []))
        with self.assertRaises(lookup_table.LookupEvidenceError):
            lookup_table.decode_update(GLib.Variant('(vb)', (table, True)))

    def test_malformed_gdbus_body_fails(self):
        with self.assertRaises(lookup_table.LookupEvidenceError):
            lookup_table.decode_gdbus_body("(<('IBusLookupTable',)>, true")


if __name__ == '__main__':
    unittest.main()
