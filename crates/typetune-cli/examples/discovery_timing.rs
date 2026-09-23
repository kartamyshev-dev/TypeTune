fn main() {
    for _ in 0..5 {
        let start = std::time::Instant::now();
        let keyboards = typetune_input::device_discovery::discover_keyboards(&[]);
        println!(
            "discovery_ms={} keyboards={}",
            start.elapsed().as_millis(),
            keyboards.len()
        );
    }
}
