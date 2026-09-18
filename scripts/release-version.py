#!/usr/bin/python3
"""Strict mapping from a release tag to a Debian version (also used by CI)."""
import os,re

def version(ref,tag):
    if ref.startswith('refs/tags/'):
        match=re.fullmatch(r'v(\d+\.\d+\.\d+)-preview(\d+)-(\d+)',tag)
        if not match:raise ValueError('Expected tag vMAJOR.MINOR.PATCH-previewN-REVISION')
        base,preview,revision=match.groups()
        return f'{base}~preview{preview}-{revision}'
    return '0.1.0~preview55-2'

if __name__=='__main__':
    print('DEB_VERSION='+version(os.environ.get('REF',''),os.environ.get('TAG','')))
