import SwiftUI
import AppKit

/// Native scrolling keeps trackpad panning and cursor-anchored magnification together.
struct ZoomableImageView: NSViewRepresentable {
    let image: NSImage
    let identity: String
    let seed: Int?
    var zoomChanged: (CGFloat) -> Void = { _ in }
    func makeNSView(context: Context) -> ImageZoomScrollView { ImageZoomScrollView() }
    func updateNSView(_ view: ImageZoomScrollView, context: Context) {
        view.zoomChanged = nil
        view.show(image, identity: identity, seed: seed)
        view.zoomChanged = zoomChanged
        // Representable updates must not publish SwiftUI state synchronously.
        let expectedIdentity = identity
        DispatchQueue.main.async { [weak view] in
            guard let view, view.imageIdentity == expectedIdentity else { return }
            zoomChanged(view.magnification)
        }
    }
}

final class ImageZoomScrollView: NSScrollView {
    private let imageView = NSImageView()
    private(set) var imageIdentity: String?
    private var displayedSeed: Int?
    var zoomChanged: ((CGFloat) -> Void)?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        borderType = .noBorder; drawsBackground = false
        contentView.drawsBackground = false
        hasHorizontalScroller = false; hasVerticalScroller = false
        horizontalScrollElasticity = .none; verticalScrollElasticity = .none
        allowsMagnification = true; minMagnification = 1; maxMagnification = 16
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        documentView = imageView
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func show(_ image: NSImage, identity: String, seed: Int?) {
        let reset = imageIdentity == nil || displayedSeed != seed || (seed == nil && identity != imageIdentity)
        guard identity != imageIdentity || reset else { return }
        imageIdentity = identity; displayedSeed = seed; imageView.image = image
        guard reset else { return }
        magnification = 1
        imageView.frame = NSRect(origin: .zero, size: contentView.frame.size)
        contentView.scroll(to: .zero); reflectScrolledClipView(contentView)
        needsLayout = true
    }
    override func layout() {
        super.layout()
        let size = contentView.frame.size
        guard size.width > 0, size.height > 0, imageView.frame.size != size else { return }
        let oldSize = imageView.frame.size
        let visible = contentView.bounds
        let center = NSPoint(x: oldSize.width > 0 ? visible.midX / oldSize.width : 0.5,
                             y: oldSize.height > 0 ? visible.midY / oldSize.height : 0.5)
        imageView.frame = NSRect(origin: .zero, size: size)
        if magnification == 1 { contentView.scroll(to: .zero) }
        else {
            contentView.scroll(to: NSPoint(x: center.x * size.width - contentView.bounds.width / 2,
                                          y: center.y * size.height - contentView.bounds.height / 2))
        }
        reflectScrolledClipView(contentView)
    }
    override func magnify(with event: NSEvent) {
        let target = magnification * (1 + event.magnification)
        guard target.isFinite else { return }
        let bounded = min(maxMagnification, max(minMagnification, target))
        guard bounded != magnification else { return }
        // Avoid NSScrollView's elastic undershoot below the full-image fit.
        setMagnification(bounded, centeredAt: contentView.convert(event.locationInWindow, from: nil))
    }
    override func setMagnification(_ magnification: CGFloat, centeredAt point: NSPoint) {
        super.setMagnification(magnification, centeredAt: point)
        zoomChanged?(self.magnification)
    }
}
