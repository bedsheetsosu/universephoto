import SwiftUI
import AppKit

/// UniversePhoto's independent implementation of the Universe family surface hierarchy.
/// Reference provenance and the differences for an image editor are recorded in DESIGN.md.
struct PhotoTheme {
    /// UniversePen's accent (mint) and the presets both apps offer.
    static let mint = Color(red:0x7F/255.0,green:0xE3/255.0,blue:0xD3/255.0)
    static let accentKeys = ["mint","blue","violet","rose","amber"]
    var isDark = true
    var accent = PhotoTheme.mint
    /// Hue of the night background: like UniversePen, it sits 0.205 above the accent's hue
    /// (mint → deep indigo).
    private(set) var baseHue = 0.68
    private(set) var baseSat = 1.0
    init(isDark:Bool = true,accent:Color = PhotoTheme.mint) {
        self.isDark = isDark
        let c = NSColor(accent).usingColorSpace(.sRGB) ?? NSColor(PhotoTheme.mint)
        var h:CGFloat = 0,s:CGFloat = 0,b:CGFloat = 0,a:CGFloat = 0;c.getHue(&h,saturation:&s,brightness:&b,alpha:&a)
        baseHue = (Double(h)+0.205).truncatingRemainder(dividingBy:1)
        baseSat = s < 0.12 ? 0.25 : 1
        if !isDark { self.accent = Color(red:c.redComponent*0.68,green:c.greenComponent*0.68,blue:c.blueComponent*0.68) } else { self.accent = accent }
    }
    var accentSoft:Color { accent.opacity(isDark ? 0.16 : 0.12) }
    var text:Color { isDark ? Color.white.opacity(0.95) : Color(hue:baseHue,saturation:0.55*baseSat,brightness:0.22) }
    var secondary:Color { text.opacity(isDark ? 0.62 : 0.65) }
    /// UniversePen's deepest slate; also the text colour on accent fills.
    var onAccent:Color { Color(hue:baseHue,saturation:0.7*baseSat,brightness:0.11) }
    var deep:Color { isDark ? onAccent : Color(hue:baseHue,saturation:0.08*baseSat,brightness:0.93) }
    var card:Color { isDark ? Color.white.opacity(0.06) : Color.white.opacity(0.56) }
    var outline:Color { isDark ? Color.white.opacity(0.09) : Color(hue:baseHue,saturation:0.5,brightness:0.3).opacity(0.12) }
    var canvas:Color { isDark ? Color(hue:baseHue,saturation:0.45*baseSat,brightness:0.09) : Color(hue:baseHue,saturation:0.05,brightness:0.8) }
    var accentBright:Color { let c = NSColor(accent).usingColorSpace(.sRGB) ?? NSColor(PhotoTheme.mint);return Color(red:(c.redComponent+1)/2,green:(c.greenComponent+1)/2,blue:(c.blueComponent+1)/2) }
    /// Fill of anything that is "on" (UltraUI's accentFill: bright at the top).
    var accentGradient:LinearGradient { LinearGradient(colors:[accentBright,accent],startPoint:.top,endPoint:.bottom) }
    var edge:LinearGradient { LinearGradient(colors:[.white.opacity(isDark ? 0.30 : 0.8),.white.opacity(0.05),.white.opacity(isDark ? 0.14 : 0.4)],startPoint:.topLeading,endPoint:.bottomTrailing) }
    /// UniversePen's background: indigo top, slate middle, near-black deep.
    var background:LinearGradient {
        let colors = isDark ? [Color(hue:baseHue,saturation:0.62*baseSat,brightness:0.48),Color(hue:baseHue,saturation:0.64*baseSat,brightness:0.25),Color(hue:baseHue,saturation:0.7*baseSat,brightness:0.11)] : [Color(hue:baseHue,saturation:0.06,brightness:0.98),Color(hue:baseHue,saturation:0.09,brightness:0.94),Color(hue:baseHue,saturation:0.13,brightness:0.88)]
        return LinearGradient(colors:colors,startPoint:.topLeading,endPoint:.bottomTrailing)
    }
    /// The same presets as UniversePen (hex 7FE3D3, 7CC4FF, C08BFF, FF7EB6, FFC46B).
    static func accent(_ key:String)->Color {
        switch key { case "blue":Color(red:0x7C/255.0,green:0xC4/255.0,blue:1);case "violet":Color(red:0xC0/255.0,green:0x8B/255.0,blue:1);case "rose":Color(red:1,green:0x7E/255.0,blue:0xB6/255.0);case "amber":Color(red:1,green:0xC4/255.0,blue:0x6B/255.0);default:mint }
    }
}
private struct PhotoThemeKey:EnvironmentKey { static let defaultValue = PhotoTheme() }
extension EnvironmentValues { var photoTheme:PhotoTheme { get { self[PhotoThemeKey.self] } set { self[PhotoThemeKey.self] = newValue } } }
enum PhotoMotion { static var select:Animation { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .easeInOut(duration:0.15) : .spring(response:0.29,dampingFraction:0.88) };static var panel:Animation { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .easeInOut(duration:0.2) : .spring(response:0.42,dampingFraction:0.9) } }
struct PhotoAmbient:View {
    @Environment(\.photoTheme) private var theme
    var body:some View { GeometryReader { g in ZStack { theme.background;RadialGradient(colors:[theme.accent.opacity(theme.isDark ? 0.13 : 0.10),.clear],center:.topLeading,startRadius:0,endRadius:g.size.width*0.65);RadialGradient(colors:[Color(red:0xC0/255.0,green:0x8B/255.0,blue:1).opacity(theme.isDark ? 0.12 : 0.09),.clear],center:.bottomTrailing,startRadius:0,endRadius:g.size.width*0.6) } }.allowsHitTesting(false) }
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
        var body:some View { label.font(.system(size:compact ? 11 : 13,weight:.semibold,design:.rounded)).padding(.horizontal,compact ? 12 : 18).padding(.vertical,compact ? 7 : 10).foregroundStyle(prominent ? theme.onAccent : theme.text).background { if prominent { Capsule().fill(theme.accentGradient) } else { Capsule().fill(theme.text.opacity(hover ? 0.12 : 0.065)) } }.overlay(Capsule().strokeBorder(prominent ? .white.opacity(0.45) : theme.outline,lineWidth:0.75)).shadow(color:prominent ? theme.accent.opacity(0.18) : .clear,radius:8,y:3).contentShape(Capsule()).scaleEffect(pressed ? 0.97 : 1).opacity(enabled ? 1 : 0.35).onHover { hover = $0 }.animation(PhotoMotion.select,value:pressed).animation(PhotoMotion.select,value:hover) }
    }
}
struct PhotoMark:View {
    @Environment(\.photoTheme) var theme
    var body:some View { ZStack { RoundedRectangle(cornerRadius:10,style:.continuous).fill(theme.accentGradient);Ellipse().stroke(theme.onAccent.opacity(0.8),lineWidth:1.3).frame(width:27,height:13).rotationEffect(.degrees(-35));Circle().fill(.white.opacity(0.92)).frame(width:11,height:11);Circle().fill(theme.onAccent).frame(width:4,height:4).offset(x:11,y:-8) }.frame(width:35,height:35).overlay(RoundedRectangle(cornerRadius:10).strokeBorder(.white.opacity(0.4),lineWidth:0.7)).shadow(color:theme.accent.opacity(0.2),radius:8,y:3) }
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
