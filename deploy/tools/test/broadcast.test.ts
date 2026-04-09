import { describe, it } from "node:test";
import assert from "node:assert";
import { parseBroadcast } from "../src/broadcast.js";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const fixturesDir = resolve(import.meta.dirname, "fixtures");

describe("parseBroadcast", () => {
  it("extracts CREATE transactions only", () => {
    const json = JSON.parse(readFileSync(`${fixturesDir}/broadcast-phase1.json`, "utf-8"));
    const result = parseBroadcast(json);

    // Should have 5 CREATE transactions (AccessManager, MockUSDC, MockCbBTC, BTCVault, ERC1967Proxy), not the CALL
    assert.strictEqual(result.contracts.length, 5);
    assert.ok(result.contracts.every((c) => c.type === "CREATE"));
  });

  it("preserves deployment order", () => {
    const json = JSON.parse(readFileSync(`${fixturesDir}/broadcast-phase1.json`, "utf-8"));
    const result = parseBroadcast(json);

    assert.strictEqual(result.contracts[0].name, "BitmorAccessManager");
    assert.strictEqual(result.contracts[1].name, "MockUSDC");
    assert.strictEqual(result.contracts[2].name, "MockCbBTC");
    assert.strictEqual(result.contracts[3].name, "BTCVault");
    assert.strictEqual(result.contracts[4].name, "ERC1967Proxy");
    assert.strictEqual(result.contracts.length, 5);
  });

  it("extracts metadata", () => {
    const json = JSON.parse(readFileSync(`${fixturesDir}/broadcast-phase1.json`, "utf-8"));
    const result = parseBroadcast(json);

    assert.strictEqual(result.chainId, 31337);
    assert.strictEqual(result.commit, "abc1234");
    assert.strictEqual(result.deployer, "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266");
  });

  it("extracts libraries from libraries array", () => {
    const json = JSON.parse(readFileSync(`${fixturesDir}/broadcast-libraries.json`, "utf-8"));
    const result = parseBroadcast(json);

    assert.strictEqual(result.libraries.length, 4);
    assert.deepStrictEqual(result.libraries[0], {
      path: "src/libraries/logic/LoanLogic.sol",
      name: "LoanLogic",
      address: "0x1111000000000000000000000000000000000001",
    });
  });
});
