"""In-process inferred suggestion API; never fabricate a committed Snapshot."""
import ctypes
import json
import preferences
from pathlib import Path
class Rules:
    def __init__(self):
        local=Path(__file__).resolve().parent.parent/'libtypetune_bridge.so'
        self.lib=ctypes.CDLL(str(local if local.exists() else Path(__file__).resolve().parents[2]/'target/debug/libtypetune_bridge.so'))
        self.lib.typetune_bridge_new.restype=ctypes.c_void_p
        self.lib.typetune_bridge_free.argtypes=[ctypes.c_void_p]
        self.lib.typetune_bridge_call.argtypes=[ctypes.c_void_p,ctypes.c_char_p,ctypes.c_size_t,ctypes.c_void_p]
        self.lib.typetune_bridge_call.restype=ctypes.c_size_t
        self.handle=self.lib.typetune_bridge_new()
        self.generation=None
        self.settings_generation=None
    def call(self, value):
        request=json.dumps(value,ensure_ascii=False).encode()
        output=ctypes.create_string_buffer(32768)
        size=self.lib.typetune_bridge_call(self.handle,request,len(request),output)
        return json.loads(output.raw[:size]) if size else {'status':'ignored'}

    def suggest(self,text,automatic):
        if automatic and preferences.ERROR: return {'status':'ignored'}
        try:
            import app_settings
            settings=app_settings.load()
        except Exception:
            settings={}
        settings_generation=settings.get('generation')
        if (self.generation != preferences.CURRENT['generation']
                or self.settings_generation != settings_generation):
            result=self.call(dict(op='configure',words=preferences.CURRENT['words'],exclusions=preferences.CURRENT['exclusions'],
                # Linux learned words live in words.json (`words`); bridge `learned` stays empty.
                learned=[],policy=self.policy(settings)))
            if result['status']!='configured': return {'status':'ignored'}
            self.generation=preferences.CURRENT['generation']
            self.settings_generation=settings_generation
        return self.call(dict(op='infer',text=text,automatic=automatic))

    @staticmethod
    def policy(settings=None):
        if settings is None:
            try:
                import app_settings
                settings=app_settings.load()
            except Exception:
                settings={}
        return dict(
            switch_only_last_word=settings.get('switch_only_last_word',True),
            dont_switch_words=settings.get('dont_switch_words',False),
            dont_correct_after_layout_change=settings.get('dont_correct_after_layout_change',True),
        )
