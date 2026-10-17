import SwiftUI

// MARK: The house drawing

/// A small illustrated home whose windows glow with how much it's using right now.
struct HomeArt: View {
    var style: Home.Style = .house
    /// 0 when nothing is known or nothing is drawn, up to 1 for a busy evening.
    var glow: Double = 0
    var size: CGFloat = 64

    static let light = Theme.homeEnergy

    /// How brightly the windows burn for a load in watts.
    static func glow(for watts: Double?) -> Double {
        guard let w = watts, w > 0 else { return 0 }
        return min(0.3 + w / 3000, 1)
    }

    var body: some View {
        Canvas { ctx, size in draw(&ctx, size.width) }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext, _ s: CGFloat) {
        // A soft shadow on the ground.
        ctx.fill(Path(ellipseIn: CGRect(x: s * 0.14, y: s * 0.84, width: s * 0.72, height: s * 0.09)),
                 with: .color(.black.opacity(0.45)))
        switch style {
        case .house: house(&ctx, s)
        case .apartment: apartment(&ctx, s)
        case .office: office(&ctx, s)
        }
    }

    private func wall(_ rect: CGRect) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: [Color(white: 0.93), Color(white: 0.74)]),
                        startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY))
    }

    /// Green glass with a halo represents home consumption; dark glass means no draw.
    private func window(_ ctx: inout GraphicsContext, _ r: CGRect, lit: Double) {
        let shape = Path(roundedRect: r, cornerRadius: r.width * 0.12)
        if lit > 0 {
            var halo = ctx
            halo.addFilter(.blur(radius: r.width * 0.6))
            halo.fill(Path(roundedRect: r.insetBy(dx: -r.width * 0.2, dy: -r.height * 0.2), cornerRadius: r.width * 0.3),
                      with: .color(Self.light.opacity(0.55 * lit)))
            ctx.fill(shape, with: .linearGradient(Gradient(colors: [Self.light.opacity(0.65 + 0.35 * lit), Theme.homeEnergyEnd.opacity(0.7 + 0.3 * lit)]),
                                                  startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))
        } else {
            ctx.fill(shape, with: .linearGradient(Gradient(colors: [Color(white: 0.32), Color(white: 0.16)]),
                                                  startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))
        }
        ctx.stroke(shape, with: .color(Theme.fg.opacity(0.5)), lineWidth: max(r.width * 0.06, 0.6))
    }

    private func house(_ ctx: inout GraphicsContext, _ s: CGFloat) {
        let body = CGRect(x: s * 0.2, y: s * 0.44, width: s * 0.6, height: s * 0.42)
        ctx.fill(Path(roundedRect: body, cornerRadius: s * 0.025), with: wall(body))
        // Chimney, then the roof over it.
        let chimney = CGRect(x: s * 0.62, y: s * 0.2, width: s * 0.08, height: s * 0.18)
        ctx.fill(Path(chimney), with: .color(Color(white: 0.3)))
        var roof = Path()
        roof.move(to: CGPoint(x: s * 0.12, y: s * 0.47))
        roof.addLine(to: CGPoint(x: s * 0.5, y: s * 0.16))
        roof.addLine(to: CGPoint(x: s * 0.88, y: s * 0.47))
        roof.addLine(to: CGPoint(x: s * 0.82, y: s * 0.5))
        roof.addLine(to: CGPoint(x: s * 0.5, y: s * 0.245))
        roof.addLine(to: CGPoint(x: s * 0.18, y: s * 0.5))
        roof.closeSubpath()
        ctx.fill(roof, with: .linearGradient(Gradient(colors: [Color(white: 0.36), Color(white: 0.16)]),
                                             startPoint: CGPoint(x: s * 0.5, y: s * 0.16), endPoint: CGPoint(x: s * 0.5, y: s * 0.5)))
        // Gable fill under the roof.
        var gable = Path()
        gable.move(to: CGPoint(x: s * 0.2, y: s * 0.48))
        gable.addLine(to: CGPoint(x: s * 0.5, y: s * 0.255))
        gable.addLine(to: CGPoint(x: s * 0.8, y: s * 0.48))
        gable.closeSubpath()
        ctx.fill(gable, with: .color(Color(white: 0.86)))
        window(&ctx, CGRect(x: s * 0.44, y: s * 0.33, width: s * 0.12, height: s * 0.1), lit: glow * 0.7)
        // Door and two windows.
        let door = CGRect(x: s * 0.44, y: s * 0.64, width: s * 0.12, height: s * 0.22)
        ctx.fill(Path(roundedRect: door, cornerRadius: s * 0.015),
                 with: .linearGradient(Gradient(colors: [Color(red: 0.42, green: 0.3, blue: 0.22), Color(red: 0.26, green: 0.18, blue: 0.13)]),
                                       startPoint: CGPoint(x: door.midX, y: door.minY), endPoint: CGPoint(x: door.midX, y: door.maxY)))
        ctx.fill(Path(ellipseIn: CGRect(x: door.maxX - s * 0.035, y: door.midY, width: s * 0.015, height: s * 0.015)),
                 with: .color(Color(red: 0.95, green: 0.8, blue: 0.5)))
        window(&ctx, CGRect(x: s * 0.26, y: s * 0.54, width: s * 0.13, height: s * 0.13), lit: glow)
        window(&ctx, CGRect(x: s * 0.61, y: s * 0.54, width: s * 0.13, height: s * 0.13), lit: glow * 0.85)
    }

    private func apartment(_ ctx: inout GraphicsContext, _ s: CGFloat) {
        let body = CGRect(x: s * 0.28, y: s * 0.12, width: s * 0.44, height: s * 0.74)
        ctx.fill(Path(roundedRect: body, cornerRadius: s * 0.03), with: wall(body))
        ctx.fill(Path(CGRect(x: body.minX - s * 0.02, y: body.minY - s * 0.02, width: body.width + s * 0.04, height: s * 0.04)),
                 with: .color(Color(white: 0.3)))
        // Windows lit from the bottom floors up, more of them the more the home is using.
        let lit = Int((glow * 12).rounded())
        var n = 0
        for row in (0..<4).reversed() {
            for col in 0..<3 {
                let r = CGRect(x: body.minX + s * (0.05 + Double(col) * 0.13), y: body.minY + s * (0.07 + Double(row) * 0.15),
                               width: s * 0.08, height: s * 0.09)
                let order = [0, 4, 8, 2, 6, 10, 1, 5, 9, 3, 7, 11][n]
                window(&ctx, r, lit: order < lit ? glow : 0)
                n += 1
            }
        }
        let door = CGRect(x: s * 0.45, y: s * 0.74, width: s * 0.1, height: s * 0.12)
        ctx.fill(Path(roundedRect: door, cornerRadius: s * 0.01), with: .color(Color(white: 0.22)))
    }

    private func office(_ ctx: inout GraphicsContext, _ s: CGFloat) {
        let body = CGRect(x: s * 0.12, y: s * 0.36, width: s * 0.76, height: s * 0.5)
        ctx.fill(Path(roundedRect: body, cornerRadius: s * 0.03), with: wall(body))
        ctx.fill(Path(CGRect(x: body.minX - s * 0.02, y: body.minY - s * 0.03, width: body.width + s * 0.04, height: s * 0.05)),
                 with: .color(Color(white: 0.28)))
        for band in 0..<2 {
            let r = CGRect(x: body.minX + s * 0.05, y: body.minY + s * (0.07 + Double(band) * 0.17), width: body.width - s * 0.1, height: s * 0.11)
            window(&ctx, r, lit: band == 0 ? glow : glow * 0.7)
        }
        let door = CGRect(x: s * 0.44, y: s * 0.72, width: s * 0.12, height: s * 0.14)
        ctx.fill(Path(roundedRect: door, cornerRadius: s * 0.01), with: .color(Color(white: 0.25)))
    }
}

