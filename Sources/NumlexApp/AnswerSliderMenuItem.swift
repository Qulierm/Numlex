import AppKit
import NumlexCore

/// r54: the inline discrete precision slider of the answer context
/// menu — a NATIVE `NSSlider` (0...10, eleven tick marks, tick-only
/// values) with a live `N dp` label, wrapped in ONE custom
/// `NSMenuItem`. No custom menu background: the item's view paints
/// nothing behind the control, so the menu's native material, corners
/// and shadow are exactly what NSMenu draws.
///
/// Target lifetime: `NSControl` does NOT retain its target, so the
/// slider targets THE OWNING VIEW ITSELF. The view is retained by the
/// `NSMenuItem.view` slot (the menu retains its items for the whole
/// tracking session), so the target chain lives exactly as long as the
/// open menu — no leak, no stale closure, no extra retention cycle.
@MainActor
enum AnswerSliderMenuItem {
    /// One custom item: slider + live label. `initial` is the row's
    /// effective precision (already clamped to 0...10 by
    /// `AnswerDisplay.sliderValue`); `onChange` fires with the SNAPPED
    /// integer only when it changes (a tick-to-tick drag emits each
    /// value once — no duplicate persistence storms).
    static func menuItem(initial: Int,
                         language: AppLanguage,
                         onChange: @escaping (Int) -> Void) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = SliderView(initial: initial,
                               language: language,
                               onChange: onChange)
        item.isEnabled = true
        return item
    }

    /// The centered, disabled, informational caption under the slider
    /// (`Edit answer formatting` in the active language). Disabled by
    /// construction: it never opens Settings and can never be chosen.
    static func caption(language: AppLanguage) -> NSMenuItem {
        let mi = NSMenuItem()
        let ps = NSMutableParagraphStyle()
        ps.alignment = .center
        mi.attributedTitle = NSAttributedString(
            string: L10n.t("editAnswerFormatting", language: language),
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .paragraphStyle: ps,
            ])
        mi.isEnabled = false
        return mi
    }
}

/// The slider + label view inside one menu item. Deterministic manual
/// layout (menus do not guarantee a full Auto Layout pass for custom
/// views): standard menu text inset on the left, a fixed label column
/// on the right, the slider filling the middle; the ticks hang BELOW
/// the track (the reference's tick row) and stay inside the item.
private final class SliderView: NSView {
    private let slider: NSSlider
    private let label: NSTextField
    private let onChange: (Int) -> Void
    private let language: AppLanguage
    private var lastValue: Int

    // Deterministic geometry (points): the item is compact — wide
    // enough for the slider plus `10 dp`, not a giant panel.
    private let width: CGFloat = 224
    private let height: CGFloat = 40
    private let leftInset: CGFloat = 14
    private let rightInset: CGFloat = 12
    private let labelColumn: CGFloat = 44
    private let gap: CGFloat = 10

    init(initial: Int, language: AppLanguage, onChange: @escaping (Int) -> Void) {
        self.onChange = onChange
        self.language = language
        self.lastValue = initial

        // The target is wired AFTER super.init (a self target cannot
        // exist before the view is initialized).
        let s = NSSlider(value: Double(initial),
                         minValue: Double(AnswerDisplay.minPlaces),
                         maxValue: Double(AnswerDisplay.maxPlaces),
                         target: nil,
                         action: nil)
        s.numberOfTickMarks = AnswerDisplay.maxPlaces + 1
        s.allowsTickMarkValuesOnly = true
        s.tickMarkPosition = .below
        s.controlSize = .small
        s.isContinuous = true
        s.setAccessibilityLabel(L10n.t("decimalPlaces", language: language))
        s.setAccessibilityValue(
            AnswerDisplay.sliderAccessibilityValue(initial, language: language))
        self.slider = s

        let l = NSTextField(labelWithString: AnswerDisplay.sliderLabel(initial))
        l.font = NSFont.menuFont(ofSize: 0)
        l.textColor = .labelColor
        l.alignment = .right
        self.label = l

        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        s.target = self
        s.action = #selector(changed)
        addSubview(s)
        addSubview(l)
        setAccessibilityLabel(L10n.t("editAnswerFormatting", language: language))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        let w = bounds.width
        let sliderW = w - leftInset - rightInset - labelColumn - gap
        let sliderH: CGFloat = 24
        // The track sits slightly above the item's centerline so the
        // tick row below it stays inside the item; the label is
        // centered on the TRACK line.
        let sliderY = (height - sliderH) / 2 - 2
        slider.frame = NSRect(x: leftInset, y: sliderY,
                              width: sliderW, height: sliderH)
        label.sizeToFit()
        let lh = label.frame.height
        label.frame = NSRect(x: w - rightInset - labelColumn,
                             y: sliderY + (sliderH - lh) / 2,
                             width: labelColumn, height: lh)
    }

    /// Continuous during the drag: the label updates immediately and
    /// the row's override is written ONLY when the snapped integer
    /// changes (NSSlider re-fires on every tracking step).
    @objc private func changed() {
        let v = Int(slider.doubleValue.rounded())
        label.stringValue = AnswerDisplay.sliderLabel(v)
        slider.setAccessibilityValue(
            AnswerDisplay.sliderAccessibilityValue(v, language: language))
        if v != lastValue {
            lastValue = v
            onChange(v)
        }
    }
}
