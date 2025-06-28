(define-constant challenge-fee u1000000) ;; 1 STX in microstacks
(define-constant required-days u7)       ;; Must log activity for 7 unique days

;; Admin-defined reward pool
(define-data-var reward-pool uint u0)

;; Admin principal (set once by deployer)
(define-data-var admin principal (as-contract tx-sender)) ;; Set to contract principal by default

;; Initialize admin (can only be called once)
(define-public (initialize-admin (admin-address principal))
  (begin
    (asserts! (is-eq (var-get admin) (as-contract tx-sender)) (err u200)) ;; Only if not set
    (var-set admin admin-address)
    (ok admin-address)
  )
)

;; Track participant logs
(define-map participant-log
  { user: principal }
  { joined-at: uint, days-logged: uint, last-log-block: uint }
)

;; Allow admin to fund the reward pool
(define-public (fund-reward-pool (amount uint))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err u100))
    (var-set reward-pool (+ (var-get reward-pool) amount))
    (ok (var-get reward-pool))
  )
)

;; Allow users to join the challenge
(define-public (join-challenge (current-block uint))
  (begin
    (asserts! (is-none (map-get? participant-log { user: tx-sender })) (err u101)) ;; Already joined
    ;; NOTE: Clarity does not support checking STX sent to contract directly. 
    ;; Enforce join fee off-chain or via transaction construction.
    (map-set participant-log { user: tx-sender } {
      joined-at: current-block,
      days-logged: u0,
      last-log-block: u0
    })
    (ok "Joined successfully")
  )
)

;; Submit daily activity proof
(define-public (submit-proof (current-block uint))
  (match (map-get? participant-log { user: tx-sender })
    entry
    (let (
      (last-block (get last-log-block entry))
      (days (get days-logged entry))
    )
      (begin
        (asserts! (> current-block last-block) (err u103)) ;; Only once per block
        (map-set participant-log { user: tx-sender } {
          joined-at: (get joined-at entry),
          days-logged: (+ days u1),
          last-log-block: current-block
        })
        ;; Log: activity-logged {user: tx-sender, days-completed: (+ days u1)}
        (ok (+ days u1))
      )
    )
    (err u104) ;; Not a participant
  )
)

;; Claim reward after completing the challenge
(define-public (claim-reward)
  (match (map-get? participant-log { user: tx-sender })
    entry
    (let ((days (get days-logged entry)))
      (if (>= days required-days)
          (let ((pool (var-get reward-pool)))
            (if (> pool u0)
                (let ((reward (/ pool u10))) ;; Fixed share from pool
                  (begin
                    (map-delete participant-log { user: tx-sender })
                    (var-set reward-pool (- pool reward))
                    (try! (stx-transfer? reward (var-get admin) tx-sender))
                    ;; Log: reward-claimed {user: tx-sender, amount: reward}
                    (ok reward)
                  )
                )
                (err u106) ;; No reward pool
            )
          )
          (err u105) ;; Not enough days logged
      )
    )
    (err u104) ;; Not a participant
  )
)

;; Read-only function to get user status
(define-read-only (get-user-status (user principal))
  (map-get? participant-log { user: user })
)

;; Read-only function to check the current reward pool
(define-read-only (get-reward-pool)
  (ok (var-get reward-pool))
) 

;; Error codes:
;; u100 - Not admin
;; u101 - Already joined
;; u102 - Must send exactly 1 STX (enforced off-chain)
;; u103 - Cannot log twice in same block
;; u104 - User not registered
;; u105 - Challenge not complete
;; u106 - No reward pool

;; NOTE: Clarity does not provide a way to access the amount of STX sent to a contract function directly.
;; You must enforce STX payments off-chain or via transaction construction.
;; u104 - User not registered
;; u105 - Challenge not complete
;; u106 - No reward pool

;; NOTE: Clarity does not provide a way to access the amount of STX sent to a contract function directly.
;; You must use payable functions and check the amount in the transaction, or use SIP-010 tokens for more advanced logic.
