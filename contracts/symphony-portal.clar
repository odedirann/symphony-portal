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
