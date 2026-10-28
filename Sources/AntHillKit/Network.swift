import Foundation

/// lsof rules for the Network Monitor module, ported from
/// the Scripts repo, Network/MonitorNetworkConnection.sh (`lsof -i -P -n | grep <app>`).
public enum Network {
    /// One open network socket of one process.
    public struct Connection: Identifiable, Hashable, Sendable {
        public let pid: Int
        public let command: String
        /// The file descriptor, unique within the process.
        public let fd: String
        /// IPv4 or IPv6.
        public let family: String
        /// TCP or UDP.
        public let proto: String
        public let local: String
        /// Empty for a socket that only listens or has no peer.
        public let remote: String
        /// ESTABLISHED, LISTEN, CLOSE_WAIT…; empty for UDP.
        public let state: String

        public var id: String { "\(pid)/\(fd)" }

        public init(pid: Int, command: String, fd: String, family: String, proto: String, local: String, remote: String, state: String) {
            self.pid = pid; self.command = command; self.fd = fd; self.family = family
            self.proto = proto; self.local = local; self.remote = remote; self.state = state
        }
    }

    /// lsof arguments: every internet socket, numeric hosts and ports, full command names, field output.
    public static let arguments = ["-nP", "-i", "+c", "0", "-F", "pcftPnT"]

    /// Parses `lsof -F pcftPnT` output: a `p` line starts a process, an `f` line starts a socket.
    public static func parse(_ output: String) -> [Connection] {
        var connections: [Connection] = []
        var pid = 0, command = ""
        var fd: String?, family = "", proto = "", name = "", state = ""
        func flush() {
            guard let current = fd else { return }
            let ends = name.components(separatedBy: "->")
            connections.append(Connection(pid: pid, command: command, fd: current, family: family, proto: proto,
                                          local: ends[0], remote: ends.count > 1 ? ends[1] : "", state: state))
            fd = nil
        }
        for line in output.split(separator: "\n") {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())
            switch field {
            case "p": flush(); pid = Int(value) ?? 0
            case "c": command = value
            case "f": flush(); fd = value; family = ""; proto = ""; name = ""; state = ""
            case "t": family = value
            case "P": proto = value
            case "n": name = value
            case "T" where value.hasPrefix("ST="): state = String(value.dropFirst(3))
            default: break
            }
        }
        flush()
        return connections
    }

    /// The connections of processes whose name contains `name`, ignoring case, like the script's grep.
    public static func connections(_ all: [Connection], of name: String) -> [Connection] {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return [] }
        return all.filter { $0.command.localizedCaseInsensitiveContains(name) }
    }

    /// The process names that have connections, for the app list.
    public static func apps(_ all: [Connection]) -> [String] {
        Set(all.map(\.command)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
