import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = FlowModel()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: 100)
        if let button = item.button {
            button.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
            button.title = model.menuBarTitle
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 344, height: 532)
        popover.contentViewController = NSHostingController(rootView: PopoverView(model: model))
        self.popover = popover

        cancellable = model.$menuBarTitle.sink { [weak self] title in
            guard let self = self else { return }
            self.statusItem?.button?.title = title
            self.statusItem?.button?.toolTip = "Download \(ByteFormat.rate(self.model.downRate)) · Upload \(ByteFormat.rate(self.model.upRate))"
        }

        if CommandLine.arguments.contains("--show-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.showPopover()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.flush()
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover?.isShown == true {
            popover?.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let popover = popover,
              let button = statusItem?.button,
              !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
