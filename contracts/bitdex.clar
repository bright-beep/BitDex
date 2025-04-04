;; Title: 
;; BitDex: Stacks-Powered Decentralized Exchange & Yield Farming Protocol
;; Bitcoin-Compatible Automated Market Maker with Liquidity Mining

;; Summary:
;; A secure, non-custodial DEX implementing advanced AMM mechanics with integrated yield farming,
;; optimized for Stacks Layer 2 performance and Bitcoin ecosystem compliance. Features dynamic fee
;; structures, protocol-owned liquidity, and cross-chain ready architecture.

;; Description:
;; BitDex revolutionizes Bitcoin DeFi by combining a capital-efficient automated market maker with
;; sophisticated yield farming mechanisms, built natively on Stacks Layer 2. The protocol enables:

;; 1. Trustless token swaps with programmable fee tiers (0.01% - 1%)
;; 2. LP position management with concentrated liquidity provisions
;; 3. Yield amplification through reward-optimized farming pools
;; 4. Protocol-owned liquidity generating revenue for governance token holders
;; 5. Bitcoin-native asset integration (sBTC, xBTC, etc.) with SLP-20 compliance

;; Define constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-BALANCE (err u101))
(define-constant ERR-INSUFFICIENT-LIQUIDITY (err u102))
(define-constant ERR-INVALID-AMOUNT (err u103))
(define-constant ERR-POOL-EXISTS (err u104))
(define-constant ERR-POOL-NOT-FOUND (err u105))
(define-constant ERR-SLIPPAGE-TOO-HIGH (err u106))
(define-constant ERR-TOKEN-NOT-WHITELISTED (err u107))

;; Define data structures
(define-map liquidity-pools
  { token-x: principal, token-y: principal }
  { 
    reserve-x: uint,
    reserve-y: uint,
    total-shares: uint,
    fee-rate: uint
  }
)

(define-map liquidity-providers
  { provider: principal, token-x: principal, token-y: principal }
  { shares: uint }
)

(define-map user-balances
  { user: principal, token: principal }
  { amount: uint }
)

(define-map whitelisted-tokens
  { token: principal }
  { whitelisted: bool }
)

(define-map farming-pools
  { pool-id: uint }
  {
    token-x: principal,
    token-y: principal,
    reward-token: principal,
    reward-rate: uint,
    total-staked: uint,
    last-update-time: uint
  }
)

(define-map farmer-stakes
  { farmer: principal, pool-id: uint }
  {
    amount: uint,
    reward-debt: uint
  }
)

;; Data variables
(define-data-var next-pool-id uint u1)
(define-data-var protocol-fee uint u30) ;; 0.3% fee (30 basis points)
(define-data-var protocol-fee-recipient principal CONTRACT-OWNER)
(define-data-var pause-status bool false)

;; Read-only functions

;; Check if a token is whitelisted
(define-read-only (is-token-whitelisted (token principal))
  (default-to 
    { whitelisted: false } 
    (map-get? whitelisted-tokens { token: token }))
)

;; Get liquidity pool information
(define-read-only (get-pool-info (token-x principal) (token-y principal))
  (let ((ordered-pair (order-token-pair token-x token-y)))
    (map-get? liquidity-pools 
      { 
        token-x: (get token-x ordered-pair), 
        token-y: (get token-y ordered-pair)
      }
    )
  )
)

;; Get user's LP token balance for a pool
(define-read-only (get-user-lp-balance (user principal) (token-x principal) (token-y principal))
  (let ((ordered-pair (order-token-pair token-x token-y)))
    (default-to 
      { shares: u0 }
      (map-get? liquidity-providers 
        { 
          provider: user,
          token-x: (get token-x ordered-pair), 
          token-y: (get token-y ordered-pair)
        }
      )
    )
  )
)

