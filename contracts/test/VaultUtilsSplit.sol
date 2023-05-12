/**
 * @author Musket
 */
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "../interfaces/IVaultUtils.sol";
import "../interfaces/IVault.sol";

contract VaultUtilsSplit is IVaultUtils, Initializable {
    using SafeMath for uint256;

    IVault public vault;

    uint256 public constant BORROWING_RATE_PRECISION = 1000000;

    function initialize(IVault _vault) public initializer {
        vault = _vault;
    }

    function getBuyUsdgFeeBasisPoints(
        address _token,
        uint256 _usdgAmount
    ) public view override returns (uint256) {
        return
            getFeeBasisPoints(
                _token,
                _usdgAmount,
                vault.mintBurnFeeBasisPoints(),
                vault.taxBasisPoints(),
                true
            );
    }

    function getSellUsdgFeeBasisPoints(
        address _token,
        uint256 _usdgAmount
    ) public view override returns (uint256) {
        return
            getFeeBasisPoints(
                _token,
                _usdgAmount,
                vault.mintBurnFeeBasisPoints(),
                vault.taxBasisPoints(),
                false
            );
    }

    function isStableSwap(
        address _tokenIn,
        address _tokenOut
    ) public view returns (bool) {
        bool isStableSwap = vault.isStableToken(_tokenIn) &&
            vault.isStableToken(_tokenOut);
        return isStableSwap;
    }

    function baseBps(bool isStableSwap) public view  returns (uint256) {
        uint256 baseBps = isStableSwap
            ? vault.stableSwapFeeBasisPoints()
            : vault.swapFeeBasisPoints();
        return baseBps;
    }

    function taxBps(bool isStableSwap) public view  returns (uint256) {
        uint256 taxBps = isStableSwap
            ? vault.stableTaxBasisPoints()
            : vault.taxBasisPoints();
        return taxBps;
    }

    function getSwapFeeBasisPoints(
        address _tokenIn,
        address _tokenOut,
        uint256 _usdgAmount
    ) public view override returns (uint256) {
        bool isStableSwap = isStableSwap(_tokenIn, _tokenOut);
        //        vault.isStableToken(_tokenIn) &&
        //            vault.isStableToken(_tokenOut);

        uint256 baseBps = baseBps(isStableSwap);
        //        isStableSwap
        //            ? vault.stableSwapFeeBasisPoints()
        //            : vault.swapFeeBasisPoints();

        uint256 taxBps = taxBps(isStableSwap);
        //        isStableSwap
        //            ? vault.stableTaxBasisPoints()
        //            : vault.taxBasisPoints();
        uint256 feesBasisPoints0 = getFeeBasisPoints(
            _tokenIn,
            _usdgAmount,
            baseBps,
            taxBps,
            true
        );
        uint256 feesBasisPoints1 = getFeeBasisPoints(
            _tokenOut,
            _usdgAmount,
            baseBps,
            taxBps,
            false
        );
        // use the higher of the two fee basis points
        return
            feesBasisPoints0 > feesBasisPoints1
                ? feesBasisPoints0
                : feesBasisPoints1;
    }

    function initAmountAndNextAmount(
        address _token,
        uint256 _usdgDelta,
        bool _increment
    ) public view returns (uint256 initialAmount, uint256 nextAmount) {
        uint256 initialAmount = vault.usdpAmount(_token);
        uint256 nextAmount = initialAmount.add(_usdgDelta);
        if (!_increment) {
            nextAmount = _usdgDelta > initialAmount
                ? 0
                : initialAmount.sub(_usdgDelta);
        }

        return (initialAmount, nextAmount);
    }

    function targetAmount(address _token) public view returns (uint256) {
        return vault.getTargetUsdpAmount(_token);
    }

    function initialDiff(
        uint256 initialAmount,
        uint256 targetAmount
    ) public view returns (uint256) {
        uint256 initialDiff = initialAmount > targetAmount
            ? initialAmount.sub(targetAmount)
            : targetAmount.sub(initialAmount);
        return initialDiff;
    }

    function nextDiff(
        uint256 nextAmount,
        uint256 targetAmount
    ) public view returns (uint256) {
        uint256 nextDiff = nextAmount > targetAmount
            ? nextAmount.sub(targetAmount)
            : targetAmount.sub(nextAmount);

        return nextDiff;
    }

    function averageDiff(
        uint256 initialDiff,
        uint256 nextDiff
    ) public view returns (uint256) {
        uint256 averageDiff = initialDiff.add(nextDiff).div(2);
        return averageDiff;
    }

    function taxBps(
        uint256 _taxBasisPoints,
        uint256 averageDiff,
        uint256 targetAmount
    ) public view returns (uint256) {
        uint256 taxBps = _taxBasisPoints.mul(averageDiff).div(targetAmount);
        return taxBps;
    }

    // cases to consider
    // 1. initialAmount is far from targetAmount, action increases balance slightly => high rebate
    // 2. initialAmount is far from targetAmount, action increases balance largely => high rebate
    // 3. initialAmount is close to targetAmount, action increases balance slightly => low rebate
    // 4. initialAmount is far from targetAmount, action reduces balance slightly => high tax
    // 5. initialAmount is far from targetAmount, action reduces balance largely => high tax
    // 6. initialAmount is close to targetAmount, action reduces balance largely => low tax
    // 7. initialAmount is above targetAmount, nextAmount is below targetAmount and vice versa
    // 8. a large swap should have similar fees as the same trade split into multiple smaller swaps
    function getFeeBasisPoints(
        address _token,
        uint256 _usdgDelta,
        uint256 _feeBasisPoints,
        uint256 _taxBasisPoints,
        bool _increment
    ) public view override returns (uint256) {
        if (!vault.hasDynamicFees()) {
            return _feeBasisPoints;
        }

        (uint256 initialAmount, uint256 nextAmount) = initAmountAndNextAmount(
            _token,
            _usdgDelta,
            _increment
        );

        uint256 targetAmount = targetAmount(_token);

        if (targetAmount == 0) {
            return _feeBasisPoints;
        }

        uint256 initialDiff = initialDiff(initialAmount, targetAmount);

        //        uint256 initialDiff = initialAmount > targetAmount
        //            ? initialAmount.sub(targetAmount)
        //            : targetAmount.sub(initialAmount);

        uint256 nextDiff = nextDiff(nextAmount, targetAmount);

        //        uint256 nextDiff = nextAmount > targetAmount
        //            ? nextAmount.sub(targetAmount)
        //            : targetAmount.sub(nextAmount);

        // action improves relative asset balance

        if (nextDiff < initialDiff) {
            uint256 rebateBps = _taxBasisPoints.mul(initialDiff).div(
                targetAmount
            );
            return
                rebateBps > _feeBasisPoints
                    ? 0
                    : _feeBasisPoints.sub(rebateBps);
        }

        uint256 averageDiff = averageDiff(initialDiff, nextDiff); // initialDiff.add(nextDiff).div(2);
        if (averageDiff > targetAmount) {
            averageDiff = targetAmount;
        }
        uint256 taxBps = taxBps(_taxBasisPoints, averageDiff, targetAmount); //_taxBasisPoints.mul(averageDiff).div(targetAmount);
        return _feeBasisPoints.add(taxBps);
    }

    function getBorrowingFee(
        address _collateralToken,
        uint256 _size,
        uint256 _entryBorrowingRate
    ) public view override returns (uint256) {
        if (_size == 0) {
            return 0;
        }
        uint256 borrowingRate = vault
            .cumulativeBorrowingRates(_collateralToken)
            .sub(_entryBorrowingRate);
        if (borrowingRate == 0) {
            return 0;
        }

        return _size.mul(borrowingRate).div(BORROWING_RATE_PRECISION);
    }

    function setVault(address _vault) external {
        vault = IVault(_vault);
    }

    function updateCumulativeBorrowingRate(
        address /* _collateralToken */,
        address /* _indexToken */
    ) public override returns (bool) {
        return true;
    }
}
