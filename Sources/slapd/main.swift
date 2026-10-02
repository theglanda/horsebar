import Foundation
import SlapCore

// slapd — reads the accelerometer (needs root) and broadcasts slaps over a Unix socket.
// Run by hand for debugging:  sudo .build/release/slapd --print

let printImpacts = CommandLine.arguments.contains("--print")
let path = SlapProtocol.socketPath

func log(_ s: String) {
    FileHandle.standardError.write("slapd: \(s)\n".data(using: .utf8)!)
}

guard getuid() == 0 else {
    log("must run as root: sudo \(CommandLine.arguments[0])")
    exit(1)
}
signal(SIGPIPE, SIG_IGN)

// MARK: - socket

final class Broadcaster {
    private var clients: [Int32] = []
    private let lock = NSLock()

    func add(_ fd: Int32) {
        lock.lock(); clients.append(fd); lock.unlock()
        send("hello\n", to: [fd])
    }

    func broadcast(_ line: String) {
        lock.lock(); let fds = clients; lock.unlock()
        let dead = send(line, to: fds)
        guard !dead.isEmpty else { return }
        lock.lock(); clients.removeAll { dead.contains($0) }; lock.unlock()
        dead.forEach { close($0) }
    }

    @discardableResult
    private func send(_ line: String, to fds: [Int32]) -> [Int32] {
        let bytes = Array(line.utf8)
        return fds.filter { fd in write(fd, bytes, bytes.count) != bytes.count }
    }
}

let broadcaster = Broadcaster()

unlink(path)
let server = socket(AF_UNIX, SOCK_STREAM, 0)
var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
withUnsafeMutableBytes(of: &addr.sun_path) { buf in
    _ = path.withCString { strncpy(buf.baseAddress!.assumingMemoryBound(to: CChar.self), $0, buf.count - 1) }
}
let bound = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard server >= 0, bound == 0, listen(server, 8) == 0 else {
    log("failed to open socket \(path): \(String(cString: strerror(errno)))")
    exit(1)
}
chmod(path, 0o666)   // the menu bar app does not run as root

Thread.detachNewThread {
    while true {
        let fd = accept(server, nil, nil)
        if fd >= 0 { broadcaster.add(fd) }
    }
}

// MARK: - sensor

var detector = ImpactDetector()
let reader = AccelerometerReader { x, y, z in
    guard let strength = detector.feed(x: x, y: y, z: z, at: ProcessInfo.processInfo.systemUptime) else { return }
    let line = String(format: "impact %.3f\n", strength)
    if printImpacts { print(line, terminator: ""); fflush(stdout) }
    broadcaster.broadcast(line)
}

do {
    try reader.start()
} catch AccelerometerReader.Failure.notFound {
    // no sensor on this Mac: exit cleanly so launchd stops restarting us
    log("\(AccelerometerReader.Failure.notFound)")
    exit(0)
} catch {
    log("\(error)")
    exit(1)
}
log("listening to accelerometer, socket \(path)")
CFRunLoopRun()
