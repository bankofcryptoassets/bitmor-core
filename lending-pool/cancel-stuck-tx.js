// Script to cancel stuck transaction by replacing it with a 0-value self-transfer
// Run with: npx hardhat run cancel-stuck-tx.js --network sepolia

import hre from "hardhat";

async function main() {
  const conn = await hre.network.connect();
  const ethers = conn.ethers;

  const [signer] = await ethers.getSigners();
  const addr = await signer.getAddress();
  const provider = ethers.provider;

  console.log("Checking nonces for:", addr);

  const nonceLatest = await provider.getTransactionCount(addr, "latest");
  const noncePending = await provider.getTransactionCount(addr, "pending");

  console.log("Latest nonce:", nonceLatest);
  console.log("Pending nonce:", noncePending);

  if (nonceLatest === noncePending) {
    console.log("No stuck transactions. All clear!");
    return;
  }

  const numStuck = noncePending - nonceLatest;
  console.log(`\n⚠️  Found ${numStuck} stuck transaction(s)!`);
  console.log("Clearing all stuck transactions from nonce", nonceLatest, "to", noncePending - 1);

  const feeData = await provider.getFeeData();
  const bump = (x) => x ? (x * 16n) / 10n : undefined; // +60% gas bump for safety

  // Clear all stuck transactions
  for (let nonce = nonceLatest; nonce < noncePending; nonce++) {
    console.log(`\nSending replacement transaction with nonce: ${nonce}`);

    const tx = await signer.sendTransaction({
      to: addr,
      value: 0n,
      nonce: nonce,
      maxFeePerGas: bump(feeData.maxFeePerGas),
      maxPriorityFeePerGas: bump(feeData.maxPriorityFeePerGas),
    });

    console.log(`  Transaction sent: ${tx.hash}`);
    console.log(`  Waiting for confirmation...`);

    await tx.wait();
    console.log(`  ✅ Nonce ${nonce} cleared!`);
  }

  console.log("\n✅ All stuck transactions cleared!");
  console.log("You can now retry your deployment.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
