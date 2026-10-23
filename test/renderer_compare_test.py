"""Run with a Pillow-enabled Python: python test/renderer_compare_test.py."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from PIL import Image, ImageCms

spec = importlib.util.spec_from_file_location('compare_parity', Path(__file__).parents[1] / 'tool/compare_parity.py')
compare_parity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compare_parity)


class ComparatorTest(unittest.TestCase):
    def test_exact_delta_crops_and_dimensions(self):
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp)
            ref, actual = out / 'ref.png', out / 'actual.png'
            Image.new('RGBA', (800, 600), 'white').save(ref)
            Image.new('RGBA', (800, 600), 'white').save(actual)
            self.assertEqual(compare_parity.compare(ref, actual, out, 'exact', 8)['status'], 'exact')
            image = Image.open(actual)
            image.putpixel((2, 2), (0, 255, 255, 255))
            image.save(actual)
            result = compare_parity.compare(ref, actual, out, 'changed', 8)
            self.assertEqual(result['different_pixel_ratio'], 1 / 480000)
            self.assertEqual(result['mae_rgba'], 255 / (480000 * 4))
            self.assertEqual(result['max_channel_delta'], 255)
            self.assertEqual(compare_parity.compare(ref, actual, out, 'crop', 8, [0, 0, 2, 2], [0, 0, 2, 2])['status'], 'exact')
            image = Image.new('RGBA', (800, 600), 'white')
            image.putpixel((2, 2), (255, 255, 255, 254))
            image.save(actual)
            alpha_result = compare_parity.compare(ref, actual, out, 'alpha', 8)
            self.assertEqual(alpha_result['mae_rgba'], 1 / (480000 * 4))
            self.assertEqual(alpha_result['different_pixel_ratio'], 1 / 480000)
            profile = ImageCms.ImageCmsProfile(ImageCms.createProfile('sRGB')).tobytes()
            Image.new('RGBA', (800, 600), 'white').save(actual, icc_profile=profile)
            self.assertEqual(compare_parity.compare(ref, actual, out, 'profile', 8)['status'], 'exact')
            Image.new('RGBA', (799, 600), 'white').save(actual)
            self.assertEqual(compare_parity.compare(ref, actual, out, 'size', 8)['status'], 'dimension_mismatch')
            for suffix in ['heat', 'side', 'absolute']:
                self.assertTrue((out / f'changed-{suffix}.png').exists())


if __name__ == '__main__':
    unittest.main()
