import AppKit
import SwiftUI
import os.log

@main
struct LlamaBarnApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    // Empty scene, as we are a menu bar app
    Settings {
      EmptyView()
    }
    .commands {
      CommandGroup(replacing: .appSettings) {
        Button("Settings...") {
          NotificationCenter.default.post(name: .LBShowSettings, object: nil)
        }
        .keyboardShortcut(",")
      }
    }
  }
}

class AppDelegate: NSObject, NSApplicationDelegate {
  private let logger = Logger(subsystem: Logging.subsystem, category: "AppDelegate")
  private var menuController: MenuController?
  private var settingsWindowController: SettingsWindowController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Enable visual debugging if LB_DEBUG_UI is set
    NSView.swizzleDebugBehavior()

    logger.info("LlamaBarn starting up")

    // Configure app as menu bar only (removes from Dock)
    NSApp.setActivationPolicy(.accessory)

    // Initialize the shared model library manager to scan for existing models
    _ = ModelManager.shared

    // Create the AppKit-based status bar menu (installed models only for now)
    menuController = MenuController()

    // Initialize settings window controller (listens for LBShowSettings notifications)
    settingsWindowController = SettingsWindowController.shared

    // Start the server in Router Mode
    LlamaServer.shared.start()

    #if DEBUG
      // Auto-open menu in debug builds to save a click
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        self?.menuController?.openMenu()
      }
    #endif

    logger.info("LlamaBarn startup complete")
  }

  func applicationWillTerminate(_ notification: Notification) {
    logger.info("LlamaBarn shutting down")

    // Gracefully stop the llama-server process when app quits
    LlamaServer.shared.stop()
  }
}
