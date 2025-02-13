;;; shadow.el --- locate Emacs Lisp file shadowings  -*- lexical-binding: t; -*-

;; Copyright (C) 1995, 2001-2023 Free Software Foundation, Inc.

;; Author: Terry Jones <terry@santafe.edu>
;; Keywords: lisp
;; Created: 15 December 1995

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

;; The functions in this file detect (`load-path-shadows-find')
;; and display (`list-load-path-shadows') potential load-path
;; problems that arise when Emacs Lisp files "shadow" each other.
;;
;; For example, a file XXX.el early in one's load-path will shadow
;; a file with the same name in a later load-path directory.  When
;; this is unintentional, it may result in problems that could have
;; been easily avoided.  This occurs often (to me) when installing a
;; new version of Emacs and something in the site-lisp directory
;; has been updated and added to the Emacs distribution.  The old
;; version, now outdated, shadows the new one.  This is obviously
;; undesirable.
;;
;; The `list-load-path-shadows' function was run when you installed
;; this version of Emacs.  To run it by hand in emacs:
;;
;;     M-x list-load-path-shadows
;;
;; or run it non-interactively via:
;;
;;     emacs -batch -f list-load-path-shadows
;;
;; Thanks to Francesco Potortì <pot@cnuce.cnr.it> for suggestions,
;; rewritings & speedups.

;;; Code:

(defgroup lisp-shadow nil
  "Locate Emacs Lisp file shadowings."
  :prefix "load-path-shadows-"
  :group 'lisp)

(defcustom load-path-shadows-compare-text nil
  "If non-nil, then shadowing files are reported only if their text differs.
This is slower, but filters out some innocuous shadowing."
  :type 'boolean)

(defun load-path-shadows-find (&optional path)
  "Return a list of Emacs Lisp files that create shadows.
This function does the work for `list-load-path-shadows'.

We traverse PATH looking for shadows, and return a \(possibly empty)
even-length list of files.  A file in this list at position 2i shadows
the file in position 2i+1.  Emacs Lisp file suffixes \(.el and .elc)
are stripped from the file names in the list.

See the documentation for `list-load-path-shadows' for further information."
  (let (true-names			; List of dirs considered.
	shadows				; List of shadowings, to be returned.
	files				; File names ever seen, with dirs.
	dir				; The dir being currently scanned.
        dir-case-insensitive            ; `file-name-case-insensitive-p' of dir.
	curr-files			; This dir's Emacs Lisp files.
	orig-dir			; Where the file was first seen.
	files-seen-this-dir)		; Files seen so far in this dir.
    (dolist (pp (or path load-path))
      (setq dir (directory-file-name (file-truename (or pp "."))))
      (if (member dir true-names)
	  ;; We have already considered this PATH redundant directory.
	  ;; Show the redundancy if we are interactive, unless the PATH
	  ;; dir is nil or "." (these redundant directories are just a
	  ;; result of the current working directory, and are therefore
	  ;; not always redundant).
	  (or noninteractive
	      (and pp
		   (not (string= pp "."))
		   (message "Ignoring redundant directory %s" pp)))

	(setq true-names (append true-names (list dir)))
	(setq dir (directory-file-name (or pp ".")))
	(setq curr-files (if (file-accessible-directory-p dir)
			     (directory-files dir nil
                                              "\\.elc?\\(?:\\.gz\\)?\\'" t)))
	(and curr-files
	     (not noninteractive)
	     (message "Checking %d files in %s..." (length curr-files) dir))

	(setq files-seen-this-dir nil)
        ;; We assume that case sensitivity of a directory applies to
        ;; its files.
        (setq dir-case-insensitive (file-name-case-insensitive-p dir))

	(dolist (file curr-files)

	  (if (string-match "\\.gz\\'" file)
	      (setq file (substring file 0 -3)))
	  (setq file (substring
		      file 0 (if (string= (substring file -1) "c") -4 -3)))

	  ;; FILE now contains the current file name, with no suffix.
	  (unless (or (member file files-seen-this-dir)
		      ;; Ignore these files.
		      (member file
                              (list "subdirs" "leim-list"
				    (file-name-sans-extension dir-locals-file)
                                    (concat
				     (file-name-sans-extension dir-locals-file)
                                     "-2"))))
	    ;; File has not been seen yet in this directory.
	    ;; This test prevents us declaring that XXX.el shadows
	    ;; XXX.elc (or vice-versa) when they are in the same directory.
	    (setq files-seen-this-dir (cons file files-seen-this-dir))

            (if (setq orig-dir
                      (assoc file files
                             (and dir-case-insensitive
                                  #'string-equal-ignore-case)))
		;; This file was seen before, we have a shadowing.
		;; Report it unless the files are identical.
                (let ((base1 (concat (cdr orig-dir) "/" (car orig-dir)))
		      (base2 (concat dir "/" file)))
		  (if (not (and load-path-shadows-compare-text
				(load-path-shadows-same-file-or-nonexistent
				 (concat base1 ".el") (concat base2 ".el"))
				;; This is a bit strict, but safe.
				(load-path-shadows-same-file-or-nonexistent
				 (concat base1 ".elc") (concat base2 ".elc"))))
		      (setq shadows
			    (append shadows (list base1 base2)))))

	      ;; Not seen before, add it to the list of seen files.
	      (push (cons file dir) files))))))
    ;; Return the list of shadowings.
    shadows))

;; Return true if neither file exists, or if both exist and have identical
;; contents.
(defun load-path-shadows-same-file-or-nonexistent (f1 f2)
  (let ((exists1 (file-exists-p f1))
	(exists2 (file-exists-p f2)))
    (or (and (not exists1) (not exists2))
	(and exists1 exists2
	     (or (equal (file-truename f1) (file-truename f2))
		 ;; As a quick test, avoiding spawning a process, compare file
		 ;; sizes.
		 (and (= (file-attribute-size (file-attributes f1))
			 (file-attribute-size (file-attributes f2)))
		      (eq 0 (call-process "cmp" nil nil nil "-s" f1 f2))))))))

(defvar load-path-shadows-font-lock-keywords
  ;; The idea is that shadows of files supplied with Emacs are more
  ;; serious than various versions of external packages shadowing each
  ;; other.
  `((,(format "hides \\(%s.*\\)"
	      (file-name-directory
	       (or (locate-library "simple")
		   (file-name-as-directory
		    (expand-file-name "../lisp" data-directory)))))
     . (1 font-lock-warning-face)))
  "Keywords to highlight in `load-path-shadows-mode'.")

(define-derived-mode load-path-shadows-mode special-mode "LP-Shadows"
  "Major mode for `load-path' shadows buffer."
  (setq-local font-lock-defaults
              '((load-path-shadows-font-lock-keywords)))
  (setq buffer-undo-list t))

;; TODO use text-properties instead, a la dired.
(define-button-type 'load-path-shadows-find-file
  'follow-link t
;;  'face 'default
  'action (lambda (button)
	    (let ((file (concat (button-get button 'shadow-file) ".el")))
	      (or (file-exists-p file)
		  (setq file (concat file ".gz")))
	      (if (file-readable-p file)
		  (pop-to-buffer (find-file-noselect file))
		(error "Cannot read file"))))
  'help-echo "mouse-2, RET: find this file")


;;;###autoload
(defun list-load-path-shadows (&optional stringp)
  "Display a list of Emacs Lisp files that shadow other files.

If STRINGP is non-nil, returns any shadows as a string.
Otherwise, if interactive shows any shadows in a `*Shadows*' buffer;
else prints messages listing any shadows.

This function lists potential load path problems.  Directories in
the `load-path' variable are searched, in order, for Emacs Lisp
files.  When a previously encountered file name is found again, a
message is displayed indicating that the later file is \"hidden\" by
the earlier.

For example, suppose `load-path' is set to

\(\"/usr/share/emacs/site-lisp\" \"/usr/share/emacs/24.3/lisp\")

and that each of these directories contains a file called XXX.el.  Then
XXX.el in the site-lisp directory is referred to by all of:
\(require \\='XXX), (autoload .... \"XXX\"), (load-library \"XXX\") etc.

The first XXX.el file prevents Emacs from seeing the second (unless
the second is loaded explicitly via `load-file').

When not intended, such shadowings can be the source of subtle
problems.  For example, the above situation may have arisen because the
XXX package was not distributed with versions of Emacs prior to
24.3.  A system administrator downloaded XXX from elsewhere and installed
it.  Later, XXX was updated and included in the Emacs distribution.
Unless the system administrator checks for this, the new version of XXX
will be hidden behind the old (which may no longer work with the new
Emacs version).

This function performs these checks and flags all possible
shadowings.  Because a .el file may exist without a corresponding .elc
\(or vice-versa), these suffixes are essentially ignored.  A file
XXX.elc in an early directory (that does not contain XXX.el) is
considered to shadow a later file XXX.el, and vice-versa.

Shadowings are located by calling the (non-interactive) companion
function, `load-path-shadows-find'."
  (interactive)
  (let* ((shadows (load-path-shadows-find load-path))
	 (n (/ (length shadows) 2))
	 (msg (format "%s Emacs Lisp load-path shadowing%s found"
		      (if (zerop n) "No" (concat "\n" (number-to-string n)))
		      (if (= n 1) " was" "s were"))))
    (with-temp-buffer
      (while shadows
	(insert (format "%s hides %s\n" (car shadows)
			(car (cdr shadows))))
	(setq shadows (cdr (cdr shadows))))
      (if stringp
	  (buffer-string)
	(if (called-interactively-p 'interactive)
	    ;; We are interactive.
	    ;; Create the *Shadows* buffer and display shadowings there.
	    (let ((string (buffer-string)))
	      (with-current-buffer (get-buffer-create "*Shadows*")
		(display-buffer (current-buffer))
		(load-path-shadows-mode) ; run after-change-major-mode-hook
		(let ((inhibit-read-only t))
		  (erase-buffer)
		  (insert string)
		  (insert msg "\n")
		  (while (re-search-backward "\\(^.*\\) hides \\(.*$\\)"
					     nil t)
		    (dotimes (i 2)
		      (make-button (match-beginning (1+ i))
				   (match-end (1+ i))
				   'type 'load-path-shadows-find-file
				   'shadow-file
				   (match-string (1+ i)))))
		  (goto-char (point-max)))))
	  ;; We are non-interactive, print shadows via message.
	  (unless (zerop n)
	    (message "This site has duplicate Lisp libraries with the same name.
If a locally-installed Lisp library overrides a library in the Emacs release,
that can cause trouble, and you should probably remove the locally-installed
version unless you know what you are doing.\n")
	    (goto-char (point-min))
	    ;; Mimic the previous behavior of using lots of messages.
	    ;; I think one single message would look better...
	    (while (not (eobp))
	      (message "%s" (buffer-substring (line-beginning-position)
					      (line-end-position)))
	      (forward-line 1))
	    (message "%s" msg)))))))

(provide 'shadow)

;;; shadow.el ends here
