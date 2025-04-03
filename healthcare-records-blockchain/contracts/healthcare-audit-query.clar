;; Healthcare Audit Query Contract (Querying Logs)
;; This contract queries audit log entries by making cross-contract read-only calls.

;; Error code
(define-constant ERR_NOT_FOUND u404)

;; The deployed address of the audit contract.
;; Replace the placeholder with the actual contract address after deployment.
(define-constant AUDIT_ADDR 'ST3J2AW... ) 

;; Helper: Get log count from the audit contract.
(define-read-only (get-log-count-from-audit)
  (contract-call? AUDIT_ADDR get-log-count)
)

;; Helper: Get an audit log entry from the audit contract.
(define-read-only (get-audit-log-from-audit (log-id uint))
  (contract-call? AUDIT_ADDR get-audit-log { log-id: log-id })
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Recursive helper for checking if a log exists.
;; Iterates from 'current' to 'end' and returns the first log-id that matches
;; the given patient-id, accessor-id, and action.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-private (check-log-recursive
  (patient-id principal)
  (accessor-id principal)
  (action (string-ascii 64))
  (current uint)
  (end uint)
)
  (if (> current end)
      u0
      (let ((log (get-audit-log-from-audit current)))
        (match log
          log-data (if (and
                        (is-eq (get patient-id log-data) patient-id)
                        (is-eq (get accessor-id log-data) accessor-id)
                        (is-eq (get action log-data) action))
                      current
                      (check-log-recursive patient-id accessor-id action (+ current u1) end)
                   )
          (check-log-recursive patient-id accessor-id action (+ current u1) end)
        )
      )
  )
)

;; Public function: check-log-exists
;; Returns the first log id that matches the given criteria, or u0 if not found.
(define-read-only (check-log-exists (patient-id principal) (accessor-id principal) (action (string-ascii 64)))
  (let ((log-count (unwrap! (get-log-count-from-audit) u0)))
    (ok (check-log-recursive patient-id accessor-id action u1 log-count))
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Recursive helper for retrieving patient logs.
;; Iterates from 'current' to 'end' and appends each log (that belongs to the given patient)
;; to the results list.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-private (get-logs-recursive
  (patient-id principal)
  (current uint)
  (end uint)
  (results (list 20 {
    log-id: uint,
    accessor-id: principal,
    action: (string-ascii 64),
    timestamp: uint,
    block-height: uint
  }))
)
  (if (or (> current end) (>= (len results) u20))
      results
      (let ((log (get-audit-log-from-audit current)))
        (match log
          log-data (if (is-eq (get patient-id log-data) patient-id)
                      (get-logs-recursive patient-id (+ current u1) end
                        (append results (list {
                          log-id: current,
                          accessor-id: (get accessor-id log-data),
                          action: (get action log-data),
                          timestamp: (get timestamp log-data),
                          block-height: (get block-height log-data)
                        }))
                      )
                      (get-logs-recursive patient-id (+ current u1) end results)
                   )
          (get-logs-recursive patient-id (+ current u1) end results)
        )
      )
  )
)

;; Public function: get-patient-logs
;; Returns up to `limit` logs for the given patient, starting from `offset`.
;; Maximum logs returned is capped at 20.
(define-read-only (get-patient-logs (patient-id principal) (limit uint) (offset uint))
  (let (
        (log-count (unwrap! (get-log-count-from-audit) u0))
        (effective-offset (if (> offset log-count) u0 offset))
        (end (+ effective-offset limit))
        (results (get-logs-recursive patient-id (+ u1 effective-offset) end (list)))
       )
    (ok results)
  )
)
