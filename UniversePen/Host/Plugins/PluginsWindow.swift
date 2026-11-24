import SwiftUI
import TafelKit

/// Plugins window: list with switches, a small editor, the plugin's log.
struct PluginsWindow: View {
    @EnvironmentObject var host: HostController
    @ObservedObject var theme = Theme.shared
    @State private var selection: String?
    @State private var newName = ""
    @State private var askName = false
    @State private var confirmEnable: String?
    @AppStorage("pluginsWarned") private var warned = false

    private var plugins: PluginManager { host.plugins }

    var body: some View {
        PluginsSplit(plugins: host.plugins, selection: $selection, askName: $askName, confirmEnable: $confirmEnable, warned: warned)
            .frame(minWidth: 820, minHeight: 520)
            .preferredColorScheme(.dark)
            .onAppear { plugins.scan(); if selection == nil { selection = plugins.entries.first?.id } }
            .alert(L("Neues Plugin"), isPresented: $askName) {
                TextField(L("Name"), text: $newName)
                Button(L("Anlegen")) {
                    if let id = try? plugins.create(named: newName.isEmpty ? "My plugin" : newName) { selection = id }
                    newName = ""
                }
                Button(L("Abbrechen"), role: .cancel) { newName = "" }
            }
            .alert(L("Plugin einschalten?"), isPresented: Binding(get: { confirmEnable != nil }, set: { if !$0 { confirmEnable = nil } })) {
                Button(L("Einschalten")) {
                    if let id = confirmEnable { warned = true; plugins.setEnabled(id, true) }
                    confirmEnable = nil
                }
                Button(L("Abbrechen"), role: .cancel) { confirmEnable = nil }
            } message: {
                Text(L("Plugins laufen auf diesem Mac und können Stift-Eingaben lesen und verändern, Tasten drücken und UniversePen steuern. Sie haben keinen Zugriff auf Dateien oder das Internet. Nur Plugins einschalten, deren Code du kennst oder vertraust."))
            }
    }
}

private struct PluginsSplit: View {
    @ObservedObject var plugins: PluginManager
    @Binding var selection: String?
    @Binding var askName: Bool
    @Binding var confirmEnable: String?
    let warned: Bool
    @ObservedObject var theme = Theme.shared

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(plugins.entries) { e in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(e.error != nil ? Color.orange : e.enabled ? Brand.mint : Color.secondary.opacity(0.4))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.name).font(.body.weight(.medium))
                            if !e.summary.isEmpty { Text(e.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                        }
                        Spacer()
                        Toggle("", isOn: Binding(get: { e.enabled }, set: { on in
                            if on && !warned { confirmEnable = e.id } else { plugins.setEnabled(e.id, on) }
                        }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(Brand.mint)
                    }
                    .tag(e.id)
                    .padding(.vertical, 3)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    if plugins.entries.isEmpty {
                        Text(L("Noch keine Plugins. Lege eins an oder installiere die Beispiele.")).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button { askName = true } label: { Label(L("Neu"), systemImage: "plus") }
                        Button { _ = plugins.installExamples() } label: { Label(L("Beispiele"), systemImage: "square.and.arrow.down") }
                        Button { plugins.openFolder() } label: { Image(systemName: "folder") }
                            .help(L("Plugin-Ordner öffnen"))
                    }
                    .controlSize(.small)
                }
                .padding(10)
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            if let id = selection, let e = plugins.entries.first(where: { $0.id == id }) {
                PluginDetail(plugins: plugins, entry: e).id(e.id)
            } else {
                Text(L("Plugin auswählen")).foregroundStyle(.secondary)
            }
        }
    }
}

private struct PluginDetail: View {
    @ObservedObject var plugins: PluginManager
    let entry: PluginManager.Entry
    @ObservedObject var theme = Theme.shared
    @State private var source = ""
    @State private var saved = ""
    @State private var saveError: String?

    private var log: [String] { plugins.logs[entry.id] ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).font(.title3.weight(.semibold))
                    Text("\(entry.id)\(entry.version.isEmpty ? "" : " · v\(entry.version)")").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                if source != saved { Text(L("Nicht gespeichert")).font(.caption).foregroundStyle(.orange) }
                Button(L("Speichern & neu laden")) { save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent).tint(Brand.mint).foregroundStyle(Brand.slateDeep)
                Button { plugins.reload(entry.id) } label: { Image(systemName: "arrow.clockwise") }
                    .help(L("Neu laden"))
                Button { NSWorkspace.shared.activateFileViewerSelecting([entry.folder]) } label: { Image(systemName: "folder") }
                    .help(L("Im Finder zeigen"))
            }
            .padding(12)
            if let err = entry.error ?? saveError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.bottom, 8)
            }
            TextEditor(text: $source)
                .font(.system(.callout, design: .monospaced))
                .autocorrectionDisabled()
                .scrollContentBackground(.hidden)
                .background(Color.black.opacity(0.35))
            Divider()
            HStack {
                Text(L("Log")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button(L("Leeren")) { plugins.clearLog(entry.id) }.buttonStyle(.borderless).font(.caption)
            }
            .padding(.horizontal, 12).padding(.top, 6)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(log.enumerated()), id: \.offset) { i, line in
                            Text(line).font(.caption.monospaced()).textSelection(.enabled)
                                .foregroundStyle(line.contains("⚠︎") ? Color.orange : Color.primary.opacity(0.85))
                                .id(i)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.bottom, 8)
                }
                .frame(height: 150)
                .onChange(of: log.count) { proxy.scrollTo(log.count - 1, anchor: .bottom) }
            }
        }
        .onAppear { source = plugins.source(of: entry.id); saved = source }
    }

    private func save() {
        do {
            try plugins.save(entry.id, source: source)
            saved = source
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}
