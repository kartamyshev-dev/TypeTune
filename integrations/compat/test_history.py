import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'ibus'))
import unittest
from history import History,key_plan,CODES,US,RU,UPPER_US
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
        self.tap(58);self.assertEqual(self.h.text,'')
    def test_executor_plan_text_caret_and_balanced_keys(self):
        text='prefix ghbdtn ';caret=len(text);held=set()
        plan=key_plan(7,'Привет ','ru')
        for code,down in plan:
            if not down:held.remove(code);continue
            held.add(code)
            if code==42:continue
            if code==14:text=text[:caret-1]+text[caret:];caret-=1;continue
            c=' ' if code==57 else (RU.upper() if 42 in held else RU)[CODES.index(code)]
            text=text[:caret]+c+text[caret:];caret+=1
        self.assertEqual((text,caret,held),('prefix Привет ',14,set()))
        self.assertIsNone(key_plan(6,'привет😀','ru'))
        self.assertIsNone(key_plan(129,'a','us'))
        self.assertEqual(len(CODES),len(US));self.assertEqual(len(RU),len(UPPER_US))
if __name__=='__main__':unittest.main()
