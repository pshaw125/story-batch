import SwiftUI
import AppKit
import StoryBatchCore

@MainActor
final class PromptFindModel: ObservableObject {
    @Published var visible = false
    @Published var query = "" { didSet { refresh(resetActive: true) } }
    @Published private(set) var matches: [NSRange] = []
    @Published private(set) var activeIndex: Int?
    @Published private(set) var focusRequest = UUID()
    private weak var editor: NSTextView?
    private var source = ""
    static let matchColor = NSColor.yellow.withAlphaComponent(0.22)
    static let activeColor = NSColor(calibratedRed: 1, green: 0.65, blue: 0.22, alpha: 0.48)
    var counter: String { matches.isEmpty ? (query.isEmpty ? "" : "No matches") : "\((activeIndex ?? 0) + 1) of \(matches.count)" }
    func attach(_ view: NSTextView) { editor = view; updateText(view.string) }
    func open() {
        visible = true; refresh(resetActive: false); focusRequest = UUID()
        editor?.window?.makeKeyAndOrderFront(nil)
    }
    func close() {
        visible = false; paint()
        if let editor { editor.window?.makeFirstResponder(editor) }
    }
    func updateText(_ text: String) { source = text; refresh(resetActive: false) }
    func move(by offset: Int) {
        if !visible { visible = true; refresh(resetActive: false) }
        guard !matches.isEmpty else { open(); return }
        let current = activeIndex ?? 0
        activeIndex = (current + (offset < 0 ? -1 : 1) + matches.count) % matches.count
        paint(); revealActive()
    }
    func activate(at location: Int) {
        guard visible, let index = matches.firstIndex(where: { NSLocationInRange(location, $0) }), index != activeIndex else { return }
        activeIndex = index; paint()
    }
    private func refresh(resetActive: Bool) {
        let text = source as NSString
        var ranges: [NSRange] = []
        if !query.isEmpty {
            var remaining = NSRange(location: 0, length: text.length)
            while remaining.length > 0 {
                let range = text.range(of: query, options: [.caseInsensitive], range: remaining)
                guard range.location != NSNotFound, range.length > 0 else { break }
                ranges.append(range)
                remaining = NSRange(location: NSMaxRange(range), length: text.length - NSMaxRange(range))
            }
        }
        matches = ranges
        activeIndex = ranges.isEmpty ? nil : (resetActive ? 0 : min(activeIndex ?? 0, ranges.count - 1))
        paint()
        if visible && resetActive { revealActive() }
    }
    private func paint() {
        guard let editor, let layout = editor.layoutManager else { return }
        layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: (editor.string as NSString).length))
        guard visible else { return }
        for (index, range) in matches.enumerated() {
            layout.addTemporaryAttribute(.backgroundColor, value: index == activeIndex ? Self.activeColor : Self.matchColor, forCharacterRange: range)
        }
    }
    private func revealActive() {
        guard let index = activeIndex, matches.indices.contains(index) else { return }
        editor?.scrollRangeToVisible(matches[index])
    }
}

struct PlainPromptEditor: NSViewRepresentable {
    @Binding var text: String
    let find: PromptFindModel
    @Environment(\.isEnabled) private var enabled
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .noBorder
        let view = NSTextView(); view.isRichText = false; view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false; view.isAutomaticTextReplacementEnabled = false
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false; view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true; view.textContainerInset = NSSize(width: 12, height: 14)
        view.string = text; view.delegate = context.coordinator
        DispatchQueue.main.async { [weak view, find] in if let view { find.attach(view) } }
        view.setAccessibilityIdentifier("metapromptEditor"); view.setAccessibilityLabel("Metaprompt editor")
        scroll.documentView = view; return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        if let view = scroll.documentView as? NSTextView {
            view.isEditable = enabled
            if view.string != text {
                view.string = text
                view.undoManager?.removeAllActions()
                DispatchQueue.main.async { [weak view, find] in if let view { find.updateText(view.string) } }
            }
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainPromptEditor
        init(_ parent: PlainPromptEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let view = notification.object as? NSTextView { parent.find.updateText(view.string); parent.text = view.string }
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            if let view = notification.object as? NSTextView { parent.find.activate(at: view.selectedRange().location) }
        }
    }
}

@MainActor
final class FieldsEditorWindow: NSWindow {
    weak var find: PromptFindModel?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if event.type == .keyDown, modifiers.contains(.command),
           !modifiers.contains(.option), !modifiers.contains(.control) {
            if event.charactersIgnoringModifiers?.lowercased() == "f", !modifiers.contains(.shift) {
                find?.open(); return true
            }
            if event.charactersIgnoringModifiers?.lowercased() == "g" {
                find?.move(by: modifiers.contains(.shift) ? -1 : 1); return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

struct FieldsEditor: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var find: PromptFindModel
    @FocusState private var findFocused: Bool
    init(model: AppModel) { self.model = model; self.find = model.fieldsFind }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Prompt Fields").font(.title2.weight(.semibold))
                Spacer()
                Button("Extract Choices from Prompt") { model.extractChoices() }.disabled(model.parameters == nil)
            }
            Text("[NAME] shares one fully resolved value throughout an image. [NAME*] resolves fresh each time. Both draw new values for the next image.").font(.callout)
            Text("COLOR={red|green:::2}\nEXPRESSION={smiling|thoughtful|looking at a {book|cup}}\nDESCRIPTION=She is [EXPRESSION] and wears a [COLOR] blouse.")
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            if find.visible {
                HStack {
                    TextField("Find in fields", text: $find.query).textFieldStyle(.roundedBorder).focused($findFocused)
                        .onSubmit { find.move(by: 1) }.onExitCommand { find.close() }
                        .onAppear { findFocused = true }
                    Text(find.counter).font(.caption).foregroundStyle(.secondary)
                    Button("↑") { find.move(by: -1) }.disabled(find.matches.isEmpty)
                    Button("↓") { find.move(by: 1) }.disabled(find.matches.isEmpty)
                    Button("Close Find") { find.close() }
                }
            }
            PlainPromptEditor(text: Binding(get: { model.fieldText }, set: { model.fieldText = $0 }), find: find)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
            Text("Start each NAME= definition at the left margin. Values may continue over multiple lines and contain weighted choices or other fields. Edits affect the next round and keep the current batch live.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = model.validationError { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled).lineLimit(4) }
        }.padding(20).frame(minWidth: 580, minHeight: 480)
            .onChange(of: find.focusRequest) { _ in findFocused = true }
    }
}
