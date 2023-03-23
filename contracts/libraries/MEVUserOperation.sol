// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/* solhint-disable no-inline-assembly */
import {IEntryPoint} from "../interfaces/IEntryPoint.sol";
import {UserOperation} from "../interfaces/UserOperation.sol";

/**
 * Utility functions helpful when working with UserOperation structs.
 */
library MEVUserOperation {
    function _internalUserBoostOpHash(
        UserOperation memory userOp
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    userOp.sender,
                    userOp.nonce,
                    keccak256(userOp.initCode),
                    keccak256(userOp.callData),
                    userOp.callGasLimit,
                    userOp.verificationGasLimit,
                    userOp.preVerificationGas,
                    userOp.maxFeePerGas,
                    userOp.maxPriorityFeePerGas
                )
            );
    }

    function boostHash(
        UserOperation memory userOp,
        IEntryPoint entryPoint
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _internalUserBoostOpHash(userOp),
                    address(this),
                    entryPoint,
                    block.chainid
                )
            );
    }
}
