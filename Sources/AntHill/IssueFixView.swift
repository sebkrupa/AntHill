import SwiftUI
import AntHillKit

extension YTMusic.Issue {
    /// The label of the fix button beside the page title.
    var fixTitle: String {
        switch self {
        case .signIn: "Sign In to YouTube"
        case .cookieAccess: "Allow Browser Access"
        case .missingTool: "Install yt-dlp"
        }
    }
}

/// Explains a problem that stops downloads and fixes it with one button.
struct IssueFixView: View {
    @Environment(AppModel.self) private var model
    let issue: YTMusic.Issue
    @State private var browser: YTMusic.Browser?

    private var queue: MusicQueue { model.music }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Label(issue.fixTitle, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .symbolRenderingMode(.multicolor)
            switch issue {
            case .signIn: signIn
            case .cookieAccess: cookieAccess
            case .missingTool: missingTool
            }
        }
        .padding(Space.lg)
        .frame(width: 400, alignment: .leading)
        .noInitialFocus()
    }

    @ViewBuilder private var signIn: some View {
        let browsers = queue.installedBrowsers
        Text("YouTube wants a signed-in account for some songs: age checks, private videos, or a check that you are not a bot. AntHill can use your YouTube sign-in from a browser.")
            .fixedSize(horizontal: false, vertical: true)
        if browsers.isEmpty {
            Text("No supported browser found. Install Safari, Chrome, Firefox, Brave, or Edge and sign in to YouTube there.")
                .foregroundStyle(.secondary)
        } else {
            Picker("Browser", selection: Binding(get: { browser ?? browsers[0] }, set: { browser = $0 })) {
                ForEach(browsers) { Text($0.title).tag($0) }
            }
            .fixedSize()
            Text("Sign in to YouTube in that browser first. Chrome-based browsers ask once for Keychain access: choose Always Allow.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Use \((browser ?? browsers[0]).title) and Retry") { queue.useBrowser(browser ?? browsers[0]) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder private var cookieAccess: some View {
        Text("macOS keeps AntHill from reading the YouTube sign-in in \(queue.browser?.title ?? "the browser"). Turn on AntHill in Full Disk Access, then retry. Or pick another browser.")
            .fixedSize(horizontal: false, vertical: true)
        HStack {
            Button("Other Browser…") { queue.browser = nil; queue.retryFailed(.cookieAccess) }
            Spacer()
            Button("Open Full Disk Access") { queue.openFullDiskAccess() }
            Button("Retry") { queue.showsFix = false; queue.retryFailed(.cookieAccess) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder private var missingTool: some View {
        Text("AntHill downloads with yt-dlp and converts with ffmpeg. Neither is installed.")
            .fixedSize(horizontal: false, vertical: true)
        HStack {
            if queue.installing {
                ProgressView().controlSize(.small)
                Text("Installing with Homebrew…").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Install and Retry") { queue.installTools() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(queue.installing)
        }
    }
}
