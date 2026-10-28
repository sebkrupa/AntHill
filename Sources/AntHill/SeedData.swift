import Foundation
import AntHillKit

/// Sample queue for snapshots: APP_SEED=1 with APP_STORE in /tmp.
/// Every status here is one a real download reaches.
@MainActor
enum SeedData {
    static let playlist: [YTMusic.Entry] = [
        "Daft Punk - One More Time", "Fleetwood Mac - Dreams", "Nina Simone - Feeling Good",
        "Massive Attack - Teardrop", "Portishead - Glory Box", "Radiohead - Weird Fishes/Arpeggi",
        "Bring Me The Horizon - Happy Song (Live on the Honda Stage at Webster Hall)",
        "Björk - Jóga", "Air - La femme d'argent", "Bonobo - Kerala",
    ].enumerated().map { .init(id: "sample\($0.offset)", title: $0.element) }

    static func insertIfRequested(into model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1" else { return }
        guard Store.isOverridden else {
            print("APP_SEED ignored: APP_STORE must be a file in /tmp")
            return
        }
        let samples: [(String?, DownloadItem.Status, Double)] = [
            ("Daft Punk - One More Time", .done, 1),
            ("Fleetwood Mac - Dreams (Official Music Video, Remastered 2004 Edition)", .done, 1),
            ("Nina Simone - Feeling Good", .downloading, 0.42),
            ("Massive Attack - Teardrop", .paused, 0.18),
            (nil, .waiting, 0),
            (nil, .failed("Video unavailable (youtube, dQw4w9WgXcQ)"), 0),
        ]
        for (index, sample) in samples.enumerated() {
            let item = DownloadItem(url: "https://www.youtube.com/watch?v=sample\(index)")
            item.title = sample.0
            item.status = sample.1
            item.progress = sample.2
            if case .failed = sample.1 { item.stage = .info }
            model.music.insertSample(item)
        }
        let ageCheck = DownloadItem(url: "https://www.youtube.com/watch?v=sample7")
        ageCheck.title = "Bring Me The Horizon - Happy Song (Live on the Honda Stage at Webster Hall)"
        ageCheck.status = .failed("Sign in to confirm your age. This video may be inappropriate for some users. (youtube, sample7)")
        ageCheck.issue = .signIn
        ageCheck.stage = .info
        model.music.insertSample(ageCheck)
        let converting = DownloadItem(url: "https://www.youtube.com/watch?v=sample6")
        converting.title = "Find Your Focus - Atmospheric Music for Deep Work"
        converting.status = .downloading
        converting.progress = 1
        converting.stage = .convert
        converting.log = ["[youtube] Extracting URL", "[download] 100% of 182.40MiB",
                          "[ExtractAudio] Destination: Find Your Focus.m4a"]
        model.music.insertSample(converting)
    }
}
