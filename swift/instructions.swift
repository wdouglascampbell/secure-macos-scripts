#!/usr/bin/swift
import Cocoa

// -------------------------------------------------------------
// Constants
// -------------------------------------------------------------
enum KeyCode {
    static let enter: UInt16 = 36
    static let esc: UInt16 = 53
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
}

guard CommandLine.arguments.count == 2 else {
    print("Usage: instructions.swift instructions.json")
    exit(1)
}

// -------------------------------------------------------------
// Script Helpers
// -------------------------------------------------------------
let instructionsDirectory = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("instructions")

func imageFromInstructionsDirectory(_ relativePath: String) -> NSImage? {
    let path = instructionsDirectory.appendingPathComponent(relativePath).path
    return NSImage(contentsOfFile: path)
}

// -------------------------------------------------------------
// NSStackView Helpers
// -------------------------------------------------------------
extension NSStackView {
    func clearArrangedSubviews() {
        for view in arrangedSubviews {
            removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }
    
    static func vertical(spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }
    
    static func horizontal(spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }
}

// -------------------------------------------------------------
// UI Helpers
// -------------------------------------------------------------
func makeWrappingLabel(_ text: String, maxWidth: CGFloat = 360) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = NSFont.systemFont(ofSize: 14)
    label.lineBreakMode = .byWordWrapping
    label.maximumNumberOfLines = 0
    label.translatesAutoresizingMaskIntoConstraints = false
    label.preferredMaxLayoutWidth = maxWidth
    NSLayoutConstraint.activate([
        label.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth)
    ])
    return label
}

func makeNumberedWrappingLabel(
    number: Int,
    text: String,
    maxWidth: CGFloat = 360
) -> NSTextField {

    let numberString = "\(number). "
    let fullText = numberString + text

    let label = NSTextField(labelWithString: "")
    label.font = NSFont.systemFont(ofSize: 14)
    label.lineBreakMode = .byWordWrapping
    label.maximumNumberOfLines = 0
    label.translatesAutoresizingMaskIntoConstraints = false
    label.preferredMaxLayoutWidth = maxWidth

    // Measure number width so indentation is exact
    let numberWidth = (numberString as NSString).size(
        withAttributes: [.font: label.font!]
    ).width

    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.firstLineHeadIndent = 0
    paragraphStyle.headIndent = numberWidth
    paragraphStyle.lineBreakMode = .byWordWrapping

    let attributed = NSMutableAttributedString(
        string: fullText,
        attributes: [
            .font: label.font!,
            .paragraphStyle: paragraphStyle
        ]
    )

    label.attributedStringValue = attributed

    NSLayoutConstraint.activate([
        label.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth)
    ])

    return label
}

func makeListItemView(index: inout Int, items: [InstructionItem], maxWidth: CGFloat = 360) -> NSView {
    let container = NSStackView.vertical(spacing: 6)
    
    for item in items {
        switch item {
        case .text(let text):
            let label = makeNumberedWrappingLabel(
                number: index,
                text: text,
                maxWidth: maxWidth
            )
            container.addArrangedSubview(label)
            index += 1
        case .image(let path, let scale):
            if let img = imageFromInstructionsDirectory(path) {
                let iv = NSImageView()
                iv.image = img
                iv.imageScaling = .scaleProportionallyUpOrDown
                iv.translatesAutoresizingMaskIntoConstraints = false
                let w = min(img.size.width * (scale ?? 1), maxWidth)
                NSLayoutConstraint.activate([
                    iv.widthAnchor.constraint(equalToConstant: w),
                    iv.heightAnchor.constraint(equalTo: iv.widthAnchor, multiplier: img.size.height / img.size.width)
                ])
                container.addArrangedSubview(iv)
            }
        case .images(let paths, let scale):
            let hStack = NSStackView.horizontal(spacing: 8)
            hStack.alignment = .top
            for path in paths {
                if let img = imageFromInstructionsDirectory(path) {
                    let iv = NSImageView()
                    iv.image = img
                    iv.imageScaling = .scaleProportionallyUpOrDown
                    iv.translatesAutoresizingMaskIntoConstraints = false
                    let w = min(img.size.width * (scale ?? 1), maxWidth / CGFloat(paths.count))
                    NSLayoutConstraint.activate([
                        iv.widthAnchor.constraint(equalToConstant: w),
                        iv.heightAnchor.constraint(equalTo: iv.widthAnchor, multiplier: img.size.height / img.size.width)
                    ])
                    hStack.addArrangedSubview(iv)
                }
            }
            container.addArrangedSubview(hStack)
        case .list(let subItems):
            container.addArrangedSubview(makeListItemView(index: &index, items: subItems, maxWidth: maxWidth))
        }
    }
    
    return container
}

