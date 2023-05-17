// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IPaymaster} from "./IPaymaster.sol";
import {UserOperation} from "./UserOperation.sol";

interface IMEVBoostPaymaster is IERC165, IPaymaster {
    event SettleMEV(
        bytes32 indexed userOpHash,
        bytes32 indexed boostUserOpHash,
        address indexed provider,
        address receiver,
        uint256 expectedAmount,
        bool opSucceeded
    );

    struct MEVPayInfo {
        address provider;
        bytes32 boostUserOpHash;
        uint256 amount;
        bytes signature;
    }

    function getMEVPayInfo(
        address provider,
        UserOperation calldata userOp
    ) external view returns (MEVPayInfo memory);

    function getDeposit(address provider) external view returns (uint256);

    function deposit(address provider) external payable;

    function withdrawTo(
        address payable withdrawAddress,
        uint256 amount
    ) external;

    function fetchLegacy() external returns (uint256 legacy);
}
