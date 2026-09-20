import SwiftUI
import UIKit

// MARK: - 卡片容器

struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
    }
}

// MARK: - 区块标题

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(Theme.text3)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 分段控件

struct SegmentedControl: View {
    let options: [String]
    @Binding var selection: Int
    var mono: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { idx, title in
                let active = idx == selection
                Text(title)
                    .font(mono
                          ? .system(size: 12, weight: active ? .semibold : .regular).monospaced()
                          : .system(size: 13, weight: active ? .semibold : .regular))
                    .foregroundColor(active ? Theme.text : Theme.text2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(active ? Theme.chip : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { selection = idx }
            }
        }
        .padding(3)
        .background(Theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
    }
}

// MARK: - 开关（44×26）

struct CapsuleSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Theme.accent : Theme.stroke)
                .frame(width: 44, height: 26)
            Circle()
                .fill(Color.white)
                .frame(width: 20, height: 20)
                .padding(.horizontal, 3)
        }
        .animation(.easeInOut(duration: 0.16), value: isOn)
        .onTapGesture { isOn.toggle() }
    }
}

// MARK: - 滑杆

struct SliderBar: View {
    @Binding var value: Double        // 0...1
    var onColor: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let knobX = max(10, min(w - 10, CGFloat(value) * w))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.stroke)
                    .frame(height: 4)
                Capsule()
                    .fill(onColor)
                    .frame(width: knobX, height: 4)
                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .position(x: knobX, y: geo.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let x = min(max(0, g.location.x), w)
                        value = Double(x / w)
                    }
            )
        }
        .frame(height: 24)
    }
}

// MARK: - 底部标签栏

struct PillTabBar: View {
    let items: [String]
    @Binding var selection: Int
    var onSelect: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, title in
                let active = idx == selection
                Text(title)
                    .font(.system(size: 13, weight: active ? .semibold : .regular))
                    .foregroundColor(active ? Theme.bg : Theme.text2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(active ? Theme.accent : Color.clear)
                    .clipShape(Capsule())
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selection = idx
                        onSelect?(idx)
                    }
            }
        }
        .padding(4)
        .background(Theme.card)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
    }
}

// MARK: - 导航栏

struct NavBar: View {
    let title: String
    var onBack: (() -> Void)? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 10) {
            if let onBack = onBack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
                    .onTapGesture { onBack() }
            }
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Theme.text)
            Spacer(minLength: 0)
            if let trailing = trailing { trailing }
        }
        .frame(height: 44)
    }
}

// MARK: - Toast

extension View {
    func toast(message: Binding<String?>) -> some View {
        overlay(alignment: .bottom) {
            if let text = message.wrappedValue {
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.bg)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.accent)
                    .clipShape(Capsule())
                    .padding(.bottom, 70)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            message.wrappedValue = nil
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: message.wrappedValue)
    }
}

// MARK: - 分享面板

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension View {
    func shareSheet(url: Binding<URL?>) -> some View {
        sheet(isPresented: Binding(
            get: { url.wrappedValue != nil },
            set: { if !$0 { url.wrappedValue = nil } }
        )) {
            if let u = url.wrappedValue {
                ShareSheet(url: u)
            }
        }
    }
}
