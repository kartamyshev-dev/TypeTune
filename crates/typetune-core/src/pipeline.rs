use crate::event::InputEvent;

pub trait PipelineStage: Send {
    fn name(&self) -> &str;
    fn process(&mut self, event: InputEvent) -> Vec<InputEvent>;
    fn reset(&mut self) {}
}

pub struct Pipeline {
    stages: Vec<Box<dyn PipelineStage>>,
}

impl Pipeline {
    pub fn new() -> Self {
        Self { stages: Vec::new() }
    }

    pub fn add_stage(&mut self, stage: Box<dyn PipelineStage>) {
        tracing::info!("Pipeline: added stage '{}'", stage.name());
        self.stages.push(stage);
    }

    pub fn process(&mut self, event: InputEvent) -> Vec<InputEvent> {
        let mut events = vec![event];
        for stage in &mut self.stages {
            let mut next = Vec::new();
            for e in events.drain(..) {
                next.extend(stage.process(e));
            }
            events = next;
        }
        events
    }

    pub fn reset(&mut self) {
        for stage in &mut self.stages {
            stage.reset();
        }
    }

    pub fn stage_names(&self) -> Vec<&str> {
        self.stages.iter().map(|s| s.name()).collect()
    }
}

impl Default for Pipeline {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::event::KeyState;

    struct PassThrough {
        name: &'static str,
    }

    impl PipelineStage for PassThrough {
        fn name(&self) -> &str {
            self.name
        }

        fn process(&mut self, event: InputEvent) -> Vec<InputEvent> {
            vec![event]
        }
    }

    struct Doubler;

    impl PipelineStage for Doubler {
        fn name(&self) -> &str {
            "doubler"
        }

        fn process(&mut self, event: InputEvent) -> Vec<InputEvent> {
            vec![event.clone(), event]
        }
    }

    #[test]
    fn empty_pipeline_passthrough() {
        let mut pipeline = Pipeline::new();
        let ev = InputEvent::new(30, KeyState::Pressed);
        let result = pipeline.process(ev);
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].keycode, 30);
    }

    #[test]
    fn pipeline_chains_stages() {
        let mut pipeline = Pipeline::new();
        pipeline.add_stage(Box::new(PassThrough { name: "a" }));
        pipeline.add_stage(Box::new(PassThrough { name: "b" }));
        let ev = InputEvent::new(30, KeyState::Pressed);
        let result = pipeline.process(ev);
        assert_eq!(result.len(), 1);
    }

    #[test]
    fn pipeline_doubler() {
        let mut pipeline = Pipeline::new();
        pipeline.add_stage(Box::new(Doubler));
        let ev = InputEvent::new(30, KeyState::Pressed);
        let result = pipeline.process(ev);
        assert_eq!(result.len(), 2);
    }

    #[test]
    fn pipeline_stage_names() {
        let mut pipeline = Pipeline::new();
        pipeline.add_stage(Box::new(PassThrough { name: "first" }));
        pipeline.add_stage(Box::new(PassThrough { name: "second" }));
        assert_eq!(pipeline.stage_names(), vec!["first", "second"]);
    }

    #[test]
    fn pipeline_reset_calls_stages() {
        struct Resettable {
            reset_count: std::sync::Arc<std::sync::atomic::AtomicU32>,
        }

        impl PipelineStage for Resettable {
            fn name(&self) -> &str {
                "resettable"
            }

            fn process(&mut self, event: InputEvent) -> Vec<InputEvent> {
                vec![event]
            }

            fn reset(&mut self) {
                self.reset_count
                    .fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            }
        }

        let count = std::sync::Arc::new(std::sync::atomic::AtomicU32::new(0));
        let mut pipeline = Pipeline::new();
        pipeline.add_stage(Box::new(Resettable {
            reset_count: count.clone(),
        }));

        pipeline.reset();
        assert_eq!(count.load(std::sync::atomic::Ordering::SeqCst), 1);
    }
}
