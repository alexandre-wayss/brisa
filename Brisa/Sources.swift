import SwiftUI
import AVFoundation
import AppKit
import ApplicationServices
import Carbon

struct Sound: Identifiable {
 let id: String; let name: String; let icon: String; let category: String; let detail: String
}
let library: [Sound] = [
 .init(id:"white",name:"White Noise",icon:"waveform",category:"Noise",detail:"Even and immersive"),
 .init(id:"pink",name:"Pink Noise",icon:"waveform.path",category:"Noise",detail:"Soft and balanced"),
 .init(id:"brown",name:"Brown Noise",icon:"waveform.path.ecg",category:"Noise",detail:"Low and deep"),
 .init(id:"green",name:"Green Noise",icon:"leaf",category:"Noise",detail:"Gentle mid frequencies"),
 .init(id:"grey",name:"Grey Noise",icon:"aqi.medium",category:"Noise",detail:"Wide filtered texture"),
 .init(id:"rain",name:"Light Rain",icon:"cloud.drizzle",category:"Water",detail:"A quiet afternoon"),
 .init(id:"heavy",name:"Heavy Rain",icon:"cloud.rain",category:"Water",detail:"Rain in every direction"),
 .init(id:"tent",name:"Rain on a Tent",icon:"tent",category:"Water",detail:"A small shelter"),
 .init(id:"thunder",name:"Distant Thunder",icon:"cloud.bolt.rain",category:"Water",detail:"Deep rolling echoes"),
 .init(id:"creek",name:"Creek",icon:"water.waves",category:"Water",detail:"Moving water"),
 .init(id:"ocean",name:"Ocean Waves",icon:"water.waves",category:"Water",detail:"Breathe with the tide"),
 .init(id:"waterfall",name:"Waterfall",icon:"drop.fill",category:"Water",detail:"A continuous flow"),
 .init(id:"wind",name:"Wind in Leaves",icon:"wind",category:"Nature",detail:"A passing breeze"),
 .init(id:"fire",name:"Fireplace",icon:"flame",category:"Nature",detail:"Warmth and quiet crackles"),
 .init(id:"night",name:"Night Field",icon:"moon.stars",category:"Nature",detail:"Crickets in the distance"),
 .init(id:"birds",name:"Sunrise",icon:"bird",category:"Nature",detail:"Delicate birdsong"),
 .init(id:"fan",name:"Fan",icon:"fan",category:"Spaces",detail:"Steady comfort"),
 .init(id:"cabin",name:"Airplane Cabin",icon:"airplane",category:"Spaces",detail:"A calm journey"),
 .init(id:"train",name:"Train",icon:"tram",category:"Spaces",detail:"Rhythm on the rails"),
 .init(id:"keyboard",name:"Keyboard",icon:"keyboard",category:"Spaces",detail:"Small rhythmic taps")
]
struct Mix: Codable, Identifiable { var id = UUID(); var name: String; var levels: [String: Double] }

func loadRecording(_ url:URL) throws -> AVAudioPCMBuffer {
 let file=try AVAudioFile(forReading:url)
 let buffer=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:AVAudioFrameCount(file.length))!
 try file.read(into:buffer)
 return buffer
}
func recordingURL(_ path:String) throws -> URL {
 guard let root=Bundle.main.resourceURL else {throw NSError(domain:"Brisa",code:1,userInfo:[NSLocalizedDescriptionKey:"Audio folder not found."])}
 let url=root.appendingPathComponent("Audio").appendingPathComponent(path)
 guard FileManager.default.fileExists(atPath:url.path) else {throw NSError(domain:"Brisa",code:2,userInfo:[NSLocalizedDescriptionKey:"Recording missing: \(path)"])}
 return url
}

