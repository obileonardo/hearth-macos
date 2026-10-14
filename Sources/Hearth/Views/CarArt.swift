import AppKit
import SwiftUI

// MARK: Models

/// The electric cars Hearth can draw as themselves, so a Model Y looks like a Model Y and a
/// Seal like a Seal. No logos: proportions, glasshouse, lights and wheels carry the likeness.
enum CarModel: String, CaseIterable, Identifiable, Codable {
    case model3, modelY, modelS, modelX, cybertruck
    case seal, atto3, dolphin
    case ioniq5, ev6, i4, polestar2
    case generic

    var id: String { rawValue }

    var maker: String {
        switch self {
        case .model3, .modelY, .modelS, .modelX, .cybertruck: "Tesla"
        case .seal, .atto3, .dolphin: "BYD"
        case .ioniq5: "Hyundai"
        case .ev6: "Kia"
        case .i4: "BMW"
        case .polestar2: "Polestar"
        case .generic: "Electric car"
        }
    }

    var name: String {
        switch self {
        case .model3: "Model 3"
        case .modelY: "Model Y"
        case .modelS: "Model S"
        case .modelX: "Model X"
        case .cybertruck: "Cybertruck"
        case .seal: "Seal"
        case .atto3: "Atto 3"
        case .dolphin: "Dolphin"
        case .ioniq5: "Ioniq 5"
        case .ev6: "EV6"
        case .i4: "i4"
        case .polestar2: "Polestar 2"
        case .generic: "Electric car"
        }
    }

    /// Recognises the model from what Home Assistant (or the demo) says about the car.
    static func from(manufacturer: String?, model: String?, name: String? = nil) -> CarModel {
        let text = " " + [manufacturer, model, name].compactMap { $0 }.joined(separator: " ").lowercased() + " "
        func has(_ words: String...) -> Bool { words.contains { text.contains($0) } }
        if has("cybertruck") { return .cybertruck }
        if has("model y", "model_y", "modely") { return .modelY }
        if has("model x", "model_x", "modelx") { return .modelX }
        if has("model s", "model_s", "models ") { return .modelS }
        if has("model 3", "model_3", "model3") { return .model3 }
        if has("atto 3", "atto3", "atto_3", "yuan plus") { return .atto3 }
        if has("dolphin") { return .dolphin }
        if has(" seal") { return .seal }
        if has("ioniq 5", "ioniq5", "ioniq_5") { return .ioniq5 }
        if has("ev6") { return .ev6 }
        if has(" i4", "i4 ") { return .i4 }
        if has("polestar 2", "polestar2", "polestar_2") { return .polestar2 }
        return .generic
    }

    /// Well-known paint colours for each maker.
    var palette: [CarPaint] {
        switch self {
        case .model3, .modelY, .modelS, .modelX:
            [.init("Pearl White", 0.94, 0.94, 0.93, .pearl), .init("Solid Black", 0.07, 0.07, 0.08, .gloss),
             .init("Deep Blue Metallic", 0.09, 0.17, 0.36, .metallic), .init("Ultra Red", 0.66, 0.05, 0.08, .metallic),
             .init("Stealth Grey", 0.26, 0.27, 0.29, .metallic), .init("Quicksilver", 0.62, 0.63, 0.65, .metallic)]
        case .cybertruck:
            [.init("Stainless Steel", 0.72, 0.73, 0.74, .stainless), .init("Satin Black Wrap", 0.12, 0.12, 0.13, .matte)]
        case .seal:
            [.init("Aurora White", 0.94, 0.94, 0.93, .pearl), .init("Atlantis Grey", 0.33, 0.37, 0.41, .metallic),
             .init("Shadow Green", 0.16, 0.24, 0.21, .metallic), .init("Cosmos Black", 0.07, 0.07, 0.08, .gloss),
             .init("Arctic Blue", 0.52, 0.66, 0.77, .metallic)]
        case .atto3:
            [.init("Ski White", 0.95, 0.95, 0.94, .gloss), .init("Surf Blue", 0.22, 0.45, 0.66, .metallic),
             .init("Boulder Grey", 0.47, 0.47, 0.46, .metallic), .init("Parkour Red", 0.64, 0.1, 0.12, .metallic),
             .init("Forest Green", 0.2, 0.31, 0.26, .metallic)]
        case .dolphin:
            [.init("Ski White", 0.95, 0.95, 0.94, .gloss), .init("Coral Pink", 0.9, 0.6, 0.57, .metallic),
             .init("Surf Blue", 0.24, 0.47, 0.66, .metallic), .init("Urban Grey", 0.42, 0.43, 0.44, .metallic),
             .init("Atlantis Grey", 0.33, 0.37, 0.41, .metallic)]
        case .ioniq5:
            [.init("Gravity Gold Matte", 0.6, 0.54, 0.4, .matte), .init("Digital Teal", 0.27, 0.43, 0.42, .metallic),
             .init("Lucid Blue", 0.55, 0.67, 0.76, .metallic), .init("Cyber Grey", 0.44, 0.46, 0.47, .metallic),
             .init("Atlas White", 0.94, 0.94, 0.93, .gloss), .init("Mystic Olive", 0.33, 0.36, 0.28, .metallic)]
        case .ev6:
            [.init("Runway Red", 0.64, 0.08, 0.1, .metallic), .init("Yacht Blue", 0.08, 0.15, 0.3, .metallic),
             .init("Moonscape Matte", 0.43, 0.44, 0.44, .matte), .init("Glacier", 0.93, 0.94, 0.94, .gloss),
             .init("Interstellar Grey", 0.24, 0.25, 0.27, .metallic), .init("Snow White Pearl", 0.95, 0.95, 0.93, .pearl)]
        case .i4:
            [.init("Portimao Blue", 0.09, 0.29, 0.66, .metallic), .init("Mineral White", 0.91, 0.91, 0.89, .pearl),
             .init("Brooklyn Grey", 0.48, 0.5, 0.52, .metallic), .init("Black Sapphire", 0.06, 0.07, 0.09, .metallic),
             .init("San Remo Green", 0.17, 0.3, 0.27, .metallic)]
        case .polestar2:
            [.init("Snow", 0.93, 0.93, 0.92, .gloss), .init("Thunder", 0.31, 0.33, 0.35, .metallic),
             .init("Space", 0.07, 0.07, 0.08, .metallic), .init("Midnight", 0.1, 0.14, 0.25, .metallic),
             .init("Jupiter", 0.74, 0.73, 0.69, .metallic), .init("Magnesium", 0.6, 0.62, 0.64, .metallic)]
        case .generic:
            [.init("Pearl White", 0.94, 0.94, 0.93, .pearl), .init("Graphite", 0.3, 0.31, 0.33, .metallic),
             .init("Ocean Blue", 0.14, 0.3, 0.5, .metallic), .init("Crimson", 0.6, 0.1, 0.12, .metallic)]
        }
    }
}

/// A car's paint: a name, a colour and how the surface takes light.
struct CarPaint: Codable, Hashable, Identifiable {
    enum Finish: String, Codable { case gloss, metallic, pearl, matte, stainless }

    let name: String
    let r, g, b: Double
    let finish: Finish