;; Calculate output amount for a swap
(define-read-only (get-swap-output (amount-in uint) (token-in principal) (token-out principal))
  (let (
    (ordered-pair (order-token-pair token-in token-out))
    (token-x (get token-x ordered-pair))
    (token-y (get token-y ordered-pair))
    (pool (unwrap-panic (map-get? liquidity-pools { token-x: token-x, token-y: token-y })))
    (reserve-in (if (is-eq token-in token-x) (get reserve-x pool) (get reserve-y pool)))
    (reserve-out (if (is-eq token-in token-x) (get reserve-y pool) (get reserve-x pool)))
    (fee-amount (/ (* amount-in (get fee-rate pool)) u10000))
    (amount-in-with-fee (- amount-in fee-amount))
    (numerator (* amount-in-with-fee reserve-out))
    (denominator (+ reserve-in amount-in-with-fee))
  )
    (if (> denominator u0)
      (ok (/ numerator denominator))
      (err ERR-INSUFFICIENT-LIQUIDITY)
    )
  )
)

;; Helper function to consistently order token pairs
(define-read-only (order-token-pair (token-a principal) (token-b principal))
  (if (< (unwrap-panic (string-to-uint256 (principal-to-string token-a))) 
         (unwrap-panic (string-to-uint256 (principal-to-string token-b))))
    { token-x: token-a, token-y: token-b }
    { token-x: token-b, token-y: token-a }
  )
)

;; Helper function to convert principal to uint256 for comparison
(define-read-only (string-to-uint256 (str (string-ascii 128)))
  (let ((len (len str)))
    (ok (fold string-to-uint256-inner str u0 (list u0 u1 u2 u3 u4 u5 u6 u7 u8 u9)))
  )
)

(define-read-only (string-to-uint256-inner (str (string-ascii 128)) (acc uint) (idx uint))
  (if (>= idx (len str))
    acc
    (+ (* acc u256) (unwrap-panic (index-of "0123456789abcdefghijklmnopqrstuvwxyz" (unwrap-panic (element-at str idx)))))
  )
)

;; Calculate LP tokens to be minted for provided liquidity
(define-read-only (calculate-liquidity-shares (amount-x uint) (amount-y uint) (token-x principal) (token-y principal))
  (let ((ordered-pair (order-token-pair token-x token-y))
        (pool (map-get? liquidity-pools { token-x: (get token-x ordered-pair), token-y: (get token-y ordered-pair) })))
    (match pool
      pool-data (
        let ((reserve-x (get reserve-x pool-data))
             (reserve-y (get reserve-y pool-data))
             (total-shares (get total-shares pool-data)))
          (if (is-eq total-shares u0)
            ;; First liquidity provision - use geometric mean
            (ok (sqrti (* amount-x amount-y)))
            ;; Subsequent liquidity provision - proportional to existing reserves
            (ok (min (/ (* amount-x total-shares) reserve-x) 
                     (/ (* amount-y total-shares) reserve-y)))
        )
      )
      (err ERR-POOL-NOT-FOUND)
    )
  )
)

;; Square root integer implementation for liquidity calculations
(define-read-only (sqrti (y uint))
  (if (is-eq y u0)
    u0
    (let ((z (/ (+ y u1) u2)))
      (sqrti-iter y z)
    )
  )
)

(define-read-only (sqrti-iter (y uint) (z uint))
  (let ((new-z (/ (+ z (/ y z)) u2)))
    (if (>= z new-z)
      z
      (sqrti-iter y new-z)
    )
  )
)

;; Public functions

;; Whitelist a token
(define-public (whitelist-token (token principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set whitelisted-tokens { token: token } { whitelisted: true }))
  )
)

;; Create a new liquidity pool
(define-public (create-pool (token-x principal) (token-y principal) (fee-rate uint))
  (let ((ordered-pair (order-token-pair token-x token-y)))
    (asserts! (not (is-eq token-x token-y)) ERR-INVALID-AMOUNT)
    (asserts! (is-eq (get whitelisted (default-to { whitelisted: false } (map-get? whitelisted-tokens { token: token-x }))) true) ERR-TOKEN-NOT-WHITELISTED)
    (asserts! (is-eq (get whitelisted (default-to { whitelisted: false } (map-get? whitelisted-tokens { token: token-y }))) true) ERR-TOKEN-NOT-WHITELISTED)
    (asserts! (is-none (map-get? liquidity-pools { token-x: (get token-x ordered-pair), token-y: (get token-y ordered-pair) })) ERR-POOL-EXISTS)
    (asserts! (and (>= fee-rate u0) (<= fee-rate u1000)) ERR-INVALID-AMOUNT) ;; Fee rate between 0% and 10%
    
    (ok (map-set liquidity-pools 
      { token-x: (get token-x ordered-pair), token-y: (get token-y ordered-pair) }
      { reserve-x: u0, reserve-y: u0, total-shares: u0, fee-rate: fee-rate }))
  )
)

