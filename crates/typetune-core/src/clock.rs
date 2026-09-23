use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

pub trait Clock: Send {
    fn now(&self) -> Instant;
    fn advance(&self, duration: Duration);
}

#[derive(Clone)]
pub struct SystemClock;

impl Clock for SystemClock {
    fn now(&self) -> Instant {
        Instant::now()
    }

    fn advance(&self, _duration: Duration) {}
}

#[derive(Clone)]
pub struct FakeClock {
    time: Arc<Mutex<Instant>>,
}

impl FakeClock {
    pub fn new(start: Instant) -> Self {
        Self {
            time: Arc::new(Mutex::new(start)),
        }
    }

    pub fn at_zero() -> Self {
        Self::new(Instant::now())
    }
}

impl Clock for FakeClock {
    fn now(&self) -> Instant {
        *self.time.lock().unwrap()
    }

    fn advance(&self, duration: Duration) {
        let mut t = self.time.lock().unwrap();
        *t += duration;
    }
}
