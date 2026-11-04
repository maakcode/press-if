import AppKit
import SwiftUI

enum PressLocale {
    static let english = Locale(identifier: "en_US")
}

enum PressPalette {
    static let white = Color.white
    static let neutral50 = color(0xFAFAFA)
    static let neutral100 = color(0xF5F5F5)
    static let neutral200 = color(0xE5E5E5)
    static let neutral300 = color(0xD4D4D4)
    static let neutral400 = color(0xA1A1A1)
    static let neutral500 = color(0x737373)
    static let neutral600 = color(0x525252)
    static let neutral700 = color(0x404040)
    static let neutral900 = color(0x171717)
    static let neutral950 = color(0x0A0A0A)
    static let cyan50 = color(0xECFEFF)
    static let cyan100 = color(0xCEFAFE)
    static let cyan200 = color(0xA2F4FD)
    static let cyan400 = color(0x00D3F2)
    static let cyan500 = color(0x00B8DB)
    static let cyan600 = color(0x0092B8)
    static let cyan700 = color(0x007595)
    static let cyan800 = color(0x005F78)
    static let cyan900 = color(0x104E64)
    static let cyan950 = color(0x053345)

    static let canvas = neutral50
    static let surface = white
    static let surfaceMuted = neutral100
    static let border = neutral200
    static let textPrimary = neutral900
    static let textSecondary = neutral600
    static let textTertiary = neutral500
    static let accent = cyan900
    static let accentPressed = cyan950
    static let accentSurface = cyan900.opacity(0.06)
    static let accentBorder = cyan900.opacity(0.22)

    static let editorText = nativeColor(0x171717)
    static let editorCaret = nativeColor(0x104E64)
    static let editorSelection = nativeColor(0x104E64)
    static let editorSelectionText = NSColor.white

    private static func color(_ hex: UInt32) -> Color {
        Color(nsColor: nativeColor(hex))
    }

    private static func nativeColor(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

struct PressButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet }
    var kind: Kind = .secondary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        PressButtonContent(configuration: configuration, kind: kind, isEnabled: isEnabled)
    }
}

private struct PressButtonContent: View {
    let configuration: ButtonStyleConfiguration
    let kind: PressButtonStyle.Kind
    let isEnabled: Bool
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, kind == .quiet ? 8 : 14)
            .frame(minHeight: 36)
            .foregroundStyle(foreground)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(kind == .secondary ? PressPalette.border : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var foreground: Color {
        guard isEnabled else { return PressPalette.neutral400 }
        return kind == .primary ? .white : PressPalette.textSecondary
    }

    private var background: Color {
        guard isEnabled else { return PressPalette.neutral100 }
        switch kind {
        case .primary: return configuration.isPressed || hovering ? PressPalette.accentPressed : PressPalette.accent
        case .secondary: return configuration.isPressed || hovering ? PressPalette.surfaceMuted : PressPalette.surface
        case .quiet: return configuration.isPressed || hovering ? PressPalette.surfaceMuted : .clear
        }
    }
}

private struct PressCard: ViewModifier {
    let padding: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PressPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(PressPalette.border, lineWidth: 1) }
    }
}

extension View {
    func pressCard(padding: CGFloat = 20) -> some View { modifier(PressCard(padding: padding)) }
}
