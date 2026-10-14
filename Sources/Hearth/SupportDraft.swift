import Foundation

/// An editable local draft. Creating or copying one never sends a message.
struct SupportDraft: Equatable {
    enum Kind: Hashable {
        case support, bug
        var title: String { self == .bug ? "Report a bug" : "Get help" }
        var subject: String { self == .bug ? "Hearth — Bug report" : "Hearth — Support request" }
        var template: String {
            switch self {
            case .support: "Hi Elvis,\n\nI’d like help with:\n\nWhat I’ve tried so far:\n\n"
            case .bug: "Hi Elvis,\n\nSteps to reproduce:\n1. \n2. \n3. \n\nExpected result:\n\nActual result:\n\nHow often it happens:\n\n"
            }
        }
    }
    static let address = "contact@elvisobi.com"
    var subject: String
    var body: String

    init(kind: Kind, versions: String? = nil) {
        subject = kind.subject
        body = kind.template + (versions ?? "")
    }

    /// Derive outgoing diagnostic text without modifying the editable message.
    func includingVersions(_ versions: String?) -> SupportDraft {
        var outgoing = self
        if let versions { outgoing.body += "\n" + versions }
        return outgoing
    }

    var clipboardText: String { "To: \(Self.address)\nSubject: \(subject)\n\n\(body)" }
    var mailtoURL: URL? {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: allowed),
              let encodedBody = body.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "mailto:\(Self.address)?subject=\(encodedSubject)&body=\(encodedBody)")
    }
}
