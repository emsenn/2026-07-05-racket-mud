#lang racket

(require rackunit
         racket/async-channel
         racket/file
         "../adapters/accounts.rkt"
         "../adapters/login.rkt"
         "../adapters/tcp-line-server.rkt"
         "../engine/model.rkt"
         "../engine/server.rkt")

;; This intentionally insecure codec exists only in this test module.  The
;; application exposes no default password codec.
(define test-codec
  (credential-codec (lambda (password) (string-append "test:" password))
                    (lambda (password credential)
                      (string=? credential (string-append "test:" password)))))

(module+ test
  (define initial (make-memory-account-store))
  (define registered (register-account initial test-codec "ava" "correct"))
  (check-true (account? (account-store-ref registered "ava")))
  (let-values ([(ok? unchanged) (authenticate-account registered test-codec "ava" "wrong")])
    (check-false ok?)
    (check-eq? unchanged registered))
  (let-values ([(ok? upgraded)
                (authenticate-account
                 (account-store-put initial
                                    (account "legacy" (legacy-credential "old-pass") 0))
                 test-codec "legacy" "old-pass")])
    (check-true ok?)
    (check-false (legacy-credential? (account-credential (account-store-ref upgraded "legacy")))))

  (define directory (make-temporary-file "racket-mud-adapters~a" 'directory))
  (define account-path (build-path directory "accounts.rktd"))
  (define file-store
    (account-store-put (load-file-account-store account-path) (account "ava" "opaque" 0)))
  (account-store-save! file-store)
  (check-equal? (account-store-ref (load-file-account-store account-path) "ava")
                (account "ava" "opaque" 0))
  (call-with-output-file account-path (lambda (out) (display "not-account-data" out)) #:exists 'truncate)
  (check-exn exn:fail? (lambda () (load-file-account-store account-path)))
  (check-false (account-store-ref (load-file-account-store account-path #:on-malformed 'empty) "ava"))
  (delete-directory/files directory)

  ;; In-memory ports exercise the adapter seam without binding a public port.
  (define server (make-tcp-line-server #:queue-capacity 8 #:max-line-bytes 8))
  (define-values (server-in client-out) (make-pipe))
  (define server-out (open-output-string))
  (define sid (tcp-line-server-add-session! server server-in server-out #:id 'test-client))
  (define connected (sync/timeout 1 (tcp-line-server-inbox server)))
  (check-equal? (mud-message-kind connected) 'client-connected)
  (display "look\r\n" client-out) (flush-output client-out)
  (define line (sync/timeout 1 (tcp-line-server-inbox server)))
  (check-equal? (mud-message-kind line) 'client-line)
  (check-equal? (mud-message-payload line) "look")
  (display "look\n" client-out) (flush-output client-out)
  (define repeated-line (sync/timeout 1 (tcp-line-server-inbox server)))
  (check-equal? (mud-message-payload repeated-line) "look")
  (check-not-equal? (mud-message-id line) (mud-message-id repeated-line))
  (check-true (tcp-line-server-deliver-message!
               server (make-message 'reply 'outbound-line #:audience sid #:payload "You see a room.")))
  ;; The bounded session outbox is the in-memory delivery seam; the single
  ;; writer worker owns the supplied output port.
  (void (tcp-line-server-disconnect! server sid 'test-complete))
  (define terminal (sync/timeout 1 (tcp-line-server-inbox server)))
  (check-equal? (mud-message-kind terminal) 'client-disconnected)
  (check-false (hash-has-key? (tcp-line-server-sessions server) sid))
  (tcp-line-server-stop! server)

  ;; End to end: a TCP line enters the core, the pure login library changes
  ;; only world metadata, and normal scheduled egress reaches the writer.
  (define tcp (make-tcp-line-server #:queue-capacity 16))
  (define core (make-server #:ingress-capacity 16))
  (server-load-library! core (make-login-library test-codec #:max-failures 2))
  (server-load-library! core (make-tcp-line-library tcp))
  (define-values (one-in one-client) (make-pipe))
  (define one-out (open-output-string))
  (define one-id (tcp-line-server-add-session! tcp one-in one-out #:id 'one))
  (define (advance! message)
    (server-enqueue! core message)
    (void (server-step! core)))
  (define (flush-core!) (void (server-step! core)))
  (define (next-tcp!) (sync/timeout 1 (tcp-line-server-inbox tcp)))
  (advance! (next-tcp!))                         ; client-connected
  (define welcome-id (mud-message-id (car (mud-server-queue core))))
  (flush-core!)                                  ; welcome outbound-line
  (void (sync/timeout 1 (tcp-line-server-session-written tcp one-id)))
  (display "ava\n" one-client) (flush-output one-client)
  (advance! (next-tcp!))
  (define choose-password-id (mud-message-id (car (mud-server-queue core))))
  (check-not-equal? welcome-id choose-password-id)
  (check-false (regexp-match? #rx"chosen-password" (symbol->string choose-password-id)))
  (flush-core!)
  (display "chosen-password\n" one-client) (flush-output one-client)
  (advance! (next-tcp!))
  (define registered-id (mud-message-id (car (mud-server-queue core))))
  (check-not-equal? choose-password-id registered-id)
  (check-false (regexp-match? #rx"chosen-password" (symbol->string registered-id)))
  (flush-core!)
  (check-equal? (hash-ref (active-sessions (server-world core)) one-id) "ava")
  (check-false (regexp-match? #rx"chosen-password" (get-output-string one-out)))

  ;; A second TCP session takes the existing-user path and is disconnected
  ;; after the configured bounded failures; it is removed before the terminal
  ;; client-disconnected message is emitted.
  (define-values (two-in two-client) (make-pipe))
  (define two-id (tcp-line-server-add-session! tcp two-in (open-output-string) #:id 'two))
  (advance! (next-tcp!)) (flush-core!)
  (display "ava\n" two-client) (flush-output two-client)
  (advance! (next-tcp!)) (flush-core!)
  (for ([attempt (in-range 2)])
    (display "wrong\n" two-client) (flush-output two-client)
    (advance! (next-tcp!)) (flush-core!))
  (check-false (hash-has-key? (tcp-line-server-sessions tcp) two-id))
  (define closed-two (next-tcp!))
  (check-equal? (mud-message-kind closed-two) 'client-disconnected)
  (advance! closed-two)

  ;; Existing credentials authenticate without appearing in an outbound line.
  (define-values (three-in three-client) (make-pipe))
  (define three-id (tcp-line-server-add-session! tcp three-in (open-output-string) #:id 'three))
  (advance! (next-tcp!)) (flush-core!)
  (display "ava\n" three-client) (flush-output three-client)
  (advance! (next-tcp!)) (flush-core!)
  (display "chosen-password\n" three-client) (flush-output three-client)
  (advance! (next-tcp!)) (flush-core!)
  (check-equal? (hash-ref (active-sessions (server-world core)) three-id) "ava")
  (tcp-line-server-stop! tcp))