final class AudioBank {
 let engine = AVAudioEngine()
 var players: [String: AVAudioPlayerNode] = [:]
 var buffers: [String: AVAudioPCMBuffer] = [:]
 func buffer(_ id: String) throws -> AVAudioPCMBuffer {
  if let b = buffers[id] { return b }
  if id == "keyboard" {let b=try loadRecording(recordingURL("keyboard-ambient.wav"));buffers[id]=b;return b}
  let rate = 24000.0, count = 24000 * 16
  let format = AVAudioFormat(standardFormatWithSampleRate:rate,channels:1)!
  let b = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(count))!
  b.frameLength = AVAudioFrameCount(count)
  let p = b.floatChannelData![0]
  var low = 0.0, slow = 0.0, pink = 0.0
  var seed: UInt64 = 934821
  func rand() -> Double { seed = seed &* 6364136223846793005 &+ 1; return Double(seed >> 33) / Double(UInt32.max) * 4 - 1 }
  for i in 0..<count {
   let t = Double(i)/rate, n = rand()
   low += 0.025*(n-low); slow += 0.002*(n-slow); pink += 0.12*(n-pink)
   let swell = 0.6 + 0.4*sin(2 * .pi*t/8)
   var x: Double = 0
   switch id {
   case "white": x=n*0.23
   case "pink": x=pink*0.8 + low*0.5
   case "brown": x=slow*3.2
   case "green": x=(pink-low)*1.1
   case "grey": x=low*1.4+n*0.09
   case "rain": x=n*0.12+pink*0.35
   case "heavy": x=n*0.22+low*0.7
   case "tent": x=pink*0.8+(n > 0.995 ? n*0.25 : 0)
   case "thunder": x=slow*4*pow(max(0,sin(2 * .pi*t/16)),4)+pink*0.15
   case "creek": x=pink*0.6 + sin(2 * .pi*650*t + 5*sin(2 * .pi*3*t))*0.018*swell
   case "ocean": x=(pink*0.7+n*0.1)*swell
   case "waterfall": x=low*0.8+pink*0.6+n*0.1
   case "wind": x=low*1.5*swell
   case "fire": x=low*0.7+(n > 0.998 ? n*0.65 : 0)
   case "night": x=sin(2 * .pi*3200*t)*pow(max(0,sin(2 * .pi*4*t)),12)*0.07 + low*0.15
   case "birds": x=sin(2 * .pi*1800*t+30*sin(2 * .pi*2*t))*pow(max(0,sin(2 * .pi*t/4)),24)*0.09+pink*0.08
   case "fan": x=low*1.1+sin(2 * .pi*120*t)*0.025
   case "cabin": x=slow*2.2+pink*0.3
   case "train": x=low*0.9+n*0.1*pow(max(0,sin(2 * .pi*2*t)),16)
   default: x=0
   }
   // Gentle loop edges prevent discontinuity clicks.
   let edge = min(1.0,min(Double(i)/1200,Double(count-1-i)/1200))
   p[i]=Float(tanh(x)*edge)
  }
  buffers[id]=b; return b
 }
 func update(_ levels: [String:Double], playing: Bool, master: Double) throws {
  for (id,level) in levels where level > 0 {
   if players[id] == nil {
    let b=try buffer(id), node=AVAudioPlayerNode(); engine.attach(node)
    engine.connect(node,to:engine.mainMixerNode,format:b.format)
    node.scheduleBuffer(b,at:nil,options:.loops); players[id]=node
   }
  }
  if !engine.isRunning { try engine.start() }
  engine.mainMixerNode.outputVolume=Float(master)
  for (id,node) in players { node.volume=Float(levels[id] ?? 0); if playing { if !node.isPlaying { node.play() } } else { node.pause() } }
 }
}

struct InputTone: Identifiable {
 let id:String; let name:String; let detail:String; let count:Int
}
let keyboardTones:[InputTone]=[
 .init(id:"kc1000",name:"Cherry KC 1000",detail:"Real recording · 32 distinct key presses",count:32),
 .init(id:"mechanical",name:"Mechanical — real recording",detail:"Feedbackdesignz · 3 keypress samples",count:3)
]
let mouseTones:[InputTone]=[
 .init(id:"mouse-recorded",name:"Mouse — crisp tap",detail:"joebro10 recording · 8 samples",count:8),
 .init(id:"mouse-clean",name:"Mouse — full click",detail:"Six Ways recording · press and release",count:1)
]

