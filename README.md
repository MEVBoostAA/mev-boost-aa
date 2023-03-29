# MEVBoostAA

The current paradigm for MEV primarily benefits validators and searchers. However, the MEV is caputured from the user and the user accutally pays more than just indicated transaction fee. In other word, users have been robbed secretly.

In the user's view:

- user -- fee to excute tx --> validator

However, things happen like that:

- user -- fee to excute tx --> validator
- user -- mev caputured by searcher --> searcher
- searcher -- share mev with validator --> validator

MEVBoostAA captures MEV from searchers to wallets based on the framework of ERC-4337 by implementing `MEVBoostWallet` and `MEVBoostPaymaster`.

Now, things become must better:

- user -- mev caputured by searcher --> searcher
- **searcher (as a paymaster) -- fee to excute tx --> validator**
- **searcher -- max mev (through auction) refund to user --> user**
- searcher -- share mev with validator --> validator

## Work Flow

![image info](./graphs/interaction.png)

The wallet user just need to depoly a 4337 wallet `MEVBoostWallet`, construct a boostUserOp which is a userOp calling method `boostExecute` or `boostExecuteBatch` of sender wallet and brocast it to the 4337 mempool.

The first paramter of method `boostExecute` or `boostExecuteBatch` is `MEVConfig` which including `minAmount` and `selfSponsoredAfter`.

Searchers who has deposit fund to `MEVBoostPaymaster` will scan all boostUserOps in the 4337 mempool.

- If the boostOp is profitable, the searcher will fill `paymasterAndData` to make boostUserOp valid, build a profitable bundle including that boostUserOp and sends it the bundler. Finally, if boostUserOp is success, the wallet user will get `minAmount` mev value from searcher and the boostUserOp is sponsored by the searcher.

- If the boostOp is not profitable, no searcher will fill the boostUserOp. Origin boostOp in the 4337 mempool will be valid after timestamp `selfSponsoredAfter`. The bundler will regularly bundle that boostUserOp.

Briefly, a boostUserOp is valid when one of the following conditions is met:

- Searcher fills the `paymasterAndData`, pays `minAmount` mev value to sender and sponsors that boostUserOp.
- The boostUserOp is valid after timestamp `selfSponsoredAfter` and sponsored by the sender.

## Prerequisite

- node (>=16.0.0 <18)
- yarn (^1.22.10)
- foundry
- Environment Variables (Used for foundry fork tests)
  - MAINNET_NODE_RPC_URL: The RPC URL for accessing forked states.

### Example

```
  MAINNET_NODE_RPC_URL=https://eth-mainnet.alchemyapi.io/v2/#####__YOUR_SECRET__#####
```

## Installation

```
$ git submodule update --init --recursive
$ yarn run setup
```

## Compile contracts

```
$ yarn run compile # compile contracts
```

## Run unit test

```
$ yarn run test-foundry-fork # run unit tests with forked states
```
