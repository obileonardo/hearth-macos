import SwiftUI

// MARK: Account page (in the panel)

/// Who's signed in and the server Hearth talks to, live: connection, latency, what's set up,
/// what needs attention, and the main things you'd otherwise open Home Assistant for.
struct AccountPage: View {
    @EnvironmentObject var store: HomeStore
    @Environment(\.hearthOpenWindow) private var openWindow
    @ObservedObject private var admin = HAAdmin.shared
    let back: () -> Void

    @State private var reloading = false
    @State private var reloaded = false
    @State private var confirmRestart = false
    @State private var restarting = false
    @State private var confirmSignOut = false
    @State private var actionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SubpageHeader(eyebrow: "Settings", title: "Account", back: back) { EmptyView() }

            userCard
            serverCard
            counts
            if !failing.isEmpty { health }
            actions

            if let actionError {
                Text(actionError).font(.system(size: 12)).foregroundStyle(Theme.live).fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            admin.attach(store)
            await admin.refreshAccount()
            // Keep the status live while the page is open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await admin.ping()
            }
        }
    }

    private var failing: [HAEntry] { admin.entries.filter(\.isFailing) }

    // MARK: Who

    private var userCard: some View {
        Bezel(radius: 20, inset: 3) {
            HStack(spacing: 14) {
                LiveAvatar(name: admin.user?.name ?? "You", fallback: admin.avatar, size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(admin.user?.name ?? "Signed in").font(.system(size: 17, weight: .semibold))
                    if let username = admin.user?.username ?? UserDefaults.standard.string(forKey: "ha.username"), !username.isEmpty {
                        Text(username).font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                    HStack(spacing: 6) {
                        if admin.user?.isOwner == true { Badge(text: "Owner") }
                        if admin.user?.isAdmin == true { Badge(text: "Administrator") }
                    }
                    .padding(.top, 2)
                }
                Spacer()
            }
            .padding(14)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Server

    private var serverCard: some View {
        Bezel(radius: 20, inset: 3) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    PulseDot(color: store.status == .connected ? Theme.ok : Theme.live, size: 7, live: store.status == .connected)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(admin.server?.locationName ?? "Home Assistant").font(.system(size: 15, weight: .semibold))
                        Text(statusLine).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                divider
                InfoRow(label: "Address", value: address)
                divider
                InfoRow(label: "Version", value: admin.server.map { "Home Assistant \($0.version)" } ?? "…")
                divider
                LocationRow(actual: admin.server?.timeZone)
                divider
                InfoRow(label: "Units", value: admin.server?.units ?? "…")
            }
        }
    }

    private var divider: some View { Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 14) }

    private var address: String {
        let real = admin.server?.externalURL ?? admin.server?.internalURL ?? store.baseURL?.absoluteString ?? ""
        return LocationPrivacy.current == .real ? real : LocationPrivacy.maskAddress(real)
    }

    private var statusLine: String {
        switch store.status {
        case .connected:
            var parts = ["Connected"]
            if let ms = admin.latency { parts.append("\(Int(ms.rounded())) ms") }
            if let since = admin.connectedSince { parts.append("for \(Self.duration(since))") }
            return parts.joined(separator: " · ")
        case .connecting: return "Connecting…"
        case .failed: return "Can't reach the server"
        case .rejected: return "Signed out by the server"
        case .needsSetup: return "Not signed in"
        }
    }

    private static func duration(_ since: Date) -> String {
        let s = Int(Date().timeIntervalSince(since))
        if s < 60 { return "under a minute" }
        let m = s / 60, h = m / 60, d = h / 24
        if d > 0 { return "\(d) d \(h % 24) h" }
        if h > 0 { return "\(h) h \(m % 60) min" }
        return "\(m) min"
    }

    // MARK: Counts

    private var counts: some View {
        let devices = store.devices.values.filter { !$0.isService }.count
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            CountTile(value: admin.entries.count, label: "Integrations", symbol: "puzzlepiece.extension",
                      note: failing.isEmpty ? nil : "\(failing.count) need attention") { openAdmin(.integrations) }
            CountTile(value: devices, label: "Devices", symbol: "cpu", note: nil) { openAdmin(.devices) }
            CountTile(value: store.entities.count, label: "Entities", symbol: "list.bullet", note: nil) { openWeb() }
            CountTile(value: store.areas.count, label: "Areas", symbol: "square.split.2x2", note: nil) { openAdmin(.areas) }
        }
    }

    // MARK: Health

    private var health: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NEEDS ATTENTION").eyebrow().padding(.leading, 4)
            Bezel(radius: 18, inset: 3, lit: true, tint: Theme.live) {
                VStack(spacing: 0) {
                    ForEach(failing) { entry in
                        Button { openAdmin(.integrations) } label: {
                            HStack(spacing: 11) {
                                BrandIcon(domain: entry.domain, size: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(IntegrationTitle.display(entry.title, integration: admin.name(of: entry.domain)) ?? admin.name(of: entry.domain))
                                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    Text([entry.stateText, entry.reason].compactMap { $0 }.joined(separator: ": "))
                                        .font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.faint)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
        }
    }

    // MARK: Actions

    private var actions: some View {
        Bezel(radius: 18, inset: 3) {
            VStack(spacing: 0) {
                ActionRow(symbol: "puzzlepiece.extension", label: "Integrations and devices",
                          detail: "Add, fix and organise what Home Assistant controls") { openAdmin(.integrations) }
                divider
                ActionRow(symbol: "safari", label: "Open Home Assistant",
                          detail: "Automations, dashboards and logs, already signed in") { openWeb() }
                divider
                ActionRow(symbol: reloaded ? "checkmark" : "arrow.triangle.2.circlepath", label: reloaded ? "Reloaded" : "Reload integrations",
                          detail: "Re-reads the setup without restarting", busy: reloading) {
                    Task {
                        reloading = true
                        defer { reloading = false }
                        do { try await admin.reloadIntegrations(); reloaded = true; actionError = nil } catch { actionError = error.localizedDescription }
                        try? await Task.sleep(for: .seconds(3))
                        reloaded = false
                    }
                }
                divider
                ActionRow(symbol: "power", label: confirmRestart ? "Click again to restart" : "Restart Home Assistant",
                          detail: confirmRestart ? "Everything goes offline for about a minute" : "Needed after some updates",
                          tint: Theme.live, warning: confirmRestart, busy: restarting) {
                    if confirmRestart {
                        confirmRestart = false
                        Task {
                            restarting = true
                            do { try await admin.restart(); actionError = nil } catch { actionError = error.localizedDescription }
                            restarting = false
                        }
                    } else {
                        confirmRestart = true
                        Task { try? await Task.sleep(for: .seconds(4)); confirmRestart = false }
                    }
                }
                divider
                ActionRow(symbol: "rectangle.portrait.and.arrow.right", label: confirmSignOut ? "Click again to sign out" : "Sign out",
                          detail: confirmSignOut ? "You'll need your password to sign back in" : nil,
                          tint: Theme.live, warning: confirmSignOut) {
                    if confirmSignOut {
                        store.signOut()
                        back()
                    } else {
                        confirmSignOut = true
                        Task { try? await Task.sleep(for: .seconds(4)); confirmSignOut = false }
                    }
                }
            }
        }
    }

    private func openAdmin(_ section: HAAdmin.Section) {
        admin.section = section
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "ha-admin")
    }

    private func openWeb() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "homeassistant")
    }
}