    var id: String { name }
    var color: Color { Color(red: r, green: g, blue: b) }

    init(_ name: String, _ r: Double, _ g: Double, _ b: Double, _ finish: Finish) {
        self.name = name; self.r = r; self.g = g; self.b = b; self.finish = finish
    }

    /// The paint lifted toward white (amount > 0) or pressed toward black (amount < 0).
    func shade(_ amount: Double) -> Color {
        if amount >= 0 {
            return Color(red: r + (1 - r) * amount, green: g + (1 - g) * amount, blue: b + (1 - b) * amount)
        }
        let k = 1 + amount
        return Color(red: r * k, green: g * k, blue: b * k)
    }

    var isLight: Bool { 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.55 }
}

/// Which model a car is and how it's painted.
struct CarLook: Hashable {
    var model: CarModel
    var paint: CarPaint
}

// MARK: Paint choices

/// Remembers the paint chosen for each car. Real cars keep theirs between launches; the demo
/// car's is set when a car is picked and isn't saved.
@MainActor
final class CarPaints: ObservableObject {
    static let shared = CarPaints()
    @Published private var chosen: [String: String] = [:]
    @Published private var demo: [String: CarPaint] = [:]

    private init() {
        chosen = UserDefaults.standard.dictionary(forKey: "car.paints") as? [String: String] ?? [:]
    }

    func look(for device: HomeDevice) -> CarLook {
        let model = CarModel.from(manufacturer: device.info.manufacturer, model: device.info.model, name: device.name)
        if let paint = demo[device.id] { return CarLook(model: model, paint: paint) }
        let palette = model.palette
        if let name = chosen[device.id], let paint = palette.first(where: { $0.name == name }) {
            return CarLook(model: model, paint: paint)
        }
        // A stable colour from the device id, so the same car always comes up the same.
        let hash = device.id.unicodeScalars.reduce(UInt32(2166136261)) { ($0 ^ $1.value) &* 16777619 }
        return CarLook(model: model, paint: palette[Int(hash % UInt32(palette.count))])
    }

    func choose(_ paint: CarPaint, for deviceID: String) {
        if demo[deviceID] != nil { demo[deviceID] = paint; return }
        chosen[deviceID] = paint.name
        UserDefaults.standard.set(chosen, forKey: "car.paints")
    }

    /// The demo car's paint, kept in memory only.
    func setDemo(_ paint: CarPaint, for deviceID: String) { demo[deviceID] = paint }
}

/// The same remembered illustration in vehicle cards, rooms and device details.
struct HomeCarArt: View {
    @ObservedObject private var paints = CarPaints.shared
    let device: HomeDevice
    var size: CGFloat = 76

    var body: some View {
        CarArtView(look: paints.look(for: device), active: device.online,
                   charging: VehicleStatus(device).isCharging, size: size)
            .accessibilityHidden(true)
    }
}

struct CarPaintPicker: View {
    @EnvironmentObject private var store: HomeStore
    @ObservedObject private var paints = CarPaints.shared
    let device: HomeDevice

    var body: some View {
        let look = paints.look(for: device)
        HStack(spacing: 8) {
            Text("Paint").font(.system(size: 12)).foregroundStyle(Theme.muted)
            HStack(spacing: 6) {
                ForEach(look.model.palette) { paint in
                    Button {
                        if store.isDemo { paints.setDemo(paint, for: device.id) }
                        else { paints.choose(paint, for: device.id) }
                    } label: {
                        Circle().fill(paint.color)
                            .overlay(Circle().strokeBorder(Theme.fg.opacity(0.25), lineWidth: 0.75))
                            .padding(3)
                            .overlay(Circle().strokeBorder(look.paint == paint ? Theme.ink : .clear, lineWidth: 1))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(PressStyle())
                    .help(paint.name)
                    .accessibilityLabel(paint.name)
                    .accessibilityAddTraits(look.paint == paint ? .isSelected : [])
                }
            }
            Spacer(minLength: 0)
            Text(look.paint.name).font(.system(size: 11.5)).foregroundStyle(Theme.muted).lineLimit(1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Illustration paint")
    }
}

// MARK: The view

/// A car drawn as its own model and paint. Changing the look slides the new car in.
struct CarArtView: View {
    var look: CarLook
    var active: Bool = true
    /// Lights the charge port.
    var charging: Bool = false
    var accent: Color = Color(red: 0.42, green: 0.92, blue: 0.7)
    var size: CGFloat = 76
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Canvas { ctx, _ in CarArt(look: look, size: size, on: active, charging: charging, accent: accent).draw(ctx) }
                .id(look)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .offset(x: size * 0.5).combined(with: .opacity),
                    removal: .offset(x: -size * 0.5).combined(with: .opacity)))
        }
        .frame(width: size, height: size)
        .clipped()
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.86), value: look)
        .saturation(active ? 1 : 0.15)
        .accessibilityElement()
        .accessibilityLabel("\(look.paint.name) \(look.model.maker) \(look.model.name)")
    }
}

// MARK: Drawing

/// A model's side profile, in millimetres from the nose (x) and the ground (y), with its glass,
/// lights and wheels. Turned into the 100 by 100 art grid when drawn.
private struct CarSpec {
    enum WheelStyle { case aero, turbine, spokes(Int), pixel, cyber, twin }

    var length: Double
    var frontAxle: Double, rearAxle: Double
    var tyre: Double
    var clearance: Double
    /// The silhouette, clockwise from the bottom of the front bumper to the bottom of the rear.
    var body: [(Double, Double)]
    var bodyCorners: Set<Int> = []
    /// The side windows, as one closed outline.
    var glass: [(Double, Double)]
    var glassCorners: Set<Int> = []
    var head: [(Double, Double)]
    var tail: [(Double, Double)]
    var wheels: WheelStyle = .aero
    /// Black plastic around the arches and along the sill, as on crossovers.
    var cladding = false
    /// A chrome line around the windows.
    var chromeGlass = false
    /// Body outline points the glass roof runs along (Tesla's all-glass roof).
    var glassRoof: ClosedRange<Int>? = nil
}

