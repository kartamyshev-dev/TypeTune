#!/usr/bin/python3
"""Strict mapping from a release tag to a Debian version (also used by CI)."""
import os
import re


def version(ref, tag):
    if ref.startswith('refs/tags/'):
        match = re.fullmatch(r'v(\d+\.\d+\.\d+)', tag)
        if not match:
            raise ValueError('Expected tag vMAJOR.MINOR.PATCH')
        return match.group(1)
    return '0.1.0'


if __name__ == '__main__':
    print('DEB_VERSION=' + version(os.environ.get('REF', ''), os.environ.get('TAG', '')))