// MARK: Small pieces

/// A label and its value on one line.
/// How Hearth shows where this home is. Display only: Home Assistant's own location, sun times
/// and automations are untouched.
enum LocationPrivacy: Equatable {
    case real, hidden, region(String)

    static let regions: [(id: String, name: String)] = [
        ("Europe/London", "London"), ("Europe/Paris", "Paris"), ("Europe/Berlin", "Berlin"),
        ("America/New_York", "New York"), ("America/Los_Angeles", "Los Angeles"), ("America/Toronto", "Toronto"),
        ("Asia/Dubai", "Dubai"), ("Asia/Singapore", "Singapore"), ("Asia/Tokyo", "Tokyo"),
        ("Australia/Sydney", "Sydney"), ("Africa/Nairobi", "Nairobi"), ("Africa/Johannesburg", "Johannesburg"),
    ]

    static var current: LocationPrivacy {
        let raw = UserDefaults.standard.string(forKey: "privacy.location") ?? ""
        switch raw {
        case "": return .real
        case "hidden": return .hidden
        default: return .region(raw)
        }
    }

    /// Keeps the scheme, hides the host unless it's this Mac.
    static func maskAddress(_ url: String) -> String {
        guard let u = URL(string: url), let host = u.host else { return "Hidden" }
        if ["localhost", "127.0.0.1"].contains(host) || host.hasSuffix(".local") { return url }
        return "\(u.scheme ?? "https")://•••"
    }
}

/// The home's region, shown as it is, hidden, or as another region you pick, so screenshots and
/// screen shares don't give away where you live.
private struct LocationRow: View {
    let actual: String?
    @AppStorage("privacy.location") private var setting = ""

    private var shown: String {
        switch LocationPrivacy.current {
        case .real: return actual ?? "…"
        case .hidden: return "Hidden"
        case .region(let id): return LocationPrivacy.regions.first { $0.id == id }.map { "\($0.name) (\($0.id))" } ?? id
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Region").font(.system(size: 13)).foregroundStyle(Theme.muted)
            if setting != "" {
                Image(systemName: "eye.slash").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.faint)
                    .help("Shown differently from your real region. Home Assistant itself is unchanged.")
            }
            Spacer(minLength: 12)
            Menu {
                Picker("Region", selection: $setting) {
                    Text("Real (\(actual ?? "from Home Assistant"))").tag("")
                    Text("Hidden").tag("hidden")
                    Divider()
                    ForEach(LocationPrivacy.regions, id: \.id) { r in Text(r.name).tag(r.id) }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 4) {
                    Text(shown).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.muted)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Region shown: \(shown)")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.muted)
            Spacer(minLength: 12)
            Text(value).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

/// A row that does something, with a line saying what.
private struct ActionRow: View {
    let symbol: String
    let label: String
    var detail: String?
    var tint: Color = Theme.sand
    var warning = false
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Group {
                    if busy { ProgressView().controlSize(.small) } else {
                        Image(systemName: symbol).font(.system(size: 13, weight: .regular))
                    }
                }
                .foregroundStyle(warning ? tint : Theme.muted)
                .frame(width: 28, height: 28)
                .background(Circle().fill(warning ? tint.opacity(0.14) : Theme.ink.opacity(0.06)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(warning ? tint : Theme.ink)
                    if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(2) }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.faint)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(busy)
        .animation(.snap, value: warning)
    }
}

/// A number you can open.
private struct CountTile: View {
    let value: Int
    let label: String
    let symbol: String
    let note: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Bezel(radius: 18, inset: 3) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Theme.muted)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.faint)
                    }
                    Text("\(value)").font(.system(size: 24, weight: .semibold)).monospacedDigit().contentTransition(.numericText())
                    Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                    if let note { Text(note).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.live) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(value) \(label)\(note.map { ", \($0)" } ?? "")")
    }
}

