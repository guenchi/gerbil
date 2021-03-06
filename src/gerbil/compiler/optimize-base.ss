;;; -*- Gerbil -*-
;;; (C) vyzo at hackzen.org
;;; gerbil compiler optimization passes
package: gerbil/compiler
namespace: gxc

(import :gerbil/expander
        "base"
        "compile"
        <syntax-case> <syntax-sugar>)
(export #t (import: <syntax-case> <syntax-sugar>))

(def current-compile-optimizer-info
  (make-parameter #f))
(def current-compile-mutators
  (make-parameter #f))
(def current-compile-local-type
  (make-parameter #f))

(defstruct optimizer-info (type ssxi)
  constructor: :init!)

(defmethod {:init! optimizer-info}
  (lambda (self)
    (struct-instance-init! self (make-hash-table-eq) (make-hash-table-eq))))

;;; optimizer-info: types
(defstruct !type (id))
(defstruct (!alias !type) ())
(defstruct (!struct-type !type) (super fields xfields ctor plist methods)
  constructor: :init!)
(defstruct (!procedure !type) ())
(defstruct (!struct-pred !procedure) ())
(defstruct (!struct-cons !procedure) ())
(defstruct (!struct-getf !procedure) (off unchecked?))
(defstruct (!struct-setf !procedure) (off unchecked?))
(defstruct (!lambda !procedure) (arity dispatch inline inline-typedecl)
  constructor: :init!)
(defstruct (!case-lambda !procedure) (clauses))
(defstruct (!kw-lambda !procedure) (table dispatch))
(defstruct (!kw-lambda-primary !procedure) (keys main))

(defmethod {:init! !struct-type}
  (lambda (self id super fields xfields ctor plist)
    (struct-instance-init! self id super fields xfields ctor plist #f)))

(defmethod {:init! !lambda}
  (lambda (self id arity dispatch (inline #f) (typedecl #f))
    (struct-instance-init! self id arity dispatch inline typedecl)))

(def (!struct-type-vtab type)
  (cond
   ((!struct-type-methods type) => values)
   (else
    (let (vtab (make-hash-table-eq))
      (set! (!struct-type-methods type) vtab)
      vtab))))

(def (!struct-type-lookup-method type method)
  (alet (vtab (!struct-type-methods type))
    (hash-get vtab method)))

(def (optimizer-declare-type! sym type (local? #f))
  (unless (!type? type)
    (error "bad declaration: expected !type" sym type))
  (verbose "declare-type " sym " " (struct->list type))
  (hash-put! (if local?
               (current-compile-local-type)
               (optimizer-info-type (current-compile-optimizer-info)))
             sym type))

(def (optimizer-clear-type! sym (local? #f))
  (verbose "clear-type " sym)
  (hash-remove! (if local?
                  (current-compile-local-type)
                  (optimizer-info-type (current-compile-optimizer-info)))
                sym))

(def (optimizer-declare-method! type-t method sym (rebind? #f))
  (let (type (optimizer-resolve-type type-t))
    (cond
     ((!struct-type? type)
      (let (vtab (!struct-type-vtab type))
        (cond
        (rebind? ; we don't track rebindable methods, so it shouldn't be there
         (if (hash-key? vtab method)
           (verbose "declare-method: [warning] skip rebind on existing method" type-t " " method)
           (verbose "declare-method: skip rebind method " type-t " " method)))
        ((hash-key? vtab method)
         (error "declare-method: duplicate method declaration"))
        (else
         (verbose "declare-method " type-t " " method " => " sym)
         (hash-put! vtab method sym)))))
     ((not type)
      (verbose "declare-method: unknown type "  type-t))
     (else
      (error "declare-method: bad method declaration; no method table" type-t type)))))

(def (optimizer-lookup-type sym)
  (or (alet (ht (current-compile-local-type))
        (hash-get ht sym))
      (hash-get (optimizer-info-type (current-compile-optimizer-info))
                sym)))

(def (optimizer-resolve-type sym)
  (alet (type (optimizer-lookup-type sym))
    (if (!alias? type)
      (optimizer-resolve-type (!type-id type))
      type)))

(def (optimizer-lookup-method type-t method)
  (let (type (optimizer-resolve-type type-t))
    (cond
     ((!struct-type? type)
      (!struct-type-lookup-method type method))
     (else #f))))

(def (identifier-symbol stx)
  (if (syntax-quote? stx)
    (generate-runtime-binding-id stx)
    (stx-e stx)))
