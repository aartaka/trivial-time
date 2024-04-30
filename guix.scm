;;;; SPDX-FileCopyrightText: Artyom Bologov
;;;; SPDX-License-Identifier: BSD-2 Clause

;;; Commentary:
;;
;; GNU Guix development package.  To build and install, clone this repository,
;; switch directory to here and run:
;;
;;   guix package --install-from-file=guix.scm
;;
;; To use as the basis for a development environment, run:
;;
;;   guix shell --container -D -f guix.scm
;;
;; Replace --container by --pure if you still want ASDF to see external
;; libraries in ~/common-lisp, etc.
;;
;;; Code:

(use-modules (guix packages)
             ((guix licenses) #:prefix license:)
             (guix gexp)
             (guix git-download)
             (guix build-system asdf)
             (gnu packages)
             (gnu packages lisp)
             (gnu packages lisp-check)
             (gnu packages lisp-xyz))

(define-public sbcl-trivial-time
  (package
   (name "sbcl-trivial-time")
   (version "0.0.0")
   (source
    (local-file (dirname (current-filename)) #:recursive? #t)
    ;;;; Or this, in case of contributing to Guix.
    ;; (origin
    ;;   (method git-fetch)
    ;;   (uri (git-reference
    ;;         (url "https://github.com/aartaka/trivial-time")
    ;;         (commit version)))
    ;;   (file-name (git-file-name "cl-trivial-time" version))
    ;;   (sha256
    ;;    (base32
    ;;     "SPECIFY-HASH")))
    )
   (build-system asdf-build-system/sbcl)
   ;; We use `cl-*' inputs and not `sbcl-*' ones so that CCL users can also use
   ;; this Guix manifests.
   ;;
   ;; Another reason is to not fail when an input dependency is found in
   ;; ~/common-lisp, which would trigger a rebuild of the SBCL input in the
   ;; store, which is read-only and would thus fail.
   ;;
   ;; The official Guix package should use `sbcl-*' inputs though.
   (native-inputs (list cl-lisp-unit2 sbcl))
   (inputs SPECIFY-INPUTS)
   (synopsis "ADD A SYNOPSYS.")
   (home-page "https://github.com/aartaka/trivial-time")
   (description "ADD A DESCRIPTION")
   (license license:bsd-3)))

(define-public cl-trivial-time
  (sbcl-package->cl-source-package sbcl-trivial-time))

(define-public ecl-trivial-time
  (sbcl-package->ecl-package sbcl-trivial-time))

cl-trivial-time
