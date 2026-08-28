#lang info

(define collection "racket-mud")
(define deps '("base"))
(define build-deps '("rackunit-lib" "scribble-lib"))
(define pkg-desc "A Racket-idiomatic, message-driven multi-user dungeon engine")
(define version "0.1.0")
(define pkg-authors '(emsenn))
(define scribblings '(("scribblings/racket-mud.scrbl" (multi-page))))
