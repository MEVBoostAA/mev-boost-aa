// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;
import {IAccount} from "./IAccount.sol";

struct MEVConfig {
    uint256 minAmount;
    uint48 selfSponsoredAfter;
}

interface IMEVBoostAccount is IAccount {
    function boostExecute(
        MEVConfig calldata mevConfig,
        address dest,
        uint256 value,
        bytes calldata func
    ) external;

    function boostExecuteBatch(
        MEVConfig calldata mevConfig,
        address[] calldata dest,
        uint256[] calldata value,
        bytes[] calldata func
    ) external;
}
