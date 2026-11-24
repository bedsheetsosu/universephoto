import TafelKit

extension IPadTool {
    var symbol: String {
        switch self {
        case .ruler: return "ruler"
        case .perspective1, .perspective2, .perspective3: return "perspective"
        case .ellipse: return "oval"
        case .shapeRecognition: return "scribble.variable"
        case .laser: return "light.beacon.max"
        case .screenshot: return "camera.viewfinder"
        case .palette: return "square.on.square.dashed"
        case .mirror: return "arrow.left.and.right.righttriangle.left.righttriangle.right"
        case .grayscale: return "circle.lefthalf.filled"
        case .grid: return "grid"
        case .rope: return "lasso"
        case .fixedPressure: return "lineweight"
        case .speedPressure: return "hare"
        }
    }
}
