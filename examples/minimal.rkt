#lang racket/base

(require "../main.rkt")

(define atrium
  (instantiate-area
   (make-area-recipe 'atrium "Atrium"
                     #:description "A small room for testing messages."
                     #:exits (hash 'north 'garden))))

(define garden
  (instantiate-area
   (make-area-recipe 'garden "Garden"
                     #:description "A quiet garden."
                     #:exits (hash 'south 'atrium))))

(define visitor
  (instantiate-person
   (make-person-recipe 'visitor "Visitor"
                       #:qualities (hash 'person? #t))))

(define initial-world
  (world-move
   (for/fold ([a-world (make-world)])
             ([item (in-list (list atrium garden visitor))])
     (world-add-thing a-world item))
   'visitor
   'atrium))

(define server (make-server #:world initial-world))

(define console-library
  (make-library
   'console
   #:handlers
   (list
    (make-handler
     'outbound-line
     (lambda (_schedule! a-world message)
       (displayln (mud-message-payload message))
       a-world)))))

(server-load-library! server (standard-mud-library))
(server-load-library! server console-library)
(server-schedule!
 server
 (make-message 'example-look 'command
               #:sender 'visitor
               #:payload "look"))

;; Command handling emits output for the next deterministic step.
(void (server-step! server))
(void (server-step! server))
