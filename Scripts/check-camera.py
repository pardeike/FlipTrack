#!/usr/bin/env python3
"""Run isolated scanner checks with the physical camera; never publish the host."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time
import uuid

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--device', default='AP11')
parser.add_argument('--reuse-benchmark', action='store_true',
                    help='Temporarily use the camera-authorized benchmark identity, then restore its app.')
parser.add_argument('--scenario', choices=['turn', 'finalPixels', 'recorded', 'corrections'])
args = parser.parse_args()
scenarios = [args.scenario] if args.scenario else ['turn', 'finalPixels', 'recorded', 'corrections']
run_id = str(uuid.uuid4())
output = root / '.build/camera-checks' / run_id
output.mkdir(parents=True)
log_path = root / '.build/logs/check-camera.log'
log_path.parent.mkdir(parents=True, exist_ok=True)
bundle = 'net.pardeike.FlipTrackBenchmark' if args.reuse_benchmark else 'net.pardeike.FlipTrackDeviceHost'
restore = root / '.build/benchmark/Build/Products/Release-iphoneos/FlipTrackBenchmark.app'
step = 'prepare device checks'
installed = False
failure = None

with log_path.open('w') as log:
    def run(*command, check=True):
        return subprocess.run(command, cwd=root, stdout=log, stderr=subprocess.STDOUT, check=check)

    def receive(name, destination):
        return run('xcrun', 'devicectl', '--timeout', '10', 'device', 'copy', 'from', '--device', args.device,
                   '--domain-type', 'appDataContainer', '--domain-identifier', bundle,
                   '--source', f'Documents/{name}', '--destination', str(destination), check=False).returncode == 0

    def stop_host():
        processes_path = output / 'processes.json'
        deadline = time.monotonic() + 15
        terminated = set()
        while True:
            run('xcrun', 'devicectl', '--timeout', '10', 'device', 'info', 'processes',
                '--device', args.device, '--json-output', str(processes_path))
            processes = json.loads(processes_path.read_text())['result']['runningProcesses']
            hosts = [p for p in processes if p.get('executable', '').endswith('/FlipTrackDeviceHost.app/FlipTrackDeviceHost')]
            if not hosts:
                return
            for process in hosts:
                pid = process['processIdentifier']
                if pid not in terminated:
                    run('xcrun', 'devicectl', '--timeout', '10', 'device', 'process', 'terminate',
                        '--device', args.device, '--pid', str(pid))
                    terminated.add(pid)
            if time.monotonic() > deadline:
                raise RuntimeError('Previous check host did not exit before next scenario')
            time.sleep(0.2)

    try:
        if args.reuse_benchmark and not restore.is_dir():
            raise RuntimeError(f'Missing benchmark app to restore: {restore}')
        run('python3', 'Scripts/prepare-live-fixtures.py')
        run('xcodegen', 'generate', '--spec', 'DeviceTests/project.yml', '--project', '.build')
        step = 'build signed camera check host'
        run('xcodebuild', '-project', '.build/FlipTrackDeviceTests.xcodeproj', '-target', 'FlipTrackDeviceHost',
            '-configuration', 'Release', '-sdk', 'iphoneos', '-allowProvisioningUpdates',
            f'PRODUCT_BUNDLE_IDENTIFIER={bundle}', f'SYMROOT={root}/.build/device-autocheck', 'build')
        step = 'install camera check host'
        run('xcrun', 'devicectl', 'device', 'install', 'app', '--device', args.device,
            str(root / '.build/device-autocheck/Release-iphoneos/FlipTrackDeviceHost.app'))
        installed = True
        for scenario in scenarios:
            step = f'physical camera check: {scenario}'
            env = json.dumps({'FLIPTRACK_AUTOCHECK': '1', 'FLIPTRACK_TEST_SCENARIO': scenario,
                              'FLIPTRACK_CHECK_ID': run_id})
            stop_host()
            run('xcrun', 'devicectl', '--timeout', '30', 'device', 'process', 'launch', '--device', args.device,
                '--environment-variables', env, bundle)
            report_path = output / f'autocheck-{scenario}.json'
            deadline = time.monotonic()+90
            while True:
                if receive(report_path.name, report_path):
                    report = json.loads(report_path.read_text())
                    if report.get('runID') == run_id:
                        telemetry_dir = report.get('telemetryDirectory')
                        if not telemetry_dir or not receive(f'Telemetry/{telemetry_dir}', output / f'telemetry-{scenario}'):
                            raise RuntimeError('Missing telemetry or evidence images')
                        if not report.get('passed'):
                            raise RuntimeError(report.get('error', 'Device assertion failed'))
                        break
                if time.monotonic() > deadline:
                    raise RuntimeError('No completed report. Check camera permission and foreground state.')
                time.sleep(2)
            run('xcrun', 'devicectl', 'device', 'capture', 'screenshot', '--device', args.device,
                '--destination', str(output / f'{scenario}.png'))
        if 'recorded' in scenarios:
            step = 'retrieve reader performance'
            if not receive('reader-performance.json', output / 'reader-performance.json'):
                raise RuntimeError('Missing production-reader timing report')
            metrics = json.loads((output / 'reader-performance.json').read_text())
            if metrics['samples'] != 32 or metrics['cameraFrames'] < 32:
                raise RuntimeError('Incomplete recorded-pixel/camera workload')
        (root / '.build/last-camera-check-result').write_text(str(output)+'\n')
    except (Exception, KeyboardInterrupt) as error:
        failure = f'{step} failed: {error}'
    finally:
        if installed and args.reuse_benchmark:
            try:
                run('xcrun', 'devicectl', 'device', 'install', 'app', '--device', args.device, str(restore))
            except Exception as error:
                failure = f'{failure or "Checks completed"}; restoring benchmark app failed: {error}'

if failure:
    print(f'{failure}\nFull log: {log_path}', file=sys.stderr)
    sys.exit(1)
print('ok')
