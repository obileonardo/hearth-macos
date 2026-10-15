import SwiftUI

// MARK: Panel page

/// The house in 3D in the panel: a live preview you can turn with a drag, what's using power,
/// and the way into the full map.
struct MapPage: View {
    @EnvironmentObject var store: HomeStore
    @Environment(\.hearthOpenWindow) private var openWindow
    @ObservedObject private var maps = HomeMapStore.shared
    @StateObject private var scene = MapSceneController(full: false)
    let shown: Bool
    let visible: Bool

    var body: some View {
        let loads = maps.pins.filter { MapPower.role(of: $0) == .load }
            .map { ($0, scene.watts[$0.id]) }
            .sorted { ($0.1 ?? -1) > ($1.1 ?? -1) }
        let total = loads.compactMap(\.1).reduce(0, +)

        VStack(alignment: .leading, spacing: 14) {
            PageHeader(eyebrow: eyebrow(total: total, count: maps.pins.count), title: "3D map",
                       pinnedIllustrations: maps.pins.prefix(3).map(\.art), pinnedCount: maps.pins.count,
                       pinnedSymbols: ["cube.transparent", "square.3.layers.3d", "bolt"]) {
                Button { maps.importScan() } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 13, weight: .regular))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Theme.fg.opacity(0.05)).overlay(Circle().strokeBorder(Theme.hairline)))
                }
                .buttonStyle(PressStyle())
                .help("Import a scan")
                .accessibilityLabel("Import a scan of your home")
            }
            .reveal(shown, 0)

            preview.reveal(shown, 1)

            if maps.isDemo {
                DemoNote(import: maps.importScan).reveal(shown, 2)
            } else if scene.loadFailed {
                Text("Hearth couldn't read this scan, so the demo house is showing. Try exporting it again as USDZ.")
                    .font(.system(size: 12)).foregroundStyle(Theme.live)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !loads.isEmpty {
                Text("USING POWER").eyebrow().padding(.leading, 4).reveal(shown, 3)
                Bezel(radius: 20, inset: 3) {
                    VStack(spacing: 0) {
                        ForEach(Array(loads.enumerated()), id: \.element.0.id) { i, item in
                            if i > 0 { Divider().overlay(Theme.hairline).padding(.leading, 52) }
                            PowerRow(pin: item.0, watts: item.1, total: total)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .reveal(shown, 4)
            }

            let sources = maps.pins.filter { MapPower.role(of: $0) == .source }
            if !sources.isEmpty {
                Text("SUPPLYING").eyebrow().padding(.leading, 4).reveal(shown, 5)
                Bezel(radius: 20, inset: 3) {
                    VStack(spacing: 0) {
                        ForEach(sources) { pin in PowerRow(pin: pin, watts: nil, total: 0, supplying: true) }
                    }
                    .padding(.vertical, 4)
                }
                .reveal(shown, 6)
            }

            MapsList().reveal(shown, 7)
        }
        .onAppear { scene.attach(store) }
        .onChange(of: visible && shown, initial: true) { _, on in scene.active = on }
        .onDisappear { scene.active = false }
    }

    private var preview: some View {
        ZStack(alignment: .bottom) {
            MapSceneView(controller: scene)
            VStack {
                HStack(spacing: 6) {
                    if maps.hasFloors {
                        FloorPicker(compact: true)
                    }
                    Spacer(minLength: 0)
                    ViewModePicker(compact: true)
                }
                HStack {
                    DragModePicker(scene: scene, compact: true)
                    Spacer(minLength: 0)
                }
                .padding(.top, 6)
                Spacer()
            }
            .padding(10)
            HStack {
                Text(maps.title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.1)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.base.opacity(0.88)).overlay(Capsule().strokeBorder(Theme.hairline)))
                Spacer()
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "map")
                } label: {
                    HStack(spacing: 6) {
                        Text("Open full map").font(.system(size: 12.5, weight: .semibold))
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(Theme.onCTA)
                    .padding(.horizontal, 12).frame(height: 28)
                    .background(Capsule().fill(Theme.cta))
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Open full map")
                .accessibilityHint("Opens the map in a separate window")
            }
            .padding(10)
        }
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.75))
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.fg.opacity(0.025))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.75)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("3D map of \(maps.title)")
        .accessibilityHint("Scroll to zoom, drag to move or turn, double-click to fit")
    }

    private func eyebrow(total: Double, count: Int) -> String {
        let using = total > 0 ? " · \(EnergyUnits.power(total)) in use" : ""
        return "\(count) device\(count == 1 ? "" : "s") placed\(using)"
    }
}

