pragma solidity ^0.8.9;

import {Errors} from "./helpers/Errors.sol";

library PositionInfo {
    struct Data {
        uint256 reservedAmount;
        uint128 entryBorrowingRates;
        address collateralToken;
    }

    function setEntryBorrowingRates(
        Data storage _self,
        uint256 _rate
    ) internal {
        _self.entryBorrowingRates = uint128(_rate);
    }

    function addReservedAmount(Data storage _self, uint256 _amount) internal {
        _self.reservedAmount = _self.reservedAmount + _amount;
    }

    function subReservedAmount(
        Data storage _self,
        uint256 _amount
    ) internal returns (uint256) {
        // Position already decreased on process chain -> no point in reverting
        // require(
        //    _amount <= _self.reservedAmount,
        //    "Vault: reservedAmount exceeded"
        // );
        if (_amount >= _self.reservedAmount) {
            _amount = _self.reservedAmount;
        }
        _self.reservedAmount = _self.reservedAmount - _amount;
        return _amount;
    }

    function setCollateralToken(Data storage _self, address _token) internal {
        if (_self.collateralToken == address(0)) {
            _self.collateralToken = _token;
            return;
        }
        require(
            _self.collateralToken == _token,
            Errors.FGWU_INVALID_POSITION_COLLATERAL
        );
    }
}
