import Contacts
import Foundation

actor ContactsService {
    private let contactStore: CNContactStore

    init(contactStore: CNContactStore = CNContactStore()) {
        self.contactStore = contactStore
    }

    func retrieveContext(
        for query: String,
        limit: Int = Constants.ToolCalling.maxContactLookupResults
    ) async throws -> MessageGroundingResult {
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
            .filter { contactMatchesQuery($0, query: sanitizedQuery) }
            .sorted { lhs, rhs in
                contactRank(lhs, query: sanitizedQuery) < contactRank(rhs, query: sanitizedQuery)
            }
            .prefix(max(1, min(limit, Constants.ToolCalling.maxContactLookupResults)))

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

    nonisolated func contactMatchesQuery(_ contact: CNContact, query: String) -> Bool {
        contactRank(contact, query: query) < Int.max
    }

    private nonisolated func contactRank(_ contact: CNContact, query: String) -> Int {
        let queryText = normalizedContactSearchText(query)
        let queryTokens = contactSearchTokens(in: query)
        guard !queryText.isEmpty, !queryTokens.isEmpty else { return Int.max }

        let fieldTokens = contactSearchFields(for: contact)
            .map { (normalizedContactSearchText($0), contactSearchTokens(in: $0)) }
            .filter { !$0.0.isEmpty && !$0.1.isEmpty }

        if fieldTokens.contains(where: { $0.0 == queryText }) { return 0 }

        if queryTokens.count == 1 {
            return fieldTokens.contains(where: { $0.1.contains(queryTokens[0]) }) ? 1 : Int.max
        }

        if fieldTokens.contains(where: { containsTokenSequence(queryTokens, in: $0.1, allowsPrefix: false) }) {
            return 1
        }
        if fieldTokens.contains(where: { containsTokenSequence(queryTokens, in: $0.1, allowsPrefix: true) }) {
            return 2
        }
        return Int.max
    }

    private nonisolated func contactSearchFields(for contact: CNContact) -> [String] {
        [
            displayName(for: contact),
            contact.givenName,
            contact.middleName,
            contact.familyName,
            contact.nickname,
            contact.organizationName
        ]
    }

    private nonisolated func normalizedContactSearchText(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private nonisolated func contactSearchTokens(in text: String) -> [String] {
        normalizedContactSearchText(text)
            .split(separator: " ")
            .map(String.init)
    }

    private nonisolated func containsTokenSequence(
        _ queryTokens: [String],
        in fieldTokens: [String],
        allowsPrefix: Bool
    ) -> Bool {
        guard !queryTokens.isEmpty, fieldTokens.count >= queryTokens.count else {
            return false
        }

        for startIndex in 0...(fieldTokens.count - queryTokens.count) {
            let matches = queryTokens.indices.allSatisfy { offset in
                let fieldToken = fieldTokens[startIndex + offset]
                let queryToken = queryTokens[offset]
                return allowsPrefix ? fieldToken.hasPrefix(queryToken) : fieldToken == queryToken
            }
            if matches { return true }
        }
        return false
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
