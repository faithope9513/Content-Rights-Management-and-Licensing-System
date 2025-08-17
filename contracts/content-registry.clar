;; Content Registry Contract
;; Manages intellectual property registration and ownership tracking

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-CONTENT-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-EXISTS (err u102))
(define-constant ERR-INVALID-INPUT (err u103))
(define-constant ERR-TRANSFER-FAILED (err u104))

;; Data Variables
(define-data-var next-content-id uint u1)
(define-data-var total-registered uint u0)

;; Data Maps
(define-map content-registry uint {
  title: (string-ascii 256),
  description: (string-ascii 512),
  owner: principal,
  creator: principal,
  content-hash: (buff 32),
  content-type: (string-ascii 64),
  metadata-uri: (optional (string-ascii 256)),
  registration-date: uint,
  last-updated: uint,
  is-active: bool,
  transfer-count: uint
})

(define-map owner-content-count principal uint)
(define-map content-ownership-history uint (list 10 {
  previous-owner: principal,
  new-owner: principal,
  transfer-date: uint,
  transfer-reason: (string-ascii 128)
}))

;; Public Functions

;; Register new content
(define-public (register-content
  (title (string-ascii 256))
  (description (string-ascii 512))
  (content-hash (buff 32))
  (content-type (string-ascii 64))
  (metadata-uri (optional (string-ascii 256))))
  (let ((content-id (var-get next-content-id)))
    ;; Using native Clarity operators instead of HTML entities
    (asserts! (> (len title) u0) ERR-INVALID-INPUT)
    (asserts! (> (len description) u0) ERR-INVALID-INPUT)
    (asserts! (> (len content-hash) u0) ERR-INVALID-INPUT)

    ;; Store content information
    (map-set content-registry content-id {
      title: title,
      description: description,
      owner: tx-sender,
      creator: tx-sender,
      content-hash: content-hash,
      content-type: content-type,
      metadata-uri: metadata-uri,
      registration-date: block-height,
      last-updated: block-height,
      is-active: true,
      transfer-count: u0
    })

    ;; Update counters
    (var-set next-content-id (+ content-id u1))
    (var-set total-registered (+ (var-get total-registered) u1))

    ;; Update owner content count
    (map-set owner-content-count tx-sender
      (+ (default-to u0 (map-get? owner-content-count tx-sender)) u1))

    (ok content-id)))

;; Transfer ownership
(define-public (transfer-ownership
  (content-id uint)
  (new-owner principal)
  (transfer-reason (string-ascii 128)))
  (let ((content-info (unwrap! (map-get? content-registry content-id) ERR-CONTENT-NOT-FOUND)))
    ;; Using native Clarity operators
    (asserts! (is-eq (get owner content-info) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (get is-active content-info) ERR-INVALID-INPUT)
    (asserts! (not (is-eq tx-sender new-owner)) ERR-INVALID-INPUT)

    ;; Update ownership
    (map-set content-registry content-id
      (merge content-info {
        owner: new-owner,
        last-updated: block-height,
        transfer-count: (+ (get transfer-count content-info) u1)
      }))

    ;; Update ownership history
    (let ((current-history (default-to (list) (map-get? content-ownership-history content-id))))
      (map-set content-ownership-history content-id
        (unwrap! (as-max-len?
          (append current-history {
            previous-owner: tx-sender,
            new-owner: new-owner,
            transfer-date: block-height,
            transfer-reason: transfer-reason
          }) u10) ERR-TRANSFER-FAILED)))

    ;; Update owner content counts
    (map-set owner-content-count tx-sender
      (- (default-to u1 (map-get? owner-content-count tx-sender)) u1))
    (map-set owner-content-count new-owner
      (+ (default-to u0 (map-get? owner-content-count new-owner)) u1))

    (ok true)))

;; Update content metadata
(define-public (update-metadata
  (content-id uint)
  (new-description (string-ascii 512))
  (new-metadata-uri (optional (string-ascii 256))))
  (let ((content-info (unwrap! (map-get? content-registry content-id) ERR-CONTENT-NOT-FOUND)))
    ;; Using native Clarity operators
    (asserts! (is-eq (get owner content-info) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (get is-active content-info) ERR-INVALID-INPUT)
    (asserts! (> (len new-description) u0) ERR-INVALID-INPUT)

    (map-set content-registry content-id
      (merge content-info {
        description: new-description,
        metadata-uri: new-metadata-uri,
        last-updated: block-height
      }))

    (ok true)))

;; Deactivate content
(define-public (deactivate-content (content-id uint))
  (let ((content-info (unwrap! (map-get? content-registry content-id) ERR-CONTENT-NOT-FOUND)))
    (asserts! (is-eq (get owner content-info) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (get is-active content-info) ERR-INVALID-INPUT)

    (map-set content-registry content-id
      (merge content-info {
        is-active: false,
        last-updated: block-height
      }))

    (ok true)))

;; Read-only Functions

;; Get content information
(define-read-only (get-content-info (content-id uint))
  (map-get? content-registry content-id))

;; Verify ownership
(define-read-only (verify-ownership (content-id uint) (claimed-owner principal))
  (match (map-get? content-registry content-id)
    content-info (and (is-eq (get owner content-info) claimed-owner) (get is-active content-info))
    false))

;; Get ownership history
(define-read-only (get-ownership-history (content-id uint))
  (map-get? content-ownership-history content-id))

;; Get owner content count
(define-read-only (get-owner-content-count (owner principal))
  (default-to u0 (map-get? owner-content-count owner)))

;; Get total registered content
(define-read-only (get-total-registered)
  (var-get total-registered))

;; Check if content exists and is active
(define-read-only (is-content-active (content-id uint))
  (match (map-get? content-registry content-id)
    content-info (get is-active content-info)
    false))
