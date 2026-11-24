import SwiftUI

/// History snapshots: keep the document as it is now under a name and come back to it later with
/// one click, however far the 60-step history has moved on. Restoring is itself one undo step.
/// Snapshots belong to their tab and last as long as the app runs (like Photoshop's).
struct HistorySnapshot: Identifiable, Equatable {
    var id = UUID(); var name: String; var date = Date(); var document: ArtDocument
    static func == (a: HistorySnapshot, b: HistorySnapshot) -> Bool { a.id == b.id && a.name == b.name }
}

extension Studio {
    var snapshots: [HistorySnapshot] { snapshotsByTab[tabID] ?? [] }

    func takeSnapshot(name: String? = nil) {
        let n = name ?? LF("Snapshot %d", (snapshotsByTab[tabID]?.count ?? 0) + 1)
        snapshotsByTab[tabID, default: []].append(HistorySnapshot(name: n, document: document()))
    }

    func restoreSnapshot(_ id: UUID) {
        guard let snap = snapshots.first(where: { $0.id == id }), !isPlaying else { return }
        checkpoint("Restore snapshot")
        apply(snap.document); changed()
    }

    func deleteSnapshot(_ id: UUID) { snapshotsByTab[tabID]?.removeAll { $0.id == id } }
    func renameSnapshot(_ id: UUID, to name: String) {
        guard let i = snapshotsByTab[tabID]?.firstIndex(where: { $0.id == id }), !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        snapshotsByTab[tabID]?[i].name = name
    }
}

/// The snapshot list at the top of the History tab.
struct SnapshotList: View {
    @EnvironmentObject var s: Studio
    @Environment(\.photoTheme) private var theme
    @State private var editing: UUID?
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "camera.shutter.button").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.accent)
                Text(L("Snapshots")).font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { withAnimation(PhotoMotion.select) { s.takeSnapshot() } } label: { Label(L("New snapshot"), systemImage: "plus") }
                    .buttonStyle(PhotoButtonStyle()).help(L("Keep the document as it is now"))
            }
            if s.snapshots.isEmpty {
                Text(L("Keep a state to come back to later, however many steps you take.")).font(.system(size: 10)).foregroundStyle(theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(s.snapshots) { snap in
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle").font(.system(size: 10)).foregroundStyle(theme.secondary)
                    if editing == snap.id {
                        TextField("", text: $draft).textFieldStyle(.roundedBorder).controlSize(.small)
                            .onSubmit { s.renameSnapshot(snap.id, to: draft); editing = nil }
                    } else {
                        Button { withAnimation(PhotoMotion.select) { s.restoreSnapshot(snap.id) } } label: {
                            HStack { Text(snap.name).font(.system(size: 11)); Spacer(); Text(snap.date, style: .time).font(.system(size: 9, design: .monospaced)).foregroundStyle(theme.secondary) }.contentShape(Rectangle())
                        }.buttonStyle(.plain).help(L("Go back to this state"))
                    }
                    Menu {
                        Button(L("Rename…")) { draft = snap.name; editing = snap.id }
                        Button(L("Delete"), role: .destructive) { withAnimation(PhotoMotion.select) { s.deleteSnapshot(snap.id) } }
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }.padding(.vertical, 3).transition(.opacity.combined(with: .move(edge: .top)))
            }
        }.photoCard()
    }
}
