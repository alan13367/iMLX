# Memory Architecture

## Overview

The memory system is now a local-first pipeline built on SQLite/GRDB. It treats memory as more than a flat list of strings:

- canonical memory items
- typed fact metadata
- source evidence
- lifecycle events
- bounded retrieval explanations

The public app-facing API stays intentionally small. `AppState` and chat flows still work with familiar operations such as:

- `saveMemory(...)`
- `forgetMemory(matching:)`
- `retrieveMemoryContext(for:maxCharacters:)`
- `accept`, `reject`, `delete`, and `update`

Under the hood, those operations now fan out through a more explicit architecture.

## Components

### `MemorySystem`

Defined in [`iMLX/Shared/Services/Memory/MemoryService.swift`](../iMLX/Shared/Services/Memory/MemoryService.swift), `MemorySystem` is the facade used by `AppState`.

Responsibilities:

- synchronous app-facing API
- relation blocking policy
- legacy JSON import
- wiring between ingestion, retrieval, diagnostics, and the store

It is intentionally thin. It should not become the place where persistence details or ranking heuristics accrete over time.

### `MemoryStore`

Defined in [`iMLX/Shared/Services/Memory/Persistence/MemoryStore.swift`](../iMLX/Shared/Services/Memory/Persistence/MemoryStore.swift), `MemoryStore` is an `actor` and the persistence boundary for the memory system.

Responsibilities:

- opening and repairing the SQLite database
- GRDB reads and writes
- transactional create/update/archive/delete flows
- loading summaries and rich memory detail
- candidate generation for retrieval and conflict checks
- retrieval event logging and usage updates

`MemoryStore` owns durability and transactional correctness. If a change needs raw SQL, migration work, or a write that must be atomic, it belongs here.

### `MemoryDatabase`

Defined in [`iMLX/Shared/Services/Memory/Persistence/MemoryDatabase.swift`](../iMLX/Shared/Services/Memory/Persistence/MemoryDatabase.swift), this is the schema and migration owner.

Normalized tables:

- `memory_item`: canonical memory row
- `memory_fact`: typed semantic fact metadata
- `memory_evidence`: source grounding
- `memory_event`: append-only lifecycle history
- `memory_embedding_cache`: persisted vector/sketch cache
- `memory_fts`: FTS5 table for sparse candidate lookup

Compatibility tables:

- `user_memory`: retained only for migration/backfill compatibility

The migration path is:

1. old JSON file
2. legacy `user_memory` compatibility table
3. normalized relational schema

Legacy sources are only moved aside after a successful import.

### `MemoryIngestionService`

Defined in [`iMLX/Shared/Services/Memory/MemoryService.swift`](../iMLX/Shared/Services/Memory/MemoryService.swift), this service turns extracted facts into persisted memories.

Responsibilities:

- normalize memory content and metadata
- reject low-value or unsupported memories
- enforce relation-blocking policy
- detect duplicates
- resolve contradictions and retractions
- persist canonical memory rows plus evidence

This is the policy layer for what gets remembered.

### `MemoryService+Extraction`

Implemented in [`iMLX/Shared/Services/Memory/Extraction/MemoryExtraction.swift`](../iMLX/Shared/Services/Memory/Extraction/MemoryExtraction.swift), this extension handles structured extraction parsing.

Responsibilities:

- parse model output
- normalize extracted candidates
- validate source quotes
- reject unsupported inferred memories
- bridge legacy string-based extraction output

Extraction should remain source-grounded. The system must not turn assistant-generated details into memories unless they are directly grounded in user text.

### `MemoryRetrievalService`

Implemented across [`MemoryService.swift`](../iMLX/Shared/Services/Memory/MemoryService.swift) and [`MemoryRetrieval.swift`](../iMLX/Shared/Services/Memory/Retrieval/MemoryRetrieval.swift), this service handles forgetting and retrieval.

Responsibilities:

- archive matching memories for forget flows
- generate bounded retrieval candidates from DB queries
- rerank candidates locally
- attach retrieval explanations
- persist retrieval events and usage updates

The candidate pipeline is:

1. fact-based candidate lookup
2. FTS candidate lookup
3. recent/salient fallback candidates
4. bounded reranking with local features

Current reranking still uses existing local support code from `MemorySupport.swift`, but the important shift is that candidate generation no longer relies on mutable list-order indexing.

### `MemoryDiagnosticsService`

Defined in [`iMLX/Shared/Services/Memory/MemoryService.swift`](../iMLX/Shared/Services/Memory/MemoryService.swift), this service creates retrieval explanations and trace payloads used by the detail UI and event log.

Responsibilities:

- explanation objects for why a memory was chosen
- trace payloads with candidate counts and score breakdowns

This keeps observability close to the retrieval path without forcing the UI to understand the scoring internals directly.

## Data Model

The app still uses `UserMemory` in lists and chat-facing flows, but `UserMemory` is now a summary projection rather than the only model worth caring about.

Primary types in [`iMLX/Shared/Models/UserMemory.swift`](../iMLX/Shared/Models/UserMemory.swift):

- `UserMemory`: summary model used by UI and prompt assembly
- `MemoryDetail`: enriched detail view model
- `MemoryEvidence`: source quote and source message metadata
- `MemoryEvent`: lifecycle event log entry
- `MemoryRetrievalExplanation`: reason a memory was retrieved
- `MemoryRetrievalTrace`: debug-friendly retrieval trace

## Retrieval Model

Retrieval is still fully local and synchronous from the app's point of view.

Inputs:

- user query
- max memory count
- max character budget

Signals used during reranking:

- sparse lexical overlap
- local semantic similarity
- fact relation intent
- global scope
- salience and recency

Outputs:

- context block for prompting
- selected `UserMemory` summaries
- retrieval explanations
- optional trace payload

The detail UI under Settings -> Memory can now surface evidence and retrieval reasons for a selected memory.

## Operational Rules

- Persist only user-grounded facts.
- Keep writes transactional.
- Never depend on list position as a durable memory identifier.
- Prefer typed fact matching when available.
- Keep retrieval bounded; do not scan the whole corpus unless the candidate set is already small.
- Keep production SQL tracing off by default.

## Current Gaps

This architecture is in place, but a few pieces are still follow-up work rather than finished system guarantees:

- dedicated `xctest` coverage and fixture corpus
- broader diagnostics/eval tooling beyond detail-view traces
- full localization for some new memory detail copy

Those are additive tasks on top of the current architecture, not blockers for understanding how the system is now organized.
