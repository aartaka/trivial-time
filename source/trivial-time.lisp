;;;; SPDX-FileCopyrightText: Artyom Bologov
;;;; SPDX-License-Identifier: BSD-2 Clause

(in-package :trivial-time)

#+ecl
(defun gc-allocated ()
  (ffi:c-inline
   () ()
   :object "ecl_make_unsigned_integer(GC_get_total_bytes())"
   :one-liner t))

(defmacro with-time ((&rest time-keywords)
                     (&rest multiple-value-args) form
                     &body body)
  "Measure the timing properties for FORM and bind them to TIME-KEYWORDS in BODY.
The values of FORM are bound to MULTIPLE-VALUE-ARGS.

Both TIME-KEYWORDS and MULTIPLE-VALUE-ARGS are destructuring lists,
allowing for &REST, &KEY etc. in them.

TIME-KEYWORDS is a &KEY destructuring list, but one may omit &KEY and
&ALLOW-OTHER-KEYS in it.

TIME-KEYWORDS are destructuring a keyword-indexed property list with:
- :REAL --- for real time (in seconds, float).
- :USER --- for user-space CPU use/run time (in seconds, float).
- :SYSTEM --- for system-space CPU use/run time (in seconds, float).
- :CYCLES --- for CPU cycles spent.
- :GC-COUNT --- for the times GC was invoked.
- :GC --- for time spend on GC (in seconds, float).
- :ALLOCATED --- for the amount of bytes consed.
- :ABORTED --- for whether the evaluation errored out.
- :FAULTS --- for the number of page faults (both major and minor).

Not all of properties are guaranteed to be there. More so: it's almost
always the case that some are missing."
  (let ((props (gensym "PROPS"))
        (values (gensym "VALUES")))
    `(let* ((,props (list))
            (,values (multiple-value-list
                      #+sbcl
                      (sb-ext::call-with-timing
                       (lambda (&key real-time-ms user-run-time-us system-run-time-us
                                  gc-real-time-ms gc-run-time-ms processor-cycles eval-calls
                                  lambdas-converted (page-faults 0) bytes-consed
                                  aborted)
                         (declare (ignorable processor-cycles eval-calls lambdas-converted
                                             ;; TODO
                                             gc-real-time-ms))
                         (push (cons :aborted aborted) ,props)
                         (when real-time-ms
                           (push (cons :real (/ real-time-ms 1000)) ,props))
                         (when user-run-time-us
                           (push (cons :user (/ user-run-time-us 1000000)) ,props))
                         (when system-run-time-us
                           (push (cons :system (/ system-run-time-us 1000000)) ,props))
                         (when gc-run-time-ms
                           (push (cons :gc (/ gc-run-time-ms 1000)) ,props))
                         (when processor-cycles
                           (push (cons :cycles processor-cycles) ,props))
                         (when bytes-consed
                           (push (cons :allocated bytes-consed) ,props))
                         (when (and page-faults (plusp page-faults))
                           (push (cons :faults page-faults) ,props)))
                       (lambda () ,form))
                      #+clozure
                      (let ((ccl::*report-time-function*
                              (lambda (&key form results elapsed-time user-time
                                         system-time gc-time bytes-allocated
                                         minor-page-faults major-page-faults
                                         swaps)
                                (declare (ignorable swaps form))
                                (let ((page-faults (+ minor-page-faults major-page-faults)))
                                  (unless (zerop page-faults)
                                    (push (cons :faults page-faults) ,props)))
                                (push (cons :allocated bytes-allocated) ,props)
                                (push (cons :real (/ elapsed-time internal-time-units-per-second)) ,props)
                                (push (cons :system (/ system-time internal-time-units-per-second)) ,props)
                                (push (cons :user (/ user-time internal-time-units-per-second)) ,props)
                                (push (cons :gc (/ gc-time internal-time-units-per-second)) ,props)
                                (values-list results))))
                        (ccl::report-time
                         ',form
                         (lambda ()
                           (handler-case
                               ,form
                             (serious-condition ()
                               (push (cons :aborted t) ,props)
                               nil)))))
                      #+clisp
                      (multiple-value-bind (old-real1 old-real2 old-run1 old-run2 old-gc1 old-gc2 old-space1 old-space2 old-gccount)
                          (system::%%time)
                        (multiple-value-prog1
                            (handler-case
                                ,form
                              (serious-condition ()
                                (push (cons :aborted t) ,props)
                                nil))
                          (multiple-value-bind (new-real1 new-real2 new-run1 new-run2 new-gc1 new-gc2 new-space1 new-space2 new-gccount)
                              (system::%%time)
                            (flet ((diff4 (newval1 newval2 oldval1 oldval2)
                                     (+ (* (- newval1 oldval1) internal-time-units-per-second)
                                        (- newval2 oldval2))))
                              (push (cons :real (/ (diff4 new-real1 new-real2 old-real1 old-real2)
                                                   internal-time-units-per-second))
                                    ,props)
                              (push (cons :user (/ (diff4 new-run1 new-run2 old-run1 old-run2)
                                                   internal-time-units-per-second))
                                    ,props)
                              (push (cons :allocated (system::delta4 new-space1 new-space2 old-space1 old-space2 24))
                                    ,props)
                              (let ((gc-time (diff4 new-gc1 new-gc2 old-gc1 old-gc2))
                                    (gc-count (- new-gccount old-gccount)))
                                (unless (zerop gc-time)
                                  (push (cons :gc (/ gc-time internal-time-units-per-second))
                                        ,props))
                                (unless (zerop gc-count)
                                  (push (cons :gc-count gc-count) ,props)))))))
                      #+allegro
                      (excl::time-a-funcall
                       (lambda (stream tgcu tgcs tu ts tr scons sother static
                                &optional pfmajor pfminor gcpfmajor gcpfminor threadu threads)
                         (declare (ignorable s sother static threadu threads))
                         ;; FIXME: printing the args gives:
                         ;; #<TERMINAL-SIMPLE-STREAM...> 21022 3169
                         ;; 25560 3957 29504 521699 212000 0 0 977 829
                         ;; 829 0 0
                         (push (cons :system (/ ts 1000000)) ,props)
                         (push (cons :user (/ tu 1000000)) ,props)
                         (push (cons :real (/ tr 1000000)) ,props)
                         ;; FIXME: Allegro seems to ignore sother and
                         ;; static?
                         (push (cons :allocated scons) ,props)
                         ;; pfmajor pfminor gcpfmajor gcpfminor are
                         ;; often ~1000 each???
                         ;;
                         ;; (let ((faults (+ (or pfmajor 0)
                         ;;                  (or pfminor 0)
                         ;;                  (or gcpfmajor 0)
                         ;;                  (or gcpfminor 0))))
                         ;;   (unless (zerop faults)
                         ;;     (push (cons :faults (+ (or pfmajor 0)
                         ;;                            (or pfminor 0)
                         ;;                            (or gcpfmajor 0)
                         ;;                            (or gcpfminor 0)))
                         ;;           ,props)))
                         (push (cons :gc (/ (+ tgcu tgcs) 1000000)) ,props))
                       *trace-output*
                       (lambda ()
                         (handler-case
                             ,form
                           (serious-condition ()
                             (push (cons :aborted t) ,props)
                             (values)))))
                      #-(or sbcl clozure clisp allegro)
                      (let* ((old-real-time (get-internal-real-time))
                             (old-run-time (get-internal-run-time))
                             #+ecl
                             (ecl-force-gc (si::gc t))
                             (old-gc-time
                               #+(and ecl (not boehm-gc))
                               (si::gc-time))
                             #+abcl
                             (runtime
                               (java:jstatic "getRuntime"
                                             (java:jclass "java.lang.Runtime")))
                             (old-bytes-allocated
                               #+(and ecl boehm-gc)
                               (si::gc-stats t)
                               #+(and ecl (not boehm-gc))
                               (gc-allocated)
                               #+abcl
                               (- (java:jcall "totalMemory" runtime)
                                  (java:jcall "freeMemory" runtime)))
                             (old-gc-count
                               #+(and ecl boehm-gc)
                               (nth-value 1 (si::gc-stats t))))
                        (declare (ignorable
                                  #+ecl ecl-force-gc
                                  old-gc-time old-gc-count old-bytes-allocated))
                        (multiple-value-prog1
                            (handler-case
                                ,form
                              (serious-condition ()
                                (push (cons :aborted t) ,props)
                                nil))
                          (push (cons :real (/ (- (get-internal-real-time)
                                                  old-real-time)
                                               internal-time-units-per-second))
                                ,props)
                          (push (cons :user (/ (- (get-internal-run-time)
                                                  old-run-time)
                                               internal-time-units-per-second))
                                ,props)
                          #+(and ecl (not boehm-gc))
                          (push (cons :gc (/ (- (si::gc-time) old-gc-time)
                                             internal-time-units-per-second))
                                ,props)
                          #+ecl
                          (push (cons :allocated
                                      (- #+boehm-gc (si::gc-stats t)
                                         #-boehm-gc (gc-allocated)
                                         old-bytes-allocated))
                                ,props)
                          #+abcl
                          (push (cons :allocated (max 0 (- (java:jcall "totalMemory" runtime)
                                                           (java:jcall "freeMemory" runtime)
                                                           old-bytes-allocated)))
                                ,props)
                          #+(and ecl boehm-gc)
                          (push (cons :gc-count (- (nth-value 1 (si::gc-stats t)) old-gc-count))
                                ,props))))))
       (destructuring-bind (,@(unless (member (car time-keywords) '(&key &rest))
                                (list '&key))
                            ,@time-keywords
                            ,@(unless (eq (car (last time-keywords)) '&allow-other-keys)
                                (list '&allow-other-keys)))
           (reduce #'append (mapcar (lambda (p) (list (car p) (cdr p))) ,props))
         (destructuring-bind (,@multiple-value-args)
             ,values
           ,@body)))))

(defgeneric %time (thunk form)
  (:method ((thunk function) form)
    (let ((decimal-length (ceiling (log internal-time-units-per-second 10))))
      (with-time (&key aborted real system user cycles gc-count gc allocated faults)
          (&rest values)
          (funcall thunk)
        (format *trace-output*
                "~&Time spent ~@[un~*~]successfully evaluating:~
~&~s~
~:[~2*~;~&Real time:         ~,vf seconds~]~
~:[~2*~;~&Run time (system): ~,vf seconds~]~
~:[~2*~;~&Run time (user):   ~,vf seconds~]~
~@[~&CPU cycles:        ~:d~]~
~@[~&GC:                ~d times~]~
~:[~2*~;~&GC time:           ~,vf seconds~]~
~@[~&Allocated:         ~:d bytes~]~
~@[~&Page faults:       ~:d~]~%"
                aborted form
                real decimal-length real
                system decimal-length system
                user decimal-length user
                cycles
                gc-count
                gc decimal-length gc
                allocated
                faults)
        (values-list values)))))

(defmacro time (&rest forms)
  "Execute FORMS and print timing information for them.
The values of last form in FORMS are returned unaltered.

Affected by:
- `with-time' implementation support.
- `*trace-output*' for printing.
- Printer variables for float format and form printing."
  (let ((form (if (= 1 (length forms))
                  (first forms)
                  (cons 'progn forms))))
    `(%time (lambda () ,form) (quote ,form))))

