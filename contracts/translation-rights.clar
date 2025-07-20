;; Translation Rights Contract
;; Manages international publishing agreements

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-ALREADY-EXISTS (err u501))
(define-constant ERR-NOT-FOUND (err u502))
(define-constant ERR-INVALID-INPUT (err u503))
(define-constant ERR-RIGHTS-UNAVAILABLE (err u504))
(define-constant ERR-TRANSLATION-INCOMPLETE (err u505))

;; Data Variables
(define-data-var next-agreement-id uint u1)
(define-data-var next-translation-id uint u1)
(define-data-var platform-fee uint u250) ;; 2.5% in basis points

;; Data Maps
(define-map translation-agreements
  { agreement-id: uint }
  {
    book-id: uint,
    original-author: principal,
    translator: principal,
    target-language: (string-ascii 10),
    territory: (string-ascii 50),
    royalty-split: uint, ;; Translator's percentage
    advance-payment: uint,
    deadline: uint,
    status: (string-ascii 20),
    created-at: uint
  }
)

(define-map language-rights
  { book-id: uint, language: (string-ascii 10) }
  {
    available: bool,
    exclusive-translator: (optional principal),
    total-agreements: uint,
    revenue-generated: uint
  }
)

(define-map translations
  { translation-id: uint }
  {
    agreement-id: uint,
    content-hash: (buff 32),
    word-count: uint,
    completion-percentage: uint,
    quality-score: uint,
    submitted-at: uint,
    approved: bool
  }
)

(define-map translator-profiles
  { translator: principal }
  {
    languages: (list 10 (string-ascii 10)),
    completed-translations: uint,
    average-quality: uint,
    total-earnings: uint,
    reputation-score: uint
  }
)

(define-map territory-rights
  { book-id: uint, territory: (string-ascii 50) }
  {
    exclusive-rights-holder: (optional principal),
    rights-expiry: uint,
    revenue-share: uint
  }
)

(define-map quality-reviews
  { translation-id: uint, reviewer: principal }
  {
    score: uint,
    feedback: (string-ascii 500),
    reviewed-at: uint
  }
)

;; Public Functions

;; Register translator profile
(define-public (register-translator (languages (list 10 (string-ascii 10))))
  (let
    (
      (translator tx-sender)
    )
    (asserts! (is-none (map-get? translator-profiles { translator: translator })) ERR-ALREADY-EXISTS)
    (asserts! (> (len languages) u0) ERR-INVALID-INPUT)

    (map-set translator-profiles
      { translator: translator }
      {
        languages: languages,
        completed-translations: u0,
        average-quality: u0,
        total-earnings: u0,
        reputation-score: u100
      }
    )

    (ok true)
  )
)

;; Create translation agreement
(define-public (create-translation-agreement
  (book-id uint)
  (translator principal)
  (target-language (string-ascii 10))
  (territory (string-ascii 50))
  (royalty-split uint)
  (advance-payment uint)
  (deadline-blocks uint))
  (let
    (
      (agreement-id (var-get next-agreement-id))
      (author tx-sender)
      (deadline (+ block-height deadline-blocks))
      (language-rights-data (default-to
        { available: true, exclusive-translator: none, total-agreements: u0, revenue-generated: u0 }
        (map-get? language-rights { book-id: book-id, language: target-language })
      ))
    )
    (asserts! (> (len target-language) u0) ERR-INVALID-INPUT)
    (asserts! (> (len territory) u0) ERR-INVALID-INPUT)
    (asserts! (<= royalty-split u5000) ERR-INVALID-INPUT) ;; Max 50%
    (asserts! (> deadline-blocks u0) ERR-INVALID-INPUT)
    (asserts! (get available language-rights-data) ERR-RIGHTS-UNAVAILABLE)

    ;; Create agreement
    (map-set translation-agreements
      { agreement-id: agreement-id }
      {
        book-id: book-id,
        original-author: author,
        translator: translator,
        target-language: target-language,
        territory: territory,
        royalty-split: royalty-split,
        advance-payment: advance-payment,
        deadline: deadline,
        status: "active",
        created-at: block-height
      }
    )

    ;; Update language rights
    (map-set language-rights
      { book-id: book-id, language: target-language }
      (merge language-rights-data {
        total-agreements: (+ (get total-agreements language-rights-data) u1)
      })
    )

    (var-set next-agreement-id (+ agreement-id u1))

    (ok agreement-id)
  )
)