func applyWindowSizeToFitContent(_ window: NSWindow, stack: NSStackView) {
    stack.layoutSubtreeIfNeeded()
    var contentSize = stack.fittingSize
    contentSize.width += 40
    contentSize.height += 40
    contentSize.width = max(400, contentSize.width)
    contentSize.height = min(600, contentSize.height)
    
    if let screen = NSScreen.main?.visibleFrame {
        let frame = window.frameRect(forContentRect: NSRect(origin: CGPoint(x: screen.minX, y: screen.maxY - contentSize.height), size: contentSize))
        window.setFrame(frame, display: true, animate: true)
    }
}

func scrollToTop(_ scrollView: NSScrollView) {
    guard let documentView = scrollView.documentView else { return }
    scrollView.layoutSubtreeIfNeeded()
    documentView.layoutSubtreeIfNeeded()
    let topPoint = NSPoint(x: 0, y: max(0, documentView.frame.height - scrollView.contentView.bounds.height))
    scrollView.contentView.scroll(to: topPoint)
    scrollView.reflectScrolledClipView(scrollView.contentView)
}

// -------------------------------------------------------------
// Wizard Data Models (JSON-driven)
// -------------------------------------------------------------
enum InstructionItem: Codable {
    case text(String)
    case image(path: String, scale: CGFloat?)
    case images(paths: [String], scale: CGFloat?)
    case list([InstructionItem])

    enum CodingKeys: String, CodingKey { case type, text, path, paths, scale, items }
    enum ItemType: String, Codable { case text, image, images, list }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ItemType.self, forKey: .type)
        switch type {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .image:
            self = .image(
                path: try container.decode(String.self, forKey: .path),
                scale: try container.decodeIfPresent(CGFloat.self, forKey: .scale)
            )
        case .images:
            self = .images(
                paths: try container.decode([String].self, forKey: .paths),
                scale: try container.decodeIfPresent(CGFloat.self, forKey: .scale)
            )
        case .list:
            self = .list(try container.decode([InstructionItem].self, forKey: .items))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let t): try c.encode(ItemType.text, forKey: .type); try c.encode(t, forKey: .text)
        case .image(let p, let s): try c.encode(ItemType.image, forKey: .type); try c.encode(p, forKey: .path); try c.encodeIfPresent(s, forKey: .scale)
        case .images(let p, let s): try c.encode(ItemType.images, forKey: .type); try c.encode(p, forKey: .paths); try c.encodeIfPresent(s, forKey: .scale)
        case .list(let i): try c.encode(ItemType.list, forKey: .type); try c.encode(i, forKey: .items)
        }
    }
}

struct OpenDefinition: Codable {
    enum OpenType: String, Codable { case application, url }
    let type: OpenType
    let bundleIdentifier: String?
    let url: String?
    let activate: Bool?
}

struct ButtonDefinition: Codable {
    let title: String
    let target: String?
    let `default`: Bool?
}

struct PageDefinition: Codable {
    let title: String
    let items: [InstructionItem]
    let buttons: [ButtonDefinition]?
    let onFinish: String?
    let open: OpenDefinition?
    let nextPage: String?
}

struct InstructionFile: Codable {
    let first: String
    let pages: [String: PageDefinition]
    let open: OpenDefinition?
}

// -------------------------------------------------------------
// Open Handler
// -------------------------------------------------------------
func handleOpenDefinition(_ open: OpenDefinition) {

    switch open.type {

    case .url:
        if let urlString = open.url,
           let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }

    case .application:
        guard let bundleID = open.bundleIdentifier else { return }

        if let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .first {

            if open.activate == true {
                running.activate()
            }

        } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {

            let config = NSWorkspace.OpenConfiguration()
            config.activates = open.activate == true

            NSWorkspace.shared.openApplication(at: appURL, configuration: config)
        }
    }
}

// -------------------------------------------------------------
// ActionButton
// -------------------------------------------------------------
class ActionButton: NSButton {
    var actionClosure: (() -> Void)?
    init(title: String, action: (() -> Void)? = nil) {
        self.actionClosure = action
        super.init(frame: .zero)
        self.title = title
        self.target = self
        self.action = #selector(buttonClicked)
        self.bezelStyle = .rounded
        self.translatesAutoresizingMaskIntoConstraints = false
    }
    @objc private func buttonClicked() { actionClosure?() }
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }
}

// -------------------------------------------------------------
// ButtonHandler
// -------------------------------------------------------------
class ButtonHandler: NSObject {
    let stack: NSStackView
    let window: NSWindow
    let scrollView: NSScrollView
    var currentPageKey: String?
    private var history: [String] = []
    var pages: [String: PageDefinition] = [:]

    init(stack: NSStackView, window: NSWindow, scrollView: NSScrollView, pages: [String: PageDefinition]) {
        self.stack = stack
        self.window = window
        self.scrollView = scrollView
        self.pages = pages
    }