// MARK: The homes strip in the Devices tab

/// Every home as a card with what it's using now and today, and a way to add another.
struct HomesStrip: View {
    @EnvironmentObject var store: HomeStore
    @ObservedObject private var list = HomeList.shared
    @ObservedObject private var gadgets = GadgetStore.shared
    @ObservedObject var feed: HomesFeed
    let open: (HomeRoute) -> Void
    @State private var adding = false

    var body: some View {
        let energies = list.homes.map { HomeEnergy(home: $0, store: store, list: list, gadgets: gadgets.gadgets) }
        // Until something reports live power, offer the demo home to show what it would look like.
        let anyReadings = energies.contains { $0.nowWatts != nil }
        VStack(alignment: .leading, spacing: 8) {
            Text(list.homes.count == 1 ? "HOME" : "HOMES").eyebrow().padding(.leading, 4)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(energies, id: \.home.id) { e in
                    HomeCard(energy: e, today: feed.today(e)) { open(.real(e.home.id)) }
                }
                if !adding {
                    AddHomeCard { withAnimation(.glide) { adding = true } }
                }
            }
            if adding {
                HomeEditor(home: nil) { name, style in
                    let home = list.add(name: name, style: style)
                    withAnimation(.glide) { adding = false }
                    open(.real(home.id))
                } onCancel: {
                    withAnimation(.glide) { adding = false }
                }
                .transition(.opacity.combined(with: .offset(y: -6)))
            }
            if !anyReadings {
                Button { open(.demo) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill").font(.system(size: 9, weight: .bold))
                        Text("See what a home looks like with power readings").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(HomeArt.light)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(Capsule().fill(HomeArt.light.opacity(0.1)).overlay(Capsule().strokeBorder(HomeArt.light.opacity(0.3), lineWidth: 0.75)))
                }
                .buttonStyle(PressStyle())
                .padding(.leading, 2)
                .accessibilityLabel("Try the demo home")
            }
        }
    }
}

