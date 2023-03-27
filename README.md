# MEVBoostAA

MEVBoostAA captures MEV from searchers to wallet based on the framework of ERC-4337 by `MEVBoostWallet` and `MEVBoostPaymaster`.

The wallet user just need to depoly a MEVBoostWallet(4337 wallet), construct a boostUserOp which is a userOp calling `boostExecute` or `boostExecuteBatch` and brocast it to the 4337 mempool.

The first paramter of `boostExecute` or `boostExecuteBatch` is `MEVConfig` which including `minAmount` and `selfSponsoredAfter`.

Searchers who has deposit fund to `MEVBoostPaymaster` will scan boostOps in the 4337 mempool.

- If the boostOp is profitable, the searcher will fill `paymasterAndData` to make boostUserOp valid, build a profitable bundle including that boostUserOp and sends it the bundler.Finally, if boostUserOp is executed success, the wallet user will get `minAmount` mev value from searcher and the boostUserOp is sponsored by the searcher.

- If the boostOp is not profitable, no searcher will fill the boostUserOp. Origin boostOp in the 4337 mempool will be valid after timestamp `selfSponsoredAfter`. The bundler will regularly bundle that boostUserOp.

Briefly, a boostUserOp is valid when one of the following conditions is met:

- Searcher fills the `paymasterAndData`, pays `minAmount` mev value to sender and sponsors that boostUserOp
- BoostUserOp is executed after timestamp `selfSponsoredAfter` and the sender sponsors that boostUser himself
