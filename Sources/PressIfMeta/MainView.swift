import SwiftUI
import PressIfCore

struct MainView: View {
    @ObservedObject var model: AppModel
    @StateObject private var editor = InlineEditorController()

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 236)
            PressPalette.border.frame(width: 1)
            VStack(spacing: 0) {
                if model.runningID != nil || model.pendingCount > 0 || model.interpreting { topbar }
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let error = model.error, error != model.selectedJob?.events.last?.message { errorBanner(error) }
                        if let job = model.selectedJob { JobDetail(job: job, model: model).id(job.id) }
                        else { composer }
                    }
                    .padding(30)
                    .frame(maxWidth: 980, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .id(model.selectedJobID)
            }
            .background(PressPalette.canvas)
        }
        .foregroundStyle(PressPalette.textPrimary)
        .frame(minWidth: 960, minHeight: 700)
        .preferredColorScheme(.light)
        .tint(PressPalette.accent)
        .sheet(isPresented: $model.showSettings) { SettingsPanel(model: model) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(PressPalette.accent)
                    .frame(width: 36, height: 36)
                    .background(PressPalette.accentSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text("Press If").font(.system(size: 22, weight: .bold))
            }
            .padding(.top, 6)
            Button { model.newRequest() } label: {
                HStack {
                    Label("New task", systemImage: "plus")
                    Spacer()
                    Text("⌘N").font(.system(size: 11, design: .monospaced)).opacity(0.75)
                }.frame(maxWidth: .infinity)
            }
            .buttonStyle(PressButtonStyle())
            Text("Tasks").font(.system(size: 11, weight: .semibold)).foregroundStyle(PressPalette.textTertiary)
            ScrollView {
                VStack(spacing: 6) {
                    if model.jobs.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "tray").font(.system(size: 25, weight: .light))
                            Text("No tasks yet").font(.system(size: 12))
                        }
                        .foregroundStyle(PressPalette.textTertiary)
                        .frame(maxWidth: .infinity).padding(.vertical, 28)
                    }
                    ForEach(model.jobs) { job in
                        taskRow(job)
                    }
                }
            }
            Spacer(minLength: 0)
            Rectangle().fill(PressPalette.border).frame(height: 1)
            Button { model.showSettings = true } label: {
                HStack(spacing: 9) {
                    Image(systemName: "slider.horizontal.3")
                    Text("Settings").font(.system(size: 12, weight: .medium))
                    Spacer()
                    if model.apiKey.isEmpty || !model.accessibilityGranted || !model.imagePermissionsReady {
                        Text("Set up").font(.system(size: 11)).foregroundStyle(PressPalette.accent)
                    }
                }
                .foregroundStyle(PressPalette.textSecondary)
                .padding(.vertical, 4)
            }.buttonStyle(.plain)
        }
        .padding(18)
        .background(.white)
    }

    private func taskRow(_ job: ScheduledJob) -> some View {
        let selected = model.selectedJobID == job.id
        return Button { model.selectedJobID = job.id } label: {
            HStack(alignment: .top, spacing: 10) {
                ApplicationIcon(appID: job.plan.steps.first?.appID, catalog: model.catalog, size: 28)
                VStack(alignment: .leading, spacing: 7) {
                    Text(job.plan.title)
                        .font(.system(size: 12, weight: .semibold)).lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 5) {
                        Image(systemName: job.state.symbol).accessibilityHidden(true)
                        Text(job.state.label)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(job.state.isAccented ? PressPalette.accent : PressPalette.textTertiary)
                    Text(job.runAt.formatted(.dateTime.month().day().hour().minute().locale(PressLocale.english)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(PressPalette.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? PressPalette.accentSurface : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(selected ? PressPalette.accentBorder : .clear, lineWidth: 1) }
            .overlay(alignment: .leading) {
                if selected { Capsule().fill(PressPalette.accent).frame(width: 3, height: 24) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(job.plan.title), \(job.state.label), \(job.runAt.formatted(.dateTime.month().day().hour().minute().locale(PressLocale.english)))")
        .accessibilityRemoveTraits(.isSelected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var topbar: some View {
        HStack(spacing: 12) {
            if model.runningID != nil {
                ProgressView().controlSize(.small).tint(PressPalette.accent)
                Text("Running").font(.system(size: 12, weight: .medium)).foregroundStyle(PressPalette.accent)
            } else if model.pendingCount > 0 {
                Label("\(model.pendingCount) scheduled", systemImage: "clock")
                    .font(.system(size: 11)).foregroundStyle(PressPalette.textTertiary)
            }
            Spacer()
            Button { model.stopAll() } label: { Label(model.interpreting && model.pendingCount == 0 && model.runningID == nil ? "Cancel" : "Stop all", systemImage: "stop.circle") }
                .buttonStyle(PressButtonStyle(kind: .quiet))
                .help("Control + Option + Escape")
        }
        .padding(.horizontal, 28).padding(.vertical, 8)
        .background(.white)
        .overlay(alignment: .bottom) { PressPalette.border.frame(height: 1) }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("New task").font(.system(size: 26, weight: .bold))
            inputCard
            if let plan = model.preview {
                previewCard(plan)
            } else if !model.interpreting && model.document.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Try a task").font(.system(size: 12, weight: .semibold)).foregroundStyle(PressPalette.textTertiary)
                    HStack(spacing: 14) {
                        ExampleCard(appID: "com.apple.clock", title: "Start a stopwatch", schedule: "In 1 min", target: "Start", catalog: model.catalog) {
                            model.newRequest("In 1 minute, open Clock and start the stopwatch.")
                        }
                        ExampleCard(appID: "com.apple.Safari", title: "Open a new tab", schedule: "Tomorrow, 9 AM", target: "", keys: ["command", "t"], catalog: model.catalog) {
                            model.newRequest("Tomorrow at 9 AM, open a new tab in Safari.")
                        }
                    }
                }
            }
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                if model.document.isEmpty {
                    Text("In 1 minute, start the stopwatch in Clock…")
                        .font(.system(size: 17))
                        .foregroundStyle(PressPalette.textTertiary)
                        .padding(.top, 8).padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                InlineRequestEditor(document: $model.document, controller: editor, onError: { model.error = $0 }, onSubmit: model.interpret)
                    .frame(height: 150)
            }
            Rectangle().fill(PressPalette.surfaceMuted).frame(height: 1)
            HStack(spacing: 10) {
                Button { editor.chooseImage() } label: { Label("Add image", systemImage: "photo.badge.plus") }
                    .buttonStyle(PressButtonStyle())
                    .help("Insert a button image at the cursor. You can also paste (⌘V) or drop an image.")
                Spacer()
                Button { model.interpret() } label: {
                    HStack(spacing: 8) {
                        if model.interpreting { ProgressView().controlSize(.small).tint(.white) }
                        Text(model.interpreting ? "Planning…" : "Preview")
                        if !model.interpreting { Image(systemName: "arrow.right") }
                    }
                }
                .buttonStyle(PressButtonStyle(kind: model.preview != nil && model.previewIsCurrent ? .secondary : .primary))
                .disabled(model.interpreting || model.document.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityIdentifier("interpret-request")
            }
        }
        .pressCard()
    }

    private func previewCard(_ plan: AutomationPlan) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Plan").font(.system(size: 16, weight: .semibold))
            PlanContent(plan: plan, date: model.previewDate, catalog: model.catalog, images: model.document.images, isPreview: true)
            HStack {
                if !model.previewIsCurrent {
                    Label("Request changed. Preview again.", systemImage: "arrow.clockwise")
                        .font(.system(size: 11)).foregroundStyle(PressPalette.textSecondary)
                }
                Spacer()
                Button { model.savePreview() } label: {
                    Label(plan.schedule.kind == .now ? "Run" : "Schedule", systemImage: plan.schedule.kind == .now ? "play.fill" : "calendar.badge.plus")
                        .frame(minWidth: 76)
                }
                .buttonStyle(PressButtonStyle(kind: .primary))
                .disabled(!model.previewIsCurrent || !model.accessibilityGranted || !model.imagePermissionsReady)
                .accessibilityIdentifier("save-plan")
            }
            if !model.accessibilityGranted || !model.imagePermissionsReady {
                Button { model.showSettings = true } label: {
                    Label("Set up permissions", systemImage: "lock.open")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PressPalette.accent)
                }.buttonStyle(.plain)
            }
        }
        .pressCard()
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.octagon")
                .font(.system(size: 18)).foregroundStyle(PressPalette.textPrimary)
            Text(error).font(.system(size: 13)).textSelection(.enabled)
            Spacer()
            Button { model.error = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(PressPalette.textTertiary)
                .accessibilityLabel("Dismiss error")
        }
        .pressCard(padding: 16)
    }
}

private struct ExampleCard: View {
    let appID: String
    let title: String
    let schedule: String
    let target: String
    var keys: [String] = []
    let catalog: DesktopCatalog
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    ApplicationIcon(appID: appID, catalog: catalog, size: 32)
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Image(systemName: "arrow.up.left").font(.system(size: 12)).foregroundStyle(PressPalette.neutral400)
                }
                HStack(spacing: 10) {
                    InfoPill(title: schedule, symbol: "clock")
                    Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(PressPalette.neutral400)
                    if keys.isEmpty {
                        Label(target, systemImage: "play.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(PressPalette.accent)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(PressPalette.accentSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        KeyboardKeys(keys: keys)
                    }
                    Spacer(minLength: 0)
                }
            }
            .pressCard(padding: 18)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Try: \(title), \(schedule)")
    }
}