/// Where the Devices tab can go for homes: one of yours, or the demo home.
enum HomeRoute: Equatable {
    case real(UUID)
    case demo
}

private struct HomeCard: View {
    let energy: HomeEnergy
    let today: Double?
    let action: () -> Void

    var body: some View {
        let now = energy.nowWatts
        let lit = (now ?? 0) > 0
        Button(action: action) {
            Bezel(radius: 22, inset: 3, lit: lit, tint: HomeArt.light) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        HomeArt(style: energy.home.style, glow: HomeArt.glow(for: now), size: 54)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.faint).padding(.top, 4)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(energy.home.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text(line(now)).font(.system(size: 12, weight: .medium))
                            .foregroundStyle(lit ? HomeArt.light : Theme.muted)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(energy.home.name). \(line(now))")
        .accessibilityHint("Opens this home")
    }

    private func line(_ now: Double?) -> String {
        let parts = [now.map { "\(EnergyUnits.power($0)) now" }, today.map { "\(EnergyUnits.energy($0)) today" }].compactMap { $0 }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        let n = energy.devices.count + energy.gadgets.count
        return n == 0 ? "No devices yet" : "\(n) device\(n == 1 ? "" : "s") · no power readings"
    }
}

private struct AddHomeCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 16, weight: .medium))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.fg.opacity(0.07)).overlay(Circle().strokeBorder(Theme.hairline)))
                Text("Add home").font(.system(size: 13, weight: .semibold))
                Text("A second house, a flat, the office").font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 134)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(Theme.fg.opacity(0.16)))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Add home")
    }
}

// MARK: Adding and editing a home

struct HomeEditor: View {
    let home: Home?
    let onSave: (String, Home.Style) -> Void
    let onCancel: () -> Void
    var onDelete: (() -> Void)?
    @State private var name: String
    @State private var style: Home.Style

