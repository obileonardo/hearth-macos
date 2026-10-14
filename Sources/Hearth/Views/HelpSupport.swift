import AppKit
import SwiftUI

/// Support actions create an editable local draft with mail and copy options. Hearth does not
/// send messages or attach logs, account details, or device information.
struct HelpAndSupport: View {
    let back: () -> Void
    @State private var includeVersions = false
    @State private var mailUnavailable = false
    @State private var copied = false
    @State private var request: SupportDraft.Kind?
    @State private var draft = SupportDraft(kind: .support)
    @State private var draftCopied = false
    @State private var drafts: [SupportDraft.Kind: SupportDraft] = [:]
    @Environment(\.hearthDocumentationPreview) private var documentationPreview

    private static let address = SupportDraft.address

    init(initialRequest: SupportDraft.Kind? = nil, back: @escaping () -> Void) {
        self.back = back
        _request = State(initialValue: initialRequest)
        _draft = State(initialValue: SupportDraft(kind: initialRequest ?? .support))
    }

    var body: some View {
        ScreenFlow(route: request, depth: request == nil ? 0 : 1) { kind in
            if let kind { draftForm(kind) } else { overview }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 20) {
            SubpageHeader(eyebrow: "Settings", title: "Help & Support", back: back) { EmptyView() }

            Bezel(radius: 20, inset: 3) {
                HStack(spacing: 12) {
                    supportMark("envelope", size: 42)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Here to help").font(.system(size: 16, weight: .semibold))
                        Button(Self.address) { compose(.support) }
                            .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.muted)
                            .buttonStyle(PressStyle()).help("Review a support draft")
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
                        Text("Review a draft here, then open your mail app or copy it.")
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
                        HStack(spacing: 16) {
                            Text("Include app and macOS versions").font(.system(size: 12.5, weight: .medium))
                            Spacer(minLength: 12)
                            Toggle("Include app and macOS versions", isOn: $includeVersions)
                                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                                .tint(Theme.brand).accessibilityLabel("Include app and macOS versions")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    Text("Optional. No logs or account details are attached.")
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

    private func emailAction(_ title: String, detail: String, symbol: String, kind: SupportDraft.Kind) -> some View {
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
        .accessibilityLabel("\(title), review an email draft")
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

    private func compose(_ kind: SupportDraft.Kind) {
        if let request { drafts[request] = draft }
        draft = drafts[kind] ?? SupportDraft(kind: kind)
        mailUnavailable = false
        draftCopied = false
        request = kind
    }

    private var versions: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = info["CFBundleVersion"] as? String
        let system = ProcessInfo.processInfo.operatingSystemVersion
        return "Hearth version: \(version)\(build.map { " (\($0))" } ?? "")\nmacOS version: \(system.majorVersion).\(system.minorVersion).\(system.patchVersion)\n"
    }

    private var outgoingDraft: SupportDraft {
        draft.includingVersions(includeVersions ? versions : nil)
    }

    private func leaveDraft() {
        if let request { drafts[request] = draft }
        mailUnavailable = false
        request = nil
    }

    private func draftForm(_ kind: SupportDraft.Kind) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SubpageHeader(eyebrow: "Help & Support", title: kind.title, back: leaveDraft) { EmptyView() }
            Text("Edit your message, then open mail or copy it.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Bezel(radius: 20, inset: 3) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("To").font(.system(size: 12)).foregroundStyle(Theme.muted)
                        Spacer()
                        Text(Self.address).font(.system(size: 12, weight: .medium))
                    }
                    LabeledField(label: "Subject", placeholder: "Subject", text: $draft.subject)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Message").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                        Group {
                            if documentationPreview {
                                Text(draft.body).frame(maxWidth: .infinity, alignment: .topLeading)
                            } else {
                                TextEditor(text: $draft.body).scrollContentBackground(.hidden)
                                    .accessibilityLabel("Support message")
                            }
                        }
                        .font(.system(size: 12.5)).foregroundStyle(Theme.ink)
                        .frame(height: 132, alignment: .topLeading)
                        .padding(10).background(RoundedRectangle(cornerRadius: 12).fill(Theme.field))
                    }
                }
                .padding(16)
            }
            if includeVersions {
                Text(versions.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Button(action: openMail) {
                    Label("Open mail app", systemImage: "envelope")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.onCTA).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Capsule().fill(Theme.cta))
                }.buttonStyle(PressStyle())
                Button(action: copyDraft) {
                    Label(draftCopied ? "Copied" : "Copy draft", systemImage: draftCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12.5, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Capsule().fill(Theme.fg.opacity(0.07)))
                }.buttonStyle(PressStyle())
            }
            Text(mailUnavailable ? "Couldn’t open mail. Copy this draft into your email service." : "Using webmail? Copy the draft into a new email to the address above.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func openMail() {
        guard let url = outgoingDraft.mailtoURL else { mailUnavailable = true; return }
        mailUnavailable = !NSWorkspace.shared.open(url)
    }

    private func copyDraft() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(outgoingDraft.clipboardText, forType: .string)
        draftCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { draftCopied = false }
    }

    private func copyAddress() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.address, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }
}
