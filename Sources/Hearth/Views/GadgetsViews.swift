import Network
import SwiftUI

// MARK: Gadgets added by hand

/// Something the user lists themselves, whether or not Home Assistant knows about it.
struct Gadget: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case printer, console, computer, other
        case car, aircraft, robot

        /// The kinds each page offers when adding by hand.
        static let gadgetKinds: [Kind] = [.printer, .console, .computer, .other]
        static let vehicleKinds: [Kind] = [.car, .aircraft, .robot]

        var title: String {
            switch self {
            case .printer: "Printer"
            case .console: "Console"
            case .computer: "Computer"
            case .other: "Other"
            case .car: "Car"
            case .aircraft: "Aircraft"
            case .robot: "Robot"
            }
        }

        var symbol: String {
            switch self {
            case .printer: "cube"
            case .console: "gamecontroller"
            case .computer: "desktopcomputer"
            case .other: "ellipsis.circle"
            case .car: "car.side"
            case .aircraft: "airplane"
            case .robot: "figure.walk"
            }
        }

        var art: DeviceKind {
            switch self {
            case .printer: .printer3D
            case .console: .gameConsole
            case .computer: .computer
            case .other: .generic
            case .car: .electricCar
            case .aircraft: .aircraft
            case .robot: .robot
            }
        }

        /// Ports each kind usually listens on: a printer's MQTT and FTPS, a console's
        /// remote play, a computer's SSH, file sharing and screen sharing.
        var ports: [UInt16] {
            switch self {
            case .printer: [8883, 990]
            case .console: [9295, 997]
            case .computer: [22, 445, 5900, 548]
            case .other, .car, .aircraft: [80, 443]
            case .robot: [80, 443, 22]
            }
        }
    }

    var id = UUID()
    var name: String
    var kind: Kind
    var host = ""

    var address: String? {
        let h = host.trimmingCharacters(in: .whitespaces)
        return h.isEmpty ? nil : h
    }
}

/// Whether a gadget answered on the network.
enum Reach: Equatable { case unknown, checking, online, offline }

/// The hand-made list, kept in Application Support, and whether each one is on.
@MainActor
final class GadgetStore: ObservableObject {
    static let shared = GadgetStore()

    @Published private(set) var gadgets: [Gadget] = []
    @Published private(set) var reach: [UUID: Reach] = [:]
    private let file: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hearth", isDirectory: true)
        // Development: `-gadgetsFile <path>` uses another list, so tests never touch yours.
        file = UserDefaults.standard.string(forKey: "gadgetsFile").map { URL(fileURLWithPath: $0) }
            ?? base.appendingPathComponent("gadgets.json")
        if let data = try? Data(contentsOf: file), let list = try? JSONDecoder().decode([Gadget].self, from: data) {
            gadgets = list
        }
    }

    func save(_ gadget: Gadget) {
        if let i = gadgets.firstIndex(where: { $0.id == gadget.id }) {
            gadgets[i] = gadget
        } else {
            gadgets.append(gadget)
        }
        reach[gadget.id] = nil
        write()
        Task { await check(gadget) }
    }

    func remove(_ id: UUID) {
        gadgets.removeAll { $0.id == id }
        reach[id] = nil
        write()
    }

    func checkAll(_ kinds: [Gadget.Kind] = Gadget.Kind.gadgetKinds) async {
        await withTaskGroup(of: Void.self) { group in
            for g in gadgets where g.address != nil && kinds.contains(g.kind) {
                group.addTask { await self.check(g) }
            }
        }
    }

    func check(_ gadget: Gadget) async {
        guard let host = gadget.address else { return }
        if reach[gadget.id] == nil || reach[gadget.id] == .unknown { reach[gadget.id] = .checking }
        let answered = await Knock.answers(host: host, ports: gadget.kind.ports)
        // It may have been deleted or changed while we waited.
        guard gadgets.first(where: { $0.id == gadget.id })?.address == host else { return }
        reach[gadget.id] = answered ? .online : .offline
    }

    private func write() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(gadgets).write(to: file, options: .atomic)
    }
}

