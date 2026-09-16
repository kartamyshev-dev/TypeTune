"""Two complete taps of one Shift. Times are injected monotonic arrival times."""
class DoubleShift:
    def __init__(self):
        self.reset()

    def reset(self):
        self.down = None
        self.first = None

    def edge(self, key, release, now):
        if not release:
            if self.down is not None:  # repeat/overlap is never a second tap
                self.reset()
                return False
            if self.first and (self.first[0] != key or not 0 <= now - self.first[1] <= .350):
                self.first = None
            self.down = (key, now)
            return False
        if self.down is None or self.down[0] != key:
            self.reset()
            return False
        started = self.down[1]
        self.down = None
        if not 0 <= now - started <= .200:
            self.reset()
            return False
        if self.first is not None and self.first[0] == key and 0 <= now - self.first[1] <= .350:
            self.reset()
            return True
        self.first = (key, now)
        return False
