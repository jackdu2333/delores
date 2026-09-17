import CoreGraphics
import Foundation

/// Which edge of its display the Companion rides. Declared beside the wander that walks it, so the
/// rules can be asserted without a window: a corner is two edges at once, and the right one wins.
enum DeloresCompanionEdge: Equatable, Sendable {
    case top, bottom, left, right
}

/// How the Companion decides where to be.
///
/// Randomness is injected rather than drawn, because a wander nobody can replay is a wander nobody
/// can assert. A trip is one speed and one destination; between trips it stands still, and for much
/// longer than it walks. The clock is the caller's — a rest's `until` and the `now` compared
/// against it only have to come from the same one.
///
/// Every distance here is along the display's perimeter, so the body rides an edge and never cuts
/// across the middle of the screen it exists to be found beside.
enum DeloresCompanionWander {
    enum Phase: Equatable, Sendable {
        case resting(until: TimeInterval)
        case strolling(destination: CGFloat, speed: CGFloat)
    }

    struct State: Equatable, Sendable {
        var center: CGPoint
        var phase: Phase
    }

    /// Most rests are a pause; the tail is what makes the thing read as occupied rather than
    /// scheduled. An even rhythm is the thing that looks mechanical.
    static let shortRestRange: ClosedRange<TimeInterval> = 2...8
    static let longRestRange: ClosedRange<TimeInterval> = 20...60
    static let longRestChance = 0.25

    /// Past this a motionless Companion reads as a dead one, so no rest is allowed to reach it.
    static let maximumRest: TimeInterval = longRestRange.upperBound

    /// A trip holds one speed from end to end. Held, because a speed that jitters reads as a fault
    /// and a speed that never varies reads as a motor.
    static let speedRange: ClosedRange<CGFloat> = 16...34

    /// How far a trip goes. Most are a few steps and a look around; the tail is the long way, which
    /// is what keeps the walking from reading as a metronome. The floor is also the guarantee that a
    /// trip never ends on the spot the last one left.
    static let shortTripRange: ClosedRange<CGFloat> = 120...360
    static let longTripChance = 0.2

    /// A frame that arrives late — a slept machine, a stalled run loop — must not fling the body
    /// across the display.
    static let maximumStep: TimeInterval = 0.25

    /// Every arrival — a start, a drop, a screen change — begins here: still, on an edge.
    static func settled(
        at center: CGPoint, in bounds: CGRect, at now: TimeInterval,
        using rng: inout some RandomNumberGenerator
    ) -> State {
        State(
            center: project(center, into: bounds),
            phase: .resting(until: now + restDuration(using: &rng)))
    }

    /// One frame. A rest that is not yet due returns the state untouched, which is what lets the
    /// caller run no timer at all in between.
    static func advance(
        _ state: State, elapsed: TimeInterval, now: TimeInterval, in bounds: CGRect,
        using rng: inout some RandomNumberGenerator
    ) -> State {
        switch state.phase {
        case .resting(let until):
            guard now >= until else { return state }
            return State(
                center: state.center,
                phase: .strolling(
                    destination: destination(from: state.center, in: bounds, using: &rng),
                    speed: CGFloat.random(in: speedRange, using: &rng)))
        case .strolling(let destination, let speed):
            let budget = speed * CGFloat(min(max(elapsed, 0), maximumStep))
            return travel(state, to: destination, budget: budget, now: now, in: bounds, using: &rng)
        }
    }

    /// When the caller has to think about the Companion again: the end of a rest, or nothing at all
    /// while it is walking.
    static func nextWake(after state: State) -> TimeInterval? {
        guard case .resting(let until) = state.phase else { return nil }
        return until
    }

    /// The point on the perimeter nearest `point`. Every write to the body goes through here, so it
    /// can never be left somewhere the wander has no way back from.
    static func project(_ point: CGPoint, into bounds: CGRect) -> CGPoint {
        position(at: distanceAlongPerimeter(of: point, in: bounds), in: bounds)
    }

    /// A corner is equally near two edges, and the right one wins — the edge it spawns on.
    static func edge(for point: CGPoint, in bounds: CGRect) -> DeloresCompanionEdge {
        let distances: [(DeloresCompanionEdge, CGFloat)] = [
            (.right, abs(bounds.maxX - point.x)),
            (.left, abs(point.x - bounds.minX)),
            (.top, abs(bounds.maxY - point.y)),
            (.bottom, abs(point.y - bounds.minY)),
        ]
        return distances.min { $0.1 < $1.1 }?.0 ?? .right
    }

