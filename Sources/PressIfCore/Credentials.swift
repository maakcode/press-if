import Foundation

public enum Credentials {
    public static func load(environment: [String: String] = ProcessInfo.processInfo.environment, envFile: URL? = nil) -> String? {
        for name in ["MODEL_API_KEY", "META_API_KEY"] {
            if let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return value }
        }
        guard let envFile, let contents = try? String(contentsOf: envFile, encoding: .utf8) else { return nil }
        let values = parseEnv(contents)
        for name in ["MODEL_API_KEY", "META_API_KEY"] {
            if let value = values[name], !value.isEmpty { return value }
        }
        return nil
    }

    public static func parseEnv(_ contents: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in contents.components(separatedBy: .newlines) {
            var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("export ") { trimmed = String(trimmed.dropFirst(7)) }
            guard !trimmed.hasPrefix("#"), let separator = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
            var value = trimmed[trimmed.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first {
                value = String(value.dropFirst().dropLast())
            }
            values[key] = value
        }
        return values
    }
}
