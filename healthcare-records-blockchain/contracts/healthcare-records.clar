;; Healthcare Records NFT - A secure platform for patient records management
;; Using NFTs for access control on the Stacks blockchain

;; Import the audit trait
(use-trait audit-trait .audit-trait.audit-trait)

;; Error codes
(define-constant ERR_UNAUTHORIZED u1)
(define-constant ERR_NOT_FOUND u2)
(define-constant ERR_ALREADY_EXISTS u3)
(define-constant ERR_INVALID_INPUT u4)
(define-constant ERR_EXPIRED_ACCESS u5)
(define-constant ERR_EMERGENCY_INACTIVE u6)
(define-constant ERR_AUDIT_FAILED u7)

;; NFT definition for access tokens
(define-non-fungible-token healthcare-access-token uint)

;; Data Maps for storing patient records and access controls
(define-map patients 
  { patient-id: principal }
  { 
    name: (string-ascii 64),
    created-at: uint,
    record-hash: (string-ascii 64), ;; IPFS hash of encrypted medical records
    emergency-contact: (optional principal)
  }
)

;; Map to track which healthcare providers have access to which patients
(define-map access-controls
  { patient-id: principal, provider-id: principal }
  { 
    granted-at: uint,
    expires-at: uint,
    access-level: uint, ;; 1: Read, 2: Read/Write, 3: Admin
    token-id: uint,
    consent-proof: (string-ascii 64) ;; Hash of consent document
  }
)

;; Track emergency access situations
(define-map emergency-access
  { patient-id: principal }
  {
    active: bool,
    activated-by: principal,
    activated-at: uint,
    reason: (string-ascii 256)
  }
)

;; Map to track NFT metadata
(define-map token-metadata
  { token-id: uint }
  {
    patient: principal,
    provider: principal,
    access-level: uint,
    expires-at: uint
  }
)

;; Variables
(define-data-var admin principal tx-sender)
(define-data-var next-token-id uint u1)
(define-data-var audit-contract (optional principal) none) ;; Will be set during initialization

;; Initialize contract
(define-public (initialize (audit-contract-address <audit-trait>))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err ERR_UNAUTHORIZED))
    (var-set audit-contract (some (contract-of audit-contract-address)))
    (ok true)
  )
)

;; Validate string input is not empty
(define-private (validate-string (input (string-ascii 64)))
  (not (is-eq input ""))
)

;; Validate access level
(define-private (validate-access-level (level uint))
  (and (>= level u1) (<= level u3))
)

;; Validate expiration is in the future
(define-private (validate-expiration (expires-at uint))
  (> expires-at block-height)
)

;; Log access via audit contract
(define-private (log-access (patient-id principal) (provider-id principal) (action (string-ascii 64)))
  (match (var-get audit-contract)
    audit-addr (as-contract (contract-call? .audit-contract log-access-event patient-id provider-id action))
    (ok u0) ;; If audit contract not set yet, just return success
  )
)

;; Register a new patient
(define-public (register-patient 
  (name (string-ascii 64)) 
  (record-hash (string-ascii 64))
  (emergency-contact (optional principal)))
  (let 
    (
      (patient-id tx-sender)
    )
    ;; Validate inputs
    (asserts! (validate-string name) (err ERR_INVALID_INPUT))
    (asserts! (validate-string record-hash) (err ERR_INVALID_INPUT))
    
    ;; Check if patient already exists
    (asserts! (is-none (map-get? patients { patient-id: patient-id })) (err ERR_ALREADY_EXISTS))
    
    ;; Add patient to the map
    (map-set patients
      { patient-id: patient-id }
      {
        name: name,
        created-at: block-height,
        record-hash: record-hash,
        emergency-contact: emergency-contact
      }
    )
    
    ;; Log the registration
    (try! (log-access patient-id patient-id "patient-registration"))
    
    (ok true)
  )
)

;; Update emergency contact
(define-public (update-emergency-contact (new-contact (optional principal)))
  (let 
    (
      (patient-id tx-sender)
    )
    ;; Verify patient exists
    (let 
      (
        (patient-data (unwrap! (map-get? patients { patient-id: patient-id }) (err ERR_NOT_FOUND)))
      )
      ;; Update the emergency contact
      (map-set patients
        { patient-id: patient-id }
        (merge patient-data { emergency-contact: new-contact })
      )
      
      ;; Log the update
      (try! (log-access patient-id patient-id "update-emergency-contact"))
      
      (ok true)
    )
  )
)