private struct Badge: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Theme.sand.opacity(0.16)))
            .foregroundStyle(Theme.sand)
    }
}

/// The person's picture, or their initials.
struct Avatar: View {
    let name: String
    let image: NSImage?
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Text(initials).font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(Theme.base)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LinearGradient(colors: [Theme.sand, Theme.sand.opacity(0.7)], startPoint: .top, endPoint: .bottom))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 0.75))
        .accessibilityHidden(true)
    }

    private var initials: String {
        let words = name.split(separator: " ").prefix(2)
        return words.compactMap(\.first).map(String.init).joined().uppercased()
    }
}

/// An integration's brand icon, fetched once and kept.
struct BrandIcon: View {
    let domain: String
    var size: CGFloat = 32
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit).padding(size * 0.14)
            } else {
                Image(systemName: "puzzlepiece.extension").font(.system(size: size * 0.42)).foregroundStyle(Theme.muted)
            }
        }
        .frame(width: size, height: size)
        // Brand icons are drawn for a white background, in either appearance.
        .background(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(Color.white))
        .accessibilityHidden(true)
        .task(id: domain) { image = await HAAdmin.shared.icon(domain) }
    }
}

// MARK: The admin window

/// Home Assistant's setup, drawn natively: integrations (and adding them, with their setup forms),
/// areas and devices. Anything else opens Home Assistant's own pages, signed in.
struct HAAdminWindow: View {
    @EnvironmentObject var store: HomeStore
    @Environment(\.hearthOpenWindow) private var openWindow
    @ObservedObject private var admin = HAAdmin.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.hairline).frame(width: 1)
            Group {
                switch admin.section {
                case .integrations: IntegrationsView()
                case .add: AddIntegrationView()
                case .areas: AreasView()
                case .devices: DevicesView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: 820, minHeight: 560)
        .background(Theme.base)
        .foregroundStyle(Theme.ink)
        .navigationTitle("Home Assistant")
        .task {
            admin.attach(store)
            async let areas: Void = admin.refreshAreas()
            if admin.server == nil { await admin.refreshAccount() } else { await admin.refreshEntries() }
            await areas
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 3) {
                Text("HOME ASSISTANT").eyebrow()
                Text(admin.server?.locationName ?? "Home").font(.system(size: 18, weight: .semibold))
                if let v = admin.server?.version { Text("Version \(v)").font(.system(size: 12)).foregroundStyle(Theme.muted) }
            }
            .padding(.horizontal, 10).padding(.bottom, 14)

            ForEach(HAAdmin.Section.allCases) { s in
                Button { admin.section = s } label: {
                    HStack(spacing: 10) {
                        Image(systemName: s.symbol).font(.system(size: 13)).frame(width: 18)
                        Text(s.title).font(.system(size: 13, weight: .medium))
                        Spacer()
                        if let n = count(s) { Text("\(n)").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted).monospacedDigit() }
                    }
                    .padding(.horizontal, 10).frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.ink.opacity(admin.section == s ? 0.1 : 0)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityAddTraits(admin.section == s ? .isSelected : [])
            }

            Spacer()

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "homeassistant")
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "safari").font(.system(size: 13))
                    Text("Open Home Assistant").font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline))
            }
            .buttonStyle(PressStyle())
            .help("Automations, dashboards and logs, in Home Assistant's own pages")
        }
        .padding(14)
        .frame(width: 228)
        .background(Theme.ink.opacity(0.025))
    }

    private func count(_ s: HAAdmin.Section) -> Int? {
        switch s {
        case .integrations: admin.entries.count
        case .areas: admin.areas.count
        case .devices: admin.devices.filter { !$0.isService }.count
        case .add: nil
        }
    }
}

/// A page title inside the admin window.
private struct AdminHeader<Trailing: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 22, weight: .semibold)).tracking(-0.4).accessibilityAddTraits(.isHeader)
                if let detail { Text(detail).font(.system(size: 13)).foregroundStyle(Theme.muted) }
            }
            Spacer()
            trailing
        }
    }
}

/// The light pill used for the main action on a page.
private struct PrimaryButton: View {
    let title: String
    var symbol: String?
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Theme.base)
            .padding(.horizontal, 14).frame(height: 32)
            .background(Capsule().fill(Theme.ink))
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// A quiet pill for secondary actions.
private struct QuietButton: View {
    let title: String
    var tint: Color = Theme.ink
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(tint)
                .padding(.horizontal, 12).frame(height: 30)
                .background(Capsule().strokeBorder(Theme.hairline))
                .contentShape(Capsule())
                .hoverFill(Capsule())
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: Integrations

private struct IntegrationsView: View {
    @ObservedObject private var admin = HAAdmin.shared
    @State private var search = ""
    @State private var pendingDelete: HAEntry?
    @State private var working: String?
    @State private var problem: String?