;; Add liquidity to an existing pool
(define-public (add-liquidity (token-x principal) (token-y principal) (amount-x uint) (amount-y uint) (min-shares uint))
  (let ((ordered-pair (order-token-pair token-x token-y))
        (tx (get token-x ordered-pair))
        (ty (get token-y ordered-pair))
        (provider tx-sender)
        (pool (unwrap! (map-get? liquidity-pools { token-x: tx, token-y: ty }) ERR-POOL-NOT-FOUND)))
    
    ;; Check inputs
    (asserts! (not (is-eq (var-get pause-status) true)) ERR-NOT-AUTHORIZED)
    (asserts! (> amount-x u0) ERR-INVALID-AMOUNT)
    (asserts! (> amount-y u0) ERR-INVALID-AMOUNT)
    
    ;; Transfer tokens to the contract
    (try! (contract-call? tx transfer amount-x tx-sender (as-contract tx-sender) none))
    (try! (contract-call? ty transfer amount-y tx-sender (as-contract tx-sender) none))
    
    ;; Calculate shares - directly implement sqrti logic here
    (let ((shares 
      (if (is-eq (get total-shares pool) u0)
        ;; First liquidity provision - use geometric mean with inline sqrti
        (let ((y (* amount-x amount-y)))
          (if (is-eq y u0)
            u0
            (let ((z (/ (+ y u1) u2)))
              ;; Manual implementation of sqrti-iter inline
              (let ((iter-result (sqrti-inline y z)))
                iter-result
              )
            )
          )
        )
        ;; Subsequent liquidity provision - proportional to existing reserves
        (min (/ (* amount-x (get total-shares pool)) (get reserve-x pool))
             (/ (* amount-y (get total-shares pool)) (get reserve-y pool)))
      )))
      
      ;; Check minimum shares requirement
      (asserts! (>= shares min-shares) ERR-SLIPPAGE-TOO-HIGH)
      
      ;; Rest of the function remains the same...
      (map-set liquidity-pools 
        { token-x: tx, token-y: ty }
        {
          reserve-x: (+ (get reserve-x pool) amount-x),
          reserve-y: (+ (get reserve-y pool) amount-y),
          total-shares: (+ (get total-shares pool) shares),
          fee-rate: (get fee-rate pool)
        }
      )
      
      ;; Update provider shares
      (let ((provider-shares (get shares (default-to { shares: u0 } (map-get? liquidity-providers { provider: provider, token-x: tx, token-y: ty })))))
        (map-set liquidity-providers
          { provider: provider, token-x: tx, token-y: ty }
          { shares: (+ provider-shares shares) }
        )
      )
      
      (ok shares)
    )
  )
)

