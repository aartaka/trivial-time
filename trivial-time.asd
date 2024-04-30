;;;; SPDX-FileCopyrightText: Artyom Bologov
;;;; SPDX-License-Identifier: BSD-2 Clause

(defsystem "trivial-time"
  :description "trivial-time allows timing a benchmarking a piece of code portably"
  :author "Artyom Bologov"
  :homepage "https://github.com/aartaka/trivial-time"
  :bug-tracker "https://github.com/aartaka/trivial-time/issues"
  :source-control (:git "https://github.com/aartaka/trivial-time.git")
  :license  "BSD-2 Clause"
  :version "0.0.0"
  :serial t
  :pathname "source/"
  :components ((:file "package")
               (:file "trivial-time")))