;; Grant access to a healthcare provider via NFT
(define-public (grant-provider-access 
  (provider-id principal) 
  (access-level uint) 
  (expires-at uint)
  (consent-proof (string-ascii 64)))
  (let 
    (
      (patient-id tx-sender)
      (token-id (var-get next-token-id))
    )
    ;; Validate inputs
    (asserts! (not (is-eq provider-id tx-sender)) (err ERR_INVALID_INPUT))
    (asserts! (validate-access-level access-level) (err ERR_INVALID_INPUT))
    (asserts! (validate-expiration expires-at) (err ERR_INVALID_INPUT))
    (asserts! (validate-string consent-proof) (err ERR_INVALID_INPUT))
    
    ;; Verify patient exists
    (asserts! (is-some (map-get? patients { patient-id: patient-id })) (err ERR_NOT_FOUND))
    
    ;; Set access controls
    (map-set access-controls
      { patient-id: patient-id, provider-id: provider-id }
      {
        granted-at: block-height,
        expires-at: expires-at,
        access-level: access-level,
        token-id: token-id,
        consent-proof: consent-proof
      }
    )
    
    ;; Store token metadata
    (map-set token-metadata
      { token-id: token-id }
      {
        patient: patient-id,
        provider: provider-id,
        access-level: access-level,
        expires-at: expires-at
      }
    )
    
    ;; Mint NFT to provider
    (try! (nft-mint? healthcare-access-token token-id provider-id))
    
    ;; Increment token ID
    (var-set next-token-id (+ token-id u1))
    
    ;; Log the access grant
    (try! (log-access patient-id provider-id "grant-access"))
    
    (ok token-id)
  )
)

;; Revoke access from a healthcare provider
(define-public (revoke-provider-access (patient-id principal) (provider-id principal))
  (begin
    ;; Validate inputs
    (asserts! (not (is-eq provider-id patient-id)) (err ERR_INVALID_INPUT))
    
    ;; Check authorization - either the patient themselves or the admin can revoke
    (asserts! (or (is-eq tx-sender patient-id) (is-eq tx-sender (var-get admin))) (err ERR_UNAUTHORIZED))
    
    ;; Verify access exists
    (let 
      (
        (access (unwrap! (map-get? access-controls { patient-id: patient-id, provider-id: provider-id }) (err ERR_NOT_FOUND)))
        (token-id (get token-id access))
      )
      ;; Remove access controls
      (map-delete access-controls { patient-id: patient-id, provider-id: provider-id })
      
      ;; Burn NFT - only burn if the provider still owns it
      (if (is-eq (some provider-id) (nft-get-owner? healthcare-access-token token-id))
        (try! (nft-burn? healthcare-access-token token-id provider-id))
        true
      )
      
      ;; Remove token metadata
      (map-delete token-metadata { token-id: token-id })
      
      ;; Log the revocation
      (try! (log-access patient-id provider-id "revoke-access"))
      
      (ok true)
    )
  )
)

;; Update patient record hash (only by patient)
(define-public (update-record-hash (new-record-hash (string-ascii 64)))
  (let 
    (
      (patient-id tx-sender)
    )
    ;; Validate inputs
    (asserts! (validate-string new-record-hash) (err ERR_INVALID_INPUT))
    
    ;; Verify patient exists
    (let 
      (
        (patient-data (unwrap! (map-get? patients { patient-id: patient-id }) (err ERR_NOT_FOUND)))
      )
      ;; Update the record hash
      (map-set patients
        { patient-id: patient-id }
        (merge patient-data { record-hash: new-record-hash })
      )
      
      ;; Log the update
      (try! (log-access patient-id patient-id "update-record"))
      
      (ok true)
    )
  )
)

;; Activate emergency access (by emergency contact or admin)
(define-public (activate-emergency-access (patient-id principal) (reason (string-ascii 256)))
  (begin
    ;; Verify patient exists
    (let 
      (
        (patient-data (unwrap! (map-get? patients { patient-id: patient-id }) (err ERR_NOT_FOUND)))
        (emergency-contact (get emergency-contact patient-data))
      )
      ;; Check authorization
      (asserts! (or 
                  (is-eq tx-sender (var-get admin))
                  (and (is-some emergency-contact) (is-eq tx-sender (unwrap! emergency-contact (err ERR_UNAUTHORIZED))))
                ) 
                (err ERR_UNAUTHORIZED))
      
      ;; Set emergency access
      (map-set emergency-access
        { patient-id: patient-id }
        {
          active: true,
          activated-by: tx-sender,
          activated-at: block-height,
          reason: reason
        }
      )
      
      ;; Log the emergency activation
      (try! (log-access patient-id tx-sender "activate-emergency"))
      
      (ok true)
    )
  )
)

;; Deactivate emergency access
(define-public (deactivate-emergency-access (patient-id principal))
  (begin
    ;; Check authorization
    (asserts! (or 
                (is-eq tx-sender patient-id)
                (is-eq tx-sender (var-get admin))
              ) 
              (err ERR_UNAUTHORIZED))
    
    ;; Verify emergency access exists
    (asserts! (is-some (map-get? emergency-access { patient-id: patient-id })) (err ERR_NOT_FOUND))
    
    ;; Remove emergency access
    (map-delete emergency-access { patient-id: patient-id })
    
    ;; Log the deactivation
    (try! (log-access patient-id tx-sender "deactivate-emergency"))
    
    (ok true)
  )
)

