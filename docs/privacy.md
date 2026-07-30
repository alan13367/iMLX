# Privacy and data flow

This document describes the behavior of the open-source iMLX codebase on `main`. Forks and redistributed builds can change that behavior.

## Local by default

iMLX does not require an iMLX account or developer-operated backend. Model inference, prompt construction, OCR, document retrieval, memory retrieval, and Kokoro speech synthesis run on the device.

The app stores data in its local container, including:

- Conversations and message attachments
- Imported document indexes
- Downloaded models and speech assets
- User memories and their source evidence
- App settings and optional inference-profiling records

The app does not include third-party analytics, advertising, or crash-reporting SDKs.

## Network access

Network requests occur only for features that need them:

| Feature | Recipient | Data sent |
|---|---|---|
| Model and speech-asset downloads | Hugging Face | Requested repository/file path plus normal network metadata such as IP address and user agent |
| Web Search | DuckDuckGo and selected result sites | The search query; selected pages receive normal web-request metadata |
| Read URL | The host named by the user-provided URL | The URL request and normal web-request metadata |
| Swift package resolution during development | Package hosts listed in `Package.resolved` | Normal source-control/package request metadata |

Enabling Web Search makes internet tools available; it does not send every chat online. The app presents a privacy confirmation before web search is first enabled. Search terms or requested URLs can contain information derived from the current conversation, so users should review requests before using internet tools.

No chat transcript is sent to a developer-operated iMLX service.

## System permissions

Depending on the feature, iMLX may request access to the camera, photo library, microphone, on-device speech recognition, contacts, calendars, reminders, files selected by the user, or AlarmKit. Access is requested through Apple system permission dialogs.

Contacts, calendars, reminders, and speech recognition are accessed through Apple frameworks. iMLX requests on-device speech recognition. Data managed by those frameworks may separately sync according to the user's Apple ID or configured account settings; that synchronization is outside iMLX.

Personal-data tools use the minimum data needed to answer the user's request. Their results can be added to the local model prompt but are not sent to an iMLX backend.

## User control

Users can manage conversations, memories, downloaded models, speech assets, documents, and profiling records through the app where controls are provided. Removing the app and its data removes its sandboxed local storage; files in user-selected external folders remain under the user's control.

For security disclosures, see [`SECURITY.md`](../SECURITY.md).
