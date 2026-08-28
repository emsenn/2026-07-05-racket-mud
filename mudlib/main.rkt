#lang racket/base

(require racket/list
         racket/string
         racket/match
         "../engine/model.rkt"
         "../engine/library.rkt")

(provide (struct-out search-match)
         (struct-out search-no-match)
         (struct-out search-ambiguous)
         (struct-out parsed-command)
         (struct-out mud-action)
         (struct-out exchange-request)
         area-recipe?
         area-recipe-id
         area-recipe-name
         area-recipe-nouns
         area-recipe-adjectives
         area-recipe-description
         area-recipe-exits
         area-recipe-qualities
         object-recipe?
         object-recipe-id
         object-recipe-name
         object-recipe-nouns
         object-recipe-adjectives
         object-recipe-description
         object-recipe-qualities
         person-recipe?
         person-recipe-id
         person-recipe-name
         person-recipe-nouns
         person-recipe-adjectives
         person-recipe-description
         person-recipe-qualities
         make-area-recipe
         make-object-recipe
         make-person-recipe
         instantiate-area
         instantiate-object
         instantiate-person
         find-things
         thing-location
         thing-contents
         thing-exits
         world-move
         world-collect
         parse-command
         standard-command-registry
         active-session-metadata-key
         command->messages
         logical-tick->messages
         make-mud-action
         standard-mud-library
         make-standard-library)

