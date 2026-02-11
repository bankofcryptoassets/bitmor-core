#!/usr/bin/env python3
"""
Calculate orphaned assets in Solady ERC-4626 vault with virtual offset.

convertToAssets(shares) = shares * (totalAssets + 1) / (totalSupply + 1)
"""

def orphaned_assets(total_supply, total_assets):
    """Calculate orphaned assets using exact integer math."""
    shares_value = (total_supply * (total_assets + 1)) // (total_supply + 1)
    orphaned = total_assets - shares_value
    return orphaned

def orphaned_percentage(total_supply, total_assets):
    """Calculate orphaned percentage."""
    orphaned = orphaned_assets(total_supply, total_assets)
    return (orphaned / total_assets) * 100 if total_assets > 0 else 0

# Test cases
print("=" * 80)
print("ORPHANED ASSETS ANALYSIS")
print("=" * 80)

# 1. Verify the problem with small totalSupply
print("\n1. Small totalSupply Problem:")
print("-" * 80)
test_cases = [
    (2, 2, "1:1 ratio, 2 shares"),
    (2, 3, "50% yield"),
    (10, 10, "1:1 ratio, 10 shares"),
    (10, 20, "100% yield"),
    (100, 100, "1:1 ratio, 100 shares"),
    (100, 200, "100% yield"),
]

for S, A, desc in test_cases:
    orphaned = orphaned_assets(S, A)
    pct = orphaned_percentage(S, A)
    print(f"S={S:4d}, A={A:4d} ({desc:20s}): Orphaned={orphaned:4d}, {pct:6.2f}%")

# 2. Find minimum S for different yield scenarios
print("\n2. Minimum totalSupply for < 0.01% Orphaned:")
print("-" * 80)

yield_scenarios = [
    (1.0, "No yield (1:1)"),
    (1.1, "10% yield"),
    (1.5, "50% yield"),
    (2.0, "100% yield"),
    (3.0, "200% yield"),
    (11.0, "1000% yield (stress)"),
]

for k, desc in yield_scenarios:
    # Binary search for minimum S
    min_S = 1
    for S in range(1, 100000):
        A = int(S * k)
        pct = orphaned_percentage(S, A)
        if pct < 0.01:
            min_S = S
            break

    A = int(min_S * k)
    orphaned = orphaned_assets(min_S, A)
    pct = orphaned_percentage(min_S, A)
    print(f"{desc:25s}: min_S={min_S:6d}, A={A:7d}, Orphaned={orphaned:4d}, {pct:.6f}%")

# 3. Convert to cbBTC (8 decimals)
print("\n3. Minimum Deposit in cbBTC (8 decimals, 1 BTC = 1e8 sat):")
print("-" * 80)

for k, desc in yield_scenarios:
    # Binary search for minimum S
    min_S = 1
    for S in range(1, 100000):
        A = int(S * k)
        pct = orphaned_percentage(S, A)
        if pct < 0.01:
            min_S = S
            break

    # Convert to BTC
    btc = min_S / 1e8
    sat = min_S

    print(f"{desc:25s}: {sat:8d} sat = {btc:.8f} BTC")

# Compare to BTCVault minimum
print(f"\nBTCVault current minimum: 1,000,000 sat = 0.01000000 BTC")

# 4. Seeded strategy analysis
print("\n4. Seeded Strategy (1000 sat initial deposit):")
print("-" * 80)

SEED = 1000  # sat

# Scenario: User deposits 1 BTC (1e8 sat), earns APY over 1 year
print("\nUser deposits 1 BTC after seed:")
user_deposit = int(1e8)  # 1 BTC
S = SEED + user_deposit
print(f"Initial: S={S} sat, A={S} sat")

apy_scenarios = [
    (0.01, "1% APY"),
    (0.05, "5% APY"),
    (0.10, "10% APY"),
]

for apy, desc in apy_scenarios:
    # After 1 year
    yield_amount = int(S * apy)
    A = S + yield_amount
    orphaned = orphaned_assets(S, A)
    pct = orphaned_percentage(S, A)

    print(f"{desc:10s}: A={A:11d} sat, Orphaned={orphaned:6d} sat ({pct:.6f}%), ${orphaned * 100000 / 1e8:.2f} @ $100k/BTC")

# 5. Worst case: seed only (no user deposits yet)
print("\n5. Worst Case: Seed Only (before any user deposits):")
print("-" * 80)

S = SEED
for apy, desc in apy_scenarios:
    # Hypothetical yield on just the seed
    yield_amount = int(S * apy)
    A = S + yield_amount
    orphaned = orphaned_assets(S, A)
    pct = orphaned_percentage(S, A)

    print(f"{desc:10s}: A={A:5d} sat, Orphaned={orphaned:3d} sat ({pct:.2f}%)")

print("\n" + "=" * 80)
