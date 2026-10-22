import AppKit
import SwiftUI

/// Item da barra de menus com NSStatusItem + NSPopover, para que o atalho global ⌘⇧H consiga abri-lo
/// por código (o MenuBarExtra do SwiftUI não tem API para isso).
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "tree.fill", accessibilityDescription: "Hábitos")
            button.image?.isTemplate = true
            button.action = #selector(statusItemClicked)
            button.target = self
            button.toolTip = "Hábitos (⌘⇧H)"
        }
        statusItem = item

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: MenuBarPopoverView().habitForestEnvironment())
    }

    @objc private func statusItemClicked() {
        togglePopover()
    }

    func togglePopover() {
        popover.isShown ? closePopover() : showPopover()
    }

    func showPopover() {
        guard let button = statusItem?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        Haptics.perform(.alignment)
    }

    func closePopover() {
        popover.performClose(nil)
    }

    func popoverDidShow(_ notification: Notification) {
        HabitStore.shared.drainPendingActions()
    }
}
