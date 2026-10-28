import SwiftUI
import AntHillKit

/// eCommerce Security Check: type a shop address, press Return, read the report. Past reports on the left.
struct ShopCheckView: View {
    @Environment(AppModel.self) private var model
    @State private var address = ""

    private var checks: ShopChecks { model.shopChecks }

    var body: some View {
        @Bindable var checks = checks
        VStack(spacing: 0) {
            HStack(spacing: Space.sm) {
                TextField("Shop address, like sklep.pl", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .onSubmit(start)
                Button("Check", systemImage: "checkmark.shield", action: start)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(checks.running != nil || ShopCheck.target(address) == nil)
            }
            .padding(Space.margin)
            .gridArea("header")
            Divider()
            HStack(spacing: 0) {
                List(checks.reports, selection: $checks.selection) { report in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(report.domain).lineLimit(1)
                        Label(report.verdict.title, systemImage: report.verdict.symbol)
                            .font(.caption)
                            .foregroundStyle(report.verdict.color)
                    }
                    .padding(.vertical, Space.xs)
                    .contextMenu {
                        Button("Check Again") { checks.check(report.domain) }
                        Button("Remove") { checks.remove(report.id) }
                    }
                }
                .onDeleteCommand { if let id = checks.selection { checks.remove(id) } }
                .overlay {
                    if checks.reports.isEmpty {
                        ContentUnavailableView("No History", systemImage: "clock")
                    }
                }
                .frame(width: 240)
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(Module.shopCheck.title)
        .toolbar {
            ToolbarItem {
                Button("Clear History", systemImage: "trash") { checks.confirmsClear = true }
                    .help("Remove every report")
                    .disabled(checks.reports.isEmpty)
            }
        }
        .confirmationDialog("Remove all \(checks.reports.count) reports?", isPresented: $checks.confirmsClear) {
            Button("Clear History", role: .destructive) { checks.clearHistory() }
        } message: {
            Text("You can’t undo this.")
        }
    }

    @ViewBuilder private var detail: some View {
        if let running = checks.running {
            VStack(spacing: Space.md) {
                ProgressView()
                Text("Checking \(running.domain)…").font(.headline)
                Text(running.step).foregroundStyle(.secondary)
            }
        } else if let report = checks.selected {
            ReportView(report: report)
        } else {
            ContentUnavailableView("Check a Shop", systemImage: Module.shopCheck.symbol,
                                   description: Text("Type a shop address above and press Return. The report shows here."))
        }
    }

    private func start() {
        if checks.check(address) { address = "" }
    }
}

/// One report: the verdict, then red flags, good signs, notes, and what to check by hand.
struct ReportView: View {
    let report: ShopCheck.Report

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(report.domain).font(.title2.bold())
                    Label(report.verdict.title, systemImage: report.verdict.symbol)
                        .font(.headline)
                        .foregroundStyle(report.verdict.color)
                    Text("\(report.verdict.advice) Risk points: \(report.score). Checked \(report.date.formatted(date: .abbreviated, time: .shortened)).")
                        .foregroundStyle(.secondary)
                }
                section("Red Flags", .bad)
                section("Good Signs", .ok)
                section("Notes", .info)
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Check by Hand").font(.headline)
                    ForEach(report.hints, id: \.self) { hint in
                        if let url = hint.url {
                            Link(destination: url) { Label(hint.text, systemImage: "arrow.up.right.square") }
                        } else {
                            Label(hint.text, systemImage: "hand.point.right")
                        }
                    }
                }
                Text("The result is a hint, not a guarantee. Pay by card or with buyer protection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .textSelection(.enabled)
            .padding(Space.margin)
            .frame(maxWidth: .infinity, alignment: .leading)
            .gridArea("report")
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ kind: ShopCheck.Finding.Kind) -> some View {
        let findings = report.findings.filter { $0.kind == kind }
        if !findings.isEmpty {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text(title).font(.headline)
                ForEach(findings, id: \.self) { finding in
                    Label {
                        Text(finding.points > 0 ? "\(finding.text) (+\(finding.points))" : finding.text)
                    } icon: {
                        Image(systemName: kind.symbol).foregroundStyle(kind.color)
                    }
                }
            }
        }
    }
}

extension ShopCheck.Verdict {
    var symbol: String {
        switch self {
        case .clear: "checkmark.shield.fill"
        case .risky: "exclamationmark.triangle.fill"
        case .fraud: "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .clear: .green
        case .risky: .orange
        case .fraud: .red
        }
    }
}

extension ShopCheck.Finding.Kind {
    var symbol: String {
        switch self {
        case .bad: "exclamationmark.circle.fill"
        case .ok: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .bad: .red
        case .ok: .green
        case .info: .secondary
        }
    }
}
