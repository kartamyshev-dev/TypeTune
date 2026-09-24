"""Optional short click on confirmed layout switch. Never on the input hot path."""
import shutil
import subprocess
from pathlib import Path

_CANDIDATES = ('paplay', 'pw-play', 'canberra-gtk-play')
_SOUND = Path(__file__).resolve().parent / 'layout-switch.ogg'


def play_if_allowed(allowed=True):
    """Best-effort, non-blocking. Silent when no player or no sample is present."""
    if not allowed:
        return
    player = next((name for name in _CANDIDATES if shutil.which(name)), None)
    if player is None:
        return
    sample = _SOUND if _SOUND.is_file() else None
    if sample is None:
        return
    try:
        subprocess.Popen([player, str(sample)],
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError:
        pass
