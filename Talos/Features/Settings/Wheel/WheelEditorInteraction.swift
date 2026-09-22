import SwiftUI

/// Each source owns its gesture lifetime. SwiftUI resets GestureState on both
/// completion and cancellation; only onEnded is allowed to commit an edit.
struct WheelEditorInteraction: ViewModifier {
    static let folderOpenDuration: TimeInterval = 0.5

    let source: WheelDragSource
    let model: WheelSettingsViewModel
    var folderID: WheelItem.ID?

    @GestureState private var isDragging = false
    @GestureState private var isPressingFolder = false

    func body(content: Content) -> some View {
        content
            .highPriorityGesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .named("wheelEditor"))
                    .updating($isDragging) { _, isDragging, _ in
                        isDragging = true
                    }
                    .onChanged { value in
                        model.updateDrag(source: source, location: value.location)
                    }
                    .onEnded { value in
                        model.endDrag(source: source, location: value.location)
                    }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: Self.folderOpenDuration, maximumDistance: 2)
                    .updating($isPressingFolder) { isPressing, state, _ in
                        state = isPressing
                    }
                    .onEnded { _ in
                        if let folderID { model.openFolder(folderID) }
                    },
                including: folderID == nil ? .none : .all
            )
            .onChange(of: isDragging) { _, isDragging in
                if !isDragging { model.cancelDrag(source: source) }
            }
            .onChange(of: isPressingFolder) { _, isPressed in
                if let folderID { model.setFolderPress(folderID, isPressed: isPressed) }
            }
            .onDisappear {
                model.cancelDrag(source: source)
                if let folderID { model.setFolderPress(folderID, isPressed: false) }
            }
    }
}
