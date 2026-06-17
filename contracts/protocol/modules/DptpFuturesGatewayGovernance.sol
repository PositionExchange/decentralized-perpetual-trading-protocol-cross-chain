// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "./DptpFuturesGatewayStorage.sol";

// Make sure to inherit the contract follow storage layout of DptpFuturesGateway
contract DptpFuturesGatewayGovernance is
    DptpFuturesGatewayStorage,
    PausableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    //******************************************************************************************************************
    // ONLY OWNER FUNCTIONS
    //******************************************************************************************************************

    function setExecutionFee(uint256 _executionFee) external onlyOwner {
        executionFee = _executionFee;
    }

    function setWeth(address _weth) external onlyOwner {
        weth = _weth;
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    function setFuturesAdapter(address _futuresAdapter) external onlyOwner {
        futuresAdapter = _futuresAdapter;
    }

    function setPosiChainId(uint256 _posiChainId) external onlyOwner {
        pcsId = _posiChainId;
    }

    function setPosiChainCrosschainGatewayContract(
        address _address
    ) external onlyOwner {
        pscCrossChainGateway = _address;
    }

    function setPositionKeeper(
        address _address,
        bool _status
    ) external onlyOwner {
        positionKeepers[_address] = _status;
    }

    function setCoreManager(
        address _token,
        address _manager
    ) external onlyOwner {
        coreManagers[_token] = _manager;
        indexTokens[_manager] = _token;
    }

    function setMaxGlobalShortSize(
        address _token,
        uint256 _amount
    ) external onlyOwner {
        maxGlobalShortSizes[_token] = _amount;
    }

    function setMaxGlobalLongSize(
        address _token,
        uint256 _amount
    ) external onlyOwner {
        maxGlobalLongSizes[_token] = _amount;
    }

    function setReferralRewardTracker(address _address) external onlyOwner {
        referralRewardTracker = _address;
    }

    function setFuturXVoucher(address _address) external onlyOwner {
        futurXVoucher = _address;
    }

    function setFuturXGatewayStorage(address _address) external onlyOwner {
        gatewayStorage = _address;
    }

    function setFuturXGatewayUtils(address _address) external onlyOwner {
        gatewayUtils = _address;
    }

    function isPaused() external view returns (bool) {
        return paused();
    }

    function setFeeStrategy(address _feeStrategy) external onlyOwner {
        feeStrategy = _feeStrategy;
    }

    function executeDecreasePosition(
        bytes32 _key,
        uint256 _amountOutAfterFeesUsd,
        uint256 _feeUsd,
        uint256 _entryPrice,
        uint256 _sizeDeltaToken,
        bool _isLong,
        bool _isExecutedFully
    ) external {}
}
