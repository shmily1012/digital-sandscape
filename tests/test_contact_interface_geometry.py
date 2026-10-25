import unittest
from contact_interface_geometry import classify


class ContactInterfaceGeometryTests(unittest.TestCase):
    def scene(self, offsets):
        gas = [0.]*49
        material = [0]*49
        material[24] = 2
        for dx, dy in offsets:
            gas[24+dx+7*dy] = 1.
        return gas, material

    def test_local_support_and_underside(self):
        for offset, expected in [((0, 1), 'gas_downstream'),
                                 ((0, -1), 'gas_upstream'),
                                 ((1, 0), 'lateral_or_ambiguous')]:
            groups = classify(*self.scene([offset]), 7)
            self.assertEqual(groups[expected], [24])
            self.assertEqual(sum(map(len, groups.values())), 1)

    def test_rotate_scene_and_gravity_together(self):
        for offset in [(0, 1), (1, 0), (0, -1), (-1, 0), (1, 1)]:
            self.assertEqual(classify(*self.scene([offset]), 7, offset)['gas_downstream'], [24])

    def test_surrounded_grain_not_misclassified(self):
        self.assertEqual(classify(*self.scene([(0, 1), (0, -1)]), 7)
                         ['lateral_or_ambiguous'], [24])

    def test_no_gas_and_invalid_input(self):
        scene = self.scene([])
        self.assertEqual(classify(*scene, 7)['no_adjacent_gas'], [24])
        with self.assertRaises(ValueError):
            classify(*scene, 7, (0, 0))
        scene[0][0] = float('nan')
        with self.assertRaises(ValueError):
            classify(*scene, 7)
