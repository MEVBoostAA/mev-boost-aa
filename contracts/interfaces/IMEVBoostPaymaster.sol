// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;
import {IPaymaster} from "./IPaymaster.sol";
import {UserOperation} from "./UserOperation.sol";

struct MEVPayInfo {
    address provider;
    bytes32 boostUserOpHash;
    uint256 amount;
}

interface IMEVBoostPaymaster is IPaymaster {
    event SettleMEV(
        bytes32 indexed userOpHash,
        bytes32 indexed boostUserOpHash,
        address indexed provider,
        address receiver,
        uint256 expectedAmount,
        bool opSucceeded
    );

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
