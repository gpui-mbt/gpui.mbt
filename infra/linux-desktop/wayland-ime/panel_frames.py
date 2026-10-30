"""Inspect input-panel frame callbacks in a retained WAYLAND_DEBUG stream.

This is a diagnostic building block only. A completed callback does not prove
which IBus lookup update was painted, that a screenshot captured that frame, or
that candidate text/highlight was visible. It never qualifies the IME gate.
"""

import re


class PanelFrameError(ValueError):
    pass


_LINE = re.compile(r'^\[\s*(\d+\.\d+)\]\s+\{[^}]+\}\s+(?:(->)\s+)?(.*)$')
_CREATE = re.compile(r'^wl_compositor[#@]\d+\.create_surface\(new id wl_surface[#@](\d+)\)$')
_PANEL = re.compile(r'^zwp_input_panel_v1[#@]\d+\.get_input_panel_surface\(new id zwp_input_panel_surface_v1[#@](\d+), wl_surface[#@](\d+)\)$')
_ATTACH = re.compile(r'^wl_surface[#@](\d+)\.attach\((nil|wl_buffer[#@]\d+),\s*-?\d+,\s*-?\d+\)$')
_FRAME = re.compile(r'^wl_surface[#@](\d+)\.frame\(new id wl_callback[#@](\d+)\)$')
_COMMIT = re.compile(r'^wl_surface[#@](\d+)\.commit\(\)$')
_DESTROY = re.compile(r'^wl_surface[#@](\d+)\.destroy\(\)$')
_DONE = re.compile(r'^wl_callback[#@](\d+)\.done\((\d+)\)$')


def collect_panel_frames(log):
    """Return complete panel callback records; never infer lookup contents.

    IDs belong to one connection and may be recycled. A surface gets a new
    generation at every create and is recognized only after the panel role is
    created for it. A callback is bound to the next surface commit, and a
    callback completed after destruction is not a completed live frame.
    Truncated/unrelated records do not create a positive result.
    """
    if not isinstance(log, str) or len(log) > 64 * 1024 * 1024:
        raise PanelFrameError('invalid or oversized trace')
    surfaces = {}
    generations = {}
    callbacks = {}
    retired = set()
    completed = []
    for number, raw in enumerate(log.splitlines(), 1):
        line = _LINE.match(raw)
        if not line:
            continue
        timestamp, arrow, body = line.groups()
        outgoing = arrow is not None
        match = _CREATE.fullmatch(body) if outgoing else None
        if match:
            surface = int(match[1])
            if surface in surfaces:
                raise PanelFrameError('surface created before destruction')
            generations[surface] = generations.get(surface, 0) + 1
            surfaces[surface] = dict(generation=generations[surface], panel=None,
                                     pending=[], attached=None, next_attach=None,
                                     has_attach=False)
            continue
        match = _PANEL.fullmatch(body) if outgoing else None
        if match:
            panel, surface = map(int, match.groups())
            if surface not in surfaces or surfaces[surface]['panel'] is not None:
                raise PanelFrameError('invalid panel surface role')
            surfaces[surface]['panel'] = panel
            continue
        match = _ATTACH.fullmatch(body) if outgoing else None
        if match:
            surface, attachment = int(match[1]), match[2]
            if surface in surfaces and surfaces[surface]['panel'] is not None:
                surfaces[surface]['next_attach'] = attachment != 'nil'
                surfaces[surface]['has_attach'] = True
            continue
        match = _FRAME.fullmatch(body) if outgoing else None
        if match:
            surface, callback = map(int, match.groups())
            if surface in surfaces and surfaces[surface]['panel'] is not None:
                if callback in callbacks or callback in retired:
                    raise PanelFrameError('ambiguous reused callback')
                record = dict(surface=surface, generation=surfaces[surface]['generation'],
                              panel=surfaces[surface]['panel'], callback=callback,
                              request_line=number, request_ms=timestamp,
                              commit_line=None, commit_ms=None, attached=None)
                callbacks[callback] = record
                surfaces[surface]['pending'].append(callback)
            continue
        match = _COMMIT.fullmatch(body) if outgoing else None
        if match:
            surface = int(match[1])
            if surface in surfaces and surfaces[surface]['panel'] is not None:
                state = surfaces[surface]
                if state['has_attach']:
                    state['attached'] = state['next_attach']
                    state['has_attach'] = False
                for callback in state['pending']:
                    callbacks[callback].update(commit_line=number, commit_ms=timestamp,
                                               attached=state['attached'])
                state['pending'] = []
            continue
        match = _DESTROY.fullmatch(body) if outgoing else None
        if match:
            surface = int(match[1])
            if surface in surfaces:
                generation = surfaces[surface]['generation']
                for callback, record in list(callbacks.items()):
                    if record['surface'] == surface and record['generation'] == generation:
                        del callbacks[callback]
                        retired.add(callback)
                del surfaces[surface]
            continue
        match = _DONE.fullmatch(body) if not outgoing else None
        if match:
            callback, serial = map(int, match.groups())
            if callback in retired:
                retired.remove(callback)
                continue
            record = callbacks.pop(callback, None)
            if record is None:
                continue
            if record['commit_line'] is None:
                raise PanelFrameError('callback completed before commit')
            record.update(done_line=number, done_ms=timestamp, compositor_time=serial)
            completed.append(record)
    return completed
