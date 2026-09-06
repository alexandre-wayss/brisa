import SwiftUI
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
