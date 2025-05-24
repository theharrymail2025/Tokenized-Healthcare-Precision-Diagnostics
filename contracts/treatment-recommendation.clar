;; Treatment Recommendation Contract
;; Links diagnostic results to personalized treatment options

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-RECOMMENDATION-NOT-FOUND (err u501))
(define-constant ERR-INVALID-RECOMMENDATION (err u502))
(define-constant ERR-RESULT-NOT-VERIFIED (err u503))
(define-constant ERR-TREATMENT-NOT-FOUND (err u504))
(define-constant TREATMENT-TOKEN-REWARD u200)

;; Data Variables
(define-data-var next-recommendation-id uint u1)
(define-data-var next-treatment-id uint u1)
(define-data-var total-recommendations uint u0)

;; Data Maps
(define-map treatment-protocols
  { treatment-id: uint }
  {
    name: (string-ascii 100),
    description: (string-ascii 500),
    treatment-type: (string-ascii 50),
    target-conditions: (string-ascii 200),
    efficacy-rate: uint,
    side-effects: (string-ascii 300),
    duration: uint,
    cost: uint,
    is-active: bool
  }
)

(define-map treatment-recommendations
  { recommendation-id: uint }
  {
    result-id: uint,
    patient-id: uint,
    treatment-id: uint,
    confidence-score: uint,
    priority-level: uint,
    recommended-by: (string-ascii 50),
    recommendation-notes: (string-ascii 500),
    created-at: uint,
    status: (string-ascii 20)
  }
)

(define-map treatment-outcomes
  { recommendation-id: uint }
  {
    treatment-started: bool,
    start-date: uint,
    end-date: uint,
    outcome-score: uint,
    patient-feedback: (string-ascii 300),
    side-effects-reported: (string-ascii 300),
    treatment-successful: bool,
    follow-up-required: bool
  }
)

(define-map physician-profiles
  { physician-id: (string-ascii 50) }
  {
    name: (string-ascii 100),
    specialization: (string-ascii 100),
    license-number: (string-ascii 50),
    total-recommendations: uint,
    success-rate: uint,
    is-verified: bool
  }
)

(define-map treatment-tokens
  { physician-id: (string-ascii 50) }
  { balance: uint }
)

;; Public Functions

;; Register treatment protocol
(define-public (register-treatment-protocol
  (name (string-ascii 100))
  (description (string-ascii 500))
  (treatment-type (string-ascii 50))
  (target-conditions (string-ascii 200))
  (efficacy-rate uint)
  (side-effects (string-ascii 300))
  (duration uint)
  (cost uint))
  (let
    (
      (treatment-id (var-get next-treatment-id))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (<= efficacy-rate u100) ERR-INVALID-RECOMMENDATION)

    (map-set treatment-protocols
      { treatment-id: treatment-id }
      {
        name: name,
        description: description,
        treatment-type: treatment-type,
        target-conditions: target-conditions,
        efficacy-rate: efficacy-rate,
        side-effects: side-effects,
        duration: duration,
        cost: cost,
        is-active: true
      }
    )

    (var-set next-treatment-id (+ treatment-id u1))

    (ok treatment-id)
  )
)

;; Register physician
(define-public (register-physician
  (physician-id (string-ascii 50))
  (name (string-ascii 100))
  (specialization (string-ascii 100))
  (license-number (string-ascii 50)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set physician-profiles
      { physician-id: physician-id }
      {
        name: name,
        specialization: specialization,
        license-number: license-number,
        total-recommendations: u0,
        success-rate: u0,
        is-verified: true
      }
    )

    (map-set treatment-tokens { physician-id: physician-id } { balance: u0 })

    (ok true)
  )
)

;; Create treatment recommendation
(define-public (create-recommendation
  (result-id uint)
  (patient-id uint)
  (treatment-id uint)
  (confidence-score uint)
  (priority-level uint)
  (physician-id (string-ascii 50))
  (recommendation-notes (string-ascii 500)))
  (let
    (
      (recommendation-id (var-get next-recommendation-id))
      (treatment (unwrap! (map-get? treatment-protocols { treatment-id: treatment-id }) ERR-TREATMENT-NOT-FOUND))
      (physician (unwrap! (map-get? physician-profiles { physician-id: physician-id }) ERR-NOT-AUTHORIZED))
    )
    (asserts! (get is-verified physician) ERR-NOT-AUTHORIZED)
    (asserts! (<= confidence-score u100) ERR-INVALID-RECOMMENDATION)
    (asserts! (<= priority-level u5) ERR-INVALID-RECOMMENDATION)

    (map-set treatment-recommendations
      { recommendation-id: recommendation-id }
      {
        result-id: result-id,
        patient-id: patient-id,
        treatment-id: treatment-id,
        confidence-score: confidence-score,
        priority-level: priority-level,
        recommended-by: physician-id,
        recommendation-notes: recommendation-notes,
        created-at: block-height,
        status: "pending"
      }
    )

    ;; Update physician stats
    (map-set physician-profiles
      { physician-id: physician-id }
      (merge physician { total-recommendations: (+ (get total-recommendations physician) u1) })
    )

    (var-set next-recommendation-id (+ recommendation-id u1))
    (var-set total-recommendations (+ (var-get total-recommendations) u1))

    (ok recommendation-id)
  )
)

