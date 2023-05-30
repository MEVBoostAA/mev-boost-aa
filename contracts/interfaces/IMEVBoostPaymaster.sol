// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IPaymaster} from "./IPaymaster.sol";
import {UserOperation} from "./UserOperation.sol";

interface IMEVBoostPaymaster is IERC165, IPaymaster {
    struct MEVPayInfo {
        address provider;
        bytes32 boostUserOpHash;
        uint256 amount;
        bool requireSuccess;
    }

    event SettleUserOp(
        bytes32 indexed userOpHash,
        bytes32 indexed boostUserOpHash,
        address indexed provider,
        address mevReceiver,
        uint256 actualMevAmount,
        uint256 expectedMEVAmount,
        uint256 totalCost,
        bool isBoostUserOp,
        bool opSucceeded
    );

    function deposit(address provider) external payable;

    function withdrawTo(
        address payable withdrawAddress,
        uint256 amount
    ) external;

    function fetchLegacy() external returns (uint256 legacy);

    function getDeposit(address provider) external view returns (uint256);

    function getMEVPayInfo(
        address provider,
        bool requireSuccess,
        UserOperation calldata userOp
    )
        external
        view
        returns (MEVPayInfo memory mevPayInfo, bool isMEVBoostUserOp);

    function getBoostUserOpHash(
        UserOperation calldata userOp
    ) external view returns (bytes32 boostUserOpHash);

    function getMinMEVAmount(
        UserOperation calldata userOp
    ) external pure returns (uint256 minMEVAmount);
}
