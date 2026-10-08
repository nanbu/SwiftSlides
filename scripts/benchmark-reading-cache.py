#!/usr/bin/env python3
"""Compare a previous ReadingCache.swift with this checkout on macOS; alternate fresh processes."""
import argparse
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = r'''
import Foundation
let n = Int(CommandLine.arguments[1])!
let hits = Int(CommandLine.arguments[2])!
let cache = ReadingDataCache(limit: n * 64)
let keys = (0..<n).map { "part-\($0)" }
let payload = Data(repeating: 42, count: 64)
let start = ContinuousClock.now
for key in keys { cache.insert(payload, for: key) }
var checksum = 0
for i in 0..<hits { checksum += cache.value(for: keys[i % n])!.count }
let duration = start.duration(to: .now).components
precondition(checksum == hits * 64 && cache.statistics.retainedBytes == n * 64)
var usage = rusage()
precondition(getrusage(RUSAGE_SELF, &usage) == 0)
print(Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15)
print(usage.ru_maxrss)
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-source', required=True, type=Path)
    parser.add_argument('--runs', type=int, default=3)
    parser.add_argument('--hits', type=int, default=50000)
    parser.add_argument('--entries', nargs='+', type=int, default=[32, 8000])
    args = parser.parse_args()
    if sys.platform != 'darwin':
        parser.error('Performance measurements are supported on macOS only.')
    if min([args.runs, args.hits, *args.entries]) <= 0:
        parser.error('runs, hits and entries must be positive')
    result = {'platform': platform.platform(), 'swift': subprocess.check_output(['swift', '--version'], text=True).splitlines(),
              'runs': args.runs, 'hits': args.hits, 'payloadBytes': 64, 'operation': 'insert all entries, then cyclic cache hits',
              'scope': 'isolated cache microbenchmark; elapsed time excludes process startup; peak RSS includes process baseline',
              'datasets': []}
    with tempfile.TemporaryDirectory(prefix='swiftslides-cache-benchmark-') as folder:
        work = Path(folder)
        (work / 'main.swift').write_text(SOURCE)
        env = dict(os.environ)
        env.setdefault('CLANG_MODULE_CACHE_PATH', str(work / 'modules'))
        for name, source in [('before', args.baseline_source), ('after', ROOT / 'Sources/SlideCore/ReadingCache.swift')]:
            subprocess.run(['swiftc', '-O', '-package-name', 'CacheBenchmark', str(source), str(work / 'main.swift'), '-o', str(work / name)], env=env, check=True)
        for entries in args.entries:
            samples = {'before': [], 'after': []}
            for _ in range(args.runs):
                for name in samples:
                    output = subprocess.check_output([str(work / name), str(entries), str(args.hits)], text=True).splitlines()
                    samples[name].append({'milliseconds': float(output[0]), 'peakRSSBytes': int(output[1])})
            operations = {name: {'medianMilliseconds': statistics.median(v['milliseconds'] for v in values),
                                  'medianPeakRSSBytes': statistics.median(v['peakRSSBytes'] for v in values), 'samples': values}
                          for name, values in samples.items()}
            result['datasets'].append({'entries': entries, 'operations': operations})
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
