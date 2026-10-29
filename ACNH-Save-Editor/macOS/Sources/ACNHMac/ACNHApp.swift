import SwiftUI
import AppKit

@main struct ACNHApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = EditorModel()
    var body: some Scene {
        Window("ACNH Save Editor", id: "editor") {
            EditorView().environmentObject(model)
                .frame(minWidth: 1060, minHeight: 700)
                .onAppear {
                    delegate.model = model
                    if CommandLine.arguments.contains("--preview") { model.openDemo() }
                    if let index = CommandLine.arguments.firstIndex(of: "--open"), CommandLine.arguments.count > index + 1 {
                        model.open(URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true))
                    }
                }
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Save Folder…", action: model.chooseFolder).keyboardShortcut("o").disabled(model.busy)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Review & Save…") { model.reviewing = true }.keyboardShortcut("s").disabled(!model.hasChanges || model.busy)
                Button("Export Edited Copy…", action: model.export).keyboardShortcut("s", modifiers: [.command, .shift]).disabled(model.session == nil || model.busy)
                Divider()
                Button("Revert Draft", action: model.revert).disabled(!model.hasChanges || model.busy)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo Edit", action: model.undo).keyboardShortcut("z").disabled(!model.canUndo)
                Button("Redo Edit", action: model.redo).keyboardShortcut("z", modifiers: [.command, .shift]).disabled(model.future.isEmpty || model.busy)
            }
            CommandGroup(replacing: .help) {
                Button("Preparing & Importing Saves") { model.showGuide = true }
                Button("Original Project on GitHub") { NSWorkspace.shared.open(URL(string: "https://github.com/cbreezy210/ACNH-Save-Editor")!) }
                Button("Licenses & Credits") {
                    if let url = Bundle.module.url(forResource: "Credits", withExtension: "txt") { NSWorkspace.shared.open(url) }
                }
            }
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: EditorModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        return !model.busy && model.confirmDiscard() ? .terminateNow : .terminateCancel
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