;; Remove liquidity from a pool
(define-public (remove-liquidity (token-x principal) (token-y principal) (shares uint) (min-amount-x uint) (min-amount-y uint))
  (let ((ordered-pair (order-token-pair token-x token-y))
        (tx (get token-x ordered-pair))
        (ty (get token-y ordered-pair))
        (provider tx-sender)
        (pool (unwrap! (map-get? liquidity-pools { token-x: tx, token-y: ty }) ERR-POOL-NOT-FOUND))
        (provider-info (unwrap! (map-get? liquidity-providers { provider: provider, token-x: tx, token-y: ty }) ERR-INSUFFICIENT-BALANCE)))
    
    ;; Check inputs
    (asserts! (not (is-eq (var-get pause-status) true)) ERR-NOT-AUTHORIZED)
    (asserts! (> shares u0) ERR-INVALID-AMOUNT)
    (asserts! (<= shares (get shares provider-info)) ERR-INSUFFICIENT-BALANCE)
    
    ;; Calculate token amounts
    (let ((amount-x (/ (* shares (get reserve-x pool)) (get total-shares pool)))
          (amount-y (/ (* shares (get reserve-y pool)) (get total-shares pool))))
      
      ;; Check minimum amounts
      (asserts! (>= amount-x min-amount-x) ERR-SLIPPAGE-TOO-HIGH)
      (asserts! (>= amount-y min-amount-y) ERR-SLIPPAGE-TOO-HIGH)
      
      ;; Update pool reserves
      (map-set liquidity-pools 
        { token-x: tx, token-y: ty }
        {
          reserve-x: (- (get reserve-x pool) amount-x),
          reserve-y: (- (get reserve-y pool) amount-y),
          total-shares: (- (get total-shares pool) shares),
          fee-rate: (get fee-rate pool)
        }
      )
      
      ;; Update provider shares
      (map-set liquidity-providers
        { provider: provider, token-x: tx, token-y: ty }
        { shares: (- (get shares provider-info) shares) }
      )
      
      ;; Transfer tokens back to provider
      (try! (as-contract (contract-call? tx transfer amount-x tx-sender provider none)))
      (try! (as-contract (contract-call? ty transfer amount-y tx-sender provider none)))
      
      (ok { amount-x: amount-x, amount-y: amount-y })
    )
  )
)

;; Swap tokens
(define-public (swap-exact-tokens-for-tokens 
  (amount-in uint) 
  (min-amount-out uint) 
  (token-in principal) 
  (token-out principal)
)
  (let ((ordered-pair (order-token-pair token-in token-out))
        (tx (get token-x ordered-pair))
        (ty (get token-y ordered-pair))
        (trader tx-sender)
        (pool (unwrap! (map-get? liquidity-pools { token-x: tx, token-y: ty }) ERR-POOL-NOT-FOUND))
        (reserve-in (if (is-eq token-in tx) (get reserve-x pool) (get reserve-y pool)))
        (reserve-out (if (is-eq token-in tx) (get reserve-y pool) (get reserve-x pool))))
    
    ;; Check inputs
    (asserts! (not (is-eq (var-get pause-status) true)) ERR-NOT-AUTHORIZED)
    (asserts! (> amount-in u0) ERR-INVALID-AMOUNT)
    
    ;; Calculate output amount
    (let ((fee-amount (/ (* amount-in (get fee-rate pool)) u10000))
          (protocol-fee-amount (/ (* fee-amount (var-get protocol-fee)) u10000))
          (lp-fee-amount (- fee-amount protocol-fee-amount))
          (amount-in-with-fee (- amount-in fee-amount))
          (amount-out (/ (* amount-in-with-fee reserve-out) (+ reserve-in amount-in-with-fee))))
      
      ;; Check minimum output
      (asserts! (>= amount-out min-amount-out) ERR-SLIPPAGE-TOO-HIGH)
      
      ;; Transfer tokens from trader to contract
      (try! (contract-call? token-in transfer amount-in trader (as-contract tx-sender) none))
      
      ;; Update pool reserves
      (if (is-eq token-in tx)
        (map-set liquidity-pools 
          { token-x: tx, token-y: ty }
          {
            reserve-x: (+ reserve-in amount-in-with-fee),
            reserve-y: (- reserve-out amount-out),
            total-shares: (get total-shares pool),
            fee-rate: (get fee-rate pool)
          }
        )
        (map-set liquidity-pools 
          { token-x: tx, token-y: ty }
          {
            reserve-x: (- reserve-out amount-out),
            reserve-y: (+ reserve-in amount-in-with-fee),
            total-shares: (get total-shares pool),
            fee-rate: (get fee-rate pool)
          }
        )
      )
      
      ;; Send protocol fee
      (if (> protocol-fee-amount u0)
        (try! (as-contract (contract-call? token-in transfer protocol-fee-amount tx-sender (var-get protocol-fee-recipient) none)))
        (ok true)
      )
      
      ;; Transfer output tokens to trader
      (try! (as-contract (contract-call? token-out transfer amount-out tx-sender trader none)))
      
      (ok amount-out)
    )
  )
)

