;; NotePay - Decentralized Music Revenue Distribution Protocol
;; A sophisticated blockchain-based system for transparent and automated 
;; distribution of music royalties among composers, performers, and rights stakeholders.

;; Error constants
(define-constant ERR-FORBIDDEN-OPERATION (err u100))
(define-constant ERR-INVALID-EQUITY-RATIO (err u101))
(define-constant ERR-COMPOSITION-EXISTS (err u102))
(define-constant ERR-COMPOSITION-UNDEFINED (err u103))
(define-constant ERR-INSUFFICIENT-VAULT-BALANCE (err u104))
(define-constant ERR-INVALID-BENEFICIARY (err u105))
(define-constant ERR-DISBURSEMENT-MALFUNCTION (err u106))
(define-constant ERR-INVALID-METADATA-LENGTH (err u107))
(define-constant ERR-INVALID-COMPOSITION-TITLE (err u108))
(define-constant ERR-INVALID-CONTRIBUTOR-CLASS (err u109))
(define-constant ERR-INVALID-CREATIVE-TALENT (err u110))
(define-constant ERR-INVALID-PROTOCOL-STEWARD (err u111))

;; Data structures
(define-map composition-registry
    { opus-id: uint }
    {
        opus-title: (string-ascii 50),
        creative-talent: principal,
        aggregate-earnings: uint,
        genesis-block: uint,
        revenue-flow-active: bool
    }
)

(define-map equity-allocations
    { opus-id: uint, beneficiary: principal }
    {
        equity-fraction: uint,
        contributor-class: (string-ascii 20),
        lifetime-accumulation: uint
    }
)

;; State variables
(define-data-var registry-magnitude uint u0)
(define-data-var protocol-steward principal tx-sender)

;; Read-only functions - Data access
(define-read-only (fetch-opus-metadata (opus-id uint))
    (map-get? composition-registry { opus-id: opus-id })
)

(define-read-only (fetch-beneficiary-profile (opus-id uint) (beneficiary principal))
    (map-get? equity-allocations { opus-id: opus-id, beneficiary: beneficiary })
)

(define-read-only (get-registry-magnitude)
    (var-get registry-magnitude)
)

(define-read-only (enumerate-opus-stakeholders (opus-id uint))
    (let (
        (opus-metadata (fetch-opus-metadata opus-id))
        (primary-talent (match opus-metadata record (get creative-talent record) tx-sender))
    )
    (let ((beneficiary-profile (fetch-beneficiary-profile opus-id primary-talent)))
        (match beneficiary-profile allocation
            (list {
                beneficiary: primary-talent,
                equity-fraction: (get equity-fraction allocation)
            })
            (list))))
)

;; Private validation functions
(define-private (validate-allocation-parameters (allocation {
    equity-fraction: uint,
    contributor-class: (string-ascii 20),
    lifetime-accumulation: uint
}))
    (> (get equity-fraction allocation) u0)
)

(define-private (verify-protocol-authority)
    (is-eq tx-sender (var-get protocol-steward))
)

(define-private (validate-equity-bounds (equity-percentage uint))
    (and (>= equity-percentage u0) (<= equity-percentage u100))
)

(define-private (validate-metadata-integrity (metadata (string-ascii 50)))
    (let ((metadata-length (len metadata)))
        (and (> metadata-length u0) (<= metadata-length u50))))

(define-private (validate-contributor-classification (classification (string-ascii 20)))
    (let ((classification-length (len classification)))
        (and (> classification-length u0) (<= classification-length u20))))

(define-private (validate-beneficiary-legitimacy (address principal))
    (and 
        (not (is-eq address tx-sender))
        (not (is-eq address (var-get protocol-steward)))
    ))

;; Private payment processing functions
(define-private (execute-stakeholder-disbursement
    (stakeholder-data {beneficiary: principal, equity-fraction: uint}) 
    (total-disbursement uint))
    (let (
        (stakeholder-portion (/ (* total-disbursement (get equity-fraction stakeholder-data)) u100))
    )
    (if (> stakeholder-portion u0)
        (match (stx-transfer? stakeholder-portion tx-sender (get beneficiary stakeholder-data))
            success total-disbursement
            error u0)
        u0))
)