    var body: some View {
        let groups = grouped
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AdminHeader(title: "Integrations", detail: "\(admin.entries.count) set up, \(admin.entries.filter(\.isFailing).count) need attention") {
                    PrimaryButton(title: "Add integration", symbol: "plus") { admin.section = .add }
                }
                HearthField(label: "Search integrations", placeholder: "Search", text: $search)
                if let problem { Text(problem).font(.system(size: 12)).foregroundStyle(Theme.live) }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                    ForEach(groups, id: \.domain) { group in
                        card(group.domain, group.entries)
                    }
                }
            }
            .padding(24)
        }
        .confirmationDialog("Delete \(pendingDelete.map { IntegrationTitle.display($0.title, integration: admin.name(of: $0.domain)) ?? admin.name(of: $0.domain) } ?? "")?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { entry in
            Button("Delete", role: .destructive) { run(entry) { try await admin.delete(entry) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its devices and entities are removed from Home Assistant. You can add it again later.")
        }
        .task { await admin.loadCatalog() }
    }

    private var grouped: [(domain: String, entries: [HAEntry])] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let list = admin.entries.filter { q.isEmpty || $0.title.lowercased().contains(q) || admin.name(of: $0.domain).lowercased().contains(q) || $0.domain.contains(q) }
        let byDomain = Dictionary(grouping: list, by: \.domain)
        return byDomain.map { ($0.key, $0.value) }
            .sorted { a, b in
                let fa = a.entries.contains(where: \.isFailing), fb = b.entries.contains(where: \.isFailing)
                if fa != fb { return fa }
                return admin.name(of: a.domain).localizedCaseInsensitiveCompare(admin.name(of: b.domain)) == .orderedAscending
            }
    }

    private func card(_ domain: String, _ entries: [HAEntry]) -> some View {
        let name = admin.name(of: domain)
        // A single entry named after its integration says nothing new: fold it into the header.
        let single = entries.count == 1 ? entries[0] : nil
        let folded = single.map { IntegrationTitle.display($0.title, integration: name) == nil } ?? false
        return Bezel(radius: 18, inset: 3, lit: entries.contains(where: \.isFailing), tint: Theme.live) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    BrandIcon(domain: domain, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        if folded, let single {
                            status(single)
                        } else if let single, let title = IntegrationTitle.display(single.title, integration: name) {
                            // Its account or host, then its state, on one line, so every card is the same height.
                            HStack(spacing: 6) {
                                status(single).layoutPriority(1)
                                Text("·").foregroundStyle(Theme.faint)
                                Text(title).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle)
                            }
                            .font(.system(size: 12))
                        } else {
                            Text("\(entries.count) entries").font(.system(size: 12)).foregroundStyle(Theme.muted).monospacedDigit()
                        }
                    }
                    Spacer(minLength: 6)
                    if let single, folded || entries.count == 1 {
                        actions(single)
                    }
                }
                if single == nil {
                    VStack(spacing: 0) {
                        ForEach(entries) { entry in
                            Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.vertical, 8)
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(IntegrationTitle.display(entry.title, integration: name) ?? name)
                                        .font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                                    status(entry)
                                    reason(entry)
                                }
                                Spacer()
                                actions(entry)
                            }
                        }
                    }
                    .padding(.leading, 48)
                } else if let single {
                    reason(single).padding(.leading, 48)
                }
            }
            .padding(12)
        }
    }

    private func status(_ entry: HAEntry) -> some View {
        HStack(spacing: 6) {
            Circle().fill(entry.isFailing ? Theme.live : entry.disabledBy != nil ? Theme.faint : Theme.ok).frame(width: 6, height: 6)
            Text(entry.stateText).font(.system(size: 12)).foregroundStyle(entry.isFailing ? Theme.live : Theme.muted)
        }
    }

    @ViewBuilder
    private func reason(_ entry: HAEntry) -> some View {
        if let reason = entry.reason, entry.isFailing {
            Text(reason).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(3)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
        }
    }

    private func actions(_ entry: HAEntry) -> some View {
        HStack(spacing: 6) {
            if working == entry.id { ProgressView().controlSize(.small) }
            Button { menu(entry) } label: {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Theme.fg.opacity(0.06)))
                    .contentShape(Circle())
                    .hoverFill(Circle())
            }
            .buttonStyle(PressStyle())
            .help("Reload, turn off or delete")
            .accessibilityLabel("Options for \(IntegrationTitle.display(entry.title, integration: admin.name(of: entry.domain)) ?? admin.name(of: entry.domain))")
        }
    }

    private func menu(_ entry: HAEntry) {
        var options = ["reload", entry.disabledBy == nil ? "disable" : "enable", "delete"]
        if entry.disabledBy != nil { options.removeFirst() }
        PopupMenu.show(options, selected: nil, label: {
            switch $0 {
            case "reload": "Reload"
            case "disable": "Turn off"
            case "enable": "Turn on"
            default: "Delete…"
            }
        }) { choice in
            switch choice {
            case "reload": run(entry) { try await admin.reload(entry) }
            case "disable": run(entry) { try await admin.setEnabled(entry, false) }
            case "enable": run(entry) { try await admin.setEnabled(entry, true) }
            default: pendingDelete = entry
            }
        }
    }

    private func run(_ entry: HAEntry, _ work: @escaping () async throws -> Void) {
        Task {
            working = entry.id
            defer { working = nil }
            do { try await work(); problem = nil } catch { problem = error.localizedDescription }
        }
    }
}

// MARK: Add integration

private struct AddIntegrationView: View {
    @ObservedObject private var admin = HAAdmin.shared
    @State private var search = ""
    @State private var session: FlowSession?

