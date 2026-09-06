import SwiftUI
import AppKit
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