(define-private (orchestrate-revenue-distribution (opus-id uint) (total-disbursement uint))
    (let (
        (stakeholder-roster (enumerate-opus-stakeholders opus-id))
        (aggregated-disbursement (fold execute-stakeholder-disbursement 
                          stakeholder-roster 
                          total-disbursement))
    )
    (begin
        (asserts! (> (len stakeholder-roster) u0) ERR-COMPOSITION-UNDEFINED)
        (asserts! (> aggregated-disbursement u0) ERR-DISBURSEMENT-MALFUNCTION)
        (ok aggregated-disbursement)))
)

;; Public functions - Administrative
(define-public (register-musical-opus (opus-title (string-ascii 50)) (creative-talent principal))
    (let (
        (next-opus-id (+ (var-get registry-magnitude) u1))
    )
    (begin
        (asserts! (verify-protocol-authority) ERR-FORBIDDEN-OPERATION)
        (asserts! (validate-metadata-integrity opus-title) ERR-INVALID-COMPOSITION-TITLE)
        (asserts! (validate-beneficiary-legitimacy creative-talent) ERR-INVALID-CREATIVE-TALENT)
        
        (map-set composition-registry
            { opus-id: next-opus-id }
            {
                opus-title: opus-title,
                creative-talent: creative-talent,
                aggregate-earnings: u0,
                genesis-block: block-height,
                revenue-flow-active: true
            }
        )
        (var-set registry-magnitude next-opus-id)
        (ok next-opus-id)))
)

(define-public (configure-equity-distribution 
    (opus-id uint) 
    (beneficiary principal) 
    (equity-fraction uint) 
    (contributor-class (string-ascii 20)))
    (let (
        (opus-metadata (fetch-opus-metadata opus-id))
    )
    (begin
        (asserts! (is-some opus-metadata) ERR-COMPOSITION-UNDEFINED)
        (asserts! (validate-equity-bounds equity-fraction) ERR-INVALID-EQUITY-RATIO)
        (asserts! (validate-contributor-classification contributor-class) ERR-INVALID-CONTRIBUTOR-CLASS)
        (asserts! (validate-beneficiary-legitimacy beneficiary) ERR-INVALID-BENEFICIARY)
        
        (map-set equity-allocations
            { opus-id: opus-id, beneficiary: beneficiary }
            {
                equity-fraction: equity-fraction,
                contributor-class: contributor-class,
                lifetime-accumulation: u0
            }
        )
        (ok true)))
)

(define-public (toggle-revenue-stream (opus-id uint) (stream-enabled bool))
    (let (
        (opus-metadata (fetch-opus-metadata opus-id))
    )
    (begin
        (asserts! (verify-protocol-authority) ERR-FORBIDDEN-OPERATION)
        (asserts! (is-some opus-metadata) ERR-COMPOSITION-UNDEFINED)
        
        (map-set composition-registry
            { opus-id: opus-id }
            (merge (unwrap-panic opus-metadata)
                { revenue-flow-active: stream-enabled }
            )
        )
        (ok true)))
)

(define-public (designate-protocol-steward (new-steward principal))
    (begin
        (asserts! (verify-protocol-authority) ERR-FORBIDDEN-OPERATION)
        (asserts! (validate-beneficiary-legitimacy new-steward) ERR-INVALID-PROTOCOL-STEWARD)
        
        (var-set protocol-steward new-steward)
        (ok true))
)

;; Public functions - Revenue distribution
(define-public (execute-royalty-cascade (opus-id uint) (revenue-amount uint))
    (let (
        (opus-metadata (fetch-opus-metadata opus-id))
    )
    (begin
        (asserts! (is-some opus-metadata) ERR-COMPOSITION-UNDEFINED)
        (asserts! (>= (stx-get-balance tx-sender) revenue-amount) ERR-INSUFFICIENT-VAULT-BALANCE)
        
        (try! (orchestrate-revenue-distribution opus-id revenue-amount))
        (map-set composition-registry
            { opus-id: opus-id }
            (merge (unwrap-panic opus-metadata)
                { aggregate-earnings: (+ (get aggregate-earnings (unwrap-panic opus-metadata)) revenue-amount) }
            )
        )
        (ok true)))
)

;; Protocol initialization
(begin
    (var-set registry-magnitude u0))