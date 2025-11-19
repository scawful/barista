;;; Barista Emacs Integration
;;; Provides Emacs integration for the Barista SketchyBar configuration

(require 'projectile)

(defgroup barista nil
  "Barista SketchyBar configuration integration"
  :group 'external)

(defcustom barista-config-dir (expand-file-name "~/.config/sketchybar")
  "Directory containing Barista configuration files"
  :type 'directory
  :group 'barista)

(defcustom barista-code-dir (expand-file-name "~/Code")
  "Directory containing code projects"
  :type 'directory
  :group 'barista)

(defun barista-find-config-file (filename)
  "Find a configuration file in the Barista config directory"
  (expand-file-name filename barista-config-dir))

(defun barista-open-main-config ()
  "Open the main.lua configuration file"
  (interactive)
  (find-file (barista-find-config-file "main.lua")))

(defun barista-open-state-json ()
  "Open the state.json configuration file"
  (interactive)
  (find-file (barista-find-config-file "state.json")))

(defun barista-open-profile (profile-name)
  "Open a specific profile file"
  (interactive "sProfile name: ")
  (find-file (barista-find-config-file (format "profiles/%s.lua" profile-name))))

(defun barista-reload-sketchybar ()
  "Reload SketchyBar configuration"
  (interactive)
  (async-shell-command "sketchybar --reload"))

(defun barista-open-control-panel ()
  "Open the Barista control panel"
  (interactive)
  (async-shell-command (format "%s/bin/config_menu_v2" barista-config-dir)))

;; Integration with yaze
(defun barista-open-yaze ()
  "Open Yaze ROM hacking toolkit"
  (interactive)
  (let ((yaze-path (expand-file-name "yaze/build/bin/yaze" barista-code-dir)))
    (if (file-exists-p yaze-path)
        (async-shell-command (format "open -a %s" yaze-path))
      (message "Yaze not found at %s" yaze-path))))

;; Integration with halext-org
(defun barista-open-halext-tasks ()
  "Open halext-org tasks"
  (interactive)
  (let ((script (barista-find-config-file "plugins/halext_menu.sh")))
    (if (file-exists-p script)
        (async-shell-command (format "%s open_tasks" script))
      (message "halext-org integration not configured"))))

;; Key bindings (optional)
(when (boundp 'barista-keymap)
  (define-key barista-keymap (kbd "C-c b m") 'barista-open-main-config)
  (define-key barista-keymap (kbd "C-c b s") 'barista-open-state-json)
  (define-key barista-keymap (kbd "C-c b r") 'barista-reload-sketchybar)
  (define-key barista-keymap (kbd "C-c b c") 'barista-open-control-panel))

(provide 'barista-integration)

