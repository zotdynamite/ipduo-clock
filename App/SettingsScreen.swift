import IpduoClockCore
import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $model.appearance) {
                        ForEach(AppearanceChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: model.appearance) { _, _ in model.touch() }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(AccentPalette.allCases) { palette in
                            Button {
                                model.accent = palette
                                Haptics.selection(enabled: model.hapticsEnabled)
                                model.touch()
                            } label: {
                                VStack(spacing: 8) {
                                    Circle()
                                        .fill(palette.color)
                                        .frame(height: 36)
                                        .overlay {
                                            if model.accent == palette {
                                                Image(systemName: "checkmark")
                                                    .font(.caption.weight(.bold))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                    Text(palette.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(palette.displayName)
                            .accessibilityAddTraits(model.accent == palette ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Time") {
                    Toggle("24-hour clock", isOn: $model.use24Hour)
                        .onChange(of: model.use24Hour) { _, _ in model.touch() }
                    Toggle("Show seconds", isOn: $model.showSeconds)
                        .onChange(of: model.showSeconds) { _, _ in model.touch() }
                }
                Section("Feedback") {
                    Toggle("Haptics", isOn: $model.hapticsEnabled)
                        .onChange(of: model.hapticsEnabled) { _, _ in model.touch() }
                }
                Section("About") {
                    LabeledContent("Name", value: AppIdentity.name)
                    Text("The working name lives in AppIdentity, the display name, and the bundle id app.ipduo.clock. Change all three together when you rename the app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Done", systemImage: "checkmark")
                    }
                }
                .duoPriorityHigh()
            }
            .screenshotMarker()
        }
    }
}
