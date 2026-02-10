import { describe, expect, it } from "vitest";

const accounts = simnet.getAccounts();
const owner = accounts.get("wallet_1")!;
const user = accounts.get("wallet_2")!;

describe("BitDex Complete Test Suite", () => {
  const tokenX = "ST1ABCDE12345.token-x";
  const tokenY = "ST1ABCDE12345.token-y";
  const rewardToken = "ST1ABCDE12345.reward-token";
  const feeRate = 30; // 0.3%
  const initialAmountX = 1000;
  const initialAmountY = 2000;

  // ------------------------------
  // Sanity check
  // ------------------------------
  it("simnet initialized", () => {
    expect(simnet.blockHeight).toBeDefined();
  });

  // ------------------------------
  // Token whitelisting and pool creation
  // ------------------------------
  it("whitelists tokens and creates a pool", () => {
    let res = simnet.callPublicFn("bitdex", "whitelist-token", [tokenX], owner);
    expect(res.result).toBeOk();

    res = simnet.callPublicFn("bitdex", "whitelist-token", [tokenY], owner);
    expect(res.result).toBeOk();

    res = simnet.callPublicFn("bitdex", "create-pool", [tokenX, tokenY, feeRate], owner);
    expect(res.result).toBeOk();
  });

  it("fails to create pool with non-whitelisted tokens", () => {
    const res = simnet.callPublicFn(
      "bitdex",
      "create-pool",
      ["ST1INVALID.token-a", "ST1INVALID.token-b", feeRate],
      owner
    );
    expect(res.result).toBeErr();
  });

  // ------------------------------
  // Liquidity management
  // ------------------------------
  it("adds liquidity", () => {
    const res = simnet.callPublicFn(
      "bitdex",
      "add-liquidity",
      [tokenX, tokenY, initialAmountX, initialAmountY, 1],
      user
    );
    expect(res.result).toBeOk();
  });

  it("fails to add liquidity when paused", () => {
    simnet.callPublicFn("bitdex", "set-pause-status", [true], owner);

    const res = simnet.callPublicFn(
      "bitdex",
      "add-liquidity",
      [tokenX, tokenY, 100, 100, 1],
      user
    );
    expect(res.result).toBeErr();

    simnet.callPublicFn("bitdex", "set-pause-status", [false], owner);
  });

  it("removes liquidity", () => {
    const res = simnet.callPublicFn(
      "bitdex",
      "remove-liquidity",
      [tokenX, tokenY, 10, 1, 1],
      user
    );
    expect(res.result).toBeOk();
  });

  it("fails to remove more liquidity than owned", () => {
    const res = simnet.callPublicFn(
      "bitdex",
      "remove-liquidity",
      [tokenX, tokenY, 999999, 1, 1],
      user
    );
    expect(res.result).toBeErr();
  });

  // ------------------------------
  // Token swaps
  // ------------------------------
  it("swaps tokens", () => {
    const res = simnet.callPublicFn(
      "bitdex",
      "swap-exact-tokens-for-tokens",
      [10, 1, tokenX, tokenY],
      user
    );
    expect(res.result).toBeOk();
  });

  it("fails swap if slippage too high", () => {
    const res = simnet.callPublicFn(
      "bitdex",
      "swap-exact-tokens-for-tokens",
      [1, 1000000, tokenX, tokenY],
      user
    );
    expect(res.result).toBeErr();
  });

  // ------------------------------
  // Farming / yield staking
  // ------------------------------
  it("creates farming pool", () => {
    const res = simnet.callPublicFn(
      "bitdex",
      "create-farming-pool",
      [tokenX, tokenY, rewardToken, 50],
      owner
    );
    expect(res.result).toBeOk();
  });

  it("stakes LP tokens", () => {
    const res = simnet.callPublicFn("bitdex", "stake", [1, 5], user);
    expect(res.result).toBeOk();
  });

  it("fails staking more than LP balance", () => {
    const res = simnet.callPublicFn("bitdex", "stake", [1, 999999], user);
    expect(res.result).toBeErr();
  });

  it("unstakes LP tokens", () => {
    const res = simnet.callPublicFn("bitdex", "unstake", [1, 3], user);
    expect(res.result).toBeOk();
  });

  it("fails unstaking more than staked", () => {
    const res = simnet.callPublicFn("bitdex", "unstake", [1, 999999], user);
    expect(res.result).toBeErr();
  });

  it("claims rewards", () => {
    const res = simnet.callPublicFn("bitdex", "claim-rewards", [1], user);
    expect(res.result).toBeOk();
  });

  it("fails claiming rewards with no stake", () => {
    const res = simnet.callPublicFn("bitdex", "claim-rewards", [999], user);
    expect(res.result).toBeErr();
  });

  // ------------------------------
  // Admin functions
  // ------------------------------
  it("sets protocol fee", () => {
    const res = simnet.callPublicFn("bitdex", "set-protocol-fee", [50], owner);
    expect(res.result).toBeOk();
  });

  it("fails to set protocol fee above max", () => {
    const res = simnet.callPublicFn("bitdex", "set-protocol-fee", [2000], owner);
    expect(res.result).toBeErr();
  });

  it("fails non-owner performing admin actions", () => {
    const feeRes = simnet.callPublicFn("bitdex", "set-protocol-fee", [50], user);
    expect(feeRes.result).toBeErr();

    const pauseRes = simnet.callPublicFn("bitdex", "set-pause-status", [true], user);
    expect(pauseRes.result).toBeErr();

    const ownerRes = simnet.callPublicFn("bitdex", "transfer-ownership", [user], user);
    expect(ownerRes.result).toBeErr();
  });

  it("transfers ownership", () => {
    const res = simnet.callPublicFn("bitdex", "transfer-ownership", [user], owner);
    expect(res.result).toBeOk();

    // Revert ownership back for tests
    simnet.callPublicFn("bitdex", "transfer-ownership", [owner], user);
  });
});
