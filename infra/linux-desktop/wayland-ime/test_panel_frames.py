import unittest

from panel_frames import PanelFrameError, collect_panel_frames


def out(n, event):
    return f'[ {n}.000] {{Default Queue}}  -> {event}'


def incoming(n, event):
    return f'[ {n}.000] {{Default Queue}} {event}'


def panel(surface=23, role=24):
    return [out(1, f'wl_compositor#4.create_surface(new id wl_surface#{surface})'),
            out(2, f'zwp_input_panel_v1#21.get_input_panel_surface(new id zwp_input_panel_surface_v1#{role}, wl_surface#{surface})')]


class PanelFrameTests(unittest.TestCase):
    def test_callback_must_belong_to_panel_and_follow_its_commit(self):
        lines = panel() + [
            out(3, 'wl_surface#23.attach(wl_buffer#26, 0, 0)'),
            out(4, 'wl_surface#23.frame(new id wl_callback#28)'),
            out(5, 'wl_surface#23.commit()'),
            incoming(6, 'wl_callback#99.done(10)'),
            incoming(7, 'wl_callback#28.done(11)'),
        ]
        frames = collect_panel_frames('\n'.join(lines))
        self.assertEqual(len(frames), 1)
        self.assertEqual((frames[0]['surface'], frames[0]['generation'], frames[0]['callback']), (23, 1, 28))
        self.assertEqual((frames[0]['request_line'], frames[0]['commit_line'], frames[0]['done_line']), (4, 5, 7))
        self.assertIs(frames[0]['attached'], True)

    def test_unrelated_surface_and_unfinished_frame_never_qualify(self):
        lines = [out(1, 'wl_compositor#4.create_surface(new id wl_surface#2)'),
                 out(2, 'wl_surface#2.frame(new id wl_callback#3)'),
                 out(3, 'wl_surface#2.commit()'), incoming(4, 'wl_callback#3.done(1)')]
        self.assertEqual(collect_panel_frames('\n'.join(lines)), [])
        self.assertEqual(collect_panel_frames('\n'.join(panel() + [out(3, 'wl_surface#23.frame(new id wl_callback#28)')])), [])

    def test_done_before_commit_and_callback_reuse_are_rejected(self):
        lines = panel() + [out(3, 'wl_surface#23.frame(new id wl_callback#28)'), incoming(4, 'wl_callback#28.done(1)')]
        with self.assertRaises(PanelFrameError):
            collect_panel_frames('\n'.join(lines))
        lines = panel() + [out(3, 'wl_surface#23.frame(new id wl_callback#28)'),
                           out(4, 'wl_surface#23.frame(new id wl_callback#28)')]
        with self.assertRaises(PanelFrameError):
            collect_panel_frames('\n'.join(lines))

    def test_destroy_fences_old_lifetime_and_allows_reused_ids(self):
        lines = panel() + [out(3, 'wl_surface#23.frame(new id wl_callback#28)'),
                           out(4, 'wl_surface#23.commit()'), out(5, 'wl_surface#23.destroy()'),
                           incoming(6, 'wl_callback#28.done(1)')] + panel() + [
                           out(7, 'wl_surface#23.attach(wl_buffer#26, 0, 0)'),
                           out(8, 'wl_surface#23.frame(new id wl_callback#28)'),
                           out(9, 'wl_surface#23.commit()'), incoming(10, 'wl_callback#28.done(2)')]
        frames = collect_panel_frames('\n'.join(lines))
        self.assertEqual(len(frames), 1)
        self.assertEqual(frames[0]['generation'], 2)
        self.assertEqual(frames[0]['compositor_time'], 2)

    def test_attachment_changes_only_on_commit_and_nil_is_not_visible(self):
        lines = panel() + [out(3, 'wl_surface#23.attach(wl_buffer#26, 0, 0)'),
                           out(4, 'wl_surface#23.frame(new id wl_callback#28)'), out(5, 'wl_surface#23.commit()'),
                           incoming(6, 'wl_callback#28.done(1)'), out(7, 'wl_surface#23.attach(nil, 0, 0)'),
                           out(8, 'wl_surface#23.frame(new id wl_callback#28)'), out(9, 'wl_surface#23.commit()'),
                           incoming(10, 'wl_callback#28.done(2)')]
        frames = collect_panel_frames('\n'.join(lines))
        self.assertEqual([f['attached'] for f in frames], [True, False])

    def test_reuse_before_old_callback_retired_is_ambiguous(self):
        lines = panel() + [out(3, 'wl_surface#23.frame(new id wl_callback#28)'),
                           out(4, 'wl_surface#23.commit()'), out(5, 'wl_surface#23.destroy()')] + panel() + [
                           out(6, 'wl_surface#23.frame(new id wl_callback#28)')]
        with self.assertRaises(PanelFrameError):
            collect_panel_frames('\n'.join(lines))

    def test_foreign_callback_cannot_impersonate_panel_callback(self):
        lines = panel() + [out(3, 'wl_surface#23.frame(new id wl_callback#28)'),
                           out(4, 'wl_surface#23.commit()'),
                           out(5, 'wl_display#1.sync(new id wl_callback#28)'),
                           incoming(6, 'wl_callback#28.done(1)')]
        with self.assertRaises(PanelFrameError):
            collect_panel_frames('\n'.join(lines))

    def test_foreign_role_and_oversized_trace_are_rejected(self):
        with self.assertRaises(PanelFrameError):
            collect_panel_frames(out(1, 'zwp_input_panel_v1#21.get_input_panel_surface(new id zwp_input_panel_surface_v1#24, wl_surface#23)'))
        with self.assertRaises(PanelFrameError):
            collect_panel_frames('x' * (64 * 1024 * 1024 + 1))


if __name__ == '__main__':
    unittest.main()
