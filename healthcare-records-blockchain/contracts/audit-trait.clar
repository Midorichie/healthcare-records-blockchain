;; Define a trait for the audit contract interface
(define-trait audit-trait
  (
    ;; Log an access event with patient ID, accessor ID, and action
    (log-access-event (principal principal (string-ascii 64)) (response uint uint))
  )
)
