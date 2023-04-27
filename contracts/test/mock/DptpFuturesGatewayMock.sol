// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.8;

import "../../protocol/DptpFuturesGateway.sol";

contract DptpFuturesGatewayMock is DptpFuturesGateway {
    function calculateMarginFees(
        address[] memory _path,
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta,
        uint256 _amountInToken,
        uint256 _amountInUsd,
        uint256 _leverage,
        bool _isLimitOrder
    ) public returns (uint256) {
        return 0;
    }
}
