import LayoutPilotCore

func doubleCapitalChecks() -> [(Bool, String)] {
    var checks: [(Bool, String)] = []
    func check(_ result: Bool, _ name: String) { checks.append((result, "double capital: " + name)) }
    let engine = Engine()
    for word in ["IDs", "PCs", "TVs", "VMs", "OKs", "GHz", "KHz", "ЦРу"] {
        check(engine.decide(word) == nil, "unknown three-letter acronym form stays: \(word)")
    }
    for (word, expected) in [("DAy", "Day"), ("МИр", "Мир"), ("КОд", "Код"), ("ПРивет", "Привет"), ("HEllo", "Hello")] {
        check(engine.decide(word)?.replacement == expected, "\(word) becomes \(expected)")
    }
    check(engine.decide("VBh")?.replacement == "Мир", "three letters known after layout conversion")
    check(engine.decide("GHbdtn")?.replacement == "Привет", "longer words keep case + layout composition")
    var noTypos = Settings(); noTypos.typos = false
    check(Engine(settings: noTypos).decide("DAy") == nil, "typos off disables the rule")
    for (word, expected) in [("ПРивет", true), ("IDs", true), ("Hello", false), ("HTTP", false), ("ПРивет.", false), ("AB", false)] {
        check(Engine.isDoubleCapitalTypo(word) == expected, "shape predicate: \(word)")
    }
    return checks
}
