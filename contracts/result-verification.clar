;; Result Verification Contract
;; Validates test results through multi-party verification

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-RESULT-NOT-FOUND (err u401))
(define-constant ERR-RESULT-ALREADY-EXISTS (err u402))
(define-constant ERR-INVALID-VERIFICATION (err u403))
(define-constant ERR-INSUFFICIENT-VERIFIERS (err u404))
(define-constant VERIFIER-TOKEN-REWARD u25)
(define-constant MIN-VERIFIERS u3)

;; Data Variables
(define-data-var next-result-id uint u1)
(define-data-var total-results uint u0)

;; Data Maps
(define-map test-results
  { result-id: uint }
  {
    test-id: uint,
    lab-id: uint,
    patient-id: uint,
    result-data-hash: (string-ascii 64),
    result-summary: (string-ascii 500),
    confidence-level: uint,
    created-at: uint,
    verification-status: (string-ascii 20),
    final-accuracy-score: uint,
    is-verified: bool
  }
)

(define-map result-verifications
  { result-id: uint, verifier-id: (string-ascii 50) }
  {
    verification-score: uint,
    verification-notes: (string-ascii 300),
    verified-at: uint,
    verifier-reputation: uint
  }
)

(define-map verifier-profiles
  { verifier-id: (string-ascii 50) }
  {
    name: (string-ascii 100),
    specialization: (string-ascii 100),
    total-verifications: uint,
    accuracy-rate: uint,
    reputation-score: uint,
    is-active: bool
  }
)

(define-map verifier-tokens
  { verifier-id: (string-ascii 50) }
  { balance: uint }
)

(define-map result-consensus
  { result-id: uint }
  {
    total-verifiers: uint,
    positive-verifications: uint,
    average-score: uint,
    consensus-reached: bool,
    consensus-threshold: uint
  }
)

;; Public Functions

;; Register a new verifier
(define-public (register-verifier
  (verifier-id (string-ascii 50))
  (name (string-ascii 100))
  (specialization (string-ascii 100)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set verifier-profiles
      { verifier-id: verifier-id }
      {
        name: name,
        specialization: specialization,
        total-verifications: u0,
        accuracy-rate: u100,
        reputation-score: u100,
        is-active: true
      }
    )

    (map-set verifier-tokens { verifier-id: verifier-id } { balance: u0 })

    (ok true)
  )
)

;; Submit test result for verification
(define-public (submit-result
  (test-id uint)
  (lab-id uint)
  (patient-id uint)
  (result-data-hash (string-ascii 64))
  (result-summary (string-ascii 500))
  (confidence-level uint))
  (let
    (
      (result-id (var-get next-result-id))
    )
    (asserts! (<= confidence-level u100) ERR-INVALID-VERIFICATION)

    (map-set test-results
      { result-id: result-id }
      {
        test-id: test-id,
        lab-id: lab-id,
        patient-id: patient-id,
        result-data-hash: result-data-hash,
        result-summary: result-summary,
        confidence-level: confidence-level,
        created-at: block-height,
        verification-status: "pending",
        final-accuracy-score: u0,
        is-verified: false
      }
    )

    (map-set result-consensus
      { result-id: result-id }
      {
        total-verifiers: u0,
        positive-verifications: u0,
        average-score: u0,
        consensus-reached: false,
        consensus-threshold: u80
      }
    )

    (var-set next-result-id (+ result-id u1))
    (var-set total-results (+ (var-get total-results) u1))

    (ok result-id)
  )
)

;; Verify test result
(define-public (verify-result
  (result-id uint)
  (verifier-id (string-ascii 50))
  (verification-score uint)
  (verification-notes (string-ascii 300)))
  (let
    (
      (result (unwrap! (map-get? test-results { result-id: result-id }) ERR-RESULT-NOT-FOUND))
      (verifier (unwrap! (map-get? verifier-profiles { verifier-id: verifier-id }) ERR-NOT-AUTHORIZED))
      (consensus (unwrap! (map-get? result-consensus { result-id: result-id }) ERR-RESULT-NOT-FOUND))
      (current-tokens (default-to { balance: u0 } (map-get? verifier-tokens { verifier-id: verifier-id })))
    )
    (asserts! (get is-active verifier) ERR-NOT-AUTHORIZED)
    (asserts! (<= verification-score u100) ERR-INVALID-VERIFICATION)

    ;; Record verification
    (map-set result-verifications
      { result-id: result-id, verifier-id: verifier-id }
      {
        verification-score: verification-score,
        verification-notes: verification-notes,
        verified-at: block-height,
        verifier-reputation: (get reputation-score verifier)
      }
    )

    ;; Update verifier stats
    (map-set verifier-profiles
      { verifier-id: verifier-id }
      (merge verifier { total-verifications: (+ (get total-verifications verifier) u1) })
    )

    ;; Update consensus
    (let
      (
        (new-total-verifiers (+ (get total-verifiers consensus) u1))
        (new-positive-verifications (if (>= verification-score u70) (+ (get positive-verifications consensus) u1) (get positive-verifications consensus)))
        (new-average-score (/ (+ (* (get average-score consensus) (get total-verifiers consensus)) verification-score) new-total-verifiers))
      )
      (map-set result-consensus
        { result-id: result-id }
        (merge consensus {
          total-verifiers: new-total-verifiers,
          positive-verifications: new-positive-verifications,
          average-score: new-average-score,
          consensus-reached: (and (>= new-total-verifiers MIN-VERIFIERS) (>= new-average-score (get consensus-threshold consensus)))
        })
      )

      ;; Award tokens to verifier
      (map-set verifier-tokens
        { verifier-id: verifier-id }
        { balance: (+ (get balance current-tokens) VERIFIER-TOKEN-REWARD) }
      )
    )

    (ok true)
  )
)

;; Finalize result verification
(define-public (finalize-verification (result-id uint))
  (let
    (
      (result (unwrap! (map-get? test-results { result-id: result-id }) ERR-RESULT-NOT-FOUND))
      (consensus (unwrap! (map-get? result-consensus { result-id: result-id }) ERR-RESULT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (get consensus-reached consensus) ERR-INSUFFICIENT-VERIFIERS)

    (map-set test-results
      { result-id: result-id }
      (merge result {
        verification-status: "verified",
        final-accuracy-score: (get average-score consensus),
        is-verified: true
      })
    )

    (ok true)
  )
)

;; Read-only Functions

;; Get test result
(define-read-only (get-test-result (result-id uint))
  (map-get? test-results { result-id: result-id })
)

;; Get result verification
(define-read-only (get-result-verification (result-id uint) (verifier-id (string-ascii 50)))
  (map-get? result-verifications { result-id: result-id, verifier-id: verifier-id })
)

;; Get verifier profile
(define-read-only (get-verifier-profile (verifier-id (string-ascii 50)))
  (map-get? verifier-profiles { verifier-id: verifier-id })
)

;; Get verifier tokens
(define-read-only (get-verifier-tokens (verifier-id (string-ascii 50)))
  (default-to { balance: u0 } (map-get? verifier-tokens { verifier-id: verifier-id }))
)

;; Get result consensus
(define-read-only (get-result-consensus (result-id uint))
  (map-get? result-consensus { result-id: result-id })
)

;; Check if result is verified
(define-read-only (is-result-verified (result-id uint))
  (match (map-get? test-results { result-id: result-id })
    result (get is-verified result)
    false
  )
)

;; Get total results
(define-read-only (get-total-results)
  (var-get total-results)
)