/// Says plainly that the demo house and its power use are made up, and how to get your own home in.
private struct DemoNote: View {
    let `import`: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Text("DEMO")
                .font(.system(size: 11, weight: .bold)).tracking(1.1)
                .foregroundStyle(Theme.onBrand)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Theme.brandFill))
            VStack(alignment: .leading, spacing: 6) {
                Text("This is a demo house with simulated devices, so you can see how the map works.")
                    .font(.system(size: 12.5, weight: .medium))
                Text("Scan your home with a LiDAR iPhone or iPad, AirDrop the USDZ to this Mac, then import it.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                Button("Import a scan", action: `import`)
                    .buttonStyle(PressStyle())
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.sand)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.sand.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.sand.opacity(0.22), lineWidth: 0.75)))
    }
}

/// A placed device with its share of the house's power.
private struct PowerRow: View {
    let pin: MapPin
    let watts: Double?
    let total: Double
    var supplying = false

    var body: some View {
        HStack(spacing: 11) {
            DeviceArtView(kind: pin.art, active: (watts ?? 0) > 0 || supplying, accent: Theme.sand, size: 30)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(pin.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if pin.isDemo {
                        Text("DEMO").font(.system(size: 11, weight: .bold)).tracking(0.8).foregroundStyle(Theme.sand)
                    }
                }
                if supplying {
                    Text("Supplying the house").font(.system(size: 12)).foregroundStyle(Theme.muted)
                } else if let w = watts, total > 0 {
                    GeometryReader { g in
                        Capsule().fill(Theme.fg.opacity(0.07))
                            .overlay(alignment: .leading) {
                                Capsule().fill(Theme.sand.opacity(0.8)).frame(width: max(4, g.size.width * min(1, w / total)))
                            }
                    }
                    .frame(height: 4)
                } else {
                    Text("No power reading").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 8)
            if let w = watts {
                Text(EnergyUnits.power(w)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

/// The demo house and every scan you've imported, to switch between.
private struct MapsList: View {
    @ObservedObject private var maps = HomeMapStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MAPS").eyebrow().padding(.leading, 4)
            Bezel(radius: 18, inset: 3) {
                VStack(spacing: 0) {
                    row(title: "Demo house", detail: "Simulated devices", url: nil)
                    ForEach(maps.scans, id: \.self) { url in
                        Divider().overlay(Theme.hairline).padding(.leading, 12)
                        row(title: url.deletingPathExtension().lastPathComponent, detail: url.pathExtension.uppercased() + " scan", url: url)
                    }
                }
            }
        }
    }

    private func row(title: String, detail: String, url: URL?) -> some View {
        let on = maps.current == url
        return Button { maps.show(url) } label: {
            HStack(spacing: 10) {
                Image(systemName: url == nil ? "house" : "cube.transparent")
                    .font(.system(size: 13)).foregroundStyle(on ? Theme.ink : Theme.muted).frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                if on { Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.sand) }
            }
            .padding(.horizontal, 12).frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: Full window

/// The full map: every device on one side to drag into the house, the house in the middle, and
/// the device you clicked, with its main control, on the other.
struct MapWindow: View {
    /// The offline renderer supplies a SceneKit snapshot, since AppKit's view
    /// cache cannot capture a Metal surface. Interactive windows use the scene.
    var previewImage: NSImage?
    @EnvironmentObject var store: HomeStore
    @ObservedObject private var maps = HomeMapStore.shared
    @ObservedObject private var gadgets = GadgetStore.shared
    @StateObject private var scene = MapSceneController(full: true)
    @State private var selected: String?
    @State private var search = ""
    @State private var draggingID: String?
    @State private var lastPlacedID: String?
    @State private var placementRevision = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(previewImage: NSImage? = nil) { self.previewImage = previewImage }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 280)
                .background(Theme.base)
            Rectangle().fill(Theme.hairline).frame(width: 1)
            ZStack {
                if let previewImage {
                    Image(nsImage: previewImage).resizable().aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                MapSceneView(controller: scene, onPin: { id in
                    withAnimation(.snap) { selected = id }
                    scene.selected = id
                }, onDrop: place)
                }
                VStack {
                    toolbar
                    Spacer()
                    legend
                }
                .padding(14)
                if let id = selected, let pin = maps.pins.first(where: { $0.id == id }) {
                    PinInspector(pin: pin, watts: scene.watts[id]) {
                        maps.remove(id)
                        selected = nil
                        scene.selected = nil
                    } close: {
                        selected = nil
                        scene.selected = nil
                    }
                    .frame(width: 300)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 96)
                    .transition(.opacity.combined(with: .offset(x: 12)))
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .frame(minWidth: 860, minHeight: 540)
        .onAppear {
            scene.attach(store)
            scene.active = true
        }
        .onDisappear { scene.active = false }
    }

    // MARK: Sidebar

    private struct Candidate: Identifiable {
        let id: String
        let name: String
        let detail: String
        let kind: DeviceKind
    }

    private var candidates: [Candidate] {
        let fromHA = store.devices.values.compactMap { store.homeDevice($0.id) }
            .filter { !$0.entities.isEmpty && !$0.info.isService }
            .map { d in
                Candidate(id: d.id, name: d.name,
                          detail: d.info.areaID.flatMap { store.areas[$0]?.name } ?? d.kind.title, kind: d.kind)
            }
        let byHand = gadgets.gadgets.map { g in
            Candidate(id: "gadget:\(g.id.uuidString)", name: g.name, detail: "\(g.kind.title), added by hand", kind: g.kind.art)
        }
        // Pins are saved in placement order. Keep that order across launches without
        // adding a separate timestamp or changing the existing map file format.
        let order = maps.pins.enumerated().reduce(into: [String: Int]()) { $0[$1.element.id] = $1.offset }
        let all = (fromHA + byHand).sorted {
            let a = order[$0.id] ?? -1, b = order[$1.id] ?? -1
            return a != b ? a > b : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        guard !search.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.detail.localizedCaseInsensitiveContains(search) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("DEVICES").eyebrow()
                Text("Drag one onto the floor or a wall").font(.system(size: 15, weight: .semibold))
            }
            .padding(.top, 18)
            HearthField(label: "Search devices", placeholder: "Search", text: $search)
            ScrollViewReader { proxy in
              ScrollView {
                VStack(spacing: 2) {
                    ForEach(candidates) { c in
                        let placed = maps.isPinned(c.id)
                        MapDeviceLift(payload: "\(MapDrag.prefix)\(c.id)|\(c.name)|\(c.kind.rawValue)",
                                      accessibilityLabel: c.name, onLift: { draggingID = c.id }, onEnd: { draggingID = nil },
                                      onSelect: { if placed { selected = c.id; scene.selected = c.id } },
                                      onPlace: placed ? nil : {
                                          let (point, level) = scene.suggestedPlacement()
                                          place("\(c.id)|\(c.name)|\(c.kind.rawValue)", point, level)
                                      }) {
                         HStack(spacing: 10) {
                            DeviceArtView(kind: c.kind, active: true, accent: Theme.sand, size: 30).frame(width: 30, height: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                Text(c.detail).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            if placed {
                                Image(systemName: "mappin").font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Theme.onBrand).frame(width: 16, height: 16)
                                    .background(Circle().fill(Theme.brandFill))
                                    .accessibilityLabel("On the map")
                            } else {
                                Image(systemName: "line.3.horizontal").font(.system(size: 12)).foregroundStyle(Theme.faint)
                                    .accessibilityHidden(true)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selected == c.id ? Theme.fg.opacity(0.08) : .clear))
                        }
                        .frame(height: 48)
                        .opacity(draggingID == c.id ? 0.16 : 1)
                        .background(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.hairline,
                            style: StrokeStyle(lineWidth: draggingID == c.id ? 1 : 0, dash: [3, 3])))
                        .id(c.id)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(c.name), \(c.detail)\(placed ? ", on the map" : "")")
                        .accessibilityAction { if placed { selected = c.id; scene.selected = c.id } }
                        .accessibilityHint("Drag onto the map to place it")
                    }
                    if candidates.isEmpty {
                        Text(search.isEmpty ? "Sign in to Home Assistant to see your devices." : "Nothing matches.")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.muted).padding(.top, 20)
                    }
                }
            }
            .scrollIndicators(.never)
            .onChange(of: placementRevision) { _, _ in
                if let id = lastPlacedID { withAnimation(reduceMotion ? nil : .settle) { proxy.scrollTo(id, anchor: .top) } }
            }
            }
        }
        .padding(.horizontal, 14)
    }

    /// A dropped device: `id|name|kind`, pinned where it landed, on the floor it landed on.
    private func place(_ payload: String, _ at: SIMD3<Float>, _ level: Int) {
        let parts = payload.split(separator: "|", maxSplits: 2).map(String.init)
        guard parts.count == 3 else { return }
        withAnimation(reduceMotion ? nil : .settle) {
            maps.place(MapPin(id: parts[0], name: parts[1], kind: parts[2], x: at.x, y: at.y, z: at.z, floor: level))
            selected = parts[0]
            draggingID = nil
            lastPlacedID = parts[0]
            placementRevision += 1
        }
        scene.selected = parts[0]
    }

    // MARK: Toolbar and legend

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                mapMenu
                ViewModePicker()
                Spacer(minLength: 0)
                chip("Fit", symbol: "arrow.up.left.and.down.right.magnifyingglass", on: false) { scene.fit(animated: true) }
                    .help("Fit the house in view (or double-click the map)")
                Menu {
                    if !maps.planView {
                        Picker("Walls", selection: $maps.wallMode) {
                            ForEach(WallMode.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    }
                    Picker("Drag to", selection: $maps.dragMode) {
                        ForEach(DragMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Divider()
                    if maps.isDemo { Button("Reset demo") { maps.resetDemo() } }
                    else { Toggle("Show textures", isOn: $maps.showTextures) }
                } label: {
                    Label("View options", systemImage: "slider.horizontal.3")
                        .font(.system(size: 12.5, weight: .semibold))
                        .padding(.horizontal, 12).frame(height: 34)
                        .liquidGlass(in: Capsule())
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help("Wall appearance, mouse interaction, and map options")
            }
            .onChange(of: maps.dragMode) { _, mode in if mode == .move { scene.surface() } }
            if maps.hasFloors { FloorPicker(compact: true) }
        }
    }

    private var mapMenu: some View {
        Menu {
            Button("Demo house") { maps.show(nil) }
            if !maps.scans.isEmpty { Divider() }
            ForEach(maps.scans, id: \.self) { url in
                Button(url.deletingPathExtension().lastPathComponent) { maps.show(url) }
            }
            Divider()
            Button("Import a scan as a new map…") { maps.importScan() }
            if let url = maps.current {
                Button("Add a floor from a scan…") { maps.addFloorFromScan() }
                ForEach(maps.floors.filter { $0.level != 0 }) { floor in
                    Button("Remove the \(maps.name(of: floor.level, homeAssistant: store.floors).lowercased()) floor", role: .destructive) {
                        maps.removeFloor(floor.level)
                    }
                }
                Divider()
                Button("Delete this map", role: .destructive) { maps.delete(url) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: maps.isDemo ? "house" : "cube.transparent")
                Text(maps.title).font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 12).frame(height: 34)
        .liquidGlass(in: Capsule())
    }

    private func chip(_ title: String, symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12))
                Text(title).font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(on ? Theme.ink : Theme.muted)
            .padding(.horizontal, 12).frame(height: 34)
            .liquidGlass(in: Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var legend: some View {
        let loads = maps.pins.filter { MapPower.role(of: $0) == .load }
        let total = loads.compactMap { scene.watts[$0.id] }.reduce(0, +)
        let hasSource = maps.pins.contains { MapPower.role(of: $0) == .source }
        return HStack(alignment: .bottom, spacing: 14) {
         HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("IN USE").eyebrow()
                Text(total > 0 ? EnergyUnits.power(total) : "No readings").font(.system(size: 20, weight: .semibold)).monospacedDigit()
            }
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 34)
            VStack(alignment: .leading, spacing: 4) {
                legendRow(color: Color.accent(1, 0.78, 0.42), text: hasSource ? "Energy flowing from the inverter" : "Place an inverter or battery to see energy flow")
                legendRow(color: Theme.ok, text: "Supplies power")
                Text(maps.dragMode == .turn ? "Scroll to zoom · drag to turn, any way up · double-click to fit"
                                            : "Scroll to zoom · drag to move · right-drag to turn · double-click to fit")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: 460, alignment: .leading)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
         Spacer(minLength: 12)
         if maps.isDemo {
            Text("DEMO · POWER IS SIMULATED")
                .font(.system(size: 9.9, weight: .semibold)).tracking(0.7)
                .foregroundStyle(Theme.sand)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Capsule().fill(Theme.base.opacity(0.9)).overlay(Capsule().strokeBorder(Theme.sand.opacity(0.3))))
                .fixedSize()
         }
        }
    }

    private func legendRow(color: Color, text: String) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 7, height: 7).glow(color: color, radius: 3)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.ink.opacity(0.85))
        }
    }
}