private extension CarModel {
    var spec: CarSpec {
        switch self {
        case .model3:
            CarSpec(length: 4720, frontAxle: 845, rearAxle: 3720, tyre: 690, clearance: 140,
                    body: [(230, 140), (40, 330), (0, 500), (55, 640), (450, 760), (1300, 875), (1950, 1340), (2500, 1441),
                           (3150, 1400), (3900, 1170), (4350, 1010), (4680, 985), (4720, 860), (4700, 560), (4600, 250), (4450, 140)],
                    bodyCorners: [0, 15],
                    glass: [(1430, 915), (1980, 1320), (2550, 1385), (3200, 1350), (3760, 1110), (3830, 1035), (3500, 1025), (2300, 985)],
                    glassCorners: [0, 5],
                    head: [(30, 625), (300, 705), (420, 700), (140, 610)],
                    tail: [(4520, 990), (4712, 955), (4716, 860), (4480, 930)],
                    wheels: .aero, glassRoof: 6...10)
        case .modelY:
            CarSpec(length: 4750, frontAxle: 870, rearAxle: 3760, tyre: 715, clearance: 167,
                    body: [(240, 167), (40, 370), (0, 560), (60, 715), (500, 835), (1300, 955), (1950, 1510), (2550, 1624),
                           (3250, 1605), (3950, 1430), (4430, 1190), (4700, 1060), (4750, 920), (4730, 600), (4620, 280), (4480, 167)],
                    bodyCorners: [0, 15],
                    glass: [(1430, 1000), (1990, 1490), (2580, 1570), (3280, 1545), (3880, 1350), (4020, 1180), (3700, 1125), (2400, 1075)],
                    glassCorners: [0, 5],
                    head: [(35, 705), (310, 790), (430, 785), (150, 690)],
                    tail: [(4560, 1080), (4745, 1035), (4748, 935), (4520, 1000)],
                    wheels: .aero, glassRoof: 6...10)
        case .modelS:
            CarSpec(length: 4970, frontAxle: 880, rearAxle: 3840, tyre: 720, clearance: 135,
                    body: [(250, 135), (40, 330), (0, 510), (60, 640), (550, 760), (1400, 870), (2100, 1360), (2750, 1445),
                           (3400, 1400), (4250, 1150), (4700, 1000), (4940, 965), (4970, 850), (4950, 540), (4840, 240), (4700, 135)],
                    bodyCorners: [0, 15],
                    glass: [(1530, 910), (2130, 1340), (2800, 1400), (3450, 1360), (4060, 1130), (4190, 1050), (3700, 1035), (2400, 985)],
                    glassCorners: [0, 5],
                    head: [(30, 625), (330, 705), (450, 700), (150, 610)],
                    tail: [(4760, 985), (4960, 945), (4966, 860), (4720, 925)],
                    wheels: .turbine, glassRoof: 6...9)
        case .modelX:
            CarSpec(length: 5057, frontAxle: 920, rearAxle: 3885, tyre: 760, clearance: 160,
                    body: [(260, 160), (40, 380), (0, 590), (70, 760), (600, 885), (1300, 995), (2000, 1600), (2750, 1680),
                           (3550, 1650), (4300, 1450), (4800, 1225), (5010, 1105), (5057, 940), (5040, 620), (4930, 260), (4780, 160)],
                    bodyCorners: [0, 15],
                    glass: [(1450, 1040), (2060, 1570), (2750, 1640), (3550, 1605), (4250, 1390), (4400, 1250), (4100, 1200), (2700, 1120)],
                    glassCorners: [0, 5],
                    head: [(40, 740), (330, 830), (460, 825), (160, 725)],
                    tail: [(4820, 1120), (5050, 1070), (5054, 960), (4790, 1040)],
                    wheels: .turbine)
        case .cybertruck:
            CarSpec(length: 5683, frontAxle: 1000, rearAxle: 4800, tyre: 890, clearance: 330,
                    body: [(320, 330), (40, 560), (0, 1110), (2650, 1791), (5683, 1290), (5683, 640), (5500, 330)],
                    bodyCorners: [0, 1, 2, 3, 4, 5, 6],
                    glass: [(1380, 1300), (1430, 1385), (2650, 1735), (3550, 1560), (3470, 1290)],
                    glassCorners: [0, 1, 2, 3, 4],
                    head: [(0, 1080), (20, 1112), (420, 1215), (420, 1180)],
                    tail: [(5520, 1300), (5683, 1290), (5683, 1250), (5520, 1262)],
                    wheels: .cyber)
        case .seal:
            CarSpec(length: 4800, frontAxle: 860, rearAxle: 3780, tyre: 700, clearance: 120,
                    body: [(240, 120), (40, 300), (0, 470), (70, 615), (550, 740), (1350, 850), (2050, 1375), (2650, 1460),
                           (3300, 1420), (4050, 1175), (4500, 1020), (4775, 995), (4800, 880), (4780, 560), (4660, 240), (4520, 120)],
                    bodyCorners: [0, 15],
                    glass: [(1450, 880), (2080, 1355), (2700, 1425), (3350, 1395), (3900, 1150), (4060, 1045), (3700, 1020), (2300, 960)],
                    glassCorners: [0, 5],
                    head: [(25, 600), (360, 690), (430, 670), (110, 575)],
                    tail: [(4470, 1005), (4790, 975), (4795, 945), (4460, 975)],
                    wheels: .spokes(10), chromeGlass: true)
        case .atto3:
            CarSpec(length: 4455, frontAxle: 860, rearAxle: 3580, tyre: 680, clearance: 175,
                    body: [(230, 175), (40, 390), (0, 610), (90, 765), (600, 880), (1250, 960), (1850, 1470), (2400, 1600),
                           (3300, 1590), (3900, 1535), (4330, 1350), (4440, 1150), (4455, 820), (4400, 420), (4300, 175)],
                    bodyCorners: [0, 14],
                    glass: [(1350, 1000), (1900, 1440), (2450, 1550), (3300, 1545), (3880, 1495), (4180, 1380), (4020, 1200), (3600, 1160), (2400, 1060)],
                    glassCorners: [0, 6],
                    head: [(30, 740), (360, 840), (470, 830), (160, 725)],
                    tail: [(4300, 1250), (4445, 1180), (4450, 1110), (4280, 1190)],
                    wheels: .turbine, cladding: true)
        case .dolphin:
            CarSpec(length: 4290, frontAxle: 820, rearAxle: 3520, tyre: 640, clearance: 150,
                    body: [(220, 150), (40, 370), (0, 590), (80, 730), (550, 830), (1150, 915), (1800, 1470), (2350, 1570),
                           (3200, 1555), (3800, 1465), (4150, 1300), (4270, 1100), (4290, 800), (4240, 400), (4140, 150)],
                    bodyCorners: [0, 14],
                    glass: [(1250, 960), (1850, 1430), (2400, 1520), (3200, 1505), (3620, 1440), (3760, 1300), (3560, 1160), (2300, 1030)],
                    glassCorners: [0, 5],
                    head: [(30, 700), (330, 795), (440, 780), (150, 680)],
                    tail: [(4160, 1220), (4280, 1130), (4285, 1050), (4140, 1140)],
                    wheels: .spokes(5))
        case .ioniq5:
            CarSpec(length: 4635, frontAxle: 760, rearAxle: 3760, tyre: 730, clearance: 160,
                    body: [(200, 160), (30, 380), (0, 640), (35, 820), (400, 895), (1200, 970), (1800, 1495), (2300, 1605),
                           (3600, 1595), (4250, 1525), (4585, 1385), (4635, 1150), (4630, 700), (4560, 300), (4430, 160)],
                    bodyCorners: [0, 10, 14],
                    glass: [(1300, 1010), (1850, 1465), (2350, 1555), (3600, 1550), (4120, 1480), (4170, 1150), (3880, 1110), (2500, 1060)],
                    glassCorners: [0, 4, 5],
                    head: [(15, 690), (250, 690), (250, 820), (30, 820)],
                    tail: [(4470, 1060), (4625, 1060), (4630, 1310), (4470, 1310)],
                    wheels: .pixel)
        case .ev6:
            CarSpec(length: 4680, frontAxle: 850, rearAxle: 3750, tyre: 720, clearance: 160,
                    body: [(230, 160), (40, 370), (0, 560), (70, 700), (550, 820), (1300, 920), (1950, 1455), (2550, 1550),
                           (3250, 1520), (3950, 1345), (4400, 1155), (4650, 1080), (4680, 920), (4660, 560), (4560, 270), (4420, 160)],
                    bodyCorners: [0, 15],
                    glass: [(1400, 960), (2000, 1435), (2600, 1515), (3300, 1485), (3800, 1300), (3720, 1150), (2400, 1010)],
                    glassCorners: [0, 4],
                    head: [(30, 655), (380, 745), (460, 730), (140, 640)],
                    tail: [(3760, 1045), (4670, 1065), (4675, 1030), (3800, 1015)],
                    wheels: .twin, cladding: true)
        case .i4:
            CarSpec(length: 4785, frontAxle: 860, rearAxle: 3716, tyre: 710, clearance: 125,
                    body: [(240, 125), (30, 330), (0, 570), (70, 710), (650, 805), (1500, 880), (2150, 1375), (2750, 1448),
                           (3350, 1410), (4100, 1180), (4500, 1040), (4755, 1010), (4785, 900), (4770, 560), (4660, 240), (4530, 125)],
                    bodyCorners: [0, 15],
                    glass: [(1560, 920), (2170, 1355), (2780, 1415), (3380, 1385), (3960, 1150), (3870, 1060), (3750, 1045), (2400, 990)],
                    glassCorners: [0, 4, 5, 6],
                    head: [(30, 640), (420, 725), (500, 715), (120, 620)],
                    tail: [(4560, 1015), (4775, 990), (4780, 905), (4540, 950)],
                    wheels: .spokes(5), chromeGlass: true)
        case .polestar2:
            CarSpec(length: 4606, frontAxle: 880, rearAxle: 3615, tyre: 720, clearance: 151,
                    body: [(230, 151), (40, 380), (0, 600), (70, 760), (550, 860), (1300, 940), (1900, 1415), (2450, 1479),
                           (3150, 1450), (3850, 1265), (4350, 1115), (4580, 1085), (4606, 950), (4590, 600), (4500, 280), (4370, 151)],
                    bodyCorners: [0, 15],
                    glass: [(1400, 980), (1950, 1395), (2500, 1450), (3200, 1425), (3700, 1265), (3800, 1170), (3500, 1140), (2300, 1060)],
                    glassCorners: [0, 5],
                    head: [(30, 735), (340, 820), (440, 810), (150, 715)],
                    tail: [(4400, 1100), (4600, 1080), (4604, 1040), (4390, 1060)],
                    wheels: .spokes(5), cladding: true)
        case .generic:
            CarSpec(length: 4650, frontAxle: 860, rearAxle: 3700, tyre: 700, clearance: 150,
                    body: [(230, 150), (40, 350), (0, 540), (60, 690), (500, 810), (1300, 910), (1950, 1430), (2550, 1530),
                           (3250, 1505), (3950, 1300), (4400, 1110), (4620, 1060), (4650, 900), (4630, 560), (4530, 260), (4400, 150)],
                    bodyCorners: [0, 15],
                    glass: [(1420, 950), (2000, 1410), (2600, 1490), (3300, 1460), (3850, 1250), (3950, 1150), (3650, 1110), (2400, 1030)],
                    glassCorners: [0, 5],
                    head: [(30, 670), (320, 760), (430, 750), (140, 655)],
                    tail: [(4480, 1080), (4645, 1050), (4648, 960), (4460, 1020)],
                    wheels: .aero)
        }
    }
}

