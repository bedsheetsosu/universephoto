import SwiftUI
import AppKit

/// UniversePhoto's independent implementation of the Universe family surface hierarchy.
/// Reference provenance and the differences for an image editor are recorded in DESIGN.md.
struct PhotoTheme {
    var isDark = true
    var accent = Color(red:1,green:0.57,blue:0.74)
    init(isDark:Bool = true,accent:Color = Color(red:1,green:0.57,blue:0.74)) {
        self.isDark = isDark
        if !isDark,let c = NSColor(accent).usingColorSpace(.sRGB) { self.accent = Color(red:c.redComponent*0.68,green:c.greenComponent*0.68,blue:c.blueComponent*0.68) } else { self.accent = accent }
    }
    var accentSoft:Color { accent.opacity(isDark ? 0.16 : 0.12) }
    var text:Color { isDark ? Color(red:0.97,green:0.94,blue:0.98) : Color(red:0.2,green:0.15,blue:0.26) }
    var secondary:Color { text.opacity(isDark ? 0.62 : 0.65) }
    var deep:Color { isDark ? Color(red:0.09,green:0.065,blue:0.135) : Color(red:0.91,green:0.87,blue:0.93) }
    var card:Color { isDark ? Color.white.opacity(0.045) : Color.white.opacity(0.56) }
    var outline:Color { isDark ? Color.white.opacity(0.09) : Color(red:0.3,green:0.2,blue:0.4).opacity(0.12) }
    var canvas:Color { isDark ? Color(red:0.095,green:0.085,blue:0.12) : Color(red:0.78,green:0.76,blue:0.81) }
    var accentBright:Color { let c = NSColor(accent).usingColorSpace(.sRGB) ?? .systemPink;return Color(red:(c.redComponent+1)/2,green:(c.greenComponent+1)/2,blue:(c.blueComponent+1)/2) }
    var accentGradient:LinearGradient { LinearGradient(colors:[accentBright,accent],startPoint:.topLeading,endPoint:.bottomTrailing) }
    var edge:LinearGradient { LinearGradient(colors:[.white.opacity(isDark ? 0.27 : 0.8),.white.opacity(0.035),.white.opacity(isDark ? 0.10 : 0.4)],startPoint:.topLeading,endPoint:.bottomTrailing) }
    var background:LinearGradient {
        // Separate warm rose light, plum middle and ink base; accent softly changes their hue.
        let c = NSColor(accent).usingColorSpace(.deviceRGB) ?? .systemPink
        var h:CGFloat = 0,s:CGFloat = 0,b:CGFloat = 0,a:CGFloat = 0;c.getHue(&h,saturation:&s,brightness:&b,alpha:&a)
        let base = 0.78 + (Double(h)-0.92)*0.10
        let colors = isDark ? [Color(hue:base+0.055,saturation:0.36,brightness:0.32),Color(hue:base,saturation:0.38,brightness:0.20),Color(hue:base-0.025,saturation:0.42,brightness:0.095)] : [Color(hue:base,saturation:0.065,brightness:0.98),Color(hue:base,saturation:0.09,brightness:0.94),Color(hue:base,saturation:0.13,brightness:0.88)]
        return LinearGradient(colors:colors,startPoint:.topLeading,endPoint:.bottomTrailing)
    }
    static func accent(_ key:String)->Color {
        switch key { case "mint":Color(red:0.50,green:0.89,blue:0.83);case "blue":Color(red:0.49,green:0.77,blue:1);case "violet":Color(red:0.75,green:0.55,blue:1);case "amber":Color(red:1,green:0.77,blue:0.42);default:Color(red:1,green:0.55,blue:0.72) }
    }
}
private struct PhotoThemeKey:EnvironmentKey { static let defaultValue = PhotoTheme() }
extension EnvironmentValues { var photoTheme:PhotoTheme { get { self[PhotoThemeKey.self] } set { self[PhotoThemeKey.self] = newValue } } }
enum PhotoMotion { static var select:Animation { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .easeInOut(duration:0.15) : .spring(response:0.29,dampingFraction:0.88) };static var panel:Animation { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .easeInOut(duration:0.2) : .spring(response:0.42,dampingFraction:0.9) } }
struct PhotoAmbient:View {
    @Environment(\.photoTheme) private var theme
    var body:some View { GeometryReader { g in ZStack { theme.background;RadialGradient(colors:[theme.accent.opacity(theme.isDark ? 0.13 : 0.10),.clear],center:.topLeading,startRadius:0,endRadius:g.size.width*0.65);RadialGradient(colors:[Color(red:0.61,green:0.43,blue:0.9).opacity(theme.isDark ? 0.12 : 0.09),.clear],center:.bottomTrailing,startRadius:0,endRadius:g.size.width*0.6) } }.allowsHitTesting(false) }
}
private struct PhotoSurface:ViewModifier {
    @Environment(\.photoTheme) var theme
    var radius:CGFloat;var elevated:Bool
    func body(content:Content)->some View { let shape = RoundedRectangle(cornerRadius:radius,style:.continuous);content.background { ZStack { shape.fill(theme.deep.opacity(theme.isDark ? 0.45 : 0.22));shape.fill(.ultraThinMaterial).opacity(theme.isDark ? 0.42 : 0.65);shape.fill(LinearGradient(colors:[.white.opacity(theme.isDark ? 0.035 : 0.3),.clear],startPoint:.topLeading,endPoint:.bottomTrailing)) } }.overlay(shape.strokeBorder(theme.edge.opacity(elevated ? 0.8 : 0.5),lineWidth:0.75)).clipShape(shape).shadow(color:.black.opacity(theme.isDark ? (elevated ? 0.22 : 0.1) : 0.06),radius:elevated ? 18 : 8,x:0,y:elevated ? 8 : 3) }
}
extension View {
    func photoSurface(radius:CGFloat = 18,elevated:Bool = false)->some View { modifier(PhotoSurface(radius:radius,elevated:elevated)) }
    func photoCard(padding:CGFloat = 14)->some View { self.padding(padding).frame(maxWidth:.infinity,alignment:.leading).modifier(PhotoCardSurface()) }
}
private struct PhotoCardSurface:ViewModifier { @Environment(\.photoTheme) var theme;func body(content:Content)->some View { let shape = RoundedRectangle(cornerRadius:16,style:.continuous);content.background(theme.card,in:shape).overlay(shape.strokeBorder(theme.edge.opacity(0.32),lineWidth:0.7)) } }
struct PhotoPress:ButtonStyle { func makeBody(configuration:Configuration)->some View { configuration.label.scaleEffect(configuration.isPressed ? 0.97 : 1).brightness(configuration.isPressed ? 0.05 : 0).animation(PhotoMotion.select,value:configuration.isPressed) } }
struct PhotoButtonStyle:ButtonStyle {
    var prominent = false;var compact = true
    func makeBody(configuration:Configuration)->some View { Body(label:configuration.label,pressed:configuration.isPressed,prominent:prominent,compact:compact) }
    private struct Body<Label:View>:View { @Environment(\.photoTheme) var theme;@Environment(\.isEnabled) var enabled;var label:Label;var pressed:Bool;var prominent:Bool;var compact:Bool;@State var hover = false
        var body:some View { label.font(.system(size:compact ? 11 : 13,weight:.semibold,design:.rounded)).padding(.horizontal,compact ? 12 : 18).padding(.vertical,compact ? 7 : 10).foregroundStyle(prominent ? Color(red:0.18,green:0.10,blue:0.22) : theme.text).background { if prominent { Capsule().fill(theme.accentGradient) } else { Capsule().fill(theme.text.opacity(hover ? 0.12 : 0.065)) } }.overlay(Capsule().strokeBorder(prominent ? .white.opacity(0.45) : theme.outline,lineWidth:0.75)).shadow(color:prominent ? theme.accent.opacity(0.18) : .clear,radius:8,y:3).contentShape(Capsule()).scaleEffect(pressed ? 0.97 : 1).opacity(enabled ? 1 : 0.35).onHover { hover = $0 }.animation(PhotoMotion.select,value:pressed).animation(PhotoMotion.select,value:hover) }
    }
}
struct PhotoMark:View {
    @Environment(\.photoTheme) var theme
    var body:some View { ZStack { RoundedRectangle(cornerRadius:10,style:.continuous).fill(theme.accentGradient);Ellipse().stroke(Color(red:0.2,green:0.1,blue:0.3).opacity(0.8),lineWidth:1.3).frame(width:27,height:13).rotationEffect(.degrees(-35));Circle().fill(.white.opacity(0.92)).frame(width:11,height:11);Circle().fill(Color(red:0.28,green:0.14,blue:0.34)).frame(width:4,height:4).offset(x:11,y:-8) }.frame(width:35,height:35).overlay(RoundedRectangle(cornerRadius:10).strokeBorder(.white.opacity(0.4),lineWidth:0.7)).shadow(color:theme.accent.opacity(0.2),radius:8,y:3) }
}

/// Native glass is reserved for chrome over the stationary family background.
/// The document surface uses PhotoSurface so its contrast stays stable over changing artwork.
private struct PhotoChrome:ViewModifier {
    @Environment(\.photoTheme) var theme
    var radius:CGFloat
    @ViewBuilder func body(content:Content)->some View {
        let shape = RoundedRectangle(cornerRadius:radius,style:.continuous)
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.tint(theme.deep.opacity(theme.isDark ? 0.44 : 0.16)),in:shape)
                .overlay(shape.strokeBorder(theme.edge.opacity(0.6),lineWidth:0.65))
                .shadow(color:.black.opacity(theme.isDark ? 0.18 : 0.06),radius:16,y:7)
        } else { content.photoSurface(radius:radius,elevated:true) }
    }
}
extension View { func photoChrome(radius:CGFloat = 20)->some View { modifier(PhotoChrome(radius:radius)) } }
