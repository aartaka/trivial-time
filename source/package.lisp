;;;; SPDX-FileCopyrightText: Artyom Bologov
;;;; SPDX-License-Identifier: BSD-2 Clause

(uiop:define-package :trivial-time
  (:use :common-lisp)
  (:export #:with-time #:time #:benchmark)
  (:shadow #:time)
  (:documentation "`trivial-time' provides two macros for code timing/benchmarking:
- `time' counts the time, GC stats, and error rate of the code.
- `benchmark' runs the code X times and prints the aggregate stats.

There's also `with-time' as the underlying implementation between
these, available for use outside them."))
