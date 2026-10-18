import AppKit

struct ProbeFailure: Error { let message: String }
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw ProbeFailure(message: message) }
}

@main struct ClipboardLeaseProbe {
    static func main() throws {
        let board = NSPasteboard.general
        let nonce = UUID().uuidString
        let outer = try ClipboardLease(synthetic: nonce, referenceContext: {})
        defer { _ = outer.restore() }
        var contextValid = true
        let modal = try ClipboardLease(synthetic: "modal-test", referenceContext: {
            try require(contextValid, "simulated_modal")
        })
        contextValid = false
        try require(modal.restore() == "restored_all_representations", "modal_restore_failed")
        try require(outer.syntheticUnchanged(), "modal_baseline_changed")

        let newer = try ClipboardLease(synthetic: "owned-test")
        board.clearContents(); try require(board.writeObjects(["newer-test" as NSString]), "write_failed")
        try require(newer.restore() == "skipped_newer_clipboard", "newer_owner_overwritten")
        try require(board.string(forType: .string) == "newer-test", "newer_data_changed")

        // Restore our nonce before the outer lease restores the user's complete snapshot.
        board.clearContents(); try require(board.writeObjects([nonce as NSString]), "nonce_write_failed")
        try require(outer.restore() == "restored_all_representations", "outer_restore_failed")
        print("{\"passed\":true,\"modalRestore\":true,\"newerOwnerPreserved\":true,\"originalClipboardRestored\":true,\"events\":0}")
    }
}
