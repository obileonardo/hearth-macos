import AppKit
import SwiftUI

/// Support links create editable drafts in the user's mail app. Hearth does not
/// send messages or attach logs, account details, or device information.
struct HelpAndSupport: View {
    let back: () -> Void
    @State private var includeVersions = false
    @State private var mailUnavailable = false
    @State private var copied = false

    private static let address = "contact@elvisobi.com"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SubpageHeader(eyebrow: "Settings", title: "Help & Support", back: back) { EmptyView() }

            Bezel(radius: 20, inset: 3) {
                HStack(spacing: 12) {
                    Image(systemName: "envelope").font(.system(size: 20, weight: .light))
                        .foregroundStyle(Theme.sand).frame(width: 42, height: 42)
                        .background(Circle().fill(Theme.sand.opacity(0.1)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Here to help").font(.system(size: 16, weight: .semibold))
                        Button(Self.address) { compose(.support) }
                            .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.muted)
                            .buttonStyle(PressStyle()).help("Open a support email")
                    }
                    Spacer(minLength: 8)
                    Button(action: copyAddress) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Theme.fg.opacity(0.06)))
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel(copied ? "Email address copied" : "Copy support email address")
                    .help(copied ? "Copied" : "Copy email address")
                }
                .padding(14)
            }

            VStack(spacing: 10) {
                emailAction("Get help", detail: "Questions about setup or using Hearth", symbol: "bubble.left", kind: .support)
                emailAction("Report a bug", detail: "Tell us what didn’t work as expected", symbol: "ladybug", kind: .bug)
            }

            Text("Your mail app opens with a draft you can edit before sending.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)

            if mailUnavailable {
                Text("Couldn’t open your mail app. Copy the email address above and contact us from your preferred email service.")
                    .font(.system(size: 12)).foregroundStyle(Theme.live)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
                    .accessibilityLabel("Could not open your mail app. Copy the support email address to use another email service.")
            }

            Bezel(radius: 18, inset: 3) {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Include app and macOS versions", isOn: $includeVersions)
                        .font(.system(size: 13, weight: .medium)).toggleStyle(.switch).controlSize(.small)
                    Text("Optional version numbers help us understand your setup.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("A HELPFUL BUG REPORT").eyebrow().padding(.leading, 4)
                Bezel(radius: 18, inset: 3) {
                    VStack(alignment: .leading, spacing: 12) {
                        guidance("1", title: "What you tried", detail: "The steps that led to the problem")
                        guidance("2", title: "What you expected", detail: "What you thought would happen")
                        guidance("3", title: "What happened", detail: "What appeared on screen or stopped working")
                    }
                    .padding(14)
                }
                Text("A screenshot or recording can help explain a visual issue.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
            }
        }
    }

    private func emailAction(_ title: String, detail: String, symbol: String, kind: RequestKind) -> some View {
        Button { compose(kind) } label: {
            Bezel(radius: 18, inset: 3) {
                HStack(spacing: 11) {
                    Image(systemName: symbol).font(.system(size: 16, weight: .light))
                        .foregroundStyle(Theme.muted).frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.system(size: 13, weight: .semibold))
                        Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.muted).frame(width: 28, height: 28)
                        .background(Circle().fill(Theme.fg.opacity(0.06)))
                }
                .padding(12)
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(title), opens an email draft")
    }

    private func guidance(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                .frame(width: 22, height: 22).background(Circle().fill(Theme.fg.opacity(0.06)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private enum RequestKind {
        case support, bug
        var subject: String { self == .bug ? "Hearth — Bug report" : "Hearth — Support request" }
        var template: String {
            switch self {
            case .support:
                "Hi Elvis,\n\nI’d like help with:\n\nWhat I’ve tried so far:\n\n"
            case .bug:
                "Hi Elvis,\n\nSteps to reproduce:\n1. \n2. \n3. \n\nExpected result:\n\nActual result:\n\nHow often it happens:\n\n"
            }
        }
    }

    private func compose(_ kind: RequestKind) {
        var body = kind.template
        if includeVersions {
            let info = Bundle.main.infoDictionary ?? [:]
            let version = info["CFBundleShortVersionString"] as? String ?? "Unknown"
            let build = info["CFBundleVersion"] as? String
            let system = ProcessInfo.processInfo.operatingSystemVersion
            body += "Hearth version: \(version)\(build.map { " (\($0))" } ?? "")\n"
            body += "macOS version: \(system.majorVersion).\(system.minorVersion).\(system.patchVersion)\n"
        }
        // RFC 3986 unreserved characters keep &, +, # and line breaks safely
        // inside their subject/body values rather than changing the mailto URL.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let subject = kind.subject.addingPercentEncoding(withAllowedCharacters: allowed),
              let message = body.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "mailto:\(Self.address)?subject=\(subject)&body=\(message)") else {
            mailUnavailable = true
            return
        }
        mailUnavailable = !NSWorkspace.shared.open(url)
    }

    private func copyAddress() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.address, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }
}
