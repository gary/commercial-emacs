;;; misearch.el --- isearch extensions for multi-buffer search  -*- lexical-binding: t; -*-

;; Copyright (C) 2007-2023 Free Software Foundation, Inc.

;; Author: Juri Linkov <juri@jurta.org>
;; Keywords: matching

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

;;; Commentary:

;; This file adds more dimensions to the search space.  It implements
;; various features that extend isearch.  One of them is an ability to
;; search through multiple buffers.

;;; Code:

(require 'cl-lib)

;;; Search multiple buffers

;;;###autoload (add-hook 'isearch-mode-hook 'multi-isearch-setup)

(defgroup multi-isearch nil
  "Using isearch to search through multiple buffers."
  :version "23.1"
  :group 'isearch)

(defcustom multi-isearch-search t
  "Non-nil enables searching multiple related buffers, in certain modes."
  :type 'boolean
  :version "23.1")

(defcustom multi-isearch-pause t
  "A choice defining where to pause the search.
If the value is nil, don't pause before going to the next buffer.
If the value is `initial', pause only after a failing search in the
initial buffer.
If t, pause in all buffers that contain the search string."
  :type '(choice
	  (const :tag "Don't pause" nil)
	  (const :tag "Only in initial buffer" initial)
	  (const :tag "All buffers" t))
  :version "23.1")

;;;###autoload
(defvar multi-isearch-next-buffer-function nil
  "Function to call to get the next buffer to search.

When this variable is set to a function that returns a buffer, then
after typing another \\[isearch-forward] or \\[isearch-backward] \
at a failing search, the search goes
to the next buffer in the series and continues searching for the
next occurrence.

This function should return the next buffer (it doesn't need to switch
to it), or nil if it can't find the next buffer (when it reaches the
end of the search space).

The first argument of this function is the current buffer where the
search is currently searching.  It defines the base buffer relative to
which this function should find the next buffer.  When the isearch
direction is backward (when option `isearch-forward' is nil), this function
should return the previous buffer to search.

If the second argument of this function WRAP is non-nil, then it
should return the first buffer in the series; and for the backward
search, it should return the last buffer in the series.")

;;;###autoload
(defvar multi-isearch-next-buffer-current-function nil
  "The currently active function to get the next buffer to search.
Initialized from `multi-isearch-next-buffer-function' when
Isearch starts.")

;;;###autoload
(defvar multi-isearch-current-buffer nil
  "The buffer where the search is currently searching.
The value is nil when the search still is in the initial buffer.")

;;;###autoload
(defvar multi-isearch-buffer-list nil
  "Sequence of buffers visited by multiple buffers Isearch.
This is nil if Isearch is not currently searching more than one buffer.")
;;;###autoload
(defvar multi-isearch-file-list nil
  "Sequence of files visited by multiple file buffers Isearch.")

(defvar multi-isearch-orig-search-fun nil)
(defvar multi-isearch-orig-wrap nil)
(defvar multi-isearch-orig-push-state nil)


;;;###autoload
(defun multi-isearch-setup ()
  "Set up isearch to search multiple buffers.
Intended to be added to `isearch-mode-hook'."
  (when (and multi-isearch-search
	     multi-isearch-next-buffer-function)
    (setq multi-isearch-current-buffer nil
	  multi-isearch-next-buffer-current-function
	  multi-isearch-next-buffer-function
	  multi-isearch-orig-search-fun
	  (default-value 'isearch-search-fun-function)
	  multi-isearch-orig-wrap
	  (default-value 'isearch-wrap-function)
	  multi-isearch-orig-push-state
	  (default-value 'isearch-push-state-function))
    (setq-default isearch-search-fun-function #'multi-isearch-search-fun
		  isearch-wrap-function       #'multi-isearch-wrap
		  isearch-push-state-function #'multi-isearch-push-state)
    (add-hook 'isearch-mode-end-hook #'multi-isearch-end)))

(defun multi-isearch-end ()
  "Clean up the multi-buffer search after terminating isearch."
  (setq multi-isearch-current-buffer nil
	multi-isearch-next-buffer-current-function nil
	multi-isearch-buffer-list nil
	multi-isearch-file-list nil)
  (setq-default isearch-search-fun-function multi-isearch-orig-search-fun
		isearch-wrap-function       multi-isearch-orig-wrap
		isearch-push-state-function multi-isearch-orig-push-state)
  (remove-hook 'isearch-mode-end-hook #'multi-isearch-end))

(defun multi-isearch-search-fun ()
  "Return the proper search function, for isearch in multiple buffers."
  (lambda (string bound noerror)
    (let ((search-fun
	   ;; Use standard functions to search within one buffer
	   (isearch-search-fun-default))
	  found buffer)
      (or
       ;; 1. First try searching in the initial buffer
       (let ((res (funcall search-fun string bound noerror)))
	 ;; Reset wrapping for all-buffers pause after successful search
	 (if (and res (not bound) (eq multi-isearch-pause t))
	     (setq multi-isearch-current-buffer nil))
	 res)
       ;; 2. If the above search fails, start visiting next/prev buffers
       ;; successively, and search the string in them.  Do this only
       ;; when bound is nil (i.e. not while lazy-highlighting search
       ;; strings in the current buffer).
       (when (and (not bound) multi-isearch-search)
	 ;; If no-pause or there was one attempt to leave the current buffer
	 (if (or (null multi-isearch-pause)
		 (and multi-isearch-pause multi-isearch-current-buffer))
	     (condition-case nil
		 (progn
		   (while (not found)
		     ;; Find the next buffer to search
		     (setq buffer (funcall multi-isearch-next-buffer-current-function
					   (or buffer (current-buffer)) nil))
		     (with-current-buffer buffer
		       (goto-char (if isearch-forward (point-min) (point-max)))
		       (setq isearch-barrier (point) isearch-opoint (point))
		       ;; After visiting the next/prev buffer search the
		       ;; string in it again, until the function in
		       ;; multi-isearch-next-buffer-current-function raises
		       ;; an error at the beginning/end of the buffer sequence.
		       (setq found (funcall search-fun string bound noerror))))
		   ;; Set buffer for isearch-search-string to switch
		   (if buffer (setq multi-isearch-current-buffer buffer))
		   ;; Return point of the new search result
		   found)
	       ;; Return nil when multi-isearch-next-buffer-current-function fails
	       ;; (`with-current-buffer' raises an error for nil returned from it).
	       (error (signal 'search-failed (list string "end of multi"))))
	   (signal 'search-failed (list string "repeat for next buffer"))))))))

(defun multi-isearch-wrap ()
  "Wrap the multiple buffers search when search is failed.
Switch buffer to the first buffer for a forward search,
or to the last buffer for a backward search.
Set `multi-isearch-current-buffer' to the current buffer to display
the isearch suffix message [initial buffer] only when isearch leaves
the initial buffer."
  (if (or (null multi-isearch-pause)
	  (and multi-isearch-pause multi-isearch-current-buffer))
      (progn
	(setq multi-isearch-current-buffer
	      (funcall multi-isearch-next-buffer-current-function
		       (current-buffer) t))
	(multi-isearch-switch-buffer)
	(goto-char (if isearch-forward (point-min) (point-max))))
    (setq multi-isearch-current-buffer (current-buffer))
    (setq isearch-wrapped nil)))

(defun multi-isearch-push-state ()
  "Save a function restoring the state of multiple buffers search.
Save the current buffer to the additional state parameter in the
search status stack."
  (let ((buf (current-buffer)))
    (lambda (cmd)
      (multi-isearch-pop-state cmd buf))))

(defun multi-isearch-pop-state (_cmd buffer)
  "Restore the multiple buffers search state in BUFFER.
Switch to the buffer restored from the search status stack."
  (unless (eq buffer (current-buffer))
    (setq multi-isearch-current-buffer buffer)
    (multi-isearch-switch-buffer)))

;;;###autoload
(defun multi-isearch-switch-buffer ()
  "Switch to the next buffer in multi-buffer search."
  (when (and (buffer-live-p multi-isearch-current-buffer)
             (not (eq multi-isearch-current-buffer (current-buffer))))
    (setq isearch-mode nil)
    (switch-to-buffer multi-isearch-current-buffer)
    (setq isearch-mode " M-Isearch")))


;;; Global multi-buffer search invocations

(defun multi-isearch-next-buffer-from-list (&optional buffer wrap)
  "Return the next buffer in the series of buffers.
This function is used for multiple buffers Isearch.  A sequence of
buffers is defined by the variable `multi-isearch-buffer-list'
set in `multi-isearch-buffers' or `multi-isearch-buffers-regexp'."
  (let ((buffers (if isearch-forward
		     multi-isearch-buffer-list
		   (reverse multi-isearch-buffer-list))))
    (if wrap
	(car buffers)
      (cadr (member buffer buffers)))))

(defvar ido-ignore-item-temp-list)  ; from ido.el

(defun multi-isearch-read-buffers ()
  "Return a list of buffers specified interactively, one by one."
  ;; Most code from `multi-occur'.
  (let* ((bufs (list (read-buffer "First buffer to search: "
				  (current-buffer) t)))
	 (buf nil)
	 (ido-ignore-item-temp-list bufs))
    (while (not (string-equal
		 (setq buf (read-buffer (multi-occur--prompt) nil t))
		 ""))
      (cl-pushnew buf bufs :test #'equal)
      (setq ido-ignore-item-temp-list bufs))
    (nreverse bufs)))

(defun multi-isearch-read-matching-buffers ()
  "Return a list of buffers whose names match specified regexp.
Uses `read-regexp' to read the regexp."
  ;; Most code from `multi-occur-in-matching-buffers'
  ;; and `kill-matching-buffers'.
  (let ((bufregexp
	 (read-regexp "Search in buffers whose names match regexp")))
    (when bufregexp
      (delq nil (mapcar (lambda (buf)
			  (when (string-match bufregexp (buffer-name buf))
			    buf))
			(buffer-list))))))

;;;###autoload
(defun multi-isearch-buffers (buffers)
  "Start multi-buffer Isearch on a list of BUFFERS.
This list can contain live buffers or their names.
Interactively read buffer names to search, one by one, ended with RET.
With a prefix argument, ask for a regexp, and search in buffers
whose names match the specified regexp."
  (interactive
   (list (if current-prefix-arg
	     (multi-isearch-read-matching-buffers)
	   (multi-isearch-read-buffers))))
  (let ((multi-isearch-next-buffer-function
	 'multi-isearch-next-buffer-from-list))
    (setq multi-isearch-buffer-list (mapcar #'get-buffer buffers))
    (switch-to-buffer (car multi-isearch-buffer-list))
    (goto-char (if isearch-forward (point-min) (point-max)))
    (isearch-forward nil t)))

;;;###autoload
(defun multi-isearch-buffers-regexp (buffers)
  "Start multi-buffer regexp Isearch on a list of BUFFERS.
This list can contain live buffers or their names.
Interactively read buffer names to search, one by one, ended with RET.
With a prefix argument, ask for a regexp, and search in buffers
whose names match the specified regexp."
  (interactive
   (list (if current-prefix-arg
	     (multi-isearch-read-matching-buffers)
	   (multi-isearch-read-buffers))))
  (let ((multi-isearch-next-buffer-function
	 'multi-isearch-next-buffer-from-list))
    (setq multi-isearch-buffer-list (mapcar #'get-buffer buffers))
    (switch-to-buffer (car multi-isearch-buffer-list))
    (goto-char (if isearch-forward (point-min) (point-max)))
    (isearch-forward-regexp nil t)))


;;; Global multi-file search invocations

(defun multi-isearch-next-file-buffer-from-list (&optional buffer wrap)
  "Return the next buffer in the series of file buffers.
This function is used for multiple file buffers Isearch.  A sequence
of files is defined by the variable `multi-isearch-file-list' set in
`multi-isearch-files' or `multi-isearch-files-regexp'.
Every next/previous file in the defined sequence is visited by
`find-file-noselect' that returns the corresponding file buffer."
  (let ((files (if isearch-forward
		   multi-isearch-file-list
		 (reverse multi-isearch-file-list))))
    (find-file-noselect
     (if wrap
	 (car files)
       (cadr (member (buffer-file-name buffer) files))))))

(defun multi-isearch-read-files ()
  "Return a list of files specified interactively, one by one."
  ;; Most code from `multi-occur'.
  (let* ((files (list (read-file-name "First file to search: "
				      default-directory
				      buffer-file-name)))
	 (file nil))
    (while (not (string-equal
		 (setq file (read-file-name
			     "Next file to search (RET to end): "
			     default-directory
			     default-directory))
		 default-directory))
      (cl-pushnew file files :test #'equal))
    (nreverse files)))

;; A regexp is not the same thing as a file glob - does this matter?
(defun multi-isearch-read-matching-files ()
  "Return a list of files whose names match specified wildcard.
Uses `read-regexp' to read the wildcard."
  ;; Most wildcard code from `find-file-noselect'.
  (let ((filename (read-regexp "Search in files whose names match wildcard")))
    (when (and filename
	       (not (string-match "\\`/:" filename))
	       (string-match "[[*?]" filename))
      (condition-case nil
	  (file-expand-wildcards filename t)
	(error (list filename))))))

;;;###autoload
(defun multi-isearch-files (files)
  "Start multi-buffer Isearch on a list of FILES.
Relative file names in this list are expanded to absolute
file names using the current buffer's value of `default-directory'.
Interactively read file names to search, one by one, ended with RET.
With a prefix argument, ask for a wildcard, and search in file buffers
whose file names match the specified wildcard."
  (interactive
   (list (if current-prefix-arg
	     (multi-isearch-read-matching-files)
	   (multi-isearch-read-files))))
  (let ((multi-isearch-next-buffer-function
	 'multi-isearch-next-file-buffer-from-list))
    (setq multi-isearch-file-list (mapcar #'expand-file-name files))
    (find-file (car multi-isearch-file-list))
    (goto-char (if isearch-forward (point-min) (point-max)))
    (isearch-forward nil t)))

;;;###autoload
(defun multi-isearch-files-regexp (files)
  "Start multi-buffer regexp Isearch on a list of FILES.
Relative file names in this list are expanded to absolute
file names using the current buffer's value of `default-directory'.
Interactively read file names to search, one by one, ended with RET.
With a prefix argument, ask for a wildcard, and search in file buffers
whose file names match the specified wildcard."
  (interactive
   (list (if current-prefix-arg
	     (multi-isearch-read-matching-files)
	   (multi-isearch-read-files))))
  (let ((multi-isearch-next-buffer-function
	 'multi-isearch-next-file-buffer-from-list))
    (setq multi-isearch-file-list (mapcar #'expand-file-name files))
    (find-file (car multi-isearch-file-list))
    (goto-char (if isearch-forward (point-min) (point-max)))
    (isearch-forward-regexp nil t)))

(defvar unload-function-defs-list)

(defun multi-isearch-unload-function ()
  "Remove autoloaded variables from `unload-function-defs-list'.
Also prevent the feature from being reloaded via `isearch-mode-hook'."
  (remove-hook 'isearch-mode-hook #'multi-isearch-setup)
  (let ((defs (list (car unload-function-defs-list)))
	(auto '(multi-isearch-next-buffer-function
		multi-isearch-next-buffer-current-function
		multi-isearch-current-buffer
		multi-isearch-buffer-list multi-isearch-file-list)))
    (dolist (def (cdr unload-function-defs-list))
      (unless (and (symbolp def)
		   (memq def auto))
	(push def defs)))
    (setq unload-function-defs-list (nreverse defs))
    ;; .
    nil))

(defalias 'misearch-unload-function #'multi-isearch-unload-function)


(provide 'multi-isearch)
(provide 'misearch)
;;; misearch.el ends here