(struct search-match (thing) #:transparent)

(struct search-no-match (query) #:transparent)

(struct search-ambiguous (query things) #:transparent)

(struct parsed-command (verb arguments raw) #:transparent)

(struct mud-action (id payload probability audience) #:transparent)

(struct exchange-request (operation item-id) #:transparent)

(struct
 area-recipe
 (id name nouns adjectives description exits qualities)
 #:transparent)

(struct
 object-recipe
 (id name nouns adjectives description qualities)
 #:transparent)

(struct
 person-recipe
 (id name nouns adjectives description qualities)
 #:transparent)

(define active-session-metadata-key 'active-sessions)

(define standard-command-registry
  '(channel
    collect
    commands
    help
    inventory
    look
    move
    say
    sell
    talk
    trivia
    whereami
    who))

(define (copy-hash who h)
  (unless (hash? h) (raise-argument-error who "hash?" h))
  (for/fold ((r (hash))) (((k v) (in-hash h))) (hash-set r k v)))

(define (recipe who id name n a d q)
  (unless (symbol? id) (raise-argument-error who "symbol?" id))
  (unless (string? name) (raise-argument-error who "string?" name))
  (unless (andmap string? n) (raise-argument-error who "(listof string?)" n))
  (unless (andmap string? a) (raise-argument-error who "(listof string?)" a))
  (unless (string? d) (raise-argument-error who "string?" d))
  (values id name (append '() n) (append '() a) d (copy-hash who q)))

(define (make-area-recipe
         id
         name
         #:nouns
         (n '())
         #:adjectives
         (a '())
         #:description
         (d "")
         #:exits
         (e (hash))
         #:qualities
         (q (hash)))
  (define-values (i x ns as ds qs) (recipe 'make-area-recipe id name n a d q))
  (area-recipe i x ns as ds (copy-hash 'make-area-recipe e) qs))

(define (make-object-recipe
         id
         name
         #:nouns
         (n '())
         #:adjectives
         (a '())
         #:description
         (d "")
         #:qualities
         (q (hash)))
  (define-values
   (i x ns as ds qs)
   (recipe 'make-object-recipe id name n a d q))
  (object-recipe i x ns as ds qs))

(define (make-person-recipe
         id
         name
         #:nouns
         (n '())
         #:adjectives
         (a '())
         #:description
         (d "")
         #:qualities
         (q (hash)))
  (define-values
   (i x ns as ds qs)
   (recipe 'make-person-recipe id name n a d q))
  (person-recipe i x ns as ds qs))

(define (instantiate-area r)
  (make-thing
   (area-recipe-id r)
   (area-recipe-name r)
   #:nouns
   (area-recipe-nouns r)
   #:adjectives
   (area-recipe-adjectives r)
   #:qualities
   (hash-set
    (hash-set
     (hash-set
      (area-recipe-qualities r)
      'description
      (area-recipe-description r))
     'exits
     (area-recipe-exits r))
    'contents
    '())))

(define (instantiate-object r)
  (make-thing
   (object-recipe-id r)
   (object-recipe-name r)
   #:nouns
   (object-recipe-nouns r)
   #:adjectives
   (object-recipe-adjectives r)
   #:qualities
   (hash-set
    (object-recipe-qualities r)
    'description
    (object-recipe-description r))))

(define (instantiate-person r)
  (make-thing
   (person-recipe-id r)
   (person-recipe-name r)
   #:nouns
   (person-recipe-nouns r)
   #:adjectives
   (person-recipe-adjectives r)
   #:qualities
   (hash-set
    (hash-set
     (person-recipe-qualities r)
     'description
     (person-recipe-description r))
    'contents
    '())))

(define (thing-location t) (thing-ref-quality t 'location #f))

(define (thing-contents t) (thing-ref-quality t 'contents '()))

(define (thing-exits t) (thing-ref-quality t 'exits (hash)))

(define (sorted w)
  (sort (hash-values (world-things w)) symbol<? #:key thing-id))

(define (tok s)
  (filter
   (lambda (x) (not (string=? x "")))
   (string-split (string-downcase (string-trim s)))))

(define (match? t q)
  (define x (string-downcase (string-trim q)))
  (or (string=? x (symbol->string (thing-id t)))
      (string=? x (string-downcase (thing-name t)))
      (member x (map string-downcase (thing-nouns t)))
      (andmap
       (lambda (y)
         (or (member y (map string-downcase (thing-nouns t)))
             (member y (map string-downcase (thing-adjectives t)))))
       (tok x))))

(define (find-things w q (cs #f))
  (define xs (filter (lambda (t) (match? t q)) (or cs (sorted w))))
  (cond
   ((null? xs) (search-no-match q))
   ((null? (cdr xs)) (search-match (car xs)))
   (else (search-ambiguous q xs))))

(define (rm xs id) (filter (lambda (x) (not (equal? x id))) xs))

(define (world-move w id dest)
  (define t (world-ref-thing w id #f))
  (unless t (raise-arguments-error 'world-move "missing thing" "id" id))
  (unless (world-ref-thing w dest #f)
    (raise-arguments-error 'world-move "missing destination" "id" dest))
  (define p (thing-location t))
  (define w1
    (if p
      (world-update-thing
       w
       p
       (lambda (x)
         (thing-with-quality x 'contents (rm (thing-contents x) id))))
      w))
  (define w2
    (world-update-thing
     w1
     id
     (lambda (x) (thing-with-quality x 'location dest))))
  (world-update-thing
   w2
   dest
   (lambda (x)
     (thing-with-quality
      x
      'contents
      (append (rm (thing-contents x) id) (list id))))))

(define (world-collect w who id) (world-move w id who))

(define aliases
  (hash
   "?"
   'help
   "commands"
   'commands
   "look"
   'look
   "l"
   'look
   "move"
   'move
   "go"
   'move
   "trivia"
   'trivia
   "who"
   'who
   "whereami"
   'whereami
   "inventory"
   'inventory
   "i"
   'inventory
   "collect"
   'collect
   "get"
   'collect
   "say"
   'say
   "channel"
   'channel
   "talk"
   'talk
   "sell"
   'sell))

(define (parse-command input (exits (hash)))
  (cond
   ((not (string? input)) (parsed-command 'invalid '() input))
   (else
    (define p (tok input))
    (cond
     ((null? p) (parsed-command 'empty '() input))
     ((hash-has-key? exits (string->symbol (car p)))
      (parsed-command 'move (list (car p)) input))
     (else
      (parsed-command (hash-ref aliases (car p) 'unknown) (cdr p) input))))))

(define (id tag ref n to) (string->symbol (format "~a:~s:~a:~s" tag ref n to)))

(define (out to text ref (n 0))
  (make-message
   (id 'outbound-line ref n to)
   'outbound-line
   #:sender
   'mudlib
   #:audience
   to
   #:payload
   text
   #:references
   (list ref)))

(define (by-ids w ids)
  (sort
   (filter values (map (lambda (i) (world-ref-thing w i #f)) ids))
   symbol<?
   #:key
   thing-id))

(define (room w p) (and p (world-ref-thing w (thing-location p) #f)))

(define (room-look w actor r)
  (if (not r)
    "You are nowhere."
    (string-join
     (list
      (thing-name r)
      (thing-ref-quality r 'description "")
      (format
       "Contents: ~a"
       (let ((x (by-ids w (rm (thing-contents r) actor))))
         (if (null? x) "nothing" (string-join (map thing-name x) ", "))))
      (format
       "Exits: ~a"
       (let ((x (sort (hash-keys (thing-exits r)) symbol<?)))
         (if (null? x) "none" (string-join (map symbol->string x) ", ")))))
     "\n")))

(define (target-look w p r args)
  (match
   (find-things
    w
    (string-join args " ")
    (by-ids
     w
     (append (if p (thing-contents p) '()) (if r (thing-contents r) '()))))
   ((search-match t)
    (format "~a\n~a" (thing-name t) (thing-ref-quality t 'description "")))
   ((search-no-match _) "You do not see that here.")
   ((search-ambiguous _ ts)
    (format "Be more specific: ~a" (string-join (map thing-name ts) ", ")))))

(define (pick xs rng)
  (and (pair? xs)
       (list-ref
        xs
        (min
         (sub1 (length xs))
         (inexact->exact (floor (* (rng) (length xs))))))))

(define (command->messages w actor c (rng random) (ref actor))
  (define p (world-ref-thing w actor #f))
  (define r (room w p))
  (define a (parsed-command-arguments c))
  (case (parsed-command-verb c)
    ((commands help)
     (list
      (out
       actor
       (string-append
        "commands: "
        (string-join
         (sort (map symbol->string standard-command-registry) string<?)
         ", "))
       ref)))
    ((look)
     (list
      (out
       actor
       (if (null? a) (room-look w actor r) (target-look w p r a))
       ref)))
    ((whereami)
     (list (out actor (if r (thing-name r) "You are nowhere.") ref)))
    ((who)
     (define sessions
       (world-ref-metadata w active-session-metadata-key (hash)))
     (define names (if (hash? sessions) (hash-values sessions) '()))
     (list
      (out
       actor
       (string-join (sort (remove-duplicates names) string<?) ", ")
       ref)))
    ((inventory)
     (list
      (out
       actor
       (if p
         (string-join (map thing-name (by-ids w (thing-contents p))) ", ")
         "You have no inventory.")
       ref)))
    ((trivia)
     (list
      (out
       actor
       (or (and r (pick (thing-ref-quality r 'trivia '()) rng))
           "There is no trivia here.")
       ref)))
    ((say)
     (define rid (and p (thing-location p)))
     (for/list
      ((x
        (in-list
         (filter
          (lambda (t)
            (and (equal? (thing-location t) rid)
                 (thing-ref-quality t 'person? #f)))
          (sorted w))))
       (n (in-naturals)))
      (out
       (thing-id x)
       (format "~a says: ~a" (if p (thing-name p) actor) (string-join a " "))
       ref
       n)))
    ((channel talk)
     (if (null? a)
       (list (out actor "usage: channel NAME MESSAGE" ref))
       (let ((ch (string->symbol (car a))))
         (for/list
          ((to
            (in-list
             (sort (world-ref-metadata w (list 'channel ch) '()) symbol<?)))
           (n (in-naturals)))
          (out to (format "[~a] ~a" ch (string-join (cdr a) " ")) ref n)))))
    ((sell)
     (if (null? a)
       (list (out actor "usage: sell ITEM" ref))
       (list
        (make-message
         (id 'exchange ref 0 actor)
         'exchange-request
         #:sender
         actor
         #:payload
         (exchange-request 'sell (string->symbol (car a)))
         #:references
         (list ref)))))
    (else (list (out actor "I do not understand." ref)))))

(define (make-command-handler rng)
  (lambda (schedule! w m)
    (define who (mud-message-sender m))
    (define p (world-ref-thing w who #f))
    (define r (room w p))
    (define c
      (if (parsed-command? (mud-message-payload m))
        (mud-message-payload m)
        (parse-command (mud-message-payload m) (if r (thing-exits r) (hash)))))
    (cond
     ((and (eq? (parsed-command-verb c) 'move)
           p
           r
           (pair? (parsed-command-arguments c)))
      (define d
        (hash-ref
         (thing-exits r)
         (string->symbol (car (parsed-command-arguments c)))
         #f))
      (if d
        (begin
          (schedule! (out who "You move." (mud-message-id m)))
          (world-move w who d))
        (begin
          (schedule! (out who "There is no exit that way." (mud-message-id m)))
          w)))
     ((and (eq? (parsed-command-verb c) 'collect)
           p
           r
           (pair? (parsed-command-arguments c)))
      (match
       (find-things
        w
        (string-join (parsed-command-arguments c) " ")
        (by-ids w (thing-contents r)))
       ((search-match t)
        (if (thing-ref-quality t 'collectible? #f)
          (begin
            (schedule! (out who "Collected." (mud-message-id m)))
            (world-collect w who (thing-id t)))
          (begin
            (schedule! (out who "You cannot collect that." (mud-message-id m)))
            w)))
       (_
        (for
         ((x (in-list (command->messages w who c rng (mud-message-id m)))))
         (schedule! x))
        w)))
     (else
      (for
       ((x (in-list (command->messages w who c rng (mud-message-id m)))))
       (schedule! x))
      w))))

(define (make-mud-action id payload probability #:audience (audience #f))
  (unless (symbol? id) (raise-argument-error 'make-mud-action "symbol?" id))
  (unless (and (real? probability) (<= 0 probability 1))
    (raise-argument-error 'make-mud-action "real in [0,1]" probability))
  (mud-action id payload probability audience))

(define (actions t)
  (define x (thing-ref-quality t 'actions #f))
  (cond
   (x
    (unless (and (list? x) (andmap mud-action? x))
      (raise-arguments-error
       'logical-tick->messages
       "list of mud-action?"
       "thing"
       (thing-id t)))
    x)
   ((thing-ref-quality t 'action #f)
    (list
     (make-mud-action
      'legacy
      (thing-ref-quality t 'action)
      (thing-ref-quality t 'action-probability 1))))
   (else '())))

(define (logical-tick->messages w rng (ref 'logical-tick))
  (append-map
   (lambda (t)
     (for/list
      ((a (in-list (actions t)))
       (n (in-naturals))
       #:when
       (< (rng) (mud-action-probability a)))
      (make-message
       (id (mud-action-id a) ref n (thing-id t))
       (mud-action-id a)
       #:sender
       (thing-id t)
       #:audience
       (mud-action-audience a)
       #:payload
       (mud-action-payload a)
       #:references
       (list ref))))
   (sorted w)))

(define (standard-mud-library (rng random))
  (define (tick schedule! w m)
    (for
     ((x
       (in-list
        (logical-tick->messages
         w
         (if (procedure? (mud-message-payload m)) (mud-message-payload m) rng)
         (mud-message-id m)))))
     (schedule! x))
    w)
  (make-library
   'mudlib
   #:handlers
   (list
    (make-handler 'command (make-command-handler rng))
    (make-handler 'logical-tick tick))))

(define make-standard-library standard-mud-library)