private struct CarArt {
    let look: CarLook
    let size: CGFloat
    let on: Bool
    let charging: Bool
    let accent: Color

    private var spec: CarSpec { look.model.spec }
    private var paint: CarPaint { look.paint }
    private var k: CGFloat { size / 100 }
    /// Millimetres to art units: the longest cars still fit, the rest share one scale.
    private var scale: Double { min(0.0182, 94 / spec.length) }
    private let groundY: Double = 71
    private var x0: Double { 50 - spec.length * scale / 2 }

    private func pt(_ p: (Double, Double)) -> CGPoint {
        CGPoint(x: (x0 + p.0 * scale) * k, y: (groundY - p.1 * scale * 1.1) * k)
    }
    private func u(_ v: Double) -> CGFloat { v * k }
    private func mm(_ v: Double) -> CGFloat { v * scale * k }

    // MARK: Paths

    /// A smooth closed outline through the points, sharp where a point is a corner.
    private func smooth(_ pts: [(Double, Double)], corners: Set<Int>) -> Path {
        let p = pts.map(pt)
        let n = p.count
        var path = Path()
        path.move(to: p[0])
        for i in 0..<n {
            let a = p[i], b = p[(i + 1) % n]
            let prev = p[(i - 1 + n) % n], next = p[(i + 2) % n]
            let aCorner = corners.contains(i), bCorner = corners.contains((i + 1) % n)
            let c1 = aCorner ? CGPoint(x: a.x + (b.x - a.x) / 3, y: a.y + (b.y - a.y) / 3)
                : CGPoint(x: a.x + (b.x - prev.x) / 6, y: a.y + (b.y - prev.y) / 6)
            let c2 = bCorner ? CGPoint(x: b.x - (b.x - a.x) / 3, y: b.y - (b.y - a.y) / 3)
                : CGPoint(x: b.x - (next.x - a.x) / 6, y: b.y - (next.y - a.y) / 6)
            path.addCurve(to: b, control1: c1, control2: c2)
        }
        path.closeSubpath()
        return path
    }

    private var bodyPath: Path { smooth(spec.body, corners: spec.bodyCorners) }
    private var bodyRect: CGRect { bodyPath.boundingRect }

    private func circle(_ c: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }

