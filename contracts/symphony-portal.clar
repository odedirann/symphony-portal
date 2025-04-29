;; Symphony Portal: A Distributed Melodic Assets Management System
;; 
;; This contract facilitates a decentralized platform for melodic asset management
;; Users can register compositions, transfer asset rights, and curate personal collections
;; Built with Clarity for a robust and transparent musical ecosystem

;; ------------------------------------------------------------
;; State Management Variables
;; ------------------------------------------------------------
(define-data-var composition-registry-size uint u0)   ;; Tracks total number of registered compositions
(define-data-var ensemble-registry-size uint u0)      ;; Tracks total number of curated ensembles

;; ------------------------------------------------------------
;; Core System Constants 
;; ------------------------------------------------------------
(define-constant ERROR-INVALID-LENGTH (err u304)) ;; Response when composition length is outside acceptable range
(define-constant ERROR-NOT-AUTHORIZED (err u305)) ;; Response when operation is attempted without proper rights
(define-constant ERROR-PERMISSION-REJECTED (err u306)) ;; Response when access request is denied
(define-constant ERROR-ADMINISTRATOR-REQUIRED (err u307)) ;; Response when admin privileges are required
(define-constant ERROR-OPERATION-FORBIDDEN (err u308))    ;; Response when operation violates system rules
(define-constant PORTAL-ADMINISTRATOR tx-sender)  ;; Establishes the contract creator as system administrator
(define-constant ERROR-ASSET-MISSING (err u301))  ;; Response when attempting to access non-existent composition
(define-constant ERROR-ASSET-EXISTS (err u302))   ;; Response when attempting to create a duplicate composition
(define-constant ERROR-INVALID-NAME (err u303))   ;; Response when composition name is invalid

;; ------------------------------------------------------------
;; Data Structure Definitions
;; ------------------------------------------------------------


;; Ensemble collections mapping
(define-map ensemble-registry
    {identifier: uint}  ;; Key: Ensemble ID
    {
        title: (string-ascii 64),           ;; Ensemble title
        description: (string-ascii 256),    ;; Ensemble description
        founder: principal,                 ;; Ensemble creator
        style: (string-ascii 32),           ;; Ensemble style
        creation-timestamp: uint,           ;; Creation block
        modification-timestamp: uint,       ;; Last modification block
        composition-total: uint,            ;; Number of compositions
        collaborative-status: bool          ;; Collaboration setting
    }
)

;; Ensemble contributors mapping
(define-map ensemble-contributors
    {ensemble-id: uint, contributor: principal}  ;; Key: Ensemble ID and contributor
    {
        contributor-status: bool,    ;; Whether contributor status is active
        joining-timestamp: uint,     ;; Block when joined
        founder-status: bool         ;; Whether contributor is founder
    }
)

;; Compositions in ensembles mapping
(define-map ensemble-compositions
    {ensemble-id: uint, composition-id: uint}  ;; Key: Ensemble ID and composition ID
    {
        contributor: principal,     ;; Contributor who added composition
        addition-timestamp: uint    ;; Block when added
    }
)

;; Central registry mapping composition identifiers to their complete details
(define-map composition-registry
    {identifier: uint}  ;; Key: Unique composition identifier
    {
        name: (string-ascii 64),           ;; Composition title (max 64 chars)
        composer: (string-ascii 32),       ;; Composer name (max 32 chars)
        rights-holder: principal,          ;; Current rights holder address
        length-seconds: uint,              ;; Playback length in seconds
        registration-block: uint,          ;; Block height at registration
        category: (string-ascii 32),       ;; Musical category classification
        descriptive-elements: (list 8 (string-ascii 24))  ;; Descriptive markers for search and organization
    }
)

;; Maps access privileges for each composition across different users
(define-map access-privileges
    {composition-identifier: uint, listener: principal}  ;; Key: Composition ID and User Principal
    {access-granted: bool}  ;; Value: Whether access is permitted
)


;; Compositions within collections mapping
(define-map collection-compositions
    {collection-curator: principal, collection-id: uint, composition-id: uint}  ;; Key: Collection curator, ID, and composition ID
    {
        addition-timestamp: uint,  ;; Block when added
        sequence-position: uint    ;; Position in collection
    }
)

;; Access grant history
(define-map privilege-history
    {composition-id: uint, grantor: principal, recipient: principal}  ;; Key: Composition ID, grantor, and recipient
    {
        grant-timestamp: uint,     ;; Block when access was granted
        revocation-timestamp: uint, ;; Block when access was revoked (0 if active)
        privilege-active: bool      ;; Whether access is currently active
    }
)

;; Listener feedback system
(define-map listener-feedback
    {composition-id: uint, evaluator: principal}  ;; Key: Composition ID and evaluator
    {
        score: uint,                           ;; Rating (1-5)
        commentary: (optional (string-ascii 256)),  ;; Optional commentary
        update-timestamp: uint,                ;; Block when last updated
        initial-evaluation-timestamp: uint     ;; Block when first evaluated
    }
)

