#lang racket/base

(require rackunit
         "../engine/model.rkt"
         "../engine/library.rkt"
         "../engine/server.rkt"
         "../mudlib/main.rkt")

(module+
 test
 (test-case
  "deterministic search reports all outcomes"
  (define w
    (world-add-thing
     (world-add-thing
      (make-world)
      (make-thing
       'red-apple
       "red apple"
       #:nouns
       '("apple")
       #:adjectives
       '("red")))
     (make-thing
      'green-apple
      "green apple"
      #:nouns
      '("apple")
      #:adjectives
      '("green"))))
  (check-true (search-match? (find-things w "red apple")))
  (check-true (search-ambiguous? (find-things w "apple")))
  (check-true (search-no-match? (find-things w "pear"))))
 (test-case
  "recipes are immutable and movement preserves both ends"
  (define a
    (instantiate-area (make-area-recipe 'a "A" #:exits (hash 'east 'b))))
  (define b (instantiate-area (make-area-recipe 'b "B")))
  (define p
    (instantiate-person
     (make-person-recipe 'p "P" #:qualities (hash 'person? #t))))
  (define w
    (world-move
     (world-add-thing (world-add-thing (world-add-thing (make-world) a) b) p)
     'p
     'a))
  (define moved (world-move w 'p 'b))
  (check-equal? (thing-location (world-ref-thing moved 'p)) 'b)
  (check-false (member 'p (thing-contents (world-ref-thing moved 'a))))
  (check-not-false (member 'p (thing-contents (world-ref-thing moved 'b)))))
 (test-case
  "parser is total and bare exits move"
  (check-equal? (parsed-command-verb (parse-command #f)) 'invalid)
  (check-equal?
   (parsed-command-verb (parse-command "north" (hash 'north 'r)))
   'move))
 (test-case
  "say and channels have explicit recipient scope"
  (define room (instantiate-area (make-area-recipe 'room "Room")))
  (define elsewhere
    (instantiate-area (make-area-recipe 'elsewhere "Elsewhere")))
  (define (person id)
    (instantiate-person
     (make-person-recipe
      id
      (symbol->string id)
      #:qualities
      (hash 'person? #t))))
  (define w0
    (for/fold
     ((w (make-world)))
     ((t (in-list (list room elsewhere (person 'a) (person 'b) (person 'c)))))
     (world-add-thing w t)))
  (define w
    (world-move (world-move (world-move w0 'a 'room) 'b 'room) 'c 'elsewhere))
  (define say (command->messages w 'a (parse-command "say hi")))
  (check-equal? (map mud-message-audience say) '(a b))
  (define subscribed (world-set-metadata w (list 'channel 'news) '(b c)))
  (check-equal?
   (map
    mud-message-audience
    (command->messages subscribed 'a (parse-command "channel news update")))
   '(b c)))
 (test-case
  "trivia uses the injected RNG and collect moves the item"
  (define room
    (instantiate-area
     (make-area-recipe
      'room
      "Room"
      #:qualities
      (hash 'trivia '("first" "second")))))
  (define p
    (instantiate-person
     (make-person-recipe 'p "P" #:qualities (hash 'person? #t))))
  (define coin
    (instantiate-object (make-object-recipe 'coin "coin" #:nouns '("coin"))))
  (define w0
    (for/fold
     ((w (make-world)))
     ((t (in-list (list room p coin))))
     (world-add-thing w t)))
  (define w (world-move (world-move w0 'p 'room) 'coin 'room))
  (check-equal?
   (mud-message-payload
    (car (command->messages w 'p (parse-command "trivia") (lambda () 0.9))))
   "second")
  (define collected (world-collect w 'p 'coin))
  (check-equal? (thing-location (world-ref-thing collected 'coin)) 'p)
  (check-not-false
   (member 'coin (thing-contents (world-ref-thing collected 'p))))
  (check-false
   (member 'coin (thing-contents (world-ref-thing collected 'room)))))
 (test-case
  "logical tick honors its probability boundary"
  (define actor
    (make-thing
     'actor
     "Actor"
     #:qualities
     (hash 'action 'wave 'action-probability 0.5)))
  (define w (world-add-thing (make-world) actor))
  (check-equal? (length (logical-tick->messages w (lambda () 0.49))) 1)
  (check-equal? (logical-tick->messages w (lambda () 0.5)) '()))
 (test-case
  "who consumes the login active-sessions hash"
  (define w
    (world-set-metadata
     (make-world)
     active-session-metadata-key
     (hash 'session-1 "zoe" 'session-2 "ava" 'session-3 "ava")))
  (check-equal?
   (mud-message-payload
    (car (command->messages w 'nobody (parse-command "who"))))
   "ava, zoe"))
 (test-case
  "actions retain their declared message kind for extension handlers"
  (define w
    (world-add-thing
     (make-world)
     (make-thing
      'clock
      "Clock"
      #:qualities
      (hash 'actions (list (make-mud-action 'ring 'payload 1))))))
  (check-equal?
   (mud-message-kind (car (logical-tick->messages w (lambda () 0))))
   'ring))
 (test-case
  "emissions defer through server boundary"
  (define s (make-server))
  (server-load-library! s (standard-mud-library))
  (server-schedule! s (make-message 'x 'logical-tick #:payload (lambda () 1)))
  (server-step! s)
  (check-true (world? (server-step! s)))))