    private func vertical(_ r: CGRect, _ stops: [(Color, CGFloat)]) -> GraphicsContext.Shading {
        .linearGradient(Gradient(stops: stops.map { .init(color: $0.0, location: $0.1) }),
                        startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY))
    }

    // MARK: Draw

    func draw(_ ctx: GraphicsContext) {
        let body = bodyPath
        let r = bodyRect
        // Wheels drawn a touch larger than life, as illustrations do, so they read at small sizes.
        let wheelR = mm(spec.tyre / 2) * 1.12
        let axleY = groundY * k - wheelR
        let wheels = [pt((spec.frontAxle, 0)).x, pt((spec.rearAxle, 0)).x].map { CGPoint(x: $0, y: axleY) }

        // Ground shadow.
        ctx.clayer(blur: u(2.4)) {
            $0.fill(Path(ellipseIn: CGRect(x: r.minX - u(1), y: groundY * k - u(2.2), width: r.width + u(2), height: u(4.4))),
                    with: .color(.black.opacity(0.8)))
        }
        ctx.clayer(blur: u(0.6)) {
            for w in wheels {
                $0.fill(Path(ellipseIn: CGRect(x: w.x - wheelR * 0.9, y: groundY * k - u(0.9), width: wheelR * 1.8, height: u(1.8))),
                        with: .color(.black.opacity(0.9)))
            }
        }

        // Paint.
        paintBody(ctx, body, r)
        var inPaint = ctx
        inPaint.clip(to: body)

        // Sill and lower body: dark, or black cladding on crossovers.
        let sillTop = r.maxY - (spec.cladding ? mm(330) : mm(150))
        inPaint.fill(Path(CGRect(x: r.minX, y: sillTop, width: r.width, height: r.maxY - sillTop)),
                     with: vertical(CGRect(x: r.minX, y: sillTop, width: r.width, height: r.maxY - sillTop),
                                    [(Color(white: spec.cladding ? 0.13 : 0.2), 0), (Color(white: 0.05), 1)]))

        // Wheel arches.
        for w in wheels {
            if look.model == .cybertruck {
                let arch = cyberArch(w, wheelR)
                inPaint.fill(arch, with: .color(Color(white: 0.11)))
                inPaint.fill(cyberArch(w, wheelR * 0.86), with: .color(Color(white: 0.03)))
            } else {
                if spec.cladding {
                    inPaint.fill(circle(w, wheelR * 1.32), with: .color(Color(white: 0.1)))
                }
                inPaint.fill(circle(w, wheelR * 1.13), with: .color(Color(white: 0.03)))
                inPaint.stroke(circle(w, wheelR * 1.13), with: .color(.white.opacity(paint.isLight ? 0.1 : 0.06)), lineWidth: u(0.4))
            }
        }

        // Shoulder light and door lines.
        shoulder(inPaint, r)
        doors(inPaint, r)

        // Glass.
        let glassShape = smooth(spec.glass, corners: spec.glassCorners)
        glass(ctx, glassShape)
        if spec.chromeGlass {
            ctx.stroke(glassShape, with: .color(Color(white: 0.82).opacity(0.85)), lineWidth: u(0.55))
        }
        pillars(ctx, glassShape)
        if let range = spec.glassRoof {
            let edge = Array(spec.body[range])
            // Tesla's glass roof: a dark band along the whole roofline and down the rear glass.
            let outer = edge.map { ($0.0, $0.1 + 30) }
            let inner = outer.reversed().map { ($0.0 + 30, $0.1 - 120) }
            let roofShape = smooth(outer + inner, corners: [0, outer.count - 1, outer.count, outer.count * 2 - 1])
            var roof = ctx
            roof.clip(to: body)
            let rr = roofShape.boundingRect
            roof.fill(roofShape, with: vertical(rr, [(Color(red: 0.16, green: 0.18, blue: 0.23), 0), (Color(white: 0.03), 1)]))
            roof.stroke(roofShape, with: .color(.white.opacity(0.18)), lineWidth: u(0.35))
        }

        // Lights.
        lights(ctx)

        // The details that make the model.
        signature(ctx, inPaint, r, wheels, wheelR)

        // Charge port.
        let port = pt(chargePort)
        ctx.fill(Path(roundedRect: CGRect(x: port.x - u(1.5), y: port.y - u(1), width: u(3), height: u(2)), cornerRadius: u(0.7)),
                 with: .color(paint.isLight ? Color(white: 0.7) : Color(white: 0.16)))
        if charging && on {
            ctx.clayer(blur: u(1.6), additive: true) { $0.fill(circle(port, u(2.6)), with: .color(accent.opacity(0.85))) }
            ctx.fill(circle(port, u(0.85)), with: .color(.white))
        }

        // Wheels.
        for w in wheels { wheel(ctx, w, wheelR) }
        if look.model == .polestar2 {
            // Gold brake callipers, Polestar's signature, peeking through the spokes.
            for w in wheels {
                ctx.fill(circle(w, wheelR * 0.68), with: .color(Color(white: 0.08)))
                ctx.fill(Path(roundedRect: CGRect(x: w.x + wheelR * 0.18, y: w.y - wheelR * 0.62, width: wheelR * 0.3, height: wheelR * 0.5),
                              cornerRadius: wheelR * 0.1), with: .color(Color(red: 0.86, green: 0.66, blue: 0.27)))
            }
            for w in wheels { wheelFace(ctx, w, wheelR, overCalliper: true) }
        }

        // Light along the top edge of the body.
        var top = ctx
        top.clip(to: body)
        top.stroke(body, with: vertical(r, [(.white.opacity(paint.finish == .matte ? 0.35 : 0.8), 0), (.white.opacity(0), 0.18)]),
                   lineWidth: u(1))
    }

    private var chargePort: (Double, Double) {
        let s = spec
        switch look.model {
        case .ioniq5, .ev6: return (s.rearAxle + s.tyre * 0.75, s.clearance + s.tyre * 0.95)
        case .cybertruck: return (s.rearAxle + s.tyre * 0.55, 1150)
        default:
            // Rear quarter, above the arch.
            let y = s.tail.map(\.1).min() ?? 900
            return (s.rearAxle + s.tyre * 0.62, y - 40)
        }
    }

    // MARK: Paint

    private func paintBody(_ ctx: GraphicsContext, _ body: Path, _ r: CGRect) {
        let p = paint
        switch p.finish {
        case .stainless:
            ctx.fill(body, with: vertical(r, [(Color(white: 0.9), 0), (Color(white: 0.76), 0.32), (Color(white: 0.6), 0.6),
                                             (Color(white: 0.42), 1)]))
            var brushed = ctx
            brushed.clip(to: body)
            var y = r.minY
            var i = 0
            while y < r.maxY {
                brushed.fill(Path(CGRect(x: r.minX, y: y, width: r.width, height: u(0.18))),
                             with: .color(.white.opacity(i % 3 == 0 ? 0.16 : 0.05)))
                y += u(0.55); i += 1
            }
        case .matte:
            ctx.fill(body, with: vertical(r, [(p.shade(0.18), 0), (p.color, 0.38), (p.shade(-0.18), 0.72), (p.shade(-0.42), 1)]))
        default:
            let lift = p.isLight ? 0.6 : 0.38
            ctx.fill(body, with: vertical(r, [(p.shade(lift), 0), (p.shade(0.06), 0.3), (p.color, 0.48), (p.shade(-0.28), 0.74),
                                             (p.shade(-0.55), 1)]))
        }
        var c = ctx
        c.clip(to: body)
        // The ends turn away from the light.
        c.fill(Path(r), with: .linearGradient(Gradient(stops: [.init(color: .black.opacity(0.25), location: 0), .init(color: .clear, location: 0.12),
                                                               .init(color: .clear, location: 0.88), .init(color: .black.opacity(0.3), location: 1)]),
                                              startPoint: CGPoint(x: r.minX, y: r.midY), endPoint: CGPoint(x: r.maxX, y: r.midY)))
        if p.finish == .metallic || p.finish == .pearl {
            // A soft reflection of the sky along the flank.
            c.clayer(blur: u(2.2)) {
                $0.fill(Path(ellipseIn: CGRect(x: r.minX + r.width * 0.18, y: r.minY + r.height * 0.32, width: r.width * 0.5, height: u(2.6))),
                        with: .color(.white.opacity(p.isLight ? 0.6 : 0.32)))
            }
        }
    }

    private func shoulder(_ ctx: GraphicsContext, _ r: CGRect) {
        let s = spec
        let beltFront = s.glass[0].1, beltRear = s.glass.last?.1 ?? beltFront
        let y0 = beltFront - 140, y1 = beltRear - 120
        var crease = Path()
        crease.move(to: pt((s.frontAxle - s.tyre * 0.2, y0 - 40)))
        crease.addCurve(to: pt((s.rearAxle + s.tyre * 0.6, y1)), control1: pt((s.frontAxle + 900, y0 + 10)), control2: pt((s.rearAxle - 600, y1 + 20)))
        let strength = look.model == .seal ? 0.95 : paint.isLight ? 0.75 : 0.45
        ctx.stroke(crease, with: .color(.white.opacity(strength)), lineWidth: u(look.model == .seal ? 0.8 : 0.55))
        ctx.stroke(crease.offsetBy(dx: 0, dy: u(0.8)), with: .color(.black.opacity(0.14)), lineWidth: u(0.5))
    }

    private func doors(_ ctx: GraphicsContext, _ r: CGRect) {
        let s = spec
        guard look.model != .cybertruck else {
            var lines = Path()
            for x in [s.frontAxle + s.tyre * 0.85, (s.frontAxle + s.rearAxle) / 2 + 150, s.rearAxle - s.tyre * 0.85] {
                lines.move(to: pt((x, s.clearance + 250))); lines.addLine(to: pt((x + 40, 1290)))
            }
            ctx.stroke(lines, with: .color(.black.opacity(0.25)), lineWidth: u(0.4))
            return
        }
        let wb = s.rearAxle - s.frontAxle
        let front = s.frontAxle + wb * 0.21, middle = s.frontAxle + wb * 0.57
        let rear = s.rearAxle - s.tyre * 0.62
        var seams = Path()
        let belt = s.glass[0].1
        seams.move(to: pt((front, belt))); seams.addLine(to: pt((front + 30, s.clearance + 80)))
        seams.move(to: pt((middle, belt + 30))); seams.addLine(to: pt((middle + 10, s.clearance + 80)))
        if look.model.hasFourDoorsWithRearCut { seams.move(to: pt((rear, belt + 40))); seams.addCurve(to: pt((rear - 60, s.clearance + 120)), control1: pt((rear + 120, belt - 200)), control2: pt((rear - 30, s.clearance + 300))) }
        ctx.stroke(seams, with: .color(.black.opacity(paint.isLight ? 0.2 : 0.4)), lineWidth: u(0.4))
        // Flush handles.
        for x in [front + 220, middle + 200] {
            let h = pt((x, belt - 110))
            ctx.fill(Path(roundedRect: CGRect(x: h.x, y: h.y, width: mm(260), height: u(0.7)), cornerRadius: u(0.35)),
                     with: .color(paint.isLight ? Color(white: 0.55) : Color(white: 0.75).opacity(0.7)))
        }
    }

    private func glass(_ ctx: GraphicsContext, _ shape: Path) {
        let r = shape.boundingRect
        ctx.fill(shape, with: vertical(r, [(Color(red: 0.22, green: 0.25, blue: 0.32), 0), (Color(white: 0.06), 0.55), (Color(white: 0.02), 1)]))
        var inside = ctx
        inside.clip(to: shape)
        inside.clayer(blur: min(r.width, r.height) * 0.12) {
            $0.fill(Path(ellipseIn: CGRect(x: r.minX + r.width * 0.12, y: r.minY - r.height * 0.4, width: r.width * 0.75, height: r.height * 0.8)),
                    with: .color(.white.opacity(0.3)))
        }
        inside.stroke(shape, with: .color(.white.opacity(0.12)), lineWidth: u(0.5))
    }

    /// The B-pillar, and the model-specific rear pillar treatments.
    private func pillars(_ ctx: GraphicsContext, _ glassShape: Path) {
        let s = spec
        let wb = s.rearAxle - s.frontAxle
        let bx = s.frontAxle + wb * 0.57
        var inside = ctx
        inside.clip(to: glassShape)
        let top = pt((bx, 1900)), bottom = pt((bx + 40, 0))
        inside.fill(Path(CGRect(x: top.x - mm(45), y: top.y, width: mm(90), height: bottom.y - top.y)), with: .color(Color(white: 0.02)))
    }

    private func lights(_ ctx: GraphicsContext) {
        let head = smooth(spec.head, corners: Set(spec.head.indices))
        let tail = smooth(spec.tail, corners: Set(spec.tail.indices))
        let red = Color(red: 1, green: 0.16, blue: 0.16)
        if on {
            ctx.clayer(blur: u(1.8), additive: true) { $0.fill(head, with: .color(.white.opacity(0.7))) }
            ctx.clayer(blur: u(1.6), additive: true) { $0.fill(tail, with: .color(red.opacity(0.75))) }
        }
        ctx.fill(head, with: .color(on ? .white : Color(white: 0.5)))
        ctx.fill(tail, with: .color(on ? red : Color(red: 0.35, green: 0.08, blue: 0.08)))
    }

    // MARK: Signatures

    private func signature(_ ctx: GraphicsContext, _ inPaint: GraphicsContext, _ r: CGRect, _ wheels: [CGPoint], _ wheelR: CGFloat) {
        let s = spec
        switch look.model {
        case .model3, .modelY, .modelS:
            // No grille: just a slim dark intake low in the nose.
            var intake = Path()
            intake.move(to: pt((60, 300))); intake.addLine(to: pt((320, 270)))
            inPaint.stroke(intake, with: .color(Color(white: 0.04)), style: StrokeStyle(lineWidth: u(1.1), lineCap: .round))
            if look.model == .modelS {
                // The long, low liftback's chrome-free window line kick.
                break
            }
        case .modelX:
            // The falcon wing: the rear door's cut line runs up into the roof.
            var wing = Path()
            wing.move(to: pt((2650, 1090)))
            wing.addLine(to: pt((2660, 1660)))
            wing.addCurve(to: pt((3700, 1610)), control1: pt((3000, 1690)), control2: pt((3400, 1660)))
            wing.addLine(to: pt((3680, 1060)))
            ctx.stroke(wing, with: .color(.black.opacity(0.5)), lineWidth: u(0.55))
            ctx.stroke(wing.offsetBy(dx: 0, dy: -u(0.5)), with: .color(.white.opacity(0.25)), lineWidth: u(0.35))
            // The panoramic windscreen flowing into the roof.
            var screen = Path()
            screen.move(to: pt((1380, 1010))); screen.addLine(to: pt((2050, 1600))); screen.addLine(to: pt((2350, 1660)))
            ctx.stroke(screen, with: .color(Color(white: 0.06)), style: StrokeStyle(lineWidth: u(1.2), lineCap: .round))
        case .cybertruck:
            // The light bars across the nose and tail.
            var bar = Path()
            bar.move(to: pt((0, 1112))); bar.addLine(to: pt((900, 1262)))
            ctx.clayer(blur: u(1.4), additive: on) { $0.stroke(bar, with: .color(.white.opacity(on ? 0.7 : 0.2)), lineWidth: u(1.2)) }
            ctx.stroke(bar, with: .color(on ? .white : Color(white: 0.6)), lineWidth: u(0.55))
            var tailBar = Path()
            tailBar.move(to: pt((5683, 1285))); tailBar.addLine(to: pt((5200, 1365)))
            ctx.stroke(tailBar, with: .color(on ? Color(red: 1, green: 0.2, blue: 0.2) : Color(red: 0.4, green: 0.1, blue: 0.1)), lineWidth: u(0.55))
            // The bed's tonneau line.
            var bed = Path()
            bed.move(to: pt((3550, 1560))); bed.addLine(to: pt((3600, 1310)))
            ctx.stroke(bed, with: .color(.black.opacity(0.35)), lineWidth: u(0.45))
        case .seal:
            // The "ocean wave" drop falling from the headlight.
            var drop = Path()
            drop.move(to: pt((260, 650)))
            drop.addCurve(to: pt((110, 300)), control1: pt((250, 520)), control2: pt((140, 400)))
            ctx.stroke(drop, with: .color(on ? .white.opacity(0.9) : Color(white: 0.55)), style: StrokeStyle(lineWidth: u(0.6), lineCap: .round))
            // The lightbar runs the width of the tail and along the deck.
            var bar = Path()
            bar.move(to: pt((4150, 1050))); bar.addCurve(to: pt((4795, 960)), control1: pt((4450, 1020)), control2: pt((4650, 985)))
            ctx.stroke(bar, with: .color(on ? Color(red: 1, green: 0.2, blue: 0.2) : Color(red: 0.4, green: 0.1, blue: 0.1)),
                       style: StrokeStyle(lineWidth: u(0.6), lineCap: .round))
        case .atto3:
            // The chrome strip curving up the rear pillar, over the blacked-out floating roof.
            var strip = Path()
            strip.move(to: pt((3620, 1180)))
            strip.addCurve(to: pt((4150, 1440)), control1: pt((3900, 1230)), control2: pt((4060, 1330)))
            ctx.stroke(strip, with: .linearGradient(Gradient(colors: [Color(white: 0.95), Color(white: 0.6)]),
                                                    startPoint: pt((3620, 1300)), endPoint: pt((4150, 1300))),
                       style: StrokeStyle(lineWidth: u(1.1), lineCap: .round))
            // Roof rails.
            var rail = Path()
            rail.move(to: pt((2100, 1630))); rail.addLine(to: pt((3800, 1615)))
            ctx.stroke(rail, with: .color(Color(white: 0.7)), style: StrokeStyle(lineWidth: u(0.6), lineCap: .round))
        case .dolphin:
            // The fin-like crease sweeping up into the rear pillar.
            var fin = Path()
            fin.move(to: pt((1200, 560)))
            fin.addCurve(to: pt((3650, 1240)), control1: pt((2300, 600)), control2: pt((3200, 820)))
            inPaint.stroke(fin, with: .color(.white.opacity(paint.isLight ? 0.85 : 0.5)), lineWidth: u(0.6))
            inPaint.stroke(fin.offsetBy(dx: 0, dy: u(0.7)), with: .color(.black.opacity(0.2)), lineWidth: u(0.5))
        case .ioniq5:
            // Parametric pixels: square clusters front and rear.
            pixels(ctx, x: 30, y: 700, cols: 3, rows: 2, color: on ? .white : Color(white: 0.55))
            pixels(ctx, x: 4485, y: 1080, cols: 2, rows: 3, color: on ? Color(red: 1, green: 0.2, blue: 0.2) : Color(red: 0.4, green: 0.1, blue: 0.1))
            // The diagonal Z crease across the doors, and the clamshell bonnet's line.
            var z = Path()
            z.move(to: pt((1150, 860))); z.addLine(to: pt((3350, 420)))
            inPaint.stroke(z, with: .color(.white.opacity(paint.isLight ? 0.8 : 0.45)), lineWidth: u(0.55))
            inPaint.stroke(z.offsetBy(dx: 0, dy: u(0.7)), with: .color(.black.opacity(0.22)), lineWidth: u(0.5))
            var clam = Path()
            clam.move(to: pt((80, 820))); clam.addLine(to: pt((1300, 960)))
            inPaint.stroke(clam, with: .color(.black.opacity(0.3)), lineWidth: u(0.4))
        case .ev6:
            // The tail light sweeps forward over the rear wheel: drawn as the tail shape already.
            var haunch = Path()
            haunch.move(to: pt((3300, 980))); haunch.addCurve(to: pt((4600, 1020)), control1: pt((3800, 1010)), control2: pt((4300, 1040)))
            inPaint.stroke(haunch, with: .color(.white.opacity(0.35)), lineWidth: u(0.4))
        case .i4:
            // The kidney grille, tall and blanked, and the air breather behind the front wheel.
            let kidney = Path(roundedRect: CGRect(origin: pt((0, 600)), size: CGSize(width: mm(130), height: mm(330))), cornerRadius: mm(55))
            ctx.fill(kidney, with: .color(Color(white: 0.08)))
            ctx.stroke(kidney, with: .color(Color(white: 0.85)), lineWidth: u(0.45))
            var breather = Path()
            breather.move(to: pt((s.frontAxle + s.tyre * 0.75, 560))); breather.addLine(to: pt((s.frontAxle + s.tyre * 0.82, 760)))
            ctx.stroke(breather, with: .color(Color(white: 0.05)), style: StrokeStyle(lineWidth: u(1), lineCap: .round))
        case .polestar2:
            // Frameless mirror and a full-width rear light bar.
            var bar = Path()
            bar.move(to: pt((4380, 1085))); bar.addLine(to: pt((4604, 1060)))
            ctx.stroke(bar, with: .color(on ? Color(red: 1, green: 0.2, blue: 0.2) : Color(red: 0.4, green: 0.1, blue: 0.1)), lineWidth: u(0.7))
        case .generic:
            break
        }
        // A mirror on everything but the Cybertruck, whose mirror sits in the A-pillar line.
        if look.model != .cybertruck {
            let g = spec.glass[0]
            let m = pt((g.0 + 60, g.1 + 120))
            ctx.fill(Path(roundedRect: CGRect(x: m.x - mm(80), y: m.y - mm(60), width: mm(230), height: mm(110)), cornerRadius: mm(50)),
                     with: .color(look.model == .polestar2 ? Color(white: 0.1) : paint.shade(-0.15)))
        }
    }

    private func pixels(_ ctx: GraphicsContext, x: Double, y: Double, cols: Int, rows: Int, color: Color) {
        let cell = 46.0, gap = 22.0
        for c in 0..<cols {
            for r in 0..<rows {
                let o = pt((x + Double(c) * (cell + gap), y + Double(rows - r) * (cell + gap)))
                let sq = Path(CGRect(x: o.x, y: o.y, width: mm(cell), height: mm(cell)))
                if on { ctx.clayer(blur: u(0.6), additive: true) { $0.fill(sq, with: .color(color.opacity(0.6))) } }
                ctx.fill(sq, with: .color(color))
            }
        }
    }

    private func cyberArch(_ c: CGPoint, _ r: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: c.x - r * 1.42, y: c.y + r * 1.2))
        p.addLine(to: CGPoint(x: c.x - r * 1.0, y: c.y - r * 1.08))
        p.addLine(to: CGPoint(x: c.x + r * 1.0, y: c.y - r * 1.08))
        p.addLine(to: CGPoint(x: c.x + r * 1.42, y: c.y + r * 1.2))
        p.closeSubpath()
        return p
    }

    // MARK: Wheels

    private func wheel(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        ctx.fill(circle(c, r), with: .radialGradient(Gradient(colors: [Color(white: 0.17), Color(white: 0.07), Color(white: 0.02)]),
                                                     center: CGPoint(x: c.x, y: c.y - r * 0.3), startRadius: 0, endRadius: r))
        ctx.stroke(circle(c, r - u(0.3)), with: vertical(CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2),
                                                          [(.white.opacity(0.2), 0), (.clear, 0.45)]), lineWidth: u(0.5))
        wheelFace(ctx, c, r, overCalliper: false)
    }

    private func wheelFace(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat, overCalliper: Bool) {
        let rim = r * (look.model == .cybertruck ? 0.6 : 0.68)
        let metal = GraphicsContext.Shading.linearGradient(Gradient(colors: [Color(white: 0.9), Color(white: 0.55), Color(white: 0.25)]),
                                                           startPoint: CGPoint(x: c.x - rim, y: c.y - rim), endPoint: CGPoint(x: c.x + rim, y: c.y + rim))
        let dark = Color(white: 0.08)
        switch spec.wheels {
        case .aero:
            // Tesla's aero cover: a smooth disc with soft scoops.
            if !overCalliper { ctx.fill(circle(c, rim), with: metal) }
            var scoops = Path()
            for i in 0..<5 {
                let a = Double(i) / 5 * 2 * .pi - .pi / 2
                scoops.addEllipse(in: CGRect(x: c.x + cos(a) * rim * 0.58 - rim * 0.16, y: c.y + sin(a) * rim * 0.58 - rim * 0.16,
                                             width: rim * 0.32, height: rim * 0.32))
            }
            ctx.fill(scoops, with: .color(dark.opacity(0.85)))
        case .turbine:
            if !overCalliper { ctx.fill(circle(c, rim), with: metal) }
            var blades = Path()
            for i in 0..<10 {
                let a = Double(i) / 10 * 2 * .pi
                blades.move(to: CGPoint(x: c.x + cos(a) * rim * 0.3, y: c.y + sin(a) * rim * 0.3))
                blades.addQuadCurve(to: CGPoint(x: c.x + cos(a + 0.5) * rim * 0.92, y: c.y + sin(a + 0.5) * rim * 0.92),
                                    control: CGPoint(x: c.x + cos(a + 0.05) * rim * 0.7, y: c.y + sin(a + 0.05) * rim * 0.7))
            }
            ctx.stroke(blades, with: .color(dark.opacity(0.8)), lineWidth: max(u(0.35), rim * 0.07))
        case .spokes(let n):
            if !overCalliper { ctx.fill(circle(c, rim), with: .color(dark)) }
            var spokes = Path()
            for i in 0..<n {
                let a = Double(i) / Double(n) * 2 * .pi - .pi / 2
                spokes.move(to: c)
                spokes.addLine(to: CGPoint(x: c.x + cos(a) * rim * 0.97, y: c.y + sin(a) * rim * 0.97))
            }
            ctx.stroke(spokes, with: metal, style: StrokeStyle(lineWidth: rim * (n > 6 ? 0.12 : 0.22), lineCap: .round))
            ctx.stroke(circle(c, rim * 0.96), with: metal, lineWidth: rim * 0.08)
        case .twin:
            ctx.fill(circle(c, rim), with: .color(dark))
            var spokes = Path()
            for i in 0..<5 {
                let a = Double(i) / 5 * 2 * .pi - .pi / 2
                for d in [-0.13, 0.13] {
                    spokes.move(to: c)
                    spokes.addLine(to: CGPoint(x: c.x + cos(a + d) * rim * 0.96, y: c.y + sin(a + d) * rim * 0.96))
                }
            }
            ctx.stroke(spokes, with: metal, style: StrokeStyle(lineWidth: rim * 0.1, lineCap: .round))
        case .pixel:
            // Ioniq 5's parametric pixel wheel: a disc cut with a ring of squares.
            ctx.fill(circle(c, rim), with: metal)
            for ring in [0.42, 0.74] {
                let count = ring < 0.5 ? 6 : 12
                for i in 0..<count {
                    let a = Double(i) / Double(count) * 2 * .pi
                    let side = rim * (ring < 0.5 ? 0.2 : 0.16)
                    let p = CGPoint(x: c.x + cos(a) * rim * ring, y: c.y + sin(a) * rim * ring)
                    ctx.fill(Path(CGRect(x: p.x - side / 2, y: p.y - side / 2, width: side, height: side)), with: .color(dark))
                }
            }
        case .cyber:
            // A flat aero cover, almost the tyre's size.
            var hex = Path()
            for i in 0..<6 {
                let a = Double(i) / 6 * 2 * .pi
                let p = CGPoint(x: c.x + cos(a) * rim, y: c.y + sin(a) * rim)
                i == 0 ? hex.move(to: p) : hex.addLine(to: p)
            }
            hex.closeSubpath()
            ctx.fill(hex, with: .color(Color(white: 0.24)))
            ctx.stroke(hex, with: .color(Color(white: 0.45)), lineWidth: u(0.35))
        }
        ctx.fill(circle(c, rim * 0.18), with: .color(Color(white: 0.7)))
        ctx.stroke(circle(c, rim), with: .color(.black.opacity(0.35)), lineWidth: u(0.3))
    }
}

