import Foundation

@MainActor enum WheelFixtures {
    static var actions: [TalosAction] {
        (0..<6).map { index in
            TalosAction(id: "test.\(index)", title: "Action \(index)", symbol: "doc",
                destination: index == 3 ? .submenu((0..<7).map {
                    TalosAction(id: "child.\($0)", title: "Child \($0)", destination: .window)
                }) : .window)
        }
    }
}
