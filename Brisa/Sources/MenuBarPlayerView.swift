import SwiftUI
import AppKit
struct MenuBarPlayerView: View {
 @Environment(\.openWindow) private var openWindow
 @ObservedObject var model: AppModel
 var body: some View {
  VStack(spacing:16){
   HStack(spacing:11){
    Image(systemName:"wind").font(.system(size:17,weight:.semibold)).foregroundStyle(accent).frame(width:34,height:34).background(accent.opacity(0.16),in:Circle())
    VStack(alignment:.leading,spacing:2){Text("brisa").font(.system(size:15,weight:.semibold,design:.rounded));Text(model.isPlaying ? "Now playing" : "Paused").font(.system(size:10,weight:.medium)).foregroundStyle(model.isPlaying ? accent:.secondary)}
    Spacer()
    Button{BrisaWindowActions.showInDock();openWindow(id:"main")}label:{Image(systemName:"arrow.up.left.and.arrow.down.right").font(.caption).frame(width:28,height:28).background(.white.opacity(0.08),in:Circle())}.buttonStyle(.plain).help("Open Brisa")
   }
   VStack(alignment:.leading,spacing:5){Text(model.nowPlayingTitle).font(.system(size:16,weight:.medium)).lineLimit(1);Text("\(model.levels.count) sounds in your mix").font(.system(size:11)).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,alignment:.leading)
   TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !model.isPlaying)) { timeline in
    Canvas { context, size in
     let phase = model.isPlaying ? timeline.date.timeIntervalSinceReferenceDate * 0.8 : 0
     for layer in 0..<7 {
      var path = Path()
      for step in 0...80 {
       let t = Double(step) / 80
       let wave = sin(t * .pi * 3.2 + phase + Double(layer) * 0.18) * 0.30
       let y = size.height * (0.5 + wave) + Double(layer - 3) * 2.1
       let point = CGPoint(x: t * size.width, y: y)
       if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
      }
      context.stroke(path, with: .color(accent.opacity(model.isPlaying ? 0.22 : 0.08)), lineWidth: 0.8)
     }
    }
   }.frame(height:44).background(accent.opacity(0.05),in:RoundedRectangle(cornerRadius:12)).clipShape(RoundedRectangle(cornerRadius:12)).accessibilityHidden(true)
   HStack(spacing:12){
    Button{model.togglePlayback()}label:{Image(systemName:model.isPlaying ? "pause.fill":"play.fill").font(.system(size:15,weight:.bold)).foregroundStyle(Color.black.opacity(0.8)).frame(width:42,height:42).background(accent,in:Circle())}.buttonStyle(.plain).accessibilityLabel(model.isPlaying ? "Pause":"Play")
    Button{model.toggleMute()}label:{Image(systemName:model.masterVolume == 0 ? "speaker.slash.fill":"speaker.wave.2.fill").font(.system(size:14)).frame(width:34,height:34).background(.white.opacity(0.09),in:Circle())}.buttonStyle(.plain).accessibilityLabel(model.masterVolume == 0 ? "Unmute":"Mute")
    Slider(value:$model.masterVolume,in:0...1).frame(width:116).onChange(of:model.masterVolume){_ in model.synchronizeAudio()}.accessibilityLabel("Master volume")
    Text("\(Int(model.masterVolume*100))%").font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary).frame(width:27)
   }
   Button("Clear") { model.levels=[:]; model.isPlaying=false; model.synchronizeAudio() }
    .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(accent).disabled(model.levels.isEmpty)
   Divider().overlay(.white.opacity(0.16))
   HStack{Text("Switch sound").font(.system(size:12,weight:.medium));Spacer();Menu{ForEach(library){sound in Button{model.replaceWith(sound)}label:{Label(sound.name,systemImage:sound.icon)}}}label:{HStack(spacing:5){Text("Choose");Image(systemName:"chevron.up.chevron.down").font(.caption2)}.font(.system(size:12,weight:.medium)).foregroundStyle(accent).padding(.horizontal,11).padding(.vertical,7).background(accent.opacity(0.15),in:Capsule())}.menuStyle(.borderlessButton).fixedSize()}
   ScrollView(.horizontal,showsIndicators:false){HStack(spacing:7){ForEach(library.prefix(6)){sound in Button{model.replaceWith(sound)}label:{Image(systemName:sound.icon).font(.system(size:14)).frame(width:35,height:35).background(model.levels[sound.id] != nil ? accent.opacity(0.24):.white.opacity(0.07),in:RoundedRectangle(cornerRadius:11))}.buttonStyle(.plain).help(sound.name)}}}
   HStack{Menu{Button("Off"){model.remainingSeconds=0;model.synchronizeAudio()};ForEach([5,15,25,30,60],id:\.self){minutes in Button("\(minutes) minutes"){model.remainingSeconds=minutes*60;model.synchronizeAudio()}}}label:{Label(model.remainingSeconds > 0 ? String(format:"%02d:%02d",model.remainingSeconds/60,model.remainingSeconds%60):"Timer",systemImage:"timer")}.menuStyle(.borderlessButton).font(.system(size:11)).foregroundStyle(.secondary);Spacer()}
   Divider().overlay(.white.opacity(0.16))
   Button("Quit Brisa Completely") { NSApp.terminate(nil) }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(.red)
  }.padding(18).frame(width:325).background(.ultraThinMaterial).preferredColorScheme(.dark).tint(accent)
 }
}
