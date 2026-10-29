import Foundation

/// Shell commands for the Network Lock module. The lock itself is the netlock
/// script from the MacNetLock repo, bundled as Resources/netlock. With an allow
/// list pf blocks all traffic in and out, and every 0.5 s the script opens the
/// local ports of the listed apps' sockets; with a block list everything passes
/// and the script closes those ports instead. It runs as root, so the app starts
/// and stops it with one administrator prompt each.
public enum NetLock {
    /// Which apps the lock cuts off.
    public enum Mode: String, CaseIterable, Sendable {
        /// Everything is blocked except the listed apps.
        case allow
        /// Only the listed apps are blocked.
        case block
    }

    /// One argument for /bin/sh, in single quotes.
    public static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// pgrep -f pattern for a running lock. Anchored, so it never matches the
    /// root `sh -c` that starts or stops the lock, whose command line names the script too.
    public static func pattern(script: String) -> String {
        "^/bin/bash " + NSRegularExpression.escapedPattern(for: script) + " "
    }

    /// Stops a running lock and waits until it has restored the network (it does that on SIGTERM).
    /// Failsafe: a lock still running after 5 s ignored SIGTERM (a signal ignored when bash starts
    /// can't be trapped), so it gets SIGKILL and the network is restored here. Unlock never hangs.
    public static func stopCommand(script: String) -> String {
        let pattern = quote(pattern(script: script))
        return "/usr/bin/pkill -TERM -f \(pattern); i=0; while /usr/bin/pgrep -f \(pattern) >/dev/null; do "
            + "if [ $i -ge 25 ]; then /usr/bin/pkill -KILL -f \(pattern); sleep 0.5; /bin/bash \(quote(script)) restore; break; fi; "
            + "i=$((i + 1)); sleep 0.2; done"
    }

    /// Stops a running lock, then starts it again in the background with these apps.
    /// Allow mode without apps: everything except DNS is blocked. Output goes to `log`.
    /// The administrator prompt starts the shell with SIGTERM ignored and blocked, and bash can't trap
    /// a signal ignored at start, so perl sets TERM, HUP, and INT back to default and unblocks them
    /// before it runs the script.
    public static func startCommand(script: String, mode: Mode = .allow, apps: [String], log: String) -> String {
        let list = apps.map { "--\(mode.rawValue) \(quote($0))" }.joined(separator: " ")
        let resetSignals = #"/usr/bin/perl -MPOSIX -e '$SIG{$_} = "DEFAULT" for qw(TERM HUP INT); sigprocmask(SIG_UNBLOCK, POSIX::SigSet->new(SIGTERM, SIGHUP, SIGINT)); exec @ARGV'"#
        let run = [resetSignals, "/bin/bash", quote(script), "--no-monitor", list].filter { !$0.isEmpty }.joined(separator: " ")
        return "\(stopCommand(script: script)); \(run) >\(quote(log)) 2>&1 </dev/null &"
    }

    /// After a crash or kill -9 the rules stay in pf: load /etc/pf.conf and turn pf off.
    public static func restoreCommand(script: String) -> String {
        "\(stopCommand(script: script)); /bin/bash \(quote(script)) restore"
    }

    /// AppleScript that runs `command` as root after the administrator prompt.
    public static func appleScript(_ command: String) -> String {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }

    /// netlock splits --allow and --block at commas, so an app path with one can't be passed.
    public static func canAllow(_ path: String) -> Bool {
        path.hasSuffix(".app") && !path.contains(",")
    }
}
