#!/usr/bin/env python3
"""Start the R-independent, loopback-only metadata UI (Python 3.10+)."""
import sys

# Keep this file parseable by older Python so the diagnostic precedes sidecar imports.
if sys.version_info < (3, 10):
    sys.stderr.write('Metadata UI requires Python >= 3.10; full analysis additionally requires R >= 4.3.3.\n')
    sys.exit(1)

import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess


def analysis_rscript(scripts):
    if os.name == 'nt':
        return shutil.which(os.environ.get('EMPI_RSCRIPT') or 'Rscript')
    try:
        result = subprocess.run(['bash', str(scripts / 'resolve_rscript.sh')],
                                capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result.stdout.rstrip('\n') if result.returncode == 0 else None


def dependency_report(*, check_r=True):
    scripts = Path(__file__).resolve().parent
    required = ['public_data', 'public_data_server', 'processed_data', 'paper_sources', 'workflow_plans', 'agent_adapter', 'agent_context', 'omics_workbench', 'workbench_api', 'matrix_api', 'matrix_downloads']
    missing = [name for name in required if not (scripts / (name + '.py')).is_file()]
    rscript = analysis_rscript(scripts) if check_r else None
    return {
        'ready': not missing,
        'mode': 'metadata-only',
        'host': '127.0.0.1',
        'python': {'version': '.'.join(map(str, sys.version_info[:3])), 'minimum': '3.10'},
        'missing_modules': missing,
        'optional': {'pypdf': importlib.util.find_spec('pypdf') is not None},
        'r': {'required_for_metadata': False, 'available': rscript is not None, 'path': rscript,
              'note': 'Full R analysis requires a separate R >= 4.3.3 installation and EMP packages.'},
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Print dependency JSON without starting services or installing anything')
    parser.add_argument('--port', type=int, default=os.environ.get('EMP_PUBLIC_DATA_PORT', '8081'))
    args = parser.parse_args(argv)
    if not 1 <= args.port <= 65535:
        parser.error('--port must be between 1 and 65535')
    report = dependency_report(check_r=args.check)
    if args.check:
        print(json.dumps(report, sort_keys=True))
        return 0 if report['ready'] else 1
    if not report['ready']:
        parser.error('Missing project modules: ' + ', '.join(report['missing_modules']))
    try:
        from public_data_server import make_server
        server = make_server(args.port)
    except (ImportError, OSError, ValueError) as exc:
        sys.stderr.write('Metadata UI could not start: {}\n'.format(exc))
        return 1
    print('Metadata-only UI: http://127.0.0.1:{}/public_data.html'.format(server.server_port), flush=True)
    print('No R required for metadata. Full R analysis is a separate service. Press Ctrl+C to stop.', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == '__main__':
    sys.exit(main())
