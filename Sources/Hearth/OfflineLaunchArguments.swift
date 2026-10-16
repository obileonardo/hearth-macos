import Foundation

/// Pure validation runs before saved-session store initialization. Review modes
/// take no destination; the three offline exporters each require a real path.
enum OfflineLaunchArguments {
    enum Invalid: LocalizedError, Equatable {
        case missingDestination(String)
        var errorDescription: String? {
            switch self {
            case .missingDestination(let flag):
                return "\(flag) requires an output path. No home connection was started."
            }
        }
    }

    private static let exporters: Set<String> = ["--render-preview", "--render-cars", "--render-art"]

    static func validate(_ arguments: [String]) throws {
        for index in arguments.indices where exporters.contains(arguments[index]) {
            guard index + 1 < arguments.count else { throw Invalid.missingDestination(arguments[index]) }
            let path = arguments[index + 1]
            guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !path.hasPrefix("-") else { throw Invalid.missingDestination(arguments[index]) }
        }
    }
}
