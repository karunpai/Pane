import AppKit
import PaneCore

/// Panel metrics (padding 20, header 44, minimum 320×280),
/// scaled so cells stay roughly square for larger grids.
enum OverlayMetrics {
    static let headerHeight: CGFloat = 44
    static let padding: CGFloat = 20
    static let cornerRadius: CGFloat = 14
    static let minimumSize = NSSize(width: 320, height: 280)
    static let maximumGridExtent: CGFloat = 340
    static let maximumCellPitch: CGFloat = 44

    static func panelSize(rows: Int, columns: Int) -> NSSize {
        let rows = max(1, rows), columns = max(1, columns)
        let pitch = min(maximumCellPitch, maximumGridExtent / CGFloat(max(rows, columns)))
        let width = max(minimumSize.width, (pitch * CGFloat(columns) + padding * 2).rounded())
        let height = max(minimumSize.height, (headerHeight + pitch * CGFloat(rows) + padding).rounded())
        return NSSize(width: width, height: height)
    }
}

protocol OverlayContentViewDelegate: AnyObject {
    func overlayContentViewRequestedClose(_ view: OverlayContentView)
    func overlayContentViewRequestedSettings(_ view: OverlayContentView)
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
}

/// Root view of the overlay panel: a dark HUD card with a front side (header +
/// grid) and a back side (Grid Settings) that the gear button flips between.
final class OverlayContentView: NSView {
    weak var delegate: OverlayContentViewDelegate?
    let gridView = GridView(frame: .zero)
    private(set) var isShowingBack = false

    private let cardView = FlippedView()
    private let effectView = NSVisualEffectView()
    private let tintView = NSView()
    private let borderView = NSView()
    private let frontView = FlippedView()
    private let backView = OverlayBackView()
    private let appIconView = NSImageView()
    private let appNameLabel = NSTextField(labelWithString: "")
    private let backTitleLabel = NSTextField(labelWithString: "Grid Settings")
    private lazy var closeButton = OverlayIconButton(symbol: "xmark.circle.fill", pointSize: 17, label: "Close",
                                                     target: self, action: #selector(closeClicked))
    private lazy var gearButton = OverlayIconButton(symbol: "gearshape.fill", pointSize: 15, label: "Grid Settings",
                                                    target: self, action: #selector(gearClicked))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setUp()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func setUp() {
        cardView.wantsLayer = true
        cardView.autoresizingMask = [.width, .height]
        addSubview(cardView)

        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.maskImage = Self.roundedMask(radius: OverlayMetrics.cornerRadius)
        cardView.addSubview(effectView)

        // Deepen the HUD a little toward a dark translucent panel.
        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = NSColor(white: 0, alpha: 0.28).cgColor
        tintView.layer?.cornerRadius = OverlayMetrics.cornerRadius  // maskImage doesn't clip subviews
        effectView.addSubview(tintView)

        appIconView.imageScaling = .scaleProportionallyUpOrDown
        appNameLabel.font = .systemFont(ofSize: 18, weight: .medium)
        appNameLabel.textColor = .white
        appNameLabel.lineBreakMode = .byTruncatingTail
        appNameLabel.maximumNumberOfLines = 1
        backTitleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        backTitleLabel.textColor = .white
        backTitleLabel.alignment = .center

        frontView.addSubview(appIconView)
        frontView.addSubview(appNameLabel)
        frontView.addSubview(gridView)
        cardView.addSubview(frontView)

        backView.isHidden = true
        backView.addSubview(backTitleLabel)
        backView.onDone = { [weak self] in self?.setShowingBack(false, animated: true) }
        backView.onOpenSettings = { [weak self] in
            guard let self else { return }
            self.delegate?.overlayContentViewRequestedSettings(self)
        }
        cardView.addSubview(backView)

        cardView.addSubview(closeButton)
        cardView.addSubview(gearButton)

        // Hairline edge like the system HUD windows.
        borderView.wantsLayer = true
        borderView.layer?.cornerRadius = OverlayMetrics.cornerRadius
        borderView.layer?.borderWidth = 1
        borderView.layer?.borderColor = NSColor(white: 1, alpha: 0.14).cgColor
        cardView.addSubview(borderView)
    }

    func configure(appName: String?, icon: NSImage?) {
        appNameLabel.stringValue = appName ?? "No Window"
        appNameLabel.textColor = appName == nil ? NSColor(white: 1, alpha: 0.5) : .white
        appIconView.image = icon
        appIconView.isHidden = icon == nil
        needsLayout = true
    }

    func refreshSettings() { backView.refresh() }

    /// Offscreen renders can't sample the desktop for a behind-window blur, so
    /// snapshots use a flat translucent dark fill instead.
    func useFlatBackgroundForSnapshot() {
        effectView.isHidden = true
        let fill = NSView()
        fill.wantsLayer = true
        fill.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.72).cgColor
        fill.layer?.cornerRadius = OverlayMetrics.cornerRadius
        fill.autoresizingMask = [.width, .height]
        fill.frame = cardView.bounds
        cardView.addSubview(fill, positioned: .below, relativeTo: frontView)
    }

