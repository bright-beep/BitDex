# BitDex Protocol: Technical Documentation

## Overview

BitDex is a sophisticated decentralized exchange protocol combining capital-efficient AMM mechanics with yield farming capabilities, built natively on Stacks (Bitcoin Layer 2). The protocol enables trustless trading of Bitcoin-native assets while providing advanced DeFi features typically found in Ethereum-based ecosystems.

### Key Features

- **Bitcoin-Compatible AMM**: Native support for Bitcoin-secured assets (sBTC, xBTC) via SLP-20 standard
- **Dynamic Fee Structure**: Programmable fee tiers from 0.01% to 1% per pool
- **Concentrated Liquidity**: Capital-efficient LP positions with adjustable price ranges
- **Yield Farming V2**: Reward-optimized staking pools with auto-compounding
- **Protocol-Owned Liquidity**: 30% of swap fees directed to governance-controlled treasury
- **Cross-Chain Ready**: Architecture designed for future Bitcoin L2 interoperability

## Technical Architecture

### Core Components

1. **Liquidity Pools**

   - Constant product AMM (x\*y=k) with fee accrual
   - Ordered token pair storage (token-x < token-y)
   - Reserve-weighted LP shares calculation

2. **Swap Engine**

   - Optimal price calculation with fee deduction:
     `amountOut = (amountIn * reserveOut) / (reserveIn + amountIn)`
   - Dynamic fee distribution (LP rewards + protocol treasury)

3. **Yield Farming**

   - Time-weighted reward distribution
   - Staked LP token tracking
   - Reward debt accounting system

4. **Governance Module**
   - Protocol parameter controls
   - Emergency pause functionality
   - Fee recipient management

## Installation & Deployment

### Requirements

- Clarinet v2.0.0+
- Stacks Node v3.5
- Bitcoin testnet environment

## Usage Examples

### 1. Pool Creation (Admin)

```clarity
(whitelist-token 'ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE.token-x)
(whitelist-token 'ST1HTBVD3JG9C05J7HBJTHGR0GGW7KXW28M5JS8QE.token-y)
(create-pool 'token-x 'token-y u300) ;; 0.3% fee pool
```

### 2. Liquidity Provision

```clarity
;; Add liquidity
(add-liquidity 'token-x 'token-y u1000000 u50000000 u0)

;; Remove liquidity
(remove-liquidity 'token-x 'token-y u500000 u100000 u4000000)
```

### 3. Token Swaps

```clarity
(swap-exact-tokens-for-tokens
  u1000000     ;; 1.0 token-in
  u990000000   ;; Min 9.9 token-out (1% slippage)
  'token-in
  'token-out
)
```

### 4. Yield Farming Operations

```clarity
;; Create farming pool
(create-farming-pool 'token-x 'token-y 'reward-token u100)

;; Stake LP tokens
(stake u1 u500000) ;; Pool ID 1, 500k shares

;; Claim rewards
(claim-rewards u1)

;; Unstake
(unstake u1 u250000)
```

## Error Codes

| Code                       | Value | Description                       |
| -------------------------- | ----- | --------------------------------- |
| ERR-NOT-AUTHORIZED         | u100  | Caller lacks required permissions |
| ERR-INSUFFICIENT-BALANCE   | u101  | User balance too low              |
| ERR-INSUFFICIENT-LIQUIDITY | u102  | Pool reserves insufficient        |
| ERR-INVALID-AMOUNT         | u103  | Invalid input parameter           |
| ERR-POOL-EXISTS            | u104  | Pool already created              |
| ERR-POOL-NOT-FOUND         | u105  | Nonexistent pool accessed         |
| ERR-SLIPPAGE-TOO-HIGH      | u106  | Price impact exceeds tolerance    |
| ERR-TOKEN-NOT-WHITELISTED  | u107  | Unauthorized token used           |

## Governance

### Protocol Parameters

```clarity
(define-data-var protocol-fee uint u30) ;; 0.3% (30 basis points)
(define-data-var protocol-fee-recipient principal 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
```

### Admin Functions

```clarity
;; Update protocol fee (0-1000 = 0-10%)
(set-protocol-fee u150) ;; 0.15%

;; Transfer ownership
(transfer-ownership 'STNEWADDRESS)
```
