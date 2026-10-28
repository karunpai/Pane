import AppKit

final class AppearancePreferencesViewController: NSViewController {
    private let prefs = AppPreferences.shared
    private var fields: [String: NumberStepperField] = [:]
    private var spacingFields: [NumberStepperField] = []

    override func loadView() {
        let form = SettingsForm()

        form.row("Grid rows:", numberControl("rows", Double(prefs.rows), 1...10, suffix: "1–10"))
        form.row("Grid columns:", numberControl("columns", Double(prefs.columns), 1...10, suffix: "1–10"))
        form.row(nil, checkbox("Show resize preview", state: prefs.showPreview,
                               target: self, action: #selector(togglePreview(_:))))

        form.separator()
        form.row("Window spacing:", checkbox("Use gaps and screen margins", state: prefs.marginsEnabled,
                                             target: self, action: #selector(toggleMargins(_:))))
        form.row("Horizontal gap:", numberControl("horizontalGap", prefs.horizontalGap, 0...300, suffix: "pt", spacing: true))
        form.row("Vertical gap:", numberControl("verticalGap", prefs.verticalGap, 0...300, suffix: "pt", spacing: true))

        let margins = BaselineGridView(views: [
            [formLabel("Top"), numberControl("marginTop", prefs.marginTop, 0...300, spacing: true),
             formLabel("Bottom"), numberControl("marginBottom", prefs.marginBottom, 0...300, spacing: true)],
            [formLabel("Left"), numberControl("marginLeft", prefs.marginLeft, 0...300, spacing: true),
             formLabel("Right"), numberControl("marginRight", prefs.marginRight, 0...300, spacing: true)]
        ])
        margins.rowSpacing = SettingsMetrics.spacing
        margins.columnSpacing = SettingsMetrics.spacing
        margins.rowAlignment = .firstBaseline
        margins.column(at: 0).xPlacement = .trailing
        margins.column(at: 2).xPlacement = .trailing
        margins.column(at: 2).leadingPadding = 12
        form.row("Screen margins:", margins)
        form.row(nil, wrappingNote("Margins are in points. Changes apply to the next preview or window move and are saved automatically.",
                                   width: SettingsMetrics.controlColumnWidth))
        updateSpacingEnabled()

        view = makeFormTabView(form: form, for: self)
    }

    private func numberControl(_ key: String, _ value: Double, _ range: ClosedRange<Double>,
                               suffix: String? = nil, spacing: Bool = false) -> NSView {
        let control = NumberStepperField(value: value, range: range)
        control.onChange = { [weak self] newValue in self?.commit(key, newValue) }
        fields[key] = control
        if spacing { spacingFields.append(control) }
        guard let suffix else { return control }
        return hStack([control, secondaryLabel(suffix)], spacing: 6)
    }

    private func commit(_ key: String, _ value: Double) {
        switch key {
        case "rows": prefs.rows = Int(value)
        case "columns": prefs.columns = Int(value)
        case "horizontalGap": prefs.horizontalGap = value
        case "verticalGap": prefs.verticalGap = value
        case "marginLeft": prefs.marginLeft = value
        case "marginRight": prefs.marginRight = value
        case "marginTop": prefs.marginTop = value
        case "marginBottom": prefs.marginBottom = value
        default: return
        }
        refreshFields()
    }

    private func refreshFields() {
        fields["rows"]?.setValue(Double(prefs.rows))
        fields["columns"]?.setValue(Double(prefs.columns))
        fields["horizontalGap"]?.setValue(prefs.horizontalGap)
        fields["verticalGap"]?.setValue(prefs.verticalGap)
        fields["marginLeft"]?.setValue(prefs.marginLeft)
        fields["marginRight"]?.setValue(prefs.marginRight)
        fields["marginTop"]?.setValue(prefs.marginTop)
        fields["marginBottom"]?.setValue(prefs.marginBottom)
    }

    private func updateSpacingEnabled() {
        spacingFields.forEach { $0.isEnabled = prefs.marginsEnabled }
    }

    @objc private func togglePreview(_ sender: NSButton) { prefs.showPreview = sender.state == .on }
    @objc private func toggleMargins(_ sender: NSButton) {
        prefs.marginsEnabled = sender.state == .on
        updateSpacingEnabled()
    }
}
