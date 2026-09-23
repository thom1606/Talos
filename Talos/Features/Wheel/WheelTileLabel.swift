import SwiftUI

/// Actions without an icon show their title centered in the segment.
/// Icon actions keep the compact icon and label layout.
struct WheelTileLabel: View {
    let title: String
    let symbolName: String
    let layout: WheelLayout
    let count: Int

    var body: some View {
        let isEditor = layout == .editor
        let width = layout.contentWidth(count: count, maximum: isEditor ? 58 : 68)
        let iconSize = min(isEditor ? 17.0 : 19.0, width * 0.65)

        if symbolName.isEmpty {
            Text(title.uppercased())
                .font(.system(size: isEditor ? 10 : 11, weight: .semibold))
                .tracking(isEditor ? 0.15 : 0.2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .frame(width: width)
        } else {
            VStack(spacing: isEditor ? 6 : 7) {
                Image(systemName: symbolName)
                    .font(.system(size: iconSize, weight: .regular))
                    .frame(width: min(24, width), height: min(24, width))

                if width >= 48 {
                    Text(title.uppercased())
                        .font(.system(size: isEditor ? 8 : 9, weight: .semibold))
                        .tracking(isEditor ? 0.15 : 0.2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: width, height: 14)
                        .clipped()
                }
            }
        }
    }
}
