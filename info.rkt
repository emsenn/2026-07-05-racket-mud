#lang info

(define collection "racket-mud")
(define deps '("base" "rackunit-lib"))
(define build-deps '("scribble-lib"))
(define pkg-desc "A Racket-idiomatic, message-driven multi-user dungeon engine")
(define version "0.1")
(define pkg-authors '(emsenn))
(define license 'CC0-1.0)
;; Catalog-facing discovery metadata for a future package registration.
(define tags '(games networking mud))
(define scribblings '(("scribblings/racket-mud.scrbl" (multi-page))))
