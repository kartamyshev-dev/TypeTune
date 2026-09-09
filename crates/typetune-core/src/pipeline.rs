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
}

impl Default for Pipeline {
    fn default() -> Self {
        Self::new()
    }
}
