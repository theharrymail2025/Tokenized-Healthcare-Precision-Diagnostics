;; Patient Verification Contract
;; Manages patient identities, consent, and privacy protection

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-PATIENT-NOT-FOUND (err u201))
(define-constant ERR-PATIENT-ALREADY-EXISTS (err u202))
(define-constant ERR-CONSENT-NOT-GIVEN (err u203))
(define-constant ERR-INVALID-PATIENT-DATA (err u204))
(define-constant PATIENT-TOKEN-REWARD u50)

;; Data Variables
(define-data-var next-patient-id uint u1)
(define-data-var total-patients uint u0)

;; Data Maps
(define-map patients
  { patient-id: uint }
  {
    encrypted-identity: (string-ascii 200),
    age-range: uint,
    gender: (string-ascii 10),
    consent-given: bool,
    consent-date: uint,
    privacy-level: uint,
    total-tests: uint,
    created-at: uint,
    is-active: bool
  }
)

(define-map patient-consents
  { patient-id: uint, consent-type: (string-ascii 50) }
  {
    consent-given: bool,
    consent-date: uint,
    expiry-date: uint,
    scope: (string-ascii 200)
  }
)

(define-map patient-tokens
  { patient-id: uint }
  { balance: uint }
)

(define-map patient-test-history
  { patient-id: uint, test-id: uint }
  {
    lab-id: uint,
    test-type: (string-ascii 100),
    test-date: uint,
    result-verified: bool
  }
)

;; Public Functions

;; Register a new patient
(define-public (register-patient
  (encrypted-identity (string-ascii 200))
  (age-range uint)
  (gender (string-ascii 10))
  (privacy-level uint))
  (let
    (
      (patient-id (var-get next-patient-id))
    )
    (asserts! (> (len encrypted-identity) u0) ERR-INVALID-PATIENT-DATA)
    (asserts! (<= privacy-level u3) ERR-INVALID-PATIENT-DATA)

    (map-set patients
      { patient-id: patient-id }
      {
        encrypted-identity: encrypted-identity,
        age-range: age-range,
        gender: gender,
        consent-given: false,
        consent-date: u0,
        privacy-level: privacy-level,
        total-tests: u0,
        created-at: block-height,
        is-active: true
      }
    )

    (map-set patient-tokens { patient-id: patient-id } { balance: u0 })
    (var-set next-patient-id (+ patient-id u1))
    (var-set total-patients (+ (var-get total-patients) u1))

    (ok patient-id)
  )
)

;; Give consent for data usage
(define-public (give-consent
  (patient-id uint)
  (consent-type (string-ascii 50))
  (expiry-date uint)
  (scope (string-ascii 200)))
  (let
    (
      (patient (unwrap! (map-get? patients { patient-id: patient-id }) ERR-PATIENT-NOT-FOUND))
    )
    (map-set patient-consents
      { patient-id: patient-id, consent-type: consent-type }
      {
        consent-given: true,
        consent-date: block-height,
        expiry-date: expiry-date,
        scope: scope
      }
    )

    ;; Update general consent status
    (map-set patients
      { patient-id: patient-id }
      (merge patient {
        consent-given: true,
        consent-date: block-height
      })
    )

    (ok true)
  )
)

;; Revoke consent
(define-public (revoke-consent
  (patient-id uint)
  (consent-type (string-ascii 50)))
  (let
    (
      (patient (unwrap! (map-get? patients { patient-id: patient-id }) ERR-PATIENT-NOT-FOUND))
      (consent (unwrap! (map-get? patient-consents { patient-id: patient-id, consent-type: consent-type }) ERR-CONSENT-NOT-GIVEN))
    )
    (map-set patient-consents
      { patient-id: patient-id, consent-type: consent-type }
      (merge consent { consent-given: false })
    )

    (ok true)
  )
)

;; Record test participation and award tokens
(define-public (record-test-participation
  (patient-id uint)
  (test-id uint)
  (lab-id uint)
  (test-type (string-ascii 100)))
  (let
    (
      (patient (unwrap! (map-get? patients { patient-id: patient-id }) ERR-PATIENT-NOT-FOUND))
      (current-tokens (default-to { balance: u0 } (map-get? patient-tokens { patient-id: patient-id })))
    )
    (asserts! (get consent-given patient) ERR-CONSENT-NOT-GIVEN)

    ;; Record test in history
    (map-set patient-test-history
      { patient-id: patient-id, test-id: test-id }
      {
        lab-id: lab-id,
        test-type: test-type,
        test-date: block-height,
        result-verified: false
      }
    )

    ;; Update patient stats
    (map-set patients
      { patient-id: patient-id }
      (merge patient { total-tests: (+ (get total-tests patient) u1) })
    )

    ;; Award tokens for participation
    (map-set patient-tokens
      { patient-id: patient-id }
      { balance: (+ (get balance current-tokens) PATIENT-TOKEN-REWARD) }
    )

    (ok true)
  )
)

;; Update test verification status
(define-public (update-test-verification
  (patient-id uint)
  (test-id uint)
  (verified bool))
  (let
    (
      (test-record (unwrap! (map-get? patient-test-history { patient-id: patient-id, test-id: test-id }) ERR-PATIENT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set patient-test-history
      { patient-id: patient-id, test-id: test-id }
      (merge test-record { result-verified: verified })
    )

    (ok true)
  )
)

;; Read-only Functions

;; Get patient details (privacy-protected)
(define-read-only (get-patient (patient-id uint))
  (match (map-get? patients { patient-id: patient-id })
    patient (some {
      age-range: (get age-range patient),
      gender: (get gender patient),
      consent-given: (get consent-given patient),
      privacy-level: (get privacy-level patient),
      total-tests: (get total-tests patient),
      created-at: (get created-at patient),
      is-active: (get is-active patient)
    })
    none
  )
)

;; Get patient consent status
(define-read-only (get-consent-status (patient-id uint) (consent-type (string-ascii 50)))
  (map-get? patient-consents { patient-id: patient-id, consent-type: consent-type })
)

;; Get patient token balance
(define-read-only (get-patient-tokens (patient-id uint))
  (default-to { balance: u0 } (map-get? patient-tokens { patient-id: patient-id }))
)

;; Get patient test history
(define-read-only (get-test-history (patient-id uint) (test-id uint))
  (map-get? patient-test-history { patient-id: patient-id, test-id: test-id })
)

;; Check if patient has valid consent
(define-read-only (has-valid-consent (patient-id uint) (consent-type (string-ascii 50)))
  (match (map-get? patient-consents { patient-id: patient-id, consent-type: consent-type })
    consent (and (get consent-given consent) (> (get expiry-date consent) block-height))
    false
  )
)

;; Get total number of patients
(define-read-only (get-total-patients)
  (var-get total-patients)
)
