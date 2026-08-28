#lang racket/base

(require rackunit
         "../main.rkt")

(define (append-trace a-world item)
  (world-set-metadata a-world 'trace
                      (append (world-ref-metadata a-world 'trace '()) (list item))))

(module+ test
  (test-case "things and worlds are immutable values"
    (define original (make-world))
    (define supplied-qualities (make-hash (list (cons 'weight 2))))
    (define sword (make-thing 'sword "an iron sword" #:nouns '("sword")
                              #:qualities supplied-qualities))
    (define changed (world-add-thing original sword))
    (check-false (world-ref-thing original 'sword))
    (check-equal? (thing-ref-quality (world-ref-thing changed 'sword) 'weight) 2)
    (define polished
      (world-update-thing changed 'sword
                          (lambda (item) (thing-with-quality item 'polished #t))))
    (check-false (thing-ref-quality (world-ref-thing changed 'sword) 'polished))
    (check-true (thing-ref-quality (world-ref-thing polished 'sword) 'polished))
    (check-equal? (thing-name sword) "an iron sword")
    (hash-set! supplied-qualities 'weight 99)
    (check-equal? (thing-ref-quality sword 'weight) 2))

  (test-case "message records retain messaging context"
    (define message
      (make-message 'message-1 'announce
                    #:sender 'alice
                    #:audience '(room tavern)
                    #:payload "hello"
                    #:sent-at 123.5
                    #:references '(prior-message room-42)))
    (check-equal? (mud-message-sender message) 'alice)
    (check-equal? (mud-message-audience message) '(room tavern))
    (check-equal? (mud-message-sent-at message) 123.5)
    (check-equal? (mud-message-references message) '(prior-message room-42)))

  (test-case "a step is FIFO and work scheduled during it is deferred"
    (define server (make-server #:world (make-world #:metadata (hash 'trace '()))))
    (define library
      (make-library
       'queue-test
       #:handlers
       (list
        (make-handler
         'first
         (lambda (schedule! a-world message)
           (schedule! (make-message 'second-message 'second))
           (append-trace a-world 'first)))
        (make-handler
         'second
         (lambda (schedule! a-world message)
           (append-trace a-world 'second))))))
    (server-load-library! server library)
    (server-schedule! server (make-message 'first-message 'first))
    (check-equal? (world-ref-metadata (server-step! server) 'trace) '(first))
    (check-equal? (world-ref-metadata (server-step! server) 'trace) '(first second)))

  (test-case "libraries reject handler and service collisions before mutation"
    (define server (make-server))
    (server-load-library! server
                          (make-library 'one
                                        #:handlers
                                        (list (make-handler 'echo
                                                            (lambda (_ w _m) w)))))
    (check-exn exn:fail:contract?
               (lambda ()
                 (server-load-library!
                  server
                  (make-library 'two
                                #:handlers
                                (list (make-handler 'echo
                                                    (lambda (_ w _m) w))))))))

  (test-case "service lifecycle and event phase are stable"
    (define calls (box '()))
    (define (record! tag) (set-box! calls (append (unbox calls) (list tag))))
    (define server (make-server #:world (make-world #:metadata (hash 'trace '()))))
    (server-load-library!
     server
     (make-library
      'lifecycle
      #:handlers (list (make-handler 'mark (lambda (_ world _message)
                                              (append-trace world 'event))))
      #:services (list (make-service 'recorder
                                     #:load (lambda (_) (record! 'load))
                                     #:start (lambda (_) (record! 'start))
                                     #:tick (lambda (_) (record! 'tick))
                                     #:stop (lambda (_) (record! 'stop))))))
    (server-start! server)
    (server-schedule! server (make-message 'mark-message 'mark))
    (check-equal? (world-ref-metadata (server-step! server) 'trace) '(event))
    (server-stop! server)
    (check-equal? (unbox calls) '(load start tick stop)))

  (test-case "ingress acceptance queues messages but does not tick services"
    (define ticks (box 0))
    (define server (make-server))
    (server-load-library!
     server
     (make-library
      'ingress
      #:handlers (list (make-handler 'noop (lambda (_ world _message) world)))
      #:services (list (make-service 'clock
                                     #:tick (lambda (_)
                                              (set-box! ticks (add1 (unbox ticks))))))))
    (server-accept-ingress! server (make-message 'one 'noop))
    (server-accept-ingress! server (make-message 'two 'noop))
    (check-equal? (unbox ticks) 0)
    (server-step! server)
    (check-equal? (unbox ticks) 1)))
