import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert";
import { readRegistry, mergeIntoRegistry, writeRegistry } from "../src/registry.js";
import { mkdtempSync, rmSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

describe("registry", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = mkdtempSync(join(tmpdir(), "bitmor-test-"));
  });

  afterEach(() => {
    rmSync(tmpDir, { recursive: true, force: true });
  });

  it("reads empty registry when file doesn't exist", () => {
    const reg = readRegistry(tmpDir, "31337");
    assert.strictEqual(reg, null);
  });

  it("writes and reads back registry", () => {
    const data = {
      network: "localhost",
      chainId: 31337,
      timestamp: 1712200800000,
      commit: "abc123",
      deployer: "0xf39f...",
      loanProvider: { accessManager: "0x1111" },
      lendingPool: {},
      tokens: {},
      external: {},
    };
    writeRegistry(tmpDir, "31337", data);

    const read = readRegistry(tmpDir, "31337");
    assert.deepStrictEqual(read, data);
  });

  it("creates timestamped snapshot on write", () => {
    const data = {
      network: "localhost",
      chainId: 31337,
      timestamp: 1712200800000,
      commit: "abc123",
      deployer: "0xf39f...",
      loanProvider: {},
      lendingPool: {},
      tokens: {},
      external: {},
    };
    writeRegistry(tmpDir, "31337", data);

    const snapshotPath = join(tmpDir, "31337", "1712200800000.json");
    const snapshot = JSON.parse(readFileSync(snapshotPath, "utf-8"));
    assert.deepStrictEqual(snapshot, data);
  });

  it("deep merges new addresses without overwriting existing", () => {
    const existing = {
      network: "localhost",
      chainId: 31337,
      timestamp: 1712200800000,
      commit: "abc123",
      deployer: "0xf39f...",
      loanProvider: { accessManager: "0x1111", btcVault: "0x2222" },
      lendingPool: {},
      tokens: { usdc: "0x3333" },
      external: {},
    };

    const updates = {
      "loanProvider.loan": "0x4444",
      "loanProvider.loanImpl": "0x5555",
      "tokens.cbBTC": "0x6666",
    };

    const result = mergeIntoRegistry(existing, updates, 1712200900000, "def456");

    assert.strictEqual(result.loanProvider.accessManager, "0x1111"); // preserved
    assert.strictEqual(result.loanProvider.btcVault, "0x2222"); // preserved
    assert.strictEqual((result.loanProvider as any).loan, "0x4444"); // new
    assert.strictEqual((result.loanProvider as any).loanImpl, "0x5555"); // new
    assert.strictEqual(result.tokens.usdc, "0x3333"); // preserved
    assert.strictEqual((result.tokens as any).cbBTC, "0x6666"); // new
    assert.strictEqual(result.timestamp, 1712200900000); // updated
    assert.strictEqual(result.commit, "def456"); // updated
  });
});
