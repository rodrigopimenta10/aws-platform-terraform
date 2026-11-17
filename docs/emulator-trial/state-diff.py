#!/usr/bin/env python3
"""Compares the state Terraform read back from Moto and from AWS Emulator for the same test run.

Input: two `terraform test -verbose` logs of the same module (written by run.sh as <module>.test.log).
Output: for each resource type, the attribute lines that differ once run-specific values (resource IDs,
account IDs, key IDs, timestamps, addresses) are replaced by placeholders.

Usage: state-diff.py <moto.test.log> <emulator.test.log>
"""
import collections
import re
import sys

SUBS = [
    (re.compile(r'\b(123456789012|000000000000)\b'), 'ACCOUNT'),
    (re.compile(r'\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b'), 'UUID'),
    (re.compile(r'\b(vpc|subnet|rtb|igw|nat|eipalloc|eipassoc|eni|sg|sgr|vpce|fl|acl|aclassoc|rtbassoc|dopt|pl|r)-[0-9a-f]{6,}\b'), r'\1-ID'),
    (re.compile(r'\b\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d+)?(Z|[+-]\d\d:\d\d)\b'), 'TIMESTAMP'),
    (re.compile(r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b(?!/)'), 'IP'),
    (re.compile(r'\b(AKIA|AROA|AIDA|ASIA|EMULATOR)[A-Z0-9]{12,}\b'), 'PRINCIPAL_ID'),
    (re.compile(r'\s+'), ' '),
]


def norm(line):
    for rx, to in SUBS:
        line = rx.sub(to, line)
    return line.strip()


def parse(path):
    """Returns {run name: {resource address without index: Counter(normalised attribute lines)}}."""
    runs, run, addr = {}, None, None
    for raw in open(path, encoding='utf-8', errors='replace'):
        m = re.match(r'\s*run "([^"]+)"\.\.\. (pass|fail|skip)', raw)
        if m:
            run = m.group(1)
            runs[run] = collections.defaultdict(collections.Counter)
            addr = None
            continue
        m = re.match(r'# ([^\s:]+(?:\[[^\]]*\])?(?:\.[^\s:]+(?:\[[^\]]*\])?)*):', raw)
        if m and run:
            addr = re.sub(r'\[[^\]]*\]', '', m.group(1))
            continue
        if raw.startswith('}'):
            addr = None
            continue
        if run and addr and raw.startswith(' '):
            runs[run][addr][norm(raw)] += 1
    return runs


def main():
    moto, emu = parse(sys.argv[1]), parse(sys.argv[2])
    for run in moto:
        if run not in emu or not emu[run]:
            print(f'## run "{run}": no state from the emulator (run failed or was skipped)')
            continue
        diffs = []
        for addr in sorted(set(moto[run]) | set(emu[run])):
            a, b = moto[run].get(addr), emu[run].get(addr)
            if a is None or b is None:
                diffs.append(f'  {addr}: only in {"Moto" if b is None else "emulator"}')
                continue
            only_a, only_b = sorted((a - b).elements()), sorted((b - a).elements())
            if only_a or only_b:
                diffs.append(f'  {addr}')
                diffs += [f'      moto:     {x}' for x in only_a]
                diffs += [f'      emulator: {x}' for x in only_b]
        print(f'## run "{run}": ' + ('identical after normalising' if not diffs else f'{sum(1 for d in diffs if not d.startswith("      "))} resource(s) differ'))
        print('\n'.join(diffs))


if __name__ == '__main__':
    main()