private extension CarModel {
    var hasFourDoorsWithRearCut: Bool { false }
}

private extension GraphicsContext {
    func clayer(blur: CGFloat = 0, additive: Bool = false, _ draw: (inout GraphicsContext) -> Void) {
        var c = self
        if blur > 0 { c.addFilter(.blur(radius: blur)) }
        if additive { c.blendMode = .plusLighter }
        draw(&c)
    }
}

// MARK: Contact sheet (development)

/// `--render-cars <folder>` draws every model in a few paints, for checking the likenesses.
@MainActor
enum CarSheet {
    static func export(to folder: String) {
        let models = CarModel.allCases
        for dark in [true, false] {
            let view = VStack(alignment: .leading, spacing: 6) {
                ForEach(models) { m in
                    HStack(spacing: 10) {
                        Text(m == .generic ? "Generic EV" : m == .polestar2 ? "Polestar 2" : "\(m.maker) \(m.name)").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(dark ? .white : .black).frame(width: 130, alignment: .leading)
                        ForEach(Array(m.palette.prefix(3)), id: \.self) { p in
                            CarArtView(look: CarLook(model: m, paint: p), charging: p == m.palette.first, size: 150)
                        }
                        CarArtView(look: CarLook(model: m, paint: m.palette[0]), size: 76)
                    }
                    .frame(height: 96)
                }
            }
            .padding(16)
            .background(dark ? Color(red: 0.06, green: 0.06, blue: 0.07) : Color(red: 0.95, green: 0.95, blue: 0.96))
            let r = ImageRenderer(content: view)
            r.scale = 2
            if let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("cars-\(dark ? "dark" : "light").png"))
            }
        }
    }
}
