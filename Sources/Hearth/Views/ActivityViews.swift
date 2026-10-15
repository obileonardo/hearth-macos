import SwiftUI

struct ActivityPage: View {
    @EnvironmentObject var store: HomeStore
    @EnvironmentObject var log: ActivityLog
    @Environment(\.hearthOpenWindow) private var openWindow
    let shown: Bool
    @State private var filter: ActivityLog.Kind?
    @State private var displayedFilter: ActivityLog.Kind?
    @State private var feedOpacity = 1.0
    @State private var filterGeneration = 0
    @State private var showAlerts = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A face to name, opened from "Who's this?"; shows Familiar faces in place of the timeline.
    @State private var naming: UUID?
    @ObservedObject private var faces = FaceLibrary.shared

    private var visible: [ActivityLog.Item] {
        log.items.filter { displayedFilter == nil || $0.kind == displayedFilter }
    }

    /// One thing that happened: a camera's person, movement and pet events within a minute of
    /// each other read as a single moment, led by the most telling of them.
    struct Moment: Identifiable {
        var items: [ActivityLog.Item]
        var lead: ActivityLog.Item {
            items.max { Moment.rank($0.kind) < Moment.rank($1.kind) } ?? items[0]
        }
        /// The picture to show: the lead's, or any picture in the moment.
        var picture: String? { lead.imageFile ?? items.first { $0.imageFile != nil }?.imageFile }
        var faceSample: UUID? { lead.faceSample ?? items.first { $0.faceSample != nil }?.faceSample }
        var id: UUID { items[0].id }
        var date: Date { items[0].date }

        static func rank(_ kind: ActivityLog.Kind) -> Int {
            switch kind {
            case .person: 4
            case .pet: 3
            case .sound: 2
            case .motion: 1
            default: 0
            }
        }
        static let mergeable: Set<ActivityLog.Kind> = [.person, .pet, .sound, .motion]
    }

    /// Which camera or device an event came from, for merging.
    private func source(_ item: ActivityLog.Item) -> String {
        item.cameraID ?? store.registry[item.entityID]?.deviceID ?? item.entityID
    }

    private var moments: [Moment] {
        var out: [Moment] = []
        for item in visible.prefix(240) {
            if Moment.mergeable.contains(item.kind), var last = out.last,
               Moment.mergeable.contains(last.items[0].kind),
               source(last.items[0]) == source(item),
               last.items[last.items.count - 1].date.timeIntervalSince(item.date) < 60 {
                last.items.append(item)
                out[out.count - 1] = last
            } else {
                out.append(Moment(items: [item]))
            }
        }
        return out
    }

    private var days: [(String, [Moment])] {
        let cal = Calendar.current
        var out: [(String, [Moment])] = []
        for item in moments.prefix(120) {
            let label = cal.isDateInToday(item.date) ? "Today"
                : cal.isDateInYesterday(item.date) ? "Yesterday"
                : item.date.formatted(.dateTime.weekday(.wide).day().month())
            if out.last?.0 == label { out[out.count - 1].1.append(item) } else { out.append((label, [item])) }
        }
        return out
    }

    private enum Route: Equatable {
        case timeline, preferences, face(UUID)
    }

    private var route: Route {
        if let naming { return .face(naming) }
        return showAlerts ? .preferences : .timeline
    }

