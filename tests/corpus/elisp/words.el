;;; words.el --- count words -*- lexical-binding: t -*-
;; ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ comment

;;; Commentary:
;; Counts the words in a buffer.

;;; Code:

(require 'subr-x)

(defgroup words nil
  ;; ^^^^ special
  "Counting words."
  :group 'convenience)

(defcustom words-limit 10
  ;; ^^^^^ special     ^^ number
  "The most words a report lists."
  :type 'integer)

(defvar words--seen nil
  "The words counted so far.")

(defun words-count (text)
  ;; ^ special
  "Count the words in TEXT."
  ;; ^^^^^^^^^^^^^^^^^^^^^^^ doc
  (let ((table (make-hash-table :test #'equal)))
    ;;                          ^^^^^ symbol
    (dolist (word (split-string text))
      ;; ^^ special
      (unless (string-empty-p word)
        (puthash word (1+ (gethash word table 0)) table)))
    table))

(defun words-report ()
  "Show a report of the current buffer."
  (interactive)
  (if-let ((table (words-count (buffer-string))))
      (message "%d words, ratio %s" (hash-table-count table) 1.5)
      ;;       ^^^^^^^^^^^^^^^^^^^^ string                   ^^^ number
    (message "nothing")))

(provide 'words)
;;; words.el ends here
