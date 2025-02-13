;;; fringe.el --- fringe setup and control  -*- lexical-binding:t -*-

;; Copyright (C) 2002-2023 Free Software Foundation, Inc.

;; Author: Simon Josefsson <simon@josefsson.org>
;; Maintainer: emacs-devel@gnu.org
;; Keywords: frames
;; Package: emacs

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

;; This file contains code to initialize the built-in fringe bitmaps
;; as well as helpful functions for customizing the appearance of the
;; fringe.

;; The code is influenced by scroll-bar.el and avoid.el.  The author
;; gratefully acknowledge comments and suggestions made by Miles
;; Bader, Eli Zaretskii, Richard Stallman, Pavel Janík and others which
;; improved this package.

;;; Code:

(defgroup fringe nil
  "Window fringes."
  :version "22.1"
  :group 'frames)

;; Define the built-in fringe bitmaps and setup default mappings

(when (boundp 'fringe-bitmaps)
  (let ((bitmaps '(question-mark exclamation-mark
		   left-arrow right-arrow up-arrow down-arrow
		   left-curly-arrow right-curly-arrow
		   large-circle
		   left-triangle right-triangle
		   top-left-angle top-right-angle
		   bottom-left-angle bottom-right-angle
		   left-bracket right-bracket
		   filled-rectangle hollow-rectangle
		   filled-square hollow-square
		   vertical-bar horizontal-bar
		   empty-line))
	(bn 1))
    (while bitmaps
      (push (car bitmaps) fringe-bitmaps)
      (put (car bitmaps) 'fringe bn)
      (setq bitmaps (cdr bitmaps)
	    bn (1+ bn))))

  (setq-default fringe-indicator-alist
		'((truncation . (left-arrow right-arrow))
		  (continuation . (left-curly-arrow right-curly-arrow))
		  (overlay-arrow . right-triangle)
		  (up . up-arrow)
		  (down . down-arrow)
		  (top . (top-left-angle top-right-angle))
		  (bottom . (bottom-left-angle bottom-right-angle
			     top-right-angle top-left-angle))
		  (top-bottom . (left-bracket right-bracket
				 top-right-angle top-left-angle))
		  (empty-line . empty-line)
		  (unknown . question-mark)))

  (setq-default fringe-cursor-alist
		'((box . filled-rectangle)
		  (hollow . hollow-rectangle)
		  (bar . vertical-bar)
		  (hbar . horizontal-bar)
		  (hollow-small . hollow-square))))


