;;;; words.lisp --- counting words
;; ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ comment

(defpackage :words
  ;; ^^^^^^ special
  (:use :common-lisp)
  ;; ^^ symbol
  (:export #:count-words #:report))

(in-package :words)

(defparameter *limit* 10
  ;; ^^^^^^^^ special ^^ number
  "The most words a report lists.")

(defun count-words (text)
  ;; ^ special
  "A hash table of each word in TEXT to how often it occurs."
  ;; ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ string
  (let ((table (make-hash-table :test #'equal)))
    (loop for word in (split text)
          unless (string= word "")
            do (incf (gethash word table 0)))
    table))

(defun report (table &key (limit *limit*))
  (let ((pairs '()))
    (maphash (lambda (word n) (push (cons word n) pairs)) table)
    (subseq (sort pairs #'> :key #'cdr) 0 (min limit (length pairs)))))

(defmacro unless-empty ((var table) &body body)
  ;; ^^^^ special
  `(let ((,var ,table))
     (when (plusp (hash-table-count ,var))
       ,@body)))

(format t "ratio ~a~%" 1.5)
;;        ^^^^^^^^^^^^ string