;; Emergency access to patient records (for authorized providers during emergency)
(define-public (emergency-access-records (patient-id principal))
  (let 
    (
      (provider-id tx-sender)
      (emergency-status (map-get? emergency-access { patient-id: patient-id }))
    )
    ;; Verify emergency is active
    (asserts! (and (is-some emergency-status) (get active (unwrap! emergency-status (err ERR_EMERGENCY_INACTIVE)))) 
              (err ERR_EMERGENCY_INACTIVE))
    
    ;; Get patient data
    (let 
      (
        (patient-data (unwrap! (map-get? patients { patient-id: patient-id }) (err ERR_NOT_FOUND)))
      )
      ;; Log the emergency access
      (try! (log-access patient-id provider-id "emergency-access"))
      
      (ok patient-data)
    )
  )
)

;; Update patient record by healthcare provider
(define-public (provider-update-record (patient-id principal) (new-record-hash (string-ascii 64)))
  (begin
    ;; Validate inputs
    (asserts! (not (is-eq patient-id tx-sender)) (err ERR_INVALID_INPUT))
    (asserts! (validate-string new-record-hash) (err ERR_INVALID_INPUT))
    
    (let 
      (
        (provider-id tx-sender)
        (access (unwrap! (map-get? access-controls { patient-id: patient-id, provider-id: provider-id }) (err ERR_UNAUTHORIZED)))
        (patient-data (unwrap! (map-get? patients { patient-id: patient-id }) (err ERR_NOT_FOUND)))
      )
      ;; Check if provider has write access (level 2 or higher)
      (asserts! (>= (get access-level access) u2) (err ERR_UNAUTHORIZED))
      
      ;; Check if access is still valid
      (asserts! (< block-height (get expires-at access)) (err ERR_EXPIRED_ACCESS))
      
      ;; Update the record hash
      (map-set patients
        { patient-id: patient-id }
        (merge patient-data { record-hash: new-record-hash })
      )
      
      ;; Log the provider update
      (try! (log-access patient-id provider-id "provider-update-record"))
      
      (ok true)
    )
  )
)

;; Read patient data (only accessible by patient or authorized providers)
(define-public (get-patient-data (patient-id principal))
  (let 
    (
      (caller tx-sender)
      (patient-data (unwrap! (map-get? patients { patient-id: patient-id }) (err ERR_NOT_FOUND)))
    )
    ;; Allow access if caller is the patient
    (if (is-eq caller patient-id)
      (begin
        ;; Log the self-access (using non-read-only version)
        (try! (log-access patient-id caller "self-access"))
        (ok patient-data)
      )
      ;; Otherwise check if caller is an authorized provider
      (let 
        (
          (access (map-get? access-controls { patient-id: patient-id, provider-id: caller }))
          (emergency-status (map-get? emergency-access { patient-id: patient-id }))
        )
        ;; Check for emergency access first
        (if (and (is-some emergency-status) (get active (unwrap! emergency-status (err ERR_UNAUTHORIZED))))
          (begin
            ;; Log the emergency read (using non-read-only version)
            (try! (log-access patient-id caller "emergency-read"))
            (ok patient-data)
          )
          ;; Otherwise check for normal access
          (begin
            (asserts! (is-some access) (err ERR_UNAUTHORIZED))
            (let 
              (
                (access-data (unwrap! access (err ERR_UNAUTHORIZED)))
              )
              ;; Check if access is still valid
              (asserts! (< block-height (get expires-at access-data)) (err ERR_EXPIRED_ACCESS))
              
              ;; Log the provider read (using non-read-only version)
              (try! (log-access patient-id caller "provider-read"))
              
              (ok patient-data)
            )
          )
        )
      )
    )
  )
)

;; Check if a provider has access to a patient's records
(define-read-only (check-provider-access (patient-id principal) (provider-id principal))
  (let 
    (
      (access (map-get? access-controls { patient-id: patient-id, provider-id: provider-id }))
      (emergency-status (map-get? emergency-access { patient-id: patient-id }))
    )
    ;; Check for emergency access first
    (if (and (is-some emergency-status) (get active (unwrap! emergency-status (err u0))))
      (ok u3) ;; Emergency grants full access
      ;; Otherwise check normal access
      (if (is-some access)
        (let 
          (
            (access-data (unwrap! access (err u0)))
          )
          ;; Check if access is still valid
          (if (< block-height (get expires-at access-data))
            (ok (get access-level access-data))
            (ok u0) ;; Access expired
          )
        )
        (ok u0) ;; No access
      )
    )
  )
)

;; Get token owner
(define-read-only (get-token-owner (token-id uint))
  (ok (nft-get-owner? healthcare-access-token token-id))
)

;; Get token metadata
(define-read-only (get-token-metadata (token-id uint))
  (match (map-get? token-metadata { token-id: token-id })
    metadata (ok metadata)
    (err ERR_NOT_FOUND)
  )
)

;; Get emergency access status
(define-read-only (get-emergency-status (patient-id principal))
  (match (map-get? emergency-access { patient-id: patient-id })
    status (ok status)
    (err ERR_NOT_FOUND)
  )
)
