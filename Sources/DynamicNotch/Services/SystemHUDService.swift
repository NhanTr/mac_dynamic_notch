import AppKit
import ApplicationServices
import CoreAudio
import Darwin
import Foundation
import NotchCore
import Observation

/// Observes and controls system audio volume, mute state, and display brightness,
/// emitting `HUDEvent` notifications when hardware or software values change.
///
/// When `suppressNativeHUD` is enabled and Accessibility permission is granted,
/// installs a `CGEventTap` to intercept media/brightness keys and suppress the
/// default macOS `OSDUIHelper` overlay.
@MainActor
@Observable
final class SystemHUDService {
    private(set) var volume: Float = 0.5
    private(set) var isMuted: Bool = false
    private(set) var brightness: Float = 0.75
    private(set) var isAccessibilityTrusted: Bool = AXIsProcessTrusted()

    var suppressNativeHUD: Bool = false {
        didSet { updateEventTapState() }
    }

    var onHUDEvent: ((HUDEvent) -> Void)?

    @ObservationIgnored private var currentDeviceID: AudioObjectID = kAudioObjectUnknown
    @ObservationIgnored private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var volumeListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var muteListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var eventMonitors: [Any] = []
    @ObservationIgnored private var eventTap: CFMachPort?
    @ObservationIgnored private var eventTapRunLoopSource: CFRunLoopSource?
    @ObservationIgnored private let displayServices = DisplayServicesBridge()
    @ObservationIgnored private var suppressNextAudioCallback = false

    // Virtual main volume selector ('vmvc') from AudioToolbox/AudioHardwareService.
    private static let virtualMainVolumeSelector: AudioObjectPropertySelector = 0x766D_7663
    private static let stepIncrement: Float = 1.0 / 16.0

    func start() {
        isAccessibilityTrusted = AXIsProcessTrusted()
        refreshAudioDevice(emitHUD: false)
        if let currentBrightness = displayServices.getBrightness() {
            brightness = currentBrightness
        }
        installDefaultDeviceListener()
        installSystemKeyMonitors()
        updateEventTapState()
    }

