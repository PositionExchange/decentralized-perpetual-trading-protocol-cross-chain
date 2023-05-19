// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

interface IReferralRewardTracker {
    function updateClaimableReward(address _trader, uint256 _fee) external ;

    function updateRefereeStatus(
        address _trader,
        address _indexToken,
        uint256 _timestamp,
        bool _isIncrease
    ) external;
}
