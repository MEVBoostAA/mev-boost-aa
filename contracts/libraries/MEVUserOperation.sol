// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/* solhint-disable no-inline-assembly */
import {IEntryPoint} from "../interfaces/IEntryPoint.sol";

import {calldataKeccak} from "../libraries/Helpers.sol";
import {UserOperation, UserOperationLib} from "../interfaces/UserOperation.sol";

/**
 * Utility functions helpful when working with UserOperation structs.
 */
library MEVUserOperationLib {
    function pack(
        UserOperation calldata userOp
    ) internal pure returns (bytes memory ret) {
        address sender = UserOperationLib.getSender(userOp);
        uint256 nonce = userOp.nonce;
        bytes32 hashInitCode = calldataKeccak(userOp.initCode);
        bytes32 hashCallData = calldataKeccak(userOp.callData);
        uint256 callGasLimit = userOp.callGasLimit;
        uint256 verificationGasLimit = userOp.verificationGasLimit;
        uint256 preVerificationGas = userOp.preVerificationGas;
        uint256 maxFeePerGas = userOp.maxFeePerGas;
        uint256 maxPriorityFeePerGas = userOp.maxPriorityFeePerGas;

        return
            abi.encode(
                sender,
                nonce,
                hashInitCode,
                hashCallData,
                callGasLimit,
                verificationGasLimit,
                preVerificationGas,
                maxFeePerGas,
                maxPriorityFeePerGas,
                bytes32(0)
            );
    }

    function _internalUserBoostOpHash(
        UserOperation calldata userOp
    ) internal pure returns (bytes32) {
        return keccak256(pack(userOp));
    }

    function boostHash(
        UserOperation calldata userOp,
        IEntryPoint entryPoint
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _internalUserBoostOpHash(userOp),
                    entryPoint,
                    block.chainid
                )
            );
    }
}