/// A quick knock on a few TCP ports. A refusal counts as an answer: something is there,
/// that port is just closed.
enum Knock {
    static func answers(host: String, ports: [UInt16], timeout: TimeInterval = 1.5) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            for port in ports {
                group.addTask { await answers(host: host, port: port, timeout: timeout) }
            }
            for await ok in group where ok {
                group.cancelAll()
                return true
            }
            return false
        }
    }

    static func answers(host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        return await withCheckedContinuation { cont in
            // Every callback runs on this one queue, so the flag needs no lock.
            let queue = DispatchQueue(label: "hearth.knock")
            let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            let once = Once()
            @Sendable func finish(_ ok: Bool) {
                guard !once.done else { return }
                once.done = true
                connection.stateUpdateHandler = nil
                connection.cancel()
                cont.resume(returning: ok)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(true)
                case .waiting(let error), .failed(let error):
                    if case .posix(.ECONNREFUSED) = error {
                        finish(true)
                    } else if case .failed = state {
                        finish(false)
                    }
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
    }

    private final class Once: @unchecked Sendable { var done = false }
}

// MARK: Page

/// 3D printers, consoles and computers: the ones Home Assistant knows, then the ones
/// listed by hand.
struct GadgetsPage: View {
    @EnvironmentObject var store: HomeStore
    @ObservedObject private var list = GadgetStore.shared
    let shown: Bool
    /// False while the menu bar panel is closed, so the network checks rest.
    let visible: Bool
    @Binding var openDevice: String?
    @State private var editing: UUID?
    @State private var adding = false
    /// In a demo, only the sample devices show: nothing from your own list, and nothing to add.
    @Environment(\.sectionChrome) private var chrome
    private var demo: Bool { chrome?.demoOn == true }

    private static let kinds: [DeviceKind] = [.printer3D, .gameConsole, .computer]

    private var fromHome: [HomeDevice] {
        store.devices.values
            .filter { !$0.isService }
            .compactMap { store.homeDevice($0.id) }
            .filter { Self.kinds.contains($0.kind) && !$0.entities.isEmpty }
            .sorted {
                let a = Self.kinds.firstIndex(of: $0.kind) ?? 0, b = Self.kinds.firstIndex(of: $1.kind) ?? 0
                return a != b ? a < b : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    var body: some View {
        ScreenFlow(route: openDevice, depth: openDevice == nil ? 0 : 1) { deviceID in
            if let id = deviceID {
                DeviceDetail(deviceID: id) { openDevice = nil }.id(id)
            } else {
                overview
            }
        }
        .task(id: visible) {
            guard visible else { return }
            while !Task.isCancelled {
                await list.checkAll()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private var overview: some View {
        let home = fromHome
        let printers = home.filter { $0.kind == .printer3D }
        let others = home.filter { $0.kind != .printer3D }
        let manual = demo ? [] : list.gadgets.filter { Gadget.Kind.gadgetKinds.contains($0.kind) }
        let online = home.filter(\.online).count + manual.filter { list.reach[$0.id] == .online }.count
        let total = home.count + manual.count
        return VStack(alignment: .leading, spacing: 14) {
            PageHeader(eyebrow: total == 0 ? "Printers, consoles, computers" : "\(total) gadget\(total == 1 ? "" : "s") · \(online) online",
                       title: "Gadgets", pinnedIllustrations: [.printer3D, .gameConsole, .computer]) {
                if !demo {
                    Button {
                        withAnimation(.glide) {
                            editing = nil
                            adding.toggle()
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .light))
                            .rotationEffect(.degrees(adding ? 45 : 0))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Theme.fg.opacity(0.05)).overlay(Circle().strokeBorder(Theme.hairline)))
                    }
                    .buttonStyle(PressStyle())
                    .help(adding ? "Cancel" : "Add a gadget by hand")
                }
            }
            .reveal(shown, 0)

            if adding {
                GadgetEditor(gadget: nil) { g in
                    list.save(g)
                    withAnimation(.glide) { adding = false }
                } onCancel: {
                    withAnimation(.glide) { adding = false }
                }
                .transition(.dissolve)
            }

            if !printers.isEmpty {
                Text(printers.count == 1 ? "PRINTER" : "PRINTERS").eyebrow().padding(.leading, 4).reveal(shown, 1)
                ForEach(Array(printers.enumerated()), id: \.element.id) { i, p in
                    PrinterCard(device: p) { open(p.id) }.reveal(shown, 1 + i)
                }
            }

            if !others.isEmpty {
                Text(demo ? "CONSOLES AND COMPUTERS" : "FROM HOME ASSISTANT").eyebrow().padding(.leading, 4).reveal(shown, 2)
                VStack(spacing: 8) {
                    ForEach(others) { d in
                        DeviceCard(device: d) { open(d.id) }
                    }
                }
                .reveal(shown, 3)
            }

            if !manual.isEmpty {
                Text("ADDED BY HAND").eyebrow().padding(.leading, 4).reveal(shown, 4)
                VStack(spacing: 8) {
                    ForEach(manual) { g in
                        if editing == g.id {
                            GadgetEditor(gadget: g) { changed in
                                list.save(changed)
                                withAnimation(.glide) { editing = nil }
                            } onCancel: {
                                withAnimation(.glide) { editing = nil }
                            } onDelete: {
                                withAnimation(.glide) {
                                    list.remove(g.id)
                                    editing = nil
                                }
                            }
                            .transition(.dissolve)
                        } else {
                            ManualGadgetRow(gadget: g, reach: list.reach[g.id] ?? .unknown) {
                                withAnimation(.glide) {
                                    adding = false
                                    editing = g.id
                                }
                            }
                            .transition(.dissolve)
                        }
                    }
                }
                .reveal(shown, 5)
            }

            if home.isEmpty {
                ConnectGuide(steps: Self.howTo, note: "Anything else, like a console that isn't in Home Assistant, you can list by hand.",
                             showsAdd: manual.isEmpty && !adding) {
                    withAnimation(.glide) { adding = true }
                }
                .reveal(shown, 6)
            }
        }
        .animation(.glide, value: adding)
        .animation(.glide, value: editing)
        .animation(.glide, value: manual)
    }

    private func open(_ id: String) { withAnimation(.glide) { openDevice = id } }

    static let howTo: [ConnectGuide.Step] = [
        .init(kind: .printer3D, title: "Bambu Lab printers",
              detail: "Add Bambu Lab from HACS, then sign in with your Bambu account. Prints, progress and temperatures show up here."),
        .init(kind: .gameConsole, title: "PlayStation",
              detail: "Add the PlayStation Network integration in Home Assistant to see when your console is on and what's playing."),
        .init(kind: .computer, title: "Mac", detail: "Install the Home Assistant app on your Mac and turn on its sensors."),
    ]
}

// MARK: 3D printer

/// What a Bambu Lab printer (through the ha-bambulab integration) is up to.
struct PrintJob {
    let progress: Double?
    let status: String?
    let stage: String?
    let remainingMinutes: Double?
    let nozzle: String?
    let bed: String?
    let cover: Entity?
    let camera: Entity?

    init(_ device: HomeDevice) {
        func ending(_ key: String) -> Entity? {
            device.entities.first { ($0.id.hasSuffix("_" + key) || $0.id.hasSuffix("." + key)) && !$0.isUnavailable }
        }
        progress = ending("print_progress").flatMap { Double($0.state) }.map { min(max($0 / 100, 0), 1) }
        status = ending("print_status")?.state.lowercased()
        stage = ending("current_stage")?.state.lowercased()
        remainingMinutes = ending("remaining_time").flatMap { e -> Double? in
            guard let v = Double(e.state) else { return nil }
            switch e.str("unit_of_measurement") ?? "min" {
            case "h": return v * 60
            case "s": return v / 60
            case "d": return v * 1440
            default: return v
            }
        }
        func temperature(_ key: String) -> String? {
            ending(key).flatMap { e in Double(e.state).map { "\(Int($0.rounded()))°" } }
        }
        nozzle = temperature("nozzle_temperature")
        bed = temperature("bed_temperature")
        cover = device.entities.first { $0.domain == "image" && $0.id.hasSuffix("cover_image") }
        camera = device.first("camera")
    }

    var isPrinting: Bool {
        if let status { return ["running", "prepare", "slicing", "pause"].contains(status) }
        if let stage, !["idle", "unknown"].contains(stage), let progress { return progress < 1 }
        return false
    }

    var isPaused: Bool { status == "pause" || stage?.contains("pause") == true }

    var summary: String {
        let percent = progress.map { "\(Int(($0 * 100).rounded()))%" }
        if isPaused { return percent.map { "Paused at \($0)" } ?? "Paused" }
        if isPrinting { return percent.map { "Printing, \($0)" } ?? "Printing" }
        switch status {
        case "finish": return "Finished"
        case "failed": return "Print failed"
        case "offline": return "Offline"
        default: return "Idle"
        }
    }

    /// The stage in plain words, when it says more than "printing".
    var stageText: String? {
        guard let stage, !["printing", "idle", "unknown", "none"].contains(stage) else { return nil }
        return stage.replacingOccurrences(of: "_", with: " ").firstCapitalOnly
    }

    var timeLeft: String? {
        guard isPrinting, let m = remainingMinutes, m > 0 else { return nil }
        let total = Int(m.rounded())
        let h = total / 60, min = total % 60
        return h > 0 ? "\(h) h \(min) min left" : "\(min) min left"
    }
}

private extension String {
    /// "Auto Bed Leveling" to "Auto bed leveling".
    var firstCapitalOnly: String { prefix(1).uppercased() + dropFirst().lowercased() }
}

struct PrinterCard: View {
    @EnvironmentObject var store: HomeStore
    let device: HomeDevice
    let action: () -> Void

    var body: some View {
        let job = PrintJob(device)
        let tint = device.accent
        Button(action: action) {
            Bezel(radius: 24, inset: 4, lit: device.online && job.isPrinting, tint: tint) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        thumbnail(job, tint: tint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(device.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                            HStack(spacing: 5) {
                                PulseDot(color: device.online ? (job.isPrinting ? tint : Theme.ok) : Theme.live, size: 5,
                                         live: device.online && job.isPrinting)
                                Text(device.online ? job.summary : "Offline")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(device.online ? Theme.ink : Theme.live)
                            }
                            if let detail = [job.stageText, job.timeLeft].compactMap({ $0 }).first {
                                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Text([device.info.manufacturer, device.info.model].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.faint).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.faint)
                    }

                    if job.isPrinting, let progress = job.progress {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressTrack(value: progress, tint: tint)
                            HStack {
                                Text("\(Int((progress * 100).rounded()))%").font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                                Spacer()
                                if let left = job.timeLeft {
                                    Text(left).font(.system(size: 12)).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                    }

                    if job.nozzle != nil || job.bed != nil {
                        HStack(spacing: 8) {
                            if let n = job.nozzle { reading("flame", "Nozzle", n) }
                            if let b = job.bed { reading("square.3.layers.3d.down.right", "Bed", b) }
                        }
                    }
                }
                .padding(12)
            }
        }
        .buttonStyle(PressStyle())
        .task(id: job.cover?.state) {
            if let cover = job.cover { _ = await store.image(cover.id) }
        }
    }

    @ViewBuilder
    private func thumbnail(_ job: PrintJob, tint: Color) -> some View {
        if let cover = job.cover, let image = store.snapshots[cover.id] {
            Image(nsImage: image)
                .resizable().aspectRatio(contentMode: .fit)
                .padding(6)
                .frame(width: 60, height: 60)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.fg.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.75))
        } else {
            DeviceArtView(kind: .printer3D, active: device.online, accent: tint, size: 60)
        }
    }

    private func reading(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11.5, weight: .light)).foregroundStyle(Theme.muted)
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
            Spacer(minLength: 4)
            Text(value).font(.system(size: 13, weight: .semibold)).monospacedDigit()
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(Theme.fg.opacity(0.05)).overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.75)))
    }
}

