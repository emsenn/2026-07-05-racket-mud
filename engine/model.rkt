#lang racket/base

(provide thing?
         thing-id
         thing-name
         thing-nouns
         thing-adjectives
         thing-qualities
         world?
         world-things
         world-metadata
         mud-message?
         mud-message-id
         mud-message-kind
         mud-message-sender
         mud-message-audience
         mud-message-payload
         mud-message-sent-at
         mud-message-references
         make-world
         make-thing
         make-message
         world-ref-thing
         world-add-thing
         world-remove-thing
         world-update-thing
         world-ref-metadata
         world-set-metadata
         thing-ref-quality
         thing-with-quality
         thing-without-quality)

;; These records deliberately have no mutable fields. A handler receives a
;; world value and returns its successor, making a tick easy to inspect and
;; replay.
(struct thing (id name nouns adjectives qualities) #:transparent)
(struct world (things metadata) #:transparent)
(struct mud-message (id kind sender audience payload sent-at references) #:transparent)

(define (immutable-hash who value)
  (unless (hash? value)
    (raise-argument-error who "hash?" value))
  (for/fold ([result (hash)]) ([(key item) (in-hash value)])
    (hash-set result key item)))

(define (make-world #:things [things (hash)] #:metadata [metadata (hash)])
  (world (immutable-hash 'make-world things)
         (immutable-hash 'make-world metadata)))

(define (make-thing id name
                    #:nouns [nouns '()]
                    #:adjectives [adjectives '()]
                    #:qualities [qualities (hash)])
  (unless (symbol? id)
    (raise-argument-error 'make-thing "symbol?" id))
  (unless (string? name)
    (raise-argument-error 'make-thing "string?" name))
  (thing id name nouns adjectives (immutable-hash 'make-thing qualities)))

(define (make-message id kind
                      #:sender [sender #f]
                      #:audience [audience #f]
                      #:payload [payload #f]
                      #:sent-at [sent-at (current-inexact-monotonic-milliseconds)]
                      #:references [references '()])
  (unless (symbol? id)
    (raise-argument-error 'make-message "symbol?" id))
  (unless (symbol? kind)
    (raise-argument-error 'make-message "symbol?" kind))
  (unless (real? sent-at)
    (raise-argument-error 'make-message "real?" sent-at))
  (unless (list? references)
    (raise-argument-error 'make-message "list?" references))
  (mud-message id kind sender audience payload sent-at references))

(define (world-ref-thing a-world id [default #f])
  (hash-ref (world-things a-world) id default))

(define (world-add-thing a-world a-thing)
  (define id (thing-id a-thing))
  (when (hash-has-key? (world-things a-world) id)
    (raise-arguments-error 'world-add-thing "world already contains thing id"
                           "id" id))
  (struct-copy world a-world
               [things (hash-set (world-things a-world) id a-thing)]))

(define (world-remove-thing a-world id)
  (struct-copy world a-world
               [things (hash-remove (world-things a-world) id)]))

(define (world-update-thing a-world id update)
  (define prior (world-ref-thing a-world id #f))
  (unless prior
    (raise-arguments-error 'world-update-thing "world does not contain thing id"
                           "id" id))
  (define next (update prior))
  (unless (thing? next)
    (raise-arguments-error 'world-update-thing "update did not return a thing"
                           "result" next))
  (unless (equal? id (thing-id next))
    (raise-arguments-error 'world-update-thing "update changed a thing id"
                           "id" id "new-id" (thing-id next)))
  (struct-copy world a-world
               [things (hash-set (world-things a-world) id next)]))

(define (world-ref-metadata a-world key [default #f])
  (hash-ref (world-metadata a-world) key default))

(define (world-set-metadata a-world key value)
  (struct-copy world a-world
               [metadata (hash-set (world-metadata a-world) key value)]))

(define (thing-ref-quality a-thing key [default #f])
  (hash-ref (thing-qualities a-thing) key default))

(define (thing-with-quality a-thing key value)
  (struct-copy thing a-thing
               [qualities (hash-set (thing-qualities a-thing) key value)]))

(define (thing-without-quality a-thing key)
  (struct-copy thing a-thing
               [qualities (hash-remove (thing-qualities a-thing) key)]))
