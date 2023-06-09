// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import {IMEVBoostPaymaster} from "../interfaces/IMEVBoostPaymaster.sol";

// ERC-721
library MEVPayInfoLib {
    // keccak256(bytes("MEVPayInfo(address provider,bytes32 boostUserOpHash,uint256 amount,bool requireSuccess)"))
    bytes32 internal constant MEV_PAY_INFO_TYPE_HASH =
        0xbaf3c30f9598aaef1e73edaec36220004099820792a36355f5dab3ee34addaf3;

    function hash(
        IMEVBoostPaymaster.MEVPayInfo memory mevPayInfo,
        bytes32 domainSeparator
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01", // ERC-191 Header
                    domainSeparator,
                    keccak256(
                        abi.encode(
                            MEV_PAY_INFO_TYPE_HASH,
                            mevPayInfo.provider,
                            mevPayInfo.boostUserOpHash,
                            mevPayInfo.amount,
                            mevPayInfo.requireSuccess
                        )
                    )
                )
            );
    }

    function verify(
        IMEVBoostPaymaster.MEVPayInfo memory mevPayInfo,
        bytes32 domainSeparator,
        bytes memory signature
    ) internal pure returns (bool) {
        bytes32 r;
        bytes32 s;
        uint8 v;
        if (signature.length != 65) {
            return false;
        }

        /* solhint-disable no-inline-assembly */
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
        /* solhint-enable no-inline-assembly */

        if (v < 27) {
            v += 27;
        }
        if (v != 27 && v != 28) {
            return false;
        } else {
            return
                mevPayInfo.provider ==
                ecrecover(hash(mevPayInfo, domainSeparator), v, r, s);
        }
    }
}
