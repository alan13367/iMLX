# Security Policy

## Supported versions

Security fixes are made on the `main` branch and included in the next release. Older revisions are not maintained separately.

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability.

Use GitHub's private vulnerability reporting flow:

1. Open this repository's **Security** tab.
2. Select **Advisories**.
3. Select **Report a vulnerability**.

Include the affected platform and revision, impact, reproduction steps, and any suggested mitigation. Do not include real conversations, contacts, calendar entries, documents, model data, or other personal information in a report.

If private vulnerability reporting is unavailable, open a minimal public issue asking the maintainer to establish a private reporting channel. Do not disclose exploit details in that issue.

The maintainer will assess reports as availability permits. Please allow time for a fix before public disclosure.

## Security model

iMLX runs model inference and stores conversations, documents, and memories locally. Optional features can still initiate network requests, including model and speech-asset downloads, web searches, and retrieval of user-requested URLs. See [`docs/privacy.md`](docs/privacy.md) for the data-flow summary.

Downloaded models and documents are untrusted input. Security reports involving model parsing, archive extraction, public-URL validation, tool argument validation, local database access, or unintended disclosure of user data are particularly valuable.
