;; A functional queue: a front list and a reversed back list.
;; ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ comment
(define-record-type queue
  ;; ^^^^^^^^^^^^^^ special
  (make-queue front back)
  queue?
  (front queue-front)
  (back queue-back))

(define empty-queue (make-queue '() '()))

(define (enqueue q x)
  ;; ^^ special
  (make-queue (queue-front q)
              (cons x (queue-back q))))

(define (dequeue q)
  (cond
    ((pair? (queue-front q))
     (values (car (queue-front q))
             (make-queue (cdr (queue-front q)) (queue-back q))))
    ((null? (queue-back q)) (error "empty queue"))
    ;;                             ^^^^^^^^^^^^^ string
    (else (dequeue (make-queue (reverse (queue-back q)) '())))))
    ;; ^^ special

(define-syntax swap!
  ;; ^^^^^^^^^ special
  (syntax-rules ()
    ((_ a b)
     (let ((tmp a))
       (set! a b)
       (set! b tmp)))))

(define (queue->list q)
  (let loop ((q q) (acc '()))
    (if (and (null? (queue-front q)) (null? (queue-back q)))
        (reverse acc)
        (call-with-values (lambda () (dequeue q))
          ;;               ^^^^^^ special
          (lambda (x rest) (loop rest (cons x acc)))))))

(display "ratio: ")
(display 1.5)
;;       ^^^ number
(newline)
