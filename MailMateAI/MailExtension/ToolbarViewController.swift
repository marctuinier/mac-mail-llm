import MailKit
import AppKit
import Security

private extension NSFont {
    var italic: NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}

/// The compose extension panel shown inside Mail.app.
/// Thin UI layer — all generation state lives in GenerationManager (singleton).
class ToolbarViewController: MEExtensionViewController {

    /// The compose session passed from ComposeSessionHandler.
    var composeSession: MEComposeSession? {
        didSet { GenerationManager.shared.composeSession = composeSession }
    }

    private var savedPrompts: [(name: String, instruction: String, id: String, links: [(label: String, url: String)], signature: String?)] = []
    private var manager: GenerationManager { GenerationManager.shared }
    private var heightConstraint: NSLayoutConstraint?

    // MARK: - UI Elements

    private lazy var scrollView: NSScrollView = {
        let sv = NSScrollView()
        sv.hasVerticalScroller = true
        sv.autohidesScrollers = true
        sv.borderType = .noBorder
        sv.drawsBackground = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private lazy var contentStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        return stack
    }()

    // MARK: - View Lifecycle

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 100))
        container.translatesAutoresizingMaskIntoConstraints = false
        self.view = container
        self.preferredContentSize = NSSize(width: 320, height: 100)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let hc = view.heightAnchor.constraint(equalToConstant: 100)
        heightConstraint = hc
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 320),
            hc,
        ])

        view.addSubview(scrollView)
        scrollView.documentView = contentStack

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        loadData()
        renderFromState()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // Restore compose session reference if we have one
        if let session = composeSession {
            manager.composeSession = session
        }
        refreshEmailContext()
        loadData()

        // Restore UI based on current manager state
        if manager.state == .generating {
            renderGeneratingState()
            manager.geminiClient.onThinking = { [weak self] thinking in
                DispatchQueue.main.async { self?.updateThinkingPreview(thinking) }
            }
            manager.geminiClient.onToken = { [weak self] partial in
                DispatchQueue.main.async { self?.updateLivePreview(partial) }
            }
            pollForCompletion()
        } else {
            renderFromState()
        }
    }

    // MARK: - State-driven Rendering

    private func renderFromState() {
        switch manager.state {
        case .idle:
            renderIdleState()
        case .generating:
            renderGeneratingState()
        case .preview(let html):
            renderPreviewState(html: html)
        case .error(let message):
            showError(message)
        }
    }

    // MARK: - Email Context

    private func refreshEmailContext() {
        guard let session = composeSession else { return }
        let composeMsg = session.mailMessage
        let context = session.composeContext
        let originalMsg = context.originalMessage

        let subject = composeMsg.subject
        let recipients = composeMsg.allRecipientAddresses.compactMap { $0.addressString }
        let fromAddress = composeMsg.fromAddress.addressString ?? ""

        var bodyText = ""
        var bodyHTML: String? = nil
        var originalFrom = ""

        if let origMsg = originalMsg {
            originalFrom = origMsg.fromAddress.addressString ?? ""
            if let rawData = origMsg.rawData {
                let parsed = parseMIMEBody(from: rawData)
                bodyText = parsed.plainText
                bodyHTML = parsed.html
            }
        }

        if bodyText.isEmpty, let rawData = composeMsg.rawData {
            let parsed = parseMIMEBody(from: rawData)
            bodyText = parsed.plainText
            if bodyHTML == nil { bodyHTML = parsed.html }
        }

        // If MIME parsing found HTML but no plain text, convert HTML to text
        if bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let html = bodyHTML, !html.isEmpty {
            bodyText = html
                .replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
                .replacingOccurrences(of: "</p>", with: "\n\n")
                .replacingOccurrences(of: "</div>", with: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let isReply = context.action == .reply || context.action == .replyAll || context.action == .forward

        manager.emailContext = [
            "subject": subject,
            "fromAddress": fromAddress,
            "recipientAddresses": recipients,
            "bodyText": bodyText,
            "bodyHTML": bodyHTML as Any,
            "isReply": isReply,
            "originalFrom": originalFrom,
        ]

        FlowLogger.log(step: "extraction", data: [
            "subject": subject,
            "fromAddress": fromAddress,
            "originalFrom": originalFrom,
            "recipients": recipients,
            "isReply": isReply,
            "bodyText_length": bodyText.count,
            "bodyText": bodyText,
            "bodyHTML_length": bodyHTML?.count ?? 0,
            "hadPlainText": bodyText.count > 0 && bodyHTML != nil,
            "usedHTMLFallback": bodyText.count > 0 && bodyHTML != nil && originalMsg?.rawData != nil,
        ])

        let model = EmailContextModel(
            subject: subject, fromAddress: fromAddress,
            recipientAddresses: recipients, bodyText: bodyText,
            bodyHTML: bodyHTML, dateReceived: nil, isReply: isReply, timestamp: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(model) {
            try? data.write(to: AppGroupConstants.emailContextFileURL)
        }
    }

    // MARK: - MIME Parsing

    private func parseMIMEBody(from data: Data) -> (plainText: String, html: String?) {
        guard let rawString = String(data: data, encoding: .utf8) else { return ("", nil) }
        if let boundaryRange = rawString.range(of: "boundary=\""),
           let boundaryEnd = rawString[boundaryRange.upperBound...].range(of: "\"") {
            let boundary = String(rawString[boundaryRange.upperBound..<boundaryEnd.lowerBound])
            return parseMultipart(rawString, boundary: boundary)
        }
        if let boundaryRange = rawString.range(of: "boundary=") {
            let afterBoundary = rawString[boundaryRange.upperBound...]
            var endIdx = afterBoundary.endIndex
            if let crlfEnd = afterBoundary.range(of: "\r\n") { endIdx = crlfEnd.lowerBound }
            else if let lfEnd = afterBoundary.range(of: "\n") { endIdx = lfEnd.lowerBound }
            let boundary = String(afterBoundary[..<endIdx])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return parseMultipart(rawString, boundary: boundary)
        }
        if let headerEnd = rawString.range(of: "\r\n\r\n") ?? rawString.range(of: "\n\n") {
            let body = String(rawString[headerEnd.upperBound...])
            return (body.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }
        return (rawString, nil)
    }

    private func parseMultipart(_ raw: String, boundary: String) -> (plainText: String, html: String?) {
        let parts = raw.components(separatedBy: "--\(boundary)")
        var plainText = ""; var html: String? = nil
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "--" || trimmed.isEmpty { continue }
            guard let headerEnd = trimmed.range(of: "\r\n\r\n") ?? trimmed.range(of: "\n\n") else { continue }
            let headers = String(trimmed[..<headerEnd.lowerBound]).lowercased()
            let body = String(trimmed[headerEnd.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if headers.contains("multipart/") {
                if let nb = headers.range(of: "boundary=\""), let ne = headers[nb.upperBound...].range(of: "\"") {
                    let nested = parseMultipart(String(trimmed[headerEnd.upperBound...]), boundary: String(headers[nb.upperBound..<ne.lowerBound]))
                    if !nested.plainText.isEmpty { plainText = nested.plainText }
                    if nested.html != nil { html = nested.html }
                }
                continue
            }
            if headers.contains("text/plain") {
                if headers.contains("base64") {
                    plainText = decodeBase64(body)
                } else if headers.contains("quoted-printable") {
                    plainText = decodeQuotedPrintable(body)
                } else {
                    plainText = body
                }
            } else if headers.contains("text/html") {
                if headers.contains("base64") {
                    html = decodeBase64(body)
                } else if headers.contains("quoted-printable") {
                    html = decodeQuotedPrintable(body)
                } else {
                    html = body
                }
            }
        }
        return (plainText, html)
    }

    private func decodeQuotedPrintable(_ input: String) -> String {
        var result = input
        result = result.replacingOccurrences(of: "=\r\n", with: "")
        result = result.replacingOccurrences(of: "=\n", with: "")
        let pattern = "=([0-9A-Fa-f]{2})"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsString = result as NSString
            var output = ""; var lastEnd = 0
            for match in regex.matches(in: result, range: NSRange(location: 0, length: nsString.length)) {
                output += nsString.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
                let hex = nsString.substring(with: match.range(at: 1))
                if let byte = UInt8(hex, radix: 16) { output += String(UnicodeScalar(byte)) }
                lastEnd = match.range.location + match.range.length
            }
            output += nsString.substring(from: lastEnd)
            return output
        }
        return result
    }

    private func decodeBase64(_ input: String) -> String {
        let cleaned = input
            .replacingOccurrences(of: "\r\n", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: cleaned),
              let decoded = String(data: data, encoding: .utf8) else {
            return input
        }
        return decoded
    }

    // MARK: - Data Loading

    private func loadData() {
        if manager.emailContext.isEmpty {
            if let data = try? Data(contentsOf: AppGroupConstants.emailContextFileURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                manager.emailContext = json
            }
        }

        savedPrompts = []
        if let data = try? Data(contentsOf: AppGroupConstants.savedPromptsFileURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for item in json {
                let links: [(label: String, url: String)] = (item["links"] as? [[String: Any]] ?? []).compactMap {
                    guard let label = $0["label"] as? String, let url = $0["url"] as? String else { return nil }
                    return (label, url)
                }
                savedPrompts.append((
                    name: item["name"] as? String ?? "Untitled",
                    instruction: item["instruction"] as? String ?? "",
                    id: item["id"] as? String ?? UUID().uuidString,
                    links: links,
                    signature: item["signature"] as? String
                ))
            }
        }
    }

    private func retrieveAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.mailmate.ai",
            kSecAttrAccount as String: AppGroupConstants.apiKeyKeychainAccount,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Clear & Rebuild

    private func clearContent() {
        for v in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
    }

    private func resizeToFitContent() {
        contentStack.layoutSubtreeIfNeeded()
        let fittingHeight = contentStack.fittingSize.height
        let clamped = min(max(fittingHeight, 80), 400)
        heightConstraint?.constant = clamped
        self.preferredContentSize = NSSize(width: 320, height: clamped)
    }

    private func forceLabelColor(on attrStr: NSAttributedString) -> NSMutableAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attrStr)
        mutable.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: mutable.length))
        mutable.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: mutable.length))
        return mutable
    }

    // MARK: - Idle State

    private func renderIdleState() {
        clearContent()

        let header = makeLabel("MailMate AI", size: 13, weight: .bold)
        let gearBtn = NSButton(image: NSImage(systemSymbolName: "gear", accessibilityDescription: nil)!, target: self, action: #selector(openSettings))
        gearBtn.bezelStyle = .inline; gearBtn.isBordered = false; gearBtn.toolTip = "Open Settings"
        let headerRow = NSStackView(views: [header, NSView(), gearBtn])
        headerRow.orientation = .horizontal; headerRow.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(headerRow)
        headerRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -8).isActive = true

        let field = NSTextField()
        field.placeholderString = "What would you like to draft?"
        field.font = .systemFont(ofSize: 12); field.bezelStyle = .roundedBezel
        field.translatesAutoresizingMaskIntoConstraints = false
        field.cell?.wraps = true; field.cell?.isScrollable = true
        field.usesSingleLineMode = false; field.lineBreakMode = .byWordWrapping
        field.identifier = NSUserInterfaceItemIdentifier("promptField")
        field.target = self; field.action = #selector(promptFieldSubmitted(_:))
        contentStack.addArrangedSubview(field)
        field.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -8).isActive = true
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 22).isActive = true

        let generateBtn = NSButton(title: "Generate", target: self, action: #selector(generateFromField))
        generateBtn.bezelStyle = .rounded; generateBtn.controlSize = .regular
        generateBtn.font = .systemFont(ofSize: 12, weight: .medium)
        generateBtn.contentTintColor = .controlAccentColor
        if let img = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil) {
            generateBtn.image = img; generateBtn.imagePosition = .imageLeading
        }
        generateBtn.identifier = NSUserInterfaceItemIdentifier("generateBtn")
        contentStack.addArrangedSubview(generateBtn)

        let divider = NSBox(); divider.boxType = .separator; divider.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(divider)
        divider.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -8).isActive = true

        let promptsLabel = makeLabel("Saved Prompts", size: 11, weight: .medium, color: .secondaryLabelColor)
        contentStack.addArrangedSubview(promptsLabel)

        if savedPrompts.isEmpty {
            let empty = makeLabel("No saved prompts yet. Add some in the MailMate AI app.", size: 11, color: .tertiaryLabelColor)
            contentStack.addArrangedSubview(empty)
            empty.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -8).isActive = true
        } else {
            let promptListStack = NSStackView()
            promptListStack.orientation = .vertical; promptListStack.alignment = .leading; promptListStack.spacing = 3
            promptListStack.translatesAutoresizingMaskIntoConstraints = false
            for (i, prompt) in savedPrompts.enumerated() {
                let row = makeCompactPromptRow(prompt.name, index: i)
                promptListStack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: promptListStack.widthAnchor).isActive = true
            }
            let promptScroll = NSScrollView()
            promptScroll.hasVerticalScroller = true; promptScroll.autohidesScrollers = true
            promptScroll.borderType = .noBorder; promptScroll.drawsBackground = false
            promptScroll.translatesAutoresizingMaskIntoConstraints = false
            promptScroll.documentView = promptListStack
            contentStack.addArrangedSubview(promptScroll)
            promptScroll.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -8).isActive = true
            let maxH = min(CGFloat(savedPrompts.count) * 31, 130)
            promptScroll.heightAnchor.constraint(equalToConstant: maxH).isActive = true
            promptListStack.widthAnchor.constraint(equalTo: promptScroll.widthAnchor).isActive = true
        }

        resizeToFitContent()
    }

    // MARK: - Generating State

    private func renderGeneratingState() {
        clearContent()
        hasTransitionedToEmail = false

        // Phase label at top
        let phaseLabel = makeLabel("💭 Thinking...", size: 11, weight: .medium, color: .secondaryLabelColor)
        phaseLabel.identifier = NSUserInterfaceItemIdentifier("phaseLabel")
        contentStack.addArrangedSubview(phaseLabel)

        // Single full-panel text view used for both thinking and email
        let streamText = NSTextView()
        streamText.isEditable = false; streamText.isSelectable = true
        streamText.drawsBackground = false
        streamText.font = NSFont.systemFont(ofSize: 11).italic
        streamText.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.85)
        streamText.identifier = NSUserInterfaceItemIdentifier("livePreview")
        streamText.textContainerInset = NSSize(width: 6, height: 6)
        streamText.isVerticallyResizable = true
        streamText.isHorizontallyResizable = false
        streamText.autoresizingMask = [.width]
        streamText.textContainer?.widthTracksTextView = true
        streamText.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        streamText.frame = NSRect(x: 0, y: 0, width: 312, height: 0)

        let streamScroll = NSScrollView()
        streamScroll.hasVerticalScroller = true; streamScroll.autohidesScrollers = true
        streamScroll.borderType = .noBorder; streamScroll.drawsBackground = false
        streamScroll.translatesAutoresizingMaskIntoConstraints = false
        streamScroll.documentView = streamText

        contentStack.addArrangedSubview(streamScroll)
        streamScroll.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -8).isActive = true
        streamScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true

        if !manager.streamingText.isEmpty {
            updateLivePreview(manager.streamingText)
        }

        resizeToFitContent()
    }

    // MARK: - Preview State

    private func renderPreviewState(html: String) {
        clearContent()

        let previewHeader = makeLabel("Preview", size: 12, weight: .bold)
        contentStack.addArrangedSubview(previewHeader)

        let textView = NSTextView()
        textView.isEditable = false; textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.font = .systemFont(ofSize: 11)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        if let htmlData = html.data(using: .utf8),
           let attrStr = try? NSAttributedString(
               data: htmlData,
               options: [.documentType: NSAttributedString.DocumentType.html,
                         .characterEncoding: String.Encoding.utf8.rawValue],
               documentAttributes: nil
           ) {
            textView.textStorage?.setAttributedString(forceLabelColor(on: attrStr))
        } else {
            textView.string = html
        }
        textView.textColor = .labelColor

        let previewScroll = NSScrollView()
        previewScroll.hasVerticalScroller = true; previewScroll.autohidesScrollers = true
        previewScroll.borderType = .noBorder; previewScroll.drawsBackground = false
        previewScroll.translatesAutoresizingMaskIntoConstraints = false
        previewScroll.documentView = textView
        previewScroll.wantsLayer = true; previewScroll.layer?.cornerRadius = 4
        previewScroll.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.25).cgColor

        contentStack.addArrangedSubview(previewScroll)
        previewScroll.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -8).isActive = true
        previewScroll.heightAnchor.constraint(equalToConstant: 140).isActive = true
        textView.frame = NSRect(x: 0, y: 0, width: 308, height: 0)
        textView.sizeToFit()

        // Refine section: label + text field + button in a row
        let refineLabel = makeLabel("Is there anything you want me to change?", size: 11, weight: .medium, color: .secondaryLabelColor)
        contentStack.addArrangedSubview(refineLabel)

        let refineField = NSTextField()
        refineField.placeholderString = "e.g. Make it shorter, add a deadline note..."
        refineField.font = .systemFont(ofSize: 11); refineField.bezelStyle = .roundedBezel
        refineField.translatesAutoresizingMaskIntoConstraints = false; refineField.usesSingleLineMode = true
        refineField.identifier = NSUserInterfaceItemIdentifier("refineField")
        // Do NOT set action — Enter in NSTextField inside a popover can dismiss it.
        // Instead we use a dedicated button.

        let refineBtn = NSButton(title: "Refine", target: self, action: #selector(refineButtonClicked))
        refineBtn.bezelStyle = .rounded; refineBtn.controlSize = .small
        refineBtn.font = .systemFont(ofSize: 11, weight: .medium)
        refineBtn.contentTintColor = .controlAccentColor
        if let img = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil) {
            refineBtn.image = img; refineBtn.imagePosition = .imageLeading
        }
        refineBtn.identifier = NSUserInterfaceItemIdentifier("refineBtn")

        let refineRow = NSStackView(views: [refineField, refineBtn])
        refineRow.orientation = .horizontal; refineRow.spacing = 6
        refineRow.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(refineRow)
        refineRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -8).isActive = true
        refineField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        refineBtn.setContentHuggingPriority(.required, for: .horizontal)
        refineBtn.setContentCompressionResistancePriority(.required, for: .horizontal)

        let insertBtn = NSButton(title: " Insert into Email", target: self, action: #selector(insertIntoEmail))
        insertBtn.bezelStyle = .rounded; insertBtn.controlSize = .regular
        insertBtn.contentTintColor = .controlAccentColor; insertBtn.font = .systemFont(ofSize: 12, weight: .medium)
        if let img = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil) {
            insertBtn.image = img; insertBtn.imagePosition = .imageLeading
        }
        let startOverBtn = NSButton(title: "Start Over", target: self, action: #selector(startOver))
        startOverBtn.bezelStyle = .rounded; startOverBtn.controlSize = .small; startOverBtn.font = .systemFont(ofSize: 11)

        let btnRow = NSStackView(views: [startOverBtn, NSView(), insertBtn])
        btnRow.orientation = .horizontal; btnRow.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(btnRow)
        btnRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -8).isActive = true

        resizeToFitContent()
    }

    // MARK: - Live Preview Update

    /// Tracks whether we've transitioned from thinking to email writing
    private var hasTransitionedToEmail = false

    private func updateThinkingPreview(_ thinking: String) {
        guard !hasTransitionedToEmail,
              let textView = findView(withId: "livePreview") as? NSTextView else { return }

        let cleaned = thinking
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        textView.font = NSFont.systemFont(ofSize: 11).italic
        textView.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.85)
        textView.string = cleaned
        textView.scrollToEndOfDocument(nil)

        if let phaseLabel = findView(withId: "phaseLabel") as? NSTextField {
            phaseLabel.stringValue = "💭 Reasoning..."
        }
    }

    private func updateLivePreview(_ partial: String) {
        guard let textView = findView(withId: "livePreview") as? NSTextView else { return }

        var clean = partial
        if clean.hasPrefix("```") {
            if let nl = clean.firstIndex(of: "\n") { clean = String(clean[clean.index(after: nl)...]) }
        }
        if clean.hasSuffix("```") { clean = String(clean.dropLast(3)) }
        let plain = clean
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !plain.isEmpty else { return }

        // Transition: switch from italic thinking to normal email text
        if !hasTransitionedToEmail {
            hasTransitionedToEmail = true
            textView.font = .systemFont(ofSize: 11)
            textView.textColor = .labelColor
            if let phaseLabel = findView(withId: "phaseLabel") as? NSTextField {
                phaseLabel.stringValue = "✍️ Writing..."
            }
        }

        textView.string = plain
        textView.scrollToEndOfDocument(nil)
    }

    // MARK: - Helpers

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color; label.maximumNumberOfLines = 0; label.lineBreakMode = .byWordWrapping
        return label
    }

    private func makeCompactPromptRow(_ name: String, index: Int) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true; container.layer?.cornerRadius = 6
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.4).cgColor
        container.identifier = NSUserInterfaceItemIdentifier("prompt_\(index)")

        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = .systemFont(ofSize: 12, weight: .medium); nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail; nameLabel.maximumNumberOfLines = 1
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let chevron = NSImageView()
        if let img = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) {
            chevron.image = img; chevron.contentTintColor = .tertiaryLabelColor
        }
        chevron.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(nameLabel); container.addSubview(chevron)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 28),
            nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -4),
            chevron.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            chevron.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 10),
        ])
        let click = NSClickGestureRecognizer(target: self, action: #selector(promptRowClicked(_:)))
        container.addGestureRecognizer(click)
        let track = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: ["view": container])
        container.addTrackingArea(track)
        return container
    }

    override func mouseEntered(with event: NSEvent) {
        if let v = (event.trackingArea?.userInfo as? [String: Any])?["view"] as? NSView {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.1; v.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor }
        }
    }

    override func mouseExited(with event: NSEvent) {
        if let v = (event.trackingArea?.userInfo as? [String: Any])?["view"] as? NSView {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.1; v.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.4).cgColor }
        }
    }

    // MARK: - Actions

    @objc private func promptFieldSubmitted(_ sender: NSTextField) {
        let text = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        generateWithInstruction(text, links: [], signature: nil)
    }

    @objc private func generateFromField() {
        guard let field = findView(withId: "promptField") as? NSTextField else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        generateWithInstruction(text, links: [], signature: nil)
    }

    @objc private func promptRowClicked(_ gesture: NSClickGestureRecognizer) {
        guard let id = gesture.view?.identifier?.rawValue, id.hasPrefix("prompt_"),
              let index = Int(id.replacingOccurrences(of: "prompt_", with: "")),
              index >= 0, index < savedPrompts.count else { return }
        let p = savedPrompts[index]
        generateWithInstruction(p.instruction, links: p.links, signature: p.signature)
    }

    @objc private func refineButtonClicked() {
        guard let refineField = findView(withId: "refineField") as? NSTextField else { return }
        let text = refineField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        refineField.stringValue = ""

        guard let apiKey = retrieveAPIKey(), !apiKey.isEmpty else {
            showError("No API key. Add your Gemini API key in the MailMate AI app.")
            return
        }
        let model = AppGroupConstants.sharedDefaults.string(forKey: AppGroupConstants.geminiModelKey) ?? "gemini-2.5-pro"

        renderGeneratingState()

        manager.refine(
            apiKey: apiKey, model: model, instruction: text,
            onThinkingUpdate: { [weak self] thinking in
                DispatchQueue.main.async { self?.updateThinkingPreview(thinking) }
            }
        ) { [weak self] partial in
            DispatchQueue.main.async { self?.updateLivePreview(partial) }
        }

        // Poll for completion so we can transition to preview
        pollForCompletion()
    }

    @objc private func insertIntoEmail() {
        guard case .preview(let html) = manager.state else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let htmlData = html.data(using: .utf8),
           let attrStr = try? NSAttributedString(
               data: htmlData,
               options: [.documentType: NSAttributedString.DocumentType.html,
                         .characterEncoding: String.Encoding.utf8.rawValue],
               documentAttributes: nil
           ),
           let rtfData = try? attrStr.data(
               from: NSRange(location: 0, length: attrStr.length),
               documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
           ) {
            pasteboard.declareTypes([.html, .rtf, .string], owner: nil)
            pasteboard.setString(html, forType: .html)
            pasteboard.setData(rtfData, forType: .rtf)
            pasteboard.setString(attrStr.string, forType: .string)
        } else {
            pasteboard.declareTypes([.string], owner: nil)
            pasteboard.setString(html, forType: .string)
        }

        manager.reset()

        // Auto-paste: simulate Cmd+V after the popover dismisses and focus returns
        // to the compose body. We use a longer delay to let Mail restore focus.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.simulatePaste()
        }

        renderInsertedState()
    }

    /// Simulate Cmd+V keystroke to auto-paste clipboard into the compose body.
    /// Requires Accessibility permission for the process posting the events.
    private func simulatePaste() {
        guard AXIsProcessTrusted() else { return }

        let src = CGEventSource(stateID: CGEventSourceStateID.combinedSessionState)
        // Key down: Cmd+V (keycode 9 = V)
        if let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true) {
            keyDown.flags = CGEventFlags.maskCommand
            keyDown.post(tap: CGEventTapLocation.cghidEventTap)
        }
        // Brief pause between key-down and key-up for reliability
        usleep(50_000)
        // Key up
        if let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false) {
            keyUp.flags = CGEventFlags.maskCommand
            keyUp.post(tap: CGEventTapLocation.cghidEventTap)
        }
    }

    @objc private func startOver() {
        manager.reset()
        refreshEmailContext()
        renderIdleState()
    }

    @objc private func openSettings() {
        NSWorkspace.shared.open(URL(string: "mailmate-ai://settings")!)
    }

    // MARK: - Generation

    private func generateWithInstruction(_ instruction: String, links: [(label: String, url: String)], signature: String?) {
        guard let apiKey = retrieveAPIKey(), !apiKey.isEmpty else {
            showError("No API key. Add your Gemini API key in the MailMate AI app.")
            return
        }

        refreshEmailContext()

        let model = AppGroupConstants.sharedDefaults.string(forKey: AppGroupConstants.geminiModelKey) ?? "gemini-2.5-pro"
        let defaultSig = AppGroupConstants.sharedDefaults.string(forKey: AppGroupConstants.defaultSignatureKey) ?? ""
        let sig = signature ?? defaultSig

        var toneSamples: [(label: String, text: String)] = []
        if let data = try? Data(contentsOf: AppGroupConstants.toneSamplesFileURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for item in json {
                if let label = item["label"] as? String, let text = item["emailText"] as? String {
                    toneSamples.append((label, text))
                }
            }
        }

        renderGeneratingState()

        manager.generate(
            apiKey: apiKey, model: model,
            instruction: instruction, links: links,
            signature: sig, toneSamples: toneSamples,
            onThinkingUpdate: { [weak self] thinking in
                DispatchQueue.main.async { self?.updateThinkingPreview(thinking) }
            }
        ) { [weak self] partial in
            DispatchQueue.main.async { self?.updateLivePreview(partial) }
        }

        // Poll for completion so we can transition to preview state
        pollForCompletion()
    }

    /// Periodically checks if GenerationManager has finished, and transitions the UI.
    /// This survives even if the panel was dismissed and reopened, because
    /// viewWillAppear checks manager.state directly.
    private func pollForCompletion() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            switch self.manager.state {
            case .preview(let html):
                self.renderPreviewState(html: html)
            case .error(let msg):
                self.showError(msg)
            case .generating:
                self.pollForCompletion() // Keep polling
            case .idle:
                break // Was cancelled
            }
        }
    }

    // MARK: - Inserted Confirmation

    private func renderInsertedState() {
        clearContent()

        let hasAccessibility = AXIsProcessTrusted()

        let check = NSImageView()
        if let img = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil) {
            check.image = img; check.contentTintColor = .systemGreen
            check.translatesAutoresizingMaskIntoConstraints = false
            check.widthAnchor.constraint(equalToConstant: 32).isActive = true
            check.heightAnchor.constraint(equalToConstant: 32).isActive = true
        }

        let msg: NSTextField
        let sub: NSTextField
        if hasAccessibility {
            msg = makeLabel("Inserted into email!", size: 13, weight: .semibold)
            sub = makeLabel("The reply has been pasted into your compose body.", size: 11, color: .secondaryLabelColor)
        } else {
            msg = makeLabel("Copied to clipboard!", size: 13, weight: .semibold)
            sub = makeLabel("Press ⌘V in the compose body to paste.\nGrant Accessibility permission for auto-paste.", size: 11, color: .secondaryLabelColor)
        }
        msg.alignment = .center; sub.alignment = .center

        let vstack = NSStackView(views: [check, msg, sub])
        vstack.orientation = .vertical; vstack.alignment = .centerX; vstack.spacing = 6
        vstack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(vstack)
        vstack.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -8).isActive = true

        let newBtn = NSButton(title: "Start Over", target: self, action: #selector(startOver))
        newBtn.bezelStyle = .rounded; newBtn.controlSize = .small
        contentStack.addArrangedSubview(newBtn)

        resizeToFitContent()
    }

    // MARK: - Error Display

    private func showError(_ message: String) {
        clearContent()

        let icon = NSImageView()
        if let img = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil) {
            icon.image = img; icon.contentTintColor = .systemOrange
        }
        let label = makeLabel(message, size: 11, color: .secondaryLabelColor)
        let row = NSStackView(views: [icon, label])
        row.orientation = .horizontal; row.spacing = 6
        contentStack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -8).isActive = true

        // Show Retry if we have a previous request to replay
        if manager.lastRequest != nil {
            let retryBtn = NSButton(title: " Retry", target: self, action: #selector(retryLastRequest))
            retryBtn.bezelStyle = .rounded; retryBtn.controlSize = .regular
            retryBtn.font = .systemFont(ofSize: 12, weight: .medium)
            retryBtn.contentTintColor = .controlAccentColor
            if let img = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil) {
                retryBtn.image = img; retryBtn.imagePosition = .imageLeading
            }

            let backBtn = NSButton(title: "Start Over", target: self, action: #selector(startOver))
            backBtn.bezelStyle = .rounded; backBtn.controlSize = .small

            let btnRow = NSStackView(views: [retryBtn, NSView(), backBtn])
            btnRow.orientation = .horizontal
            btnRow.translatesAutoresizingMaskIntoConstraints = false
            contentStack.addArrangedSubview(btnRow)
            btnRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -8).isActive = true
        } else {
            let backBtn = NSButton(title: "Go Back", target: self, action: #selector(startOver))
            backBtn.bezelStyle = .rounded; backBtn.controlSize = .small
            contentStack.addArrangedSubview(backBtn)
        }

        resizeToFitContent()
    }

    @objc private func retryLastRequest() {
        guard let req = manager.lastRequest else { return }
        if req.isRefine {
            renderGeneratingState()
            manager.refine(
                apiKey: req.apiKey, model: req.model, instruction: req.instruction,
                onThinkingUpdate: { [weak self] thinking in
                    DispatchQueue.main.async { self?.updateThinkingPreview(thinking) }
                }
            ) { [weak self] partial in
                DispatchQueue.main.async { self?.updateLivePreview(partial) }
            }
            pollForCompletion()
        } else {
            renderGeneratingState()
            manager.generate(
                apiKey: req.apiKey, model: req.model,
                instruction: req.instruction, links: req.links,
                signature: req.signature, toneSamples: req.toneSamples,
                onThinkingUpdate: { [weak self] thinking in
                    DispatchQueue.main.async { self?.updateThinkingPreview(thinking) }
                }
            ) { [weak self] partial in
                DispatchQueue.main.async { self?.updateLivePreview(partial) }
            }
            pollForCompletion()
        }
    }

    // MARK: - Utility

    private func findView(withId id: String) -> NSView? {
        func search(_ view: NSView) -> NSView? {
            if view.identifier?.rawValue == id { return view }
            for sub in view.subviews { if let f = search(sub) { return f } }
            return nil
        }
        return search(view)
    }
}
