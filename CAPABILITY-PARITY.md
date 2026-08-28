# Racket-MUD capability parity

The revival is a semantic replacement, not an API-compatible port. A recovered
capability counts as absorbed only when the new implementation has an
executable test for the behavior or deliberately provides a stronger boundary.

| Recovered capability | Replacement | Evidence |
|---|---|---|
| Things with identity, names, nouns, adjectives, and qualities | Immutable `thing` and `world` values | `test/engine-test.rkt` |
| Event scheduling and service lifecycle | FIFO message dispatch; deferred emissions; load/start/tick/stop services | `test/engine-test.rkt` |
| Busy-loop tick scheduler | `sync` over bounded ingress and monotonic `alarm-evt` | `test/engine-test.rkt` |
| Hook-based engine extensions | Collision-checked message handlers and libraries | `test/engine-test.rkt` |
| Recipes for areas, objects, and people | Immutable defensive-copying recipe constructors | `test/mudlib-test.rkt` |
| Room topology, movement, and collection | Invariant-preserving immutable world transitions | `test/mudlib-test.rkt` |
| Commands/help, look, move, bare exits, trivia, who, inventory, collect, say, channels, and sell | Parsed commands producing recipient-scoped messages and exchange requests | `test/mudlib-test.rkt` |
| Probabilistic actions | Validated action declarations with injected randomness and declared message kinds | `test/mudlib-test.rkt` |
| Talker subscriptions and room speech | Channel audiences and spatial receiver queries over the same message substrate | `test/mudlib-test.rkt` |
| Generated/plaintext account passwords | User-chosen passwords behind an injected credential codec; one-time legacy upgrade | `test/adapters-test.rkt` |
| Serialized account file | Validated immutable store with restrictive same-directory atomic replacement | `test/adapters-test.rkt` |
| Login parser | Message-driven bounded login state machine with explicit authenticated sessions | `test/adapters-test.rkt` |
| Tick-polled MUDSocket | UTF-8 line adapter using `tcp-accept-evt`, bounded channels, and custodians | `test/adapters-test.rkt` |
| Mutable client output buffers | Adapter-owned `outbound-line` and `disconnect-client` handlers | `test/adapters-test.rkt` |
| Ad-hoc debug receiver | Racket's ordinary logging facilities remain available to hosts; secrets never enter messages or adapter logs | package boundary |

The suite also proves that repeated network inputs receive distinct stable
message identities, causation references survive dispatch, connection teardown
is exactly-once, and TCP never owns or mutates world state.

World-specific Teraum content and the qtOps and TAB engines are intentionally
outside the parity boundary.