    override func layout() {
        super.layout()
        cardView.frame = bounds
        let bounds = cardView.bounds
        let header = OverlayMetrics.headerHeight, padding = OverlayMetrics.padding
        effectView.frame = bounds
        tintView.frame = effectView.bounds
        borderView.frame = bounds
        frontView.frame = bounds
        backView.frame = bounds

        let buttonSize: CGFloat = 24
        closeButton.frame = NSRect(x: 9, y: (header - buttonSize) / 2, width: buttonSize, height: buttonSize)
        gearButton.frame = NSRect(x: bounds.width - 9 - buttonSize, y: (header - buttonSize) / 2,
                                  width: buttonSize, height: buttonSize)

        let iconSize: CGFloat = 32
        var labelX = closeButton.frame.maxX + 8
        if !appIconView.isHidden {
            appIconView.frame = NSRect(x: labelX, y: (header - iconSize) / 2, width: iconSize, height: iconSize)
            labelX = appIconView.frame.maxX + 8
        }
        let labelHeight = appNameLabel.intrinsicContentSize.height
        appNameLabel.frame = NSRect(x: labelX, y: ((header - labelHeight) / 2).rounded(),
                                    width: max(0, gearButton.frame.minX - 8 - labelX), height: labelHeight)

        let titleHeight = backTitleLabel.intrinsicContentSize.height
        backTitleLabel.frame = NSRect(x: 40, y: ((header - titleHeight) / 2).rounded(),
                                      width: max(0, bounds.width - 80), height: titleHeight)

        gridView.frame = NSRect(x: padding, y: header, width: max(1, bounds.width - padding * 2),
                                height: max(1, bounds.height - header - padding))
        backView.contentFrame = NSRect(x: padding, y: header, width: max(1, bounds.width - padding * 2),
                                       height: max(1, bounds.height - header - padding))
    }

    // MARK: Flip

