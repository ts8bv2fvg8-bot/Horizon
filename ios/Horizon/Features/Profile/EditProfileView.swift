import SwiftUI

/// Edits the member's Planning Center People record: name, birthday, anniversary, emails,
/// phone numbers and address. The backend only lets members change their own records.
struct EditProfileView: View {
    let original: Profile
    let onSave: (Profile) -> Void

    @Environment(\.api) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Profile
    @State private var birthdate: Date?
    @State private var saving = false
    @State private var error: String?

    private static let locations = ["Home", "Work", "Mobile", "Other"]

    init(original: Profile, onSave: @escaping (Profile) -> Void) {
        self.original = original
        self.onSave = onSave
        _draft = State(initialValue: original)
        _birthdate = State(initialValue: original.birthdate.flatMap { DateFormatter.dayOnly.date(from: $0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { Text(error).foregroundStyle(.red) } }

                Section("Name") {
                    TextField("First name", text: $draft.firstName).textContentType(.givenName)
                    TextField("Last name", text: $draft.lastName).textContentType(.familyName)
                    TextField("Goes by (optional)", text: Binding(get: { draft.nickname ?? "" }, set: { draft.nickname = $0.isEmpty ? nil : $0 }))
                }

                Section("Birthday") {
                    if let date = birthdate {
                        DatePicker("Birthday", selection: Binding(get: { date }, set: { birthdate = $0 }), in: ...Date(), displayedComponents: .date)
                    } else {
                        Button("Add birthday") { birthdate = Calendar.current.date(byAdding: .year, value: -30, to: Date()) }
                    }
                }

                Section("Email") {
                    ForEach(draft.emails.indices, id: \.self) { i in
                        HStack {
                            TextField("Email", text: $draft.emails[i].address).keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never)
                            locationPicker($draft.emails[i].location)
                        }
                    }
                    .onDelete { draft.emails.remove(atOffsets: $0) }
                    Button("Add email") { draft.emails.append(.init(address: "", location: "Home", primary: draft.emails.isEmpty)) }
                }

                Section("Phone") {
                    ForEach(draft.phoneNumbers.indices, id: \.self) { i in
                        HStack {
                            TextField("Phone", text: $draft.phoneNumbers[i].number).keyboardType(.phonePad).textContentType(.telephoneNumber)
                            locationPicker($draft.phoneNumbers[i].location)
                        }
                    }
                    .onDelete { draft.phoneNumbers.remove(atOffsets: $0) }
                    Button("Add phone") { draft.phoneNumbers.append(.init(number: "", location: "Mobile", primary: draft.phoneNumbers.isEmpty)) }
                }

                Section("Address") {
                    ForEach(draft.addresses.indices, id: \.self) { i in
                        VStack {
                            TextField("Street", text: $draft.addresses[i].streetLine1).textContentType(.streetAddressLine1)
                            TextField("City", text: $draft.addresses[i].city).textContentType(.addressCity)
                            HStack {
                                TextField("State", text: $draft.addresses[i].state).textContentType(.addressState)
                                TextField("ZIP", text: $draft.addresses[i].zip).textContentType(.postalCode).keyboardType(.numberPad)
                            }
                        }
                    }
                    .onDelete { draft.addresses.remove(atOffsets: $0) }
                    if draft.addresses.isEmpty {
                        Button("Add address") { draft.addresses.append(.init(streetLine1: "", city: "", state: "OR", zip: "", location: "Home", primary: true)) }
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else { Button("Save") { Task { await save() } }.disabled(draft.firstName.isEmpty) }
                }
            }
        }
    }

    private func locationPicker(_ binding: Binding<String?>) -> some View {
        Picker("", selection: Binding(get: { binding.wrappedValue ?? "Home" }, set: { binding.wrappedValue = $0 })) {
            ForEach(Self.locations, id: \.self) { Text($0) }
        }
        .labelsHidden()
        .fixedSize()
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let update = ProfileUpdate.diff(original: original, draft: draft, birthdate: birthdate.map { DateFormatter.dayOnly.string(from: $0) })
        do {
            let updated: Profile = try await api.send("PATCH", "/v1/me", body: update)
            onSave(updated)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension ProfileUpdate {
    /// Builds a minimal PATCH body: changed person fields plus added, edited and deleted
    /// contact records. Blank new rows are ignored.
    static func diff(original: Profile, draft: Profile, birthdate: String?) -> ProfileUpdate {
        func items<T: Encodable & Equatable & Identifiable>(_ old: [T], _ new: [T], isBlank: (T) -> Bool) -> [Item<T>]? where T.ID == String? {
            var out: [Item<T>] = []
            for item in new where !isBlank(item) {
                if item.id == nil || old.first(where: { $0.id == item.id }) != item { out.append(Item(value: item, delete: false)) }
            }
            for item in old where !new.contains(where: { $0.id == item.id }) { out.append(Item(value: item, delete: true)) }
            return out.isEmpty ? nil : out
        }

        var update = ProfileUpdate()
        let personChanged = original.firstName != draft.firstName || original.lastName != draft.lastName
            || original.nickname != draft.nickname || original.birthdate != birthdate
        if personChanged {
            update.person = Person(first_name: draft.firstName, last_name: draft.lastName, nickname: draft.nickname, birthdate: birthdate)
        }
        update.emails = items(original.emails, draft.emails) { $0.address.trimmingCharacters(in: .whitespaces).isEmpty }
        update.phoneNumbers = items(original.phoneNumbers, draft.phoneNumbers) { $0.number.trimmingCharacters(in: .whitespaces).isEmpty }
        update.addresses = items(original.addresses, draft.addresses) { $0.streetLine1.isEmpty && $0.city.isEmpty }
        return update
    }
}
