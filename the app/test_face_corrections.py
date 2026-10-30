"""Persistent manual decisions, synthetic media only. Run with a temporary cwd."""
import tempfile
import unittest
from pathlib import Path

import numpy as np

from database import JsonDatabase
import gallery_grouping as gg
from test_gallery import FakeFace, StubScanner, identity, write_photo


class CorrectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.db = JsonDatabase(self.root / 'db')

    def scan(self, db, path, faces):
        scanner = StubScanner(db, lambda frame: faces, self.root)
        scanner.options.rescan = True
        return scanner.scan_file(path)

    def test_delete_survives_reload_and_rescan_without_removing_another_person(self):
        photo = self.root / 'photo.jpg'
        write_photo(photo)
        faces = [FakeFace((40, 40, 140, 140), identity(1, 1)[0]),
                 FakeFace((220, 40, 320, 140), identity(2, 1)[0])]
        self.scan(self.db, photo, faces)
        removed, kept = list(self.db.faces)
        crop = Path(self.db.faces[removed]['image_path'])
        self.db.delete_face(removed)
        self.assertFalse(crop.exists())
        reloaded = JsonDatabase(self.root / 'db')
        result = self.scan(reloaded, photo, faces)
        self.assertEqual(result.faces_new, 0)
        self.assertEqual(list(reloaded.faces), [kept])
        self.assertEqual(len(reloaded.face_suppressions), 1)
        detections = reloaded.get_media_by_path(str(photo))['detections']
        self.assertTrue(all(hit[3] == kept for hit in detections if hit[2] == 'f'))

    def test_deleted_linked_copies_stay_deleted_but_new_photos_are_not_banned(self):
        photos = [self.root / name for name in ('a.jpg', 'b.jpg', 'new.jpg')]
        for path in photos:
            write_photo(path)
        faces = [FakeFace((40, 40, 140, 140), identity(1, 1)[0])]
        for path in photos[:2]:
            self.scan(self.db, path, faces)
        self.assertEqual(len(self.db.faces), 1)
        self.db.delete_face(next(iter(self.db.faces)))
        reloaded = JsonDatabase(self.root / 'db')
        for path in photos[:2]:
            self.assertEqual(self.scan(reloaded, path, faces).faces_new, 0)
        self.assertEqual(self.scan(reloaded, photos[2], faces).faces_new, 1)

    def test_video_deletion_matches_moving_frames_without_blocking_a_different_person(self):
        vector = identity(1, 1)[0]
        fid = self.db.add_face(vector, str(self.root / 'video.mp4'), bbox=dict(x=0, y=0, w=100, h=100),
                               extra=dict(frame_number=0))
        self.db.delete_face(fid, delete_file=False)
        reloaded = JsonDatabase(self.root / 'db')
        self.assertTrue(reloaded.is_face_suppressed(str(self.root / 'video.mp4'), vector,
                                                    (200, 100, 100, 100), 15, True))
        self.assertFalse(reloaded.is_face_suppressed(str(self.root / 'video.mp4'), identity(2, 1)[0],
                                                     (0, 0, 100, 100), 15, True))

    def test_hide_survives_scan_and_every_automatic_grouping_mode(self):
        person = self.db.create_person('Known')
        vectors = identity(4, 12, spread=.08)
        for vector in vectors[:6]:
            self.db.add_face(vector, 'known.jpg', person_id=person, quality_score=.9)
        hidden = [self.db.add_face(vector, f'loose-{index}.jpg', quality_score=.9)
                  for index, vector in enumerate(vectors[6:])]
        self.assertTrue(gg.review_state(self.db).suggestions)
        self.db.dismiss_face_group(hidden)
        reloaded = JsonDatabase(self.root / 'db')
        state = gg.review_state(reloaded)
        self.assertFalse(state.suggestions)
        self.assertFalse(state.groups)
        self.assertFalse(set(hidden) & set(state.unsorted_face_ids))
        gg.group_library(reloaded, log=lambda *args: None)
        self.assertTrue(all(reloaded.faces[fid]['person_id'] is None for fid in hidden))
        reloaded.assign_face_to_person(hidden[0], person)
        self.assertFalse(reloaded.faces[hidden[0]]['review_dismissed'])

    def test_merging_moves_corrections_and_does_not_resurrect_source_or_hidden_faces(self):
        source, target, third = [self.db.create_person(name) for name in ('Drop', 'Keep', 'Different')]
        owned = self.db.add_face(identity(1, 1)[0], 'owned.jpg', person_id=source)
        stray = self.db.add_face(identity(2, 1)[0], 'stray.jpg')
        self.db.reject_face_from_person(stray, source)
        self.db.dismiss_face_group([stray])
        self.db.mark_persons_distinct(source, third)
        self.assertTrue(self.db.merge_persons(source, target))
        reloaded = JsonDatabase(self.root / 'db')
        gg.group_library(reloaded, log=lambda *args: None)
        self.assertNotIn(source, reloaded.persons)
        self.assertEqual(reloaded.faces[owned]['person_id'], target)
        self.assertEqual(reloaded.faces[stray]['rejected_person_ids'], [target])
        self.assertTrue(reloaded.faces[stray]['review_dismissed'])
        self.assertIn((min(target, third), max(target, third)), reloaded.distinct_pairs())

    def test_deleting_a_profile_prevents_automatic_recreation(self):
        person = self.db.create_person('Removed')
        for index, vector in enumerate(identity(3, 8, spread=.05)):
            self.db.add_face(vector, f'photo-{index}.jpg', person_id=person, quality_score=.9)
        self.db.delete_person(person)
        reloaded = JsonDatabase(self.root / 'db')
        gg.group_library(reloaded, log=lambda *args: None)
        self.assertFalse(reloaded.persons)
        self.assertEqual(len(reloaded.faces), 8)
        self.assertTrue(all(face['review_dismissed'] for face in reloaded.faces.values()))


if __name__ == '__main__':
    unittest.main(verbosity=2)
