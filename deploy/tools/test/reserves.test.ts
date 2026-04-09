import { describe, it } from "node:test";
import assert from "node:assert";
import { mapReservesToRegistry, parseAddressArray, parseTupleAddresses } from "../src/reserves.js";

describe("parseAddressArray", () => {
  it("parses cast address[] output with spaces", () => {
    const raw = "[0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512, 0xa513E6E4b8f2a923D98304ec87F64353C4D5C853]";
    const result = parseAddressArray(raw);
    assert.strictEqual(result.length, 2);
    assert.strictEqual(result[0], "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512");
    assert.strictEqual(result[1], "0xa513E6E4b8f2a923D98304ec87F64353C4D5C853");
  });

  it("returns empty for empty brackets", () => {
    assert.strictEqual(parseAddressArray("[]").length, 0);
  });
});

describe("parseTupleAddresses", () => {
  it("extracts aToken and variableDebtToken from real cast output", () => {
    const raw =
      "(74354491629445928, 1000000000000000000000000000, 1000000000000000000000000000, 0, 0, 0, 0, 0x50778Fa94fe72061257862940aab7941adFCA22a, 0xb54B42DB68Ae5Ab711BDD7478A7D62BAa084A8B7, 0x097A4554fdfba0181c4142bb889d7cd4C8fe21a1, 0x95401dc811bb5740090279Ba06cfA8fcF6113778, 1)";
    const result = parseTupleAddresses(raw);
    assert.strictEqual(result.aToken, "0x50778Fa94fe72061257862940aab7941adFCA22a");
    assert.strictEqual(result.variableDebtToken, "0x097A4554fdfba0181c4142bb889d7cd4C8fe21a1");
  });

  it("throws when fewer than 3 addresses found", () => {
    assert.throws(() => parseTupleAddresses("(1, 2, 0xAABB, 3)"), /Expected at least 3 addresses/);
  });
});

describe("mapReservesToRegistry", () => {
  it("maps known reserves to registry dot-paths", () => {
    const reserves = [
      { underlying: "0xaaaa", aToken: "0xbbbb", variableDebtToken: "0xcccc" },
      { underlying: "0xdddd", aToken: "0xeeee", variableDebtToken: "0xffff" },
    ];
    const knownAssets = { "0xaaaa": "bvBTC", "0xdddd": "usdc" };
    const result = mapReservesToRegistry(reserves, knownAssets);

    assert.strictEqual(result["lendingPool.reserves.bvBTC.aToken"], "0xbbbb");
    assert.strictEqual(result["lendingPool.reserves.bvBTC.variableDebtToken"], "0xcccc");
    assert.strictEqual(result["lendingPool.reserves.usdc.aToken"], "0xeeee");
    assert.strictEqual(result["lendingPool.reserves.usdc.variableDebtToken"], "0xffff");
    assert.strictEqual(Object.keys(result).length, 4);
  });

  it("skips unknown reserve underlyings when no rpcUrl provided", () => {
    const reserves = [
      { underlying: "0xaaaa", aToken: "0xbbbb", variableDebtToken: "0xcccc" },
      { underlying: "0xunknown", aToken: "0x1111", variableDebtToken: "0x2222" },
    ];
    const knownAssets = { "0xaaaa": "bvBTC" };
    const result = mapReservesToRegistry(reserves, knownAssets);
    assert.strictEqual(Object.keys(result).length, 2);
  });

  it("returns empty map for empty reserves", () => {
    const result = mapReservesToRegistry([], {});
    assert.strictEqual(Object.keys(result).length, 0);
  });
});
