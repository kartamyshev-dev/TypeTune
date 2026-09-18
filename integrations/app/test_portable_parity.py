"""The same traces are consumed by the Rust macOS runtime."""
import json
from pathlib import Path
import unittest
from gesture import DoubleShift
from correction_feedback import Feedback, Tracker

class Parity(unittest.TestCase):
    def test_shared_gesture_traces(self):
        cases=json.loads((Path(__file__).resolve().parents[2]/'tests/parity/gesture.json').read_text())
        for case in cases:
            with self.subTest(case=case['name']):
                gesture=DoubleShift()
                results=[gesture.edge(key,up,stamp/1000) for key,up,stamp in case['events']]
                self.assertEqual(any(results),case['fires'])
    def test_shared_feedback_traces(self):
        cases=json.loads((Path(__file__).resolve().parents[2]/'tests/parity/feedback.json').read_text())
        for case in cases:
            with self.subTest(case=case['name']):
                feedback=Feedback();tracker=Tracker(feedback,lambda:0)
                for _ in range(case['cycles']):
                    for step in case['trace']:
                        if step.get('action')=='reset':tracker.reset()
                        elif step.get('action')=='advance':tracker.advance(step['boundary'])
                        else:tracker.completed(step['kind'],step['before'],step['after'],step.get('learn',False))
                self.assertEqual([[p['kind'],p['word']] for p in feedback.pending()],case['expected'])
