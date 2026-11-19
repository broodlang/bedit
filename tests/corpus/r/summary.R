#!/usr/bin/env Rscript
# the greeter
# ^^^^^^^^^^^ comment
library(dplyr)
# ^^^^^ function

MAX <- 0x10L
#      ^^^^^ number
names <- c("a", "b")
#          ^^^ string

greet <- function(who, loud = FALSE) {
  #      ^^^^^^^^ keyword
  if (is.null(who)) {
    return(NULL)
    #      ^^^^ constant
  } else if (loud) {
    # ^^ keyword
    print(toupper(paste("hi", who)))
  } else {
    message(sprintf("hello %s", who), 1.5, TRUE)
    #                                 ^^^ number
    #                                      ^^^^ constant
  }
  for (each in names) {
    next
    # ^^ keyword
  }
  while (FALSE) {
    break
    # ^^^ keyword
  }
  result <- switch(
    who,
    a = 1,
    b = 2
  )
  doubled <- lapply(names, function(item) {
    #        ^^^^^^ function
    item
  })
  squared <- \(x) x^2
  names |>
    toupper()
  stats::median(c(1, 2, NA, Inf))
  # ^^^ special         ^^ constant
  #      ^^^^^^ function    ^^^ constant
  invisible(NA_character_)
}

Greeter <- R6::R6Class(
  "Greeter",
  public = list(
    name = NULL
  )
)

shout = function(text) toupper(text)