;; Aggregated feedback statistics
(define-map feedback-statistics
    {composition-id: uint}  ;; Key: Composition ID
    {
        evaluation-count: uint,       ;; Total number of evaluations
        last-evaluated-timestamp: uint  ;; Block when last evaluated
    }
)

;; User's personal collection tracking
(define-map curator-collection-counters
    {curator: principal}  ;; Key: Curator Principal
    {latest-collection-id: uint}  ;; Value: Most recent collection created
)

;; Collection details mapping
(define-map melodic-collections
    {curator: principal, collection-id: uint}  ;; Key: Collection owner and ID
    {
        title: (string-ascii 64),           ;; Collection title
        summary: (string-ascii 128),        ;; Collection description
        creation-timestamp: uint,           ;; Creation block
        modification-timestamp: uint,       ;; Last modification block
        composition-total: uint,            ;; Number of compositions
        publicly-accessible: bool           ;; Visibility setting
    }
)

;; ------------------------------------------------------------
;; Core Utility Functions (Private)
;; ------------------------------------------------------------

;; Verifies if a composition exists in the registry
(define-private (composition-exists (composition-id uint))
    (is-some (map-get? composition-registry {identifier: composition-id}))
)

;; Verifies rights holder status for a composition
(define-private (is-rights-holder (composition-id uint) (user principal))
    (match (map-get? composition-registry {identifier: composition-id})
        composition-data (is-eq (get rights-holder composition-data) user)
        false
    )
)

;; Retrieves composition length in seconds
(define-private (get-composition-length (composition-id uint))
    (default-to u0 
        (get length-seconds 
            (map-get? composition-registry {identifier: composition-id})
        )
    )
)

;; Validates that a descriptive element conforms to length requirements
(define-private (is-valid-descriptor (descriptor (string-ascii 24)))
    (and 
        (> (len descriptor) u0)
        (< (len descriptor) u25)
    )
)

;; Validates that a collection of descriptors meets system requirements
(define-private (are-valid-descriptors (descriptors (list 8 (string-ascii 24))))
    (and
        (> (len descriptors) u0)
        (<= (len descriptors) u8)
        (is-eq (len (filter is-valid-descriptor descriptors)) (len descriptors))
    )
)

;; Retrieves latest collection identifier for a curator
(define-private (get-latest-collection-id (curator principal))
    (get latest-collection-id (default-to {latest-collection-id: u0} 
        (map-get? curator-collection-counters {curator: curator})))
)

;; Prepares composition identifiers for bulk operations
(define-private (prepare-composition-id (composition-id uint))
    {composition-id: composition-id}
)

;; Adds composition to ensemble during bulk operations
(define-private (integrate-composition-to-ensemble (composition-data {composition-id: uint}))
    (let
        ((composition-id (get composition-id composition-data)))
        (and 
            (composition-exists composition-id)
            (map-insert ensemble-compositions
                {ensemble-id: (var-get ensemble-registry-size), composition-id: composition-id}
                {
                    contributor: tx-sender,
                    addition-timestamp: block-height
                }
            )
        )
    )
)

;; ------------------------------------------------------------
;; Primary System Operations (Public)
;; ------------------------------------------------------------

;; Registers a new composition in the system
(define-public (register-composition 
        (name (string-ascii 64))
        (composer (string-ascii 32))
        (length-seconds uint)
        (category (string-ascii 32))
        (descriptors (list 8 (string-ascii 24)))
    )
    (let
        ((new-composition-id (+ (var-get composition-registry-size) u1)))

        ;; Input validation
        (asserts! (and (> (len name) u0) (< (len name) u65)) ERROR-INVALID-NAME)
        (asserts! (and (> (len composer) u0) (< (len composer) u33)) ERROR-INVALID-NAME)
        (asserts! (and (> length-seconds u0) (< length-seconds u10000)) ERROR-INVALID-LENGTH)
        (asserts! (and (> (len category) u0) (< (len category) u33)) ERROR-INVALID-NAME)
        (asserts! (are-valid-descriptors descriptors) ERROR-INVALID-NAME)

        ;; Add composition to registry
        (map-insert composition-registry
            {identifier: new-composition-id}
            {
                name: name,
                composer: composer,
                rights-holder: tx-sender,
                length-seconds: length-seconds,
                registration-block: block-height,
                category: category,
                descriptive-elements: descriptors
            }
        )

        ;; Establish initial access privileges
        (map-insert access-privileges
            {composition-identifier: new-composition-id, listener: tx-sender}
            {access-granted: true}
        )

        ;; Update registry size and return new identifier
        (var-set composition-registry-size new-composition-id)
        (ok new-composition-id)
    )
)

