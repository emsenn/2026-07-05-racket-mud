#lang scribble/manual

@title{Racket-MUD}

Racket-MUD is a generic, message-driven multi-user-dungeon engine. The core
holds immutable world values; a handler accepts a world and a message and
returns a successor world. Adapters own external resources and transform them
into messages, so TCP activity is not authority to advance world time.

@section{Adapters}

@racketmodname["../adapters/accounts.rkt"] defines account records, an
injectable credential codec, memory storage, and opt-in file storage. No
production password codec is bundled. @racketmodname["../adapters/tcp-line-server.rkt"]
offers a UTF-8 CRLF-normalizing TCP line adapter with bounded queues and
per-session custodians.

@racketmodname["../adapters/login.rkt"] provides a pure login library. Its
metadata accessors document the session, account-store, and @racket['active-sessions]
keys; the latter is an immutable hash mapping TCP session IDs to user names,
the connection-independent input to a @racket['who] command. Login egress is ordinary @racket['outbound-line] work handled by the
TCP adapter library.

@section{Lineage}

The engine revives generic Racket-MUD behavior only. TAB/qtOps and Teraum are
separate lineages and are not runtime dependencies.
