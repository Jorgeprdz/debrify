"""Mechanical evidence checks supporting a separately authored semantic audit.

No application imports, SDKs, compilers, test runners or workflow calls.
An 18-gate approval requires a source-bound reviewed evidence document;
textual presence alone never establishes concurrency or runtime correctness.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from cast_phase2_lexical_check import check_file

ROOT = Path(__file__).resolve().parent.parent
REPORT = ROOT / 'reports/cast_phase2_round5'


def git(*args):
    return subprocess.run(['git', *args], cwd=ROOT, capture_output=True,
                          text=True, check=False)


def source_inventory():
    paths = git('ls-files', '--cached', '--others', '--exclude-standard').stdout.splitlines()
    return sorted(set(p for p in paths if not p.startswith('reports/')
                      and '/__pycache__/' not in p and not p.endswith('.pyc')
                      and p.startswith(('lib/', 'test/', 'android/', 'scripts/',
                                        '.github/', 'pubspec.')) and (ROOT / p).is_file()))


def source_hash():
    digest = hashlib.sha256()
    for path in source_inventory():
        data = (ROOT / path).read_bytes()
        digest.update(path.encode() + b'\0' + len(data).to_bytes(8, 'big') + data)
    return digest.hexdigest()


def test_cases():
    cases = {}
    pattern = re.compile(r"\btest\(\s*(['\"])([ILCSRTEP]\d{2})\s+([^'\"]+)\1")
    for path in sorted((ROOT / 'test').rglob('*.dart')):
        text = path.read_text()
        matches = list(re.finditer(r'\btest\(\s*[\'\"]', text))
        for match in pattern.finditer(text):
            end = next((m.start() for m in matches if m.start() > match.start()), len(text))
            case = {'file': str(path.relative_to(ROOT)), 'name': match[3],
                    'line': text.count('\n', 0, match.start()) + 1,
                    'body': text[match.start():end]}
            cases.setdefault(match[2], []).append(case)
    return cases


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inventory', action='store_true',
                        help='Print source hash and numbered test locations, without approval')
    args = parser.parse_args()
    cases = test_cases()
    digest = source_hash()
    if args.inventory:
        print(json.dumps({'source_sha256': digest,
                          'cases': {key: [{k: v for k, v in c.items() if k != 'body'}
                                          for c in values] for key, values in sorted(cases.items())}},
                         indent=2))
        return 0

    errors = []
    def check(condition, label):
        print(f'{"PASS" if condition else "FAIL"} — {label}')
        if not condition:
            errors.append(label)

    check(git('branch', '--show-current').stdout.strip() == 'feature/google-cast-phase2',
          'target branch, isolated checkout')
    result = git('diff', '--check', 'HEAD')
    check(result.returncode == 0, 'git diff --check HEAD')
    if result.stdout or result.stderr:
        print(result.stdout + result.stderr)
    changed = set(git('diff', '--name-only', 'HEAD').stdout.splitlines())
    changed.update(git('ls-files', '--others', '--exclude-standard').stdout.splitlines())
    for path in sorted(changed):
        if Path(path).suffix in ('.dart', '.kt') and (ROOT / path).is_file():
            lexical = check_file(ROOT, path)
            check(not lexical, f'{path}: balanced lexical delimiters and local imports')
            for message in lexical:
                print(message)
    required = ('CYCLE_JOURNAL.md', 'GATE_RESULTS.md', 'FINDINGS_AND_FIXES.md',
                'REGRESSION_45_MATRIX.md', 'INDEPENDENT_AUDIT.md',
                'RESUME_CHECKPOINT.md', 'FINAL_CLOSURE.md')
    check(all((REPORT / f).is_file() for f in required), 'persistent checkpoint documents')

    expected = {f'{prefix}{i:02}' for prefix, start, end in (
        ('I', 1, 6), ('L', 7, 12), ('C', 13, 18), ('S', 19, 24),
        ('R', 25, 30), ('T', 31, 36), ('E', 37, 42), ('P', 43, 45))
                for i in range(start, end + 1)}
    check(expected <= cases.keys(), '45 required distinct scenario IDs authored')
    check(all(len(values) == 1 for values in cases.values()), 'no duplicate scenario IDs')
    for key in sorted(expected & cases.keys()):
        case = cases[key][0]
        check(bool(re.search(r'\bexpect(?:Later)?\s*\(', case['body']))
              and not re.search(r'\bskip\s*:|TODO|placeholder|expect\(true,\s*isTrue', case['body']),
              f'{key}: concrete assertions, no skip/placeholder')
    matrix_path = REPORT / 'REGRESSION_CASES.json'
    if matrix_path.exists():
        matrix = json.loads(matrix_path.read_text())
        check(expected <= matrix.keys(), 'scenario matrix covers all required IDs')
        for key in sorted(expected & matrix.keys()):
            entry = matrix[key]
            complete = all(entry.get(k) for k in ('initial', 'adversarial', 'expected',
                                                 'assertions', 'production', 'test_file'))
            refs = entry.get('production', [])
            valid = bool(refs) and all((ROOT / ref['file']).is_file()
                and ref['symbol'] in (ROOT / ref['file']).read_text() for ref in refs)
            actual = cases[key][0] if key in cases else {}
            snippets = entry.get('assertions', [])
            fresh = (entry.get('name') == actual.get('name')
                     and entry.get('test_line') == actual.get('line')
                     and isinstance(snippets, list) and bool(snippets)
                     and all(snippet in actual.get('body', '') for snippet in snippets))
            check(complete and valid and entry.get('status') == 'AUTHORED / NOT RUN'
                  and fresh and entry['test_file'] == actual.get('file'),
                  f'{key}: complete matrix and actual production references')
    else:
        check(False, 'reviewed regression matrix JSON missing')

    service = (ROOT / 'lib/services/cast_service.dart').read_text()
    native = (ROOT / 'android/app/src/main/kotlin/com/debrify/app/cast/DebrifyCastManager.kt').read_text()
    for field in ('bridgeInstanceId', 'sessionEpoch', 'snapshotRevision',
                  'receiverOperationBlocked', 'expectedSessionEpoch',
                  'expectedContentId', 'expectedMediaSessionId'):
        check(field in service and field in native, f'Dart/Kotlin wire contract: {field}')

    evidence_path = REPORT / 'GATE_EVIDENCE.json'
    if evidence_path.exists():
        evidence = json.loads(evidence_path.read_text())
        check(evidence.get('source_sha256') == digest, 'semantic audit binds exact current source tree')
        check(evidence.get('p0_open') == 0 and evidence.get('p1_open') == 0,
              'reviewed finding ledger has no open P0/P1')
        for number in range(1, 19):
            name = f'G{number:02}'
            entry = evidence.get('gates', {}).get(name, {})
            refs = entry.get('references', [])
            valid = bool(refs)
            for ref in refs:
                path = ROOT / ref['file']
                if not path.is_file() or ref.get('sha256') != hashlib.sha256(path.read_bytes()).hexdigest():
                    valid = False
            check(entry.get('status') == 'PASS' and entry.get('rationale')
                  and entry.get('reviewer') and valid, f'{name}: explicit reviewed, hash-bound evidence')
        check(evidence.get('independent_audit') == 'PASS', 'independent adversarial review closed')
    else:
        check(False, 'semantic review evidence missing — cannot declare STATIC GREEN')
    print(f'SOURCE SHA256: {digest}')
    print('BUILD / ANALYZE / UNIT TESTS / GRADLE: NOT RUN; ACTIONS: NOT LAUNCHED')
    if errors:
        print(f'STATIC AUDIT INCOMPLETE: {len(errors)} failed evidence checks')
        return 1
    print('MECHANICAL STATIC EVIDENCE PASS — runtime and test execution remain unverified')
    return 0


if __name__ == '__main__':
    sys.exit(main())