(defun fringe-bitmap-p (symbol)
  "Return non-nil if SYMBOL is a fringe bitmap."
  (get symbol 'fringe))


;; Control presence of fringes

(defvar fringe-mode)

(defvar fringe-mode-explicit nil
  "Non-nil means `set-fringe-mode' should really do something.
This is nil while loading `fringe.el', and t afterward.")

(defun set-fringe-mode-1 (_ignore value)
  "Call `set-fringe-mode' with VALUE.
See `fringe-mode' for valid values and their effect.
This is usually invoked when setting `fringe-mode' via customize."
  (set-fringe-mode value))

(defun set-fringe-mode (value)
  "Set `fringe-mode' to VALUE and put the new value into effect.
See `fringe-mode' for possible values and their effect."
  (fringe--check-style value)
  (setq fringe-mode value)
  (when fringe-mode-explicit
    (modify-all-frames-parameters
     (list (cons 'left-fringe (if (consp fringe-mode)
				  (car fringe-mode)
				fringe-mode))
	   (cons 'right-fringe (if (consp fringe-mode)
				   (cdr fringe-mode)
				 fringe-mode))))))

(defun fringe--check-style (style)
  (or (null style)
      (integerp style)
      (and (consp style)
	   (or (null (car style)) (integerp (car style)))
	   (or (null (cdr style)) (integerp (cdr style))))
      (error "Invalid fringe style `%s'" style)))

;; For initialization of fringe-mode, take account of changes
;; made explicitly to default-frame-alist.
(defun fringe-mode-initialize (symbol value)
  (let* ((left-pair (assq 'left-fringe default-frame-alist))
	 (right-pair (assq 'right-fringe default-frame-alist))
	 (left (cdr left-pair))
	 (right (cdr right-pair)))
    (if (or left-pair right-pair)
	;; If there's something in default-frame-alist for fringes,
	;; don't change it, but reflect that into the value of fringe-mode.
	(progn
	  (setq fringe-mode (cons left right))
	  (if (equal fringe-mode '(nil . nil))
	      (setq fringe-mode nil))
	  (if (equal fringe-mode '(0 . 0))
	      (setq fringe-mode 0)))
      ;; Otherwise impose the user-specified value of fringe-mode.
      (custom-initialize-reset symbol value))))

(defconst fringe-styles
  '(("default" . nil)
    ("no-fringes" . 0)
    ("right-only" . (0 . nil))
    ("left-only" . (nil . 0))
    ("half-width" . (4 . 4))
    ("minimal" . (1 . 1)))
  "Alist mapping fringe mode names to fringe widths.
Each list element has the form (NAME . WIDTH), where NAME is a
mnemonic fringe mode name and WIDTH is one of the following:
- nil, which means the default width (8 pixels).
- a cons cell (LEFT . RIGHT), where LEFT and RIGHT are
  respectively the left and right fringe widths in pixels, or
  nil (meaning the default width).
- a single integer, which specifies the pixel widths of both
  fringes.")

(defcustom fringe-mode nil
  "Default appearance of fringes on all frames.
The Lisp value should be one of the following:
- nil, which means the default width (8 pixels).
- a cons cell (LEFT . RIGHT), where LEFT and RIGHT are
  respectively the left and right fringe widths in pixels, or
  nil (meaning the default width).
- a single integer, which specifies the pixel widths of both
  fringes.
Note that the actual width may be rounded up to ensure that the
sum of the width of the left and right fringes is a multiple of
the frame's character width.  However, a fringe width of 0 is
never rounded.

When setting this variable from Customize, the user can choose
from the mnemonic fringe mode names defined in `fringe-styles'.

When setting this variable in a Lisp program, call
`set-fringe-mode' afterward to make it take real effect.

To modify the appearance of the fringe in a specific frame, use
the interactive function `set-fringe-style'.

Note that, despite the name, this is not a variable that controls
a (major or minor) Emacs mode, but controls the appearance of the
fringes."
  :type `(choice
          ,@ (mapcar (lambda (style)
                      (let ((name
                             (string-replace "-" " " (car style))))
                        `(const :tag
                                ,(concat (capitalize (substring name 0 1))
                                         (substring name 1))
                                ,(cdr style))))
                    fringe-styles)
          (integer :tag "Specific width")
          (cons :tag "Different left/right sizes"
                (integer :tag "Left width")
                (integer :tag "Right width")))
  :group 'fringe
  :require 'fringe
  :initialize 'fringe-mode-initialize
  :set 'set-fringe-mode-1)

;; We just set fringe-mode, but that was the default.
;; If it is set again, that is for real.
(setq fringe-mode-explicit t)

(defun fringe-query-style (&optional all-frames)
  "Query user for fringe style.
Returns values suitable for left-fringe and right-fringe frame parameters.
If ALL-FRAMES, the negation of the fringe values in
`default-frame-alist' is used when user enters the empty string.
Otherwise the negation of the fringe value in the currently selected
frame parameter is used."
  (let* ((mode (completing-read
                (concat
                 "Select fringe mode for "
                 (if all-frames "all frames" "selected frame")
                 ": ")
                fringe-styles nil t))
         (style (assoc (downcase mode) fringe-styles)))
    (cond
     (style
      (cdr style))
     ((not (eq 0 (cdr (assq 'left-fringe
			    (if all-frames
				default-frame-alist
			      (frame-parameters))))))
      0))))

(defun fringe-mode (&optional mode)
  "Set the default appearance of fringes on all frames.
When called interactively, query the user for MODE; valid values
are `no-fringes', `default', `left-only', `right-only', `minimal'
and `half-width'.  See `fringe-styles'.

When used in a Lisp program, MODE should be one of these:
- nil, which means the default width (8 pixels).
- a cons cell (LEFT . RIGHT), where LEFT and RIGHT are
  respectively the left and right fringe widths in pixels, or
  nil (meaning the default width).
- a single integer, which specifies the pixel widths of both
  fringes.

This command may round up the left and right width specifications
to ensure that their sum is a multiple of the character width of
a frame.  It never rounds up a fringe width of 0.

Note that removing a right or left fringe (by setting the width
to zero) makes Emacs reserve one column of the window body to
display a line continuation marker.  (This happens for both the
left and right fringe, since Emacs can display both left-to-right
and right-to-left text.)  You can use `window-max-chars-per-line'
to check the effective width.

Fringe widths set by `set-window-fringes' override the default
fringe widths set by this command.  This command applies to all
frames that exist and frames to be created in the future.  If you
want to set the default appearance of fringes on the selected
frame only, see the command `set-fringe-style'.

Note that, despite the name, this is not a (major or minor) Emacs
mode, but a command that controls the appearance of the fringes."
  (interactive (list (fringe-query-style 'all-frames)))
  (set-fringe-mode mode))

(defun set-fringe-style (&optional mode)
  "Set the default appearance of fringes on the selected frame.
When called interactively, query the user for MODE; valid values
are `no-fringes', `default', `left-only', `right-only', `minimal'
and `half-width'.  See `fringe-styles'.

When used in a Lisp program, MODE should be one of these:
- nil, which means the default width (8 pixels).
- a cons cell (LEFT . RIGHT), where LEFT and RIGHT are
  respectively the left and right fringe widths in pixels, or
  nil (meaning the default width).
- a single integer, which specifies the pixel widths of both
  fringes.
This command may round up the left and right width specifications
to ensure that their sum is a multiple of the character width of
a frame.  It never rounds up a fringe width of 0.

Fringe widths set by `set-window-fringes' override the default
fringe widths set by this command.  If you want to set the
default appearance of fringes on all frames, see the command
`fringe-mode'."
  (interactive (list (fringe-query-style)))
  (fringe--check-style mode)
  (modify-frame-parameters
   (selected-frame)
   (list (cons 'left-fringe (if (consp mode) (car mode) mode))
	 (cons 'right-fringe (if (consp mode) (cdr mode) mode)))))

(defsubst fringe-columns (side &optional real)
  "Return the width, measured in columns, of the fringe area on SIDE.
If optional argument REAL is non-nil, return a real floating point
number instead of a rounded integer value.
SIDE must be the symbol `left' or `right'."
  (funcall (if real '/ 'ceiling)
	   (or (funcall (if (eq side 'left) 'car 'cadr)
			(window-fringes))
	       0)
           (float (frame-char-width))))

;;;###autoload
(unless (fboundp 'define-fringe-bitmap)
  (defun define-fringe-bitmap (_bitmap _bits &optional _height _width _align)
    "Define fringe bitmap BITMAP from BITS of size HEIGHT x WIDTH.
BITMAP is a symbol identifying the new fringe bitmap.
BITS is either a string or a vector of integers.
HEIGHT is height of bitmap.  If HEIGHT is nil, use length of BITS.
WIDTH must be an integer between 1 and 16, or nil which defaults to 8.
Optional fifth arg ALIGN may be one of `top', `center', or `bottom',
indicating the positioning of the bitmap relative to the rows where it
is used; the default is to center the bitmap.  Fifth arg may also be a
list (ALIGN PERIODIC) where PERIODIC non-nil specifies that the bitmap
should be repeated.
If BITMAP already exists, the existing definition is replaced."
    ;; This is a fallback for non-GUI builds.
    ;; The real implementation is in src/fringe.c.
    ))

(defun fringe-custom-set-bitmap (symbol value)
  "Set SYMBOL to a fringe bitmap VALUE.
This sets the `fringe' property on SYMBOL to match that of VALUE,
and then force all windows to be updated on the next redisplay.
You should use this for the :set parameter for customization
options to pick a fringe bitmap."
  (prog1
      (set symbol value)
    (put symbol 'fringe (get value 'fringe))
    (force-window-update)))

(provide 'fringe)

;;; fringe.el ends here
