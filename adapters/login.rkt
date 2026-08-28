#lang racket/base

;; Pure login library: all per-connection state and accounts live in immutable
;; world metadata; the surrounding adapter is responsible for persistence.
(require "../engine/model.rkt"
         "../engine/library.rkt"
         "accounts.rkt")

(provide (struct-out login-session)
         login-sessions-key
         login-account-store-key
         active-sessions-key
         login-sessions
         login-account-store
         active-sessions
         make-login-library)

(struct login-session (stage username failures) #:transparent)
(define login-sessions-key 'racket-mud.login.sessions)
(define login-account-store-key 'racket-mud.login.account-store)
;; This deliberate public key is the world-neutral contract used by `who`.
(define active-sessions-key 'active-sessions)

(define (login-sessions a-world)
  (world-ref-metadata a-world login-sessions-key (hash)))
(define (login-account-store a-world)
  (world-ref-metadata a-world login-account-store-key (make-memory-account-store)))
(define (active-sessions a-world)
  (world-ref-metadata a-world active-sessions-key (hash)))

(define (derived-message-id reference role ordinal)
  ;; Reference IDs are already unique core message identities. Derivation
  ;; keeps replay and inspection stable without an adapter-global gensym.
  (string->symbol (format "login-~a-~a-~a" reference role ordinal)))
(define (outbound id text reference [ordinal 1])
  (make-message (derived-message-id reference 'outbound ordinal) 'outbound-line
                #:sender 'login #:audience id #:payload text #:references (list reference)))
(define (disconnect id reason reference [ordinal 1])
  (make-message (derived-message-id reference 'disconnect ordinal) 'disconnect-client
                #:sender 'login #:audience id #:payload reason #:references (list reference)))
(define (with-login-state a-world sessions store active)
  (world-set-metadata
   (world-set-metadata
    (world-set-metadata a-world login-sessions-key sessions)
    login-account-store-key store)
   active-sessions-key active))

(define (make-login-library codec #:account-store [initial-store (make-memory-account-store)]
                            #:max-failures [max-failures 3])
  (unless (credential-codec? codec)
    (raise-argument-error 'make-login-library "credential-codec?" codec))
  (unless (account-store? initial-store)
    (raise-argument-error 'make-login-library "account-store?" initial-store))
  (unless (exact-positive-integer? max-failures)
    (raise-argument-error 'make-login-library "exact-positive-integer?" max-failures))
  (define (connected schedule! a-world message)
    (define id (mud-message-sender message))
    (schedule! (outbound id "Welcome. Enter your user name." (mud-message-id message)))
    (with-login-state a-world
                      (hash-set (login-sessions a-world) id (login-session 'username #f 0))
                      (login-account-store a-world) (active-sessions a-world)))
  (define (disconnected schedule! a-world message)
    (define id (mud-message-sender message))
    (with-login-state a-world
                      (hash-remove (login-sessions a-world) id)
                      (login-account-store a-world)
                      (hash-remove (active-sessions a-world) id)))
  (define (line schedule! a-world message)
    (define id (mud-message-sender message))
    (define text (mud-message-payload message))
    (define session (hash-ref (login-sessions a-world) id #f))
    (define store (login-account-store a-world))
    (define active (active-sessions a-world))
    (cond
      [(or (not session) (not (string? text))) a-world]
      [(eq? (login-session-stage session) 'username)
       (cond
         [(zero? (string-length text))
          (schedule! (outbound id "A user name is required." (mud-message-id message))) a-world]
         [(account-store-ref store text #f)
          (schedule! (outbound id "Enter your password." (mud-message-id message)))
          (with-login-state a-world
                            (hash-set (login-sessions a-world) id (login-session 'existing-password text 0))
                            store active)]
         [else
          (schedule! (outbound id "Choose a password." (mud-message-id message)))
          (with-login-state a-world
                            (hash-set (login-sessions a-world) id (login-session 'new-password text 0))
                            store active)])]
      [(eq? (login-session-stage session) 'new-password)
       (if (zero? (string-length text))
           (begin (schedule! (outbound id "A password is required." (mud-message-id message))) a-world)
           (let ([next-store (register-account store codec (login-session-username session) text)])
             (schedule! (outbound id "Account created. You are logged in." (mud-message-id message)))
             (with-login-state a-world (hash-remove (login-sessions a-world) id) next-store
                               (hash-set active id (login-session-username session)))))]
      [(eq? (login-session-stage session) 'existing-password)
       (let-values ([(ok? next-store)
                     (authenticate-account store codec (login-session-username session) text)])
         (if ok?
             (begin
               (schedule! (outbound id "You are logged in." (mud-message-id message)))
               (with-login-state a-world (hash-remove (login-sessions a-world) id) next-store
                                 (hash-set active id (login-session-username session))))
             (let ([failures (add1 (login-session-failures session))])
               (if (>= failures max-failures)
                   (begin
                     ;; Deliberately no password or username is echoed here.
                     (schedule! (disconnect id 'authentication-failed (mud-message-id message)))
                     (with-login-state a-world (hash-remove (login-sessions a-world) id) next-store active))
                   (begin
                     (schedule! (outbound id "Password incorrect. Try again." (mud-message-id message)))
                     (with-login-state a-world
                                       (hash-set (login-sessions a-world) id
                                                 (login-session 'existing-password (login-session-username session) failures))
                                       next-store active))))))]
      [else a-world]))
  (make-library 'login
                #:handlers (list (make-handler 'client-connected connected)
                                 (make-handler 'client-line line)
                                 (make-handler 'client-disconnected disconnected))))