/// A slim progress track that glows where it's filled.
struct ProgressTrack: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fg.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, geo.size.width * value))
                    .glow(color: tint.opacity(0.5), radius: 5)
            }
        }
        .frame(height: 6)
        .animation(.glide, value: value)
    }
}

// MARK: Hand-made rows

struct ManualGadgetRow: View {
    let gadget: Gadget
    let reach: Reach
    let edit: () -> Void

    var body: some View {
        let on = reach == .online
        let tint = HomeDevice.gadgetAccent(gadget.kind.art)
        Button(action: edit) {
            Bezel(radius: 22, inset: 3, lit: on, tint: tint) {
                HStack(spacing: 12) {
                    DeviceArtView(kind: gadget.kind.art, active: on || gadget.address == nil, accent: tint, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(gadget.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        HStack(spacing: 5) {
                            if gadget.address != nil {
                                PulseDot(color: dotColor, size: 5, live: reach == .checking || on)
                            }
                            Text(status).font(.system(size: 12.5)).foregroundStyle(reach == .offline ? Theme.live : Theme.muted)
                        }
                        Text([gadget.kind.title, gadget.address].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.faint).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "pencil").font(.system(size: 12.5, weight: .light)).foregroundStyle(Theme.faint)
                }
                .padding(10)
            }
        }
        .buttonStyle(PressStyle())
        .help("Edit")
    }

    private var status: String {
        guard gadget.address != nil else { return "On your list" }
        switch reach {
        case .online: return "Online"
        case .offline: return "Not answering"
        case .checking, .unknown: return "Checking"
        }
    }

    private var dotColor: Color {
        switch reach {
        case .online: Theme.ok
        case .offline: Theme.live
        case .checking, .unknown: Theme.sand
        }
    }
}

/// Adds or edits a gadget in place, inside the panel.
struct GadgetEditor: View {
    let gadget: Gadget?
    /// The kinds to choose from, and what to call the thing in the title.
    var kinds: [Gadget.Kind] = Gadget.Kind.gadgetKinds
    var noun = "gadget"
    let onSave: (Gadget) -> Void
    let onCancel: () -> Void
    var onDelete: (() -> Void)?
    @State private var name: String
    @State private var kind: Gadget.Kind
    @State private var host: String
    /// Which home it's in, when there's more than one.
    @ObservedObject private var homes = HomeList.shared
    @State private var homeID: UUID

