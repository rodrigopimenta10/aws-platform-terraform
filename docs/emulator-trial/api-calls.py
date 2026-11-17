#!/usr/bin/env python3
"""Lists the AWS API operations Terraform called in a run, with the HTTP status codes it got back.

Input: Terraform debug logs written by `TF_DEBUG=1 run.sh ...` (<module>.tf-debug.log).
Output: one line per service and operation with the count per status code, then the operations that
ever answered 501 (not implemented) or another 5xx.

Usage: api-calls.py <tf-debug.log>...
"""
import collections
import re
import sys

calls = collections.defaultdict(collections.Counter)
STAMP = re.compile(r'^\d{4}-\d\d-\d\dT')


def record(text):
    """One log record (its first line plus any continuation lines) of a response the provider received."""
    op = re.search(r'rpc\.method="?([A-Za-z0-9 ]+)/([A-Za-z0-9]+)', text)
    code = re.search(r'http\.(?:response\.)?status_code=(\d+)', text)
    if op and code:
        calls[(op.group(1), op.group(2))][code.group(1)] += 1


for path in sys.argv[1:]:
    current = None
    for line in open(path, encoding='utf-8', errors='replace'):
        if STAMP.match(line):
            if current is not None:
                record(current)
            current = line if 'HTTP Response Received' in line else None
        elif current is not None:
            current += line
    if current is not None:
        record(current)

total = sum(sum(c.values()) for c in calls.values())
print(f'{len(calls)} distinct operations, {total} calls')
for (svc, op), codes in sorted(calls.items()):
    print(f'{svc}\t{op}\t' + ' '.join(f'{k}x{v}' for k, v in sorted(codes.items())))
bad = {k: c for k, c in calls.items() if any(code.startswith('5') for code in c)}
print(f'\noperations with a 5xx answer: {len(bad)}')
for (svc, op), codes in sorted(bad.items()):
    print(f'  {svc} {op}: ' + ' '.join(f'{k}x{v}' for k, v in sorted(codes.items())))