// MARK: Pickers

/// A small segmented control on glass for the map: a white key slides to the choice.
private struct MapPicker<Option: Hashable>: View {
    let options: [Option]
    let selected: Option
    var compact = false
    let title: (Option) -> String
    var symbol: ((Option) -> String?)? = nil
    let label: String
    let onSelect: (Option) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                let on = option == selected
                Button { onSelect(option) } label: {
                    HStack(spacing: 5) {
                        if let name = symbol?(option) {
                            Image(systemName: name).font(.system(size: compact ? 10.5 : 11.5, weight: .semibold))
                        }
                        Text(title(option)).font(.system(size: compact ? 11.5 : 12.5, weight: .semibold)).lineLimit(1)
                    }
                    .padding(.horizontal, compact ? 9 : 11)
                    .frame(height: compact ? 24 : 28)
                    .foregroundStyle(on ? Theme.onKey : Theme.muted)
                    .background {
                        if !on {
                            Color.clear.hoverFill(Capsule())
                        }
                    }
                    .contentShape(Capsule())
                    .selectionFrame(index)
                }
                .buttonStyle(PressStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .slidingSelection(options.firstIndex(of: selected), radius: 20)
        .padding(3)
        .background {
            // The panel preview sits in a scroll view, where glass loses what's on it; a solid pill reads cleanly.
            if compact {
                Capsule().fill(Theme.base.opacity(0.9)).overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.75))
            }
        }
        .modifier(GlassUnless(off: compact))
        .fixedSize()
        .animation(.selectionSlide, value: selected)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