    init(gadget: Gadget?, kinds: [Gadget.Kind] = Gadget.Kind.gadgetKinds, noun: String = "gadget",
         onSave: @escaping (Gadget) -> Void, onCancel: @escaping () -> Void, onDelete: (() -> Void)? = nil) {
        _homeID = State(initialValue: gadget.map { HomeList.shared.home(of: $0.id.uuidString).id } ?? HomeList.shared.main.id)
        self.gadget = gadget
        self.kinds = kinds
        self.noun = noun
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
        _name = State(initialValue: gadget?.name ?? "")
        _kind = State(initialValue: gadget?.kind ?? kinds.first ?? .other)
        _host = State(initialValue: gadget?.host ?? "")
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        Bezel(radius: 24, inset: 4, lit: true, tint: HomeDevice.gadgetAccent(kind.art)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    DeviceArtView(kind: kind.art, active: true, accent: HomeDevice.gadgetAccent(kind.art), size: 40)
                        .animation(.glide, value: kind)
                    Text(gadget == nil ? "Add a \(noun)" : "Edit \(gadget!.name)")
                        .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Spacer()
                }

                LabeledField(label: "Name", placeholder: kind.namePlaceholder, text: $name, onSubmit: save)

                Segmented(options: kinds, selected: kind, tint: HomeDevice.gadgetAccent(kind.art), id: "gadget-kind",
                          compact: true) { k in
                    Image(systemName: k.symbol).font(.system(size: 12.5, weight: .light))
                    Text(k.title).font(.system(size: 11, weight: .semibold))
                } onSelect: { kind = $0 }

                LabeledField(label: "Address (optional)", placeholder: "192.168.1.20 or \(kind.rawValue).local", text: $host, onSubmit: save)
                Text("With an address, Hearth knocks on it every minute while the panel is open to see if it's on.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if homes.homes.count > 1 {
                    HStack {
                        Text("Home").font(.system(size: 13, weight: .medium))
                        Spacer()
                        Button {
                            PopupMenu.show(homes.homes.map(\.id.uuidString), selected: homeID.uuidString,
                                           label: { id in homes.homes.first { $0.id.uuidString == id }?.name ?? id }) { id in
                                if let uuid = UUID(uuidString: id) { homeID = uuid }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: homes.homes.first { $0.id == homeID }?.style.symbol ?? "house").font(.system(size: 11.5))
                                Text(homes.homes.first { $0.id == homeID }?.name ?? "Home").font(.system(size: 13, weight: .medium))
                                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.muted)
                            }
                            .padding(.horizontal, 10).frame(height: 28)
                            .background(Capsule().fill(Theme.fg.opacity(0.07)))
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Home: \(homes.homes.first { $0.id == homeID }?.name ?? "Home")")
                    }
                }

