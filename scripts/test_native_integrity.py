#!/usr/bin/env python3
"""Offline exact corpus integrity fixtures; no apps/events or original assets."""
import json
import pathlib
import tempfile
from native_integrity import load_corpus_oracle, unknown_corpus_rows, correction_failures


def main():
    checks = 0
    def rejected(action):
        nonlocal checks
        try: action()
        except ValueError: checks += 1
        else: raise AssertionError('Unsafe fixture accepted')
    with tempfile.TemporaryDirectory() as folder:
        native = pathlib.Path(folder)/'native.json'
        synthetic = pathlib.Path(folder)/'synthetic.jsonl'
        rows = [{'id':'a','expected':'привет hello '}, {'id':'b','expected':'world '}]
        source = [{'id':'a','input':'ghbdtn hello','expected':'привет hello'},
                  {'id':'b','input':'world','expected':'world'}]
        native.write_text(json.dumps(rows))
        synthetic.write_text('\n'.join(json.dumps(row) for row in source)+'\n')
        oracle, identity = load_corpus_oracle(native, synthetic)
        assert correction_failures([{'id':'a','text':'привет hello '},{'id':'b','text':'world '}], rows) == []; checks += 1
        assert correction_failures([{'id':'a','text':'ghbdtn hello '},{'id':'b','text':'world '}], rows) == ['a']; checks += 1
        selected = [dict(rows[0], expectedSource='ABC', expectedSelection={'location':13,'length':0})]
        exact = {'id':'a','text':'привет hello ','inputSource':'ABC','selection':{'location':13,'length':0}}
        assert correction_failures([exact], selected) == []; checks += 1
        for mutation in [dict(inputSource='Russian'), dict(selection={'location':0,'length':0}), dict(text='')]:
            assert correction_failures([dict(exact, **mutation)], selected) == ['a']; checks += 1
        rejected(lambda: correction_failures([], selected))
        rejected(lambda: correction_failures([exact,exact], selected))
        rejected(lambda: correction_failures([exact], selected+selected))
        rejected(lambda: correction_failures([dict(exact,id='unknown')], selected))
        rejected(lambda: correction_failures([exact], [{'id':'a'}]))
        def unknown(text):
            return unknown_corpus_rows([{'id':'a','text':text}], oracle, ['a'])
        for text in ['ghbdtn hello ', 'привет hello ']:
            assert unknown(text) == []; checks += 1
        for text in ['', 'привет hello привет hello ', 'hello привет ', 'вприет hello ', 'привет hello']:
            assert unknown(text) == ['a']; checks += 1
        rejected(lambda: unknown_corpus_rows([{'id':'a','text':'привет hello '}]*2,oracle,['a']))
        rejected(lambda: unknown_corpus_rows([],oracle,['a']))
        rejected(lambda: unknown_corpus_rows([{'id':'other','text':'world '}],oracle,['other']))
        # Row order is irrelevant; order WITHIN text is tested above.
        assert unknown_corpus_rows([{'id':'b','text':'world '},{'id':'a','text':'ghbdtn hello '}],oracle,['a','b']) == []
        checks += 1
        synthetic.write_text('\n'.join(json.dumps(row) for row in source)+'\n\n')
        rejected(lambda: load_corpus_oracle(native,synthetic))
        synthetic.write_text('\n'.join(json.dumps(row) for row in source)+'\n')
        source[0]['input']='different'
        synthetic.write_text('\n'.join(json.dumps(row) for row in source)+'\n')
        assert load_corpus_oracle(native,synthetic)[1] != identity; checks += 1
        source[0]['expected']='different'
        synthetic.write_text('\n'.join(json.dumps(row) for row in source)+'\n')
        rejected(lambda: load_corpus_oracle(native,synthetic))
        source[0]['expected']='привет hello'
        synthetic.write_text('\n'.join(json.dumps(row) for row in source+[source[0]])+'\n')
        rejected(lambda: load_corpus_oracle(native,synthetic))
    print(f'{checks} offline corpus integrity checks PASS; no native/quality acceptance')


if __name__ == '__main__': main()