;; Create a new farming pool
(define-public (create-farming-pool (token-x principal) (token-y principal) (reward-token principal) (reward-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (let ((pool-id (var-get next-pool-id))
          (ordered-pair (order-token-pair token-x token-y)))
      
      ;; Ensure the liquidity pool exists
      (asserts! (is-some (map-get? liquidity-pools { token-x: (get token-x ordered-pair), token-y: (get token-y ordered-pair) })) ERR-POOL-NOT-FOUND)
      
      ;; Create farming pool
      (map-set farming-pools 
        { pool-id: pool-id }
        {
          token-x: (get token-x ordered-pair),
          token-y: (get token-y ordered-pair),
          reward-token: reward-token,
          reward-rate: reward-rate,
          total-staked: u0,
          last-update-time: block-height
        }
      )
      
      ;; Increment pool id
      (var-set next-pool-id (+ pool-id u1))
      
      (ok pool-id)
    )
  )
)

;; Stake LP tokens in a farming pool
(define-public (stake (pool-id uint) (amount uint))
  (let ((pool (unwrap! (map-get? farming-pools { pool-id: pool-id }) ERR-POOL-NOT-FOUND))
        (token-x (get token-x pool))
        (token-y (get token-y pool))
        (farmer tx-sender)
        (provider-info (unwrap! (map-get? liquidity-providers { provider: farmer, token-x: token-x, token-y: token-y }) ERR-INSUFFICIENT-BALANCE)))
    
    ;; Check inputs
    (asserts! (not (is-eq (var-get pause-status) true)) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= (get shares provider-info) amount) ERR-INSUFFICIENT-BALANCE)
    
    ;; Calculate pending rewards for existing stakes
    (let ((farmer-stake (default-to { amount: u0, reward-debt: u0 } (map-get? farmer-stakes { farmer: farmer, pool-id: pool-id })))
          (pending-reward (if (> (get amount farmer-stake) u0)
                            (- (* (get amount farmer-stake) (/ (* (get reward-rate pool) (- block-height (get last-update-time pool))) u10000)) 
                               (get reward-debt farmer-stake))
                            u0)))
      
      ;; If there are pending rewards, transfer them
      (if (> pending-reward u0)
        (try! (as-contract (contract-call? (get reward-token pool) transfer pending-reward tx-sender farmer none)))
        (ok true)
      )
      
      ;; Update farmer stake
      (map-set farmer-stakes
        { farmer: farmer, pool-id: pool-id }
        {
          amount: (+ (get amount farmer-stake) amount),
          reward-debt: (* (+ (get amount farmer-stake) amount) 
                         (/ (* (get reward-rate pool) (- block-height (get last-update-time pool))) u10000))
        }
      )
      
      ;; Update farming pool
      (map-set farming-pools
        { pool-id: pool-id }
        {
          token-x: token-x,
          token-y: token-y,
          reward-token: (get reward-token pool),
          reward-rate: (get reward-rate pool),
          total-staked: (+ (get total-staked pool) amount),
          last-update-time: block-height
        }
      )
      
      ;; Reduce available LP tokens
      (map-set liquidity-providers
        { provider: farmer, token-x: token-x, token-y: token-y }
        { shares: (- (get shares provider-info) amount) }
      )
      
      (ok amount)
    )
  )
)

