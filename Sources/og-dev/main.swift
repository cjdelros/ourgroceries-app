import Foundation
import GroceriesCore

@main
struct OGDev {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first, ["overview", "inspect-list", "add"].contains(command) else {
            write(ok: false, data: nil, error: "usage: og-dev overview | inspect-list --list-id ID | add --list-id ID --text TEXT --confirm-write")
            exit(2)
        }
        // Live mode is intentionally not implemented until a designated test-account
        // credential source and observed wire fixtures are approved. This target is a
        // development harness, never part of the distributed application.
        write(ok: false, data: nil, error: "fixture transport must be supplied by the development test harness")
        exit(2)
    }

    static func write(ok: Bool, data: Any?, error: String?) {
        var envelope: [String: Any] = ["schemaVersion": 1, "ok": ok]
        if let data { envelope["data"] = data }
        if let error { envelope["error"] = ["code": error] }
        let json = try! JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
        print(String(decoding: json, as: UTF8.self))
    }
}
