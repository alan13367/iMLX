import Contacts
import Foundation

actor ContactsService {
    private let contactStore: CNContactStore

    init(contactStore: CNContactStore = CNContactStore()) {
        self.contactStore = contactStore
    }

    func retrieveContext(for query: String, limit: Int = 5) async throws -> MessageGroundingResult {
        let sanitizedQuery = query
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedQuery.isEmpty else {
            throw ToolExecutionFailure.invalidArguments("A contact lookup query is required.")
        }
        guard try await ensureContactsAccess() else {
            throw ToolExecutionFailure.permissionDenied("Contacts access is required to look up contact details.")
        }

        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactMiddleNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]

        let predicate = CNContact.predicateForContacts(matchingName: sanitizedQuery)
        let contacts = try contactStore.unifiedContacts(matching: predicate, keysToFetch: keys)
            .sorted { lhs, rhs in
                contactRank(lhs, query: sanitizedQuery) < contactRank(rhs, query: sanitizedQuery)
            }
            .prefix(max(1, min(limit, 10)))

        guard !contacts.isEmpty else {
            throw ToolExecutionFailure.noContent("No matching contacts were found.")
        }

        var sections: [String] = []
        var sources: [MessageSource] = []

        for contact in contacts {
            let name = displayName(for: contact)
            let phones = contact.phoneNumbers.prefix(3).map { labeledValue in
                "- Phone (\(localizedLabel(labeledValue.label))): \(labeledValue.value.stringValue)"
            }
            let emails = contact.emailAddresses.prefix(3).map { labeledValue in
                "- Email (\(localizedLabel(labeledValue.label))): \(String(labeledValue.value))"
            }
            let handles = (phones + emails).joined(separator: "\n")
            let section = """
            Contact: \(name)
            \(handles.isEmpty ? "- No phone numbers or email addresses available." : handles)
            """
            sections.append(section)
            sources.append(
                MessageSource(
                    id: contact.identifier,
                    kind: .contact,
                    title: name,
                    excerpt: handles.isEmpty ? "No phone numbers or email addresses available." : handles,
                    location: nil,
                    url: nil,
                    score: nil
                )
            )
        }

        let contextBlock = """
        The user granted local Contacts access. Use only the contact names, phone numbers, and email addresses below to answer this turn.

        Do not infer or mention postal addresses, birthdays, notes, images, relationships, or other contact-card fields.

        Contact lookup query: \(sanitizedQuery)

        \(sections.joined(separator: "\n\n---\n\n"))
        """

        return MessageGroundingResult(contextBlock: contextBlock, sources: sources)
    }

    private func ensureContactsAccess() async throws -> Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited:
            return true
        case .notDetermined:
            return try await withCheckedThrowingContinuation { continuation in
                contactStore.requestAccess(for: .contacts) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private nonisolated func contactRank(_ contact: CNContact, query: String) -> Int {
        let normalizedName = displayName(for: contact).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let normalizedQuery = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if normalizedName == normalizedQuery { return 0 }
        if normalizedName.hasPrefix(normalizedQuery) { return 1 }
        if normalizedName.contains(normalizedQuery) { return 2 }
        return 3
    }

    private nonisolated func displayName(for contact: CNContact) -> String {
        let name = [
            contact.givenName,
            contact.middleName,
            contact.familyName
        ]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return name
        }
        let nickname = contact.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nickname.isEmpty {
            return nickname
        }
        let organization = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        return organization.isEmpty ? "Unnamed contact" : organization
    }

    private nonisolated func localizedLabel(_ label: String?) -> String {
        guard let label, !label.isEmpty else { return "other" }
        return CNLabeledValue<NSString>.localizedString(forLabel: label)
    }
}
