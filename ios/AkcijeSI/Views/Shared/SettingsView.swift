import CoreImage.CIFilterBuiltins
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(SyncService.self) private var sync
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("threshold") private var threshold = 30
    @AppStorage("notifyWatch") private var notifyWatch = true
    @AppStorage("notifyHighlights") private var notifyHighlights = true
    @State private var showQR = false
    @State private var pasted = ""

    var body: some View {
        @Bindable var sync = sync
        NavigationStack {
            Form {
                Section("Izpostavljene akcije") {
                    Stepper(value: $threshold, in: 10...70, step: 5) {
                        Text("Prag popusta: \(threshold) %")
                    }
                }
                Section("Obvestila") {
                    Toggle("Opazovana živila", isOn: $notifyWatch)
                    Toggle("Nove izpostavljene akcije (povzetek)", isOn: $notifyHighlights)
                    Button("Dovoli obvestila") { Task { await Notifier.requestPermission() } }
                }
                Section {
                    TextField("Moje ime (npr. Jakob)", text: $sync.displayName)
                    TextField("Lastnik repozitorija", text: $sync.owner)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Repozitorij", text: $sync.repo)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("GitHub žeton (fine-grained)", text: $sync.token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Shrani in sinhroniziraj") {
                        sync.saveSettings()
                        Task { await sync.sync(context: context) }
                    }
                    .disabled(!sync.isConfigured)
                    if let last = sync.lastSync {
                        Text("Zadnja sinhronizacija: \(last.formatted(date: .abbreviated, time: .shortened))").font(.footnote)
                    }
                    if let err = sync.lastError { Text(err).font(.footnote).foregroundStyle(.orange) }
                } header: {
                    Text("Skupna raba seznamov")
                } footer: {
                    Text("Seznama se shranjujeta v zasebni GitHub repozitorij. Žeton ustvari na github.com → Settings → Developer settings → Fine-grained tokens, z dostopom samo do tega repozitorija in pravico »Contents: Read and write«. Navodila so v README.")
                }
                Section("Prenos nastavitev na drugo napravo") {
                    Button("Pokaži QR kodo") { showQR = true }.disabled(sync.configURL == nil)
                    TextField("ali prilepi povezavo akcijesi://sync?…", text: $pasted)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit {
                            if let u = URL(string: pasted), sync.apply(configURL: u) { pasted = "" }
                        }
                }
                Section("Podatki") {
                    LabeledContent("Ponudb", value: "\(store.offers.count)")
                    if let g = store.generatedAt {
                        LabeledContent("Zajem na strežniku", value: g.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let f = store.lastFetched {
                        LabeledContent("Preneseno", value: f.formatted(date: .abbreviated, time: .shortened))
                    }
                    ForEach(store.meta?.sources ?? []) { s in
                        HStack {
                            Image(systemName: s.status == "ok" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(s.status == "ok" ? .green : .orange)
                            Text(store.chainName(s.chain))
                            Spacer()
                            Text(s.status == "ok" ? "\(s.count)" : (s.error ?? "napaka")).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .font(.subheadline)
                    }
                    if let e = store.lastError { Text(e).font(.footnote).foregroundStyle(.orange) }
                }
                Section {
                    Text("Akcije SI je zasebna aplikacija za osebno rabo. Podatki so last trgovcev in so informativni; velja cena v trgovini.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Nastavitve")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Končano") { sync.saveSettings(); dismiss() } } }
            .sheet(isPresented: $showQR) { QRSheet(url: sync.configURL) }
        }
    }
}

struct QRSheet: View {
    let url: URL?

    var body: some View {
        VStack(spacing: 16) {
            Text("Skeniraj s kamero druge naprave").font(.headline)
            if let url, let img = Self.qr(url.absoluteString) {
                Image(uiImage: img).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 280)
            }
            Text("QR koda vsebuje žeton – ne deli je z nikomer drugim.").font(.footnote).foregroundStyle(.secondary)
        }
        .padding()
        .presentationDetents([.medium])
    }

    static func qr(_ s: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(s.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