    static func perimeter(of bounds: CGRect) -> CGFloat { 2 * (bounds.width + bounds.height) }

    /// How far a point sits along the perimeter, measured clockwise from the bottom-left corner.
    static func distanceAlongPerimeter(of point: CGPoint, in bounds: CGRect) -> CGFloat {
        let width = bounds.width
        let height = bounds.height
        switch edge(for: point, in: bounds) {
        case .bottom: return clamp(point.x - bounds.minX, 0, width)
        case .right: return width + clamp(point.y - bounds.minY, 0, height)
        case .top: return width + height + clamp(bounds.maxX - point.x, 0, width)
        case .left: return 2 * width + height + clamp(bounds.maxY - point.y, 0, height)
        }
    }

    static func restDuration(using rng: inout some RandomNumberGenerator) -> TimeInterval {
        let range = Double.random(in: 0...1, using: &rng) < longRestChance ? longRestRange : shortRestRange
        return min(Double.random(in: range, using: &rng), maximumRest)
    }

    /// Half the perimeter is the longest meaningful trip: past it the short way round is the other
    /// way, and a destination stops being a direction.
    static func tripDistance(in bounds: CGRect, using rng: inout some RandomNumberGenerator) -> CGFloat {
        let longest = max(shortTripRange.upperBound, perimeter(of: bounds) / 2)
        let range = Double.random(in: 0...1, using: &rng) < longTripChance
            ? shortTripRange.upperBound...longest
            : shortTripRange
        return CGFloat.random(in: range, using: &rng)
    }

    private static func travel(
        _ state: State, to destination: CGFloat, budget: CGFloat, now: TimeInterval, in bounds: CGRect,
        using rng: inout some RandomNumberGenerator
    ) -> State {
        let total = perimeter(of: bounds)
        let here = distanceAlongPerimeter(of: state.center, in: bounds)
        let delta = shortestDelta(from: here, to: destination, around: total)
        guard abs(delta) > budget else {
            return State(
                center: position(at: destination, in: bounds),
                phase: .resting(until: now + restDuration(using: &rng)))
        }
        let moved = here + (delta > 0 ? budget : -budget)
        return State(center: position(at: moved, in: bounds), phase: state.phase)
    }

    /// A destination drawn as a signed offset from where the body stands, so the draw itself can
    /// never land on the spot it is leaving.
    private static func destination(
        from center: CGPoint, in bounds: CGRect, using rng: inout some RandomNumberGenerator
    ) -> CGFloat {
        let total = perimeter(of: bounds)
        let offset = tripDistance(in: bounds, using: &rng)
        let sign: CGFloat = Bool.random(using: &rng) ? 1 : -1
        return normalized(distanceAlongPerimeter(of: center, in: bounds) + sign * offset, around: total)
    }

    /// The short way round, so a trip never crosses the middle of the display to reach its edge.
    private static func shortestDelta(from here: CGFloat, to there: CGFloat, around total: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        var delta = (there - here).truncatingRemainder(dividingBy: total)
        if delta > total / 2 { delta -= total }
        if delta < -total / 2 { delta += total }
        return delta
    }

    private static func normalized(_ distance: CGFloat, around total: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        let remainder = distance.truncatingRemainder(dividingBy: total)
        return remainder < 0 ? remainder + total : remainder
    }

    /// Perimeter travel runs clockwise from the bottom-left corner: bottom, right, top, left.
    private static func position(at distance: CGFloat, in bounds: CGRect) -> CGPoint {
        let width = bounds.width
        let height = bounds.height
        let travelled = normalized(distance, around: 2 * (width + height))
        if travelled < width { return CGPoint(x: bounds.minX + travelled, y: bounds.minY) }
        if travelled < width + height {
            return CGPoint(x: bounds.maxX, y: bounds.minY + travelled - width)
        }
        if travelled < 2 * width + height {
            return CGPoint(x: bounds.maxX - (travelled - width - height), y: bounds.maxY)
        }
        return CGPoint(x: bounds.minX, y: bounds.maxY - (travelled - 2 * width - height))
    }

    private static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}
