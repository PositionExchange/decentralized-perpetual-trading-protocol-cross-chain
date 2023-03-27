// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../protocol/FuturesGateway.sol";

contract FuturesGatewayMock is FuturesGateway {
    function calcNotionalTest(
        address _manager,
        uint256 _price,
        uint256 _quantity
    ) public view returns (uint256) {
        return calcNotional(_manager, _price, _quantity);
    }

    function pipToPriceTest(
        address _manager,
        uint128 _pip
    ) public view returns (uint256) {
        return pipToPrice(_manager, _pip);
    }

    function calcMarginAndFeeTest(
        address _manager,
        uint256 _pQuantity,
        uint128 _pip,
        uint16 _leverage
    ) public view returns (uint256 margin, uint256 fee) {
        return calcMarginAndFee(_manager, _pQuantity, _pip, _leverage);
    }
}
