pragma solidity ^0.8.2;

library PositionInfo {
    struct Data {
        uint256 collateralAmount;
        uint256 reservedAmount;
        uint128 entryBorrowingRates;
    }

    function setEntryBorrowingRates(Data storage _self, uint256 _rate) internal {
        _self.entryBorrowingRates = uint128(_rate);
    }

    function addCollateralAmount(Data storage _self, uint256 _amount) internal {
        _self.collateralAmount = _self.collateralAmount + _amount;
    }

    function subCollateralAmount(Data storage _self, uint256 _amount) internal {
        require(
            _amount <= _self.collateralAmount,
            "Vault: collateral exceeded"
        );
        _self.collateralAmount = _self.collateralAmount - _amount;
    }

    function addReservedAmount(Data storage _self, uint256 _amount) internal {
        _self.reservedAmount = _self.reservedAmount + _amount;
    }

    function subReservedAmount(Data storage _self, uint256 _amount) internal {
        require(
            _amount <= _self.reservedAmount,
            "Vault: reservedAmount exceeded"
        );
        _self.reservedAmount = _self.reservedAmount - _amount;
    }
}