                HStack(spacing: 14) {
                    if let onDelete {
                        Button("Delete", action: onDelete)
                            .buttonStyle(PressStyle())
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.live)
                    }
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .buttonStyle(PressStyle())
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    Button(action: save) {
                        HStack(spacing: 8) {
                            Text(gadget == nil ? "Add" : "Save").font(.system(size: 13, weight: .semibold))
                            Image(systemName: "checkmark").font(.system(size: 10.5, weight: .bold))
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(Theme.onCTA.opacity(0.1)))
                        }
                        .foregroundStyle(Theme.onCTA)
                        .padding(.leading, 14).padding(.trailing, 4)
                        .frame(height: 28)
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
        var g = gadget ?? Gadget(name: trimmed, kind: kind)
        g.name = trimmed
        g.kind = kind
        g.host = host.trimmingCharacters(in: .whitespaces)
        onSave(g)
        if homes.homes.count > 1 || homes.home(of: g.id.uuidString).id != homeID {
            homes.link(g.id.uuidString, to: homeID)
        }
    }
}

// MARK: Getting started

/// How to bring things in through Home Assistant, and the way to list anything else by hand.
struct ConnectGuide: View {
    struct Step {
        let kind: DeviceKind
        let title: String
        let detail: String
    }

    let steps: [Step]
    let note: String
    let showsAdd: Bool
    let add: () -> Void