;; Start treatment
(define-public (start-treatment (recommendation-id uint))
  (let
    (
      (recommendation (unwrap! (map-get? treatment-recommendations { recommendation-id: recommendation-id }) ERR-RECOMMENDATION-NOT-FOUND))
    )
    (map-set treatment-recommendations
      { recommendation-id: recommendation-id }
      (merge recommendation { status: "active" })
    )

    (map-set treatment-outcomes
      { recommendation-id: recommendation-id }
      {
        treatment-started: true,
        start-date: block-height,
        end-date: u0,
        outcome-score: u0,
        patient-feedback: "",
        side-effects-reported: "",
        treatment-successful: false,
        follow-up-required: false
      }
    )

    (ok true)
  )
)

;; Complete treatment and record outcome
(define-public (complete-treatment
  (recommendation-id uint)
  (outcome-score uint)
  (patient-feedback (string-ascii 300))
  (side-effects-reported (string-ascii 300))
  (treatment-successful bool)
  (follow-up-required bool))
  (let
    (
      (recommendation (unwrap! (map-get? treatment-recommendations { recommendation-id: recommendation-id }) ERR-RECOMMENDATION-NOT-FOUND))
      (outcome (unwrap! (map-get? treatment-outcomes { recommendation-id: recommendation-id }) ERR-RECOMMENDATION-NOT-FOUND))
      (physician-id (get recommended-by recommendation))
      (physician (unwrap! (map-get? physician-profiles { physician-id: physician-id }) ERR-NOT-AUTHORIZED))
      (current-tokens (default-to { balance: u0 } (map-get? treatment-tokens { physician-id: physician-id })))
    )
    (asserts! (<= outcome-score u100) ERR-INVALID-RECOMMENDATION)

    ;; Update treatment outcome
    (map-set treatment-outcomes
      { recommendation-id: recommendation-id }
      (merge outcome {
        end-date: block-height,
        outcome-score: outcome-score,
        patient-feedback: patient-feedback,
        side-effects-reported: side-effects-reported,
        treatment-successful: treatment-successful,
        follow-up-required: follow-up-required
      })
    )

    ;; Update recommendation status
    (map-set treatment-recommendations
      { recommendation-id: recommendation-id }
      (merge recommendation { status: "completed" })
    )

    ;; Calculate and update physician success rate
    (let
      (
        (total-recs (get total-recommendations physician))
        (current-success-rate (get success-rate physician))
        (new-success-rate (if (> total-recs u0)
          (/ (+ (* current-success-rate (- total-recs u1)) (if treatment-successful u100 u0)) total-recs)
          (if treatment-successful u100 u0)
        ))
      )
      (map-set physician-profiles
        { physician-id: physician-id }
        (merge physician { success-rate: new-success-rate })
      )
    )

    ;; Award tokens for successful treatment
    (if treatment-successful
      (map-set treatment-tokens
        { physician-id: physician-id }
        { balance: (+ (get balance current-tokens) TREATMENT-TOKEN-REWARD) }
      )
      true
    )

    (ok true)
  )
)

;; Read-only Functions

;; Get treatment protocol
(define-read-only (get-treatment-protocol (treatment-id uint))
  (map-get? treatment-protocols { treatment-id: treatment-id })
)

;; Get treatment recommendation
(define-read-only (get-recommendation (recommendation-id uint))
  (map-get? treatment-recommendations { recommendation-id: recommendation-id })
)

;; Get treatment outcome
(define-read-only (get-treatment-outcome (recommendation-id uint))
  (map-get? treatment-outcomes { recommendation-id: recommendation-id })
)

;; Get physician profile
(define-read-only (get-physician-profile (physician-id (string-ascii 50)))
  (map-get? physician-profiles { physician-id: physician-id })
)

;; Get physician tokens
(define-read-only (get-physician-tokens (physician-id (string-ascii 50)))
  (default-to { balance: u0 } (map-get? treatment-tokens { physician-id: physician-id }))
)

;; Get recommendations for patient
(define-read-only (get-patient-recommendations (patient-id uint))
  ;; This would typically return a list, but Clarity doesn't support dynamic lists
  ;; In practice, you'd query by iterating through recommendation IDs
  (ok patient-id)
)

;; Get total recommendations
(define-read-only (get-total-recommendations)
  (var-get total-recommendations)
)

;; Check treatment success rate for protocol
(define-read-only (get-treatment-success-rate (treatment-id uint))
  (match (map-get? treatment-protocols { treatment-id: treatment-id })
    protocol (get efficacy-rate protocol)
    u0
  )
)
