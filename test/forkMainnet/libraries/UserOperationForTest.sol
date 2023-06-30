// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import {IEntryPoint} from "../../../contracts/interfaces/IEntryPoint.sol";
import {UserOperation} from "../../../contracts/interfaces/UserOperation.sol";

library UserOperationLibForTest {
    function pack(
        UserOperation memory userOp
    ) internal pure returns (bytes memory ret) {
        address sender = userOp.sender;
        uint256 nonce = userOp.nonce;
        bytes32 hashInitCode = keccak256(userOp.initCode);
        bytes32 hashCallData = keccak256(userOp.callData);
        uint256 callGasLimit = userOp.callGasLimit;
        uint256 verificationGasLimit = userOp.verificationGasLimit;
        uint256 preVerificationGas = userOp.preVerificationGas;
        uint256 maxFeePerGas = userOp.maxFeePerGas;
        uint256 maxPriorityFeePerGas = userOp.maxPriorityFeePerGas;
        bytes32 hashPaymasterAndData = keccak256(userOp.paymasterAndData);

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
                hashPaymasterAndData
            );
    }

    function hash(UserOperation memory userOp) internal pure returns (bytes32) {
        return keccak256(pack(userOp));
    }

    function getUserOpHash(
        UserOperation memory userOp,
        IEntryPoint entryPoint
    ) public view returns (bytes32) {
        return
            keccak256(
                abi.encode(hash(userOp), address(entryPoint), block.chainid)
            );
    }
}
