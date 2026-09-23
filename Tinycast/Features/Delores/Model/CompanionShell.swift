import CoreGraphics

/// Where a shell the Companion has opened goes: grown out of the body's inward side, rather than
/// hung from the menu bar.
///
/// Pure, so the geometry can be asserted without a window — the Companion rides the perimeter of
/// its display, and every question here is only "which way is inward from where it happens to be
/// standing", which needs no screen to answer.
///
/// The body stays *outside* the shell in every case: a bar that covered the Companion would take
/// away the thing the reader clicked to get it.
enum DeloresCompanionShell {
    /// Which creature skin is loaded into the Companion panel.
    enum Kind: String, CaseIterable, Sendable {
        case standard = "standard"
        case dog = "dog"
        case nezuko = "nezuko"
        case ddoZvzo = "ddoZvzo"
        case whaledou = "whaledou"
        case xiaoHei = "xiaoHei"
        case gugugaga = "gugugaga"
        case lillia = "lillia"
        case cat = "cat"
        case duck = "duck"
        case redPanda = "redPanda"

        var resourceName: String {
            switch self {
            case .standard: return "CompanionAtlas.generated"
            case .dog: return "CompanionAtlas-dog.generated"
            case .nezuko: return "CompanionAtlas-nezuko.generated"
            case .ddoZvzo: return "CompanionAtlas-ddoZvzo.generated"
            case .whaledou: return "CompanionAtlas-whaledou.generated"
            case .xiaoHei: return "CompanionAtlas-xiaoHei.generated"
            case .gugugaga: return "CompanionAtlas-gugugaga.generated"
            case .lillia: return "CompanionAtlas-lillia.generated"
            case .cat: return "CompanionAtlas-cat.generated"
            case .duck: return "CompanionAtlas-duck.generated"
            case .redPanda: return "CompanionAtlas-redPanda.generated"
            }
        }

        /// English source, and itself the catalog key — the creature's name is chrome, so a surface
        /// shows it through `L10n.text`. The proper noun stays put in both languages; what the
        /// parentheses carry is the description, and that is what gets translated.
        var displayName: String {
            switch self {
            case .standard: return "Delores (default sprite)"
            case .dog: return "July (red shiba)"
            case .nezuko: return "Nezuko (coding demon)"
            case .ddoZvzo: return "ddo-zvzo (crayfish)"
            case .whaledou: return "Whaledou (whale bean)"
            case .xiaoHei: return "Xiao Hei (black cat)"
            case .gugugaga: return "Gugugaga"
            case .lillia: return "Lillia (snow plum)"
            case .cat: return "Cat (kitten)"
            case .duck: return "Duck (yellow duck)"
            case .redPanda: return "Red Panda (red panda cub)"
            }
        }
    }

    /// How large the body is drawn. Two steps and no others: the sprite is authored at 48 px, so the
    /// only question is how many authored pixels a point is worth. Anything between the two puts a
    /// fractional number of device pixels under one authored pixel, which is what makes pixel art
    /// shimmer.
    enum Size: Int, CaseIterable, Sendable {
        case regular = 48
        case large = 96

        /// What the geometry works in. Where a shell may go is a question about the body's edge, so
        /// it is the radius that travels rather than the diameter.
        var radius: CGFloat { CGFloat(rawValue) / 2 }

        /// The window's side. There is no margin around the body any more: the sprite fills its
        /// window, and it is already larger than the thumb the old glass circle had to be padded for.
        var side: CGFloat { CGFloat(rawValue) }
    }

    /// The seam between the body and whatever grew out of it. Wide enough to read as two things,
    /// narrow enough to read as one gesture.
    static let shellGap: CGFloat = 8

    /// Where a shell ended up, and where the body had to go to let it.
    ///
    /// The body moving is part of the answer rather than a side effect: a shell that did not fit
    /// slides the Companion along its own edge until it does, and the caller has to be told, or the
    /// two drift apart on screen.
    struct Placement: Equatable {
        var petCenter: CGPoint
        var edge: DeloresCompanionEdge
        var frame: CGRect
    }

