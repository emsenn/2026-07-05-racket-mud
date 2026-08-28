# Racket-MUD

Racket-MUD is a message-driven MUD engine. Its immutable world core advances
only through `mud-message` handlers; adapters turn TCP lines and durable
account state into messages, and deliver emitted messages back to clients.
The TCP adapter never owns a world or advances time.

## Running the checks

```console
make check
make test
make example
```

`make repl` opens a Racket REPL at this source root. `make docs` renders the
small package manual. The TCP adapter is deliberately not started by any of
these commands.

`CAPABILITY-PARITY.md` maps the recovered engines' behavior to executable
replacement evidence.

## Boundaries

This is neither TAB/qtOps nor Teraum. TAB is a separate Fennel engine; qtOps
is reserved for a separate Guile-idiomatic engine revival; Teraum is a domain
world. Their preserved materials are evidence, not dependencies or runtime
payload.

The current revival keeps generic MUD concerns only: connection sessions,
line protocol, accounts, command/world integration, recipes, and logical
clocked actions. Production password hashing is mandatory caller-supplied
policy: this package ships no insecure fallback codec.

`adapters/login.rkt` is a pure core library. It owns login state in world
metadata under `racket-mud.login.sessions` and `racket-mud.login.account-store`;
the explicit `active-sessions` metadata hash maps session IDs to user names and
is the contract consumed by `who`.
It emits only `outbound-line` and `disconnect-client` messages. Load
`make-tcp-line-library` alongside it to make those messages reach TCP clients.
