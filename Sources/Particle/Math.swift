import CoreGraphics

extension CGVector {
    static var zero: CGVector { CGVector(dx: 0, dy: 0) }

    static func + (l: CGVector, r: CGVector) -> CGVector { CGVector(dx: l.dx + r.dx, dy: l.dy + r.dy) }
    static func - (l: CGVector, r: CGVector) -> CGVector { CGVector(dx: l.dx - r.dx, dy: l.dy - r.dy) }
    static func * (l: CGVector, r: CGFloat)  -> CGVector { CGVector(dx: l.dx * r,    dy: l.dy * r) }
    static func += (l: inout CGVector, r: CGVector) { l = l + r }
    static prefix func - (v: CGVector) -> CGVector { CGVector(dx: -v.dx, dy: -v.dy) }

    var magnitude: CGFloat { sqrt(dx*dx + dy*dy) }

    func normalized() -> CGVector {
        let m = magnitude
        guard m > 0 else { return .zero }
        return CGVector(dx: dx/m, dy: dy/m)
    }

    func limited(to max: CGFloat) -> CGVector {
        magnitude > max ? normalized() * max : self
    }

    func clamped(min minMag: CGFloat, max maxMag: CGFloat) -> CGVector {
        let m = magnitude
        if m < minMag { return normalized() * minMag }
        if m > maxMag { return normalized() * maxMag }
        return self
    }
}

extension String {
    func leftPad(toLength length: Int) -> String {
        count >= length ? self : String(repeating: " ", count: length - count) + self
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        sqrt((x - other.x)*(x - other.x) + (y - other.y)*(y - other.y))
    }
    static func + (p: CGPoint, v: CGVector) -> CGPoint { CGPoint(x: p.x + v.dx, y: p.y + v.dy) }
    static func - (a: CGPoint, b: CGPoint) -> CGVector { CGVector(dx: a.x - b.x, dy: a.y - b.y) }
}