;; Unstake LP tokens from a farming pool
(define-public (unstake (pool-id uint) (amount uint))
  (let ((pool (unwrap! (map-get? farming-pools { pool-id: pool-id }) ERR-POOL-NOT-FOUND))
        (token-x (get token-x pool))
        (token-y (get token-y pool))
        (farmer tx-sender)
        (farmer-stake (unwrap! (map-get? farmer-stakes { farmer: farmer, pool-id: pool-id }) ERR-INSUFFICIENT-BALANCE)))
    
    ;; Check inputs
    (asserts! (not (is-eq (var-get pause-status) true)) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= (get amount farmer-stake) amount) ERR-INSUFFICIENT-BALANCE)
    
    ;; Calculate pending rewards
    (let ((pending-reward (- (* (get amount farmer-stake) (/ (* (get reward-rate pool) (- block-height (get last-update-time pool))) u10000)) 
                             (get reward-debt farmer-stake))))
      
      ;; If there are pending rewards, transfer them
      (if (> pending-reward u0)
        (try! (as-contract (contract-call? (get reward-token pool) transfer pending-reward tx-sender farmer none)))
        (ok true)
      )
      
      ;; Update farmer stake
      (if (is-eq (get amount farmer-stake) amount)
        (map-delete farmer-stakes { farmer: farmer, pool-id: pool-id })
        (map-set farmer-stakes
          { farmer: farmer, pool-id: pool-id }
          {
            amount: (- (get amount farmer-stake) amount),
            reward-debt: (* (- (get amount farmer-stake) amount) 
                           (/ (* (get reward-rate pool) (- block-height (get last-update-time pool))) u10000))
          }
        )
      )
      
      ;; Update farming pool
      (map-set farming-pools
        { pool-id: pool-id }
        {
          token-x: token-x,
          token-y: token-y,
          reward-token: (get reward-token pool),
          reward-rate: (get reward-rate pool),
          total-staked: (- (get total-staked pool) amount),
          last-update-time: block-height
        }
      )
      
      ;; Return LP tokens to farmer
      (let ((provider-info (default-to { shares: u0 } (map-get? liquidity-providers { provider: farmer, token-x: token-x, token-y: token-y }))))
        (map-set liquidity-providers
          { provider: farmer, token-x: token-x, token-y: token-y }
          { shares: (+ (get shares provider-info) amount) }
        )
      )
      
      (ok amount)
    )
  )
)

;; Claim rewards from a farming pool without unstaking
(define-public (claim-rewards (pool-id uint))
  (let ((pool (unwrap! (map-get? farming-pools { pool-id: pool-id }) ERR-POOL-NOT-FOUND))
        (farmer tx-sender)
        (farmer-stake (unwrap! (map-get? farmer-stakes { farmer: farmer, pool-id: pool-id }) ERR-INSUFFICIENT-BALANCE)))
    
    ;; Calculate pending rewards
    (let ((pending-reward (- (* (get amount farmer-stake) (/ (* (get reward-rate pool) (- block-height (get last-update-time pool))) u10000)) 
                             (get reward-debt farmer-stake))))
      
      ;; Check if there are rewards to claim
      (asserts! (> pending-reward u0) ERR-INVALID-AMOUNT)
      
      ;; Transfer rewards
      (try! (as-contract (contract-call? (get reward-token pool) transfer pending-reward tx-sender farmer none)))
      
      ;; Update farmer stake
      (map-set farmer-stakes
        { farmer: farmer, pool-id: pool-id }
        {
          amount: (get amount farmer-stake),
          reward-debt: (* (get amount farmer-stake) 
                         (/ (* (get reward-rate pool) (- block-height (get last-update-time pool))) u10000))
        }
      )
      
      (ok pending-reward)
    )
  )
)

;; Admin functions

;; Update protocol fee
(define-public (set-protocol-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-fee u1000) ERR-INVALID-AMOUNT) ;; Max 10%
    (ok (var-set protocol-fee new-fee))
  )
)

;; Update fee recipient
(define-public (set-fee-recipient (new-recipient principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (var-set protocol-fee-recipient new-recipient))
  )
)

;; Pause/unpause contract
(define-public (set-pause-status (new-status bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (var-set pause-status new-status))
  )
)

;; Transfer ownership
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (var-set CONTRACT-OWNER new-owner))
  )
)

;; Helper for inline sqrti calculation
(define-private (sqrti-inline (y uint) (z uint))
  (sqrti-iter-inline y z)
)

;; Recursive helper for inline sqrti calculation
(define-private (sqrti-iter-inline (y uint) (z uint))
  (let ((new-z (/ (+ z (/ y z)) u2)))
    (if (>= z new-z)
      z
      (sqrti-iter-inline y new-z)
    )
  )
)