;; Healthcare Records NFT - A secure platform for patient records management
;; Using NFTs for access control on the Stacks blockchain

;; Error codes
(define-constant ERR_UNAUTHORIZED u1)
(define-constant ERR_NOT_FOUND u2)
(define-constant ERR_ALREADY_EXISTS u3)

;; NFT definition for access tokens
(define-non-fungible-token healthcare-access-token uint)

;; Data Maps for storing patient records and access controls
(define-map patients 
  { patient-id: principal }
  { 
    name: (string-ascii 64),
    created-at: uint,
    record-hash: (string-ascii 64) ;; IPFS hash of encrypted medical records
  }
)

;; Map to track which healthcare providers have access to which patients
(define-map access-controls
  { patient-id: principal, provider-id: principal }
  { 
    granted-at: uint,
    expires-at: uint,
    access-level: uint, ;; 1: Read, 2: Read/Write, 3: Admin
    token-id: uint
  }
)

;; Map to track NFT metadata
(define-map token-metadata
  { token-id: uint }
  {
    patient: principal,
    provider: principal
  }
)

;; Variables
(define-data-var admin principal tx-sender)
(define-data-var next-token-id uint u1)

;; Initialize contract
(define-public (initialize)
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err ERR_UNAUTHORIZED))
    (ok true)
  )
)

;; Register a new patient
(define-public (register-patient (name (string-ascii 64)) (record-hash (string-ascii 64)))
  (let 
    (
      (patient-id tx-sender)
    )
    ;; Check if patient already exists
    (asserts! (is-none (map-get? patients { patient-id: patient-id })) (err ERR_ALREADY_EXISTS))
    
    ;; Add patient to the map
    (map-set patients
      { patient-id: patient-id }
      {
        name: name,
        created-at: block-height,
        record-hash: record-hash
      }
    )
    (ok true)
  )
)

;; Grant access to a healthcare provider via NFT
(define-public (grant-provider-access (provider-id principal) (access-level uint) (expires-at uint))
  (let 
    (
      (patient-id tx-sender)
      (token-id (var-get next-token-id))
    )
    ;; Verify patient exists
    (asserts! (is-some (map-get? patients { patient-id: patient-id })) (err ERR_NOT_FOUND))
    
    ;; Set access controls
    (map-set access-controls
      { patient-id: patient-id, provider-id: provider-id }
      {
        granted-at: block-height,
        expires-at: expires-at,
        access-level: access-level,
        token-id: token-id
      }
    )
    
    ;; Store token metadata
    (map-set token-metadata
      { token-id: token-id }
      {
        patient: patient-id,
        provider: provider-id
      }
    )
    
    ;; Mint NFT to provider
    (try! (nft-mint? healthcare-access-token token-id provider-id))
    
    ;; Increment token ID
    (var-set next-token-id (+ token-id u1))
    
    (ok token-id)
  )
)

;; Revoke access from a healthcare provider
(define-public (revoke-provider-access (provider-id principal))
  (let 
    (
      (patient-id tx-sender)
      (access (unwrap! (map-get? access-controls { patient-id: patient-id, provider-id: provider-id }) (err ERR_NOT_FOUND)))
      (token-id (get token-id access))
    )
    ;; Remove access controls
    (map-delete access-controls { patient-id: patient-id, provider-id: provider-id })
    
    ;; Burn NFT
    (try! (nft-burn? healthcare-access-token token-id provider-id))
    
    ;; Remove token metadata
    (map-delete token-metadata { token-id: token-id })
    
    (ok true)
  )
)

;; Update patient record hash (only by patient)
(define-public (update-record-hash (new-record-hash (string-ascii 64)))
  (let 
    (
      (patient-id tx-sender)
      (patient-data (unwrap! (map-get? patients { patient-id: patient-id }) (err ERR_NOT_FOUND)))
    )
    ;; Update the record hash
    (map-set patients
      { patient-id: patient-id }
      (merge patient-data { record-hash: new-record-hash })
    )
    (ok true)
  )
)

;; Update patient record by healthcare provider
(define-public (provider-update-record (patient-id principal) (new-record-hash (string-ascii 64)))
  (let 
    (
      (provider-id tx-sender)
      (access (unwrap! (map-get? access-controls { patient-id: patient-id, provider-id: provider-id }) (err ERR_UNAUTHORIZED)))
      (patient-data (unwrap! (map-get? patients { patient-id: patient-id }) (err ERR_NOT_FOUND)))
    )
    ;; Check if provider has write access (level 2 or higher)
    (asserts! (>= (get access-level access) u2) (err ERR_UNAUTHORIZED))
    
    ;; Check if access is still valid
    (asserts! (< block-height (get expires-at access)) (err ERR_UNAUTHORIZED))
    
    ;; Update the record hash
    (map-set patients
      { patient-id: patient-id }
      (merge patient-data { record-hash: new-record-hash })
    )
    (ok true)
  )
)

;; Read patient data (only accessible by patient or authorized providers)
(define-read-only (get-patient-data (patient-id principal))
  (let 
    (
      (caller tx-sender)
      (patient-data (unwrap! (map-get? patients { patient-id: patient-id }) (err ERR_NOT_FOUND)))
    )
    ;; Allow access if caller is the patient
    (if (is-eq caller patient-id)
      (ok patient-data)
      ;; Otherwise check if caller is an authorized provider
      (let 
        (
          (access (map-get? access-controls { patient-id: patient-id, provider-id: caller }))
        )
        (asserts! (is-some access) (err ERR_UNAUTHORIZED))
        (let 
          (
            (access-data (unwrap! access (err ERR_UNAUTHORIZED)))
          )
          ;; Check if access is still valid
          (asserts! (< block-height (get expires-at access-data)) (err ERR_UNAUTHORIZED))
          (ok patient-data)
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
    )
    (if (is-some access)
      (let 
        (
          (access-data (unwrap! access (err ERR_UNAUTHORIZED)))
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
