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
;; This plugin advises `grease-toggle' so that pressing `M-e` from a grease
;; buffer automatically syncs the directory back to the ghostel terminal
;; that will receive focus after grease quits:
;;
;;   ─ Before `grease-toggle' runs its quit logic, the advice checks whether
;;     `(other-buffer (current-buffer) t)` — the buffer that will take focus
;;     after grease is killed — is a live ghostel terminal.  If it is, the
;;     advice sends `cd <grease-root-dir> && clear' to that terminal's shell
;;     process.  The cd happens unconditionally, before grease-quit.
;;
;;   `greasy-ghost-cd-here` (bound to `C-c g` in grease-mode):
;;     Without quitting grease, cd the alternate buffer to the current
;;     grease directory.  Grease stays open — useful for keeping both panes
;;     visible (e.g., a vertical split with grease on left, terminal on right).
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
;;   C-c g   → `greasy-ghost-cd-here'  (cd alternate buffer, keep grease open)

;;; Code:

(require 'cl-lib)

;; ════════════════════════════════════════════════════════════════════════════
;; ── Helpers ────────────────────────────────────────────────────────────────
;; ════════════════════════════════════════════════════════════════════════════

(defun greasy-ghost--alternate-ghostel-p ()
  "Return the alternate buffer if it is a live ghostel terminal, nil otherwise.
Uses `(other-buffer (current-buffer) t)' to predict which buffer will receive
focus after the current grease buffer is killed.

Returns nil if ghostel is not loaded, or if the alternate buffer is not in
`ghostel-mode', or if it has no live shell process."
  (when (and (featurep 'ghostel)
             (fboundp 'ghostel-send-string))
    (let ((alt (other-buffer (current-buffer) t)))
      (when (and alt
                 (buffer-live-p alt)
                 (with-current-buffer alt
                   (and (derived-mode-p 'ghostel-mode)
                        (bound-and-true-p ghostel--process)
                        (process-live-p ghostel--process))))
        alt))))

(defun greasy-ghost--cd-buffer (buf dir)
  "Send `cd DIR && clear' to BUF's ghostel shell process.
BUF must be a live ghostel-mode buffer with a live process.
DIR must be an existing directory."
  (with-current-buffer buf
    (ghostel-send-string (format "cd %s && clear\n" (expand-file-name dir)))))

;; ════════════════════════════════════════════════════════════════════════════
;; ── Interactive command ────────────────────────────────────────────────────
;; ════════════════════════════════════════════════════════════════════════════

(defun greasy-ghost-cd-here ()
  "Cd the alternate buffer to the current grease directory.
Sends `cd <dir> && clear' to the shell process of the buffer identified by
`(other-buffer (current-buffer) t)' — i.e., whatever buffer will receive
focus next.

Does NOT quit grease — the grease buffer stays open.  Useful when grease
and ghostel are side by side and you want to sync the terminal without
toggling the file manager.

Signals `user-error' if the alternate buffer is not a ghostel terminal or
`grease--root-dir' is nil."
  (interactive)
  (when (derived-mode-p 'grease-mode)
    (unless (bound-and-true-p grease--root-dir)
      (user-error "Greasy-ghost: grease--root-dir is nil — buffer may not be fully initialised"))
    (let* ((dir (expand-file-name grease--root-dir))
           (alt (greasy-ghost--alternate-ghostel-p)))
      (unless alt
        (user-error "Greasy-ghost: alternate buffer is not a live ghostel terminal"))
      (greasy-ghost--cd-buffer alt dir)
      (message "Greasy-ghost: cd → %s  [%s]" dir (buffer-name alt)))))

;; ════════════════════════════════════════════════════════════════════════════
;; ── Advice on grease-toggle ────────────────────────────────────────────────
;; ════════════════════════════════════════════════════════════════════════════
;; :before advice on `grease-toggle'.  When the current buffer is in
;; grease-mode and the alternate buffer is a ghostel terminal with a live
;; process, cd the terminal to `grease--root-dir' before grease-quit runs.
;; If ghostel isn't loaded or the alternate isn't a ghostel buffer, the
;; advice silently passes through — no error, no message.

(defun greasy-ghost--before-grease-toggle ()
  "Before `grease-toggle' quits, cd the alternate ghostel terminal to this
grease buffer's root directory."
  (when (and (derived-mode-p 'grease-mode)
             (bound-and-true-p grease--root-dir))
    (let ((alt (greasy-ghost--alternate-ghostel-p)))
      (when alt
        (greasy-ghost--cd-buffer alt grease--root-dir)))))

(advice-add 'grease-toggle :before #'greasy-ghost--before-grease-toggle)

;; ════════════════════════════════════════════════════════════════════════════
;; ── Keybinding ─────────────────────────────────────────────────────────────
;; ════════════════════════════════════════════════════════════════════════════

(with-eval-after-load 'grease
  (define-key grease-mode-map (kbd "C-c g") #'greasy-ghost-cd-here))

(provide 'greasy-ghost)
;;; greasy-ghost.el ends here
