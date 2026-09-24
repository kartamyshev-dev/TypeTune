import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'app'))
import unittest
from history import History,key_plan,CODES,US,RU,UPPER_US,RU_PUNCT,US_PUNCT
class Checks(unittest.TestCase):
    def setUp(self):self.h=History();self.t=0
    def edge(self,code,value=1,device=1,mode='us',allowed=True):
        self.t+=.02
        return self.h.event(dict(code=code,value=value,device=device,time=self.t),mode,allowed)
    def tap(self,code,**kwargs):
        result=self.edge(code,**kwargs);return self.edge(code,0,**kwargs) or result
    def test_manual_and_auto(self):
        for code in [34,35,48,32,20,49]:self.tap(code)
        self.assertEqual(self.h.text,'ghbdtn')
        self.assertIsNone(self.tap(42));self.assertEqual(self.tap(42),'manual')
        self.assertEqual(self.tap(57),'auto');self.assertEqual(self.h.text,'ghbdtn ')
        self.tap(30);self.assertEqual(self.h.text,'a')
    def test_navigation_ctrl_loss_and_shift_between_devices(self):
        self.tap(30);self.tap(42);self.assertIsNone(self.tap(42,device=2))
        self.tap(105);self.assertEqual(self.h.text,'')
        self.edge(29);self.tap(30);self.assertEqual(self.h.text,'')
        self.h.reset();self.assertFalse(self.h.held)
        self.tap(30,allowed=False);self.assertEqual(self.h.text,'')
    def test_shift_caps_and_repeat(self):
        self.edge(42);self.tap(30);self.edge(42,0)
        self.assertEqual(self.h.text,'A')
        self.tap(42);self.edge(42);self.assertIsNone(self.edge(42,2));self.assertIsNone(self.edge(42,0))
    def test_caps_lock_latch_keeps_word_and_double_shift(self):
        for code in [34,35,48]:self.tap(code)
        self.assertEqual(self.h.text,'ghb')
        self.tap(58);self.assertEqual(self.h.text,'ghb')
        self.edge(58,0);self.assertEqual(self.h.text,'ghb')
        self.tap(69);self.assertEqual(self.h.text,'ghb')
    def test_modifier_edges_do_not_clear(self):
        for code in [34,35,48]:self.tap(code)
        self.assertEqual(self.h.text,'ghb')
        for mod in (29,97,56,100,125,126):
            self.edge(mod);self.assertEqual(self.h.text,'ghb')
            self.edge(mod,0);self.assertEqual(self.h.text,'ghb')
    def test_shortcut_with_ctrl_clears(self):
        for code in [34,35,48]:self.tap(code)
        self.edge(29)
        self.tap(30)
        self.assertEqual(self.h.text,'')
    def test_mouse_button_codes_ignored(self):
        for code in [34,35,48]:self.tap(code)
        self.assertEqual(self.h.text,'ghb')
        self.edge(272);self.assertEqual(self.h.text,'ghb')
        self.edge(272,0);self.assertEqual(self.h.text,'ghb')
        self.edge(277);self.assertEqual(self.h.text,'ghb')
    def test_rapid_retoggle_not_suppressed(self):
        for code in [34,35,48,32,20,49]:self.tap(code)
        self.assertIsNone(self.tap(42));self.assertEqual(self.tap(42),'manual')
        self.assertIsNone(self.tap(42));self.assertEqual(self.tap(42),'manual')
    def _apply_plan(self,text,caret,plan,mode):
        held=set();letters=(RU,RU.upper()) if mode=='ru' else (US,UPPER_US)
        punct=RU_PUNCT if mode=='ru' else US_PUNCT
        for code,down in plan:
            if not down:held.remove(code);continue
            self.assertNotIn(code,held)
            held.add(code)
            if code==42:continue
            if code==14:text=text[:caret-1]+text[caret:];caret-=1;continue
            if code==57:char=' '
            elif code in CODES:char=(letters[1] if 42 in held else letters[0])[CODES.index(code)]
            else:
                match=[c for c,(pcode,pshift) in punct.items() if pcode==code and pshift==(42 in held)]
                self.assertEqual(len(match),1,f'no punct for code={code} shift={42 in held}')
                char=match[0]
            text=text[:caret]+char+text[caret:];caret+=1
        return text,caret,held
    def test_executor_plan_text_caret_and_balanced_keys(self):
        text='prefix ghbdtn ';caret=len(text)
        plan=key_plan(7,'Привет ','ru')
        text,caret,held=self._apply_plan(text,caret,plan,'ru')
        self.assertEqual((text,caret,held),('prefix Привет ',14,set()))
        self.assertIsNone(key_plan(6,'привет😀','ru'))
        self.assertIsNone(key_plan(129,'a','us'))
        self.assertEqual(len(CODES),len(US));self.assertEqual(len(RU),len(UPPER_US))

    def test_edge_punctuation_replacement_plan(self):
        for source,replacement in [
            ('ghbdtn, ','привет, '),
            ('ghbdtn. ','привет. '),
            ('ghbdtn... ','привет... '),
        ]:
            plan=key_plan(len(source),replacement,'ru')
            self.assertIsNotNone(plan,source)
            text,caret,held=self._apply_plan(source,len(source),plan,'ru')
            self.assertEqual((text,caret,held),(replacement,len(replacement),set()),source)

    def test_two_letter_punctuation_history_and_balanced_replacement(self):
        self.tap(51); self.tap(31)
        self.assertEqual(self.tap(57), 'auto')
        self.assertEqual(self.h.text, ',s ')
        self.assertFalse(self.h.held)
        text = 'prefix ,s suffix'; caret = len('prefix ,s ')
        text,caret,held=self._apply_plan(text,caret,key_plan(3, 'бы ', 'ru'),'ru')
        self.assertEqual((text, caret, held), ('prefix бы suffix', len('prefix бы '), set()))

if __name__=='__main__':unittest.main()
