// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import {IPaymaster} from "./IPaymaster.sol";
import {UserOperation} from "./UserOperation.sol";

interface IMEVBoostPaymaster is IPaymaster {
    event AddMEV(
        address indexed provider,
        address indexed receiver,
        uint256 amount
    );
    event FetchMEV(
        address indexed provider,
        address indexed receiver,
        uint256 amount
    );
    event RefundMEV(
        address indexed provider,
        address indexed receiver,
        uint256 amount
    );

    struct MEVPayInfo {
        address provider;
        bytes32 boostHash;
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

    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
