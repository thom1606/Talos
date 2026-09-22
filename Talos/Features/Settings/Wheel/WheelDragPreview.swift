import SwiftUI

struct PositionedWheelDragPreview: View {
    let title: String
    let symbolName: String
    let position: WheelDragPosition

    var body: some View {
        WheelDragPreview(title: title, symbolName: symbolName)
            .position(position.point)
    }
}

struct WheelDragPreview: View {
    let title: String
    let symbolName: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbolName)
                .font(.title3)

            Text(title)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: 82, height: 68)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .opacity(0.85)
    }
}
