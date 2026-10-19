import AppKit
import IOKit

/// Which application holds Secure Input. macOS does not report it directly; the console user's
/// session in the I/O registry carries `kCGSSessionSecureInputPID` (the approach espanso uses,
/// docs/ESPANSO_RESEARCH.md п. 3). Not always exact: the PID may be a helper process.
enum SecureInputOwner {
    static func application() -> NSRunningApplication? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        guard let property = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0),
              let users = property.takeRetainedValue() as? [[String: Any]] else { return nil }
        for user in users {
            if let pid = (user["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value, pid > 0 {
                return NSRunningApplication(processIdentifier: pid)
            }
        }
        return nil
    }
}
