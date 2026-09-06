import SwiftUI
struct ContentView: View {
 @ObservedObject var model: AppModel
 @State private var category="All sounds"
 @State private var search=""
 @State private var save=false
 @State private var mixName=""
 @State private var editingMix: Mix?
 @State private var showInputSounds=false
 @State private var showWelcome=false
 let categories=["All sounds","Favorites","Noise","Water","Nature","Spaces","My mixes"]
 var filtered:[Sound] {library.filter{(category=="All sounds" || category=="Favorites" && model.favorites.contains($0.id) || category==$0.category) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))}}
 var body: some View {
 ZStack {
  LinearGradient(colors:[Color(red:0.045,green:0.065,blue:0.07),Color(red:0.08,green:0.115,blue:0.105),Color(red:0.045,green:0.055,blue:0.06)],startPoint:.topLeading,endPoint:.bottomTrailing).ignoresSafeArea()
  Circle().fill(accent.opacity(0.18)).frame(width:500).blur(radius:100).offset(x:390,y:-300)
  Circle().fill(Color.cyan.opacity(0.10)).frame(width:430).blur(radius:100).offset(x:-420,y:330)
  VStack(spacing:0){
   HStack(spacing:16){
    HStack(spacing:9){Image(systemName:"wind").font(.system(size:21,weight:.medium));Text("brisa").font(.system(size:24,weight:.semibold,design:.rounded))}.foregroundStyle(accent)
    Spacer()
    Button{showInputSounds=true}label:{Label("Interaction sounds",systemImage:"keyboard").font(.system(size:12,weight:.medium)).padding(.horizontal,13).padding(.vertical,9).background(.white.opacity(0.08),in:Capsule())}.buttonStyle(.plain)
    HStack(spacing:7){Image(systemName:"magnifyingglass").foregroundStyle(.secondary);TextField("Search",text:$search).textFieldStyle(.plain).frame(width:150)}.padding(.horizontal,13).padding(.vertical,9).background(.white.opacity(0.08),in:Capsule())
   }.padding(.horizontal,34).padding(.top,25).padding(.bottom,18)
   ScrollView(.horizontal,showsIndicators:false){
    HStack(spacing:8){ForEach(categories,id:\.self){filter in
     Button{withAnimation(.easeInOut(duration:0.2)){category=filter}}label:{HStack(spacing:6){Image(systemName:icon(filter));Text(filter);if filter=="Favorites" && !model.favorites.isEmpty {Text("\(model.favorites.count)").foregroundStyle(category==filter ? Color.black.opacity(0.55):.secondary)}}.font(.system(size:12,weight:.medium)).padding(.horizontal,13).padding(.vertical,9).background(category==filter ? accent:.white.opacity(0.07),in:Capsule()).foregroundStyle(category==filter ? Color.black.opacity(0.82):.primary)}.buttonStyle(.plain)
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
          .font(.system(size:15)).foregroundStyle(Color.black.opacity(0.8))
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
       }.padding(20).background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:14))
      }
     } else {
      if filtered.isEmpty {empty("No sounds here",category=="Favorites" ? "Tap the heart to save your favorite sounds.":"Try a different search.")}
      LazyVGrid(columns:[GridItem(.adaptive(minimum:210),spacing:14)],spacing:14){ForEach(filtered){sound in card(sound)}}
     }
    }.padding(.horizontal,34).padding(.bottom,18)
   }
   player.padding(.horizontal,26).padding(.bottom,22)
  }
 }.frame(minWidth:920,minHeight:640).preferredColorScheme(.dark).tint(accent)
 .sheet(isPresented:$save){VStack(alignment:.leading,spacing:20){Text("Save mix").font(.title2);TextField("Mix name",text:$mixName);HStack{Button("Cancel"){save=false};Spacer();Button("Save"){model.saveMix(named:mixName.trimmingCharacters(in:.whitespaces));save=false;mixName=""}.disabled(mixName.trimmingCharacters(in:.whitespaces).isEmpty)}}.padding(30).frame(width:360)}
 .sheet(isPresented:$showInputSounds){InputSoundsView(input:model.inputSounds)}
 .sheet(isPresented:$showWelcome){WelcomeView{UserDefaults.standard.set(true,forKey:"didSeeWelcome");showWelcome=false}}
 .sheet(item:$editingMix){mix in
  MixEditor(mix:mix){updated in
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
 func icon(_ c:String)->String {switch c {case "Favorites":return "heart";case "Noise":return "waveform";case "Water":return "drop";case "Nature":return "leaf";case "Spaces":return "building.2";case "My mixes":return "slider.horizontal.3";default:return "square.grid.2x2"}}
 func empty(_ title:String,_ detail:String)->some View {VStack(spacing:12){Image(systemName:"wind").font(.largeTitle).foregroundStyle(accent);Text(title).font(.title3);Text(detail).foregroundStyle(.secondary)}.frame(maxWidth:.infinity).padding(.vertical,70)}
 func preset(_ name:String,_ symbol:String,_ levels:[String:Double])->some View {Button{model.applyMix(levels)}label:{HStack{Image(systemName:symbol).foregroundStyle(accent);Text(name).font(.system(size:12,weight:.medium));Spacer();Image(systemName:"arrow.up.right").font(.caption).foregroundStyle(.secondary)}.padding(18).frame(maxWidth:.infinity).background(accent.opacity(0.07),in:RoundedRectangle(cornerRadius:13))}.buttonStyle(.plain)}
 func card(_ sound:Sound)->some View {
 let active=model.levels[sound.id] != nil
 return VStack(alignment:.leading,spacing:15){
  HStack{Button{model.toggle(sound.id)}label:{Image(systemName:sound.icon).font(.system(size:27,weight:.light)).foregroundStyle(active ? accent:.secondary).frame(width:44,height:38)}.buttonStyle(.plain).accessibilityLabel("Toggle \(sound.name)");Spacer();Button{model.setFavorite(sound.id)}label:{Image(systemName:model.favorites.contains(sound.id) ? "heart.fill":"heart").foregroundStyle(model.favorites.contains(sound.id) ? accent:Color.secondary)}.buttonStyle(.plain).accessibilityLabel("Favorite \(sound.name)")}
  Button{model.toggle(sound.id)}label:{VStack(alignment:.leading,spacing:5){Text(sound.name).font(.system(size:15,weight:.medium));Text(sound.detail).font(.system(size:11)).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain)
  HStack{if active {Slider(value:Binding(get:{model.levels[sound.id] ?? 0.5},set:{model.levels[sound.id]=$0;model.synchronizeAudio()}),in:0...1).accessibilityLabel("Volume for \(sound.name)");Text("\(Int((model.levels[sound.id] ?? 0)*100))").font(.system(size:10,design:.monospaced)).foregroundStyle(accent).frame(width:25)}else{Text("Add to mix").font(.system(size:10)).foregroundStyle(.tertiary);Spacer();Button{model.toggle(sound.id)}label:{Image(systemName:"plus.circle").foregroundStyle(.secondary)}.buttonStyle(.plain)}}.frame(height:20)
 }.padding(18).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:20)).overlay(RoundedRectangle(cornerRadius:20).fill(active ? accent.opacity(0.12):.white.opacity(0.025)).allowsHitTesting(false)).overlay(RoundedRectangle(cornerRadius:20).stroke(active ? accent.opacity(0.55):.white.opacity(0.13),lineWidth:1).allowsHitTesting(false)).shadow(color:.black.opacity(0.14),radius:14,y:7)
 }
 var player:some View {
 HStack(spacing:18){
  Button{model.togglePlayback()}label:{Image(systemName:model.isPlaying ? "pause.fill":"play.fill").font(.system(size:21,weight:.bold)).foregroundStyle(Color.black.opacity(0.78)).frame(width:56,height:56).background(accent,in:Circle()).shadow(color:accent.opacity(0.35),radius:12,y:5)}.buttonStyle(.plain).keyboardShortcut(.space,modifiers:[]).accessibilityLabel(model.isPlaying ? "Pause":"Play")
  VStack(alignment:.leading,spacing:6){HStack(spacing:7){Circle().fill(model.isPlaying ? accent:Color.secondary).frame(width:7,height:7);Text(model.isPlaying ? "Now playing" : "Ready to play").font(.system(size:14,weight:.semibold))};Text("\(model.levels.count) sounds in your mix").font(.system(size:11)).foregroundStyle(.secondary)}
  Spacer(minLength:8)
  VStack(alignment:.trailing,spacing:6){HStack(spacing:8){Image(systemName:"speaker.wave.2").font(.caption).foregroundStyle(.secondary);Slider(value:$model.masterVolume,in:0...1).frame(width:130).onChange(of:model.masterVolume){_ in model.synchronizeAudio()}.accessibilityLabel("Master volume");Text("\(Int(model.masterVolume*100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width:31)};Text(model.remainingSeconds>0 ? String(format:"Ends in %02d:%02d",model.remainingSeconds/60,model.remainingSeconds%60):"No timer").font(.system(size:10)).foregroundStyle(.secondary)}
  Menu{Button("Off"){model.remainingSeconds=0;model.synchronizeAudio()};ForEach([5,15,25,30,60,90],id:\.self){m in Button("\(m) minutes"){model.remainingSeconds=m*60;model.synchronizeAudio()}}}label:{Image(systemName:"timer").font(.system(size:15,weight:.medium)).frame(width:38,height:38).background(.white.opacity(0.10),in:Circle())}.menuStyle(.borderlessButton).fixedSize()
  Button("Clear"){model.levels=[:];model.isPlaying=false;model.synchronizeAudio()}.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).disabled(model.levels.isEmpty)
  Button{save=true}label:{Image(systemName:"plus").font(.system(size:13,weight:.bold)).frame(width:38,height:38).background(accent.opacity(0.20),in:Circle())}.buttonStyle(.plain).foregroundStyle(accent).accessibilityLabel("Save mix").disabled(model.levels.isEmpty)
 }.padding(16).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:24)).overlay(RoundedRectangle(cornerRadius:24).stroke(.white.opacity(0.16),lineWidth:1).allowsHitTesting(false)).shadow(color:.black.opacity(0.22),radius:22,y:10)
 }
}
