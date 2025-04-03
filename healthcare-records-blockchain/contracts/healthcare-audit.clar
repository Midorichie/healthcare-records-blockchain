;; Healthcare Audit Contract for Healthcare Records
;; This contract stores an immutable log of all access events

;; Error codes
(define-constant ERR_UNAUTHORIZED u1)
(define-constant ERR_NOT_FOUND u2)

;; Data variable to store the admin principal
(define-data-var admin principal tx-sender)

;; Data variable to store the healthcare records contract principal
(define-data-var healthcare-records-contract (optional principal) none)

;; Data variable to track the next log ID
(define-data-var next-log-id uint u1)

;; Map to store audit logs
(define-map audit-logs
  { log-id: uint }
  {
    patient-id: principal,
    accessor-id: principal,
    action: (string-ascii 64),
    timestamp: uint,
    block-height: uint
  }
)

;; Initialize the contract with the healthcare records contract address
(define-public (initialize (healthcare-records-addr principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err ERR_UNAUTHORIZED))
    (var-set healthcare-records-contract (some healthcare-records-addr))
    (ok true)
  )
)

;; Log an access event
;; Can only be called by the healthcare records contract
(define-public (log-access-event (patient-id principal) (accessor-id principal) (action (string-ascii 64)))
  (let 
    (
      (caller-contract (unwrap! (contract-of tx-sender) (err ERR_UNAUTHORIZED)))
      (log-id (var-get next-log-id))
    )
    ;; Verify caller is the healthcare records contract
    (asserts! 
      (match (var-get healthcare-records-contract)
        records-contract (is-eq caller-contract records-contract)
        false
      )
      (err ERR_UNAUTHORIZED)
    )
    
    ;; Store the log
    (map-set audit-logs
      { log-id: log-id }
      {
        patient-id: patient-id,
        accessor-id: accessor-id,
        action: action,
        timestamp: (unwrap! (get-block-info? time block-height) u0),
        block-height: block-height
      }
    )
    
    ;; Increment log ID
    (var-set next-log-id (+ log-id u1))
    
    (ok log-id)
  )
)

;; Get the count of logs
(define-read-only (get-log-count)
  (ok (- (var-get next-log-id) u1))
)

;; Get a specific audit log
(define-read-only (get-audit-log (log-id uint))
  (match (map-get? audit-logs { log-id: log-id })
    log-data (ok log-data)
    (err ERR_NOT_FOUND)
  )
)

;; Check if a log is for a specific patient
(define-private (is-patient-log (log-id uint) (patient-id principal))
  (match (map-get? audit-logs { log-id: log-id })
    log-data (is-eq (get patient-id log-data) patient-id)
    false
  )
)

;; Check if a log is for a specific accessor
(define-private (is-accessor-log (log-id uint) (accessor-id principal))
  (match (map-get? audit-logs { log-id: log-id })
    log-data (is-eq (get accessor-id log-data) accessor-id)
    false
  )
)

;; Function to get logs by a list of IDs
(define-read-only (get-logs-by-ids (log-ids (list 10 uint)))
  (fold get-log-by-id-fold 
        (list) 
        log-ids)
)

;; Fold function for collecting logs by ID
(define-private (get-log-by-id-fold 
  (acc (list 10 {
    patient-id: principal,
    accessor-id: principal,
    action: (string-ascii 64),
    timestamp: uint,
    block-height: uint
  }))
  (log-id uint))
  (match (map-get? audit-logs { log-id: log-id })
    log-data (unwrap! (as-max-len? (append acc (list log-data)) u10) acc)
    acc
  )
)

;; Get the healthcare records contract address
(define-read-only (get-healthcare-records-contract)
  (ok (var-get healthcare-records-contract))
)

;; Get patient logs for a specific page
(define-read-only (get-patient-logs-page (patient-id principal) (page uint))
  (let
    (
      (log-count (- (var-get next-log-id) u1))
      (start-id (+ u1 (* page u10)))
      (end-id (min log-count (+ start-id u9)))
      (patient-log-ids (get-patient-log-ids patient-id start-id end-id))
    )
    (ok (get-logs-by-ids patient-log-ids))
  )
)

;; Helper to get list of log IDs for a patient
(define-private (get-patient-log-ids (patient-id principal) (start-id uint) (end-id uint))
  (get-log-ids-helper patient-id start-id end-id (list) true)
)

;; Get accessor logs for a specific page
(define-read-only (get-accessor-logs-page (accessor-id principal) (page uint))
  (let
    (
      (log-count (- (var-get next-log-id) u1))
      (start-id (+ u1 (* page u10)))
      (end-id (min log-count (+ start-id u9)))
      (accessor-log-ids (get-accessor-log-ids accessor-id start-id end-id))
    )
    (ok (get-logs-by-ids accessor-log-ids))
  )
)

;; Helper to get list of log IDs for an accessor
(define-private (get-accessor-log-ids (accessor-id principal) (start-id uint) (end-id uint))
  (get-log-ids-helper accessor-id start-id end-id (list) false)
)

;; Generic helper for getting log IDs that match a filter
;; is-patient-check: true to check patient ID, false to check accessor ID
(define-private (get-log-ids-helper 
  (principal-id principal) 
  (current-id uint) 
  (end-id uint) 
  (result (list 10 uint))
  (is-patient-check bool))
  (if (or (> current-id end-id) (>= (len result) u10))
    result
    (let
      (
        (matches-filter 
          (if is-patient-check
            (is-patient-log current-id principal-id)
            (is-accessor-log current-id principal-id)
          ))
      )
      (if matches-filter
        (get-log-ids-helper 
          principal-id 
          (+ current-id u1) 
          end-id 
          (unwrap! (as-max-len? (append result (list current-id)) u10) result)
          is-patient-check)
        (get-log-ids-helper principal-id (+ current-id u1) end-id result is-patient-check)
      )
    )
  )
)