(defgeneric %benchmark (repeat thunk form)
  (:method ((repeat integer) (thunk function) form)
    (let (real-times
          system-times user-times
          gc-times allocated-bytes)
      (flet ((count-push-return ()
               (with-time (real system user gc allocated)
                   (&rest values)
                   (funcall thunk)
                 (declare (ignorable values))
                 (push real real-times)
                 (push system system-times)
                 (push user user-times)
                 (push gc gc-times)
                 (push allocated allocated-bytes)
                 (values-list values)))
             (avg (nums)
               (if nums
                   (/ (reduce #'+ nums)
                      (length nums))
                   0))
             (non-nil (nums)
               (remove nil nums)))
        (let* ((values (multiple-value-list
                        (loop repeat (1- repeat)
                              do (count-push-return)
                              finally (return (count-push-return)))))
               (real-times (non-nil real-times))
               (system-times (non-nil system-times))
               (user-times (non-nil user-times))
               (gc-times (non-nil gc-times))
               (allocated-bytes (non-nil allocated-bytes))
               (max-number-length
                 (reduce
                  #'max (append real-times system-times user-times gc-times allocated-bytes)
                  :initial-value 15
                  :key #'(lambda (num) (length (princ-to-string num)))))
               (unit-length 10))
          (format *trace-output*
                  "~&Benchmark for ~a runs of~
~&~s" repeat form)
          (format *trace-output* "~&~a~vt~a~vt~a~vt~a~vt~a~vt~a"
                  '-
                  20 'unit
                  (+ 20 unit-length) 'minimum
                  (+ 20 unit-length max-number-length) 'average
                  (+ 20 unit-length (* 2 max-number-length)) 'maximum
                  (+ 20 unit-length (* 3 max-number-length)) 'total)
          (loop for (name unit list)
                  in `((real-time "seconds" ,real-times)
                       (user-run-time "seconds" ,user-times)
                       (system-run-time "seconds" ,system-times)
                       (gc-run-time "seconds" ,gc-times)
                       (allocated "bytes" ,allocated-bytes))
                when list
                  do (format *trace-output*
                             "~&~a~vt~a~vt~f~vt~f~vt~f~vt~f~%"
                             name
                             20 unit
                             (+ 20 unit-length)
                             (cond
                               ((uiop:emptyp list) 0)
                               ((= 1 (length list)) (first list))
                               (t (reduce #'min list :initial-value most-positive-fixnum)))
                             (+ unit-length 20 max-number-length) (avg list)
                             (+ 20 unit-length (* 2 max-number-length)) (if list
                                                                            (reduce #'max list :initial-value 0.0)
                                                                            0)
                             (+ 20 unit-length (* 3 max-number-length)) (reduce #'+ list)))
          (values-list values))))))

(defmacro benchmark ((&optional (repeat 1000)) &body forms)
  "Run FORMS REPEAT times, recording `time'-ing data per every run.
Print the total and average statistics across the runs.
Return the values returned by the last evaluation of FORMS.

REPEAT defaults to 1000.

Affected by:
- `with-time' implementation support.
- `*trace-output*' for printing.
- Print variables for float format and form printing."
  (let ((form (if (= 1 (length forms))
                  (first forms)
                  (cons 'progn forms))))
    `(%benchmark ,repeat (lambda () ,form) (quote ,form))))