    func setShowingBack(_ showBack: Bool, animated: Bool) {
        guard showBack != isShowingBack else { return }
        isShowingBack = showBack
        let swapSides = { [weak self] in
            guard let self else { return }
            self.frontView.isHidden = showBack
            self.backView.isHidden = !showBack
            if showBack {
                self.backView.refresh()
                self.window?.makeFirstResponder(self.backView.initialResponder)
            } else {
                self.window?.makeFirstResponder(self.gridView)
            }
            self.gearButton.toolTip = showBack ? "Done" : "Grid Settings"
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard animated, !reduceMotion, AppPreferences.shared.animationsEnabled, let layer = cardView.layer else {
            swapSides()
            return
        }
        // Card flip around the vertical axis.
        let centerX = layer.bounds.width * (0.5 - layer.anchorPoint.x)
        func rotation(_ angle: CGFloat) -> CATransform3D {
            var perspective = CATransform3DIdentity
            perspective.m34 = -1 / 900
            let toCenter = CATransform3DMakeTranslation(-centerX, 0, 0)
            let back = CATransform3DMakeTranslation(centerX, 0, 0)
            return CATransform3DConcat(CATransform3DConcat(CATransform3DConcat(toCenter, CATransform3DMakeRotation(angle, 0, 1, 0)), perspective), back)
        }
        let half: CFTimeInterval = 0.14
        let direction: CGFloat = showBack ? 1 : -1
        let firstHalf = CABasicAnimation(keyPath: "transform")
        firstHalf.fromValue = NSValue(caTransform3D: rotation(0))
        firstHalf.toValue = NSValue(caTransform3D: rotation(direction * .pi / 2))
        firstHalf.duration = half
        firstHalf.timingFunction = CAMediaTimingFunction(name: .easeIn)
        firstHalf.fillMode = .forwards
        firstHalf.isRemovedOnCompletion = false
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            swapSides()
            guard let layer = self?.cardView.layer else { return }
            let secondHalf = CABasicAnimation(keyPath: "transform")
            secondHalf.fromValue = NSValue(caTransform3D: rotation(-direction * .pi / 2))
            secondHalf.toValue = NSValue(caTransform3D: rotation(0))
            secondHalf.duration = half
            secondHalf.timingFunction = CAMediaTimingFunction(name: .easeOut)
            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in self?.window?.invalidateShadow() }
            layer.removeAnimation(forKey: "flip")
            layer.add(secondHalf, forKey: "flip2")
            CATransaction.commit()
        }
        layer.add(firstHalf, forKey: "flip")
        CATransaction.commit()
    }

    /// Returns to the grid side without animation (used when the panel is reopened).
    func resetToFront() {
        cardView.layer?.removeAllAnimations()
        if isShowingBack { setShowingBack(false, animated: false) }
    }

    @objc private func closeClicked() { delegate?.overlayContentViewRequestedClose(self) }
    @objc private func gearClicked() { setShowingBack(!isShowingBack, animated: true) }

    override func cancelOperation(_ sender: Any?) {
        if isShowingBack { setShowingBack(false, animated: true) } else { delegate?.overlayContentViewRequestedClose(self) }
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Back side of the card: "Grid Settings".
final class OverlayBackView: NSView {
    var onDone: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var contentFrame: NSRect = .zero { didSet { needsLayout = true } }

    private let container = NSView()
    private let rowsField = NSTextField()
    private let columnsField = NSTextField()
    private let rowsStepper = NSStepper()
    private let columnsStepper = NSStepper()
    private lazy var defaultCheckbox = NSButton(checkboxWithTitle: "Use these settings on activation",
                                                target: self, action: #selector(defaultToggled))
    private lazy var doneButton = NSButton(title: "Done", target: self, action: #selector(doneClicked))
    private lazy var settingsButton = NSButton(title: "Settings…", target: self, action: #selector(settingsClicked))

    var initialResponder: NSView { rowsField }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setUp() {
        let formatter = NumberFormatter()
        formatter.minimum = 1
        formatter.maximum = 10
        formatter.allowsFloats = false
        for (field, stepper) in [(rowsField, rowsStepper), (columnsField, columnsStepper)] {
            field.formatter = formatter
            field.alignment = .center
            field.target = self
            field.action = #selector(fieldChanged(_:))
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 44).isActive = true
            stepper.minValue = 1
            stepper.maxValue = 10
            stepper.increment = 1
            stepper.valueWraps = false
            stepper.target = self
            stepper.action = #selector(stepperChanged(_:))
        }

        let rowsLabel = Self.label("Number of Rows:")
        let columnsLabel = Self.label("Number of Columns:")
        func valueControl(_ field: NSTextField, _ stepper: NSStepper) -> NSStackView {
            let stack = NSStackView(views: [field, stepper])
            stack.orientation = .horizontal
            stack.spacing = 2
            return stack
        }
        let grid = NSGridView(views: [
            [rowsLabel, valueControl(rowsField, rowsStepper)],
            [columnsLabel, valueControl(columnsField, columnsStepper)]
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.rowAlignment = .none
        grid.yPlacement = .center

        defaultCheckbox.font = .systemFont(ofSize: NSFont.systemFontSize)

        settingsButton.isBordered = false
        settingsButton.contentTintColor = .controlAccentColor
        settingsButton.attributedTitle = NSAttributedString(string: "Settings…", attributes: [
            .foregroundColor: NSColor.controlAccentColor,
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
        ])
        settingsButton.toolTip = "Open Pane Settings"
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.controlSize = .regular

        let buttonRow = NSStackView(views: [settingsButton, NSView(), doneButton])
        buttonRow.orientation = .horizontal
        buttonRow.distribution = .fill

        let stack = NSStackView(views: [grid, defaultCheckbox])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16

        container.translatesAutoresizingMaskIntoConstraints = true
        addSubview(container)
        for view in [stack, buttonRow] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -16),
            buttonRow.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        refresh()
    }

    override func layout() {
        container.frame = contentFrame
        super.layout()
    }

    func refresh() {
        let prefs = AppPreferences.shared
        rowsField.integerValue = prefs.rows
        rowsStepper.integerValue = prefs.rows
        columnsField.integerValue = prefs.columns
        columnsStepper.integerValue = prefs.columns
        defaultCheckbox.state = prefs.useDefaultGrid ? .on : .off
    }

    private func apply(rows: Int? = nil, columns: Int? = nil) {
        let prefs = AppPreferences.shared
        if let rows { prefs.rows = rows }
        if let columns { prefs.columns = columns }
        if prefs.useDefaultGrid {
            prefs.defaultRows = prefs.rows
            prefs.defaultColumns = prefs.columns
        }
        refresh()
    }

    @objc private func stepperChanged(_ sender: NSStepper) {
        if sender === rowsStepper { apply(rows: sender.integerValue) } else { apply(columns: sender.integerValue) }
    }

    @objc private func fieldChanged(_ sender: NSTextField) {
        if sender === rowsField { apply(rows: sender.integerValue) } else { apply(columns: sender.integerValue) }
    }

    @objc private func defaultToggled() {
        let prefs = AppPreferences.shared
        prefs.useDefaultGrid = defaultCheckbox.state == .on
        if prefs.useDefaultGrid {
            prefs.defaultRows = prefs.rows
            prefs.defaultColumns = prefs.columns
        }
    }

    @objc private func doneClicked() {
        // Commit any value still being typed.
        window?.makeFirstResponder(nil)
        onDone?()
    }

    @objc private func settingsClicked() { onOpenSettings?() }

    private static func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = NSColor(white: 1, alpha: 0.85)
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        return label
    }
}
