import Foundation
import SlapCore

/// Connects to the slapd socket, reads lines, and reconnects if the daemon goes away.
final class ImpactClient {
    var onConnectionChange: ((Bool) -> Void)?
    var onImpact: ((Double) -> Void)?

    func start() {
        Thread.detachNewThread { [weak self] in
            while let self {
                self.runOnce()
                Thread.sleep(forTimeInterval: 2)
            }
        }
    }

    private func runOnce() {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            _ = SlapProtocol.socketPath.withCString {
                strncpy(buf.baseAddress!.assumingMemoryBound(to: CChar.self), $0, buf.count - 1)
            }
        }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard ok == 0 else { return notify(connected: false) }

        var pending = Data()
        var buf = [UInt8](repeating: 0, count: 1024)
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            pending.append(contentsOf: buf[0..<n])
            while let nl = pending.firstIndex(of: UInt8(ascii: "\n")) {
                let line = String(decoding: pending[pending.startIndex..<nl], as: UTF8.self)
                pending.removeSubrange(pending.startIndex...nl)
                handle(line)
            }
        }
        notify(connected: false)
    }

    private func handle(_ line: String) {
        if line == "hello" {
            notify(connected: true)
        } else if line.hasPrefix("impact "), let v = Double(line.dropFirst(7)) {
            DispatchQueue.main.async { self.onImpact?(v) }
        }
    }

    private func notify(connected: Bool) {
        DispatchQueue.main.async { self.onConnectionChange?(connected) }
    }
}
