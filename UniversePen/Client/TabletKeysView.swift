import UIKit
import TafelKit

/// Touch keys in tablet mode (like ExpressKeys on a pen tablet). A finger on a key holds that key
/// on the Mac until it lifts; several keys at once work (e.g. Z and X in osu!). Only fingers press
/// keys – the Pencil is ignored here.
final class TabletKeysView: UIView {
    var onKey: ((String, Bool) -> Void)?
    var accent: UIColor = .white { didSet { if accent != oldValue { restyle() } } }
    var config = TabletKeys() { didSet { if config != oldValue { rebuild() } } }

    private var keyViews: [UILabel] = []
    private var frames: [CGRect] = []
    /// Which key each finger holds.
    private var held: [ObjectIdentifier: Int] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        frames = config.frames(in: bounds.size)
        for (i, v) in keyViews.enumerated() where i < frames.count { v.frame = frames[i] }
    }

    /// Only the keys take touches; everything else falls through to the canvas.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        config.enabled && frames.contains { $0.insetBy(dx: -6, dy: -6).contains(point) }
    }

    private func rebuild() {
        releaseAll()
        keyViews.forEach { $0.removeFromSuperview() }
        keyViews = config.keys.map { k in
            let l = UILabel()
            l.text = k.title
            l.textAlignment = .center
            l.font = .systemFont(ofSize: 28, weight: .bold)
            l.layer.cornerRadius = 22
            l.layer.cornerCurve = .continuous
            l.layer.borderWidth = 2
            l.clipsToBounds = true
            addSubview(l)
            return l
        }
        restyle()
        setNeedsLayout()
    }

    private func restyle() {
        let pressed = Set(held.values)
        for (i, l) in keyViews.enumerated() {
            let on = pressed.contains(i)
            l.backgroundColor = on ? accent.withAlphaComponent(0.45) : UIColor.white.withAlphaComponent(0.06)
            l.layer.borderColor = accent.withAlphaComponent(on ? 1 : 0.55).cgColor
            l.textColor = on ? .white : UIColor.white.withAlphaComponent(0.8)
        }
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches where t.type == .direct {
            let p = t.location(in: self)
            guard let i = frames.firstIndex(where: { $0.insetBy(dx: -6, dy: -6).contains(p) }), i < config.keys.count else { continue }
            held[ObjectIdentifier(t)] = i
            // Another finger already holds this key: no second "down".
            if held.values.filter({ $0 == i }).count == 1 { onKey?(config.keys[i].key, true) }
        }
        restyle()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }

    private func end(_ touches: Set<UITouch>) {
        for t in touches {
            guard let i = held.removeValue(forKey: ObjectIdentifier(t)) else { continue }
            if !held.values.contains(i), i < config.keys.count { onKey?(config.keys[i].key, false) }
        }
        restyle()
    }

    /// Lets go of every held key (mode change, disconnect).
    func releaseAll() {
        for i in Set(held.values) where i < config.keys.count { onKey?(config.keys[i].key, false) }
        held.removeAll()
        restyle()
    }
}
