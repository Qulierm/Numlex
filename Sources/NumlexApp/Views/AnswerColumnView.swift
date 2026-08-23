import SwiftUI
import NumlexCore

struct AnswerColumnView: View {
    var rows: [LineResult]
    var lineHeight: CGFloat
    var fontSize: Double
    var decimalPlaces: Int
    var sumLabel: String
    var topLine: Int = 0
    var lineTops: [CGFloat] = []

    /// The NSViewRepresentable editor and this SwiftUI ScrollView resolve the
    /// unified-titlebar safe area differently in the split-view column (a
    /// constant ~33 pt on macOS 26). Compensate so answers sit exactly on
    /// the editor's logical rows.
    private static let columnTopCompensation: CGFloat = 33

    /// Top offset of row 0 in scroll-content space.
    private var leadingHeight: CGFloat {
        let base: CGFloat = lineTops.isEmpty ? 12 : lineTops[0]
        return base + Self.columnTopCompensation
    }

    /// Height of row i — mirrors the editor's logical line geometry,
    /// so wrapped lines do not desynchronize the columns.
    private func rowHeight(_ i: Int) -> CGFloat {
        guard lineTops.count > i else { return lineHeight }
        if i + 1 < lineTops.count { return lineTops[i + 1] - lineTops[i] }
        return lineHeight
    }

    private func formatted(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.groupingSeparator = ","
            f.locale = Locale(identifier: "en_US")
            return f.string(from: NSNumber(value: Int64(value))) ?? "\(Int64(value))"
        }
        var s = String(format: "%.' + '\(decimalPlaces)f", value)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    private var summary: (value: String, unit: String?)? {
        let numeric = rows.compactMap { r -> Double? in
            if case .number(let v, let u) = r, u == nil { return v } else { return nil }
        }
        guard !numeric.isEmpty else { return nil }
        var sum = numeric.reduce(0, +)
        if sum.truncatingRemainder(dividingBy: 1) != 0 {
            sum = (sum * pow(10, Double(decimalPlaces))).rounded() / pow(10, Double(decimalPlaces))
        }
        return (formatted(sum), nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Aligns row 0 with the editor's first logical line.
                        Color.clear.frame(height: leadingHeight)
                        ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                            rowView(row)
                                .frame(height: rowHeight(idx), alignment: .trailing)
                                .id(idx)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .onChange(of: topLine) { _, new in
                    guard !rows.isEmpty else { return }
                    let target = min(max(new, 0), rows.count - 1)
                    withAnimation(.linear(duration: 0.08)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                }
            }

            if let s = summary {
                HStack(spacing: 8) {
                    Text(sumLabel)
                        .font(Design.labelSmall)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(s.value)
                        .font(Design.monoMedium(fontSize))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .padding(8)
            }
        }
        .frame(width: 200)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        .overlay(Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.3)).frame(width: 1), alignment: .leading)
    }

    @ViewBuilder
    private func rowView(_ row: LineResult) -> some View {
        switch row {
        case .blank, .skip, .title(_):
            Color.clear
        case .number(let v, let unit):
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                Text(formatted(v))
                    .font(Design.monoMedium(fontSize))
                    .lineLimit(1)
                if let u = unit {
                    Text(u)
                        .font(Design.labelSmall)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
        case .variable(let name, let v):
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                Text(name)
                    .font(Design.label)
                Text("=")
                    .font(Design.label)
                    .foregroundStyle(.secondary)
                Text(formatted(v))
                    .font(Design.monoMedium(fontSize))
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 12)
        case .error(let msg):
            HStack {
                Spacer(minLength: 0)
                Text(msg == "Rates unavailable" ? "Rates unavailable" : "Error")
                    .font(Design.labelSmall)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
        }
    }
}
