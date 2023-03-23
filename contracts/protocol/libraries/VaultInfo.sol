pragma solidity ^0.8.2;

library VaultInfo {
  // TODO explain struct data for a dev
  struct Data {
    uint128 feeReserves;
    uint128 usdpAmounts;
    uint128 poolAmounts;
    uint128 reservedAmounts;
  }

  function addFees(Data storage self, uint256 feeAmount) internal {
    self.feeReserves = self.feeReserves + uint128(feeAmount);
  }

  function addUsdp(Data storage self, uint256 usdpAmount) internal {
    self.usdpAmounts = self.usdpAmounts + uint128(usdpAmount);
  }

  function subUsdp(Data storage self, uint256 usdpAmount) internal {
    self.usdpAmounts = self.usdpAmounts - uint128(usdpAmount);
  }

  function addPoolAmount(Data storage self, uint256 poolAmounts) internal {
    self.poolAmounts = self.poolAmounts + uint128(poolAmounts);
  }

  function subPoolAmount(Data storage self, uint256 poolAmounts) internal {
    require(poolAmounts <= self.poolAmounts, "Vault: poolAmount exceeded");
    self.poolAmounts = self.poolAmounts - uint128(poolAmounts);
    require(self.reservedAmounts <= self.poolAmounts, "Vault: reserved poolAmount");
  }

  function increaseUsdpAmount(Data storage self, uint256 _amount, uint256 _maxUsdpAmount) internal {
    addUsdp(self, _amount);
    if (_maxUsdpAmount != 0) {
        require(
            self.usdpAmounts <= _maxUsdpAmount,
            "Vault: Max debt amount exceeded"
        );
    }
  }


}