    // MARK: - The body

    static func circleFrame(center: CGPoint, bodyRadius: CGFloat) -> CGRect {
        CGRect(
            x: center.x - bodyRadius, y: center.y - bodyRadius,
            width: bodyRadius * 2, height: bodyRadius * 2)
    }

    /// Puts the body on `edge` without letting any part of it leave the visible area. The circle is
    /// kept a radius off each corner, so a body in a corner is on one edge and not half on two.
    static func snapCenter(
        _ point: CGPoint, to edge: DeloresCompanionEdge, in visibleFrame: CGRect,
        bodyRadius: CGFloat
    ) -> CGPoint {
        let minX = visibleFrame.minX + bodyRadius
        let maxX = visibleFrame.maxX - bodyRadius
        let minY = visibleFrame.minY + bodyRadius
        let maxY = visibleFrame.maxY - bodyRadius
        let x = min(max(point.x, minX), maxX)
        let y = min(max(point.y, minY), maxY)
        switch edge {
        case .right: return CGPoint(x: maxX, y: y)
        case .left: return CGPoint(x: minX, y: y)
        case .top: return CGPoint(x: x, y: maxY)
        case .bottom: return CGPoint(x: x, y: minY)
        }
    }

    /// Which edge a point is closest to. A corner is equally near two, and the right one wins —
    /// which is the edge the Companion spawns on, so an untouched body answers `.right`.
    static func nearestEdge(to point: CGPoint, in visibleFrame: CGRect) -> DeloresCompanionEdge {
        let distances: [(DeloresCompanionEdge, CGFloat)] = [
            (.right, abs(visibleFrame.maxX - point.x)),
            (.left, abs(point.x - visibleFrame.minX)),
            (.top, abs(visibleFrame.maxY - point.y)),
            (.bottom, abs(point.y - visibleFrame.minY)),
        ]
        return distances.min(by: { $0.1 < $1.1 })?.0 ?? .right
    }

    /// A Delores-owned body on the bottom edge slides to a vertical edge before opening a bar. An
    /// external body cannot be moved, so its horizontal edge remains the bar's orientation.
    static func edgeForOpeningBar(
        current: DeloresCompanionEdge, petCenter: CGPoint, visibleFrame: CGRect
    ) -> DeloresCompanionEdge {
        guard current == .bottom else { return current }
        let distLeft = petCenter.x - visibleFrame.minX
        let distRight = visibleFrame.maxX - petCenter.x
        return distLeft <= distRight ? .left : .right
    }

    static func openingEdge(
        current: DeloresCompanionEdge, petCenter: CGPoint, visibleFrame: CGRect,
        canMovePet: Bool
    ) -> DeloresCompanionEdge {
        canMovePet
            ? edgeForOpeningBar(current: current, petCenter: petCenter, visibleFrame: visibleFrame)
            : current
    }

    /// The menu bar and Dock of this display are still this display. `visibleFrame.contains` is the
    /// wrong question: the body walks `screen.frame`, so a body on the menu bar sits outside the
    /// visible frame on purpose.
    static func isOnSameDisplay(bodyScreenFrame: CGRect?, shellScreenFrame: CGRect) -> Bool {
        bodyScreenFrame == shellScreenFrame
    }

    // MARK: - Shells

