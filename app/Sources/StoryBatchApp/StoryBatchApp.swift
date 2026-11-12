import SwiftUI
import AppKit
import StoryBatchCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.isRunning else { return .terminateNow }
        let alert = NSAlert(); alert.messageText = "A batch is still running"; alert.informativeText = "Stop the current image and save the batch report before quitting? Completed images will be kept."
        alert.addButton(withTitle: "Keep Running"); alert.addButton(withTitle: "Stop and Quit")
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        model.stop()
        Task { @MainActor in
            while model.isRunning { try? await Task.sleep(nanoseconds: 100_000_000) }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

#if !STORYBATCH_MODEL_TESTS
@main
@MainActor
struct StoryBatchApplication: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup("Story Batch") {
            ContentView(model: model).onAppear { delegate.model = model }
        }
        .defaultSize(width: 1160, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Metaprompt") { model.newDocument() }.keyboardShortcut("n").disabled(model.isRunning)
                Button("Open Metaprompt…") { model.openDocument() }.keyboardShortcut("o").disabled(model.isRunning)
                Button("Open Batch…") { model.openBatch() }.keyboardShortcut("o", modifiers: [.command, .shift]).disabled(model.isRunning)
                Button("Save Metaprompt…") { model.saveDocument() }.keyboardShortcut("s")
            }
            CommandGroup(replacing: .appSettings) { Button("Settings…") { model.showSettings = true }.keyboardShortcut(",") }
            CommandGroup(after: .textEditing) {
                Button("Find in Prompt…") { model.find.open() }.keyboardShortcut("f")
                Button("Find Next") { model.find.move(by: 1) }.keyboardShortcut("g")
                Button("Find Previous") { model.find.move(by: -1) }.keyboardShortcut("g", modifiers: [.command, .shift])
            }
        }
    }
}
#endif