    /// What the demo shows, for the invitation above the steps.
    var demoMessage = "See how it looks and moves with sample devices first."

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TryDemoCard(message: demoMessage).padding(.bottom, 4)
            Text("CONNECT THROUGH HOME ASSISTANT").eyebrow().padding(.leading, 4)
            Bezel(radius: 22, inset: 3) {
                VStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 12) {
                            DeviceBadge(kind: step.kind, accent: HomeDevice.gadgetAccent(step.kind), size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.title).font(.system(size: 13, weight: .semibold))
                                Text(step.detail).font(.system(size: 12)).foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .accessibilityElement(children: .combine)
                        if i < steps.count - 1 { Rectangle().fill(Theme.hairline).frame(height: 0.75).padding(.leading, 62) }
                    }
                }
            }
            if showsAdd {
                HStack(alignment: .center, spacing: 12) {
                    Text(note)
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(action: add) {
                        HStack(spacing: 8) {
                            Text("Add").font(.system(size: 13, weight: .semibold))
                            Image(systemName: "plus").font(.system(size: 10.5, weight: .bold))
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(Theme.onCTA.opacity(0.1)))
                        }
                        .foregroundStyle(Theme.onCTA)
                        .padding(.leading, 14).padding(.trailing, 4)
                        .frame(height: 28)
                        .background(Capsule().fill(Theme.cta))
                    }
                    .buttonStyle(PressStyle())
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }
        }
    }
}

extension HomeDevice {
    /// The light each gadget kind glows with, for gadgets that aren't Home Assistant devices.
    static func gadgetAccent(_ kind: DeviceKind) -> Color {
        switch kind {
        case .printer3D: Color.accent(1.0, 0.66, 0.42)
        case .gameConsole: Color.accent(0.42, 0.62, 1.0)
        case .computer: Color.accent(0.78, 0.84, 1.0)
        case _ where DeviceKind.vehicles.contains(kind): vehicleAccent(kind)
        default: Theme.sand
        }
    }
}

extension Gadget.Kind {
    /// An example name for the add form.
    var namePlaceholder: String {
        switch self {
        case .printer: "Workshop printer"
        case .console: "Living room PS5"
        case .computer: "Studio Mac mini"
        case .other: "Anything with a name"
        case .car: "My car"
        case .aircraft: "Electric jet"
        case .robot: "Garden robot"
        }
    }
}
