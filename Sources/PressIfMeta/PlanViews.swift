import SwiftUI
import PressIfCore

struct PlanContent: View {
    let plan: AutomationPlan
    let date: Date?
    let catalog: DesktopCatalog
    var images: [ReferenceImage] = []
    var isPreview = false
    var completed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            schedule
            VStack(spacing: 0) {
                ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                    PlanStepRow(index: index, step: step, catalog: catalog,
                                reference: images.first { $0.id == step.referenceImageID }, completed: completed)
                    if index < plan.steps.count - 1 {
                        HStack {
                            PressPalette.border.frame(width: 1, height: 16).padding(.leading, 11)
                            Spacer()
                        }
                    }
                }
            }
            DisclosureGroup {
                Text(plan.successCriteria).font(.system(size: 12))
                    .foregroundStyle(PressPalette.textSecondary).lineSpacing(3).padding(.top, 8)
            } label: {
                Label("Success check", systemImage: "checkmark.seal")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(PressPalette.textTertiary)
            }
        }
    }

    private var schedule: some View {
        HStack(spacing: 12) {
            Image(systemName: plan.schedule.kind == .daily ? "repeat" : "clock")
                .font(.system(size: 18))
                .foregroundStyle(PressPalette.accent)
                .frame(width: 38, height: 38)
                .background(PressPalette.accentSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(scheduleTitle).font(.system(size: 17, weight: .semibold)).monospacedDigit()
                Text(scheduleDetail).font(.system(size: 11)).foregroundStyle(PressPalette.textTertiary)
            }
            Spacer()
            if plan.schedule.kind == .daily { InfoPill(title: "Daily", symbol: "repeat") }
        }
        .padding(.bottom, 4)
    }

    private var scheduleTitle: String {
        if isPreview, plan.schedule.kind == .now { return "Now" }
        if isPreview, plan.schedule.kind == .after, let seconds = plan.schedule.seconds {
            return seconds % 60 == 0 ? "In \(seconds / 60) min" : "In \(seconds) sec"
        }
        return date?.formatted(.dateTime.hour().minute().locale(PressLocale.english)) ?? "Start time"
    }

    private var scheduleDetail: String {
        if isPreview, plan.schedule.kind == .now { return "Automation starts when you click Run" }
        if isPreview, plan.schedule.kind == .after { return "Automation starts after scheduling" }
        return date?.formatted(.dateTime.year().month().day().weekday().locale(PressLocale.english)) ?? ""
    }
}

private struct PlanStepRow: View {
    let index: Int
    let step: ActionStep
    let catalog: DesktopCatalog
    let reference: ReferenceImage?
    let completed: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            Group {
                if completed { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                else { Text("\(index + 1)").font(.system(size: 11, weight: .semibold, design: .monospaced)) }
            }
            .foregroundStyle(completed ? PressPalette.accent : PressPalette.textTertiary)
            .frame(width: 23, height: 23)
            .background(completed ? PressPalette.accentSurface : PressPalette.surfaceMuted).clipShape(Circle())
            if step.action == .launch {
                ApplicationIcon(appID: step.appID, catalog: catalog, size: 36)
            } else {
                Image(systemName: step.symbol).font(.system(size: 17))
                    .foregroundStyle(PressPalette.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(PressPalette.canvas).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 14, weight: .medium))
                if step.action == .shortcut, let keys = step.keys { KeyboardKeys(keys: keys) }
                if let text = step.text {
                    Text(text).font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(9).background(PressPalette.surfaceMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                if let detail, !detail.isEmpty {
                    Text(detail).font(.system(size: 11)).foregroundStyle(PressPalette.textTertiary)
                }
            }
            Spacer(minLength: 8)
            if let reference { ReferenceThumbnail(reference: reference) }
        }
        .frame(minHeight: 48)
    }

    private var title: String {
        if step.action == .launch { return "Open \(catalog.title(for: step.appID))" }
        if reference != nil { return "Click image" }
        if step.action == .shortcut { return "Press shortcut" }
        return step.label
    }

    private var detail: String? {
        reference != nil ? step.target : step.context
    }
}

struct JobDetail: View {
    let job: ScheduledJob
    @ObservedObject var model: AppModel
    @State private var historyExpanded = false
    @State private var stepsExpanded: Bool

    init(job: ScheduledJob, model: AppModel) {
        self.job = job
        self.model = model
        _stepsExpanded = State(initialValue: [.scheduled, .running, .paused].contains(job.state))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                TaskStatusBadge(state: job.state)
                Spacer()
                if job.state == .scheduled || job.state == .running {
                    Button { model.pause(job.id) } label: { Label("Pause", systemImage: "pause") }
                        .buttonStyle(PressButtonStyle())
                } else if job.state == .paused {
                    Button { model.resume(job.id) } label: { Label("Resume", systemImage: "play") }
                        .buttonStyle(PressButtonStyle())
                }
                Menu {
                    Button("Delete task", role: .destructive) { model.remove(job.id) }.disabled(job.state == .running)
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).frame(width: 24).help("Task options")
            }
            Text(job.plan.title).font(.system(size: 25, weight: .bold))
            if showsResult { resultCard }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Request").font(.system(size: 11, weight: .semibold)).foregroundStyle(PressPalette.textTertiary)
                    Spacer()
                    Button { reuse() } label: { Label("Reuse", systemImage: "arrow.up.left") }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(PressPalette.accent)
                }
                RequestReadback(document: job.document ?? RequestDocument(text: job.request))
                    .frame(height: job.document?.images.isEmpty == false ? 90 : 52)
            }
            .pressCard(padding: 18)
            DisclosureGroup(isExpanded: $stepsExpanded) {
                PlanContent(plan: job.plan, date: job.runAt, catalog: model.catalog,
                            images: job.document?.images ?? [], completed: job.state == .completed)
                    .padding(.top, 18)
            } label: {
                Label("Steps", systemImage: "list.number").font(.system(size: 12, weight: .medium))
            }
            .pressCard(padding: 16)
            DisclosureGroup(isExpanded: $historyExpanded) {
                VStack(alignment: .leading, spacing: 15) {
                    ForEach(job.events) { event in
                        HStack(alignment: .top, spacing: 12) {
                            Text(event.date.formatted(.dateTime.hour().minute().second().locale(PressLocale.english)))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(PressPalette.textTertiary).frame(width: 86, alignment: .leading)
                            Text(event.message).font(.system(size: 12)).textSelection(.enabled)
                        }
                    }
                }.padding(.top, 16)
            } label: {
                Label("Activity", systemImage: "list.bullet").font(.system(size: 12, weight: .medium))
            }
            .pressCard(padding: 16)
        }
    }

    private var showsResult: Bool {
        [.completed, .failed, .needsReview, .missed, .running].contains(job.state)
    }

    private var resultCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if job.state == .running { ProgressView().controlSize(.small) }
                else { Image(systemName: job.state.symbol).font(.system(size: 22, weight: .medium)) }
            }
            .foregroundStyle(job.state == .completed ? PressPalette.accent : PressPalette.textSecondary)
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(job.state == .completed ? "Verified result" : job.state.label)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if let event = job.events.last {
                        Text(event.date.formatted(.dateTime.hour().minute().locale(PressLocale.english)))
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(PressPalette.textTertiary)
                    }
                }
                if let event = job.events.last {
                    Text(event.message).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(PressPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(PressPalette.border, lineWidth: 1) }
    }

    private func reuse() {
        model.newRequest(document: job.document ?? RequestDocument(text: job.request))
    }
}
