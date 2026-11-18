import AppKit
import SwiftUI

/// 視覺 token。品牌色只在這裡定義，其他地方一律用語意色（憲法 U2）。
extension Color {
    /// 柿橘：主要動作、播放中的項目、波形已播放的部分（跟圖示同色系）
    static let persimmon = Color(nsColor: .dynamic(light: 0xC2512C, dark: 0xF28C5E))
    /// 琥珀：要注意的事（不可商用、錄音太短、缺 ffmpeg）
    static let signal = Color(nsColor: .dynamic(light: 0xB97F06, dark: 0xE2AD3B))
}

extension NSColor {
    static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }
}

extension Font {
    /// 內容頁的標題與段落標題用宋體，讓稿子、聲音、模型讀起來像一份文件
    static func songti(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .custom("Songti TC", size: size).weight(weight)
    }
}

/// 內容頁的段落標題。
struct SectionTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.songti(18))
            .accessibilityAddTraits(.isHeader)
    }
}

/// 文字樣式的次要動作（主色的字加小圖示），用在內容頁的標題下方，不佔一整排按鈕的份量。
struct LinkAction: View {
    let title: String
    let systemImage: String
    var role: ButtonRole?
    let action: () -> Void

    init(_ title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? AnyShapeStyle(.red) : AnyShapeStyle(Color.persimmon))
    }
}

/// 要使用者留意的提示條（琥珀色）。
struct Banner: View {
    let text: String
    var systemImage = "exclamationmark.circle.fill"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.signal)
                .accessibilityHidden(true)
            Text(text)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.signal.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// 滑過與選取的底色：單色的灰，不用強調色。
struct RowBackground: ViewModifier {
    let selected: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(Color.primary.opacity(selected ? 0.1 : (hovering ? 0.05 : 0)),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { hovering = $0 }
    }
}

extension View {
    func rowBackground(selected: Bool = false) -> some View { modifier(RowBackground(selected: selected)) }
}

/// 設定側欄圖示的底色：彩色圓角方塊加白色符號，跟系統設定同一種讀法（深淺色用同一組）。
enum IconTint {
    static let persimmon = Color(red: 0.92, green: 0.45, blue: 0.22)
    static let brown = Color(red: 0.62, green: 0.44, blue: 0.28)
    static let gray = Color(red: 0.52, green: 0.53, blue: 0.57)
    static let indigo = Color(red: 0.35, green: 0.35, blue: 0.86)
    static let green = Color(red: 0.2, green: 0.68, blue: 0.36)
    static let blue = Color(red: 0.16, green: 0.48, blue: 0.95)
}

/// 側欄頂端的搜尋欄（主視窗與設定視窗共用）。
struct SidebarSearchField: View {
    let prompt: String
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused(focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜尋")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.07), in: Capsule())
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }
}

/// 工具列最右邊的齒輪：打開設定（同選單列的「設定⋯」、⌘,）。每一頁放在自己工具列的最後一個。
struct SettingsToolbarItem: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) { SettingsButton() }
    }

    private struct SettingsButton: View {
        @Environment(\.openWindow) private var openWindow

        var body: some View {
            Button { openWindow(id: SettingsPage.windowID) } label: { Label("設定", systemImage: "gearshape") }
                .help("設定（⌘,）")
        }
    }
}
