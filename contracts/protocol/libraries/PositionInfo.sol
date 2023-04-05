pragma solidity ^0.8.2;

library PositionInfo {
    struct Data {
        uint128 collateral;
        uint128 entryBorrowingRates;
    }

    function setEntryBorrowingRates(Data storage _self, uint256 _rate) internal {
        _self.entryBorrowingRates = uint128(_rate);
    }

    function addCollateral(Data storage _self, uint256 _amount) internal {
        _self.collateral = _self.collateral + uint128(_amount);
    }

    function subCollateral(Data storage _self, uint256 _amount) internal {
        require(
            _amount <= _self.collateral,
            "Vault: collateral exceeded"
        );
        _self.collateral = _self.collateral - uint128(_amount);
    }
}
