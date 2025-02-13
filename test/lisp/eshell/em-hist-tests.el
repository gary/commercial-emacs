;;; em-hist-tests.el --- em-hist test suite  -*- lexical-binding:t -*-

;; Copyright (C) 2017-2023 Free Software Foundation, Inc.

;; This file is NOT part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Code:

(require 'ert)
(require 'ert-x)
(require 'em-hist)

(ert-deftest eshell-write-readonly-history ()
  "Test that having read-only strings in history is okay."
  (ert-with-temp-file histfile
    (let ((eshell-history-ring (make-ring 2)))
      (ring-insert eshell-history-ring
                   (propertize "echo foo" 'read-only t))
      (ring-insert eshell-history-ring
                   (propertize "echo bar" 'read-only t))
      (eshell-write-history histfile))))

(provide 'em-hist-test)

;;; em-hist-tests.el ends here
