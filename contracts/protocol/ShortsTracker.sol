// SPDX-License-Identifier: MIT

pragma solidity ^0.8.8;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../interfaces/IShortsTracker.sol";
import "../access/Governable.sol";
import "../interfaces/IVault.sol";

contract ShortsTracker is Governable, IShortsTracker {
    using SafeMath for uint256;

    event GlobalShortDataUpdated(
        address indexed token,
        uint256 globalShortSize,
        uint256 globalShortAveragePrice
    );

    uint256 public constant MAX_INT256 = uint256(type(int256).max);

    IVault public vault;

    mapping(address => bool) public isHandler;
    mapping(bytes32 => bytes32) public data;

    mapping(address => uint256) public override globalShortAveragePrices;
    bool public override isGlobalShortDataReady;

    modifier onlyHandler() {
        require(isHandler[msg.sender], "ShortsTracker: forbidden");
        _;
    }

    constructor(address _vault) public {
        vault = IVault(_vault);
    }

    function setHandler(address _handler, bool _isActive) external onlyGov {
        require(_handler != address(0), "ShortsTracker: invalid _handler");
        isHandler[_handler] = _isActive;
    }

    function setIsGlobalShortDataReady(bool value) external override onlyGov {
        isGlobalShortDataReady = value;
    }

    function updateGlobalShortData(
        address _indexToken,
        uint256 _sizeDelta,
        uint256 _markPrice,
        bool _isIncrease
    ) external onlyHandler {
        if (!isGlobalShortDataReady) {
            return;
        }

        (
            uint256 globalShortSize,
            uint256 globalShortAveragePrice
        ) = getNextGlobalShortData(
                _indexToken,
                _markPrice,
                _sizeDelta,
                _isIncrease
            );
        _setGlobalShortAveragePrice(_indexToken, globalShortAveragePrice);

        emit GlobalShortDataUpdated(
            _indexToken,
            globalShortSize,
            globalShortAveragePrice
        );
    }

    function getGlobalShortDelta(address _token)
        public
        view
        returns (bool, uint256)
    {
        uint256 size = vault.globalShortSizes(_token);
        uint256 averagePrice = globalShortAveragePrices[_token];
        if (size == 0) {
            return (false, 0);
        }

        uint256 nextPrice = IVault(vault).getMaxPrice(_token);
        uint256 priceDelta = averagePrice > nextPrice
            ? averagePrice.sub(nextPrice)
            : nextPrice.sub(averagePrice);
        uint256 delta = size.mul(priceDelta).div(averagePrice);
        bool hasProfit = averagePrice > nextPrice;

        return (hasProfit, delta);
    }

    function setInitData(
        address[] calldata _tokens,
        uint256[] calldata _averagePrices
    ) external override onlyGov {
        require(!isGlobalShortDataReady, "ShortsTracker: already migrated");

        for (uint256 i = 0; i < _tokens.length; i++) {
            globalShortAveragePrices[_tokens[i]] = _averagePrices[i];
        }
        isGlobalShortDataReady = true;
    }

    function getNextGlobalShortData(
        address _indexToken,
        uint256 _nextPrice,
        uint256 _sizeDelta,
        bool _isIncrease
    ) public view override returns (uint256, uint256) {
        // TODO: Need realisedPnl
        int256 realisedPnl = 0;
        uint256 averagePrice = globalShortAveragePrices[_indexToken];
        uint256 priceDelta = averagePrice > _nextPrice
            ? averagePrice.sub(_nextPrice)
            : _nextPrice.sub(averagePrice);

        uint256 nextSize;
        uint256 delta;
        // avoid stack to deep
        {
            uint256 size = vault.globalShortSizes(_indexToken);
            nextSize = _isIncrease
                ? size.add(_sizeDelta)
                : size.sub(_sizeDelta);

            if (nextSize == 0) {
                return (0, 0);
            }

            if (averagePrice == 0) {
                return (nextSize, _nextPrice);
            }

            delta = size.mul(priceDelta).div(averagePrice);
        }

        uint256 nextAveragePrice = _getNextGlobalAveragePrice(
            averagePrice,
            _nextPrice,
            nextSize,
            delta,
            realisedPnl
        );

        return (nextSize, nextAveragePrice);
    }

    function _getNextGlobalAveragePrice(
        uint256 _averagePrice,
        uint256 _nextPrice,
        uint256 _nextSize,
        uint256 _delta,
        int256 _realisedPnl
    ) internal pure returns (uint256) {
        (bool hasProfit, uint256 nextDelta) = _getNextDelta(
            _delta,
            _averagePrice,
            _nextPrice,
            _realisedPnl
        );

        uint256 nextAveragePrice = _nextPrice.mul(_nextSize).div(
            hasProfit ? _nextSize.sub(nextDelta) : _nextSize.add(nextDelta)
        );

        return nextAveragePrice;
    }

    function _getNextDelta(
        uint256 _delta,
        uint256 _averagePrice,
        uint256 _nextPrice,
        int256 _realisedPnl
    ) internal pure returns (bool, uint256) {
        // global delta 10000, realised pnl 1000 => new pnl 9000
        // global delta 10000, realised pnl -1000 => new pnl 11000
        // global delta -10000, realised pnl 1000 => new pnl -11000
        // global delta -10000, realised pnl -1000 => new pnl -9000
        // global delta 10000, realised pnl 11000 => new pnl -1000 (flips sign)
        // global delta -10000, realised pnl -11000 => new pnl 1000 (flips sign)

        bool hasProfit = _averagePrice > _nextPrice;
        if (hasProfit) {
            // global shorts pnl is positive
            if (_realisedPnl > 0) {
                if (uint256(_realisedPnl) > _delta) {
                    _delta = uint256(_realisedPnl).sub(_delta);
                    hasProfit = false;
                } else {
                    _delta = _delta.sub(uint256(_realisedPnl));
                }
            } else {
                _delta = _delta.add(uint256(-_realisedPnl));
            }

            return (hasProfit, _delta);
        }

        if (_realisedPnl > 0) {
            _delta = _delta.add(uint256(_realisedPnl));
        } else {
            if (uint256(-_realisedPnl) > _delta) {
                _delta = uint256(-_realisedPnl).sub(_delta);
                hasProfit = true;
            } else {
                _delta = _delta.sub(uint256(-_realisedPnl));
            }
        }
        return (hasProfit, _delta);
    }

    function _setGlobalShortAveragePrice(address _token, uint256 _averagePrice)
        internal
    {
        globalShortAveragePrices[_token] = _averagePrice;
    }
}
