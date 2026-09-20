import SwiftUI
struct ContentView: View {
 @ObservedObject private var themeStore=BrisaThemeStore.shared
 @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
 @ObservedObject var model: AppModel
 @State private var category="All sounds"
 @State private var search=""
 @State private var save=false
 @State private var mixName=""
 @State private var editingMix: Mix?
 @State private var showInputSounds=false
 @State private var showSettings=false
 @State private var showWelcome=false
 @State private var showImport=false
 @State private var showPomodoro=false
 @State private var relinkingSound: ImportedSound?
 let categories=["All sounds","Favorites","Noise","Water","Nature","Spaces","Imported","My mixes"]
 var filtered:[Sound] {model.availableLibrary.filter{(category=="All sounds" || category=="Favorites" && model.favorites.contains($0.id) || category==$0.category) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))}}
 func navTab(_ title:String,_ symbol:String,selected:Bool,action:@escaping()->Void)->some View {
  Button(action:action){Label(title,systemImage:symbol).font(.system(size:13,weight:.medium).monospacedDigit()).padding(.horizontal,16).padding(.vertical,7).background(selected ? accent:.clear,in:Capsule()).foregroundStyle(selected ? onAccent:.primary).contentShape(Capsule())}.buttonStyle(.plain)
 }
 var body: some View {
 ZStack {
  LinearGradient(colors:themeStore.current.background,startPoint:.topLeading,endPoint:.bottomTrailing).ignoresSafeArea()
  if !reduceTransparency {
   Circle().fill(accent.opacity(0.18*themeStore.current.glowStrength)).frame(width:500).blur(radius:100).offset(x:390,y:-300)
   Circle().fill(themeStore.current.glow.opacity(0.10*themeStore.current.glowStrength)).frame(width:430).blur(radius:100).offset(x:-420,y:330)
  }
  VStack(spacing:0){
   HStack(spacing:16){
    HStack(spacing:9){Image(systemName:"wind").font(.system(size:21,weight:.medium));Text("brisa").font(.system(size:24,weight:.semibold,design:.rounded))}.foregroundStyle(accent)
    Spacer()
    HStack(spacing:4){
     navTab("Sounds","waveform",selected:!showPomodoro){withAnimation(.easeInOut(duration:0.2)){showPomodoro=false}}
     navTab(model.isPomodoroRunning ? model.pomodoroTimeText : "Pomodoro","timer",selected:showPomodoro){withAnimation(.easeInOut(duration:0.2)){showPomodoro=true}}
    }.padding(4).background(surface.opacity(0.07),in:Capsule())
    Spacer()
    HStack(spacing:7){Image(systemName:"magnifyingglass").foregroundStyle(.secondary);TextField("Search",text:$search).textFieldStyle(.plain).frame(width:150)}.padding(.horizontal,13).padding(.vertical,9).background(surface.opacity(0.08),in:Capsule()).opacity(showPomodoro ? 0:1).allowsHitTesting(!showPomodoro).accessibilityHidden(showPomodoro)
    Menu{
     Button{showImport=true}label:{Label("Import audio…",systemImage:"square.and.arrow.down")}
     Button{showInputSounds=true}label:{Label("Interaction sounds…",systemImage:"keyboard")}
     Divider()
     Button{showSettings=true}label:{Label("Settings…",systemImage:"gearshape")}
    }label:{Image(systemName:"ellipsis").font(.system(size:14,weight:.semibold)).foregroundStyle(.primary).frame(width:34,height:34).background(surface.opacity(0.08),in:Circle())}.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help("Import audio, interaction sounds, settings")
   }.padding(.horizontal,34).padding(.top,25).padding(.bottom,18)
   if showPomodoro { PomodoroTimerView(model:model) } else {
   ScrollView(.horizontal,showsIndicators:false){
    HStack(spacing:8){ForEach(categories,id:\.self){filter in
     Button{withAnimation(.easeInOut(duration:0.2)){category=filter}}label:{HStack(spacing:6){Image(systemName:icon(filter));Text(filter);if filter=="Favorites" && !model.favorites.isEmpty {Text("\(model.favorites.count)").foregroundStyle(category==filter ? Color.black.opacity(0.55):.secondary)}}.font(.system(size:12,weight:.medium)).padding(.horizontal,13).padding(.vertical,9).background(category==filter ? accent:surface.opacity(0.07),in:Capsule()).foregroundStyle(category==filter ? onAccent:.primary)}.buttonStyle(.plain)
    }}.padding(.horizontal,34)
   }.padding(.bottom,20)
   HStack(alignment:.firstTextBaseline){VStack(alignment:.leading,spacing:4){Text(category).font(.system(size:30,weight:.semibold,design:.rounded));Text(category=="My mixes" ? "Your saved soundscapes." : "Select, combine, and tune at your own pace.").font(.system(size:13)).foregroundStyle(.secondary)};Spacer()}.padding(.horizontal,34).padding(.bottom,18)
   ScrollView {
    VStack(alignment:.leading,spacing:20){
     if category=="All sounds" && search.isEmpty {
      HStack(spacing:12){preset("Deep focus","scope",["brown":0.05,"rain":0.05]);preset("Quiet break","leaf",["ocean":0.05,"wind":0.05]);preset("Good night","moon",["pink":0.05,"night":0.05])}
     }
     if category=="My mixes" {
      if model.mixes.isEmpty{empty("Your space, your way","Add a few sounds and save your first mix.")}
      ForEach(model.mixes){mix in
       HStack(spacing:16){
        Button{
         if model.isPlaying && model.levels == mix.levels {model.isPlaying=false;model.synchronizeAudio()}
         else {model.applyMix(mix.levels)}
        }label:{
         Image(systemName:model.isPlaying && model.levels == mix.levels ? "pause.fill":"play.fill")
          .font(.system(size:15)).foregroundStyle(onAccent)
          .frame(width:40,height:40).background(accent,in:Circle())
        }.buttonStyle(.plain)
         .accessibilityLabel(model.isPlaying && model.levels == mix.levels ? "Pause \(mix.name)":"Play \(mix.name)")
        Button{model.applyMix(mix.levels)}label:{
         VStack(alignment:.leading,spacing:5){Text(mix.name).font(.system(size:15,weight:.medium));Text("\(mix.levels.count) sons").font(.caption).foregroundStyle(.secondary)}
        }.buttonStyle(.plain)
        Spacer()
        if model.isPlaying && model.levels == mix.levels {Text("Playing").font(.caption).foregroundStyle(accent)}
        Button{editingMix=mix}label:{Image(systemName:"pencil")}.buttonStyle(.borderless).accessibilityLabel("Edit \(mix.name)").help("Edit mix")
        Button{model.mixes.removeAll{$0.id==mix.id};model.persistMixes()}label:{Image(systemName:"trash")}.buttonStyle(.borderless).accessibilityLabel("Delete \(mix.name)")
       }.padding(20).background(surface.opacity(0.04),in:RoundedRectangle(cornerRadius:14))
      }
     } else {
      if filtered.isEmpty {empty("No sounds here",category=="Favorites" ? "Tap the heart to save your favorite sounds.":"Try a different search.")}
      LazyVGrid(columns:[GridItem(.adaptive(minimum:210),spacing:14)],spacing:14){ForEach(filtered){sound in card(sound)}}
     }
    }.padding(.horizontal,34).padding(.bottom,18)
   }
   }
   player.padding(.horizontal,26).padding(.bottom,22)
  }
 }.frame(minWidth:920,minHeight:640).preferredColorScheme(themeStore.current.scheme).tint(accent)
 .sheet(isPresented:$save){VStack(alignment:.leading,spacing:20){Text("Save mix").font(.title2);TextField("Mix name",text:$mixName);HStack{Button("Cancel"){save=false};Spacer();Button("Save"){model.saveMix(named:mixName.trimmingCharacters(in:.whitespaces));save=false;mixName=""}.disabled(mixName.trimmingCharacters(in:.whitespaces).isEmpty)}}.padding(30).frame(width:360)}
 .sheet(isPresented:$showSettings){BrisaWidgetSettings(model:model)}
 .sheet(isPresented:$showImport){ImportSoundsView(model:model)}
 .fileImporter(isPresented:Binding(get:{relinkingSound != nil},set:{if !$0 {relinkingSound=nil}}),allowedContentTypes:[.wav,.aiff,.mp3],allowsMultipleSelection:false){result in
  guard let sound=relinkingSound else{return}; defer{relinkingSound=nil}
  do { guard let url=try result.get().first else{return}; let accessed=url.startAccessingSecurityScopedResource(); defer{if accessed{url.stopAccessingSecurityScopedResource()}}; try model.relink(sound,to:url) }
  catch {model.error=error.localizedDescription}
 }
 .sheet(isPresented:$showInputSounds){InputSoundsView(input:model.inputSounds)}
 .sheet(isPresented:$showWelcome){WelcomeView{UserDefaults.standard.set(true,forKey:"didSeeWelcome");showWelcome=false}}
 .sheet(item:$editingMix){mix in
  MixEditor(mix:mix,sounds:model.availableLibrary){updated in
   if let index=model.mixes.firstIndex(where:{$0.id==updated.id}) {
    let wasCurrent=model.levels == model.mixes[index].levels
    model.mixes[index]=updated
    model.persistMixes()
    if wasCurrent {model.levels=updated.levels;model.synchronizeAudio()}
   }
  }
 }
 .alert("Could not start audio",isPresented:Binding(get:{model.error != nil},set:{if !$0{model.error=nil}})){Button("OK"){model.error=nil}}message:{Text(model.error ?? "")}
 .onAppear { if !UserDefaults.standard.bool(forKey:"didSeeWelcome") { showWelcome=true } }
 }
 func icon(_ c:String)->String {switch c {case "Favorites":return "heart";case "Noise":return "waveform";case "Water":return "drop";case "Nature":return "leaf";case "Spaces":return "building.2";case "Imported":return "square.and.arrow.down";case "My mixes":return "slider.horizontal.3";default:return "square.grid.2x2"}}
 func empty(_ title:String,_ detail:String)->some View {VStack(spacing:12){Image(systemName:"wind").font(.largeTitle).foregroundStyle(accent);Text(title).font(.title3);Text(detail).foregroundStyle(.secondary)}.frame(maxWidth:.infinity).padding(.vertical,70)}
 func preset(_ name:String,_ symbol:String,_ levels:[String:Double])->some View {Button{model.applyMix(levels)}label:{HStack{Image(systemName:symbol).foregroundStyle(accent);Text(name).font(.system(size:12,weight:.medium));Spacer();Image(systemName:"arrow.up.right").font(.caption).foregroundStyle(.secondary)}.padding(18).frame(maxWidth:.infinity).background(accent.opacity(0.07),in:RoundedRectangle(cornerRadius:13))}.buttonStyle(.plain)}
 func card(_ sound:Sound)->some View {
 let active=model.levels[sound.id] != nil
 return VStack(alignment:.leading,spacing:15){
  HStack{Button{model.toggle(sound.id)}label:{Image(systemName:sound.icon).font(.system(size:27,weight:.light)).foregroundStyle(active ? accent:.secondary).frame(width:44,height:38)}.buttonStyle(.plain).accessibilityLabel("Toggle \(sound.name)");Spacer();Button{model.setFavorite(sound.id)}label:{Image(systemName:model.favorites.contains(sound.id) ? "heart.fill":"heart").foregroundStyle(model.favorites.contains(sound.id) ? accent:Color.secondary)}.buttonStyle(.plain).accessibilityLabel("Favorite \(sound.name)");if let imported=model.importedSounds.first(where:{$0.id==sound.id}) {Menu { if let url=URL(string:imported.originalURL) { Button("Open source") { NSWorkspace.shared.open(url) } }; Button("Relink audio…") { relinkingSound=imported }; Button("Remove imported sound",role:.destructive){model.removeImportedSound(imported)} } label:{Image(systemName:"ellipsis.circle")}.menuStyle(.borderlessButton)}}
  Button{model.toggle(sound.id)}label:{VStack(alignment:.leading,spacing:5){Text(sound.name).font(.system(size:15,weight:.medium));Text(sound.detail).font(.system(size:11)).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain)
  HStack{if active {Slider(value:Binding(get:{model.levels[sound.id] ?? 0.5},set:{model.levels[sound.id]=$0;model.synchronizeAudio()}),in:0...1).accessibilityLabel("Volume for \(sound.name)");Text("\(Int((model.levels[sound.id] ?? 0)*100))").font(.system(size:10,design:.monospaced)).foregroundStyle(accent).frame(width:25)}else{Text("Add to mix").font(.system(size:10)).foregroundStyle(.tertiary);Spacer();Button{model.toggle(sound.id)}label:{Image(systemName:"plus.circle").foregroundStyle(.secondary)}.buttonStyle(.plain)}}.frame(height:20)
 }.padding(18).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:20)).overlay(RoundedRectangle(cornerRadius:20).fill(active ? accent.opacity(0.12):surface.opacity(0.025)).allowsHitTesting(false)).overlay(RoundedRectangle(cornerRadius:20).stroke(active ? accent.opacity(0.55):surface.opacity(0.13),lineWidth:1).allowsHitTesting(false)).shadow(color:.black.opacity(0.14),radius:14,y:7)
 }
 var player:some View {
 HStack(spacing:18){
  Button{model.togglePlayback()}label:{Image(systemName:model.isPlaying ? "pause.fill":"play.fill").font(.system(size:21,weight:.bold)).foregroundStyle(onAccent).frame(width:56,height:56).background(accent,in:Circle()).shadow(color:accent.opacity(0.35),radius:12,y:5)}.buttonStyle(.plain).keyboardShortcut(.space,modifiers:[]).accessibilityLabel(model.isPlaying ? "Pause":"Play")
  VStack(alignment:.leading,spacing:6){HStack(spacing:7){Circle().fill(model.isPlaying ? accent:Color.secondary).frame(width:7,height:7);Text(model.isPlaying ? "Now playing" : "Ready to play").font(.system(size:14,weight:.semibold))};Text("\(model.levels.count) sounds in your mix").font(.system(size:11)).foregroundStyle(.secondary)}
  Spacer(minLength:8)
  VStack(alignment:.trailing,spacing:6){HStack(spacing:8){Image(systemName:"speaker.wave.2").font(.caption).foregroundStyle(.secondary);Slider(value:$model.masterVolume,in:0...1).frame(width:130).onChange(of:model.masterVolume){_ in model.synchronizeAudio()}.accessibilityLabel("Master volume");Text("\(Int(model.masterVolume*100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width:31)};Text(model.isPomodoroRunning ? "\(model.pomodoroPhase.title) · \(model.pomodoroTimeText)" : (model.remainingSeconds>0 ? String(format:"Ends in %02d:%02d",model.remainingSeconds/60,model.remainingSeconds%60):"No timer")).font(.system(size:10)).foregroundStyle(.secondary)}
  Menu{Button("Off"){model.remainingSeconds=0;model.synchronizeAudio()};ForEach([5,15,25,30,60,90],id:\.self){m in Button("\(m) minutes"){model.remainingSeconds=m*60;model.synchronizeAudio()}}}label:{Image(systemName:"timer").font(.system(size:15,weight:.medium)).frame(width:38,height:38).background(surface.opacity(0.10),in:Circle())}.menuStyle(.borderlessButton).fixedSize()
  Button("Clear"){model.levels=[:];model.isPlaying=false;model.synchronizeAudio()}.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).disabled(model.levels.isEmpty)
  Button{save=true}label:{Image(systemName:"plus").font(.system(size:13,weight:.bold)).frame(width:38,height:38).background(accent.opacity(0.20),in:Circle())}.buttonStyle(.plain).foregroundStyle(accent).accessibilityLabel("Save mix").disabled(model.levels.isEmpty)
 }.padding(16).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:24)).overlay(RoundedRectangle(cornerRadius:24).stroke(surface.opacity(0.16),lineWidth:1).allowsHitTesting(false)).shadow(color:.black.opacity(0.22),radius:22,y:10)
 }
}
