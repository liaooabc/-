import AppKit
import SwiftUI

/// 「关于更新雷达」：照 Apple 关于面板的样子做——图标、名称、版本号、一句说明。
struct AboutView: View {
    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "版本 \(short)（构建 \(build)）"
    }

    private var icon: NSImage {
        NSImage(named: NSImage.applicationIconName) ?? NSApp.applicationIconImage
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 108, height: 108)
                .padding(.top, 26)

            Text("更新雷达")
                .font(.system(size: 20, weight: .semibold))
                .padding(.top, 14)

            Text(version)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 3)

            Text("扫描本机 App，提醒你有新版本。")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
                .padding(.horizontal, 30)

            Spacer(minLength: 12)

            Text("常驻菜单栏 · 数据只存在本机")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 20)
        }
        .frame(width: 300, height: 330)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

@MainActor
final class AboutWindowController {
    private var window: NSWindow?

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: AboutView())
        let w = NSWindow(contentViewController: hosting)
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.title = "关于更新雷达"
        w.setContentSize(NSSize(width: 300, height: 330))
        w.center()
        w.isReleasedWhenClosed = false
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}
