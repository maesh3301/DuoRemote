import Foundation

/// The kit's settings, for an app that shows them itself. Sessions read them when they start.
public enum RemoteSettings {
    public static var defaults: UserDefaults { .remote }

    public static let inputModeKey = "defaultInputMode"
    public static let scrollSpeedKey = "scrollSpeed"
    public static let invertScrollKey = "invertScroll"
    public static let pointerSpeedKey = "pointerSpeed"
    public static let autoComposeKey = "autoCompose"
    public static let effectsKey = "effectsEnabled"
    public static let skyThemeKey = "skyTheme"

    public static let defaultScrollSpeed = VNCSession.defaultScrollSpeed
    public static let scrollSpeeds: ClosedRange<Double> = 1...5
    public static let pointerSpeeds: ClosedRange<Double> = 0.5...2
}
