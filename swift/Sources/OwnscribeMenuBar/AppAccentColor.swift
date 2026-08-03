import SwiftUI

/// Single source of truth for the app's accent color. The validated design
/// (design/direction-b-glass.png) is purple throughout — selection, pills, envelope,
/// timestamps; mockup.html's blue predates it. Flipping the whole app's accent back to blue,
/// if ever overruled, is a one-line change here.
public enum AppAccentColor {
    public static let color: Color = .purple
}