;; Deregisters a composition from the system
(define-public (deregister-composition (composition-id uint))
    (let
        ((composition-data (unwrap! (map-get? composition-registry {identifier: composition-id}) ERROR-ASSET-MISSING)))

        ;; Validation
        (asserts! (composition-exists composition-id) ERROR-ASSET-MISSING)
        (asserts! (is-eq (get rights-holder composition-data) tx-sender) ERROR-NOT-AUTHORIZED)

        ;; Remove composition data
        (map-delete composition-registry {identifier: composition-id})
        (map-delete access-privileges {composition-identifier: composition-id, listener: tx-sender})
        (ok true)
    )
)

;; Transfers composition rights to a new holder
(define-public (transfer-composition-rights (composition-id uint) (new-rights-holder principal))
    (let
        ((composition-data (unwrap! (map-get? composition-registry {identifier: composition-id}) ERROR-ASSET-MISSING)))

        ;; Validation
        (asserts! (composition-exists composition-id) ERROR-ASSET-MISSING)
        (asserts! (is-eq (get rights-holder composition-data) tx-sender) ERROR-NOT-AUTHORIZED)

        ;; Update rights holder
        (map-set composition-registry
            {identifier: composition-id}
            (merge composition-data {rights-holder: new-rights-holder})
        )
        (ok true)
    )
)

;; Updates composition details
(define-public (update-composition-details 
        (composition-id uint) 
        (new-name (string-ascii 64)) 
        (new-length-seconds uint) 
        (new-category (string-ascii 32)) 
        (new-descriptors (list 8 (string-ascii 24)))
    )
    (let
        ((composition-data (unwrap! (map-get? composition-registry {identifier: composition-id}) ERROR-ASSET-MISSING)))

        ;; Validation
        (asserts! (composition-exists composition-id) ERROR-ASSET-MISSING)
        (asserts! (is-eq (get rights-holder composition-data) tx-sender) ERROR-NOT-AUTHORIZED)
        (asserts! (and (> (len new-name) u0) (< (len new-name) u65)) ERROR-INVALID-NAME)
        (asserts! (and (> new-length-seconds u0) (< new-length-seconds u10000)) ERROR-INVALID-LENGTH)
        (asserts! (and (> (len new-category) u0) (< (len new-category) u33)) ERROR-INVALID-NAME)
        (asserts! (are-valid-descriptors new-descriptors) ERROR-INVALID-NAME)

        ;; Update composition details
        (map-set composition-registry
            {identifier: composition-id}
            (merge composition-data {
                name: new-name,
                length-seconds: new-length-seconds,
                category: new-category,
                descriptive-elements: new-descriptors
            })
        )
        (ok true)
    )
)

;; Adds composition to personal collection
(define-public (add-to-personal-collection 
        (collection-id uint)
        (composition-id uint)
    )
    (let
        ((collection-data (unwrap! (map-get? melodic-collections {curator: tx-sender, collection-id: collection-id}) ERROR-ASSET-MISSING))
         (composition-data (unwrap! (map-get? composition-registry {identifier: composition-id}) ERROR-ASSET-MISSING))
         (listener-access (default-to {access-granted: false} (map-get? access-privileges {composition-identifier: composition-id, listener: tx-sender}))))

        ;; Validation
        (asserts! (composition-exists composition-id) ERROR-ASSET-MISSING)
        (asserts! (or 
                    (is-eq (get rights-holder composition-data) tx-sender)
                    (get access-granted listener-access)
                  ) 
                ERROR-PERMISSION-REJECTED)

        ;; Check for duplicates
        (asserts! (is-none (map-get? collection-compositions {collection-curator: tx-sender, collection-id: collection-id, composition-id: composition-id})) 
                 ERROR-ASSET-EXISTS)

        (ok true)
    )
)

;; Grants access to a composition
(define-public (grant-composition-access 
        (composition-id uint)
        (recipient principal)
    )
    (let
        ((composition-data (unwrap! (map-get? composition-registry {identifier: composition-id}) ERROR-ASSET-MISSING)))

        ;; Validation
        (asserts! (composition-exists composition-id) ERROR-ASSET-MISSING)
        (asserts! (is-eq (get rights-holder composition-data) tx-sender) ERROR-NOT-AUTHORIZED)
        (asserts! (not (is-eq tx-sender recipient)) ERROR-INVALID-NAME)

        ;; Check for existing grant
        (asserts! (is-none (map-get? access-privileges {composition-identifier: composition-id, listener: recipient})) 
                 ERROR-ASSET-EXISTS)

        ;; Grant access
        (map-insert access-privileges
            {composition-identifier: composition-id, listener: recipient}
            {access-granted: true}
        )

        ;; Record grant history
        (map-insert privilege-history
            {composition-id: composition-id, grantor: tx-sender, recipient: recipient}
            {
                grant-timestamp: block-height,
                revocation-timestamp: u0,
                privilege-active: true
            }
        )

        (ok true)
    )
)

