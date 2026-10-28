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

    static let tracks: [Library.Track] = [
        .init(id: "T1", name: "One More Time", artist: "Daft Punk", album: "Discovery", duration: 320),
        .init(id: "T2", name: "Daft Punk - One More Time (Official Video)", artist: "", album: "", duration: 322),
        .init(id: "T3", name: "Dreams (2004 Remaster)", artist: "Fleetwood Mac", album: "", duration: 257),
        .init(id: "T4", name: "Teardrop", artist: "Unknown Artist", album: "", duration: 330),
        .init(id: "T5", name: "Feeling Good", artist: "Nina Simone", album: "I Put a Spell on You", duration: 177),
    ]

    static let changes: [Library.Change] = [
        .init(track: tracks[1], kind: .trash(keeping: tracks[0])),
        .init(track: tracks[2], kind: .edit(name: "Dreams", artist: "Fleetwood Mac", album: "Rumours")),
        .init(track: tracks[3], kind: .edit(name: "Teardrop", artist: "Massive Attack", album: "Mezzanine")),
    ]

    static let shopReports: [ShopCheck.Report] = [
        .init(domain: "nike-outlet.shop", date: .now, findings: [
            .init(kind: .bad, points: 3, text: "The domain is new: registered 2026-09-30 (28 days ago)."),
            .init(kind: .bad, points: 3, text: "No NIP or KRS on the site. Nobody knows who runs the shop."),
            .init(kind: .bad, points: 2, text: "The domain has the brand “nike”, but it is not the brand’s own domain."),
            .init(kind: .bad, points: 1, text: "Time pressure on the site (“countdown”)."),
            .init(kind: .ok, points: 0, text: "The domain is not on the CERT Polska warning list."),
            .init(kind: .info, points: 0, text: "The site has HTTPS (the padlock). That is only encryption, no proof the shop is honest."),
        ], hints: [
            .init(text: "Product photos: search by image in Google Lens, TinEye, or Yandex Images.", url: nil),
            .init(text: "Reviews outside the shop: Trustpilot", url: URL(string: "https://www.trustpilot.com/review/nike-outlet.shop")),
        ]),
        .init(domain: "kowalski.pl", date: .now.addingTimeInterval(-86_400), findings: [
            .init(kind: .ok, points: 0, text: "Domain registered 2012-03-01."),
            .init(kind: .ok, points: 0, text: "Company in the VAT white list: SKLEP KOWALSKI SP. Z O.O., NIP 9562307719, status Czynny."),
        ], hints: []),
    ]

    static let connections: [Network.Connection] = [
        .init(pid: 1200, command: "ollama", fd: "3", family: "IPv4", proto: "TCP", local: "127.0.0.1:11434", remote: "", state: "LISTEN"),
        .init(pid: 1200, command: "ollama", fd: "12", family: "IPv4", proto: "TCP", local: "127.0.0.1:11434", remote: "127.0.0.1:52344", state: "ESTABLISHED"),
        .init(pid: 1200, command: "ollama", fd: "14", family: "IPv6", proto: "TCP", local: "[2a02:a311::5]:52390", remote: "[2606:4700::6810:84e5]:443", state: "ESTABLISHED"),
        .init(pid: 1214, command: "ollama runner", fd: "8", family: "IPv4", proto: "TCP", local: "127.0.0.1:52331", remote: "127.0.0.1:11434", state: "CLOSE_WAIT"),
        .init(pid: 618, command: "ControlCenter", fd: "9", family: "IPv4", proto: "TCP", local: "*:7000", remote: "", state: "LISTEN"),
    ]

    static let jobs: [Filesfer.Job] = {
        func job(_ from: String, _ to: String, _ operation: Filesfer.Operation, _ selection: Filesfer.Selection = .whole,
                 _ pattern: String = "", _ schedule: Filesfer.Schedule.Kind = .off) -> Filesfer.Job {
            var job = Filesfer.Job()
            job.from = from
            job.to = to
            job.operation = operation
            job.selection = selection
            job.pattern = pattern
            job.schedule.kind = schedule
            return job
        }
        var photos = job("/Users/me/Pictures/Camera Roll", "/Volumes/Backup/Photos", .copy, .extensions, "jpg, heic, mov", .daily)
        photos.name = "Camera Roll to Backup"
        var invoices = job("/Users/me/Downloads", "/Users/me/Documents/Invoices", .cut, .regex, "^faktura.*\\.pdf$", .weekly)
        invoices.last = .init(date: .now.addingTimeInterval(-3_600), files: 12, seconds: 4)
        var projects = job("/Users/me/Projects/AntHill", "/Users/me/Archive", .zip)
        projects.last = .init(date: .now.addingTimeInterval(-7_200), error: "rsync: [sender] send_files failed to open \"/Users/me/Projects/AntHill/notes.txt\": Operation not permitted (1)",
                              permission: true, files: 0, seconds: 1)
        var music = job("/Users/me/Music/Mixes", "/Volumes/Studio/Mixes", .copy, .whole, "", .hours)
        music.conflict = .overwrite
        // Due since an hour ago, but its drive is away.
        music.anchor = .now.addingTimeInterval(-7 * 3_600)
        return [photos, invoices, projects, music]
    }()

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
        model.llama.models = ["qwen3-8b"]
        model.llama.model = "qwen3-8b"
        model.llama.status = .connected
        model.library.insertSample(tracks)
        model.library.notes = [
            "T1": .init(cleaned: true, log: "Removed duplicate “Daft Punk - One More Time (Official Video)”"),
            "T3": .init(cleaned: true, log: changes[1].log),
            "T4": .init(cleaned: false, log: "Not applied: " + changes[2].log),
            "T5": .init(cleaned: false, log: "Checked: nothing to change"),
        ]
        for report in shopReports.reversed() { model.shopChecks.add(report) }
        model.transfers.insertSample(jobs, previews: [
            jobs[0].id: "1,284 files · 6.2 GB", jobs[1].id: "3 files · 840 KB",
            jobs[2].id: "412 files · 96 MB", jobs[3].id: "Studio is not connected",
        ], running: .init(id: jobs[0].id, scheduled: true, phase: "Copying", fraction: 0.45, remaining: 194),
           waiting: [jobs[3].id: "Studio"])
        model.network.name = "ollama"
        model.network.insertSample(connections)
    }
}