    var body: some View {
        ScreenFlow(route: route, depth: route == .timeline ? 0 : 1) { displayed in
            switch displayed {
            case .face(let id):
                FacesPage(focus: id, back: { naming = nil })
            case .preferences:
                alertSettings
            case .timeline:
                timeline
            }
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(eyebrow: summary, title: "Activity",
                       pinnedSymbols: ["bell.fill", "figure.walk.motion", "shield.lefthalf.filled"]) {
                Button {
                    showAlerts = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .regular))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Theme.fg.opacity(showAlerts ? 0.12 : 0.05)).overlay(Circle().strokeBorder(Theme.hairline)))
                }
                .buttonStyle(PressStyle())
                .help("Notification preferences")
                .accessibilityLabel("Notification preferences")
            }
            .reveal(shown, 0)

            // A single equal-width tray keeps every filter visible without
            // horizontal clipping or partially cut-off pills at the panel edge.
            HStack(spacing: 0) {
                ForEach(Array(Self.filterKinds.enumerated()), id: \.offset) { index, kind in
                    filterButton(kind, kind?.label ?? "All").selectionFrame(index)
                }
            }
            .slidingSelection(Self.filterKinds.firstIndex { $0 == filter }, radius: 11)
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.tray)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline)))
            .reveal(shown, 1)

            activityFeed.opacity(feedOpacity)
        }
        .onAppear { log.markAllRead() }
        .onChange(of: log.items.count) { _, _ in log.markAllRead() }
        .onDisappear {
            filterGeneration += 1
            displayedFilter = filter
            feedOpacity = 1
        }
    }

    private var activityFeed: some View {
        VStack(alignment: .leading, spacing: 14) {
            if visible.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles").font(.system(size: 22, weight: .ultraLight)).foregroundStyle(Theme.faint)
                    Text("All quiet").font(.system(size: 14, weight: .semibold))
                    Text("People, the doorbell and motion will show up here as they happen.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }

            ForEach(Array(days.enumerated()), id: \.element.0) { di, day in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(day.0.uppercased()).eyebrow()
                        Spacer()
                        Text("\(day.1.count) \(day.1.count == 1 ? "moment" : "moments")")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.faint).monospacedDigit()
                    }
                    .padding(.horizontal, 4)
                    Bezel(radius: 20, inset: 3) {
                        VStack(spacing: 0) {
                            ForEach(Array(day.1.enumerated()), id: \.element.id) { i, moment in
                                row(moment)
                                if i < day.1.count - 1 {
                                    Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.leading, 74).padding(.trailing, 10)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .reveal(shown, 2 + di)
            }
        }
        // Filtering replaces the feed; it does not fold the old card into the new card's height.
        .animation(nil, value: displayedFilter)
    }

    private func selectFilter(_ kind: ActivityLog.Kind?) {
        guard filter != kind else { return }
        filter = kind
        filterGeneration += 1
        let generation = filterGeneration
        guard !reduceMotion else {
            displayedFilter = kind
            feedOpacity = 1
            return
        }
        withAnimation(.easeOut(duration: 0.10)) { feedOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard generation == filterGeneration else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { displayedFilter = kind }
            // Give the replacement feed its final layout before bringing its text back.
            DispatchQueue.main.async {
                guard generation == filterGeneration else { return }
                withAnimation(.easeOut(duration: 0.16)) { feedOpacity = 1 }
            }
        }
    }

    private var summary: String {
        let today = log.items.filter { Calendar.current.isDateInToday($0.date) }
        let people = today.filter { $0.kind == .person }.count
        return people > 0 ? "\(people) \(people == 1 ? "person" : "people") seen today" : "\(today.count) events today"
    }

    static let filterKinds: [ActivityLog.Kind?] = [nil, .person, .doorbell, .motion, .security, .climate]

    private func filterButton(_ kind: ActivityLog.Kind?, _ label: String) -> some View {
        let on = filter == kind
        return Button {
            selectFilter(kind)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: kind?.symbol ?? "line.3.horizontal.decrease")
                    .font(.system(size: 13, weight: .medium))
                Text(label).font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(on ? Theme.onKey : Theme.muted)
            .frame(maxWidth: .infinity).frame(height: 44)
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var alertSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            SubpageHeader(eyebrow: "Activity", title: "Notifications", back: { showAlerts = false }) { EmptyView() }
            Text("Choose which events notify you. All events still appear in Activity.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            notificationGroup("PEOPLE & SECURITY", kinds: [.person, .doorbell, .security])
            notificationGroup("AROUND THE HOME", kinds: [.motion, .pet, .sound, .climate])
        }
    }

    private func notificationGroup(_ title: String, kinds: [ActivityLog.Kind]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).eyebrow().padding(.leading, 4)
            Bezel(radius: 20, inset: 3) {
                VStack(spacing: 0) {
                    ForEach(Array(kinds.enumerated()), id: \.element.id) { index, kind in
                        ControlRow(symbol: kind.symbol, label: kind.label, lit: log.notifies(kind)) {
                            GlowSwitch(isOn: log.notifies(kind)) { log.setNotifies(kind, !log.notifies(kind)) }
                        }
                        if index < kinds.count - 1 {
                            Rectangle().fill(Theme.hairline).frame(height: 0.5)
                                .padding(.leading, 42).padding(.trailing, 12)
                        }
                    }
                }.padding(.vertical, 3)
            }
        }
    }

    private func row(_ moment: Moment) -> some View {
        let item = moment.lead
        let picture = moment.picture
        let sample = moment.faceSample
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return Button {
            guard let cam = moment.items.first(where: { $0.cameraID != nil })?.cameraID else { return }
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "camera", value: cam)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    if let path = picture, let image = NSImage(contentsOfFile: path) {
                        shape.fill(Color.black)
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).privacyBlurred()
                    } else {
                        // No picture: a quiet plate in the event's own colour, the same size as a thumbnail.
                        shape.fill(tint(item.kind).opacity(0.1))
                        Image(systemName: item.kind.symbol).font(.system(size: 14, weight: .regular)).foregroundStyle(tint(item.kind))
                    }
                }
                .frame(width: 52, height: 38)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 0.5))
                .overlay(alignment: .bottomTrailing) {
                    if let sample, faces.person(ofSample: sample) != nil {
                        FaceAvatar(sample: faces.person(ofSample: sample)?.best?.id, size: 20).offset(x: 6, y: 6)
                    } else if picture != nil {
                        Image(systemName: item.kind.symbol).font(.system(size: 7.5, weight: .bold)).foregroundStyle(Theme.onAccent)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(tint(item.kind)).overlay(Circle().strokeBorder(Theme.raised, lineWidth: 1.5)))
                            .offset(x: 5, y: 5)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                        if moment.items.count > 2 {
                            Text("\(moment.items.count)×").font(.system(size: 10.5, weight: .bold)).monospacedDigit()
                                .foregroundStyle(Theme.muted)
                                .padding(.horizontal, 5).frame(height: 16)
                                .background(Capsule().fill(Theme.fg.opacity(0.07)))
                                .help("\(moment.items.count) events within a minute")
                        }
                    }
                    Text([item.place, moment.date.formatted(date: .omitted, time: .shortened)].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 12)).foregroundStyle(Theme.muted).monospacedDigit().lineLimit(1)
                }
                Spacer(minLength: 4)
                if let sample, faces.enabled, faces.person(ofSample: sample) == nil, faces.group(ofSample: sample) != nil {
                    Button { withAnimation(.glide) { naming = sample } } label: {
                        Text("Who's this?").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.sand)
                            .padding(.horizontal, 8).frame(height: 22).background(Capsule().fill(Theme.sand.opacity(0.14)))
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Name the face in this picture")
                } else {
                    Text(moment.date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                        .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.faint).monospacedDigit()
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .contentShape(Rectangle())
            .hoverFill(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressStyle())
    }

    private func tint(_ kind: ActivityLog.Kind) -> Color {
        switch kind {
        case .person: Theme.sand
        case .doorbell: Color.accent(0.45, 0.75, 1.0)
        case .security: Theme.ok
        case .climate: Theme.air("cool")
        default: Theme.fg.opacity(0.8)
        }
    }
}
