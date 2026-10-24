// WindowDirector: a tiny menu bar app to list, switch to, and close open windows.
// The list is shown in a panel (not an NSMenu), so it stays open while you switch and close.
import AppKit
import SwiftUI
import Combine
import ApplicationServices

// MARK: - Accessibility helpers

func axValue(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
    return v
}

func axElement(_ el: AXUIElement, _ name: String) -> AXUIElement? {
    guard let v = axValue(el, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
    return (v as! AXUIElement)
}

func axWindows(of pid: pid_t) -> [AXUIElement] {
    let appEl = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(appEl, 0.3)
    guard let list = axValue(appEl, kAXWindowsAttribute) as? [AXUIElement] else { return [] }
    let keep: Set<String> = [kAXStandardWindowSubrole, kAXDialogSubrole]
    return list.filter { keep.contains(axValue($0, kAXSubroleAttribute) as? String ?? "") }
}

// MARK: - Model

struct WinEntry: Identifiable {
    let id: String
    let title: String
    let minimized: Bool
    let element: AXUIElement
}

struct AppEntry: Identifiable {
    let id: pid_t
    let app: NSRunningApplication
    let name: String
    let icon: NSImage?
    let windows: [WinEntry]
}

final class Model: ObservableObject {
    @Published var trusted = AXIsProcessTrusted()
    @Published var apps: [AppEntry] = []
    @Published var maxListHeight: CGFloat = 600

    // Rows and separators have fixed heights, so the panel height follows from their counts.
    var listHeight: CGFloat {
        let rows = apps.reduce(0) { $0 + 1 + $1.windows.count }
        let separators = max(apps.count - 1, 0)
        return CGFloat(rows) * rowHeight + CGFloat(separators) * separatorHeight
    }

    var panelHeight: CGFloat {
        let body = trusted ? min(listHeight, maxListHeight) : rowHeight
        return body + separatorHeight + rowHeight + listPadding * 2
    }

    func refresh() {
        trusted = AXIsProcessTrusted()
        guard trusted else { apps = []; return }
        apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
            .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
            .map { app in
                let pid = app.processIdentifier
                let wins = axWindows(of: pid).enumerated().map { i, w -> WinEntry in
                    let title = axValue(w, kAXTitleAttribute) as? String ?? ""
                    return WinEntry(id: "\(pid)-\(i)-\(CFHash(w))",
                                    title: title.isEmpty ? "Untitled" : title,
                                    minimized: axValue(w, kAXMinimizedAttribute) as? Bool == true,
                                    element: w)
                }
                return AppEntry(id: pid, app: app, name: app.localizedName ?? "?", icon: app.icon, windows: wins)
            }
    }

    private func refresh(after seconds: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { self.refresh() }
    }

    private func bringToFront(_ app: NSRunningApplication) {
        // Our panel never activates this app, so bring the target to the front via Accessibility.
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(appEl, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        app.activate(options: [])
    }

    func focus(_ a: AppEntry, _ w: WinEntry) {
        let el = w.element
        if w.minimized {
            AXUIElementSetAttributeValue(el, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        let raise = {
            AXUIElementSetAttributeValue(el, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(el, kAXRaiseAction as CFString)
        }
        raise()
        bringToFront(a.app)
        // Activation can land late and bring another window forward, so raise ours once more.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: raise)
        refresh(after: 0.3)
    }

    func close(_ w: WinEntry) {
        guard let button = axElement(w.element, kAXCloseButtonAttribute) else { NSSound.beep(); return }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
        refresh(after: 0.3)
    }

    func activate(_ a: AppEntry) {
        bringToFront(a.app)
    }

    func quit(_ a: AppEntry) {
        a.app.terminate()
        refresh(after: 0.6)
    }
}

// MARK: - Views
// Styled to look like a native macOS menu.

let panelWidth: CGFloat = 340
let cornerRadius: CGFloat = 14
let rowHeight: CGFloat = 24
let separatorHeight: CGFloat = 11
let listPadding: CGFloat = 5

// A hovered row turns accent-colored with white text, so tell child views about it.
struct HighlightedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isHighlighted: Bool {
        get { self[HighlightedKey.self] }
        set { self[HighlightedKey.self] = newValue }
    }
}

struct MenuSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(height: 1)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
    }
}

struct Row<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) { content }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .leading)
            .foregroundStyle(hover ? Color.white : Color.primary)
            .environment(\.isHighlighted, hover)
            .background(RoundedRectangle(cornerRadius: 7).fill(hover ? Color.accentColor : .clear))
            .padding(.horizontal, listPadding)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onTapGesture(perform: action)
    }
}

struct SecondaryText: View {
    let text: String
    @Environment(\.isHighlighted) private var highlighted

