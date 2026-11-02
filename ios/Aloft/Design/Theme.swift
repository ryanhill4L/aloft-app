import SwiftUI
import UIKit

/// Aloft design tokens (project/ds/aloft/tokens.json in the design canvas).
/// Dark first, light equal: every color resolves per trait.
enum Palette {
    static let ground = Color(dark: 0x0E0F11, light: 0xEFEEEA)
    static let raised = Color(dark: 0x17181B, light: 0xF8F7F3)
    static let well = Color(dark: 0x08090A, light: 0xE3E2DD)
    static let line = Color(dark: 0x2A2C30, light: 0xD6D4CD)
    static let lineStrong = Color(dark: 0x74777D, light: 0x83817A)
    static let ink = Color(dark: 0xECE9E2, light: 0x0F1012)
    static let inkMuted = Color(dark: 0xA7A6A0, light: 0x55544F)
    static let inkFaint = Color(dark: 0x8A8A84, light: 0x676660)
    static let sky = Color(dark: 0x8FD6F5, light: 0x0B6A9E)
    static let onSky = Color(dark: 0x0A1A24, light: 0xFFFFFF)
    static let skyTint = Color(dark: 0x14262F, light: 0xD8ECF5)
    static let lamp = Color(dark: 0xEFA953, light: 0x8F5410)
    static let onLamp = Color(dark: 0x1C1206, light: 0xFFFFFF)
    static let lampTint = Color(dark: 0x2A2013, light: 0xF6E6CF)
    static let fair = Color(dark: 0xDDD5C0, light: 0x6A5F45)
    static let overcast = Color(dark: 0x8B949C, light: 0x525B63)
    static let ember = Color(dark: 0xFF8F70, light: 0xB23A1E)
    /// Text drawn directly on the pixel sky, in both themes.
    static let onWindow = Color(hex: 0xF3F8FB)
    static let shadow = Color(dark: 0x000000, light: 0x28261E).opacity(0.5)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    init(dark: UInt32, light: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .light ? light : dark))
        })
    }
}

enum Space {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 24
    static let s6: CGFloat = 32
    static let s7: CGFloat = 48
}

enum Radius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 14
    static let lg: CGFloat = 22
    static let xl: CGFloat = 36
}

/// The type scale. Brand sans for words, instrument mono for numbers, human
/// serif only for words one person wrote to another.
enum TextStyle {
    case displayXL, display, title, heading, body, small
    case readoutXL, readoutLG, readout, stamp
    case voice, voiceSmall

    var font: Font {
        switch self {
        case .displayXL: .custom("HostGrotesk-Light", fixedSize: 64)
        case .display: .custom("HostGrotesk-Light", fixedSize: 44)
        case .title: .custom("HostGrotesk-Regular", size: 28, relativeTo: .title)
        case .heading: .custom("HostGrotesk-Medium", size: 20, relativeTo: .headline)
        case .body: .custom("HostGrotesk-Regular", size: 16, relativeTo: .body)
        case .small: .custom("HostGrotesk-Regular", size: 14, relativeTo: .subheadline)
        case .readoutXL: .custom("IBMPlexMono-Light", fixedSize: 88)
        case .readoutLG: .custom("IBMPlexMono-Light", fixedSize: 40)
        case .readout: .custom("IBMPlexMono-Regular", size: 16, relativeTo: .body)
        case .stamp: .custom("IBMPlexMono-Medium", size: 11, relativeTo: .caption2)
        case .voice: .custom("Newsreader16pt-Italic", size: 22, relativeTo: .title3)
        case .voiceSmall: .custom("Newsreader16pt-Italic", size: 17, relativeTo: .body)
        }
    }

    var tracking: CGFloat {
        switch self {
        case .displayXL: -1.92
        case .display: -1.1
        case .title: -0.56
        case .heading: -0.2
        case .body: -0.08
        case .readoutXL: -3.52
        case .readoutLG: -1.2
        case .stamp: 0.88
        default: 0
        }
    }

    /// Line height from the tokens, in points.
    var lineHeight: CGFloat {
        switch self {
        case .displayXL: 64
        case .display: 48
        case .title: 34
        case .heading: 26
        case .body: 24
        case .small: 20
        case .readoutXL: 88
        case .readoutLG: 44
        case .readout: 20
        case .stamp: 14
        case .voice: 30
        case .voiceSmall: 24
        }
    }
}

extension View {
    func textStyle(_ style: TextStyle) -> some View {
        font(style.font)
            .tracking(style.tracking)
            .monospacedDigit()
            .modifier(ExactLineHeight(points: style.lineHeight))
    }
}

/// iOS 26 can set an exact line height; earlier systems keep the font's own.
private struct ExactLineHeight: ViewModifier {
    let points: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.lineHeight(.exact(points: points))
        } else {
            content
        }
    }
}

/// An uppercase mono label: section numbers, captions, timestamps.
struct Stamp: View {
    let text: String
    var color: Color = Palette.inkFaint

    init(_ text: String, color: Color = Palette.inkFaint) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .textStyle(.stamp)
            .foregroundStyle(color)
    }
}
