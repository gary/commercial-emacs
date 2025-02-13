;;; mhtml-mode.el --- HTML editing mode that handles CSS and JS -*- lexical-binding:t -*-

;; Copyright (C) 2017-2023 Free Software Foundation, Inc.

;; Keywords: wp, hypermedia, comm, languages

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

;;; Code:

(eval-when-compile (require 'cl-lib))
(eval-when-compile (require 'pcase))
(require 'sgml-mode)
(require 'js)
(require 'css-mode)
(require 'prog-mode)

(defcustom mhtml-tag-relative-indent t
  "How <script> and <style> bodies are indented relative to the tag.

When t, indentation looks like:

  <script>
    code();
  </script>

When nil, indentation of the script body starts just below the
tag, like:

  <script>
  code();
  </script>

When `ignore', the script body starts in the first column, like:

  <script>
code();
  </script>"
  :group 'sgml
  :type '(choice (const nil) (const t) (const ignore))
  :safe 'symbolp
  :version "26.1")

(cl-defstruct mhtml--submode
  ;; Name of this submode.
  name
  ;; HTML end tag.
  end-tag
  ;; Syntax table.
  syntax-table
  ;; Propertize function.
  propertize
  ;; Keymap.
  keymap
  ;; Captured locals that are set when entering a region.
  crucial-captured-locals
  ;; Other captured local variables; these are not set when entering a
  ;; region but let-bound during certain operations, e.g.,
  ;; indentation.
  captured-locals)

(defconst mhtml--crucial-variable-prefix
  (regexp-opt '("comment-" "uncomment-" "electric-indent-"
                "smie-" "forward-sexp-function" "completion-" "major-mode"
                "adaptive-fill-" "fill-" "normal-auto-fill-function"
                "paragraph-"))
  "Regexp matching the prefix of \"crucial\" buffer-locals we want to capture.")

(defconst mhtml--variable-prefix
  (regexp-opt '("font-lock-" "indent-line-function"))
  "Regexp matching the prefix of buffer-locals we want to capture.")

(defun mhtml--construct-submode (mode &rest args)
  "A wrapper for make-mhtml--submode that computes the buffer-local variables."
  (let ((captured-locals nil)
        (crucial-captured-locals nil)
        (submode (apply #'make-mhtml--submode args)))
    (with-temp-buffer
      (funcall mode)
      ;; Make sure font lock is all set up.
      (font-lock-ensure-keywords)
      ;; This has to be set to a value other than the mhtml-mode
      ;; value, to avoid recursion.
      (unless (variable-binding-locus 'font-lock-fontify-region-function)
        (setq-local font-lock-fontify-region-function
                    #'font-lock-default-fontify-region))
      (dolist (iter (buffer-local-variables))
        (when (string-match mhtml--crucial-variable-prefix
                            (symbol-name (car iter)))
          (push iter crucial-captured-locals))
        (when (string-match mhtml--variable-prefix (symbol-name (car iter)))
          (push iter captured-locals)))
      (setf (mhtml--submode-crucial-captured-locals submode)
            crucial-captured-locals)
      (setf (mhtml--submode-captured-locals submode) captured-locals))
    submode))

(defun mhtml--mark-buffer-locals (submode)
  (dolist (iter (mhtml--submode-captured-locals submode))
    (make-local-variable (car iter))))

(defvar-local mhtml--crucial-variables nil
  "List of all crucial variable symbols.")

(defun mhtml--mark-crucial-buffer-locals (submode)
  (dolist (iter (mhtml--submode-crucial-captured-locals submode))
    (make-local-variable (car iter))
    (push (car iter) mhtml--crucial-variables)))

(defconst mhtml--css-submode
  (mhtml--construct-submode 'css-mode
                            :name "CSS"
                            :end-tag "</style>"
                            :syntax-table css-mode-syntax-table
                            :propertize css-syntax-propertize-function
                            :keymap css-mode-map))

(defconst mhtml--js-submode
  (mhtml--construct-submode 'js-mode
                            :name "JS"
                            :end-tag "</script>"
                            :syntax-table js-mode-syntax-table
                            :propertize #'js-syntax-propertize
                            :keymap js-mode-map))

(defmacro mhtml--with-locals (submode &rest body)
  (declare (indent 1))
  `(cl-progv
       (when ,submode (mapcar #'car (mhtml--submode-captured-locals ,submode)))
       (when ,submode (mapcar #'cdr (mhtml--submode-captured-locals ,submode)))
     (cl-progv
         (when ,submode (mapcar #'car (mhtml--submode-crucial-captured-locals
                                       ,submode)))
         (when ,submode (mapcar #'cdr (mhtml--submode-crucial-captured-locals
                                       ,submode)))
       ,@body)))

(defun mhtml--submode-lighter ()
  "Mode-line lighter indicating the current submode."
  ;; The end of the buffer has no text properties, so in this case
  ;; back up one character, if possible.
  (let* ((where (if (and (eobp) (not (bobp)))
                    (1- (point))
                  (point)))
         (submode (get-text-property where 'mhtml-submode)))
    (if submode
        (mhtml--submode-name submode)
      "")))

(defun mhtml--submode-fontify-one-region (submode beg end &optional loudly)
  (if submode
      (mhtml--with-locals submode
        (save-restriction
          (font-lock-fontify-region beg end loudly)))
    (font-lock-ensure-keywords)
    (font-lock-default-fontify-region beg end loudly)))

(defun mhtml--submode-fontify-region (beg end loudly)
  (syntax-propertize end)
  (let ((orig-beg beg)
        (orig-end end)
        (new-beg beg)
        (new-end end))
    (while (< beg end)
      (let ((submode (get-text-property beg 'mhtml-submode))
            (this-end (next-single-property-change beg 'mhtml-submode
                                                   nil end)))
        (let ((extended (mhtml--submode-fontify-one-region submode beg
                                                           this-end loudly)))
          ;; If the call extended the region, take note.  We track the
          ;; bounds we were passed and take the union of any extended
          ;; bounds.
          (when (and (consp extended)
                     (eq (car extended) 'jit-lock-bounds))
            (setq new-beg (min new-beg (cadr extended)))
            ;; Make sure that the next region starts where the
            ;; extension of this region ends.
            (setq this-end (cddr extended))
            (setq new-end (max new-end this-end))))
        (setq beg this-end)))
    (when (or (/= orig-beg new-beg)
              (/= orig-end new-end))
      (cons 'jit-lock-bounds (cons new-beg new-end)))))

(defvar-local mhtml--last-submode nil
  "Record the last visited submode.
This is used by `mhtml--pre-command'.")

(defvar-local mhtml--stashed-crucial-variables nil
  "Alist of stashed values of the crucial variables.")

(defun mhtml--stash-crucial-variables ()
  (setq mhtml--stashed-crucial-variables
        (mapcar (lambda (sym)
                  (cons sym (buffer-local-value sym (current-buffer))))
                mhtml--crucial-variables)))

(defun mhtml--map-in-crucial-variables (alist)
  (dolist (item alist)
    (set (car item) (cdr item))))

(defun mhtml--pre-command ()
  (let ((submode (get-text-property (point) 'mhtml-submode)))
    (unless (eq submode mhtml--last-submode)
      ;; If we're entering a submode, and the previous submode was
      ;; nil, then stash the current values first.  This lets the user
      ;; at least modify some values directly.  FIXME maybe always
      ;; stash into the current mode?
      (when (and submode (not mhtml--last-submode))
        (mhtml--stash-crucial-variables))
      (mhtml--map-in-crucial-variables
       (if submode
           (mhtml--submode-crucial-captured-locals submode)
         mhtml--stashed-crucial-variables))
      (setq mhtml--last-submode submode))))

(defun mhtml--syntax-propertize-submode (submode end)
  (save-excursion
    (when (search-forward (mhtml--submode-end-tag submode) end t)
      (setq end (match-beginning 0))))
  (set-text-properties (point) end
                       (list 'mhtml-submode submode
                             'syntax-table (mhtml--submode-syntax-table submode)
                             ;; We want local-map here so that we act
                             ;; more like the sub-mode and don't
                             ;; override minor mode maps.
                             'local-map (mhtml--submode-keymap submode)))
  (funcall (mhtml--submode-propertize submode) (point) end)
  (goto-char end))

(defvar mhtml--syntax-propertize
  (syntax-propertize-rules
   ("<style.*?>"
    (0 (ignore
        (goto-char (match-end 0))
        ;; Don't apply in a comment.
        (unless (syntax-ppss-context (syntax-ppss))
          (mhtml--syntax-propertize-submode mhtml--css-submode end)))))
   ("<script.*?>"
    (0 (ignore
        (goto-char (match-end 0))
        ;; Don't apply in a comment.
        (unless (syntax-ppss-context (syntax-ppss))
          (mhtml--syntax-propertize-submode mhtml--js-submode end)))))
   sgml-syntax-propertize-rules))

(defun mhtml-syntax-propertize (start end)
  (let ((submode (get-text-property start 'mhtml-submode)))
    ;; First remove our special settings from the affected text.  They
    ;; will be re-applied as needed.
    (remove-list-of-text-properties start end
                                    '(syntax-table local-map mhtml-submode))
    (goto-char start)
    (if submode
        (mhtml--syntax-propertize-submode submode end)))
  (sgml-syntax-propertize (point) end mhtml--syntax-propertize))

(defun mhtml-indent-line ()
  "Indent the current line as HTML, JS, or CSS, according to its context."
  (interactive)
  (let ((submode (save-excursion
                   (back-to-indentation)
                   (get-text-property (point) 'mhtml-submode))))
    (if submode
        (save-restriction
          (let* ((region-start
                  (or (previous-single-property-change (point) 'mhtml-submode)
                      (point)))
                 (base-indent (save-excursion
                                (goto-char region-start)
                                (sgml-calculate-indent))))
            (cond
             ((eq mhtml-tag-relative-indent nil)
              (setq base-indent (- base-indent sgml-basic-offset)))
             ((eq mhtml-tag-relative-indent 'ignore)
              (setq base-indent 0)))
            (narrow-to-region region-start (point-max))
            (let ((prog-indentation-context (list base-indent)))
              (mhtml--with-locals submode
                ;; indent-line-function was rebound by
                ;; mhtml--with-locals.
                (funcall indent-line-function)))))
      ;; HTML.
      (sgml-indent-line))))

(declare-function flyspell-generic-progmode-verify "flyspell")

(defun mhtml--flyspell-check-word ()
  (let ((submode (get-text-property (point) 'mhtml-submode)))
    (if submode
        (flyspell-generic-progmode-verify)
      t)))

;; Support for hideshow.el (see `hs-special-modes-alist').
(defun mhtml-forward (arg)
  "Move point forward past a structured expression.
If point is on a tag, move to the end of the tag.
Otherwise, this calls `forward-sexp'.
Prefix arg specifies how many times to move (default 1)."
  (interactive "P")
  (pcase (get-text-property (point) 'mhtml-submode)
    ('nil (sgml-skip-tag-forward arg))
    (_submode (forward-sexp arg))))

;;;###autoload
(define-derived-mode mhtml-mode html-mode
  '((sgml-xml-mode "XHTML+" "HTML+") (:eval (mhtml--submode-lighter)))
  "Major mode based on `html-mode', but works with embedded JS and CSS.

Code inside a <script> element is indented using the rules from
`js-mode'; and code inside a <style> element is indented using
the rules from `css-mode'."
  (setq-local indent-line-function #'mhtml-indent-line)
  (setq-local syntax-propertize-function #'mhtml-syntax-propertize)
  (setq-local font-lock-fontify-region-function
              #'mhtml--submode-fontify-region)

  ;; Attach this to both pre- and post- hooks just in case it ever
  ;; changes a key binding that might be accessed from the menu bar.
  (add-hook 'pre-command-hook #'mhtml--pre-command nil t)
  (add-hook 'post-command-hook #'mhtml--pre-command nil t)

  ;; Make any captured variables buffer-local.
  (mhtml--mark-buffer-locals mhtml--css-submode)
  (mhtml--mark-buffer-locals mhtml--js-submode)

  (mhtml--mark-crucial-buffer-locals mhtml--css-submode)
  (mhtml--mark-crucial-buffer-locals mhtml--js-submode)
  (setq mhtml--crucial-variables (delete-dups mhtml--crucial-variables))

  ;: Hack
  (js--update-quick-match-re)

  ;; Setup the appropriate js-mode value of auto-fill-function.
  (setf (mhtml--submode-crucial-captured-locals mhtml--js-submode)
        (push (cons 'auto-fill-function
                    (if (and (boundp 'auto-fill-function) auto-fill-function)
                        #'js-do-auto-fill
                      nil))
              (mhtml--submode-crucial-captured-locals mhtml--js-submode)))

  ;; This mode might be using CC Mode's filling functionality.
  (c-foreign-init-lit-pos-cache)
  (add-hook 'before-change-functions #'c-foreign-truncate-lit-pos-cache nil t)

  ;; This is sort of a prog-mode as well as a text mode.
  (run-hooks 'prog-mode-hook))

(put 'mhtml-mode 'flyspell-mode-predicate #'mhtml--flyspell-check-word)

(provide 'mhtml-mode)

;;; mhtml-mode.el ends here
