import Foundation
import IOKit
import IOKit.hid

/// Reads the SPU accelerometer (Bosch BMI286) on Apple Silicon via undocumented IOKit HID.
/// Requires root. Report layout taken from macimu (olvvier/apple-silicon-accelerometer).
public final class AccelerometerReader {
    public typealias Handler = (_ x: Double, _ y: Double, _ z: Double) -> Void

    static let vendorPage = 0xFF00
    static let accelUsage = 3
    static let reportLength = 22
    static let dataOffset = 6
    static let scale = 65536.0          // Q16 -> g
    static let reportIntervalUS: Int32 = 1000

    public enum Failure: Error, CustomStringConvertible {
        case notFound, openFailed(IOReturn)
        public var description: String {
            switch self {
            case .notFound: return "SPU accelerometer not found (requires M1 Pro / M2 or newer)"
            case .openFailed(let kr): return String(format: "IOHIDDeviceOpen returned 0x%08x (not running as root?)", kr)
            }
        }
    }

    private let handler: Handler
    private var device: IOHIDDevice?
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    deinit { buffer.deallocate() }

    /// Whether this Mac has the sensor (no root needed).
    public static func isAvailable() -> Bool {
        var found = false
        forEachService("AppleSPUHIDDevice") { svc in
            if intProperty(svc, "PrimaryUsagePage") == vendorPage && intProperty(svc, "PrimaryUsage") == accelUsage {
                found = true
            }
        }
        return found
    }

    /// Turns the sensor on and subscribes to reports on the current run loop.
    public func start() throws {
        // wake up the SPU drivers
        Self.forEachService("AppleSPUHIDDriver") { svc in
            let props: [(String, Int32)] = [
                ("SensorPropertyReportingState", 1),
                ("SensorPropertyPowerState", 1),
                ("ReportInterval", Self.reportIntervalUS),
            ]
            for (k, v) in props {
                IORegistryEntrySetCFProperty(svc, k as CFString, NSNumber(value: v))
            }
        }

        var service: io_service_t = 0
        Self.forEachService("AppleSPUHIDDevice") { svc in
            if service == 0,
               Self.intProperty(svc, "PrimaryUsagePage") == Self.vendorPage,
               Self.intProperty(svc, "PrimaryUsage") == Self.accelUsage {
                IOObjectRetain(svc)
                service = svc
            }
        }
        guard service != 0 else { throw Failure.notFound }
        defer { IOObjectRelease(service) }

        guard let dev = IOHIDDeviceCreate(kCFAllocatorDefault, service) else { throw Failure.notFound }
        let kr = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        guard kr == kIOReturnSuccess else { throw Failure.openFailed(kr) }

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(dev, buffer, 4096, { ctx, _, _, _, _, report, length in
            guard let ctx, length == AccelerometerReader.reportLength else { return }
            let reader = Unmanaged<AccelerometerReader>.fromOpaque(ctx).takeUnretainedValue()
            reader.handle(report)
        }, ctx)
        IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        device = dev
    }

    private func handle(_ report: UnsafeMutablePointer<UInt8>) {
        func axis(_ i: Int) -> Double {
            let raw = UnsafeRawPointer(report + Self.dataOffset + i * 4).loadUnaligned(as: Int32.self)
            return Double(Int32(littleEndian: raw)) / Self.scale
        }
        handler(axis(0), axis(1), axis(2))
    }

    // MARK: - IOKit helpers

    static func forEachService(_ className: String, _ body: (io_service_t) -> Void) {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &it) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(it) }
        while case let svc = IOIteratorNext(it), svc != 0 {
            body(svc)
            IOObjectRelease(svc)
        }
    }

    static func intProperty(_ svc: io_service_t, _ key: String) -> Int? {
        IORegistryEntryCreateCFProperty(svc, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Int
    }
}