    /// Where a dragged window counts as having been brought to the body. Generous on purpose: a
    /// drag carries a window, not a pointer, and a target the reader has to hit exactly is one
    /// they will miss. It grows with the body so larger external pets remain easy to hit without
    /// expanding beyond their visible bounds.
    static func dragHitFrame(center: CGPoint, bodyRadius: CGFloat = 30) -> CGRect {
        let side = max(60, bodyRadius * 2)
        return CGRect(
            x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    }

    /// The body's own target and the island it grew, as one rect: what a drag may be holding while
    /// an island is up.
    ///
    /// Separate from `dragHitFrame` because the seam between them is `shellGap` of nothing: a drag
    /// that crosses it in one frame finds no target under it, so the run is torn down there — the
    /// gesture failing at its last step, after the reader had already committed to it.
    static func dragHoldFrame(
        bodyCenter: CGPoint, islandFrame: CGRect, bodyRadius: CGFloat = 30
    ) -> CGRect {
        dragHitFrame(center: bodyCenter, bodyRadius: bodyRadius).union(islandFrame)
    }

    /// A closed bar: grown from the body's inward side, level with its centre.
    static func planBarOpening(
        petCenter: CGPoint,
        edge: DeloresCompanionEdge,
        shellSize: CGSize,
        visibleFrame: CGRect,
        bodyRadius: CGFloat,
        canMovePet: Bool = true,
        avoidFrame: CGRect? = nil
    ) -> Placement {
        let resolvedEdge = openingEdge(
            current: edge, petCenter: petCenter, visibleFrame: visibleFrame,
            canMovePet: canMovePet)
        var center = petCenter
        if canMovePet, resolvedEdge != edge {
            center = snapCenter(petCenter, to: resolvedEdge, in: visibleFrame, bodyRadius: bodyRadius)
        }
        let placement = placeShell(
            petCenter: center, edge: resolvedEdge, shellSize: shellSize,
            visibleFrame: visibleFrame, bodyRadius: bodyRadius, canMovePet: canMovePet)
        guard !canMovePet, resolvedEdge == .bottom || resolvedEdge == .top,
            let avoidFrame, placement.frame.intersects(avoidFrame)
        else { return placement }

        let pet = circleFrame(center: center, bodyRadius: bodyRadius)
        let outwardY = center.y - shellSize.height / 2
            + (resolvedEdge == .top ? shellGap : -shellGap)
        let y = min(
            max(outwardY, visibleFrame.minY),
            max(visibleFrame.minY, visibleFrame.maxY - shellSize.height))
        let left = CGRect(
            x: pet.minX - shellGap - shellSize.width, y: y,
            width: shellSize.width, height: shellSize.height)
        let right = CGRect(
            x: pet.maxX + shellGap, y: y,
            width: shellSize.width, height: shellSize.height)
        let candidates = [
            (left, pet.minX - visibleFrame.minX),
            (right, visibleFrame.maxX - pet.maxX),
        ].sorted { $0.1 > $1.1 }
        let clearAvoidance = avoidFrame.insetBy(dx: -shellGap, dy: -shellGap)
        if let frame = candidates.first(where: {
            visibleFrame.contains($0.0) && !$0.0.intersects(clearAvoidance)
        })?.0 {
            return Placement(petCenter: center, edge: resolvedEdge, frame: frame)
        }
        guard let frame = activityClearFrame(
            petCenter: center, bodyRadius: bodyRadius, shellSize: shellSize,
            visibleFrame: visibleFrame,
            activityFrame: clearAvoidance)
        else { return placement }
        return Placement(petCenter: center, edge: resolvedEdge, frame: frame)
    }

    /// A snap island: grown out of the body's inward side too, with its long axis along the edge the
    /// body rides — horizontal above or below the body, vertical beside it. The body may open one
    /// from the bottom edge, unlike a bar: an island is a preview that lives for the length of a
    /// drag, not a surface the reader reads from.
    ///
    /// Placed off where the body stands, and only then clamped to the display. The body does not
    /// move for an island — a drag chose a body standing there — so a placement derived from a body
    /// first snapped *into* the visible frame is a placement for a body that is not there, and it
    /// leaves the reader a stretch of nothing to cross on the way to the island.
    static func planIslandOpening(
        petCenter: CGPoint,
        edge: DeloresCompanionEdge,
        islandSize: CGSize,
        visibleFrame: CGRect,
        bodyRadius: CGFloat
    ) -> Placement {
        let frame = inwardFrame(
            petVisible: circleFrame(center: petCenter, bodyRadius: bodyRadius),
            edge: edge, shellSize: islandSize)
        return Placement(petCenter: petCenter, edge: edge, frame: clamp(frame, to: visibleFrame))
    }

    /// An opened card: the bar stays level with the body's centre and the answer hangs downward from
    /// it.
    ///
    /// On a vertical edge the body slides *up* when the card would otherwise run off the bottom,
    /// which is the only direction it can go that keeps it beside what it opened.
    static func planExpandedBarOpening(
        petCenter: CGPoint,
        edge: DeloresCompanionEdge,
        collapsedSize: CGSize,
        expandedSize: CGSize,
        visibleFrame: CGRect,
        bodyRadius: CGFloat,
        canMovePet: Bool = true
    ) -> Placement {
        let resolvedEdge = openingEdge(
            current: edge, petCenter: petCenter, visibleFrame: visibleFrame,
            canMovePet: canMovePet)
        var center = petCenter
        if canMovePet, resolvedEdge != edge {
            center = snapCenter(petCenter, to: resolvedEdge, in: visibleFrame, bodyRadius: bodyRadius)
        }
        var frame = hangDownFrame(
            petCenter: center, edge: resolvedEdge,
            collapsedSize: collapsedSize, expandedSize: expandedSize, bodyRadius: bodyRadius)
        if canMovePet && (resolvedEdge == .left || resolvedEdge == .right) {
            let overflowBottom = visibleFrame.minY - frame.minY
            if overflowBottom > 0 {
                center = snapCenter(
                    CGPoint(x: center.x, y: center.y + overflowBottom),
                    to: resolvedEdge, in: visibleFrame, bodyRadius: bodyRadius)
                frame = hangDownFrame(
                    petCenter: center, edge: resolvedEdge,
                    collapsedSize: collapsedSize, expandedSize: expandedSize,
                    bodyRadius: bodyRadius)
            }
        }
        frame = clamp(frame, to: visibleFrame)
        return Placement(petCenter: center, edge: resolvedEdge, frame: frame)
    }

    /// The shell sits on the body's inward side with a `shellGap` seam, and the body stays outside
    /// it. If it does not fit, the body slides along its own edge until it does.
    static func placeShell(
        petCenter: CGPoint,
        edge: DeloresCompanionEdge,
        shellSize: CGSize,
        visibleFrame: CGRect,
        bodyRadius: CGFloat,
        canMovePet: Bool = true
    ) -> Placement {
        // Stand where the body is. Snapping into `visibleFrame` first would fetch a body off the
        // menu bar — the same mistake `planIslandOpening` already stopped making.
        var center = petCenter
        var frame = inwardFrame(
            petVisible: circleFrame(center: center, bodyRadius: bodyRadius),
            edge: edge, shellSize: shellSize)

        if canMovePet {
            switch edge {
            case .top, .bottom:
                let overflowLeft = visibleFrame.minX - frame.minX
                let overflowRight = frame.maxX - visibleFrame.maxX
                var shift: CGFloat = 0
                if overflowLeft > 0 { shift += overflowLeft }
                if overflowRight > 0 { shift -= overflowRight }
                if shift != 0 {
                    center = CGPoint(x: center.x + shift, y: center.y)
                    frame = inwardFrame(
                        petVisible: circleFrame(center: center, bodyRadius: bodyRadius),
                        edge: edge, shellSize: shellSize)
                }
            case .left, .right:
                let overflowBottom = visibleFrame.minY - frame.minY
                let overflowTop = frame.maxY - visibleFrame.maxY
                var shift: CGFloat = 0
                if overflowBottom > 0 { shift += overflowBottom }
                if overflowTop > 0 { shift -= overflowTop }
                if shift != 0 {
                    center = CGPoint(x: center.x, y: center.y + shift)
                    frame = inwardFrame(
                        petVisible: circleFrame(center: center, bodyRadius: bodyRadius),
                        edge: edge, shellSize: shellSize)
                }
            }
        }

        frame = clamp(frame, to: visibleFrame)
        return Placement(petCenter: center, edge: edge, frame: frame)
    }

    /// On a vertical edge the shell is level with the body's centre; on a horizontal one it is
    /// centred on the body and hangs off its inward side.
    private static func inwardFrame(
        petVisible: CGRect, edge: DeloresCompanionEdge, shellSize: CGSize
    ) -> CGRect {
        switch edge {
        case .right:
            return CGRect(
                x: petVisible.minX - shellGap - shellSize.width,
                y: petVisible.midY - shellSize.height / 2,
                width: shellSize.width, height: shellSize.height)
        case .left:
            return CGRect(
                x: petVisible.maxX + shellGap,
                y: petVisible.midY - shellSize.height / 2,
                width: shellSize.width, height: shellSize.height)
        case .top:
            return CGRect(
                x: petVisible.midX - shellSize.width / 2,
                y: petVisible.minY - shellGap - shellSize.height,
                width: shellSize.width, height: shellSize.height)
        case .bottom:
            return CGRect(
                x: petVisible.midX - shellSize.width / 2,
                y: petVisible.maxY + shellGap,
                width: shellSize.width, height: shellSize.height)
        }
    }

    /// Where an opened card goes. On a horizontal edge it hangs below the bar, sharing the bar's
    /// top edge. On a vertical edge the bar is a vertical strip and the card shares its pet-side
    /// edge instead — the strip rides the card's pet-side rim like a spine, and the growth is one
    /// inward gesture. Either way the card starts where the bar starts along the shell's long
    /// axis, and the bar itself never moves.
    private static func hangDownFrame(
        petCenter: CGPoint,
        edge: DeloresCompanionEdge,
        collapsedSize: CGSize,
        expandedSize: CGSize,
        bodyRadius: CGFloat
    ) -> CGRect {
        let pet = circleFrame(center: petCenter, bodyRadius: bodyRadius)
        let top = pet.midY + collapsedSize.height / 2
        let y = top - expandedSize.height
        switch edge {
        case .right:
            return CGRect(
                x: pet.minX - shellGap - expandedSize.width,
                y: y, width: expandedSize.width, height: expandedSize.height)
        case .left:
            return CGRect(
                x: pet.maxX + shellGap,
                y: y, width: expandedSize.width, height: expandedSize.height)
        case .top, .bottom:
            return inwardFrame(
                petVisible: pet, edge: edge, shellSize: expandedSize)
        }
    }

    /// Keeps a shell inside what the display actually shows. A shell wider than the display is
    /// shrunk to it rather than left hanging off both ends.
    private static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        var r = rect
        if r.width > bounds.width { r.size.width = bounds.width }
        if r.height > bounds.height { r.size.height = bounds.height }
        if r.minX < bounds.minX { r.origin.x = bounds.minX }
        if r.maxX > bounds.maxX { r.origin.x = bounds.maxX - r.width }
        if r.minY < bounds.minY { r.origin.y = bounds.minY }
        if r.maxY > bounds.maxY { r.origin.y = bounds.maxY - r.height }
        return r
    }

    private static func activityClearFrame(
        petCenter: CGPoint, bodyRadius: CGFloat, shellSize: CGSize,
        visibleFrame: CGRect, activityFrame: CGRect
    ) -> CGRect? {
        let width = min(shellSize.width, visibleFrame.width)
        let height = min(shellSize.height, visibleFrame.height)
        let x = min(
            max(petCenter.x - width / 2, visibleFrame.minX),
            max(visibleFrame.minX, visibleFrame.maxX - width))
        let pet = circleFrame(center: petCenter, bodyRadius: bodyRadius)
        let above = CGRect(
            x: x, y: activityFrame.maxY + shellGap, width: width, height: height)
        let below = CGRect(
            x: x, y: activityFrame.minY - shellGap - height, width: width, height: height)
        return [above, below].first(where: {
            visibleFrame.contains($0) && !$0.intersects(activityFrame) && !$0.intersects(pet)
        })
    }
}

/// What the Companion tells another surface about where its body is standing: enough to grow a shell
/// out of it, and the radius with it, because every question here is about the body's edge and only
/// the Companion knows how large it is drawn.
typealias DeloresCompanionAnchor = (center: CGPoint, edge: DeloresCompanionEdge, radius: CGFloat)