    var body: some View {
        if let session {
            FlowView(session: session) { self.session = nil }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AdminHeader(title: "Add integration", detail: admin.catalog.isEmpty ? "Loading the catalogue…" : "\(admin.catalog.count) can be set up here") {
                        QuietButton(title: "Back") { admin.section = .integrations }
                    }
                    HearthField(label: "Search integrations", placeholder: "Search brands and services", text: $search)
                    if admin.catalog.isEmpty {
                        VStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Fetching every integration Home Assistant can set up")
                                .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 60)
                    }
                    LazyVStack(spacing: 6) {
                        ForEach(results) { item in
                            Button { session = FlowSession(domain: item.domain, name: item.name) } label: {
                                HStack(spacing: 12) {
                                    BrandIcon(domain: item.domain, size: 32)
                                    Text(item.name).font(.system(size: 13, weight: .medium))
                                    if item.isCustom {
                                        Text("HACS").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.sand)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Capsule().fill(Theme.sand.opacity(0.14)))
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.faint)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .contentShape(Rectangle())
                                .hoverFill(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                }
                .padding(24)
            }
            .task {
                // `-haFlow <domain>` (and `-haFlowValues <json>` for a first answer) open a setup straight away, for renders.
                if let domain = UserDefaults.standard.string(forKey: "haFlow"), session == nil {
                    let s = FlowSession(domain: domain, name: admin.name(of: domain))
                    // Not tied to this view: showing the form replaces it, which would cancel the requests.
                    Task { @MainActor in
                        await s.start()
                        // A `{…}` argument arrives as a dictionary; a quoted one as a JSON string.
                        if let values = UserDefaults.standard.dictionary(forKey: "haFlowValues")
                            ?? UserDefaults.standard.string(forKey: "haFlowValues").flatMap({ (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? JSON }) {
                            s.values.merge(values) { $1 }
                            await s.submit()
                        }
                    }
                    session = s
                    return
                }
                await admin.loadCatalog()
            }
        }
    }

    private var results: [HACatalogItem] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return admin.catalog }
        return admin.catalog.filter { $0.name.lowercased().contains(q) || $0.domain.contains(q) }
    }
}

// MARK: Setup flows

/// One run through an integration's setup, with the values typed so far.
@MainActor
final class FlowSession: ObservableObject, Identifiable {
    let domain: String
    let name: String
    @Published var step: FlowStep?
    @Published var values: [String: Any] = [:]
    @Published var strings: [String: String] = [:]
    @Published var busy = false
    @Published var problem: String?
    private var finished = false

    init(domain: String, name: String) {
        self.domain = domain
        self.name = name
    }

    private var started = false

    func start() async {
        // Only ever one flow per session, however many views ask.
        guard step == nil, !started else { return }
        started = true
        busy = true
        defer { busy = false }
        strings = await HAAdmin.shared.strings(for: domain)
        do { show(try await HAAdmin.shared.startFlow(domain)) } catch { problem = error.localizedDescription }
    }

    func submit(_ extra: JSON? = nil) async {
        guard let step else { return }
        busy = true
        defer { busy = false }
        do { show(try await HAAdmin.shared.submit(step.flowID, extra ?? payload(step))) } catch { problem = error.localizedDescription }
    }

    /// Polls a step that's waiting on Home Assistant (a progress spinner, or a browser sign-in).
    func waitForProgress() async {
        while let step, step.kind == .progress, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            if let next = try? await HAAdmin.shared.current(step.flowID), next.kind != .progress || next.stepID != step.stepID {
                show(next)
            }
        }
    }

    func cancel() async {
        if let step, !finished { await HAAdmin.shared.abort(step.flowID) }
        finished = true
    }

    private func show(_ next: FlowStep) {
        problem = nil
        step = next
        if next.kind == .createEntry || next.kind == .abort { finished = true }
        // Start each form from its defaults, keeping anything already typed for fields with the same name.
        for f in next.fields where values[f.name] == nil {
            if let d = f.defaultValue, !(d is NSNull) { values[f.name] = d }
        }
    }

    /// The form's values, typed the way Home Assistant expects. Empty optional fields are left out.
    private func payload(_ step: FlowStep) -> JSON {
        var out: JSON = [:]
        for f in step.fields {
            guard let v = values[f.name] else { continue }
            switch f.kind {
            case .text, .unsupported:
                let s = "\(v)".trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty || f.required { out[f.name] = s }
            case .number(_, _, let stepSize):
                let d = (v as? Double) ?? Double("\(v)".replacingOccurrences(of: ",", with: "."))
                if let d { out[f.name] = (stepSize ?? 0) >= 1 && d == d.rounded() ? Int(d) as Any : d as Any }
            case .boolean:
                out[f.name] = (v as? Bool) ?? false
            case .select(_, let multiple, _):
                if multiple {
                    if let list = v as? [String] { out[f.name] = list }
                    else if let s = v as? String { out[f.name] = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                } else if let s = v as? String, !s.isEmpty {
                    out[f.name] = s
                }
            }
        }
        return out
    }

    // MARK: Words

    func text(_ key: String) -> String? {
        guard var s = strings["component.\(domain).config.\(key)"] else { return nil }
        for (k, v) in step?.placeholders ?? [:] { s = s.replacingOccurrences(of: "{\(k)}", with: v) }
        return s
    }

    func label(_ f: FlowField) -> String {
        text("step.\(step?.stepID ?? "").data.\(f.name)") ?? f.name.replacingOccurrences(of: "_", with: " ").capitalized
    }

    func help(_ f: FlowField) -> String? { text("step.\(step?.stepID ?? "").data_description.\(f.name)") }

    func optionLabel(_ f: FlowField, _ value: String, fallback: String) -> String {
        if let key = f.translationKey, let s = strings["component.\(domain).selector.\(key).options.\(value)"] { return s }
        return fallback
    }

    func error(_ key: String) -> String { text("error.\(key)") ?? key.replacingOccurrences(of: "_", with: " ").capitalized }
}

