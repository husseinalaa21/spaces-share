import SwiftUI

/// The same surfaces, rounded typography and control proportions as Spaces Dots & AI.
enum ShareTheme {
    static let blue = Color(red: 41 / 255, green: 121 / 255, blue: 1)
    static let ink = Color.black
    static let canvas = Color(white: 0.97)
    static let pill = Color(white: 0.93)
    static let secondary = Color.black.opacity(0.5)
    static let pageTitle = Font.system(.title, design: .rounded, weight: .bold)
    static let heading = Font.system(.title3, design: .rounded, weight: .bold)
    static let rowTitle = Font.system(.subheadline, design: .rounded, weight: .medium)
}

struct SharePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct ShareActionStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .foregroundStyle(prominent ? Color.white : ShareTheme.ink)
            .background(prominent ? Color.black : ShareTheme.pill, in: RoundedRectangle(cornerRadius: 14))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.25)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

extension View {
    @ViewBuilder func shareInlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
