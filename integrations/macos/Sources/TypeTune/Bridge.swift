import Foundation
import CTypeTune

final class Engine {
    private let handle = typetune_bridge_new()!
    deinit { typetune_bridge_free(handle) }
    // Called exclusively by the runtime's serial worker.
    func call(_ request: [String: Any]) -> [String: Any] {
        guard let data = try? JSONSerialization.data(withJSONObject: request), data.count <= 131072 else { return ["status":"protocol_error"] }
        var output = [UInt8](repeating: 0, count: 32768)
        let length = data.withUnsafeBytes { bytes in
            typetune_bridge_call(handle, bytes.bindMemory(to: UInt8.self).baseAddress!, data.count, &output)
        }
        guard length > 0, length <= output.count,
              let value = try? JSONSerialization.jsonObject(with: Data(output.prefix(length))) as? [String:Any] else { return ["status":"protocol_error"] }
        return value
    }
}
