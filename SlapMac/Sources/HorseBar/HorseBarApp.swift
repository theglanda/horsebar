import AppKit
import ServiceManagement
import SlapCore
import SwiftUI

enum SoundMode: String, CaseIterable {
    case random, fixed
}

final class SlapModel: ObservableObject {
    @AppStorage("enabled") var enabled = true
    /// 0…1, higher = lighter slaps trigger a sound
    @AppStorage("sensitivity") var sensitivity = 0.8
    @AppStorage("cooldownMs") var cooldownMs = 400.0
    @AppStorage("volume") var volume = 0.8
    /// Harder slap = louder sound (capped by `volume`)
    @AppStorage("volumeByStrength") var volumeByStrength = true
    @AppStorage("soundMode") var soundMode = SoundMode.random
    @AppStorage("selectedSound") var selectedSound = ""
    @AppStorage("soundsFolder") var soundsFolder = SlapModel.defaultSoundsFolder.path
    @AppStorage("didFirstLaunch") private var didFirstLaunch = false

    /// ~/Library/Application Support/HorseBar/Sounds — seeded with the bundled sounds.
    static let defaultSoundsFolder = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("HorseBar/Sounds")

    /// false on Macs without the SPU accelerometer (base M1, Intel).
    let sensorAvailable = AccelerometerReader.isAvailable()

    @Published var connected = false
    @Published var lastImpact: Double?
    @Published var lastImpactPlayed = false
    @Published var slaps = 0
    @Published var sounds: [URL] = []

    private let client = ImpactClient()
    private let player = SoundPlayer()
    private var lastPlay = Date.distantPast

    /// Threshold in g for the current sensitivity.
    var threshold: Double { 0.05 + (1 - sensitivity) * 0.95 }

    var usingSystemSounds: Bool { player.files(in: folderURL).isEmpty }
    private var folderURL: URL { URL(fileURLWithPath: soundsFolder) }

    init() {
        client.onConnectionChange = { [weak self] in self?.connected = $0 }
        client.onImpact = { [weak self] in self?.handle($0) }
        client.start()
        seedSounds()
        reloadSounds()
        if !didFirstLaunch {
            didFirstLaunch = true
            openAtLogin = true
        }
    }

    /// Copies the sounds shipped inside the app into the user's folder on first run.
    private func seedSounds() {
        let fm = FileManager.default
        let dest = Self.defaultSoundsFolder
        guard !fm.fileExists(atPath: dest.path),
              let bundled = Bundle.main.resourceURL?.appendingPathComponent("Sounds") else { return }
        try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
        for url in player.files(in: bundled) {
            try? fm.copyItem(at: url, to: dest.appendingPathComponent(url.lastPathComponent))
        }
    }

    var openAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            if newValue { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
        }
    }

    func uninstall() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Uninstall HorseBar?"
        alert.informativeText = "This removes the app and its background service. Your sounds folder is kept."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        try? SMAppService.mainApp.unregister()
        let commands = [
            "launchctl bootout system/com.theglanda.slapd",
            "rm -f /Library/LaunchDaemons/com.theglanda.slapd.plist /var/run/slapd.sock",
            "rm -rf '/Library/Application Support/HorseBar'",
            "rm -rf '\(Bundle.main.bundlePath)'",
            "pkgutil --forget com.theglanda.horsebar.pkg",
        ].map { $0 + " >/dev/null 2>&1" }.joined(separator: "; ")
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(commands); true\" with administrator privileges")?
            .executeAndReturnError(&error)
        if error == nil { NSApp.terminate(nil) }
    }

    func reloadSounds() {
        sounds = player.available(in: folderURL)
    }

    private func handle(_ strength: Double) {
        lastImpact = strength
        lastImpactPlayed = false
        guard enabled, strength >= threshold,
              Date().timeIntervalSince(lastPlay) * 1000 >= cooldownMs else { return }
        lastPlay = Date()
        lastImpactPlayed = true
        slaps += 1
        let factor = volumeByStrength ? min(1, 0.4 + strength) : 1
        if let url = nextSound() {
            player.play(url, volume: Float(volume * factor))
        }
    }

    private func nextSound() -> URL? {
        reloadSounds()
        if soundMode == .fixed, let url = sounds.first(where: { $0.lastPathComponent == selectedSound }) {
            return url
        }
        return sounds.randomElement()
    }

    func preview(_ url: URL) {
        player.play(url, volume: Float(volume))
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = folderURL
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            soundsFolder = url.path
            reloadSounds()
        }
    }

    func openFolder() {
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folderURL)
    }
}

