import AppKit
import SwiftUI

/// Support links create editable drafts in the user's mail app. Hearth does not
/// send messages or attach logs, account details, or device information.
struct HelpAndSupport: View {
    let back: () -> Void
    @State private var includeVersions = false
    @State private var mailUnavailable = false
    @State private var copied = false
    @Environment(\.hearthDocumentationPreview) private var documentationPreview

    private static let address = "contact@elvisobi.com"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SubpageHeader(eyebrow: "Settings", title: "Help & Support", back: back) { EmptyView() }

            Bezel(radius: 20, inset: 3) {
                HStack(spacing: 12) {
                    supportMark("envelope", size: 42)
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
                .padding(16)
            }

            HStack(alignment: .top, spacing: 10) {
                emailAction("Get help", detail: "Setup questions or help using Hearth", symbol: "lifepreserver", kind: .support)
                emailAction("Report a bug", detail: "Something didn’t work as expected", symbol: "ladybug", kind: .bug)
            }

            if mailUnavailable {
                Bezel(radius: 18, inset: 3) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.circle").font(.system(size: 16)).foregroundStyle(Theme.live)
                        Text("Couldn’t open your mail app. Copy the address above to use your preferred email service.")
                            .font(.system(size: 12)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                }
                .accessibilityLabel("Could not open your mail app. Copy the support email address to use another email service.")
            }

            Bezel(radius: 18, inset: 3) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Before you send", systemImage: "square.and.pencil")
                            .font(.system(size: 12.5, weight: .semibold))
                        Text("Both buttons open an editable draft in your mail app. You choose when to send it.")
                            .font(.system(size: 12)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Rectangle().fill(Theme.hairline).frame(height: 0.5)
                    if documentationPreview {
                        HStack {
                            Text("Include app and macOS versions").font(.system(size: 12.5, weight: .medium))
                            Spacer()
                            Capsule().fill(Theme.fg.opacity(0.18)).frame(width: 26, height: 16)
                                .overlay(alignment: .leading) { Circle().fill(Theme.ink.opacity(0.65)).frame(width: 12, height: 12).padding(2) }
                        }
                    } else {
                        Toggle("Include app and macOS versions", isOn: $includeVersions)
                            .font(.system(size: 12.5, weight: .medium)).toggleStyle(.switch).controlSize(.small)
                            .tint(Theme.sand)
                    }
                    Text("Version numbers are optional. No logs, account details or device information are attached.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("QUICK CHECKS").eyebrow().padding(.horizontal, 4).padding(.bottom, 2)
                troubleshooting("network", title: "Check the connection", detail: "In Hearth Settings, confirm Home Assistant is connected.")
                troubleshooting("switch.2", title: "Check the device", detail: "Try the same control in Home Assistant. If the device is unavailable there, reconnect it there first.")
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("A HELPFUL BUG REPORT").eyebrow()
                    Text("Three details make it easier to help.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 4).padding(.bottom, 2)
                guidance("1", title: "What you tried", detail: "The steps that led to the problem")
                guidance("2", title: "What you expected", detail: "What you thought would happen")
                guidance("3", title: "What happened", detail: "What appeared on screen or stopped working")
                Text("A screenshot or recording can help explain a visual issue.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.faint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4).padding(.top, 4)
            }
        }
    }

    private func emailAction(_ title: String, detail: String, symbol: String, kind: RequestKind) -> some View {
        Button { compose(kind) } label: {
            Bezel(radius: 18, inset: 3) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        supportMark(symbol, size: 34)
                        Spacer(minLength: 6)
                        Image(systemName: "arrow.up.right").font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Theme.muted).frame(width: 24, height: 24)
                            .background(Circle().fill(Theme.fg.opacity(0.045)))
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).font(.system(size: 13, weight: .semibold))
                        Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: 32, alignment: .topLeading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(title), opens an email draft")
    }

    private func guidance(_ number: String, title: String, detail: String) -> some View {
        Bezel(radius: 18, inset: 3) {
            HStack(alignment: .top, spacing: 12) {
                Text(number).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.sand)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.sand.opacity(0.1)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 12.5, weight: .semibold))
                    Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
        }
        .accessibilityElement(children: .combine)
    }

    private func supportMark(_ symbol: String, size: CGFloat) -> some View {
        Image(systemName: symbol).font(.system(size: size * 0.47, weight: .light))
            .foregroundStyle(Theme.sand).frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous).fill(Theme.sand.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous).strokeBorder(Theme.sand.opacity(0.12), lineWidth: 0.5))
            .accessibilityHidden(true)
    }

    private func troubleshooting(_ symbol: String, title: String, detail: String) -> some View {
        Bezel(radius: 18, inset: 3) {
            HStack(alignment: .top, spacing: 12) {
                supportMark(symbol, size: 28)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 12.5, weight: .semibold))
                    Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
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
