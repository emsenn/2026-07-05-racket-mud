#lang racket/base

;; Persistence is deliberately an adapter concern.  The engine receives only
;; messages and worlds; callers decide when a changed store becomes durable.
(require racket/file
         racket/match
         racket/path)

(provide (struct-out account)
         (struct-out legacy-credential)
         (struct-out credential-codec)
         (struct-out account-store)
         make-memory-account-store
         load-file-account-store
         account-store-ref
         account-store-put
         account-store-save!
         register-account
         authenticate-account)

;; `credential` is opaque to this module.  A production caller must supply a
;; vetted, salted password KDF through credential-codec; no password codec is
;; shipped here.
(struct account (name credential created-at) #:prefab)
(struct legacy-credential (plaintext) #:prefab)
(struct credential-codec (encode verify) #:transparent)
(struct account-store (accounts path) #:transparent)

(define (immutable-account-table table)
  (for/hash ([(name value) (in-hash table)])
    (values name value)))

(define (make-memory-account-store [accounts (hash)])
  (unless (hash? accounts)
    (raise-argument-error 'make-memory-account-store "hash?" accounts))
  (account-store (immutable-account-table accounts) #f))

(define (valid-account-table? value)
  (and (hash? value)
       (for/and ([(name value) (in-hash value)])
         (and (string? name) (account? value) (string=? name (account-name value))))))

(define (load-file-account-store path #:on-malformed [on-malformed 'error])
  (unless (path-string? path)
    (raise-argument-error 'load-file-account-store "path-string?" path))
  (unless (memq on-malformed '(error empty))
    (raise-argument-error 'load-file-account-store "(or/c 'error 'empty)" on-malformed))
  (cond
    [(not (file-exists? path)) (account-store (hash) path)]
    [else
     (with-handlers ([exn:fail?
                      (lambda (error)
                        (if (eq? on-malformed 'empty)
                            (account-store (hash) path)
                            (raise error)))])
       (define datum (call-with-input-file path read))
       (unless (valid-account-table? datum)
         (raise-arguments-error 'load-file-account-store
                                "account store has invalid data" "path" path))
       (account-store (immutable-account-table datum) path))]))

(define (account-store-ref store name [default #f])
  (unless (account-store? store)
    (raise-argument-error 'account-store-ref "account-store?" store))
  (hash-ref (account-store-accounts store) name default))

(define (account-store-put store value)
  (unless (account-store? store)
    (raise-argument-error 'account-store-put "account-store?" store))
  (unless (account? value)
    (raise-argument-error 'account-store-put "account?" value))
  (struct-copy account-store store
               [accounts (hash-set (account-store-accounts store)
                                   (account-name value) value)]))

(define (account-store-save! store)
  (unless (account-store? store)
    (raise-argument-error 'account-store-save! "account-store?" store))
  (define path (account-store-path store))
  (unless path
    (raise-arguments-error 'account-store-save! "store has no file path"))
  (define parent (or (path-only (simplify-path path)) (current-directory)))
  (make-directory* parent)
  ;; A same-directory temporary file makes the final replacement atomic on
  ;; ordinary local filesystems.  Restrictive mode is set before data is
  ;; written so an interrupted save does not expose credentials.
  (define temporary (make-temporary-file "racket-mud-accounts~a" #f parent))
  (dynamic-wind
    void
    (lambda ()
      (file-or-directory-permissions temporary #o600)
      (call-with-output-file temporary
        (lambda (out)
          (write (account-store-accounts store) out)
          (newline out)
          (flush-output out))
        #:exists 'truncate/replace)
      (rename-file-or-directory temporary path #t)
      (file-or-directory-permissions path #o600))
    (lambda ()
      (when (file-exists? temporary)
        (delete-file temporary))))
  (void))

(define (valid-password? value)
  (and (string? value) (positive? (string-length value))))

(define (register-account store codec name password #:created-at [created-at (current-seconds)])
  (unless (account-store? store)
    (raise-argument-error 'register-account "account-store?" store))
  (unless (credential-codec? codec)
    (raise-argument-error 'register-account "credential-codec?" codec))
  (unless (and (string? name) (positive? (string-length name)))
    (raise-argument-error 'register-account "non-empty-string?" name))
  (unless (valid-password? password)
    (raise-argument-error 'register-account "non-empty-string?" password))
  (when (account-store-ref store name #f)
    (raise-arguments-error 'register-account "account already exists" "name" name))
  (account-store-put store
                     (account name ((credential-codec-encode codec) password) created-at)))

;; Returns two values: authenticated? and successor store.  A successful
;; legacy comparison upgrades the stored credential once; neither branch logs
;; or returns the secret.
(define (authenticate-account store codec name password)
  (unless (account-store? store)
    (raise-argument-error 'authenticate-account "account-store?" store))
  (unless (credential-codec? codec)
    (raise-argument-error 'authenticate-account "credential-codec?" codec))
  (define found (account-store-ref store name #f))
  (cond
    [(or (not found) (not (valid-password? password))) (values #f store)]
    [(legacy-credential? (account-credential found))
     (if (string=? password (legacy-credential-plaintext (account-credential found)))
         (values #t (account-store-put store
                                      (account name
                                               ((credential-codec-encode codec) password)
                                               (account-created-at found))))
         (values #f store))]
    [else
     (values (and ((credential-codec-verify codec) password (account-credential found)) #t)
             store)]))