    func stop() {
        teardownEventTap()
        removeDeviceListeners()
        if let defaultDeviceListener {
            var address = Self.defaultOutputDeviceAddress
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                defaultDeviceListener
            )
            self.defaultDeviceListener = nil
        }
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
    }

    func refreshAccessibilityTrust() {
        isAccessibilityTrusted = AXIsProcessTrusted()
        updateEventTapState()
    }

    func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isAccessibilityTrusted = AXIsProcessTrustedWithOptions(options)
        updateEventTapState()
    }

    // MARK: - Controls

    func setVolume(_ newValue: Float, emitHUD: Bool = true) {
        let clamped = min(1, max(0, newValue))
        volume = clamped
        if clamped > 0.001 && isMuted {
            isMuted = false
            writeMute(false)
        }
        suppressNextAudioCallback = !emitHUD
        writeVolume(clamped)
        if emitHUD {
            onHUDEvent?(HUDEvent(kind: .volume(clamped, isMuted: isMuted)))
        }
    }

    func toggleMute(emitHUD: Bool = true) {
        let target = !isMuted
        isMuted = target
        suppressNextAudioCallback = !emitHUD
        writeMute(target)
        if emitHUD {
            onHUDEvent?(HUDEvent(kind: .volume(volume, isMuted: target)))
        }
    }

    func setBrightness(_ newValue: Float, emitHUD: Bool = true) {
        let clamped = min(1, max(0, newValue))
        brightness = clamped
        displayServices.setBrightness(clamped)
        if emitHUD {
            onHUDEvent?(HUDEvent(kind: .brightness(clamped)))
        }
    }

    // MARK: - CoreAudio Observation

    private static var defaultOutputDeviceAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: virtualMainVolumeSelector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func installDefaultDeviceListener() {
        var address = Self.defaultOutputDeviceAddress
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.refreshAudioDevice(emitHUD: false)
            }
        }
        defaultDeviceListener = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

    private func refreshAudioDevice(emitHUD: Bool) {
        removeDeviceListeners()

        var address = Self.defaultOutputDeviceAddress
        var deviceID: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return }
        currentDeviceID = deviceID

        readAudioState(emitHUD: emitHUD)

        var volAddr = Self.volumeAddress
        let volBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.handleExternalAudioChange()
            }
        }
        if AudioObjectAddPropertyListenerBlock(deviceID, &volAddr, DispatchQueue.main, volBlock) == noErr {
            volumeListener = volBlock
        }

        var muteAddr = Self.muteAddress
        let muteBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.handleExternalAudioChange()
            }
        }
        if AudioObjectAddPropertyListenerBlock(deviceID, &muteAddr, DispatchQueue.main, muteBlock) == noErr {
            muteListener = muteBlock
        }
    }

    private func removeDeviceListeners() {
        guard currentDeviceID != kAudioObjectUnknown else { return }
        if let volumeListener {
            var addr = Self.volumeAddress
            AudioObjectRemovePropertyListenerBlock(currentDeviceID, &addr, DispatchQueue.main, volumeListener)
            self.volumeListener = nil
        }
        if let muteListener {
            var addr = Self.muteAddress
            AudioObjectRemovePropertyListenerBlock(currentDeviceID, &addr, DispatchQueue.main, muteListener)
            self.muteListener = nil
        }
        currentDeviceID = kAudioObjectUnknown
    }

    private func handleExternalAudioChange() {
        if suppressNextAudioCallback {
            suppressNextAudioCallback = false
            return
        }
        readAudioState(emitHUD: true)
    }

    private func readAudioState(emitHUD: Bool) {
        guard currentDeviceID != kAudioObjectUnknown else { return }
        let oldVolume = volume
        let oldMuted = isMuted

        var volAddr = Self.volumeAddress
        var newVolume: Float32 = volume
        var volSize = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectHasProperty(currentDeviceID, &volAddr),
           AudioObjectGetPropertyData(currentDeviceID, &volAddr, 0, nil, &volSize, &newVolume) == noErr {
            volume = min(1, max(0, newVolume))
        }

        var muteAddr = Self.muteAddress
        var muteVal: UInt32 = isMuted ? 1 : 0
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(currentDeviceID, &muteAddr),
           AudioObjectGetPropertyData(currentDeviceID, &muteAddr, 0, nil, &muteSize, &muteVal) == noErr {
            isMuted = (muteVal != 0)
        }

        if emitHUD, (abs(volume - oldVolume) > 0.005 || isMuted != oldMuted) {
            onHUDEvent?(HUDEvent(kind: .volume(volume, isMuted: isMuted)))
        }
    }

    private func writeVolume(_ value: Float) {
        guard currentDeviceID != kAudioObjectUnknown else { return }
        var volAddr = Self.volumeAddress
        var scalar = Float32(value)
        let size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectHasProperty(currentDeviceID, &volAddr) {
            AudioObjectSetPropertyData(currentDeviceID, &volAddr, 0, nil, size, &scalar)
        }
    }

    private func writeMute(_ muted: Bool) {
        guard currentDeviceID != kAudioObjectUnknown else { return }
        var muteAddr = Self.muteAddress
        var flag: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(currentDeviceID, &muteAddr) {
            AudioObjectSetPropertyData(currentDeviceID, &muteAddr, 0, nil, size, &flag)
        }
    }

    // MARK: - Media & Brightness Key Monitoring + Optional CGEventTap Interception

    private func updateEventTapState() {
        isAccessibilityTrusted = AXIsProcessTrusted()
        guard suppressNativeHUD && isAccessibilityTrusted else {
            teardownEventTap()
            return
        }
        guard eventTap == nil else { return }

        // Event type 14 == NSEvent.EventType.systemDefined
        let mask = CGEventMask(1 << 14)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, cgEvent, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(cgEvent) }
                let service = Unmanaged<SystemHUDService>.fromOpaque(userInfo).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    MainActor.assumeIsolated {
                        if let tap = service.eventTap {
                            CGEvent.tapEnable(tap: tap, enable: true)
                        }
                    }
                    return Unmanaged.passUnretained(cgEvent)
                }
                guard type.rawValue == 14,
                      let nsEvent = NSEvent(cgEvent: cgEvent),
                      nsEvent.subtype.rawValue == 8 else {
                    return Unmanaged.passUnretained(cgEvent)
                }
                let data1 = nsEvent.data1
                let keyCode = (data1 & 0xFFFF_0000) >> 16
                let keyFlags = data1 & 0x0000_FFFF
                let isKeyDown = ((keyFlags & 0xFF00) >> 8) == 0xA

                // 0: VolUp, 1: VolDown, 2: BrightUp, 3: BrightDown, 7: Mute
                guard [0, 1, 2, 3, 7].contains(keyCode) else {
                    return Unmanaged.passUnretained(cgEvent)
                }
                if isKeyDown {
                    MainActor.assumeIsolated {
                        service.handleInterceptedMediaKey(keyCode: keyCode)
                    }
                }
                // Swallow the event so OSDUIHelper does not show the system HUD.
                return nil
            },
            userInfo: refcon
        ) else {
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        eventTapRunLoopSource = source
    }

    private func teardownEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        eventTapRunLoopSource = nil
    }

    private func handleInterceptedMediaKey(keyCode: Int) {
        switch keyCode {
        case 0: // NX_KEYTYPE_SOUND_UP
            setVolume(volume + Self.stepIncrement, emitHUD: true)
        case 1: // NX_KEYTYPE_SOUND_DOWN
            setVolume(volume - Self.stepIncrement, emitHUD: true)
        case 7: // NX_KEYTYPE_MUTE
            toggleMute(emitHUD: true)
        case 2: // NX_KEYTYPE_BRIGHTNESS_UP
            let base = displayServices.getBrightness() ?? brightness
            setBrightness(base + Self.stepIncrement, emitHUD: true)
        case 3: // NX_KEYTYPE_BRIGHTNESS_DOWN
            let base = displayServices.getBrightness() ?? brightness
            setBrightness(base - Self.stepIncrement, emitHUD: true)
        default:
            break
        }
    }

    private func installSystemKeyMonitors() {
        let handler: @Sendable (NSEvent) -> Void = { [weak self] event in
            guard event.subtype.rawValue == 8 else { return } // NX_SUBTYPE_AUX_CONTROL_BUTTONS
            let data1 = event.data1
            let keyCode = (data1 & 0xFFFF_0000) >> 16
            let keyFlags = data1 & 0x0000_FFFF
            let isKeyDown = ((keyFlags & 0xFF00) >> 8) == 0xA
            guard isKeyDown else { return }

            MainActor.assumeIsolated {
                self?.handleMediaKeyDown(keyCode: keyCode)
            }
        }

        if let global = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined, handler: handler) {
            eventMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .systemDefined, handler: { event in
            handler(event)
            return event
        }) {
            eventMonitors.append(local)
        }
    }

    private func handleMediaKeyDown(keyCode: Int) {
        guard eventTap == nil else { return }
        // NX_KEYTYPE_BRIGHTNESS_UP = 2, NX_KEYTYPE_BRIGHTNESS_DOWN = 3
        if keyCode == 2 || keyCode == 3 {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(35))
                guard let self, let updated = self.displayServices.getBrightness() else { return }
                self.brightness = updated
                self.onHUDEvent?(HUDEvent(kind: .brightness(updated)))
            }
        }
    }
}

// MARK: - Dynamic DisplayServices Bridge

private final class DisplayServicesBridge: Sendable {
    private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private nonisolated(unsafe) let getPtr: GetBrightnessFn?
    private nonisolated(unsafe) let setPtr: SetBrightnessFn?

    init() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        if let handle = dlopen(path, RTLD_LAZY) {
            if let sym = dlsym(handle, "DisplayServicesGetBrightness") {
                getPtr = unsafeBitCast(sym, to: GetBrightnessFn.self)
            } else {
                getPtr = nil
            }
            if let sym = dlsym(handle, "DisplayServicesSetBrightness") {
                setPtr = unsafeBitCast(sym, to: SetBrightnessFn.self)
            } else {
                setPtr = nil
            }
        } else {
            getPtr = nil
            setPtr = nil
        }
    }

    func getBrightness(displayID: CGDirectDisplayID = CGMainDisplayID()) -> Float? {
        guard let getPtr else { return nil }
        var value: Float = 0
        let err = getPtr(displayID, &value)
        return err == 0 ? min(1, max(0, value)) : nil
    }

    func setBrightness(_ value: Float, displayID: CGDirectDisplayID = CGMainDisplayID()) {
        _ = setPtr?(displayID, min(1, max(0, value)))
    }
}