private struct GlassUnless: ViewModifier {
    let off: Bool
    func body(content: Content) -> some View {
        if off { content } else { content.liquidGlass(in: Capsule()) }
    }
}

/// Every floor stacked, or one at a time. The plan shows one floor, so it has no "All".
private struct FloorPicker: View {
    @EnvironmentObject var store: HomeStore
    @ObservedObject private var maps = HomeMapStore.shared
    var compact = false

    private enum Choice: Hashable { case all, level(Int) }

    var body: some View {
        let levels = maps.floors.map(\.level).sorted()
        let options: [Choice] = (maps.planView ? [] : [.all]) + levels.map { .level($0) }
        let selected: Choice = maps.shownFloor.map { .level($0) } ?? .all
        MapPicker(options: options, selected: selected, compact: compact, title: { choice in
            switch choice {
            case .all: "All"
            case .level(let l): maps.name(of: l, homeAssistant: store.floors)
            }
        }, symbol: { $0 == .all ? "square.3.layers.3d" : nil }, label: "Floor") { choice in
            switch choice {
            case .all: maps.floorFilter = nil
            case .level(let l): maps.floorFilter = l
            }
        }
    }
}

/// The house in 3D, or the plan from above.
private struct ViewModePicker: View {
    @ObservedObject private var maps = HomeMapStore.shared
    var compact = false

