import SwiftUI

struct CropActionView: View {
    let session: NativeActionSession
    @State private var image: CGImage?
    @State private var selection = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var error: String?
    @State private var width = 1
    @State private var height = 1
    var body: some View {
        VStack(spacing: 16) {
            Text("Crop image").font(.title2)
            if let image {
                GeometryReader { geometry in
                    let scale = min(geometry.size.width / CGFloat(image.width), geometry.size.height / CGFloat(image.height))
                    let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
                    ZStack(alignment: .topLeading) {
                        Image(decorative: image, scale: 1).resizable().frame(width: size.width, height: size.height)
                        Rectangle().stroke(.white, lineWidth: 2)
                            .background(Color.accentColor.opacity(0.15))
                            .frame(width: selection.width * size.width, height: selection.height * size.height)
                            .offset(x: selection.minX * size.width, y: selection.minY * size.height)
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                        let start = CGPoint(x: min(1, max(0, gesture.startLocation.x / size.width)), y: min(1, max(0, gesture.startLocation.y / size.height)))
                        let end = CGPoint(x: min(1, max(0, gesture.location.x / size.width)), y: min(1, max(0, gesture.location.y / size.height)))
                        selection = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
                        width = max(1, Int(selection.width * CGFloat(image.width)))
                        height = max(1, Int(selection.height * CGFloat(image.height)))
                    })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Crop selection")
                    .accessibilityHint("Use width and height fields to crop with the keyboard")
                }
                HStack {
                    TextField("Width", value: $width, format: .number)
                    TextField("Height", value: $height, format: .number)
                }.onChange(of: width) { selection.size.width = min(1 - selection.minX, CGFloat(max(1, width)) / CGFloat(image.width)) }
                 .onChange(of: height) { selection.size.height = min(1 - selection.minY, CGFloat(max(1, height)) / CGFloat(image.height)) }
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { session.finish(); NSApp.terminate(nil) }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
                    .disabled(image == nil || selection.width <= 0 || selection.height <= 0)
            }
        }.padding(24).frame(width: 760, height: 600)
         .task { do { image = try session.image(); width = image!.width; height = image!.height } catch { self.error = error.localizedDescription } }
    }
    private func save() {
        guard let image else { return }
        let rect = CGRect(x: selection.minX * CGFloat(image.width), y: selection.minY * CGFloat(image.height),
                          width: selection.width * CGFloat(image.width), height: selection.height * CGFloat(image.height)).integral
        guard let cropped = image.cropping(to: rect) else { return }
        do { session.finish(output: try session.saveCrop(cropped)); NSApp.terminate(nil) }
        catch { self.error = error.localizedDescription }
    }
}