@MainActor final class InputSounds: ObservableObject {
 @Published var keyboard=UserDefaults.standard.bool(forKey:"inputKeyboardEnabled") {
  didSet {UserDefaults.standard.set(keyboard,forKey:"inputKeyboardEnabled")}
 }
 @Published var mouse=UserDefaults.standard.bool(forKey:"inputMouseEnabled") {
  didSet {UserDefaults.standard.set(mouse,forKey:"inputMouseEnabled")}
 }
 @Published var volume=(UserDefaults.standard.object(forKey:"inputVolume") as? Double) ?? 0.45 {
  didSet {UserDefaults.standard.set(volume,forKey:"inputVolume")}
 }
 @Published var keyboardStyle=UserDefaults.standard.string(forKey:"keyboardStyle") ?? "kc1000" {
  didSet {UserDefaults.standard.set(keyboardStyle,forKey:"keyboardStyle")}
 }
 @Published var mouseStyle=UserDefaults.standard.string(forKey:"mouseStyle") ?? "mouse-recorded" {
  didSet {UserDefaults.standard.set(mouseStyle,forKey:"mouseStyle")}
 }
 @Published var trusted=AXIsProcessTrusted()
 @Published var listenAllowed=CGPreflightListenEventAccess()
 @Published var keyboardConnected=false
 @Published var secureInput=IsSecureEventInputEnabled()
 private var keyboardTap:CFMachPort?
 private var keyboardSource:CFRunLoopSource?
 @Published var failure: String?
 private let engine=AVAudioEngine()
 private var voices:[AVAudioPlayerNode]=[]
 private var toneBuffers:[String:[AVAudioPCMBuffer]]=[:]
 private var lastSample:[String:Int]=[:]
 private var nextVoice=0
 private var globalMonitor:Any?
 private var localMonitor:Any?
 private var permissionTimer:Timer?
 init() {
  if !keyboardTones.contains(where:{$0.id==keyboardStyle}) {keyboardStyle="kc1000"}
  if !mouseTones.contains(where:{$0.id==mouseStyle}) {mouseStyle="mouse-recorded"}
  permissionTimer=Timer.scheduledTimer(withTimeInterval:2,repeats:true){[weak self] _ in
   Task { @MainActor in
    guard let self=self else{return}
    let current=AXIsProcessTrusted(), listen=CGPreflightListenEventAccess()
    self.secureInput=IsSecureEventInputEnabled()
    if current != self.trusted || listen != self.listenAllowed {
     self.trusted=current;self.listenAllowed=listen;self.configure()
    }
   }
  }
  configure()
 }
 func requestPermission() {
  let options=[kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary
  trusted=AXIsProcessTrustedWithOptions(options)
  configure()
 }
 func reconnectKeyboard() {
  trusted=AXIsProcessTrusted();listenAllowed=CGPreflightListenEventAccess()
  configure()
 }
 func requestInputPermission() {
  _=CGRequestListenEventAccess()
  reconnectKeyboard()
 }
 private func stopKeyboardTap() {
  if let source=keyboardSource {CFRunLoopRemoveSource(CFRunLoopGetMain(),source,.commonModes)}
  if let tap=keyboardTap {CGEvent.tapEnable(tap:tap,enable:false);CFMachPortInvalidate(tap)}
  keyboardSource=nil;keyboardTap=nil;keyboardConnected=false
 }
 private func startKeyboardTap() {
  guard keyboard && (trusted || listenAllowed) else{return}
  let mask=CGEventMask(1)<<CGEventType.keyDown.rawValue
  let tap=CGEvent.tapCreate(tap:.cgSessionEventTap,place:.tailAppendEventTap,options:.listenOnly,eventsOfInterest:mask,callback:{_,type,event,context in
   guard let context=context else{return Unmanaged.passUnretained(event)}
   let owner=Unmanaged<InputSounds>.fromOpaque(context).takeUnretainedValue()
   if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    DispatchQueue.main.async { [weak owner] in
     guard let owner=owner,owner.keyboard,let tap=owner.keyboardTap else{return}
     CGEvent.tapEnable(tap:tap,enable:true)
     owner.keyboardConnected=CGEvent.tapIsEnabled(tap:tap)
    }
   }else if type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat)==0 {
    // Queue only a sound trigger, never the event or its text.
    DispatchQueue.main.async { [weak owner] in
     guard let owner=owner,owner.keyboard,owner.keyboardConnected else{return}
     owner.play(mouse:false)
    }
   }
   return Unmanaged.passUnretained(event)
  },userInfo:Unmanaged.passUnretained(self).toOpaque())
  guard let tap=tap,let source=CFMachPortCreateRunLoopSource(kCFAllocatorDefault,tap,0) else{return}
  keyboardTap=tap;keyboardSource=source
  CFRunLoopAddSource(CFRunLoopGetMain(),source,.commonModes)
  CGEvent.tapEnable(tap:tap,enable:true)
  keyboardConnected=CGEvent.tapIsEnabled(tap:tap)
 }
 func configure() {
  stopKeyboardTap()
  if let token=globalMonitor {NSEvent.removeMonitor(token);globalMonitor=nil}
  if let token=localMonitor {NSEvent.removeMonitor(token);localMonitor=nil}
  guard keyboard || mouse else {engine.pause();return}
  var mask:NSEvent.EventTypeMask=[]
  startKeyboardTap()
  if keyboard && !keyboardConnected {mask.insert(.keyDown)}
  if mouse {mask.formUnion([.leftMouseDown,.rightMouseDown,.otherMouseDown])}
  localMonitor=NSEvent.addLocalMonitorForEvents(matching:mask){[weak self] event in
   self?.handle(event);return event
  }
  var globalMask=mask
  globalMask.remove(.keyDown) // Keyboard is handled by the dedicated passive tap.
  if !globalMask.isEmpty {
   globalMonitor=NSEvent.addGlobalMonitorForEvents(matching:globalMask){[weak self] event in self?.handle(event)}
  }
  do {try prepare()}catch{failure=error.localizedDescription}
 }
 private func prepare() throws {
  if voices.isEmpty {
   let format=AVAudioFormat(standardFormatWithSampleRate:24000,channels:1)!
   for _ in 0..<12 {
    let node=AVAudioPlayerNode();engine.attach(node)
    engine.connect(node,to:engine.mainMixerNode,format:format);voices.append(node)
   }
  }
  if toneBuffers.isEmpty {
   var loaded:[String:[AVAudioPCMBuffer]]=[:]
   for tone in keyboardTones+mouseTones {
    loaded[tone.id]=try (0..<tone.count).map{try loadRecording(recordingURL(String(format:"%@/%02d.wav",tone.id,$0)))}
   }
   toneBuffers=loaded
  }
  if !engine.isRunning {try engine.start()}
 }
 private func handle(_ event:NSEvent) {
  // Inspect only event type and repeat flag. Never read or retain characters/key codes.
  if event.type == .keyDown {
   guard keyboard && !event.isARepeat else{return}
   play(mouse:false)
  }else if mouse {play(mouse:true)}
 }
 func play(mouse:Bool) {
  do {try prepare()}catch{failure=error.localizedDescription;return}
  let tones=mouse ? mouseTones:keyboardTones
  let selected=mouse ? mouseStyle:keyboardStyle
  let id=tones.contains(where:{$0.id==selected}) ? selected:tones[0].id
  guard let samples=toneBuffers[id], !samples.isEmpty else{return}
  let choices=samples.indices.filter{samples.count==1 || $0 != lastSample[id]}
  guard let index=choices.randomElement() else{return}
  lastSample[id]=index
  let buffer=samples[index]
  let node=voices[nextVoice];nextVoice=(nextVoice+1)%voices.count
  node.stop();node.volume=Float(volume)
  node.scheduleBuffer(buffer,at:nil);node.play()
 }
}

