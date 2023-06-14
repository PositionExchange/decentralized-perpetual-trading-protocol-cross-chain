// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.8;

import "../../interfaces/IFuturXGateway.sol";

contract DptpFuturesGatewayStorage is IFuturXGateway {
    uint256 public pcsId;
    address public pscCrossChainGateway;

    address public vault;
    address public futuresAdapter;
    address public shortsTracker;
    address public weth;
    address public gatewayUtils;
    address public referralRewardTracker;
    address public futurXVoucher;
    address public gatewayStorage;

    mapping(address => bool) public positionKeepers;

    mapping(address => uint256) public override maxGlobalLongSizes;
    mapping(address => uint256) public override maxGlobalShortSizes;

    uint256 public maxTimeDelay;
    uint256 public override executionFee;

    // mapping indexToken with positionManager
    mapping(address => address) public coreManagers;
    // mapping positionManager with indexToken
    mapping(address => address) public indexTokens;

    mapping(bytes32 => address) public latestExecutedCollateral; // For claim fund
    mapping(bytes32 => address) public latestIncreasePendingCollateral;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;

}
