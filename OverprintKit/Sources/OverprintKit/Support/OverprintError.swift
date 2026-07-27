import Foundation

/// Errors surfaced by the engine. `CustomStringConvertible` drives CLI output, and
/// `LocalizedError` lets thrown errors print cleanly from ArgumentParser.
public enum OverprintError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case configNotFound(URL)
    case invalidConfig(String)
    case postValidation(file: String, issues: [String])
    case templateError(String)
    case io(String)

    public var description: String {
        switch self {
        case .configNotFound(let url):
            return "No overprint.yml found at \(url.path)."
        case .invalidConfig(let reason):
            return "Invalid overprint.yml: \(reason)"
        case .postValidation(let file, let issues):
            return "\(file): \(issues.joined(separator: "; "))"
        case .templateError(let reason):
            return "Template error: \(reason)"
        case .io(let reason):
            return "File error: \(reason)"
        }
    }

    public var errorDescription: String? { description }
}
