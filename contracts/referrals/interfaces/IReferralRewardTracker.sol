// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IReferralRewardTracker {
    function updateClaimableReward(address _trader, uint256 _fee) external;

    function updateRefereeStatus(
        address _trader,
        address _indexToken,
        uint256 _timestamp,
        uint256 _notional,
        bool _isIncrease
    ) external;
}
