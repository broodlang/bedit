(ns app.core
  "Counting words."
  (:require [clojure.string :as str]))

;; the most a report lists
;; ^^^^^^^^^^^^^^^^^^^^^^^ comment
(def max-shown 3)
;; ^ special   ^ number

(defn count-words
  "A map of each word in `text` to how often it occurs."
  ;; ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ doc
  [text]
  (->> (str/split text #"\s+")
       (remove str/blank?)
       (frequencies)))

(defn report
  [counts]
  (let [top (take max-shown (sort-by val > counts))]
    (if (empty? top)
      :nothing
      ;; ^^^^^ symbol
      (for [[word n] top]
        (str word ": " n)))))

(defmacro unless
  ;; ^^^^ special
  [test & body]
  `(when-not ~test ~@body))

(comment
  (report (count-words "a b a"))
  {:ratio 1.5, :ok true, :none nil, :char \a})
  ;;      ^^^ number           ^^^ symbol
  ;;               ^^^^ symbol
