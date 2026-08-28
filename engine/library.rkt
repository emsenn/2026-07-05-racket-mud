#lang racket/base

(provide (struct-out mud-handler)
         (struct-out mud-service)
         (struct-out mud-library)
         make-handler
         make-service
         make-library)

;; A handler receives a scheduling procedure, the current immutable world,
;; and a message.  It must return the successor world.  Services receive the
;; authoritative server instance only at lifecycle boundaries.
(struct mud-handler (id procedure) #:transparent)
(struct mud-service (id load start tick stop) #:transparent)
(struct mud-library (id handlers services) #:transparent)

(define (make-handler id procedure)
  (unless (symbol? id)
    (raise-argument-error 'make-handler "symbol?" id))
  (unless (procedure? procedure)
    (raise-argument-error 'make-handler "procedure?" procedure))
  (mud-handler id procedure))

(define (make-service id #:load [load #f] #:start [start #f]
                      #:tick [tick #f] #:stop [stop #f])
  (unless (symbol? id)
    (raise-argument-error 'make-service "symbol?" id))
  (for ([operation (in-list (list load start tick stop))])
    (unless (or (not operation) (procedure? operation))
      (raise-argument-error 'make-service "(or/c #f procedure?)" operation)))
  (mud-service id load start tick stop))

(define (make-library id #:handlers [handlers '()] #:services [services '()])
  (unless (symbol? id)
    (raise-argument-error 'make-library "symbol?" id))
  (unless (andmap mud-handler? handlers)
    (raise-argument-error 'make-library "(listof mud-handler?)" handlers))
  (unless (andmap mud-service? services)
    (raise-argument-error 'make-library "(listof mud-service?)" services))
  (mud-library id handlers services))
