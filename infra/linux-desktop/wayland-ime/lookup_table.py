"""Decode an IBus panel lookup update; this does not establish visible pixels.

IBus 1.5.32: src/ibuspanelservice.c UpdateLookupTable has signature (vb),
while src/ibuslookuptable.c serializes IBusLookupTable as
(sa{sv}uubbiavav). Caller must authenticate and order the received message,
bind it to input/checkpoint and separately prove the panel's rendered content.
"""


class LookupEvidenceError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise LookupEvidenceError(message)


def decode_gdbus_body(body_text):
    """Parse a retained GDBus `Body:` from an authenticated panel message."""
    from gi.repository import GLib

    try:
        body = GLib.Variant.parse(GLib.VariantType.new('(vb)'), body_text, None, None)
    except GLib.Error as error:
        raise LookupEvidenceError('malformed UpdateLookupTable body') from error
    return decode_update(body)


def decode_update(body):
    """Return the expected current page from one GLib.Variant method body.

    This reports the table sent to the panel, not what GTK has painted. A
    caller must not interpret this result as candidate-table qualification.
    """
    require(body.get_type_string() == '(vb)', 'wrong UpdateLookupTable signature')
    table = body.get_child_value(0).get_variant()
    require(table.get_type_string() == '(sa{sv}uubbiavav)', 'wrong serialized lookup table signature')
    name, _attachments, page_size, cursor, cursor_visible, _round, orientation, candidates, labels = table.unpack()
    visible = body.get_child_value(1).get_boolean()
    require(name == 'IBusLookupTable', 'wrong serialized object type')
    require(1 <= page_size <= 16, 'invalid page size')
    require(not candidates or cursor < len(candidates), 'cursor outside candidate list')
    require(bool(candidates) or cursor == 0, 'empty table has nonzero cursor')

    def text(value):
        require(isinstance(value, tuple) and len(value) == 4 and value[0] == 'IBusText', 'invalid candidate or label')
        require(isinstance(value[2], str), 'invalid text')
        return value[2]

    strings = [text(value) for value in candidates]
    label_strings = [text(value) for value in labels]
    start = cursor // page_size * page_size
    rows = [{'absolute_index': i, 'page_index': i - start, 'text': strings[i],
             'label': label_strings[i - start] if i - start < len(label_strings) else None,
             'selected': visible and cursor_visible and i == cursor}
            for i in range(start, min(start + page_size, len(strings)))]
    return {'visible': visible, 'page_size': page_size, 'cursor': cursor,
            'cursor_visible': cursor_visible, 'orientation': orientation, 'rows': rows}