    init(home: Home?, onSave: @escaping (String, Home.Style) -> Void, onCancel: @escaping () -> Void, onDelete: (() -> Void)? = nil) {
        self.home = home
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
        _name = State(initialValue: home?.name ?? "")
        _style = State(initialValue: home?.style ?? .house)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        Bezel(radius: 24, inset: 4, lit: true, tint: HomeArt.light) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    HomeArt(style: style, glow: 0.7, size: 44).animation(.glide, value: style)
                    Text(home == nil ? "Add a home" : "Edit \(home!.name)").font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Spacer()
                }
                LabeledField(label: "Name", placeholder: "Beach house", text: $name) { save() }
                Segmented(options: Home.Style.allCases, selected: style, tint: HomeArt.light, id: "home-style", compact: true) { s in
                    Image(systemName: s.symbol).font(.system(size: 12.5, weight: .light))
                    Text(s.title).font(.system(size: 11, weight: .semibold))
                } onSelect: { style = $0 }
                if home?.isMain == true {
                    Text("This is your main home. Anything not linked to another home lives here.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 14) {
                    if let onDelete {
                        Button("Delete", action: onDelete)
                            .buttonStyle(PressStyle()).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.live)
                    }
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .buttonStyle(PressStyle()).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                    Button(action: save) {
                        HStack(spacing: 8) {
                            Text(home == nil ? "Add" : "Save").font(.system(size: 13, weight: .semibold))
                            Image(systemName: "checkmark").font(.system(size: 10.5, weight: .bold))
                                .frame(width: 20, height: 20).background(Circle().fill(Theme.onCTA.opacity(0.1)))
                        }
                        .foregroundStyle(Theme.onCTA)
                        .padding(.leading, 14).padding(.trailing, 4).frame(height: 28)
                        .background(Capsule().fill(Theme.cta))
                    }
                    .buttonStyle(PressStyle())
                    .disabled(trimmed.isEmpty)
                    .opacity(trimmed.isEmpty ? 0.5 : 1)
                }
            }
            .padding(12)
        }
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        onSave(trimmed, style)
    }
}

// MARK: A home

/// One home: what it's using now and today, its biggest users, and everything in it.
struct HomeDetail: View {
    @EnvironmentObject var store: HomeStore
    @ObservedObject private var list = HomeList.shared
    @ObservedObject private var gadgetList = GadgetStore.shared
    @ObservedObject var feed: HomesFeed
    let home: Home
    /// The demo home holds every device in its sample store.
    var demo = false
    let back: () -> Void
    @State private var editing = false
    @State private var linking = false

    var body: some View {
        let live = list.homes.first { $0.id == home.id } ?? home
        let energy = HomeEnergy(home: live, store: store, list: list, gadgets: demo ? [] : gadgetList.gadgets, everything: demo)
        VStack(alignment: .leading, spacing: 14) {
            SubpageHeader(eyebrow: demo ? "Demo home" : live.isMain ? "Main home" : "Home", title: live.name, back: back) {
                if !demo && !linking {
                    Button { withAnimation(.glide) { editing.toggle() } } label: {
                        Image(systemName: editing ? "xmark" : "pencil").font(.system(size: 12, weight: .medium))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Theme.fg.opacity(0.06)).overlay(Circle().strokeBorder(Theme.hairline)))
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel(editing ? "Stop editing" : "Edit home")
                }
            }

            if editing {
                HomeEditor(home: live, onSave: { name, style in
                    var h = live
                    h.name = name
                    h.style = style
                    list.update(h)
                    withAnimation(.glide) { editing = false }
                }, onCancel: {
                    withAnimation(.glide) { editing = false }
                }, onDelete: live.isMain ? nil : {
                    list.remove(live.id)
                    back()
                })
                .transition(.opacity)
            }

            if linking {
                HomeLinker(home: live) { withAnimation(.glide) { linking = false } }
                    .transition(.opacity)
            } else {
                HomeTotals(energy: energy, today: feed.today(energy), demo: demo)
                if !energy.users.isEmpty {
                    BiggestUsers(energy: energy, feed: feed)
                }
                HomeContents(energy: energy, feed: feed)
                if !demo {
                    Button { withAnimation(.glide) { linking = true } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "link").font(.system(size: 12, weight: .semibold))
                            Text("Link devices").font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.fg.opacity(0.07))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline)))
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
        .task(id: store.status == .connected) {
            guard store.status == .connected else { return }
            await feed.refresh(store, list: list)
        }
    }
}

