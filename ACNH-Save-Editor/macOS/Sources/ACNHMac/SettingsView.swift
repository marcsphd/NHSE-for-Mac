import SwiftUI
import ACNHCore

private struct SettingsHeader: View {
    let title: String
    let subtitle: String
    @EnvironmentObject var model: EditorModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 28, weight: .semibold, design: .rounded))
            Text(subtitle).foregroundStyle(.secondary)
            if model.demo { Label("Preview · Open your save to export or save edits.", systemImage: "eye").foregroundStyle(Color.island) }
            if let error = model.settingsError { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red).font(.callout).fixedSize(horizontal: false, vertical: true) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 28).padding(.top, 26)
    }
}

private struct NameField: View {
    let title: String
    @Binding var name: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(title, text: $name).textFieldStyle(.roundedBorder).accessibilityLabel(title)
            Text("\(name.utf16.count) / 10 UTF-16 units · Emoji may use two or more.")
                .font(.caption).foregroundStyle(name.utf16.count > 10 || name.isEmpty ? .red : .secondary)
        }.padding(.vertical, 4)
    }
}

struct PlayerSettingsView: View {
    @EnvironmentObject var model: EditorModel
    private let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    private var player: PlayerSettings { model.draft?.playerSettings ?? .init() }
    private var dayLimit: Int {
        guard (1...12).contains(player.birthMonth) else { return 31 }
        return [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][Int(player.birthMonth) - 1]
    }
    private var monthBinding: Binding<UInt8> {
        Binding(get: { player.birthMonth }, set: { month in
            guard (1...12).contains(month) else { return }
            model.change {
                $0.playerSettings.birthMonth = month
                let maximum = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][Int(month) - 1]
                $0.playerSettings.birthDay = UInt8(max(1, min(Int($0.playerSettings.birthDay), maximum)))
            }
        })
    }
    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader(title: "A name of your own.", subtitle: "Edit the primary human resident. Changes stay in your draft until you export or save.")
            Form {
                Section("Identity") {
                    NameField(title: "Player name", name: model.playerBinding(\.name, fallback: ""))
                    Text("Renaming updates matching player identity records throughout the island and resident files.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Birthday") {
                    Picker("Month", selection: monthBinding) {
                        if !(1...12).contains(player.birthMonth) { Text("Unset (\(player.birthMonth))").tag(player.birthMonth) }
                        ForEach(0..<12, id: \.self) { Text(months[$0]).tag(UInt8($0 + 1)) }
                    }
                    Picker("Day", selection: model.playerBinding(\.birthDay, fallback: 1)) {
                        if !(1...dayLimit).contains(Int(player.birthDay)) { Text("Saved value (\(player.birthDay))").tag(player.birthDay) }
                        ForEach(1...dayLimit, id: \.self) { Text(String($0)).tag(UInt8($0)) }
                    }
                    Text("Updates both the resident birthday and the birthday shown on their profile. February 29 is supported.").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Text("These settings apply to the primary resident. Appearance and other human residents are not editable in this version.").font(.callout).foregroundStyle(.secondary)
                    Button("Revert Player Settings") {
                        guard let initial = model.session?.initial else { return }
                        model.change { $0.playerSettings = initial.playerSettings }
                    }.disabled(model.session == nil || model.draft?.playerSettings == model.session?.initial.playerSettings)
                }
            }.formStyle(.grouped)
        }
    }
}

struct IslandSettingsView: View {
    @EnvironmentObject var model: EditorModel
    private var island: IslandSettings { model.draft?.islandSettings ?? .init() }
    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader(title: "Your island, your seasons.", subtitle: "Edit your island’s name, climate, and native plants.")
            Form {
                Section("Island") {
                    NameField(title: "Island name", name: model.islandBinding(\.name, fallback: ""))
                    Text("Renaming updates matching island identity records throughout the save.").font(.caption).foregroundStyle(.secondary)
                    bytePicker("Hemisphere", key: \.hemisphere, names: IslandSettings.hemispheres)
                    bytePicker("Airport color", key: \.airportColor, names: IslandSettings.airportColors)
                }
                Section("Fruit and flowers") {
                    fruitPicker("Native fruit", key: \.nativeFruit)
                    fruitPicker("Sister fruit", key: \.sisterFruit)
                    bytePicker("Native flower", key: \.nativeFlower, names: IslandSettings.flowers)
                    bytePicker("Sister flower", key: \.sisterFlower, names: IslandSettings.flowers)
                    Text("Native fruit also updates the island’s fruit flags and the primary resident’s profile. These settings do not replace trees or flowers already planted.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Weather") {
                    seedField("Island weather seed", key: \.weatherSeed)
                    Text("The seed controls the weather pattern. Changing the hemisphere changes the island’s seasonal calendar.").font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("Tour weather settings") {
                        bytePicker("Tour hemisphere", key: \.tourHemisphere, names: IslandSettings.hemispheres)
                        seedField("Tour weather seed", key: \.tourWeatherSeed)
                    }
                }
                Section {
                    Button("Revert Island Settings") {
                        guard let initial = model.session?.initial else { return }
                        model.change { $0.islandSettings = initial.islandSettings }
                    }.disabled(model.session == nil || model.draft?.islandSettings == model.session?.initial.islandSettings)
                }
            }.formStyle(.grouped)
        }
    }
    private func bytePicker(_ title: String, key: WritableKeyPath<IslandSettings, UInt8>, names: [String]) -> some View {
        Picker(title, selection: model.islandBinding(key, fallback: 0)) {
            if Int(island[keyPath: key]) >= names.count { Text("Unknown (\(island[keyPath: key]))").tag(island[keyPath: key]) }
            ForEach(names.indices, id: \.self) { Text(names[$0]).tag(UInt8($0)) }
        }
    }
    private func fruitPicker(_ title: String, key: WritableKeyPath<IslandSettings, UInt16>) -> some View {
        Picker(title, selection: model.islandBinding(key, fallback: 0)) {
            if !IslandSettings.fruits.contains(where: { $0.id == island[keyPath: key] }) { Text("Unknown (\(island[keyPath: key]))").tag(island[keyPath: key]) }
            ForEach(IslandSettings.fruits, id: \.id) { Text($0.name).tag($0.id) }
        }
    }
    private func seedField(_ title: String, key: WritableKeyPath<IslandSettings, UInt32>) -> some View {
        TextField(title, value: model.islandBinding(key, fallback: 0), format: .number.grouping(.never))
            .monospacedDigit().accessibilityLabel(title)
    }
}
