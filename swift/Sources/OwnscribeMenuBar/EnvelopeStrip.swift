import SwiftUI

public struct EnvelopeStrip: View {
    let buckets: [Double]

    public var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard !buckets.isEmpty else { return }

                let barWidth = size.width / CGFloat(buckets.count)
                let maxHeight = size.height

                for (index, amplitude) in buckets.enumerated() {
                    let x = CGFloat(index) * barWidth
                    let height = CGFloat(amplitude) * maxHeight
                    let y = (maxHeight - height) / 2

                    let rect = CGRect(x: x, y: y, width: barWidth, height: height)
                    context.fill(Path(rect), with: .color(.purple.opacity(0.6)))
                }
            }
        }
        .frame(height: 32)
    }
}