@main
struct HorseBarApp: App {
    @StateObject private var model = SlapModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Text(model.connected ? (model.enabled ? "🐴" : "🐴💤") : "🐴⚠️")
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - UI

struct MenuView: View {
    @ObservedObject var model: SlapModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            strengthSection
            Divider()
            soundSection
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { model.reloadSounds() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("HorseBar").font(.headline)
                Label(model.connected ? "Sensor connected"
                      : model.sensorAvailable ? "Background service is not running"
                      : "No motion sensor (needs M1 Pro / M2 or newer)",
                      systemImage: "circle.fill")
                    .labelStyle(StatusLabelStyle(color: model.connected ? .green : .red))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $model.enabled).toggleStyle(.switch).labelsHidden()
        }
    }

    // MARK: slap strength

    private var strengthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Slap strength", systemImage: "hand.raised")

            ImpactMeter(threshold: model.threshold,
                        last: model.lastImpact,
                        played: model.lastImpactPlayed)

            HStack {
                Text("Hard").font(.caption2).foregroundStyle(.secondary)
                Slider(value: $model.sensitivity, in: 0...1)
                Text("Light").font(.caption2).foregroundStyle(.secondary)
            }
            Text("Plays on slaps above \(model.threshold, specifier: "%.2f") g")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Text("Cooldown").font(.callout)
                Slider(value: $model.cooldownMs, in: 100...2000, step: 50)
                Text("\(Int(model.cooldownMs)) ms")
                    .font(.caption.monospacedDigit()).frame(width: 54, alignment: .trailing)
            }
        }
    }

    // MARK: sound

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Sound", systemImage: "speaker.wave.2")

            Picker("", selection: $model.soundMode) {
                Text("Random").tag(SoundMode.random)
                Text("Specific").tag(SoundMode.fixed)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: model.soundMode) { _, mode in
                let names = model.sounds.map(\.lastPathComponent)
                if mode == .fixed, !names.contains(model.selectedSound), let first = names.first {
                    model.selectedSound = first
                }
            }

            if model.usingSystemSounds {
                Text("No sounds in the folder — using system sounds")
                    .font(.caption).foregroundStyle(.orange)
            }

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(model.sounds, id: \.self) { url in
                        SoundRow(url: url,
                                 selectable: model.soundMode == .fixed,
                                 selected: model.selectedSound == url.lastPathComponent,
                                 onSelect: { model.selectedSound = url.lastPathComponent },
                                 onPlay: { model.preview(url) })
                    }
                }
            }
            .frame(height: min(160, CGFloat(model.sounds.count) * 28))

            HStack {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                Slider(value: $model.volume, in: 0...1)
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                Text("\(Int(model.volume * 100))%")
                    .font(.caption.monospacedDigit()).frame(width: 36, alignment: .trailing)
            }
            Toggle("Harder slap = louder", isOn: $model.volumeByStrength)
                .font(.callout)
        }
    }

    private var footer: some View {
        HStack {
            Button("Sounds Folder") { model.openFolder() }
            Button("Choose…") { model.chooseFolder() }
            Spacer()
            Text("\(model.slaps)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .help("Slaps that played a sound")
            Menu {
                Toggle("Open at Login", isOn: Binding(get: { model.openAtLogin },
                                                      set: { model.openAtLogin = $0 }))
                Divider()
                Button("Uninstall HorseBar…") { model.uninstall() }
                Divider()
                Button("Quit HorseBar") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .controlSize(.small)
    }
}

struct SectionTitle: View {
    let title: String
    let systemImage: String
    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }
    var body: some View {
        Label(title, systemImage: systemImage).font(.subheadline.weight(.semibold))
    }
}

struct StatusLabelStyle: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.foregroundStyle(color).imageScale(.small)
            configuration.title
        }
    }
}

/// 0…1 g scale: threshold mark and the last slap.
struct ImpactMeter: View {
    let threshold: Double
    let last: Double?
    let played: Bool
    private let maxG = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    if let last {
                        Capsule()
                            .fill(played ? Color.accentColor : Color.secondary.opacity(0.5))
                            .frame(width: max(6, w * min(last, maxG) / maxG))
                            .animation(.easeOut(duration: 0.15), value: last)
                    }
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: 2, height: 16)
                        .offset(x: w * min(threshold, maxG) / maxG - 1)
                }
            }
            .frame(height: 10)

            Text(last.map { String(format: "Last slap: %.2f g%@", $0, played ? " — played" : "") }
                 ?? "Slap your Mac to test it")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct SoundRow: View {
    let url: URL
    let selectable: Bool
    let selected: Bool
    let onSelect: () -> Void
    let onPlay: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if selectable {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
            }
            Text(url.deletingPathExtension().lastPathComponent)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            Button(action: onPlay) { Image(systemName: "play.fill") }
                .buttonStyle(.borderless)
                .help("Preview")
        }
        .font(.callout)
        .padding(.vertical, 4).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 5)
            .fill(selectable && selected ? Color.accentColor.opacity(0.12) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { if selectable { onSelect() } }
    }
}
