#!/usr/bin/env python3
"""Audit exhaustive UI shard coverage and PNG evidence without claiming parity.

Usage: python3 tool/parity_regression_report.py /tmp/run-{0,1,2,3} \
  --output /tmp/run-summary.json
No resizing, alignment, pixel tolerance or source comparisons are performed.
"""
import argparse
import collections
import json
from pathlib import Path
import struct


def png_size(path):
    with path.open('rb') as stream:
        header = stream.read(24)
    if header[:8] != b'\x89PNG\r\n\x1a\n' or header[12:16] != b'IHDR':
        raise ValueError('Not a PNG: ' + str(path))
    return list(struct.unpack('>II', header[16:24]))


def summarize(directories):
    reports = [(Path(d), json.loads((Path(d) / 'report.json').read_text()))
               for d in directories]
    manifests = [r['suite']['caseManifest'] for _, r in reports]
    declared = set().union(*(set(m) for m in manifests))
    cases = [c for _, r in reports for c in r['cases']]
    counts = collections.Counter(c['id'] for c in cases)
    evidence = []
    missing_evidence = []
    wrong_dimensions = []
    for _, report in reports:
        viewport = report['viewport']
        for case in report['cases']:
            screenshots = list(dict.fromkeys(case.get('screenshots', [])))
            if not screenshots:
                missing_evidence.append('case-without-screenshot:' + case['id'])
            for name in screenshots:
                main = Path(name)
                for kind, path in [('full', main),
                                   ('toolbox', Path(str(main).replace('.png', '-toolbox.png', 1))),
                                   ('desktop', Path(str(main).replace('.png', '-desktop.png', 1)))]:
                    if not path.is_file():
                        missing_evidence.append(str(path))
                        continue
                    size = png_size(path)
                    evidence.append({'case': case['id'], 'kind': kind,
                                     'path': str(path), 'size': size})
                    expected = ([viewport['width'], viewport['height']] if kind == 'full'
                                else [1224, 640] if kind == 'desktop' else None)
                    if expected and size != expected:
                        wrong_dimensions.append({'path': str(path), 'expected': expected,
                                                 'actual': size})
    failures = [c for c in cases if c['status'] != 'pass']
    missing = sorted(declared - counts.keys())
    duplicate = sorted(k for k, count in counts.items() if count != 1)
    same_manifest = all(m == manifests[0] for m in manifests)
    return {
        'scope': 'real Flutter classic-control UI; frozen compiled snapshot; native file/clipboard/link substitutes; no native shell or pixel parity claim',
        'reports': [str(d / 'report.json') for d, _ in reports],
        'declared': len(declared), 'executed': len(cases),
        'status': dict(collections.Counter(c['status'] for c in cases)),
        'allShardManifestsEqual': same_manifest,
        'missingCaseIds': missing, 'duplicateCaseIds': duplicate,
        'failures': failures,
        'presetCases': sum(c['id'].startswith(('preset.formation.', 'preset.cob.', 'preset.gloom.')) for c in cases),
        'screenshotCounts': dict(collections.Counter(e['kind'] for e in evidence)),
        'toolboxDimensions': sorted({tuple(e['size']) for e in evidence if e['kind'] == 'toolbox'}),
        'missingEvidence': missing_evidence, 'wrongDimensions': wrong_dimensions,
        'coverageCompleteAndPassing': not (missing or duplicate or failures or missing_evidence or wrong_dimensions) and same_manifest,
        'pixelParity': 'notEvaluated', 'nativeWindows': 'notEvaluated',
        'windows1051Game': 'notRun', 'actual1051SaveFile': 'notRun',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directories', nargs='+')
    parser.add_argument('--output', required=True)
    parser.add_argument('--recheck', action='append', default=[], help='Explicit focused recheck directory; original failures remain in report')
    args = parser.parse_args()
    result = summarize(args.directories)
    if args.recheck:
        latest = {case['id']: case for directory in args.directories
                  for case in json.loads((Path(directory) / 'report.json').read_text())['cases']}
        provenance = []
        for directory in args.recheck:
            report_path = Path(directory) / 'report.json'
            check_report = json.loads(report_path.read_text())
            for case in check_report['cases']:
                if case['id'] not in latest:
                    raise ValueError('Recheck ID outside initial suite: ' + case['id'])
                for name in case.get('screenshots', []):
                    png_size(Path(name))
                    png_size(Path(name.replace('.png', '-toolbox.png', 1)))
                    png_size(Path(name.replace('.png', '-desktop.png', 1)))
                provenance.append({'id': case['id'], 'previousStatus': latest[case['id']]['status'],
                                   'latestStatus': case['status'], 'report': str(report_path)})
                latest[case['id']] = case
        result['rechecks'] = provenance
        result['latestStatus'] = dict(collections.Counter(c['status'] for c in latest.values()))
        result['latestCoverageCompleteAndPassing'] = (not any(c['status'] != 'pass' for c in latest.values())
            and not result['missingCaseIds'] and not result['duplicateCaseIds']
            and not result['missingEvidence'] and not result['wrongDimensions']
            and result['allShardManifestsEqual'])
    Path(args.output).write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k not in ['failures']}, ensure_ascii=False))
    return 0 if result.get('latestCoverageCompleteAndPassing', result['coverageCompleteAndPassing']) else 1


if __name__ == '__main__':
    raise SystemExit(main())
