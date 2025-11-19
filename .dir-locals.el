;;; Directory Local Variables for Barista
;;; For more information see (info "(emacs) Directory Variables")

((nil . ((projectile-project-root . ".")
         (eval . (setq-local compile-command
                      (format "cd %s && cmake -B build -S . && cmake --build build"
                              (projectile-project-root))))
         (eval . (setq-local flycheck-clang-include-path
                      (list (expand-file-name "helpers")
                            (expand-file-name "helpers/event_providers")
                            (expand-file-name "gui"))))
         (eval . (setq-local company-clang-arguments
                      (list (concat "-I" (expand-file-name "helpers"))
                            (concat "-I" (expand-file-name "helpers/event_providers"))
                            (concat "-I" (expand-file-name "gui"))))
               )))
 (c-mode . ((c-file-style . "gnu")
            (c-basic-offset . 2)
            (indent-tabs-mode . nil)
            (flycheck-clang-language-standard . "c99")))
 (c++-mode . ((c-file-style . "gnu")
              (c-basic-offset . 2)
              (indent-tabs-mode . nil)
              (flycheck-clang-language-standard . "c++17")))
 (objc-mode . ((c-file-style . "gnu")
               (c-basic-offset . 2)
               (indent-tabs-mode . nil)
               (objc-basic-offset . 2)))
 (lua-mode . ((lua-indent-level . 2)
              (indent-tabs-mode . nil)))
 (sh-mode . ((sh-basic-offset . 2)
             (indent-tabs-mode . nil))))

