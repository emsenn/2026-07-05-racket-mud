#lang racket/base

(require racket/async-channel
         racket/list
         racket/match
         "model.rkt"
         "library.rkt")

(provide (struct-out mud-server)
         make-server
         server-world
         server-running?
         server-load-library!
         server-start!
         server-schedule!
         server-enqueue!
         server-accept-ingress!
         server-step!
         server-run!
         server-stop!
         server-shutdown!)

;; Every mutable field is owned by precisely one server.  In particular, this
;; replaces the process-global queues and registries in the historical RM6
;; prototype.
(struct mud-server (world handlers services service-order queue deferred stepping? ingress
                          custodian running? tick-milliseconds)
  #:mutable
  #:transparent)

(define (make-server #:world [initial-world (make-world)]
                     #:ingress-capacity [ingress-capacity 64]
                     #:tick-milliseconds [tick-milliseconds 100])
  (unless (world? initial-world)
    (raise-argument-error 'make-server "world?" initial-world))
  (unless (exact-positive-integer? ingress-capacity)
    (raise-argument-error 'make-server "exact-positive-integer?" ingress-capacity))
  (unless (and (real? tick-milliseconds) (positive? tick-milliseconds))
    (raise-argument-error 'make-server "positive-real?" tick-milliseconds))
  (mud-server initial-world (hash) (hash) '() '() '() #f
              (make-async-channel ingress-capacity)
              (make-custodian) #f tick-milliseconds))

(define (server-running? server)
  (mud-server-running? server))

(define (server-world server)
  (mud-server-world server))

(define (distinct-ids? values id-of)
  (= (length values) (length (remove-duplicates (map id-of values)))))

(define (server-load-library! server library)
  (unless (mud-server? server)
    (raise-argument-error 'server-load-library! "mud-server?" server))
  (unless (mud-library? library)
    (raise-argument-error 'server-load-library! "mud-library?" library))
  (define handlers (mud-library-handlers library))
  (define services (mud-library-services library))
  (unless (distinct-ids? handlers mud-handler-id)
    (raise-arguments-error 'server-load-library! "library repeats a handler id"
                           "library" (mud-library-id library)))
  (unless (distinct-ids? services mud-service-id)
    (raise-arguments-error 'server-load-library! "library repeats a service id"
                           "library" (mud-library-id library)))
  (for ([handler (in-list handlers)])
    (when (hash-has-key? (mud-server-handlers server) (mud-handler-id handler))
      (raise-arguments-error 'server-load-library! "handler id is already registered"
                             "id" (mud-handler-id handler))))
  (for ([service (in-list services)])
    (when (hash-has-key? (mud-server-services server) (mud-service-id service))
      (raise-arguments-error 'server-load-library! "service id is already registered"
                             "id" (mud-service-id service))))
  ;; Validate all collisions before changing any server state.
  (for ([handler (in-list handlers)])
    (set-mud-server-handlers!
     server
     (hash-set (mud-server-handlers server) (mud-handler-id handler) handler)))
  (for ([service (in-list services)])
    (set-mud-server-services!
     server
     (hash-set (mud-server-services server) (mud-service-id service) service))
    (set-mud-server-service-order!
     server (append (mud-server-service-order server) (list (mud-service-id service))))
    (define load (mud-service-load service))
    (when load (load server)))
  (void))

(define (server-start! server)
  (unless (mud-server? server)
    (raise-argument-error 'server-start! "mud-server?" server))
  (unless (mud-server-running? server)
    (set-mud-server-running?! server #t)
    (for ([service-id (in-list (mud-server-service-order server))])
      (define service (hash-ref (mud-server-services server) service-id))
      (define start (mud-service-start service))
      (when start (start server))))
  (void))

(define (server-schedule! server message)
  (unless (mud-server? server)
    (raise-argument-error 'server-schedule! "mud-server?" server))
  (unless (mud-message? message)
    (raise-argument-error 'server-schedule! "mud-message?" message))
  (if (mud-server-stepping? server)
      (set-mud-server-deferred!
       server (append (mud-server-deferred server) (list message)))
      (set-mud-server-queue!
       server (append (mud-server-queue server) (list message))))
  (void))

(define (server-enqueue! server message)
  (unless (mud-server? server)
    (raise-argument-error 'server-enqueue! "mud-server?" server))
  (unless (mud-message? message)
    (raise-argument-error 'server-enqueue! "mud-message?" message))
  (async-channel-put (mud-server-ingress server) message)
  (void))

;; Receiving messages is I/O progress; advancing the world and ticking
;; services remains clock progress. Keeping this boundary explicit also makes
;; the runtime's cadence guarantee testable without timing-sensitive tests.
(define (server-accept-ingress! server message)
  (server-schedule! server message))

(define (drain-ingress! server)
  (let loop ([messages '()])
    (define next (async-channel-try-get (mud-server-ingress server)))
    (if next
        (loop (append messages (list next)))
        messages)))

(define (call-handler server handler current message)
  (define next ((mud-handler-procedure handler)
                (lambda (new-message) (server-schedule! server new-message))
                current
                message))
  (unless (world? next)
    (raise-arguments-error 'server-step! "message handler did not return a world"
                           "message-kind" (mud-message-kind message)
                           "result" next))
  next)

(define (server-step! server)
  (unless (mud-server? server)
    (raise-argument-error 'server-step! "mud-server?" server))
  ;; Snapshot both queues before dispatch.  A handler may enqueue more work,
  ;; but it goes to `deferred` and is not visible until the following step.
  (define batch (append (mud-server-queue server) (drain-ingress! server)))
  (set-mud-server-queue! server '())
  (set-mud-server-deferred! server '())
  (set-mud-server-stepping?! server #t)
  (dynamic-wind
    void
    (lambda ()
      (for ([message (in-list batch)])
        (define handler
          (hash-ref (mud-server-handlers server) (mud-message-kind message) #f))
        (unless handler
          (raise-arguments-error 'server-step! "unknown message id"
                                 "kind" (mud-message-kind message)))
        (set-mud-server-world!
         server
         (call-handler server handler (mud-server-world server) message)))
      (for ([service-id (in-list (mud-server-service-order server))])
        (define service (hash-ref (mud-server-services server) service-id))
        (define tick (mud-service-tick service))
        (when tick (tick server))))
    (lambda ()
      (set-mud-server-stepping?! server #f)
      (set-mud-server-queue!
       server
       (append (mud-server-queue server) (mud-server-deferred server)))
      (set-mud-server-deferred! server '())))
  (mud-server-world server))

(define (server-run! server)
  (unless (mud-server? server)
    (raise-argument-error 'server-run! "mud-server?" server))
  (server-start! server)
  (parameterize ([current-custodian (mud-server-custodian server)])
    (let loop ([deadline (+ (current-inexact-monotonic-milliseconds)
                            (mud-server-tick-milliseconds server))])
      (when (mud-server-running? server)
        (match
            (sync
             ;; An async channel is itself a synchronizable receive event.
             (handle-evt (mud-server-ingress server)
                         (lambda (message) (cons 'ingress message)))
             (handle-evt (alarm-evt deadline #t) (lambda (_) 'alarm)))
          [(cons 'ingress message)
           ;; Ingress only queues work. The monotonic alarm is the sole
           ;; authority that advances the world and ticks services.
           (server-accept-ingress! server message)
           (loop deadline)]
          ['alarm
           (server-step! server)
           (loop (+ deadline (mud-server-tick-milliseconds server)))])))))

(define (server-stop! server)
  (unless (mud-server? server)
    (raise-argument-error 'server-stop! "mud-server?" server))
  (when (mud-server-running? server)
    (set-mud-server-running?! server #f)
    (for ([service-id (in-list (reverse (mud-server-service-order server)))])
      (define service (hash-ref (mud-server-services server) service-id))
      (define stop (mud-service-stop service))
      (when stop (stop server))))
  (void))

(define (server-shutdown! server)
  (server-stop! server)
  (custodian-shutdown-all (mud-server-custodian server))
  (void))