/// Now and today, and how much of the house's use the devices that report power account for.
private struct HomeTotals: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let energy: HomeEnergy
    let today: Double?
    let demo: Bool

    var body: some View {
        let now = energy.nowWatts
        Bezel(radius: 24, inset: 4, lit: (now ?? 0) > 0, tint: HomeArt.light) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    HomeArt(style: energy.home.style, glow: HomeArt.glow(for: now), size: 76)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(now.map(EnergyUnits.power) ?? "No live reading")
                            .font(.system(size: now == nil ? 20 : 30, weight: .semibold)).monospacedDigit()
                            .contentTransition(reduceMotion ? .opacity : .numericText(value: now ?? 0))
                            .animation(reduceMotion ? nil : .easeInOut(duration: HomeEnergyPresentation.animationDuration), value: now)
                        Text(energy.houseWatts != nil ? "The whole house, now" : "Using now").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(today.map(EnergyUnits.energy) ?? "No total")
                            .font(.system(size: 16, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(today == nil ? Theme.muted : Theme.ink)
                        Text("Today").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                }
                if let house = energy.houseWatts, let seen = energy.devicesWatts, house > 0 {
                    let share = HomeEnergyPresentation.share(watts: seen, total: house)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Devices you can see add up to \(EnergyUnits.power(seen)) of \(EnergyUnits.power(house))")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
                        ShareBar(value: share, tint: HomeArt.light)
                    }
                }
                if now == nil && !demo {
                    Text(today == nil
                         ? "Nothing in this home reports its power yet. Smart plugs, and devices that measure their own use, add up here once they're in Home Assistant."
                         : "Nothing here reports live power yet, so there's only today's total. Smart plugs, and devices that measure their own use, show up live once they're in Home Assistant.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A slim bar showing a share of a whole.
struct ShareBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Double
    var tint: Color = HomeArt.light

    var body: some View {
        let fraction = HomeEnergyPresentation.fraction(value)
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fg.opacity(0.07))
                Capsule().fill(LinearGradient(colors: [tint, tint.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: HomeEnergyPresentation.barWidth(available: Double(g.size.width), fraction: fraction))
            }
        }
        .frame(height: 5)
        .animation(reduceMotion ? nil : .easeInOut(duration: HomeEnergyPresentation.animationDuration), value: fraction)
        .accessibilityHidden(true)
    }
}

/// The devices drawing the most right now, with their share of the total.
private struct BiggestUsers: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let energy: HomeEnergy
    @ObservedObject var feed: HomesFeed

    var body: some View {
        let total = energy.nowWatts ?? energy.devicesWatts ?? 1
        let users = Array(energy.users.prefix(6))
        VStack(alignment: .leading, spacing: 8) {
            Text("BIGGEST USERS RIGHT NOW").eyebrow().padding(.leading, 4)
            Bezel(radius: 20, inset: 3) {
                VStack(spacing: 0) {
                    ForEach(Array(users.enumerated()), id: \.element.id) { i, u in
                        HStack(spacing: 11) {
                            DeviceArtView(kind: u.device.kind, active: true, accent: u.device.accent, size: 30)
                                .frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(u.device.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    Spacer(minLength: 6)
                                    Text(EnergyUnits.power(u.watts)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                                        .contentTransition(reduceMotion ? .opacity : .numericText(value: u.watts))
                                        .animation(reduceMotion ? nil : .easeInOut(duration: HomeEnergyPresentation.animationDuration), value: u.watts)
                                        .frame(width: 70, alignment: .trailing)
                                }
                                ShareBar(value: HomeEnergyPresentation.share(watts: u.watts, total: total))
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .overlay(alignment: .top) {
                            if i > 0 { Divider().overlay(Theme.hairline).padding(.leading, 52) }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(u.device.name), \(EnergyUnits.power(u.watts))")
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: HomeEnergyPresentation.animationDuration), value: users.map(\.id))
            }
        }
    }
}

/// Everything in the home, grouped by what it is.
private struct HomeContents: View {
    let energy: HomeEnergy
    @ObservedObject var feed: HomesFeed

    static func group(_ kind: DeviceKind) -> String {
        switch kind {
        case .airConditioner, .fridge: "Appliances"
        case .indoorCamera, .outdoorCamera, .doorbell, .securityHub, .securityHubPro: "Security"
        case .smartSpeaker, .speakerGroup, .meshSpeaker, .streamingBox, .tv: "Entertainment"
        case .printer3D, .gameConsole, .computer, .router, .phone: "Gadgets"
        case .electricCar, .evCharger, .robotVacuum, .lawnMower, .aircraft, .robot: "Vehicles"
        case .inverter, .battery, .solarPanel: "Energy"
        case .generic: "Other"
        }
    }

    static let order = ["Appliances", "Energy", "Vehicles", "Gadgets", "Entertainment", "Security", "Other"]

    var body: some View {
        let groups = Dictionary(grouping: energy.devices) { Self.group($0.kind) }
        let watts = Dictionary(uniqueKeysWithValues: energy.users.map { ($0.device.id, $0.watts) })
        VStack(alignment: .leading, spacing: 8) {
            let count = energy.devices.count + energy.gadgets.count
            Text("IN THIS HOME · \(count)").eyebrow().padding(.leading, 4)
            if count == 0 {
                Text("No devices here yet. Link some below.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
            }
            ForEach(Self.order, id: \.self) { name in
                if let list = groups[name], !list.isEmpty {
                    group(name, rows: list.map { d in
                        Row(id: d.id, kind: d.kind, accent: d.accent, name: d.name,
                            value: watts[d.id].map(EnergyUnits.power) ?? feed.deviceToday(energy, d.id).map { "\(EnergyUnits.energy($0)) today" },
                            detail: d.summary)
                    })
                }
            }
            if !energy.gadgets.isEmpty {
                group("Added by hand", rows: energy.gadgets.map { g in
                    Row(id: g.id.uuidString, kind: g.kind.art, accent: HomeDevice.gadgetAccent(g.kind.art), name: g.name, value: nil, detail: g.kind.title)
                })
            }
        }
    }

    struct Row: Identifiable {
        let id: String
        let kind: DeviceKind
        let accent: Color
        let name: String
        let value: String?
        let detail: String
    }

    private func group(_ title: String, rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted).padding(.leading, 4)
            Bezel(radius: 18, inset: 3) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                        if i > 0 { Divider().overlay(Theme.hairline).padding(.leading, 48) }
                        HStack(spacing: 10) {
                            DeviceArtView(kind: r.kind, active: true, accent: r.accent, size: 26).frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Text(r.detail).font(.system(size: 11.5)).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            if let v = r.value {
                                Text(v).font(.system(size: 12.5, weight: .semibold)).monospacedDigit().foregroundStyle(HomeArt.light)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

// MARK: Linking devices

/// Every device and hand-added gadget, with a tick for the ones in this home. A device lives in
/// one home, so ticking it here moves it from wherever it was.
private struct HomeLinker: View {
    @EnvironmentObject var store: HomeStore
    @ObservedObject private var list = HomeList.shared
    @ObservedObject private var gadgets = GadgetStore.shared
    let home: Home
    let done: () -> Void
    @State private var search = ""

    private struct Item: Identifiable {
        let id: String
        let name: String
        let kind: DeviceKind
        let accent: Color
        let detail: String
    }

    var body: some View {
        let items = all.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Link devices").font(.system(size: 15, weight: .semibold))
                    Text(home.isMain ? "Anything not in another home is here. Tick something to bring it back."
                         : "Tick what's in \(home.name). Each device lives in one home.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(action: done) {
                    Text("Done").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.onCTA)
                        .padding(.horizontal, 14).frame(height: 28).background(Capsule().fill(Theme.cta))
                }
                .buttonStyle(PressStyle())
            }
            HearthField(label: "Search devices", placeholder: "Search devices", text: $search)
            Bezel(radius: 18, inset: 3) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        if i > 0 { Divider().overlay(Theme.hairline).padding(.leading, 48) }
                        row(item)
                    }
                    if items.isEmpty {
                        Text("Nothing matches.").font(.system(size: 12)).foregroundStyle(Theme.muted).padding(14)
                    }
                }
            }
        }
    }

    private var all: [Item] {
        let devices = store.devices.values.filter { !$0.isService }.compactMap { store.homeDevice($0.id) }
            .filter { !$0.entities.isEmpty }
            .map { Item(id: $0.id, name: $0.name, kind: $0.kind, accent: $0.accent, detail: $0.kind.title) }
        let manual = gadgets.gadgets.map {
            Item(id: $0.id.uuidString, name: $0.name, kind: $0.kind.art, accent: HomeDevice.gadgetAccent($0.kind.art), detail: "\($0.kind.title), added by hand")
        }
        return (devices + manual).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func row(_ item: Item) -> some View {
        let owner = list.home(of: item.id)
        let here = owner.id == home.id
        // The main home can't let go of a device: it would have nowhere to live.
        let locked = here && home.isMain
        return Button {
            list.link(item.id, to: here ? list.main.id : home.id)
        } label: {
            HStack(spacing: 10) {
                DeviceArtView(kind: item.kind, active: true, accent: item.accent, size: 26).frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(here ? item.detail : "\(item.detail) · in \(owner.name)").font(.system(size: 11.5)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: here ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(here ? (locked ? Theme.muted : HomeArt.light) : Theme.faint)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(locked)
        .accessibilityLabel("\(item.name), \(here ? "in this home" : "in \(owner.name)")")
        .accessibilityAddTraits(here ? .isSelected : [])
    }
}

// MARK: On the Energy page

/// The home's use on the Energy page: now, today, and the biggest users. In a demo it's the demo home.
struct HomeUseCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var store: HomeStore
    @ObservedObject private var list = HomeList.shared
    @ObservedObject private var gadgets = GadgetStore.shared
    @StateObject private var feed = HomesFeed()
    @AppStorage("energy.home") private var chosen = ""
    let visible: Bool

    var body: some View {
        let demo = store.isDemo
        let home = demo ? Home(name: "Demo home", isMain: true)
            : list.homes.first { $0.id.uuidString == chosen } ?? list.main
        let energy = HomeEnergy(home: home, store: store, list: list, gadgets: demo ? [] : gadgets.gadgets, everything: demo)
        let today = feed.today(energy)
        Group {
            if energy.hasReadings || today != nil {
                card(home: home, energy: energy, today: today, demo: demo)
            }
        }
        .task(id: visible && store.status == .connected) {
            guard visible, store.status == .connected else { return }
            while !Task.isCancelled {
                await feed.refresh(store, list: list, force: true)
                try? await Task.sleep(for: .seconds(demo ? 20 : 300))
            }
        }
    }

    private func card(home: Home, energy: HomeEnergy, today: Double?, demo: Bool) -> some View {
            Bezel(radius: 24, inset: 4, lit: (energy.nowWatts ?? 0) > 0, tint: HomeArt.light) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        HomeArt(style: home.style, glow: HomeArt.glow(for: energy.nowWatts), size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("HOME USE").eyebrow()
                                if !demo && list.homes.count > 1 {
                                    Button {
                                        PopupMenu.show(list.homes.map(\.id.uuidString), selected: home.id.uuidString,
                                                       label: { id in list.homes.first { $0.id.uuidString == id }?.name ?? id }) { chosen = $0 }
                                    } label: {
                                        HStack(spacing: 3) {
                                            Text(home.name).font(.system(size: 11.5, weight: .semibold))
                                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 8.5, weight: .semibold))
                                        }
                                        .foregroundStyle(Theme.muted)
                                    }
                                    .buttonStyle(PressStyle())
                                    .accessibilityLabel("Home: \(home.name)")
                                }
                            }
                            Text(energy.nowWatts.map(EnergyUnits.power) ?? "No reading now")
                                .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                                .contentTransition(reduceMotion ? .opacity : .numericText(value: energy.nowWatts ?? 0))
                                .animation(reduceMotion ? nil : .easeInOut(duration: HomeEnergyPresentation.animationDuration), value: energy.nowWatts)
                        }
                        Spacer(minLength: 0)
                        if let today {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(EnergyUnits.energy(today)).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                                Text("Today").font(.system(size: 12)).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    if !energy.users.isEmpty {
                        let total = energy.nowWatts ?? 1
                        VStack(spacing: 8) {
                            ForEach(energy.users.prefix(3)) { u in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(u.device.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                                        Spacer()
                                        Text(EnergyUnits.power(u.watts)).font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                                            .contentTransition(reduceMotion ? .opacity : .numericText(value: u.watts))
                                            .animation(reduceMotion ? nil : .easeInOut(duration: HomeEnergyPresentation.animationDuration), value: u.watts)
                                            .frame(width: 68, alignment: .trailing)
                                    }
                                    ShareBar(value: HomeEnergyPresentation.share(watts: u.watts, total: total))
                                }
                            }
                        }
                        .animation(reduceMotion ? nil : .easeInOut(duration: HomeEnergyPresentation.animationDuration), value: Array(energy.users.prefix(3)).map(\.id))
                        if let house = energy.houseWatts, let seen = energy.devicesWatts {
                            Text("Devices you can see add up to \(EnergyUnits.power(seen)) of \(EnergyUnits.power(house)).")
                                .font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                    }
                }
                .padding(14)
            }
    }
}
