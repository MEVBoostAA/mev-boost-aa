// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccount} from "./IAccount.sol";

interface IMEVBoostAccount is IERC165, IAccount {
    struct MEVConfig {
        uint256 minAmount;
        uint48 selfSponsoredAfter;
    }

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