;; Revokes previously granted access
(define-public (revoke-composition-access 
        (composition-id uint)
        (recipient principal)
    )
    (let
        ((composition-data (unwrap! (map-get? composition-registry {identifier: composition-id}) ERROR-ASSET-MISSING))
         (access-data (unwrap! (map-get? privilege-history {composition-id: composition-id, grantor: tx-sender, recipient: recipient}) ERROR-ASSET-MISSING)))

        ;; Validation
        (asserts! (composition-exists composition-id) ERROR-ASSET-MISSING)
        (asserts! (is-eq (get rights-holder composition-data) tx-sender) ERROR-NOT-AUTHORIZED)
        (asserts! (get privilege-active access-data) ERROR-PERMISSION-REJECTED)

        (ok true)
    )
)

;; Submits listener feedback for a composition
(define-public (submit-composition-feedback 
        (composition-id uint)
        (score uint)
        (commentary (optional (string-ascii 256)))
    )
    (let
        ((composition-data (unwrap! (map-get? composition-registry {identifier: composition-id}) ERROR-ASSET-MISSING))
         (listener-access (default-to {access-granted: false} (map-get? access-privileges {composition-identifier: composition-id, listener: tx-sender})))
         (existing-feedback (map-get? listener-feedback {composition-id: composition-id, evaluator: tx-sender})))

        ;; Validation
        (asserts! (composition-exists composition-id) ERROR-ASSET-MISSING)
        (asserts! (or 
                    (is-eq (get rights-holder composition-data) tx-sender)
                    (get access-granted listener-access)
                  ) 
                ERROR-PERMISSION-REJECTED)
        (asserts! (and (>= score u1) (<= score u5)) ERROR-INVALID-NAME)

        ;; Validate commentary length if provided
        (if (is-some commentary)
            (asserts! (and 
                        (> (len (default-to "" commentary)) u0) 
                        (< (len (default-to "" commentary)) u257)
                      ) 
                    ERROR-INVALID-NAME)
            true
        )

        ;; Store or update feedback
        (if (is-some existing-feedback)
            ;; Update existing feedback
            (map-set listener-feedback
                {composition-id: composition-id, evaluator: tx-sender}
                {
                    score: score,
                    commentary: commentary,
                    update-timestamp: block-height,
                    initial-evaluation-timestamp: (get initial-evaluation-timestamp (unwrap! existing-feedback ERROR-ASSET-MISSING))
                }
            )
            ;; Create new feedback
            (map-insert listener-feedback
                {composition-id: composition-id, evaluator: tx-sender}
                {
                    score: score,
                    commentary: commentary,
                    update-timestamp: block-height,
                    initial-evaluation-timestamp: block-height
                }
            )
        )

        ;; Update feedback statistics
        (match (map-get? feedback-statistics {composition-id: composition-id})
            existing-stats (map-set feedback-statistics
                {composition-id: composition-id}
                (merge existing-stats {
                    evaluation-count: (if (is-some existing-feedback) 
                                      (get evaluation-count existing-stats) 
                                      (+ (get evaluation-count existing-stats) u1)),
                    last-evaluated-timestamp: block-height
                })
            )
            (map-insert feedback-statistics
                {composition-id: composition-id}
                {
                    evaluation-count: u1,
                    last-evaluated-timestamp: block-height
                }
            )
        )

        (ok true)
    )
)

;; Creates a thematic ensemble of compositions
(define-public (establish-themed-ensemble
        (ensemble-title (string-ascii 64))
        (description (string-ascii 256))
        (style (string-ascii 32))
        (initial-compositions (list 20 uint))
        (collaborative-status bool)
    )
    (let
        ((new-ensemble-id (+ (var-get ensemble-registry-size) u1))
         (valid-compositions (filter composition-exists initial-compositions)))

        ;; Validation
        (asserts! (and (> (len ensemble-title) u0) (< (len ensemble-title) u65)) ERROR-INVALID-NAME)
        (asserts! (and (> (len description) u0) (< (len description) u257)) ERROR-INVALID-NAME)
        (asserts! (and (> (len style) u0) (< (len style) u33)) ERROR-INVALID-NAME)

        ;; Register founder as contributor
        (map-insert ensemble-contributors
            {ensemble-id: new-ensemble-id, contributor: tx-sender}
            {
                contributor-status: true,
                joining-timestamp: block-height,
                founder-status: true
            }
        )

        ;; Add validated compositions to ensemble
        (map integrate-composition-to-ensemble (map prepare-composition-id valid-compositions))

        ;; Update ensemble registry size
        (var-set ensemble-registry-size new-ensemble-id)

        (ok new-ensemble-id)
    )
)

