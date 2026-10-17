import Foundation
import Darwin

final class SingleInstance {
    private let descriptor: Int32
    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let failure = errno
            close(fd)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure))
        }
        descriptor = fd
    }
    // Keep the file: unlinking would allow another process to lock a different inode.
    deinit { close(descriptor) }
}
