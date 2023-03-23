// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IEntryPoint} from "./interfaces/IEntryPoint.sol";
import {MEVAccount} from "./MEVAccount.sol";

contract MEVAccountFactory {
    MEVAccount public immutable accountImplementation;

    constructor(IEntryPoint _entryPoint) {
        accountImplementation = new MEVAccount(_entryPoint);
    }

    /**
     * create an account, and return its address.
     * returns the address even if the account is already deployed.
     * Note that during UserOperation execution, this method is called only if the account is not deployed.
     * This method returns an existing account address so that entryPoint.getSenderAddress() would work even after account creation
     */
    function createAccount(
        address owner,
        address mevPaymaster,
        uint256 salt
    ) public returns (MEVAccount ret) {
        address addr = getAddress(owner, mevPaymaster, salt);
        uint codeSize = addr.code.length;
        if (codeSize > 0) {
            return MEVAccount(payable(addr));
        }
        ret = MEVAccount(
            payable(
                new ERC1967Proxy{salt: bytes32(salt)}(
                    address(accountImplementation),
                    abi.encodeCall(MEVAccount.initialize, (owner, mevPaymaster))
                )
            )
        );
    }

    /**
     * calculate the counterfactual address of this account as it would be returned by createAccount()
     */
    function getAddress(
        address owner,
        address mevPaymaster,
        uint256 salt
    ) public view returns (address) {
        return
            Create2.computeAddress(
                bytes32(salt),
                keccak256(
                    abi.encodePacked(
                        type(ERC1967Proxy).creationCode,
                        abi.encode(
                            address(accountImplementation),
                            abi.encodeCall(
                                MEVAccount.initialize,
                                (owner, mevPaymaster)
                            )
                        )
                    )
                )
            );
    }
}