private struct FlowView: View {
    @EnvironmentObject var store: HomeStore
    @Environment(\.hearthOpenWindow) private var openWindow
    @ObservedObject var session: FlowSession
    let close: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    BrandIcon(domain: session.domain, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SET UP").eyebrow()
                        Text(title).font(.system(size: 20, weight: .semibold)).tracking(-0.3)
                    }
                    Spacer()
                    QuietButton(title: done ? "Close" : "Cancel") { Task { await session.cancel(); close() } }
                }

                if let description {
                    Text(description).font(.system(size: 13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }

                if let problem = session.problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.live)
                }

                content
            }
            .padding(24)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task { await session.start() }
        .task(id: session.step?.stepID) { await session.waitForProgress() }
    }

    private var done: Bool { session.step?.kind == .createEntry || session.step?.kind == .abort }

    private var title: String {
        guard let step = session.step else { return session.name }
        if step.kind == .form || step.kind == .menu, let t = session.text("step.\(step.stepID ?? "user").title") { return t }
        return session.name
    }

    private var description: AttributedString? {
        guard let step = session.step, step.kind == .form || step.kind == .menu || step.kind == .progress || step.kind == .external,
              let raw = session.text("step.\(step.stepID ?? "user").description"), !raw.isEmpty else { return nil }
        return (try? AttributedString(markdown: raw, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(raw)
    }

    @ViewBuilder
    private var content: some View {
        if let step = session.step {
            switch step.kind {
            case .form: form(step)
            case .menu: menu(step)
            case .progress:
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Working…").font(.system(size: 13)).foregroundStyle(Theme.muted) }
            case .external, .externalDone:
                VStack(alignment: .leading, spacing: 12) {
                    Text("This step happens in your browser. Finish there, then come back.").font(.system(size: 13)).foregroundStyle(Theme.muted)
                    HStack(spacing: 10) {
                        if let url = step.url { PrimaryButton(title: "Open in browser", symbol: "safari") { NSWorkspace.shared.open(url) } }
                        QuietButton(title: "I've finished, continue") { Task { await session.submit([:]) } }
                    }
                }
            case .createEntry:
                result(symbol: "checkmark.circle.fill", tint: Theme.ok, title: "\(step.title ?? session.name) is set up",
                       detail: "Its devices will appear in Hearth in a moment.")
            case .abort:
                result(symbol: "info.circle.fill", tint: Theme.sand, title: "Setup stopped",
                       detail: session.text("abort.\(step.reason ?? "")") ?? step.reason?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Home Assistant ended the setup.")
            case .unknown:
                openInHA(reason: "Home Assistant asked for a step Hearth can't show yet.")
            }
        } else if session.busy {
            HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Starting…").font(.system(size: 13)).foregroundStyle(Theme.muted) }
        }
    }

    private func form(_ step: FlowStep) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let base = step.errors["base"] {
                Label(session.error(base), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.live)
            }
            ForEach(step.fields) { f in
                FlowFieldView(session: session, field: f, error: step.errors[f.name].map(session.error))
            }
            if step.fields.contains(where: { if case .unsupported = $0.kind { true } else { false } }) {
                openInHA(reason: "Some of these fields are easier to fill in Home Assistant.")
            }
            HStack {
                Spacer()
                if session.busy { ProgressView().controlSize(.small) }
                PrimaryButton(title: step.lastStep == false ? "Next" : "Submit", symbol: nil, enabled: !session.busy) {
                    Task { await session.submit() }
                }
            }
        }
    }

    private func menu(_ step: FlowStep) -> some View {
        VStack(spacing: 8) {
            ForEach(step.menu, id: \.value) { option in
                Button { Task { await session.submit(["next_step_id": option.value]) } } label: {
                    HStack {
                        Text(session.text("step.\(step.stepID ?? "user").menu_options.\(option.value)") ?? option.label ?? option.value.pretty)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.faint)
                    }
                    .padding(.horizontal, 14).frame(height: 42)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.ink.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline)))
                }
                .buttonStyle(PressStyle())
            }
        }
    }

    private func result(symbol: String, tint: Color, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(tint)
            Text(title).font(.system(size: 17, weight: .semibold))
            Text(detail).font(.system(size: 13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: "Done") { close() }.padding(.top, 6)
        }
    }

    private func openInHA(reason: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "safari").font(.system(size: 13)).foregroundStyle(Theme.muted)
            Text(reason).font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            Spacer()
            QuietButton(title: "Open in Home Assistant") {
                Task {
                    await session.cancel()
                    UserDefaults.standard.set("_my_redirect/config_flow_start?domain=\(session.domain)", forKey: "haWeb.next")
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "homeassistant")
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline))
    }
}

