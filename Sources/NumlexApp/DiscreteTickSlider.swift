import AppKit
import SwiftUI
import NumlexCore

/// r88: the ONE shared NSSlider configuration used by every discrete
/// precision slider in the app — the per-answer context-menu slider
/// (0...10, 11 ticks) and the Numbers-tab global rounding slider
/// (2...10, 9 ticks). Blue native track/thumb, ticks BELOW the track
/// (the reference look), small control size, snap-to-ticks, continuous
/// tracking. No segmented control, no menu picker.
enum TickSlider {
    static func make(min: Int, max: Int, value: Double) -> NSSlider {
        let s = NSSlider(value: value,
                         minValue: Double(min),
                         maxValue: Double(max),
                         target: nil,
                         action: nil)
        s.numberOfTickMarks = max - min + 1
        s.allowsTickMarkValuesOnly = true
        s.tickMarkPosition = .below
        s.controlSize = .small
        s.isContinuous = true
        return s
    }
}

/// r88: AppKit-backed discrete slider embedded in the SwiftUI Settings
/// window (the global rounding control). The live `N dp` label sits
/// to the right of the track; the callback fires ONLY when the snapped
/// integer actually changes (NSSlider re-fires on every tracking step).
struct DiscreteTickSlider: NSViewRepresentable {
    var minValue: Int
    var maxValue: Int
    var value: Int
    var liveLabel: String
    var a11yLabel: String
    var a11yValueFor: (Int) -> String
    var onChange: (Int) -> Void

    private let sliderHeight: CGFloat = 24
    private let gap: CGFloat = 10
    private let labelWidth: CGFloat = 44

    final class Host: NSView {
        let slider: NSSlider
        let label: NSTextField
        var onChange: ((Int) -> Void)?
        var a11yValueFor: ((Int) -> String)?
        private var last: Int

        let sliderHeight: CGFloat
        let gap: CGFloat
        let labelWidth: CGFloat

        init(slider: NSSlider, label: NSTextField, a11yLabel: String,
             sliderHeight: CGFloat, gap: CGFloat, labelWidth: CGFloat) {
            self.slider = slider
            self.label = label
            self.last = Int(slider.doubleValue.rounded())
            self.sliderHeight = sliderHeight
            self.gap = gap
            self.labelWidth = labelWidth
            super.init(frame: .zero)
            slider.target = self
            slider.action = #selector(changed)
            addSubview(slider)
            addSubview(label)
            setAccessibilityLabel(a11yLabel)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override var acceptsFirstResponder: Bool { true }

        override func layout() {
            super.layout()
            let w = bounds.width
            let sw = w - labelWidth - gap
            let y = (bounds.height - sliderHeight) / 2 - 2
            slider.frame = NSRect(x: 0, y: y, width: sw, height: sliderHeight)
            label.sizeToFit()
            let lh = label.frame.height
            label.frame = NSRect(x: w - labelWidth,
                                 y: y + (sliderHeight - lh) / 2,
                                 width: labelWidth, height: lh)
        }

        /// Continuous during the drag: the label updates immediately and
        /// the persisted value changes ONLY when the snapped integer
        /// changes (dedupe — NSSlider re-fires on every tracking step).
        @objc private func changed() {
            let v = Int(slider.doubleValue.rounded())
            label.stringValue = AnswerDisplay.sliderLabel(v)
            slider.setAccessibilityValue(a11yValueFor?(v) ?? "")
            if v != last {
                last = v
                onChange?(v)
            }
        }

        /// External sync (SwiftUI re-render after a change elsewhere):
        /// moves the thumb only when the value actually differs and
        /// refreshes the label / accessibility value.
        func sync(value: Int, label text: String, a11y: String) {
            if Int(slider.doubleValue.rounded()) != value {
                slider.doubleValue = Double(value)
                last = value
            }
            self.label.stringValue = text
            slider.setAccessibilityValue(a11y)
        }

    }

    func makeNSView(context: Context) -> NSView {
        let s = TickSlider.make(min: minValue, max: maxValue, value: Double(value))
        let l = NSTextField(labelWithString: liveLabel)
        l.font = .systemFont(ofSize: 12)
        l.textColor = .labelColor
        l.alignment = .right
        let host = Host(slider: s,
                        label: l,
                        a11yLabel: a11yLabel,
                        sliderHeight: sliderHeight,
                        gap: gap,
                        labelWidth: labelWidth)
        host.a11yValueFor = a11yValueFor
        host.onChange = { [weak host] v in
            // The host already updated its own label; fire the binding.
            _ = host
            onChange(v)
        }
        return host
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let host = nsView as? Host else { return }
        host.a11yValueFor = a11yValueFor
        host.onChange = { [weak host] v in
            _ = host
            onChange(v)
        }
        host.sync(value: value, label: liveLabel, a11y: a11yValueFor(value))
    }
}
