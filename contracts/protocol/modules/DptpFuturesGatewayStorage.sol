// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "../../interfaces/IFuturXGateway.sol";

abstract contract DptpFuturesGatewayStorage is IFuturXGateway {
    uint256 public override pcsId;
    address public override pscCrossChainGateway;

    address public vault;
    address public override futuresAdapter;
    address public shortsTracker;
    address public weth;
    address public gatewayUtils;
    address public referralRewardTracker;
    address public futurXVoucher;
    address public override gatewayStorage;

    mapping(address => bool) public override positionKeepers;

    mapping(address => uint256) public override maxGlobalLongSizes;
    mapping(address => uint256) public override maxGlobalShortSizes;

    uint256 public maxTimeDelay;
    uint256 public override executionFee;

    // mapping indexToken with positionManager
    mapping(address => address) public override coreManagers;
    // mapping positionManager with indexToken
    mapping(address => address) public override indexTokens;

    mapping(bytes32 => address) public latestExecutedCollateral; // For claim fund
    mapping(bytes32 => address) public latestIncreasePendingCollateral;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
    address public override feeStrategy;
}