;; Submit translation
(define-public (submit-translation (agreement-id uint) (content-hash (buff 32)) (word-count uint))
  (let
    (
      (translation-id (var-get next-translation-id))
      (agreement-data (unwrap! (map-get? translation-agreements { agreement-id: agreement-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get translator agreement-data)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status agreement-data) "active") ERR-INVALID-INPUT)
    (asserts! (<= block-height (get deadline agreement-data)) ERR-INVALID-INPUT)
    (asserts! (> word-count u0) ERR-INVALID-INPUT)

    (map-set translations
      { translation-id: translation-id }
      {
        agreement-id: agreement-id,
        content-hash: content-hash,
        word-count: word-count,
        completion-percentage: u100,
        quality-score: u0,
        submitted-at: block-height,
        approved: false
      }
    )

    ;; Update agreement status
    (map-set translation-agreements
      { agreement-id: agreement-id }
      (merge agreement-data { status: "submitted" })
    )

    (var-set next-translation-id (+ translation-id u1))

    (ok translation-id)
  )
)

;; Review translation quality
(define-public (review-translation (translation-id uint) (score uint) (feedback (string-ascii 500)))
  (let
    (
      (translation-data (unwrap! (map-get? translations { translation-id: translation-id }) ERR-NOT-FOUND))
      (agreement-data (unwrap! (map-get? translation-agreements { agreement-id: (get agreement-id translation-data) }) ERR-NOT-FOUND))
      (reviewer tx-sender)
    )
    (asserts! (is-eq reviewer (get original-author agreement-data)) ERR-NOT-AUTHORIZED)
    (asserts! (>= score u1) ERR-INVALID-INPUT)
    (asserts! (<= score u10) ERR-INVALID-INPUT)

    (map-set quality-reviews
      { translation-id: translation-id, reviewer: reviewer }
      {
        score: score,
        feedback: feedback,
        reviewed-at: block-height
      }
    )

    ;; Update translation quality score
    (map-set translations
      { translation-id: translation-id }
      (merge translation-data { quality-score: score })
    )

    (ok true)
  )
)

;; Approve translation
(define-public (approve-translation (translation-id uint))
  (let
    (
      (translation-data (unwrap! (map-get? translations { translation-id: translation-id }) ERR-NOT-FOUND))
      (agreement-data (unwrap! (map-get? translation-agreements { agreement-id: (get agreement-id translation-data) }) ERR-NOT-FOUND))
      (translator-data (unwrap! (map-get? translator-profiles { translator: (get translator agreement-data) }) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get original-author agreement-data)) ERR-NOT-AUTHORIZED)
    (asserts! (> (get quality-score translation-data) u6) ERR-INVALID-INPUT) ;; Minimum quality threshold

    ;; Approve translation
    (map-set translations
      { translation-id: translation-id }
      (merge translation-data { approved: true })
    )

    ;; Update agreement status
    (map-set translation-agreements
      { agreement-id: (get agreement-id translation-data) }
      (merge agreement-data { status: "completed" })
    )

    ;; Update translator profile
    (map-set translator-profiles
      { translator: (get translator agreement-data) }
      (merge translator-data {
        completed-translations: (+ (get completed-translations translator-data) u1),
        average-quality: (/ (+ (* (get average-quality translator-data) (get completed-translations translator-data)) (get quality-score translation-data)) (+ (get completed-translations translator-data) u1)),
        total-earnings: (+ (get total-earnings translator-data) (get advance-payment agreement-data)),
        reputation-score: (+ (get reputation-score translator-data) u10)
      })
    )

    (ok true)
  )
)

;; Grant exclusive territory rights
(define-public (grant-territory-rights (book-id uint) (territory (string-ascii 50)) (rights-holder principal) (duration-blocks uint) (revenue-share uint))
  (let
    (
      (expiry-block (+ block-height duration-blocks))
    )
    (asserts! (> (len territory) u0) ERR-INVALID-INPUT)
    (asserts! (> duration-blocks u0) ERR-INVALID-INPUT)
    (asserts! (<= revenue-share u10000) ERR-INVALID-INPUT) ;; Max 100%

    (map-set territory-rights
      { book-id: book-id, territory: territory }
      {
        exclusive-rights-holder: (some rights-holder),
        rights-expiry: expiry-block,
        revenue-share: revenue-share
      }
    )

    (ok true)
  )
)

;; Record translation revenue
(define-public (record-translation-revenue (book-id uint) (language (string-ascii 10)) (revenue uint))
  (let
    (
      (language-rights-data (unwrap! (map-get? language-rights { book-id: book-id, language: language }) ERR-NOT-FOUND))
    )
    (asserts! (> revenue u0) ERR-INVALID-INPUT)

    (map-set language-rights
      { book-id: book-id, language: language }
      (merge language-rights-data {
        revenue-generated: (+ (get revenue-generated language-rights-data) revenue)
      })
    )

    (ok true)
  )
)

;; Read-only Functions

(define-read-only (get-translation-agreement (agreement-id uint))
  (map-get? translation-agreements { agreement-id: agreement-id })
)

(define-read-only (get-language-rights (book-id uint) (language (string-ascii 10)))
  (map-get? language-rights { book-id: book-id, language: language })
)

(define-read-only (get-translation (translation-id uint))
  (map-get? translations { translation-id: translation-id })
)

(define-read-only (get-translator-profile (translator principal))
  (map-get? translator-profiles { translator: translator })
)

(define-read-only (get-territory-rights (book-id uint) (territory (string-ascii 50)))
  (map-get? territory-rights { book-id: book-id, territory: territory })
)

(define-read-only (get-quality-review (translation-id uint) (reviewer principal))
  (map-get? quality-reviews { translation-id: translation-id, reviewer: reviewer })
)

(define-read-only (get-next-agreement-id)
  (var-get next-agreement-id)
)

(define-read-only (get-next-translation-id)
  (var-get next-translation-id)
)