/// One form field, drawn from its schema.
private struct FlowFieldView: View {
    @ObservedObject var session: FlowSession
    let field: FlowField
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Text(session.label(field)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                if field.required { Text("Required").font(.system(size: 11)).foregroundStyle(Theme.faint) }
            }
            control
            if let help = session.help(field) {
                Text((try? AttributedString(markdown: help, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(help))
                    .font(.system(size: 12)).foregroundStyle(Theme.faint).fixedSize(horizontal: false, vertical: true)
            }
            if let error {
                Text(error).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.live).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var control: some View {
        switch field.kind {
        case .text(let secure, _):
            HearthField(label: session.label(field), placeholder: secure ? "••••••••" : "", text: string, secure: secure,
                        contentType: secure ? .password : nil)
        case .number(let min, let max, _):
            HearthField(label: session.label(field), placeholder: [min.map { "from \(Self.short($0))" }, max.map { "to \(Self.short($0))" }].compactMap { $0 }.joined(separator: " "),
                        text: string)
        case .boolean:
            HStack {
                Text(boolValue ? "On" : "Off").font(.system(size: 13)).foregroundStyle(Theme.muted)
                Spacer()
                Toggle(session.label(field), isOn: Binding(get: { boolValue }, set: { session.values[field.name] = $0 }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            .padding(.horizontal, 14).frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.hairline))
        case .select(let options, let multiple, let custom):
            if multiple {
                multiSelect(options, custom: custom)
            } else if options.isEmpty {
                HearthField(label: session.label(field), placeholder: "", text: string)
            } else {
                Button {
                    PopupMenu.show(options.map(\.value), selected: session.values[field.name] as? String,
                                   label: { v in session.optionLabel(field, v, fallback: options.first { $0.value == v }?.label ?? v) }) {
                        session.values[field.name] = $0
                    }
                } label: {
                    HStack {
                        let v = session.values[field.name] as? String
                        Text(v.map { v in session.optionLabel(field, v, fallback: options.first { $0.value == v }?.label ?? v) } ?? "Choose")
                            .font(.system(size: 13.5)).foregroundStyle(v == nil ? Theme.faint : Theme.ink)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 14).frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.hairline))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(session.label(field))
            }
        case .unsupported:
            HearthField(label: session.label(field), placeholder: "Type a value", text: string)
        }
    }

    private func multiSelect(_ options: [(value: String, label: String)], custom: Bool) -> some View {
        let chosen = Set(session.values[field.name] as? [String] ?? [])
        return VStack(alignment: .leading, spacing: 8) {
            if !options.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(options, id: \.value) { o in
                        let on = chosen.contains(o.value)
                        Button {
                            var next = chosen
                            if on { next.remove(o.value) } else { next.insert(o.value) }
                            session.values[field.name] = options.map(\.value).filter(next.contains)
                        } label: {
                            Text(session.optionLabel(field, o.value, fallback: o.label)).font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(on ? Theme.base : Theme.ink)
                                .padding(.horizontal, 11).frame(height: 28)
                                .background(Capsule().fill(on ? Theme.ink : Theme.ink.opacity(0.06)))
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            if custom && options.isEmpty {
                HearthField(label: session.label(field), placeholder: "Separate several with commas",
                            text: Binding(get: { (session.values[field.name] as? [String])?.joined(separator: ", ") ?? (session.values[field.name] as? String ?? "") },
                                          set: { session.values[field.name] = $0 }))
            }
        }
    }

    private var string: Binding<String> {
        Binding(get: {
            switch session.values[field.name] {
            case let s as String: return s
            case let d as Double: return Self.short(d)
            case let i as Int: return "\(i)"
            case let n as NSNumber: return n.stringValue
            default: return ""
            }
        }, set: { session.values[field.name] = $0 })
    }

    private var boolValue: Bool { (session.values[field.name] as? Bool) ?? false }

    private static func short(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(d) }
}

/// Lays chips out in rows, wrapping to the width it's given.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
        }
        return CGSize(width: width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

// MARK: Areas

private struct AreasView: View {
    @ObservedObject private var admin = HAAdmin.shared
    @State private var newName = ""
    @State private var floorName = ""
    @State private var floorLevel = 0
    @State private var renaming: String?
    @State private var renameText = ""
    @State private var pendingDelete: HAAreaRow?
    @State private var problem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AdminHeader(title: "Areas", detail: "Rooms and spaces. Hearth's Rooms tab shows them as you set them here.") { EmptyView() }
                if admin.supportsFloors {
                    Text("FLOORS").eyebrow()
                    HStack(spacing: 10) {
                        HearthField(label: "New floor name", placeholder: "Ground floor", text: $floorName) { createFloor() }
                        Stepper("Level \(floorLevel)", value: $floorLevel, in: -20...200)
                            .font(.system(size: 12.5)).fixedSize()
                        PrimaryButton(title: "Add", symbol: "plus", enabled: !floorName.trimmingCharacters(in: .whitespaces).isEmpty) { createFloor() }
                    }
                    Text("Ground floor is level 0, first floor is 1, second floor is 2. Choose a floor for each room below.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Text("ROOMS").eyebrow().padding(.top, 4)
                }
                HStack(spacing: 10) {
                    HearthField(label: "New area name", placeholder: "New area, like Garage", text: $newName) { create() }
                    PrimaryButton(title: "Add", symbol: "plus", enabled: !newName.trimmingCharacters(in: .whitespaces).isEmpty) { create() }
                }
                if let problem { Text(problem).font(.system(size: 12)).foregroundStyle(Theme.live) }
                Bezel(radius: 18, inset: 3) {
                    VStack(spacing: 0) {
                        ForEach(Array(admin.areas.enumerated()), id: \.element.id) { i, area in
                            if i > 0 { Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 14) }
                            row(area)
                        }
                    }
                }
            }
            .padding(24)
        }
        .confirmationDialog("Delete \(pendingDelete?.name ?? "")?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { area in
            Button("Delete", role: .destructive) { run { try await admin.deleteArea(area) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its devices stay in Home Assistant, without an area.")
        }
    }

    private func row(_ area: HAAreaRow) -> some View {
        let count = admin.devices.filter { $0.areaID == area.id && !$0.isService }.count
        return HoverRow { hovering in HStack(spacing: 11) {
            Image(systemName: RoomStyle.symbol(Area(id: area.id, name: area.name)))
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
                .frame(width: 28, height: 28).background(Circle().fill(Theme.ink.opacity(0.06)))
            if renaming == area.id {
                HearthField(label: "Area name", placeholder: area.name, text: $renameText) { rename(area) }
                QuietButton(title: "Save") { rename(area) }
                QuietButton(title: "Cancel") { renaming = nil }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(area.name).font(.system(size: 13, weight: .semibold))
                    Text(count == 1 ? "1 device" : "\(count) devices").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                if admin.supportsFloors {
                    Button {
                        PopupMenu.show(["none"] + admin.floors.map(\.id), selected: area.floorID ?? "none",
                                       label: { id in admin.floors.first { $0.id == id }?.name ?? "No floor" }) { id in
                            run { try await admin.assignFloor(id == "none" ? nil : id, to: area) }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(admin.floors.first { $0.id == area.floorID }?.name ?? "No floor").lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9))
                        }
                        .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(Theme.fg.opacity(0.05)))
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Floor for \(area.name)")
                }
                RowActions(hovering: hovering) {
                    IconKey(symbol: "pencil", label: "Rename \(area.name)") { renameText = area.name; renaming = area.id }
                    IconKey(symbol: "trash", label: "Delete \(area.name)", tint: Theme.live) { pendingDelete = area }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8) }
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        run { try await admin.createArea(name); newName = "" }
    }

    private func createFloor() {
        let name = floorName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        run { try await admin.createFloor(name, level: floorLevel); floorName = "" }
    }

    private func rename(_ area: HAAreaRow) {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        run { try await admin.renameArea(area, to: name); renaming = nil }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task { do { try await work(); problem = nil } catch { problem = error.localizedDescription } }
    }
}

// MARK: Devices

private struct DevicesView: View {
    @ObservedObject private var admin = HAAdmin.shared
    @State private var search = ""
    @State private var renaming: String?
    @State private var renameText = ""
    @State private var problem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AdminHeader(title: "Devices", detail: "Give a device a name you'll recognise, and put it in its room.") { EmptyView() }
                HearthField(label: "Search devices", placeholder: "Search", text: $search)
                if let problem { Text(problem).font(.system(size: 12)).foregroundStyle(Theme.live) }
                Bezel(radius: 18, inset: 3) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { i, device in
                            if i > 0 { Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 14) }
                            row(device)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private var results: [HADeviceRow] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return admin.devices.filter { !$0.isService && (q.isEmpty || $0.shownName.lowercased().contains(q)
            || ($0.manufacturer ?? "").lowercased().contains(q) || ($0.model ?? "").lowercased().contains(q)) }
    }

    private func row(_ device: HADeviceRow) -> some View {
        HoverRow { hovering in HStack(spacing: 11) {
            if renaming == device.id {
                HearthField(label: "Device name", placeholder: device.name, text: $renameText) { rename(device) }
                QuietButton(title: "Save") { rename(device) }
                QuietButton(title: "Cancel") { renaming = nil }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.shownName).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text([device.manufacturer, device.model].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer()
                Button { pickArea(device) } label: {
                    HStack(spacing: 6) {
                        Text(admin.areas.first { $0.id == device.areaID }?.name ?? "No area").font(.system(size: 12.5, weight: .medium))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(Capsule().fill(Theme.ink.opacity(0.06)))
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Area for \(device.shownName)")
                RowActions(hovering: hovering) {
                    IconKey(symbol: "pencil", label: "Rename \(device.shownName)") { renameText = device.shownName; renaming = device.id }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8) }
    }

    private func pickArea(_ device: HADeviceRow) {
        let ids = ["none"] + admin.areas.map(\.id)
        PopupMenu.show(ids, selected: device.areaID ?? "none", label: { id in
            id == "none" ? "No area" : admin.areas.first { $0.id == id }?.name ?? id
        }) { id in
            run { try await admin.updateDevice(device, areaID: .some(id == "none" ? nil : id)) }
        }
    }

    private func rename(_ device: HADeviceRow) {
        run { try await admin.updateDevice(device, name: renameText.trimmingCharacters(in: .whitespaces)); renaming = nil }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task { do { try await work(); problem = nil } catch { problem = error.localizedDescription } }
    }
}

/// How a config entry's title is shown: hidden when it only repeats the integration's name,
/// and with phone numbers and email addresses partly masked, since some integrations title
/// their entry with the account it signed in with.
enum IntegrationTitle {
    static func display(_ title: String, integration: String) -> String? {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.caseInsensitiveCompare(integration) != .orderedSame else { return nil }
        return masked(t)
    }

    static func masked(_ t: String) -> String {
        let digits = t.filter(\.isNumber)
        if digits.count >= 7, t.allSatisfy({ $0.isNumber || "+ -()".contains($0) }) {
            let head = t.hasPrefix("+") ? "+" + digits.prefix(3) : String(digits.prefix(3))
            return "\(head) \u{2022}\u{2022}\u{2022} \(digits.suffix(4))"
        }
        if let at = t.firstIndex(of: "@"), t[t.index(after: at)...].contains(".") {
            let user = t[..<at]
            return "\(user.prefix(1))\u{2022}\u{2022}\u{2022}@\(t[t.index(after: at)...])"
        }
        return t
    }
}

/// A row's quiet actions: present but understated until the pointer is over the row, so a long
/// list doesn't repeat the same loud buttons on every line.
private struct RowActions<Content: View>: View {
    let hovering: Bool
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 6) { content }
            .opacity(hovering ? 1 : 0.35)
            .animation(.snap, value: hovering)
    }
}

/// A small round icon key for row actions.
private struct IconKey: View {
    let symbol: String
    let label: String
    var tint: Color = Theme.muted
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.fg.opacity(0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Tracks the pointer over a row.
private struct HoverRow<Content: View>: View {
    @ViewBuilder var content: (Bool) -> Content
    @State private var hovering = false
    var body: some View {
        content(hovering)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.hover).opacity(hovering ? 1 : 0).padding(.horizontal, 4))
            .onHover { inside in withAnimation(.snap) { hovering = inside } }
    }
}