    var body: some View {
        MapPicker(options: [false, true], selected: maps.planView, compact: compact,
                  title: { $0 ? "Plan" : "3D" },
                  symbol: { $0 ? "square.grid.3x3" : "cube" }, label: "View") { maps.planView = $0 }
    }
}

/// What the mouse does: move the house, or turn it over like a ball.
private struct DragModePicker: View {
    @ObservedObject private var maps = HomeMapStore.shared
    let scene: MapSceneController
    var compact = false

    var body: some View {
        MapPicker(options: DragMode.allCases, selected: maps.dragMode, compact: compact,
                  title: \.title, symbol: { $0.symbol }, label: "Drag") { mode in
            maps.dragMode = mode
            if mode == .move { scene.surface() }
        }
        .help("Move slides the house; Turn spins it in any direction, even to look up from below. Right-drag always turns.")
    }
}

/// Solid, see-through or cut walls.
private struct WallPicker: View {
    @ObservedObject private var maps = HomeMapStore.shared

    var body: some View {
        MapPicker(options: WallMode.allCases, selected: maps.wallMode, title: \.title, symbol: { $0.symbol }, label: "Walls") {
            maps.wallMode = $0
        }
    }
}

/// The device you clicked on the map: what it's doing, its main control, and a way to take it off.
private struct PinInspector: View {
    @EnvironmentObject var store: HomeStore
    let pin: MapPin
    let watts: Double?
    let remove: () -> Void
    let close: () -> Void