    var body: some View {
        Text(text).foregroundStyle(highlighted ? Color.white.opacity(0.8) : Color.secondary)
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var weight: Font.Weight = .regular
    let action: () -> Void
    @Environment(\.isHighlighted) private var highlighted

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .fontWeight(weight)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(highlighted ? Color.white : Color.secondary)
        .help(help)
    }
}

struct ContentView: View {
    @ObservedObject var model: Model

    var body: some View {
        VStack(spacing: 0) {
            if model.trusted {
                ScrollView { list }
                    .scrollIndicators(.never)
                    .frame(height: min(model.listHeight, model.maxListHeight))
            } else {
                Row(action: {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Text("Accessibility permission required")
                    Spacer()
                    SecondaryText(text: "Open Settings…")
                }
            }

            MenuSeparator()

            Row(action: { NSApp.terminate(nil) }) {
                Text("Quit WindowDirector")
            }
        }
        .font(.system(size: 13))
        .padding(.vertical, listPadding)
        .frame(width: panelWidth, alignment: .top)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.apps.enumerated()), id: \.element.id) { i, a in
                if i > 0 { MenuSeparator() }
                Row(action: { model.activate(a) }) {
                    if let icon = a.icon {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    }
                    Text(a.name).fontWeight(.semibold).lineLimit(1)
                    SecondaryText(text: "\(a.windows.count)")
                    Spacer()
                    IconButton(symbol: "power", help: "Quit \(a.name)", weight: .bold) { model.quit(a) }
                }
                ForEach(a.windows) { w in
                    Row(action: { model.focus(a, w) }) {
                        Text(w.title).lineLimit(1).truncationMode(.middle)
                            .padding(.leading, 22)
                        if w.minimized {
                            SecondaryText(text: "Minimized").font(.system(size: 11))
                        }
                        Spacer()
                        IconButton(symbol: "xmark", help: "Close Window") { model.close(w) }
                    }
                }
            }
        }
    }
}

// MARK: - Panel

final class ListPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    // Respond to the first click even though the panel is not in an active app.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: ListPanel!
    private var hosting: NSView!
    private let model = Model()
    private var timer: Timer?
    private var outsideClickMonitor: Any?
    private var modelChange: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "WindowDirector")
            button.target = self
            button.action = #selector(toggle)
        }

        panel = ListPanel(contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 300),
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // The window shadow ignores the rounded corners and leaves dark square edges, so turn it off.
        panel.hasShadow = false
        // Show and hide instantly instead of fading.
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.onCancel = { [weak self] in self?.hide() }

        let hostingView = ClickThroughHostingView(rootView: ContentView(model: model))
        // layoutPanel sizes the window; don't let SwiftUI constrain it.
        hostingView.sizingOptions = []
        hosting = hostingView
        // Resize the panel when the list changes (objectWillChange fires before the change, so defer).
        modelChange = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.layoutPanel() }
        }
        // Menu-like translucent glass background.
        // The glass draws its own outer shadow; clip to the rounded shape so no shadow or dark corners show.
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = cornerRadius
        let container = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: 300))
        container.wantsLayer = true
        container.layer?.cornerRadius = cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        for v in [glass, hosting!] {
            v.frame = container.bounds
            v.autoresizingMask = [.width, .height]
            container.addSubview(v)
        }
        panel.contentView = container

        // Ask for Accessibility permission on first launch.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    @objc private func toggle() {
        panel.isVisible ? hide() : show()
    }

    private func show() {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        model.maxListHeight = (screen?.visibleFrame.height ?? 800) * 0.75
        // Show the previous contents immediately, then refresh (don't wait for the window scan).
        layoutPanel()
        panel.orderFrontRegardless()
        panel.makeKey()
        DispatchQueue.main.async { self.model.refresh() }
        // Keep the list fresh while it is open.
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.model.refresh() }
        // Close when the user clicks outside the panel (in another app).
        // Clicks on our status icon arrive here too; leave those to toggle() so it doesn't close and reopen.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                guard let self, !self.isMouseOnStatusIcon() else { return }
                self.hide()
            }
    }

    private func isMouseOnStatusIcon() -> Bool {
        guard let button = statusItem.button, let bw = button.window else { return false }
        let frame = bw.convertToScreen(button.convert(button.bounds, to: nil))
        return frame.contains(NSEvent.mouseLocation)
    }

    private func hide() {
        timer?.invalidate()
        timer = nil
        if let m = outsideClickMonitor {
            NSEvent.removeMonitor(m)
            outsideClickMonitor = nil
        }
        panel.orderOut(nil)
    }

    // Like a menu: just below the status icon, aligned to its left edge.
    private func layoutPanel() {
        guard let button = statusItem.button, let bw = button.window else { return }
        let size = NSSize(width: panelWidth, height: model.panelHeight)
        let b = bw.convertToScreen(button.convert(button.bounds, to: nil))
        let vf = (bw.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let x = min(max(b.minX, vf.minX + 8), vf.maxX - size.width - 8)
        let y = b.minY - size.height - 6
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
