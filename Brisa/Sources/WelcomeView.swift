import SwiftUI
struct WelcomeView: View {
 @ObservedObject private var themeStore=BrisaThemeStore.shared
 @State private var page = 0
 let finish: () -> Void
 private let pages = [
  ("wind", "A quieter space", "Build a personal soundscape for focus, rest, or sleep."),
  ("slider.horizontal.3", "Make it yours", "Mix sounds, tune every level, and save your favorite environments."),
  ("menubar.rectangle", "Always within reach", "Control Brisa from the menu bar. Keyboard sounds are optional and stay on your Mac.")
 ]
 var body: some View {
  ZStack {
   LinearGradient(colors:[themeStore.current.background[0],themeStore.current.background[1]],startPoint:.topLeading,endPoint:.bottomTrailing).ignoresSafeArea()
   Circle().fill(accent.opacity(0.24*themeStore.current.glowStrength)).frame(width:360).blur(radius:85).offset(x:150,y:-220)
   VStack(spacing:0) {
    HStack {Spacer();Button("Skip") { finish() }.buttonStyle(.plain).foregroundStyle(.secondary).padding(22)}
    let item=pages[page]
    VStack(spacing:22) {
     Image(systemName:item.0).font(.system(size:48,weight:.light)).foregroundStyle(accent).frame(width:104,height:104).background(.ultraThinMaterial,in:Circle()).overlay(Circle().stroke(surface.opacity(0.18),lineWidth:1))
     Text(item.1).font(.system(size:28,weight:.semibold,design:.rounded))
     Text(item.2).font(.system(size:15)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(width:330)
    }.id(page).transition(.opacity.combined(with:.scale(scale:0.96))).frame(height:285)
    HStack(spacing:7){ForEach(pages.indices,id:\.self){index in Circle().fill(index==page ? accent:surface.opacity(0.22)).frame(width:index==page ? 18:6,height:6)}}.padding(.bottom,28)
    Button(page == pages.count-1 ? "Start listening" : "Continue") { if page == pages.count-1 {finish()} else {withAnimation{page += 1}} }
     .buttonStyle(.plain).font(.system(size:14,weight:.semibold)).foregroundStyle(onAccent).frame(width:190,height:46).background(accent,in:Capsule()).padding(.bottom,36)
   }
  }.frame(width:500,height:470).preferredColorScheme(themeStore.current.scheme).tint(accent)
 }
}
