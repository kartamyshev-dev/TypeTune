#!/usr/bin/env python3
"""Verify an unchanged app before packaging it without another ad-hoc rebuild."""
import argparse
import hashlib
import json
import pathlib
import subprocess
from native_evidence import capture, digest, require, bundle_digest, target_binary
from verify_native_session import validate_session

def validate_sources(root, sources):
    root = pathlib.Path(root).resolve()
    require((root/'Package.swift').is_file(), 'Package.swift missing')
    actual = {'Package.swift'} | {str(p.relative_to(root)) for p in (root/'Sources').rglob('*')
                                if p.is_file() or p.is_symlink()}
    tracked = set(subprocess.check_output(['git', 'ls-files', '-z', '--', 'Package.swift', 'Sources'],
                                         cwd=root).decode().split('\0')) - {''}
    require(isinstance(sources, dict) and set(sources) == actual == tracked, 'Compiled source/resource set differs')
    for name, expected in sources.items():
        path = (root/name).resolve()
        require(path.is_relative_to(root) and digest(path) == expected, 'Compiled source changed: '+name)
        committed = subprocess.check_output(['git', 'show', 'HEAD:'+name], cwd=root)
        require(hashlib.sha256(committed).hexdigest() == expected, 'Current commit differs: '+name)


def cli_artifacts(root):
    root = pathlib.Path(root)
    return {'cliBinarySha256': digest(root/'dist/layoutpilot-cli'),
            'cliBundleSha256': bundle_digest(root/'dist/LayoutPilot_LayoutPilotCore.bundle')}


def validate_cli_artifacts(root, identity):
    for key, actual in cli_artifacts(root).items():
        require(identity.get(key) == actual, 'Missing or changed CLI artifact: '+key)


def capture_build_identity(root):
    root = pathlib.Path(root).resolve()
    sources = {str(p.relative_to(root)): digest(p) for p in [root/'Package.swift', *sorted((root/'Sources').rglob('*'))] if p.is_file()}
    try:
        validate_sources(root, sources)
        committed = True
    except (ValueError, subprocess.CalledProcessError):
        committed = False
    app = root/'dist/LayoutPilot.app'
    manifest = [(str(p.relative_to(app)), digest(p)) for p in sorted(app.rglob('*')) if p.is_file()]
    return {'compiledInputsMatchCommit': committed, 'sources': sources,
            'binarySha256': digest(app/'Contents/MacOS/LayoutPilot'),
            'bundleSha256': hashlib.sha256(json.dumps(manifest, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest(),
            **cli_artifacts(root)}


def main():
    root = pathlib.Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument('identity')
    parser.add_argument('session', nargs='?')
    parser.add_argument('--artifact-only', action='store_true', help='Candidate integrity only; no native acceptance claim')
    parser.add_argument('--app', help='Exact tested running .app; must match the packaged dist bundle')
    args = parser.parse_args()
    identity = json.loads(pathlib.Path(args.identity).read_text())
    require(args.artifact_only != bool(args.session), 'Choose a native session or candidate artifact verification')
    app = root/'dist/LayoutPilot.app'
    binary = app/'Contents/MacOS/LayoutPilot'
    require(identity.get('compiledInputsMatchCommit') is True, 'Unverified compiled inputs')
    validate_sources(root, identity['sources'])
    validate_cli_artifacts(root, identity)
    require(digest(binary) == identity['binarySha256'], 'Executable changed after checks')
    manifest = [(str(p.relative_to(app)), digest(p)) for p in sorted(app.rglob('*')) if p.is_file()]
    actual = hashlib.sha256(json.dumps(manifest, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()
    require(actual == identity['bundleSha256'], 'Bundle changed after checks')
    tested_binary = target_binary(root, args.app)
    require(bundle_digest(tested_binary.parents[2]) == bundle_digest(app), 'Tested app differs from packaged dist bundle')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    subprocess.run([str(root/'dist/layoutpilot-cli'), 'selftest'], check=True, stdout=subprocess.DEVNULL)
    if args.artifact_only:
        print(json.dumps({'candidateArtifactVerified': True, 'binarySha256': digest(binary),
                          'nativeAcceptance': False, 'notice': 'Integrity only; candidate, not full release acceptance.'}))
        return
    folder = pathlib.Path(args.session)
    session = json.loads((folder/'summary.json').read_text())
    current = capture(root, tested_binary, session['pid'])
    report = validate_session(folder, current)
    require(report['integrityPassed'] and report['correctionQualityPassed'] and report['passed'], 'Native session correction quality failed')
    print(json.dumps({'existingBuildVerified': True, 'binarySha256': digest(binary),
                      'nativeSessionSeconds': report['durationSeconds'],
                      'notice': 'Packages the same tested app; does not claim native acceptance at a new installation path.'}))


if __name__ == '__main__': main()
