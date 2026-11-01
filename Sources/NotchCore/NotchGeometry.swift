import CoreGraphics

/// Raw, AppKit-independent description of a display, captured from `NSScreen`.
///
/// All rects are in global AppKit screen coordinates (origin at the bottom-left
/// of the primary display, y grows upward).
public struct ScreenMetrics: Sendable, Equatable {
    public var frame: CGRect
    public var visibleFrame: CGRect
    /// `NSScreen.safeAreaInsets.top`. Greater than zero only on displays with a camera housing.
    public var safeAreaTop: CGFloat
    /// Width of `NSScreen.auxiliaryTopLeftArea`, if any.
    public var auxiliaryTopLeftWidth: CGFloat?
    /// Width of `NSScreen.auxiliaryTopRightArea`, if any.
    public var auxiliaryTopRightWidth: CGFloat?

    public init(
        frame: CGRect,
        visibleFrame: CGRect,
        safeAreaTop: CGFloat = 0,
        auxiliaryTopLeftWidth: CGFloat? = nil,
        auxiliaryTopRightWidth: CGFloat? = nil
    ) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeftWidth = auxiliaryTopLeftWidth
        self.auxiliaryTopRightWidth = auxiliaryTopRightWidth
    }
}

/// The size of the physical notch, or of a virtual one on notch-less displays.
public struct NotchGeometry: Sendable, Equatable {
    /// Width used for the virtual notch on displays without a camera housing.
    public static let virtualNotchWidth: CGFloat = 185
    /// Height used when the menu bar height cannot be determined (e.g. auto-hidden menu bar).
    public static let fallbackHeight: CGFloat = 24

    public let hasPhysicalNotch: Bool
    public let size: CGSize

    public init(hasPhysicalNotch: Bool, size: CGSize) {
        self.hasPhysicalNotch = hasPhysicalNotch
        self.size = size
    }

    public init(metrics: ScreenMetrics) {
        if metrics.safeAreaTop > 0,
           let left = metrics.auxiliaryTopLeftWidth,
           let right = metrics.auxiliaryTopRightWidth {
            let width = metrics.frame.width - left - right
            self.init(
                hasPhysicalNotch: true,
                size: CGSize(
                    width: width > 0 ? width.rounded() : Self.virtualNotchWidth,
                    height: metrics.safeAreaTop
                )
            )
        } else {
            let menuBarHeight = metrics.frame.maxY - metrics.visibleFrame.maxY
            self.init(
                hasPhysicalNotch: false,
                size: CGSize(
                    width: Self.virtualNotchWidth,
                    height: menuBarHeight > 0 ? menuBarHeight : Self.fallbackHeight
                )
            )
        }
    }
}
