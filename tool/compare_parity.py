#!/usr/bin/env python3
"""Compare unscaled, uncropped 800x600 reference and Flutter images.

No auto-alignment, resampling or color correction. A JPEG reference is lossy;
raw metrics are always retained and never treated as proof of exact parity.
"""
import argparse
import json
import io
from pathlib import Path
from urllib.parse import quote
from PIL import Image, ImageChops, ImageCms


def compare(reference, actual, output, case_id, threshold, reference_clip=None, flutter_clip=None):
    def decode(path):
        image = Image.open(path)
        profile_data = image.info.get('icc_profile')
        profile_name = 'sRGB (assumed for untagged image)'
        raw = image.convert('RGBA')
        if profile_data:
            profile = ImageCms.ImageCmsProfile(io.BytesIO(profile_data))
            profile_name = ImageCms.getProfileName(profile).strip()
            image = ImageCms.profileToProfile(image.convert('RGB'), profile, ImageCms.createProfile('sRGB'), outputMode='RGB').convert('RGBA')
            image.putalpha(raw.getchannel('A'))
        else:
            image = raw
        return image, raw, profile_name
    ref, raw_ref, ref_profile = decode(reference)
    got, raw_got, got_profile = decode(actual)
    def crop(image, clip):
        if clip is None:
            return image
        if isinstance(clip, dict):
            x, y, w, h = (clip[k] for k in ('x', 'y', 'width', 'height'))
        else:
            x, y, w, h = clip
        if min(x, y) < 0 or min(w, h) <= 0 or x + w > image.width or y + h > image.height:
            raise ValueError(f'Clip outside image bounds: {clip}, image {image.size}')
        return image.crop((x, y, x + w, y + h))
    ref, got = crop(ref, reference_clip), crop(got, flutter_clip)
    raw_ref, raw_got = crop(raw_ref, reference_clip), crop(raw_got, flutter_clip)
    if ref.size != got.size:
        return {'id': case_id, 'status': 'dimension_mismatch', 'reference_size': ref.size, 'flutter_size': got.size}
    delta = ImageChops.difference(ref, got)
    def absolute_sum(image):
        return sum((i % 256) * n for i, n in enumerate(image.histogram()))
    def maximum_channel(image):
        channels = image.split()
        maximum = channels[0]
        for channel in channels[1:]:
            maximum = ImageChops.lighter(maximum, channel)
        return maximum
    maximum = maximum_channel(delta)
    histogram = maximum.histogram()
    raw_delta = ImageChops.difference(raw_ref, raw_got)
    raw_histogram = maximum_channel(raw_delta).histogram()
    count = ref.width * ref.height
    absolute = absolute_sum(delta)
    changed = count - histogram[0]
    significant = sum(histogram[threshold + 1:])
    black = Image.new('L', ref.size)
    heat = Image.merge('RGB', (maximum.point(lambda value: min(255, value * 4)), black, black))
    heat.save(output / f'{case_id}-heat.png', compress_level=1)
    side = Image.new('RGBA', (ref.width * 2, ref.height))
    side.paste(ref, (0, 0)); side.paste(got, (ref.width, 0))
    side.save(output / f'{case_id}-side.png', compress_level=1)
    delta.convert('RGB').save(output / f'{case_id}-absolute.png', compress_level=1)
    delta.getchannel('A').save(output / f'{case_id}-alpha.png', compress_level=1)
    return {'id': case_id, 'status': 'exact' if changed == 0 else 'different', 'comparison_space': 'sRGB via embedded ICC profiles', 'reference_profile': ref_profile, 'flutter_profile': got_profile, 'raw_encoded_mae_rgba': absolute_sum(raw_delta) / (count * 4), 'raw_encoded_different_pixel_ratio': (count - raw_histogram[0]) / count, 'mae_rgba': absolute / (count * 4), 'different_pixel_ratio': changed / count, 'over_threshold_pixel_ratio': significant / count, 'threshold': threshold, 'max_channel_delta': maximum.getextrema()[1], 'reference': str(reference), 'flutter': str(actual), 'heatmap': str(output / f'{case_id}-heat.png'), 'side_by_side': str(output / f'{case_id}-side.png')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path('/tmp/pvz-parity'))
    parser.add_argument('--kind', choices=['board', 'toolbox', 'full', 'window'], help='Limit a focused pass while retaining original dimensions.')
    parser.add_argument('--ui-root', type=Path, action='append', default=[], help='Existing real UI capture directories; repeat for multiple suites.')
    parser.add_argument('--output-dir', type=Path, help='Separate report directory for an independent comparison pass.')
    parser.add_argument('--manifest', type=Path, default=Path('docs/parity-cases.json'))
    parser.add_argument('--threshold', type=int, default=8, help='Reporting threshold only; exactness still requires zero differences. Fixed default 8 exposes JPEG/engine differences.')
    args = parser.parse_args()
    if not 0 <= args.threshold <= 255:
        parser.error('threshold must be in 0..255')
    output = args.output_dir or args.root / 'diff'; output.mkdir(parents=True, exist_ok=True)
    records = json.loads((args.root / 'render-results.json').read_text())['cases']
    extra = {}
    if args.manifest.exists():
        manifest = json.loads(args.manifest.read_text())
        extra = {c['id']: c for c in (manifest if isinstance(manifest, list) else manifest['cases'])}
        existing = {c['id'] for c in records}
        records.extend({'id': c['id'], 'status': 'rendered', 'png': str(args.root / 'flutter' / (c['id'] + '.png'))} for c in extra.values() if c['id'] not in existing)
    results = []
    for case in records:
        case_id = case['id']
        if case['status'] != 'rendered':
            results.append({'id': case_id, 'status': 'render_error'}); continue
        case = {**case, **extra.get(case_id, {})}
        if args.kind and case.get('kind', 'board') != args.kind:
            continue
        if case.get('kind') in ('toolbox', 'full'):
            suffix = '-toolbox.png' if case['kind'] == 'toolbox' else '-desktop.png'
            name = case_id[len('toolbox.'):] if case_id.startswith('toolbox.') else case_id
            if case.get('tab'):
                name = 'tab.' + quote(case['tab'], safe='')
            if case.get('windowStyle') is not None:
                name = 'original.rWindow' + str(case['windowStyle'])
            candidates = [folder / (name + suffix) for folder in args.ui_root]
            captured = [p for p in candidates if p.exists()]
            if captured:
                case['png'] = str(max(captured, key=lambda p: p.stat().st_mtime))
        if case.get('invalidReference'):
            results.append({'id': case_id, 'status': 'invalid_reference', 'reason': case.get('reason', 'Reference scenario is invalid')}); continue
        if not Path(case['png']).exists():
            results.append({'id': case_id, 'status': 'missing_flutter'}); continue
        explicit = case.get('reference')
        candidates = [Path(explicit)] if explicit else [args.root / 'reference' / f'{case_id}{ext}' for ext in ('.png', '.jpg', '.jpeg')]
        ref = next((p for p in candidates if p.exists()), None)
        if ref is None:
            results.append({'id': case_id, 'status': 'missing_reference'}); continue
        try:
            result = compare(ref, Path(case['png']), output, case_id, args.threshold, case.get('referenceClip'), case.get('flutterClip'))
            bounds = case.get('objectBounds', [])
            if len(bounds) == 1 and result['status'] in ('exact', 'different') and not case.get('referenceClip') and not case.get('flutterClip'):
                left, top, right, bottom = bounds[0]['rect']
                region = [left, top, right - left, bottom - top]
                if region[2] > 0 and region[3] > 0:
                    result['object_region'] = compare(ref, Path(case['png']), output, case_id + '-object', args.threshold, region, region)
            results.append(result)
        except (ValueError, OSError) as error:
            results.append({'id': case_id, 'status': 'comparison_error', 'error': str(error)})
    summary = {status: sum(r['status'] == status for r in results) for status in sorted({r['status'] for r in results})}
    (output / 'report.json').write_text(json.dumps({'summary': summary, 'cases': results}, ensure_ascii=False, indent=2))
    print(json.dumps(summary, ensure_ascii=False))
    return 0 if all(r['status'] == 'exact' for r in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