    func showPage(key: String, addToHistory: Bool = true) {
        guard let page = pages[key] else { return }
        if addToHistory, let current = currentPageKey { history.append(current) }
        currentPageKey = key

        if let open = page.open { handleOpenDefinition(open) }

        stack.clearArrangedSubviews()

        let titleLabel = makeWrappingLabel(page.title)
        titleLabel.font = .boldSystemFont(ofSize: 16)
        stack.addArrangedSubview(titleLabel)

        var index = 1
        for item in page.items {
            stack.addArrangedSubview(makeListItemView(index: &index, items: [item]))
        }

        let buttonStack = NSStackView.horizontal(spacing: 10)
        var defaultButtonSet = false

        if !history.isEmpty {
            buttonStack.addArrangedSubview(ActionButton(title: "Back") { [weak self] in self?.goBack() })
        }

        if let buttons = page.buttons {
            for btnDef in buttons {
                let btn = ActionButton(title: btnDef.title) { [weak self] in
                    if let target = btnDef.target { self?.showPage(key: target) }
                }
                buttonStack.addArrangedSubview(btn)
                if btnDef.default == true && !defaultButtonSet {
                    window.defaultButtonCell = btn.cell as? NSButtonCell
                    defaultButtonSet = true
                }
            }
        }

        if let nextKey = page.nextPage {
            let nextBtn = ActionButton(title: "Next") { [weak self] in
                self?.showPage(key: nextKey)
            }
            buttonStack.addArrangedSubview(nextBtn)
        
            if !defaultButtonSet {
                window.defaultButtonCell = nextBtn.cell as? NSButtonCell
                defaultButtonSet = true
            }
        }

        if page.onFinish == "terminate" {
            let finishBtn = ActionButton(title: "Finish") { NSApp.terminate(nil) }
            buttonStack.addArrangedSubview(finishBtn)
            if !defaultButtonSet {
                window.defaultButtonCell = finishBtn.cell as? NSButtonCell
            }
        }

        stack.addArrangedSubview(buttonStack)
        applyWindowSizeToFitContent(window, stack: stack)
        DispatchQueue.main.async { scrollToTop(self.scrollView) }
    }

    func goBack() {
        guard let prevKey = history.popLast() else { return }
        showPage(key: prevKey, addToHistory: false)
    }
}

// -------------------------------------------------------------
// WizardWindow
// -------------------------------------------------------------
class WizardWindow: NSWindow {
    var handler: ButtonHandler?

    override func keyDown(with event: NSEvent) {
        guard let handler = handler else { super.keyDown(with: event); return }
        switch event.keyCode {
        case KeyCode.leftArrow:
            handler.goBack()
        case KeyCode.rightArrow:
            if let currentKey = handler.currentPageKey,
               let page = handler.pages[currentKey] {
                if let next = page.nextPage {
                    handler.showPage(key: next)
                } else if page.buttons?.count == 1, let target = page.buttons?.first?.target {
                    handler.showPage(key: target)
                }
            }
        case KeyCode.enter:
            // Trigger window.defaultButtonCell
            window.defaultButtonCell?.performClick(nil)
        case KeyCode.esc:
            NSApp.terminate(nil)
        default: super.keyDown(with: event)
        }
    }
}

// -------------------------------------------------------------
// Launch Window & ScrollView
// -------------------------------------------------------------
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let window = WizardWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
window.title = "Instructions"
window.level = .floating

let scrollView = NSScrollView()
scrollView.hasVerticalScroller = true
scrollView.hasHorizontalScroller = false
scrollView.autohidesScrollers = false
scrollView.scrollerStyle = .legacy
scrollView.borderType = .noBorder
scrollView.translatesAutoresizingMaskIntoConstraints = false
scrollView.drawsBackground = false
scrollView.hasVerticalScroller = false
scrollView.contentView.postsBoundsChangedNotifications = true
window.contentView = scrollView

NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: nil) { _ in
    let contentHeight = scrollView.documentView?.frame.height ?? 0
    let visibleHeight = scrollView.contentView.bounds.height
    scrollView.hasVerticalScroller = contentHeight > visibleHeight
}

let documentView = NSView()
documentView.translatesAutoresizingMaskIntoConstraints = false
scrollView.documentView = documentView

let stack = NSStackView.vertical(spacing: 20)
documentView.addSubview(stack)

NSLayoutConstraint.activate([
    stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 20),
    stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -20),
    stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 20),
    stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -20),
    documentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
])

// -------------------------------------------------------------
// Load JSON & Launch Wizard
// -------------------------------------------------------------
let jsonData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let instructionFile = try JSONDecoder().decode(InstructionFile.self, from: jsonData)

if let open = instructionFile.open { handleOpenDefinition(open) }

let handler = ButtonHandler(stack: stack, window: window, scrollView: scrollView, pages: instructionFile.pages)
window.handler = handler
handler.showPage(key: instructionFile.first)

window.makeKeyAndOrderFront(nil)
window.orderFrontRegardless()
DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
    NSApp.activate(ignoringOtherApps: true)
}   

app.run()

