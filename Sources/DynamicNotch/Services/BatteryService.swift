import Foundation
import IOKit.ps
import NotchCore
import Observation

/// Event-driven battery and power source monitor backed by `IOKit.ps`.
@MainActor
@Observable
final class BatteryService {
    private(set) var status: BatteryStatus?
    var onBatteryEvent: ((HUDEvent) -> Void)?

    @ObservationIgnored private var runLoopSource: CFRunLoopSource?

    func start() {
        status = Self.readCurrentStatus()

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                service.handlePowerSourceChange()
            }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = source
        }
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
    }

    private func handlePowerSourceChange() {
        guard let updated = Self.readCurrentStatus() else { return }
        let previous = status
        status = updated

        if let previous {
            let pluggedChanged = previous.isPluggedIn != updated.isPluggedIn
            let chargingChanged = previous.isCharging != updated.isCharging
            let enteredLowBattery = !previous.isLowBattery && updated.isLowBattery
            if pluggedChanged || chargingChanged || enteredLowBattery {
                onBatteryEvent?(HUDEvent(kind: .battery(updated)))
            }
        }
    }

    static func readCurrentStatus() -> BatteryStatus? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any],
                  let capacity = desc[kIOPSCurrentCapacityKey] as? Int else {
                continue
            }
            let maxCapacity = (desc[kIOPSMaxCapacityKey] as? Int) ?? 100
            let pct = maxCapacity > 0 ? Int((Double(capacity) / Double(maxCapacity) * 100.0).rounded()) : capacity
            let isCharging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
            let powerSourceState = (desc[kIOPSPowerSourceStateKey] as? String) ?? ""
            let isPluggedIn = powerSourceState == kIOPSACPowerValue || isCharging
            let timeRemaining = desc[kIOPSTimeToEmptyKey] as? Int
            let validRemaining = (timeRemaining != nil && timeRemaining! > 0) ? timeRemaining : nil

            return BatteryStatus(
                percentage: pct,
                isCharging: isCharging,
                isPluggedIn: isPluggedIn,
                timeRemainingMinutes: validRemaining
            )
        }
        return nil
    }
}
