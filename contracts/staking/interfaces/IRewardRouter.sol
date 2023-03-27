// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

interface IRewardRouter {
    function feePlpTracker() external view returns (address);

    function stakedPlpTracker() external view returns (address);
}
