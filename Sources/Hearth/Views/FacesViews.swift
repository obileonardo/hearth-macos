import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A round face picture from the library, or a quiet placeholder.
struct FaceAvatar: View {
    let sample: UUID?
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle().fill(Theme.fg.opacity(0.06))
            if let sample, let image = FaceLibrary.shared.crop(sample) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).privacyBlurred()
            } else {
                Image(systemName: "person.fill").font(.system(size: size * 0.42, weight: .light)).foregroundStyle(Theme.faint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.fg.opacity(0.16), lineWidth: 0.75))
        .accessibilityHidden(true)
    }
}

/// Everyone Hearth has learned to recognise, and the faces still waiting for a name.
struct FacesPage: View {
    @ObservedObject private var faces = FaceLibrary.shared
    @EnvironmentObject var log: ActivityLog
    /// An unnamed group to bring to the top, e.g. from "Who's this?" in Activity.
    var focus: UUID?
    var back: (() -> Void)?
    @State private var openPerson: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !faces.enabled {
                intro
            } else {
                status
                if !faces.people.isEmpty {
                    Text("PEOPLE").eyebrow().padding(.leading, 4)
                    VStack(spacing: 8) {
                        ForEach(faces.people) { person in
                            PersonCard(person: person, open: openPerson == person.id) {
                                withAnimation(.glide) { openPerson = openPerson == person.id ? nil : person.id }
                            }
                        }
                    }
                }
                if !groups.isEmpty {
                    Text("WHO ARE THESE?").eyebrow().padding(.leading, 4)
                    VStack(spacing: 8) {
                        ForEach(groups) { group in
                            UnknownCard(group: group, highlighted: group.samples.contains { $0.id == focus } || group.id == focus)
                        }
                    }
                }
                if faces.people.isEmpty && faces.unknown.isEmpty { emptyState }
                note
            }
        }
        .animation(.glide, value: faces.people)
        .animation(.glide, value: faces.unknown)
    }

    /// The focused group first, then the rest, newest first.
    private var groups: [FaceLibrary.Group] {
        let focused = faces.unknown.filter { g in g.id == focus || g.samples.contains { $0.id == focus } }
        return focused + faces.unknown.filter { g in !focused.contains(g) }
    }

    @ViewBuilder
    private var header: some View {
        let eyebrow = faces.enabled ? "\(faces.people.count) known · \(faces.unknown.count) to name" : "On this Mac only"
        if let back {
            SubpageHeader(eyebrow: eyebrow, title: "Familiar faces", back: back) { addButton }
        } else {
            PageHeader(eyebrow: eyebrow, title: "Familiar faces",
                       pinnedSymbols: ["person.crop.circle", "person.2", "face.smiling"]) { addButton }
        }
    }

    @ViewBuilder
    private var addButton: some View {
        if faces.enabled {
            Button { choosePhotos(for: nil) } label: {
                Image(systemName: "photo.badge.plus").font(.system(size: 14, weight: .regular))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.fg.opacity(0.05)).overlay(Circle().strokeBorder(Theme.hairline)))
            }
            .buttonStyle(PressStyle())
            .help("Teach Hearth a face from a photo")
            .accessibilityLabel("Add a photo of someone")
        }
    }

    private var intro: some View {
        Bezel(radius: 22, inset: 3) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.checkmark").font(.system(size: 22, weight: .light)).foregroundStyle(Theme.sand)
                    Text("Recognise the people you know").font(.system(size: 14, weight: .semibold))
                }
                Text("Hearth learns faces from your own camera pictures, on this Mac only. Nothing is uploaded. Name someone once and Hearth can say who's at the door next time.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                Button {
                    faces.setEnabled(true)
                    Task { await log.learnFaces() }
                } label: {
                    Text("Turn on Familiar faces").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.onCTA)
                        .padding(.horizontal, 16).frame(height: 32).background(Capsule().fill(Theme.cta))
                }
                .buttonStyle(PressStyle())
            }
            .padding(14)
        }
    }

    private var status: some View {
        HStack(spacing: 8) {
            if faces.working { ProgressView().controlSize(.small) }
            Text(faces.working ? "Looking at pictures…"
                 : "Looked at \(faces.lookedAt) picture\(faces.lookedAt == 1 ? "" : "s") · \(faces.usable) clear face\(faces.usable == 1 ? "" : "s")")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
        .padding(.leading, 4)
    }

    private var emptyState: some View {
        Bezel(radius: 22, inset: 3) {
            VStack(alignment: .leading, spacing: 8) {
                Text("No clear faces yet").font(.system(size: 14, weight: .semibold))
                Text("Camera event pictures are often small, and a face needs to be large and facing the camera to be learned. Doorbell pictures work best. You can also teach Hearth from a clear photo of someone.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                Button { choosePhotos(for: nil) } label: {
                    HStack(spacing: 8) {
                        Text("Add a photo").font(.system(size: 13, weight: .semibold))
                        Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                            .frame(width: 20, height: 20).background(Circle().fill(Theme.onCTA.opacity(0.1)))
                    }
                    .foregroundStyle(Theme.onCTA).padding(.leading, 14).padding(.trailing, 4).frame(height: 30)
                    .background(Capsule().fill(Theme.cta))
                }
                .buttonStyle(PressStyle())
            }
            .padding(14)
        }
    }

    private var note: some View {
        Text("Suggestions can be wrong. Naming more pictures of someone makes them better. Faces stay in this Mac's Application Support folder.")
            .font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func choosePhotos(for person: UUID?) {
        FacesPage.choosePhotos(for: person)
    }

    /// Opens a file picker for photos and teaches each one's clearest face.
    static func choosePhotos(for person: UUID?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "Choose clear photos where the face is large and facing the camera."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task { await FaceLibrary.shared.addPhotos(urls, to: person) }
    }
}

/// A named person: avatar, name and when they were last seen; opens to their pictures.
private struct PersonCard: View {
    @ObservedObject private var faces = FaceLibrary.shared
    let person: FaceLibrary.Person
    let open: Bool
    let toggle: () -> Void
    @State private var newName = ""
    @State private var confirmDelete = false

    var body: some View {
        Bezel(radius: 20, inset: 3) {
            VStack(alignment: .leading, spacing: 12) {
                Button(action: toggle) {
                    HStack(spacing: 12) {
                        FaceAvatar(sample: person.best?.id, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(person.name).font(.system(size: 14, weight: .semibold))
                            Text(seenLine).font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                            .rotationEffect(.degrees(open ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("\(person.name), \(seenLine)")

                if open {
                    CropGrid(samples: person.samples)
                    HStack(spacing: 8) {
                        HearthField(label: "New name for \(person.name)", placeholder: "Rename", text: $newName) { rename() }
                        Button("Save", action: rename).buttonStyle(PressStyle())
                            .font(.system(size: 13, weight: .semibold)).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    HStack {
                        Button { FacesPage.choosePhotos(for: person.id) } label: {
                            Label("Add photos", systemImage: "photo.badge.plus").font(.system(size: 12.5, weight: .medium))
                        }
                        .buttonStyle(PressStyle())
                        Spacer()
                        Button(confirmDelete ? "Tap again to delete" : "Delete \(person.name)") {
                            if confirmDelete { faces.delete(person: person.id) } else {
                                confirmDelete = true
                                Task { try? await Task.sleep(for: .seconds(4)); confirmDelete = false }
                            }
                        }
                        .buttonStyle(PressStyle())
                        .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.live)
                    }
                    .foregroundStyle(Theme.muted)
                }
            }
            .padding(12)
        }
    }

    private var seenLine: String {
        let pictures = "\(person.samples.count) picture\(person.samples.count == 1 ? "" : "s")"
        guard let seen = person.lastSeen else { return pictures }
        return "Seen \(seen.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))) · \(pictures)"
    }

    private func rename() {
        faces.rename(person.id, to: newName)
        newName = ""
    }
}

/// Faces that look alike, waiting for a name.
private struct UnknownCard: View {
    @ObservedObject private var faces = FaceLibrary.shared
    let group: FaceLibrary.Group
    let highlighted: Bool
    @State private var name = ""

    var body: some View {
        Bezel(radius: 20, inset: 3, lit: highlighted, tint: Theme.sand) {
            VStack(alignment: .leading, spacing: 12) {
                CropGrid(samples: group.samples)
                HStack(spacing: 8) {
                    HearthField(label: "Who is this?", placeholder: "Who is this?", text: $name) { save() }
                    Button("Save", action: save).buttonStyle(PressStyle())
                        .font(.system(size: 13, weight: .semibold)).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                HStack(spacing: 16) {
                    if !faces.people.isEmpty {
                        Button {
                            PopupMenu.show(faces.people.map(\.name), selected: nil, label: { $0 }) { chosen in
                                if let p = faces.people.first(where: { $0.name == chosen }) { faces.merge(group.id, into: p.id) }
                            }
                        } label: {
                            Label("Same as…", systemImage: "person.2").font(.system(size: 12.5, weight: .medium))
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("This is someone already named")
                    }
                    Spacer()
                    Button("Don't remember") { faces.dismiss(group: group.id) }
                        .buttonStyle(PressStyle()).font(.system(size: 12.5, weight: .medium))
                        .help("Forget these pictures")
                }
                .foregroundStyle(Theme.muted)
            }
            .padding(12)
        }
    }

    private func save() {
        faces.name(group.id, as: name)
        name = ""
    }
}

/// Face pictures in a row that wraps, each with a way to take a wrong one out.
private struct CropGrid: View {
    @ObservedObject private var faces = FaceLibrary.shared
    let samples: [FaceLibrary.Sample]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(52), spacing: 8), count: 6), alignment: .leading, spacing: 8) {
            ForEach(samples.sorted { $0.date > $1.date }.prefix(18)) { sample in
                Group {
                    if let image = faces.crop(sample.id) {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).privacyBlurred()
                    } else {
                        Theme.fg.opacity(0.06)
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.fg.opacity(0.14), lineWidth: 0.75))
                    .overlay(alignment: .topTrailing) {
                        Button { faces.remove(sample: sample.id) } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.ink)
                                .frame(width: 18, height: 18).background(Circle().fill(.black.opacity(0.7)))
                        }
                        .buttonStyle(PressStyle())
                        .offset(x: 4, y: -4)
                        .help("Not this person")
                        .accessibilityLabel("Remove this picture")
                    }
            }
        }
    }
}

/// The Familiar faces row in Settings: the switch, what it does, and a way to forget everything.
struct FacesSettingsRow: View {
    @ObservedObject private var faces = FaceLibrary.shared
    @EnvironmentObject var log: ActivityLog
    @Environment(\.hearthOpenWindow) private var openWindow
    @State private var confirmForget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FAMILIAR FACES").eyebrow().padding(.leading, 4)
            Bezel(radius: 18, inset: 3) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle").font(.system(size: 12)).foregroundStyle(Theme.muted).frame(width: 18)
                        Text("Recognise faces").font(.system(size: 13, weight: .medium))
                        Spacer()
                        Toggle("Recognise faces", isOn: Binding(get: { faces.enabled }, set: { on in
                            faces.setEnabled(on)
                            if on { Task { await log.learnFaces() } }
                        }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                    .padding(.horizontal, 12).frame(height: 36)
                    HStack {
                        Button("Manage faces") {
                            NSApp.activate(ignoringOtherApps: true)
                            openWindow(id: "faces")
                        }
                        .buttonStyle(PressStyle()).font(.system(size: 13, weight: .medium))
                        Spacer()
                        Button(confirmForget ? "Tap again to forget" : "Forget all faces") {
                            if confirmForget { faces.forgetAll(); confirmForget = false } else {
                                confirmForget = true
                                Task { try? await Task.sleep(for: .seconds(4)); confirmForget = false }
                            }
                        }
                        .buttonStyle(PressStyle()).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.live)
                    }
                    .padding(.horizontal, 12).frame(height: 36)
                }
            }
            Text("Hearth learns faces from your own camera pictures, on this Mac only. Nothing is uploaded.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Familiar faces in a window of its own, opened from Settings.
struct FacesWindow: View {
    var body: some View {
        ScrollView {
            FacesPage().padding(22)
        }
        .frame(minWidth: 460, minHeight: 520)
        .background(Theme.base)
        .foregroundStyle(Theme.ink)
    }
}
