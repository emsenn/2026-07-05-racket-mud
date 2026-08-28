# Provenance and synthesis boundary

The generic runnable baseline was synthesized from the recovered Racket-MUD
corpus and the later Racket-MUD 6 architectural record. Racket-MUD 6 supplied
explicit message, service, command, and quality vocabulary, but was incomplete
as a standalone runnable tree and was not copied wholesale.

Source discovery covered the historical GitHub repositories (`emsenn/561`,
`emsenn/561-theory`, `emsenn/561-group`, and `emsenn/emsenn-archive-code`),
the older GitLab Racket-MUD registration, recovered web/wiki materials, and
the cold-red-gate VPS. The VPS had no Racket runtime, MUD service, container,
or matching deployment unit; it supplied archival corroboration only.

Parity gate: every imported behavior names its recovered source and has
executable replacement evidence. After that gate passed, the superseded local
Racket-MUD custody copies were deleted on 2026-08-28. Their exact paths,
file counts, and tree-manifest hashes are recorded in
`LEGACY-DELETION-MANIFEST.md`; tracked contents remain recoverable from Git.
World-specific Teraum material and distinct TAB/qtOps generations remain
outside this app.

Current limitations: no bundled production credential codec, no bundled
production world, no automatic legacy-account import, and no network listener
is started by default. File persistence is same-directory temporary-file plus
atomic replacement with mode 0600; it does not claim crash-durability beyond
the host filesystem's rename guarantees.

The revival's login flow is newly synthesized rather than copied: users choose
passwords, failed existing-account attempts are bounded and disconnect, and
only opaque codec records enter account metadata. Secrets are never emitted in
line payloads or written to an application log. `active-sessions` is explicit
world metadata so the generic mudlib can implement `who` without TCP access.
