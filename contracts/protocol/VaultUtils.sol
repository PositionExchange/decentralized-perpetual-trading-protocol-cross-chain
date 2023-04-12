pragma solidity ^0.8.2;

import "../interfaces/IVaultUtils.sol";
import "../interfaces/IVault.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract VaultUtils is IVaultUtils, Initializable {
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

    function getSwapFeeBasisPoints(
        address _tokenIn,
        address _tokenOut,
        uint256 _usdgAmount
    ) public view override returns (uint256) {
        bool isStableSwap = vault.isStableToken(_tokenIn) &&
            vault.isStableToken(_tokenOut);
        uint256 baseBps = isStableSwap
            ? vault.stableSwapFeeBasisPoints()
            : vault.swapFeeBasisPoints();
        uint256 taxBps = isStableSwap
            ? vault.stableTaxBasisPoints()
            : vault.taxBasisPoints();
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
        uint256 _feeBasisPoints, // 0.3%
        uint256 _taxBasisPoints, // 0.5%
        bool _increment
    ) public view override returns (uint256) {
        if (!vault.hasDynamicFees()) {
            return _feeBasisPoints;
        }

        uint256 initialAmount = vault.usdpAmount(_token); // return amount of pool usdp

        uint256 nextAmount = initialAmount.add(_usdgDelta); // get the next amount after deposit the delta amount for buy
        if (!_increment) { // for sell
            nextAmount = _usdgDelta > initialAmount
                ? 0
                : initialAmount.sub(_usdgDelta);
        }

        uint256 targetAmount = vault.getTargetUsdpAmount(_token);
        if (targetAmount == 0) {
            return _feeBasisPoints;
        }

        // get the delta of initialAmount and targetAmount
        uint256 initialDiff = initialAmount > targetAmount
            ? initialAmount.sub(targetAmount)
            : targetAmount.sub(initialAmount);
        // initialAmount = 100
        // targetAmount = 90
        // ===> initialDiff = 10


        // nextAmount = 110
        // targetAmount = 90
        // ===> nextDiff = 20
        uint256 nextDiff = nextAmount > targetAmount
            ? nextAmount.sub(targetAmount)
            : targetAmount.sub(nextAmount);

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

        // (initialDiff + nextDiff) / 2 =  (10+20)/2 = 15 = averageDiff
        uint256 averageDiff = initialDiff.add(nextDiff).div(2);
        if (averageDiff > targetAmount) {
            averageDiff = targetAmount;
        }
        // 50 * 15 / 90
        uint256 taxBps = _taxBasisPoints.mul(averageDiff).div(targetAmount);
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
}
