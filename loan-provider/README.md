# Loan Provider

## Test

The tests are structured to work with fork-url only, i.e., base mainnet as local chain.

### Setup

#### Setup Cast Wallets

You need to setup two wallets:
- `bitmor_owner`: This will act as deployer and work with the admin functions of Bitmor Protocol.
- `bitmor_user`: This will act as a user interacting with Bitmor Protocol.

Learn how to setup cast wallet [here](https://getfoundry.sh/cast/reference/wallet).

#### Setup the ENV file

Take the reference from `.env.example`

#### Setup the environment

Run the following command in the `loan-provider` directory.

```bash
make install
make setup
```
