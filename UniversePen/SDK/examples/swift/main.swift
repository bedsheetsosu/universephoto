// UniversePen SDK example (MIT): add UniversePenKit as a package dependency, then:
import UniversePenKit

let pen = UniversePen()
try await pen.connect()
print(try await pen.status())
try await pen.setAppProfile(bundleID: "com.seriflabs.affinityphoto2", name: "Affinity Photo", buttons: [
    ["title": "Undo", "key": "z", "modifiers": ["cmd"]],
    ["title": "Brush", "key": "b"],
    ["title": "⇧", "hold": "shift"],
])
try await pen.subscribeInput()
for await s in pen.penSamples() where s.phase == "move" {
    print(String(format: "%.2f  tilt %.2f/%.2f", s.pressure, s.tiltX, s.tiltY))
}
