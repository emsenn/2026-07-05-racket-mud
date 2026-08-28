#lang racket/base

(require racket/async-channel
         racket/list
         racket/match
         racket/tcp
         "../engine/model.rkt"
         "../engine/library.rkt")

(provide (struct-out tcp-line-server)
         (struct-out tcp-session)
         make-tcp-line-server
         tcp-line-server-start!
         tcp-line-server-stop!
         tcp-line-server-inbox
         tcp-line-server-sessions
         tcp-line-server-session-written
         tcp-line-server-add-session!
         make-tcp-line-library
         tcp-line-server-deliver!
         tcp-line-server-deliver-message!
         tcp-line-server-disconnect!)

;; The adapter owns ports and threads, never a world.  Its inbox contains core
;; `mud-message` values for a caller to pass to server-enqueue!.
(struct tcp-session (id input output outbox written custodian closed?) #:mutable #:transparent)
(struct tcp-line-server (listener inbox sessions custodian lock running? next-id
                                  next-message-id max-line-bytes queue-capacity accept-thread)
  #:mutable #:transparent)

(define (make-tcp-line-server #:port [port 0] #:max-line-bytes [max-line-bytes 4096]
                              #:queue-capacity [queue-capacity 32])
  (unless (exact-nonnegative-integer? port)
    (raise-argument-error 'make-tcp-line-server "exact-nonnegative-integer?" port))
  (unless (exact-positive-integer? max-line-bytes)
    (raise-argument-error 'make-tcp-line-server "exact-positive-integer?" max-line-bytes))
  (unless (exact-positive-integer? queue-capacity)
    (raise-argument-error 'make-tcp-line-server "exact-positive-integer?" queue-capacity))
  (tcp-line-server (tcp-listen port 16 #t) (make-async-channel queue-capacity)
                   (make-hash) (make-custodian) (make-semaphore 1) #f 0
                   0 max-line-bytes queue-capacity #f))

(define (with-lock server thunk)
  (call-with-semaphore (tcp-line-server-lock server) thunk))

(define (emit! server id kind payload)
  (define sequence
    (with-lock server
      (lambda ()
        (define next (add1 (tcp-line-server-next-message-id server)))
        (set-tcp-line-server-next-message-id! server next)
        next)))
  (async-channel-put
   (tcp-line-server-inbox server)
   (make-message (string->symbol (format "tcp-~a-~a-~a" id kind sequence)) kind
                 #:sender id #:audience id #:payload payload)))

(define (emit-control! server id kind payload)
  ;; A session's own custodian may be shutting down.  Put its terminal event
  ;; from the server custodian, where bounded inbox backpressure cannot strand
  ;; the closing worker or prevent registry cleanup.
  (parameterize ([current-custodian (tcp-line-server-custodian server)])
    (thread (lambda () (emit! server id kind payload)))))

(define (close-session! server session [reason 'closed])
  (unless (tcp-session-closed? session)
    (set-tcp-session-closed?! session #t)
    ;; Remove first, before a worker can be terminated by its own custodian.
    ;; The flag gives concurrent reader/writer failures exactly one terminal
    ;; event.
    (with-lock server
      (lambda () (hash-remove! (tcp-line-server-sessions server) (tcp-session-id session))))
    (with-handlers ([exn? void]) (close-input-port (tcp-session-input session)))
    (with-handlers ([exn? void]) (close-output-port (tcp-session-output session)))
    (emit-control! server (tcp-session-id session) 'client-disconnected reason)
    (custodian-shutdown-all (tcp-session-custodian session))))

(define (read-utf8-line in maximum)
  (define bytes-out (open-output-bytes))
  (let loop ([count 0])
    (define byte (read-byte in))
    (cond
      [(eof-object? byte) eof]
      [(= byte 10)
       (define raw (get-output-bytes bytes-out))
       (define trimmed
         (if (and (positive? (bytes-length raw))
                  (= (bytes-ref raw (sub1 (bytes-length raw))) 13))
             (subbytes raw 0 (sub1 (bytes-length raw))) raw))
       (with-handlers ([exn:fail? (lambda (_) 'invalid-utf8)])
         (bytes->string/utf-8 trimmed))]
      [(>= count maximum) 'line-too-long]
      [else (write-byte byte bytes-out) (loop (add1 count))])))

(define (start-session-workers! server session)
  (parameterize ([current-custodian (tcp-session-custodian session)])
    (thread
     (lambda ()
       (let loop ()
         (define line (read-utf8-line (tcp-session-input session)
                                      (tcp-line-server-max-line-bytes server)))
         (cond
           [(string? line) (emit! server (tcp-session-id session) 'client-line line) (loop)]
           [(eq? line 'line-too-long) (close-session! server session 'line-too-long)]
           [(eq? line 'invalid-utf8) (close-session! server session 'invalid-utf8)]
           [else (close-session! server session 'eof)]))))
    ;; One writer owns each output port, so concurrent core emissions never
    ;; interleave bytes on a client connection.
    (thread
     (lambda ()
       (let loop ()
         (define text (async-channel-get (tcp-session-outbox session)))
         (unless (tcp-session-closed? session)
           (with-handlers ([exn? (lambda (_) (close-session! server session 'write-failed))])
             (write-string text (tcp-session-output session))
             (write-string "\n" (tcp-session-output session))
             (flush-output (tcp-session-output session))
             (async-channel-put (tcp-session-written session) text)
             (loop))))))))

(define (tcp-line-server-session-written server session-id)
  (define session
    (with-lock server
      (lambda () (hash-ref (tcp-line-server-sessions server) session-id #f))))
  (and session (tcp-session-written session)))

(define (tcp-line-server-add-session! server input output #:id [id #f])
  (unless (tcp-line-server? server)
    (raise-argument-error 'tcp-line-server-add-session! "tcp-line-server?" server))
  (define session-id
    (or id
        (with-lock server
          (lambda ()
            (set-tcp-line-server-next-id! server (add1 (tcp-line-server-next-id server)))
            (string->symbol (format "tcp-client-~a" (tcp-line-server-next-id server)))))))
  (define child (make-custodian (tcp-line-server-custodian server)))
  (define session (tcp-session session-id input output
                               (make-async-channel (tcp-line-server-queue-capacity server))
                               (make-async-channel (tcp-line-server-queue-capacity server))
                               child #f))
  (with-lock server (lambda () (hash-set! (tcp-line-server-sessions server) session-id session)))
  (emit! server session-id 'client-connected (hash 'transport 'tcp-line))
  (start-session-workers! server session)
  session-id)

(define (accept-loop server)
  (let loop ()
    (when (tcp-line-server-running? server)
      (with-handlers ([exn:fail? (lambda (_) (void))])
        (define-values (in out) (sync (tcp-accept-evt (tcp-line-server-listener server))))
        (tcp-line-server-add-session! server in out))
      (loop))))

(define (tcp-line-server-start! server)
  (unless (tcp-line-server? server)
    (raise-argument-error 'tcp-line-server-start! "tcp-line-server?" server))
  (unless (tcp-line-server-running? server)
    (set-tcp-line-server-running?! server #t)
    (parameterize ([current-custodian (tcp-line-server-custodian server)])
      (set-tcp-line-server-accept-thread! server (thread (lambda () (accept-loop server))))))
  (void))

(define (tcp-line-server-deliver! server session-id text)
  (unless (string? text)
    (raise-argument-error 'tcp-line-server-deliver! "string?" text))
  (define session (with-lock server (lambda () (hash-ref (tcp-line-server-sessions server) session-id #f))))
  (and session (not (tcp-session-closed? session))
       (begin (async-channel-put (tcp-session-outbox session) text) #t)))

(define (tcp-line-server-deliver-message! server message)
  (unless (mud-message? message)
    (raise-argument-error 'tcp-line-server-deliver-message! "mud-message?" message))
  (unless (memq (mud-message-kind message) '(outbound-line disconnect-client))
    (raise-arguments-error 'tcp-line-server-deliver-message!
                           "adapter cannot deliver message kind"
                           "kind" (mud-message-kind message)))
  (define target (mud-message-audience message))
  (if (eq? (mud-message-kind message) 'disconnect-client)
      (tcp-line-server-disconnect! server target (mud-message-payload message))
      (tcp-line-server-deliver! server target (mud-message-payload message))))

(define (make-tcp-line-library adapter)
  (unless (tcp-line-server? adapter)
    (raise-argument-error 'make-tcp-line-library "tcp-line-server?" adapter))
  ;; These are real core handlers, not a side channel: scheduled mudlib egress
  ;; reaches the serialized TCP writers through the normal server step.
  (make-library
   'tcp-line-adapter
   #:handlers
   (list
    (make-handler 'outbound-line
                  (lambda (schedule! a-world message)
                    (tcp-line-server-deliver-message! adapter message)
                    a-world))
    (make-handler 'disconnect-client
                  (lambda (schedule! a-world message)
                    (tcp-line-server-deliver-message! adapter message)
                    a-world)))))

(define (tcp-line-server-disconnect! server session-id [reason 'requested])
  (define session (with-lock server (lambda () (hash-ref (tcp-line-server-sessions server) session-id #f))))
  (when session (close-session! server session reason))
  (and session #t))

(define (tcp-line-server-stop! server)
  (when (tcp-line-server-running? server)
    (set-tcp-line-server-running?! server #f)
    (with-handlers ([exn? void]) (tcp-close (tcp-line-server-listener server)))
    (custodian-shutdown-all (tcp-line-server-custodian server)))
  (void))