    var body: some View {
        let device = pin.isDemo || pin.id.hasPrefix("gadget:") ? nil : store.homeDevice(pin.id)
        let main = device.flatMap { d in
            d.entities.first { ["climate", "light", "switch", "fan", "cover", "lock", "media_player", "vacuum", "lawn_mower", "alarm_control_panel"].contains($0.domain)
                && !EntityCatalog.copy(for: $0, deviceName: d.name).hidden }
        }
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                DeviceArtView(kind: pin.art, active: true, accent: device?.accent ?? Theme.sand, size: 46).frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(pin.name).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                    Text(status(device)).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 4)
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 26).background(Circle().fill(Theme.fg.opacity(0.08)))
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Close")
            }
            if let w = watts {
                HStack {
                    Text(MapPower.role(of: pin) == .source ? "Supplying" : "Using").font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                    Spacer()
                    Text(EnergyUnits.power(w)).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                }
            }
            if let main, let device {
                EntityControl(entity: main, copy: EntityCatalog.copy(for: main, deviceName: device.name), tint: device.accent)
                    .padding(.horizontal, -12)
            } else if pin.isDemo {
                Text("A demo device. Its power use is simulated.").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            Button(role: .destructive, action: remove) {
                Label("Take off the map", systemImage: "mappin.slash").font(.system(size: 12.5, weight: .semibold))
            }
            .buttonStyle(PressStyle())
            .foregroundStyle(Theme.live)
        }
        .padding(16)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func status(_ device: HomeDevice?) -> String {
        let base = device?.summary ?? (pin.isDemo ? "Demo" : pin.art.title)
        let maps = HomeMapStore.shared
        guard maps.hasFloors else { return base }
        return "\(maps.name(of: pin.level, homeAssistant: store.floors)) floor · \(base)"
    }
}
