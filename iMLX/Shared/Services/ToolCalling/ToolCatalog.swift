import Foundation

nonisolated struct ToolCatalog {
    let definitions: [ToolDefinition]
    let executors: [String: any ToolExecutor]

    static func make(
        webSearchService: WebSearchService,
        imageOCRService: ImageOCRService,
        documentLibraryService: DocumentLibraryService,
        calendarBriefService: CalendarBriefService,
        remindersService: RemindersService,
        timerService: TimerService,
        contactsService: ContactsService,
        currentDateTimeNow: @escaping @Sendable () -> Date,
        currentDateTimeTimeZone: TimeZone
    ) -> ToolCatalog {
        let readURLTool = ToolDefinition(
            name: "read_url",
            description: "Reads the exact public URL found in the latest user message and returns grounded excerpts from that page.",
            argumentSchema: [
                ToolArgument(
                    name: "url",
                    type: "string",
                    required: false,
                    description: "The exact public http or https URL to read."
                )
            ],
            metadata: ToolMetadata(
                requiresWebAccessToggle: true,
                requiresSinglePublicURL: true,
                executionClass: .network
            )
        )
        let ocrTool = ToolDefinition(
            name: "ocr_image_text",
            description: "Extracts visible text from images attached on the latest user message.",
            argumentSchema: [],
            metadata: ToolMetadata(
                requiresAttachedImages: true,
                executionClass: .local
            )
        )
        let webSearchTool = ToolDefinition(
            name: "web_search",
            description: "Searches the live web for current information and returns grounded excerpts.",
            argumentSchema: [
                ToolArgument(
                    name: "query",
                    type: "string",
                    required: true,
                    description: "A short, specific search engine query."
                )
            ],
            metadata: ToolMetadata(
                requiresWebAccessToggle: true,
                executionClass: .network
            )
        )
        let documentTool = ToolDefinition(
            name: "document_synthesize",
            description: "Retrieves bounded excerpts from attached conversation documents for summaries, comparisons, extraction, and document Q&A.",
            argumentSchema: [
                ToolArgument(
                    name: "query",
                    type: "string",
                    required: true,
                    description: "The user's document-focused question or synthesis request."
                )
            ],
            metadata: ToolMetadata(
                requiresAttachedDocuments: true,
                executionClass: .local
            )
        )
        let calendarTool = ToolDefinition(
            name: "calendar_brief",
            description: "Reads local calendar events for a bounded date range and returns a private schedule brief.",
            argumentSchema: [
                ToolArgument(
                    name: "range",
                    type: "string",
                    required: true,
                    description: "One of: today, tomorrow, this_week, next_7_days."
                )
            ],
            metadata: ToolMetadata(executionClass: .local)
        )
        let calendarCreateTool = ToolDefinition(
            name: "calendar_create",
            description: "Creates one basic event in the user's default Calendar when title, start, and end or duration are explicit.",
            argumentSchema: [
                ToolArgument(
                    name: "title",
                    type: "string",
                    required: true,
                    description: "Short event title."
                ),
                ToolArgument(
                    name: "start",
                    type: "string",
                    required: true,
                    description: "Explicit start datetime: ISO datetime, yyyy-MM-dd HH:mm, today HH:mm, or tomorrow HH:mm."
                ),
                ToolArgument(
                    name: "end_or_duration",
                    type: "string",
                    required: true,
                    description: "Explicit end datetime or duration such as 30 minutes or 1 hour."
                ),
                ToolArgument(
                    name: "location",
                    type: "string",
                    required: false,
                    description: "Optional event location."
                ),
                ToolArgument(
                    name: "notes",
                    type: "string",
                    required: false,
                    description: "Optional event notes."
                ),
                ToolArgument(
                    name: "alert_minutes_before",
                    type: "string",
                    required: false,
                    description: "Optional alert offset in minutes before the event."
                )
            ],
            metadata: ToolMetadata(executionClass: .local, mutatesUserData: true)
        )
        let currentDateTimeTool = ToolDefinition(
            name: "current_datetime",
            description: "Returns the device's current local date, time, weekday, and timezone using the system clock.",
            argumentSchema: [],
            metadata: ToolMetadata(executionClass: .local)
        )
        let remindersBriefTool = ToolDefinition(
            name: "reminders_brief",
            description: "Reads incomplete local reminders for all reminders or a due-date range and returns a private brief.",
            argumentSchema: [
                ToolArgument(
                    name: "range",
                    type: "string",
                    required: true,
                    description: "One of: all, today, tomorrow, this_week, next_7_days, overdue."
                )
            ],
            metadata: ToolMetadata(executionClass: .local)
        )
        let remindersCreateTool = ToolDefinition(
            name: "reminders_create",
            description: "Creates one reminder in the user's default Reminders list with an optional due date and notes.",
            argumentSchema: [
                ToolArgument(
                    name: "title",
                    type: "string",
                    required: true,
                    description: "Short reminder title."
                ),
                ToolArgument(
                    name: "due",
                    type: "string",
                    required: false,
                    description: "Optional due: today, tomorrow, tonight, ISO date/datetime, or in N hours/minutes/days."
                ),
                ToolArgument(
                    name: "notes",
                    type: "string",
                    required: false,
                    description: "Optional notes."
                )
            ],
            metadata: ToolMetadata(executionClass: .local, mutatesUserData: true)
        )
        let timerCreateTool = ToolDefinition(
            name: "timer_create",
            description: "Creates and starts one native timer for an explicit duration between 1 second and 24 hours.",
            argumentSchema: [
                ToolArgument(
                    name: "duration",
                    type: "string",
                    required: true,
                    description: "Explicit duration such as 10 minutes, 1 hour 30 minutes, MM:SS, HH:MM:SS, or seconds."
                ),
                ToolArgument(
                    name: "title",
                    type: "string",
                    required: false,
                    description: "Optional short timer title."
                )
            ],
            metadata: ToolMetadata(executionClass: .local, mutatesUserData: true)
        )
        let contactsLookupTool = ToolDefinition(
            name: "contacts_lookup",
            description: "Looks up matching local Contacts and returns names plus phone numbers and email addresses only.",
            argumentSchema: [
                ToolArgument(
                    name: "query",
                    type: "string",
                    required: true,
                    description: "The person's or organization's name to look up."
                )
            ],
            metadata: ToolMetadata(executionClass: .local)
        )

        let readURLExecutor = ReadURLToolExecutor(webSearchService: webSearchService)
        let ocrExecutor = OCRImageTextToolExecutor(imageOCRService: imageOCRService)
        let webSearchExecutor = WebSearchToolExecutor(webSearchService: webSearchService)
        let documentExecutor = DocumentSynthesizeToolExecutor(documentLibraryService: documentLibraryService)
        let calendarExecutor = CalendarBriefToolExecutor(calendarBriefService: calendarBriefService)
        let calendarCreateExecutor = CalendarCreateToolExecutor(calendarBriefService: calendarBriefService)
        let currentDateTimeExecutor = CurrentDateTimeToolExecutor(
            now: currentDateTimeNow,
            timeZone: currentDateTimeTimeZone
        )
        let remindersBriefExecutor = RemindersBriefToolExecutor(remindersService: remindersService)
        let remindersCreateExecutor = RemindersCreateToolExecutor(remindersService: remindersService)
        let timerCreateExecutor = TimerCreateToolExecutor(timerService: timerService)
        let contactsLookupExecutor = ContactsLookupToolExecutor(contactsService: contactsService)

        var definitions: [ToolDefinition] = [
            readURLTool,
            ocrTool,
            webSearchTool,
            documentTool,
            calendarTool,
            calendarCreateTool,
            currentDateTimeTool,
            remindersBriefTool,
            remindersCreateTool,
            contactsLookupTool
        ]
        var executors: [String: any ToolExecutor] = [
            readURLExecutor.toolName: readURLExecutor,
            ocrExecutor.toolName: ocrExecutor,
            webSearchExecutor.toolName: webSearchExecutor,
            documentExecutor.toolName: documentExecutor,
            calendarExecutor.toolName: calendarExecutor,
            calendarCreateExecutor.toolName: calendarCreateExecutor,
            currentDateTimeExecutor.toolName: currentDateTimeExecutor,
            remindersBriefExecutor.toolName: remindersBriefExecutor,
            remindersCreateExecutor.toolName: remindersCreateExecutor,
            contactsLookupExecutor.toolName: contactsLookupExecutor
        ]
        if TimerService.isSupported {
            definitions.insert(timerCreateTool, at: definitions.count - 1)
            executors[timerCreateExecutor.toolName] = timerCreateExecutor
        }
        return ToolCatalog(definitions: definitions, executors: executors)
    }
}