struct InputSoundsView:View {
 @ObservedObject var input:InputSounds
 @Environment(\.dismiss) private var dismiss
 var body:some View {
  VStack(alignment:.leading,spacing:16){
   HStack{Text("Interaction sounds").font(.title2.weight(.semibold));Spacer();Button("Done"){dismiss()}}
   Text("Real recordings for every key press or click, including in other apps. Keep Brisa open.").foregroundStyle(.secondary)
   Toggle("Play sound when a key is pressed",isOn:$input.keyboard).onChange(of:input.keyboard){_ in input.configure()}
   HStack{
    Picker("Keyboard",selection:$input.keyboardStyle){ForEach(keyboardTones){Text($0.name).tag($0.id)}}
    Button("Preview"){input.play(mouse:false)}.help("Preview keyboard style")
   }
   Text(keyboardTones.first(where:{$0.id==input.keyboardStyle})?.detail ?? "").font(.caption).foregroundStyle(.secondary)
   Toggle("Play sound when the mouse is clicked",isOn:$input.mouse).onChange(of:input.mouse){_ in input.configure()}
   HStack{
    Picker("Mouse",selection:$input.mouseStyle){ForEach(mouseTones){Text($0.name).tag($0.id)}}
    Button("Preview"){input.play(mouse:true)}.help("Preview mouse style")
   }
   Text(mouseTones.first(where:{$0.id==input.mouseStyle})?.detail ?? "").font(.caption).foregroundStyle(.secondary)
   HStack{Text("Volume");Slider(value:$input.volume,in:0...1);Text("\(Int(input.volume*100))%").monospacedDigit().frame(width:42)}
   Divider()
   VStack(alignment:.leading,spacing:10){
    Label(!input.keyboard ? "Keyboard sound is off":input.keyboardConnected ? "Global keyboard connected":"Keyboard available only in Brisa",systemImage:input.keyboardConnected ? "checkmark.circle":"keyboard")
     .foregroundStyle(input.keyboardConnected ? accent:Color.secondary)
    if input.secureInput {Text("Secure Input is active in macOS. Leave the protected field or turn it off in the app that enabled it to hear key sounds.").font(.caption).foregroundStyle(.orange)}
    if input.keyboard && !input.keyboardConnected {
     Text("macOS has not enabled this version of Brisa yet. In Privacy & Security, remove the old Brisa entry from Accessibility and add this app again. You may also need to allow Input Monitoring, then reopen Brisa.").font(.caption)
     HStack{
      Button("Accessibility…"){input.requestPermission()}
      Button("Input Monitoring…"){input.requestInputPermission()}
     }
     Button("Show this Brisa in Finder"){NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])}
    }
    Button("Reconnect keyboard"){input.reconnectKeyboard()}
   }
   Text("Brisa does not read or store typed text. Protected macOS fields may not emit sound. Your settings and volume are restored when Brisa opens.").font(.caption).foregroundStyle(.secondary)
   if let failure=input.failure {Text("Audio error: \(failure)").font(.caption).foregroundStyle(.red)}
  }.padding(28).frame(width:560).tint(accent).preferredColorScheme(.dark)
 }
}

