import SwiftUI
import PressIfCore

struct SettingsPanel: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var dataDetailsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Settings").font(.system(size: 23, weight: .bold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(PressButtonStyle(kind: .quiet)).accessibilityLabel("Close settings")
            }
            connection
            permissions
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    shortcut("Quick input", keys: ["control", "option", "space"])
                    shortcut("Stop all", keys: ["control", "option", "escape"])
                }
                Spacer()
                Button { model.refreshPermissions() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(PressButtonStyle())
                    .help("Refresh permissions").accessibilityLabel("Refresh permissions")
                Button("Save") { model.saveSettings() }
                    .buttonStyle(PressButtonStyle(kind: .primary)).keyboardShortcut(.return)
            }
        }
        .padding(26).frame(width: 560)
        .foregroundStyle(PressPalette.textPrimary)
        .background(PressPalette.canvas)
        .tint(PressPalette.accent)
        .preferredColorScheme(.light)
        .onAppear { model.refreshPermissions() }
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label("Connection", systemImage: "key").font(.system(size: 13, weight: .semibold))
                Spacer()
                Link(destination: URL(string: "https://dev.meta.ai/platform/api-keys")!) {
                    Label("Manage API keys", systemImage: "arrow.up.right")
                        .font(.system(size: 11, weight: .medium))
                }.foregroundStyle(PressPalette.accent)
            }
            APIKeyField(text: $model.apiKey)
                .frame(height: 18)
                .padding(11).background(PressPalette.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(PressPalette.border, lineWidth: 1) }
            HStack {
                Label(model.credentialSource, systemImage: model.apiKey.isEmpty ? "key" : "lock.shield")
                    .font(.system(size: 11)).foregroundStyle(PressPalette.textTertiary)
                Spacer()
                Picker("Model", selection: $model.modelName) {
                    Text("Muse Spark 1.3").tag("muse-spark-1.3")
                    Text("Muse Spark 1.2").tag("muse-spark-1.2")
                }
                .labelsHidden().frame(width: 160)
                .accessibilityLabel("Model")
            }
        }
        .pressCard(padding: 18)
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("Permissions").font(.system(size: 13, weight: .semibold))
            permission("Accessibility", symbol: "hand.raised", detail: "Click and type in apps",
                       granted: model.accessibilityGranted, action: model.requestAccessibility)
            permission("Screen Recording", symbol: "viewfinder", detail: "Find controls by image",
                       granted: model.screenGranted, action: model.requestScreenAccess)
            Rectangle().fill(PressPalette.border).frame(height: 1)
            Toggle(isOn: $model.includeScreenshots) {
                Label("Send window images to Meta", systemImage: "photo")
                    .font(.system(size: 13, weight: .medium))
            }.toggleStyle(.switch).controlSize(.small)
            DisclosureGroup(isExpanded: $dataDetailsExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Requests, reference images and screen elements are sent to the selected model. Window images are also sent when image analysis is on. Sensitive content in images is not automatically hidden.")
                        .font(.system(size: 11)).foregroundStyle(PressPalette.textSecondary).lineSpacing(3)
                    Text("Keep your Mac awake and Press If running for scheduled tasks.")
                        .font(.system(size: 11)).foregroundStyle(PressPalette.textTertiary)
                }.padding(.top, 10)
            } label: {
                Text("Data & scheduling").font(.system(size: 11)).foregroundStyle(PressPalette.textTertiary)
            }
        }
        .pressCard(padding: 18)
    }

    private func permission(_ title: String, symbol: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 17))
                .foregroundStyle(PressPalette.textSecondary)
                .frame(width: 36, height: 36)
                .background(PressPalette.surfaceMuted).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(PressPalette.textTertiary)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(PressPalette.accent)
                    .accessibilityLabel("\(title) allowed")
            } else {
                Button("Allow", action: action).buttonStyle(PressButtonStyle())
                    .accessibilityLabel("Allow \(title)")
            }
        }
    }

    private func shortcut(_ title: String, keys: [String]) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 10)).foregroundStyle(PressPalette.textTertiary).frame(width: 66, alignment: .leading)
            KeyboardKeys(keys: keys)
        }
    }
}
