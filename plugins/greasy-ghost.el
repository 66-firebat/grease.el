;;; greasy-ghost.el --- Ghostel terminal integration for Grease  -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Greasy-ghost is a self-contained Grease plugin that bridges the Grease file
;; manager with Ghostel (the Ghostty-powered terminal emulator).
;;
;; Grease's built-in `M-e` (`grease-toggle`) opens grease at the ghostel
;; terminal's cwd and returns you to ghostel on quit, but it does not sync
;; grease navigation back to the terminal.  If you open grease at ~/projects,
;; navigate to ~/projects/foo/src, and quit, your ghostel terminal is still
;; in ~/projects.
;;
;; This plugin advises `grease-toggle' and `grease-open' with an
;; origin-tracking pattern: the ghostel buffer that was current when
;; Grease was toggled open is saved, and on the next toggle-quit that
;; exact terminal receives `cd <grease-root-dir> && clear'.  Even if
;; the user touches other buffers while Grease is open, the cd always
;; goes back to the originating terminal.
;;
;;   `greasy-ghost-cd-here` (bound to `C-c g` in grease-mode):
;;     Without quitting grease, cd the origin to the current grease
;;     directory.  Grease stays open — useful for keeping both panes
;;     visible (e.g., a vertical split with grease on left, terminal
;;     on right).
;;
;; ── Requirements ──
;;
;; This plugin expects ghostel to be installed and loaded.  If ghostel is
;; missing, the advice silently passes through (no cd, no error).
;;
;; ── Usage ──
;;
;; Place this file in Grease's `plugins/' directory and enable plugin
;; loading:
;;
;;   (setq grease-load-plugins t)
;;   (require 'grease)
;;
;; This plugin loads /after/ `(provide 'grease)', so all Grease symbols
;; (including `grease-quit', `grease-open', `grease--root-dir') are
;; available at load time.
;;
;; ── Grease keybindings added ──
;;
;;   C-c g   → `greasy-ghost-cd-here'  (cd origin terminal, keep grease open)

;;; Code:

(require 'cl-lib)

;; ════════════════════════════════════════════════════════════════════════════
;; ── Origin tracking ────────────────────────────────────────────────────────
;; ════════════════════════════════════════════════════════════════════════════
;; The origin is the ghostel buffer that was current at the moment Grease was
;; toggled open.  It is saved once and consumed on the next toggle-quit.
;; This guarantees the cd always targets the exact terminal the user came
;; from, even if other buffers were touched while Grease was open.

(defvar greasy-ghost--origin nil
  "Ghostel buffer that was current when Grease was last toggled open.
Nil if no origin has been recorded (or if the last origin was already
consumed by a toggle-quit).")

(defun greasy-ghost--save-origin (&rest _)
  "Save the current buffer as the ghostel origin for Grease.
Only saves if the current buffer is a live ghostel terminal with a
live shell process."
  (when (and (featurep 'ghostel)
             (fboundp 'ghostel-send-string)
             (derived-mode-p 'ghostel-mode)
             (bound-and-true-p ghostel--process)
             (process-live-p ghostel--process))
    (setq greasy-ghost--origin (current-buffer))))

;; ════════════════════════════════════════════════════════════════════════════
;; ── Helpers ────────────────────────────────────────────────────────────────
;; ════════════════════════════════════════════════════════════════════════════

(defun greasy-ghost--cd-buffer (buf dir)
  "Send `cd DIR && clear' to BUF's ghostel shell process.
BUF must be a live ghostel-mode buffer with a live process.
DIR is used as-is — caller is responsible for resolving it."
  (with-current-buffer buf
    (ghostel-send-string (format "cd %s && clear\n" dir))))

(defun greasy-ghost--valid-origin ()
  "Return `greasy-ghost--origin' if it is a live ghostel terminal.
Returns nil if the origin is nil, dead, or no longer in ghostel-mode."
  (when (and greasy-ghost--origin
             (buffer-live-p greasy-ghost--origin)
             (with-current-buffer greasy-ghost--origin
               (and (derived-mode-p 'ghostel-mode)
                    (bound-and-true-p ghostel--process)
                    (process-live-p ghostel--process))))
    greasy-ghost--origin))

;; ════════════════════════════════════════════════════════════════════════════
;; ── Interactive command ────────────────────────────────────────────────────
;; ════════════════════════════════════════════════════════════════════════════

(defun greasy-ghost-cd-here ()
  "Cd the ghostel origin to the current grease directory.
Sends `cd <dir> && clear' to the shell process of the ghostel buffer
that was current when Grease was last toggled open (the saved origin).

Does NOT quit grease — the grease buffer stays open.  Useful when
Grease and ghostel are side by side and you want to sync the terminal
without toggling the file manager.

Signals `user-error' if no ghostel origin has been recorded or
`grease--root-dir' is nil."
  (interactive)
  (when (derived-mode-p 'grease-mode)
    (unless (bound-and-true-p grease--root-dir)
      (user-error "Greasy-ghost: grease--root-dir is nil — buffer may not be fully initialised"))
    (let ((dir (expand-file-name grease--root-dir))
          (origin (greasy-ghost--valid-origin)))
      (unless origin
        (user-error "Greasy-ghost: no ghostel origin recorded — toggle Grease open from a ghostel terminal first"))
      (greasy-ghost--cd-buffer origin dir)
      (message "Greasy-ghost: cd → %s  [%s]" dir (buffer-name origin)))))

;; ════════════════════════════════════════════════════════════════════════════
;; ── Advice on grease-toggle ────────────────────────────────────────────────
;; ════════════════════════════════════════════════════════════════════════════
;; :before advice on `grease-toggle'.  When the current buffer is in
;; grease-mode and a ghostel origin has been recorded, cd the origin
;; terminal to `grease--root-dir' before grease-quit runs.  The origin
;; is consumed (set to nil) after use — a fresh origin is recorded the
;; next time Grease is toggled open from a ghostel terminal.

(defun greasy-ghost--before-grease-toggle ()
  "Before `grease-toggle' quits, cd the saved ghostel origin to this
grease buffer's root directory.  Consumes the origin after use."
  (when (and (derived-mode-p 'grease-mode)
             (bound-and-true-p grease--root-dir))
    (when-let ((origin (greasy-ghost--valid-origin)))
      (greasy-ghost--cd-buffer origin grease--root-dir)
      (setq greasy-ghost--origin nil))))

;; ════════════════════════════════════════════════════════════════════════════
;; ── Registration ───────────────────────────────────────────────────────────
;; ════════════════════════════════════════════════════════════════════════════

(with-eval-after-load 'grease
  ;; Save the ghostel origin when Grease opens (so we cd back on quit).
  (advice-add 'grease-open :before #'greasy-ghost--save-origin)
  ;; On toggle-quit, cd the origin before Grease closes.
  (advice-add 'grease-toggle :before #'greasy-ghost--before-grease-toggle)
  ;; Keybinding: cd origin to grease--root-dir without quitting.
  (define-key grease-mode-map (kbd "C-c g") #'greasy-ghost-cd-here))

(provide 'greasy-ghost)
;;; greasy-ghost.el ends here
