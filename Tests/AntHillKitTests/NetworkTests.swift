import Testing
@testable import AntHillKit

private let sample = """
    p618
    cControlCenter
    f9
    tIPv4
    PTCP
    n*:7000
    TST=LISTEN
    TQR=0
    TQS=0
    p1200
    collama
    f12
    tIPv4
    PTCP
    n127.0.0.1:11434->127.0.0.1:52344
    TST=ESTABLISHED
    f13
    tIPv6
    PUDP
    n[::1]:5353
    """

@Test func parsesLsofFields() {
    let all = Network.parse(sample)
    #expect(all.count == 3)
    #expect(all[0] == .init(pid: 618, command: "ControlCenter", fd: "9", family: "IPv4", proto: "TCP", local: "*:7000", remote: "", state: "LISTEN"))
    #expect(all[1] == .init(pid: 1200, command: "ollama", fd: "12", family: "IPv4", proto: "TCP",
                            local: "127.0.0.1:11434", remote: "127.0.0.1:52344", state: "ESTABLISHED"))
    #expect(all[2].proto == "UDP" && all[2].state.isEmpty && all[2].local == "[::1]:5353")
}

@Test func filtersByNameLikeGrep() {
    let all = Network.parse(sample)
    #expect(Network.connections(all, of: "Ollama").map(\.pid) == [1200, 1200])
    #expect(Network.connections(all, of: "  ").isEmpty)
    #expect(Network.apps(all) == ["ControlCenter", "ollama"])
}
