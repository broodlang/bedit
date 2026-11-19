;; Count the words of each line.
;; ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ comment
(local words {})
;; ^^^ special

(fn count-line [line]
  "Count the words in `line`."
  (each [word (line:gmatch "%S+")]
    (tset words word (+ 1 (or (. words word) 0)))))

(fn report [limit]
  (let [sorted (icollect [word n (pairs words)]
                 ;; ^^^^ special
                 {:word word :n n})]
                 ;; ^^^ symbol
    (table.sort sorted (fn [a b] (> a.n b.n)))
    (for [i 1 (math.min limit (length sorted))]
      (print (. sorted i :word) (. sorted i :n)))))

(macro unless [test ...]
  ;; ^ special
  `(when (not ,test) ,...))

{:count-line count-line :report report :ratio 1.5 :ok true :none nil}
;;                                            ^^^ number         ^^^ symbol
;;                                                    ^^^^ symbol