let accent=Color(red:0.66,green:0.79,blue:0.63)
struct WelcomeView: View {
 @State private var page = 0
 let finish: () -> Void
 private let pages = [
  ("wind", "A quieter space", "Build a personal soundscape for focus, rest, or sleep."),
  ("slider.horizontal.3", "Make it yours", "Mix sounds, tune every level, and save your favorite environments."),
  ("menubar.rectangle", "Always within reach", "Control Brisa from the menu bar. Keyboard sounds are optional and stay on your Mac.")
 ]
 var body: some View {
  ZStack {
   LinearGradient(colors:[Color(red:0.035,green:0.075,blue:0.075),Color(red:0.08,green:0.15,blue:0.13)],startPoint:.topLeading,endPoint:.bottomTrailing).ignoresSafeArea()
   Circle().fill(accent.opacity(0.24)).frame(width:360).blur(radius:85).offset(x:150,y:-220)
   VStack(spacing:0) {
    HStack {Spacer();Button("Skip") { finish() }.buttonStyle(.plain).foregroundStyle(.secondary).padding(22)}
    let item=pages[page]
    VStack(spacing:22) {
     Image(systemName:item.0).font(.system(size:48,weight:.light)).foregroundStyle(accent).frame(width:104,height:104).background(.ultraThinMaterial,in:Circle()).overlay(Circle().stroke(.white.opacity(0.18),lineWidth:1))
     Text(item.1).font(.system(size:28,weight:.semibold,design:.rounded))
     Text(item.2).font(.system(size:15)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(width:330)
    }.id(page).transition(.opacity.combined(with:.scale(scale:0.96))).frame(height:285)
    HStack(spacing:7){ForEach(pages.indices,id:\.self){index in Circle().fill(index==page ? accent:Color.white.opacity(0.22)).frame(width:index==page ? 18:6,height:6)}}.padding(.bottom,28)
    Button(page == pages.count-1 ? "Start listening" : "Continue") { if page == pages.count-1 {finish()} else {withAnimation{page += 1}} }
     .buttonStyle(.plain).font(.system(size:14,weight:.semibold)).foregroundStyle(Color.black.opacity(0.8)).frame(width:190,height:46).background(accent,in:Capsule()).padding(.bottom,36)
   }
  }.frame(width:500,height:470).preferredColorScheme(.dark).tint(accent)
 }
}
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
struct MixEditor: View {
 @Environment(\.dismiss) private var dismiss
 @State private var draft: Mix
 let onSave: (Mix)->Void
 init(mix:Mix,onSave:@escaping (Mix)->Void) {
  _draft=State(initialValue:mix);self.onSave=onSave
 }
 var body:some View {
  VStack(alignment:.leading,spacing:18){
   Text("Edit mix").font(.title2.weight(.semibold))
   TextField("Mix name",text:$draft.name).textFieldStyle(.roundedBorder)
   Text("Choose sounds and adjust their volumes.").font(.callout).foregroundStyle(.secondary)
   ScrollView {
    VStack(spacing:12){ForEach(library){sound in
     HStack(spacing:12){
      Toggle(isOn:Binding(get:{draft.levels[sound.id] != nil},set:{enabled in
       if enabled {draft.levels[sound.id]=0.05}else{draft.levels.removeValue(forKey:sound.id)}
      })){Label(sound.name,systemImage:sound.icon)}.toggleStyle(.checkbox).frame(width:220,alignment:.leading)
      if draft.levels[sound.id] != nil {
       Slider(value:Binding(get:{draft.levels[sound.id] ?? 0.5},set:{draft.levels[sound.id]=$0}),in:0...1).accessibilityLabel("Volume for \(sound.name)")
       Text("\(Int((draft.levels[sound.id] ?? 0)*100))%").font(.caption.monospacedDigit()).frame(width:40,alignment:.trailing)
      }else{Spacer()}
     }.padding(.vertical,5)
    }}.padding(4)
   }
   Divider()
   HStack{
    Text("\(draft.levels.count) sounds selected").font(.caption).foregroundStyle(.secondary)
    Spacer()
    Button("Cancel"){dismiss()}.keyboardShortcut(.cancelAction)
    Button("Save changes"){
     draft.name=draft.name.trimmingCharacters(in:.whitespacesAndNewlines)
     onSave(draft);dismiss()
    }.keyboardShortcut(.defaultAction).disabled(draft.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || draft.levels.isEmpty)
   }
  }.padding(26).frame(width:560,height:600).tint(accent).preferredColorScheme(.dark)
 }
}
struct MenuBarPlayerView: View {
 @ObservedObject var model: AppModel
 var body: some View {
  VStack(spacing:16){
   HStack(spacing:11){
    Image(systemName:"wind").font(.system(size:17,weight:.semibold)).foregroundStyle(accent).frame(width:34,height:34).background(accent.opacity(0.16),in:Circle())
    VStack(alignment:.leading,spacing:2){Text("brisa").font(.system(size:15,weight:.semibold,design:.rounded));Text(model.isPlaying ? "Now playing" : "Paused").font(.system(size:10,weight:.medium)).foregroundStyle(model.isPlaying ? accent:.secondary)}
    Spacer()
    Button{NSApp.activate(ignoringOtherApps:true);NSApp.windows.first?.makeKeyAndOrderFront(nil)}label:{Image(systemName:"arrow.up.left.and.arrow.down.right").font(.caption).frame(width:28,height:28).background(.white.opacity(0.08),in:Circle())}.buttonStyle(.plain).help("Open Brisa")
   }
   VStack(alignment:.leading,spacing:5){Text(model.nowPlayingTitle).font(.system(size:16,weight:.medium)).lineLimit(1);Text("\(model.levels.count) sounds in your mix").font(.system(size:11)).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,alignment:.leading)
   HStack(spacing:12){
    Button{model.togglePlayback()}label:{Image(systemName:model.isPlaying ? "pause.fill":"play.fill").font(.system(size:15,weight:.bold)).foregroundStyle(Color.black.opacity(0.8)).frame(width:42,height:42).background(accent,in:Circle())}.buttonStyle(.plain).accessibilityLabel(model.isPlaying ? "Pause":"Play")
    Button{model.toggleMute()}label:{Image(systemName:model.masterVolume == 0 ? "speaker.slash.fill":"speaker.wave.2.fill").font(.system(size:14)).frame(width:34,height:34).background(.white.opacity(0.09),in:Circle())}.buttonStyle(.plain).accessibilityLabel(model.masterVolume == 0 ? "Unmute":"Mute")
    Slider(value:$model.masterVolume,in:0...1).frame(width:116).onChange(of:model.masterVolume){_ in model.synchronizeAudio()}.accessibilityLabel("Master volume")
    Text("\(Int(model.masterVolume*100))%").font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary).frame(width:27)
   }
   Divider().overlay(.white.opacity(0.16))
   HStack{Text("Switch sound").font(.system(size:12,weight:.medium));Spacer();Menu{ForEach(library){sound in Button{model.replaceWith(sound)}label:{Label(sound.name,systemImage:sound.icon)}}}label:{HStack(spacing:5){Text("Choose");Image(systemName:"chevron.up.chevron.down").font(.caption2)}.font(.system(size:12,weight:.medium)).foregroundStyle(accent).padding(.horizontal,11).padding(.vertical,7).background(accent.opacity(0.15),in:Capsule())}.menuStyle(.borderlessButton).fixedSize()}
   ScrollView(.horizontal,showsIndicators:false){HStack(spacing:7){ForEach(library.prefix(6)){sound in Button{model.replaceWith(sound)}label:{Image(systemName:sound.icon).font(.system(size:14)).frame(width:35,height:35).background(model.levels[sound.id] != nil ? accent.opacity(0.24):.white.opacity(0.07),in:RoundedRectangle(cornerRadius:11))}.buttonStyle(.plain).help(sound.name)}}}
   HStack{Menu{Button("Off"){model.remainingSeconds=0;model.synchronizeAudio()};ForEach([5,15,25,30,60],id:\.self){minutes in Button("\(minutes) minutes"){model.remainingSeconds=minutes*60;model.synchronizeAudio()}}}label:{Label(model.remainingSeconds > 0 ? String(format:"%02d:%02d",model.remainingSeconds/60,model.remainingSeconds%60):"Timer",systemImage:"timer")}.menuStyle(.borderlessButton).font(.system(size:11)).foregroundStyle(.secondary);Spacer();Button("Clear"){model.levels=[:];model.isPlaying=false;model.synchronizeAudio()}.buttonStyle(.plain).font(.system(size:11)).foregroundStyle(.secondary).disabled(model.levels.isEmpty)}
  }.padding(18).frame(width:325).background(.ultraThinMaterial).preferredColorScheme(.dark).tint(accent)
 }
}
