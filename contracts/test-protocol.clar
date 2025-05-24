;; Test Protocol Contract
;; Records diagnostic procedures and validates protocol compliance

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-PROTOCOL-NOT-FOUND (err u301))
(define-constant ERR-PROTOCOL-ALREADY-EXISTS (err u302))
(define-constant ERR-INVALID-PROTOCOL-DATA (err u303))
(define-constant ERR-TEST-NOT-FOUND (err u304))

;; Data Variables
(define-data-var next-protocol-id uint u1)
(define-data-var next-test-id uint u1)
(define-data-var total-protocols uint u0)
(define-data-var total-tests uint u0)

;; Data Maps
(define-map test-protocols
  { protocol-id: uint }
  {
    name: (string-ascii 100),
    description: (string-ascii 500),
    test-type: (string-ascii 50),
    required-equipment: (string-ascii 200),
    sample-type: (string-ascii 50),
    processing-time: uint,
    accuracy-threshold: uint,
    cost: uint,
    created-at: uint,
    is-active: bool
  }
)

(define-map protocol-steps
  { protocol-id: uint, step-number: uint }
  {
    step-description: (string-ascii 300),
    required-time: uint,
    quality-checkpoints: (string-ascii 200),
    is-critical: bool
  }
)

(define-map test-executions
  { test-id: uint }
  {
    protocol-id: uint,
    patient-id: uint,
    lab-id: uint,
    technician-id: (string-ascii 50),
    start-time: uint,
    end-time: uint,
    sample-id: (string-ascii 100),
    equipment-used: (string-ascii 200),
    protocol-compliance: uint,
    quality-score: uint,
    status: (string-ascii 20)
  }
)

(define-map test-step-execution
  { test-id: uint, step-number: uint }
  {
    executed-at: uint,
    execution-time: uint,
    quality-passed: bool,
    notes: (string-ascii 300)
  }
)

;; Public Functions

;; Create a new test protocol
(define-public (create-protocol
  (name (string-ascii 100))
  (description (string-ascii 500))
  (test-type (string-ascii 50))
  (required-equipment (string-ascii 200))
  (sample-type (string-ascii 50))
  (processing-time uint)
  (accuracy-threshold uint)
  (cost uint))
  (let
    (
      (protocol-id (var-get next-protocol-id))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> (len name) u0) ERR-INVALID-PROTOCOL-DATA)
    (asserts! (> processing-time u0) ERR-INVALID-PROTOCOL-DATA)

    (map-set test-protocols
      { protocol-id: protocol-id }
      {
        name: name,
        description: description,
        test-type: test-type,
        required-equipment: required-equipment,
        sample-type: sample-type,
        processing-time: processing-time,
        accuracy-threshold: accuracy-threshold,
        cost: cost,
        created-at: block-height,
        is-active: true
      }
    )

    (var-set next-protocol-id (+ protocol-id u1))
    (var-set total-protocols (+ (var-get total-protocols) u1))

    (ok protocol-id)
  )
)

;; Add step to protocol
(define-public (add-protocol-step
  (protocol-id uint)
  (step-number uint)
  (step-description (string-ascii 300))
  (required-time uint)
  (quality-checkpoints (string-ascii 200))
  (is-critical bool))
  (let
    (
      (protocol (unwrap! (map-get? test-protocols { protocol-id: protocol-id }) ERR-PROTOCOL-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set protocol-steps
      { protocol-id: protocol-id, step-number: step-number }
      {
        step-description: step-description,
        required-time: required-time,
        quality-checkpoints: quality-checkpoints,
        is-critical: is-critical
      }
    )

    (ok true)
  )
)

;; Start test execution
(define-public (start-test-execution
  (protocol-id uint)
  (patient-id uint)
  (lab-id uint)
  (technician-id (string-ascii 50))
  (sample-id (string-ascii 100))
  (equipment-used (string-ascii 200)))
  (let
    (
      (test-id (var-get next-test-id))
      (protocol (unwrap! (map-get? test-protocols { protocol-id: protocol-id }) ERR-PROTOCOL-NOT-FOUND))
    )
    (asserts! (get is-active protocol) ERR-PROTOCOL-NOT-FOUND)

    (map-set test-executions
      { test-id: test-id }
      {
        protocol-id: protocol-id,
        patient-id: patient-id,
        lab-id: lab-id,
        technician-id: technician-id,
        start-time: block-height,
        end-time: u0,
        sample-id: sample-id,
        equipment-used: equipment-used,
        protocol-compliance: u0,
        quality-score: u0,
        status: "in-progress"
      }
    )

    (var-set next-test-id (+ test-id u1))
    (var-set total-tests (+ (var-get total-tests) u1))

    (ok test-id)
  )
)

;; Execute protocol step
(define-public (execute-protocol-step
  (test-id uint)
  (step-number uint)
  (execution-time uint)
  (quality-passed bool)
  (notes (string-ascii 300)))
  (let
    (
      (test (unwrap! (map-get? test-executions { test-id: test-id }) ERR-TEST-NOT-FOUND))
      (step (unwrap! (map-get? protocol-steps { protocol-id: (get protocol-id test), step-number: step-number }) ERR-PROTOCOL-NOT-FOUND))
    )
    (map-set test-step-execution
      { test-id: test-id, step-number: step-number }
      {
        executed-at: block-height,
        execution-time: execution-time,
        quality-passed: quality-passed,
        notes: notes
      }
    )

    (ok true)
  )
)

;; Complete test execution
(define-public (complete-test-execution
  (test-id uint)
  (protocol-compliance uint)
  (quality-score uint))
  (let
    (
      (test (unwrap! (map-get? test-executions { test-id: test-id }) ERR-TEST-NOT-FOUND))
    )
    (map-set test-executions
      { test-id: test-id }
      (merge test {
        end-time: block-height,
        protocol-compliance: protocol-compliance,
        quality-score: quality-score,
        status: "completed"
      })
    )

    (ok true)
  )
)

;; Read-only Functions

;; Get protocol details
(define-read-only (get-protocol (protocol-id uint))
  (map-get? test-protocols { protocol-id: protocol-id })
)

;; Get protocol step
(define-read-only (get-protocol-step (protocol-id uint) (step-number uint))
  (map-get? protocol-steps { protocol-id: protocol-id, step-number: step-number })
)

;; Get test execution details
(define-read-only (get-test-execution (test-id uint))
  (map-get? test-executions { test-id: test-id })
)

;; Get test step execution
(define-read-only (get-test-step-execution (test-id uint) (step-number uint))
  (map-get? test-step-execution { test-id: test-id, step-number: step-number })
)

;; Check protocol compliance
(define-read-only (check-protocol-compliance (test-id uint))
  (match (map-get? test-executions { test-id: test-id })
    test (>= (get protocol-compliance test) u80)
    false
  )
)

;; Get total protocols
(define-read-only (get-total-protocols)
  (var-get total-protocols)
)

;; Get total tests
(define-read-only (get-total-tests)
  (var-get total-tests)
)
