// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IFullyDptpFuturesGateway {
    function coreManagers(address) external view returns (address);

    function createAddCollateralRequest(
        address[] memory _path,
        address _indexToken,
        uint256 _amountInToken,
        bool _isLong
    ) external payable;

    function createCancelOrderRequest(
        bytes32 _key,
        uint256 _orderIdx,
        bool _isReduce
    ) external payable;

    function createDecreaseOrderRequest(
        address[] memory _path,
        address _indexToken,
        uint256 _pip,
        uint256 _sizeDeltaToken,
        bool _isLong
    ) external payable returns (bytes32);

    function createDecreasePositionRequest(
        address[] memory _path,
        address _indexToken,
        uint256 _sizeDeltaToken,
        bool _isLong
    ) external payable returns (bytes32);

    function createIncreaseOrderRequest(
        address[] memory _path,
        address _indexToken,
        uint256 _amountInUsd,
        uint256 _pip,
        uint256 _sizeDeltaToken,
        uint16 _leverage,
        bool _isLong,
        uint256 _voucherId
    ) external payable returns (bytes32);

    function createIncreasePositionRequest(
        address[] memory _path,
        address _indexToken,
        uint256 _amountInUsd,
        uint256 _sizeDeltaToken,
        uint16 _leverage,
        bool _isLong,
        uint256 _voucherId
    ) external payable returns (bytes32);

    function createRemoveCollateralRequest(
        address[] memory _path,
        address _indexToken,
        uint256 _amountOutUsd,
        bool _isLong
    ) external;

    function executeAddCollateral(bytes32 _key) external;

    function executeCancelIncreaseOrder(
        bytes32 _key,
        bool _isReduce,
        uint256 _amountOutUsd,
        uint256 _sizeDeltaToken,
        uint256 _entryPrice,
        bool _isLong
    ) external;

    function executeClaimFund(
        address _manager,
        address _account,
        bool _isLong,
        uint256 _amountOutUsd
    ) external;

    function executeDecreasePosition(
        bytes32 _key,
        uint256 _amountOutAfterFeesUsd,
        uint256 _feeUsd,
        uint256 _entryPrice,
        uint256 _sizeDeltaToken,
        bool _isLong,
        bool _isExecutedFully
    ) external;

    function executeGovFunction(bytes memory _data) external;

    function executeIncreasePosition(
        bytes32 _key,
        uint256 _entryPrice,
        uint256 _sizeDeltaInToken,
        bool _isLong,
        bool _isExecutedFully,
        uint16 _leverage
    ) external;

    function executeRemoveCollateral(
        bytes32 _key,
        uint256 _amountOutUsd
    ) external;

    function executionFee() external view returns (uint256);

    function futurXVoucher() external view returns (address);

    function futuresAdapter() external view returns (address);

    function gatewayStorage() external view returns (address);

    function gatewayUtils() external view returns (address);

    function getPositionKey(
        address _account,
        address _indexToken,
        bool _isLong
    ) external pure returns (bytes32);

    function indexTokens(address) external view returns (address);

    function initialize(
        uint256 _pcsId,
        address _pscCrossChainGateway,
        address _futuresAdapter,
        address _vault,
        address _weth,
        address _gatewayUtils,
        address _gatewayStorage,
        uint256 _executionFee
    ) external;

    function isPaused() external view returns (bool);

    function latestExecutedCollateral(bytes32) external view returns (address);

    function latestIncreasePendingCollateral(
        bytes32
    ) external view returns (address);

    function liquidatePosition(
        address _trader,
        address _collateralToken,
        address _indexToken,
        uint256 _positionSize,
        uint256 _positionMargin,
        bool _isLong
    ) external;

    function maxGlobalLongSizes(address) external view returns (uint256);

    function maxGlobalShortSizes(address) external view returns (uint256);

    function maxTimeDelay() external view returns (uint256);

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) external returns (bytes4);

    function owner() external view returns (address);

    function paused() external view returns (bool);

    function pcsId() external view returns (uint256);

    function positionKeepers(address) external view returns (bool);

    function pscCrossChainGateway() external view returns (address);

    function referralRewardTracker() external view returns (address);

    function refund(bytes32 _key, uint8 _method) external payable;

    function renounceOwnership() external;

    function setGovernanceLogic(address _newGovernanceLogic) external;

    function shortsTracker() external view returns (address);

    function transferOwnership(address newOwner) external;

    function vault() external view returns (address);

    function weth() external view returns (address);

    function withdraw(address _recipient) external;
}

// THIS FILE WAS AUTOGENERATED FROM THE FOLLOWING ABI JSON:
/*
[{"anonymous":false,"inputs":[{"indexed":false,"internalType":"bytes32","name":"requestKey","type":"bytes32"},{"indexed":false,"internalType":"address","name":"account","type":"address"},{"indexed":false,"internalType":"address","name":"paidToken","type":"address"},{"indexed":false,"internalType":"uint256","name":"tokenAmount","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"usdAmount","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"swapFee","type":"uint256"}],"name":"CollateralAddCreated","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"account","type":"address"},{"indexed":false,"internalType":"address","name":"token","type":"address"},{"indexed":false,"internalType":"uint256","name":"tokenAmount","type":"uint256"}],"name":"CollateralAddedExecuted","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"bytes32","name":"requestKey","type":"bytes32"},{"indexed":false,"internalType":"address","name":"account","type":"address"},{"indexed":false,"internalType":"address","name":"collateralToken","type":"address"},{"indexed":false,"internalType":"uint256","name":"tokenAmount","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"usdAmount","type":"uint256"}],"name":"CollateralRemoveCreated","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"account","type":"address"},{"indexed":false,"internalType":"address","name":"token","type":"address"},{"indexed":false,"internalType":"uint256","name":"tokenAmount","type":"uint256"}],"name":"CollateralRemoveExecuted","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint256","name":"amountInBeforeFeeToken","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"positionFee","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"borrowFee","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"swapFee","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"timestamp","type":"uint256"}],"name":"CollectFees","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"account","type":"address"},{"indexed":false,"internalType":"address[]","name":"path","type":"address[]"},{"indexed":false,"internalType":"address","name":"indexToken","type":"address"},{"indexed":false,"internalType":"uint256","name":"pip","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"sizeDeltaToken","type":"uint256"},{"indexed":false,"internalType":"bool","name":"isLong","type":"bool"},{"indexed":false,"internalType":"uint256","name":"executionFee","type":"uint256"},{"indexed":false,"internalType":"bytes32","name":"key","type":"bytes32"},{"indexed":false,"internalType":"uint256","name":"blockNumber","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"blockTime","type":"uint256"}],"name":"CreateDecreasePosition","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"account","type":"address"},{"indexed":false,"internalType":"address[]","name":"path","type":"address[]"},{"indexed":false,"internalType":"address","name":"indexToken","type":"address"},{"indexed":false,"internalType":"uint256","name":"amountInToken","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"sizeDelta","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"pip","type":"uint256"},{"indexed":false,"internalType":"bool","name":"isLong","type":"bool"},{"indexed":false,"internalType":"uint256","name":"executionFee","type":"uint256"},{"indexed":false,"internalType":"bytes32","name":"key","type":"bytes32"}],"name":"CreateIncreasePosition","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"account","type":"address"},{"indexed":false,"internalType":"address[]","name":"path","type":"address[]"},{"indexed":false,"internalType":"address","name":"indexToken","type":"address"},{"indexed":false,"internalType":"uint256","name":"sizeDelta","type":"uint256"},{"indexed":false,"internalType":"bool","name":"isLong","type":"bool"},{"indexed":false,"internalType":"uint256","name":"executionFee","type":"uint256"}],"name":"ExecuteDecreasePosition","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"account","type":"address"},{"indexed":false,"internalType":"address[]","name":"path","type":"address[]"},{"indexed":false,"internalType":"address","name":"indexToken","type":"address"},{"indexed":false,"internalType":"uint256","name":"amountInToken","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amountInUsd","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"sizeDelta","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"entryPrice","type":"uint256"},{"indexed":false,"internalType":"bool","name":"isLong","type":"bool"},{"indexed":false,"internalType":"uint256","name":"feeUsd","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"voucherId","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"timestamp","type":"uint256"}],"name":"ExecuteIncreasePosition","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"_prev","type":"address"},{"indexed":false,"internalType":"address","name":"_new","type":"address"}],"name":"GovernanceLogicChanged","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint8","name":"version","type":"uint8"}],"name":"Initialized","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"previousOwner","type":"address"},{"indexed":true,"internalType":"address","name":"newOwner","type":"address"}],"name":"OwnershipTransferred","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"account","type":"address"}],"name":"Paused","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"account","type":"address"}],"name":"Unpaused","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"account","type":"address"},{"indexed":false,"internalType":"uint256","name":"voucherId","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"discountAmount","type":"uint256"}],"name":"VoucherApplied","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint256","name":"voucherId","type":"uint256"},{"indexed":false,"internalType":"address","name":"account","type":"address"}],"name":"VoucherRefunded","type":"event"},{"stateMutability":"payable","type":"fallback"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"coreManagers","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address[]","name":"_path","type":"address[]"},{"internalType":"address","name":"_indexToken","type":"address"},{"internalType":"uint256","name":"_amountInToken","type":"uint256"},{"internalType":"bool","name":"_isLong","type":"bool"}],"name":"createAddCollateralRequest","outputs":[],"stateMutability":"payable","type":"function"},{"inputs":[{"internalType":"bytes32","name":"_key","type":"bytes32"},{"internalType":"uint256","name":"_orderIdx","type":"uint256"},{"internalType":"bool","name":"_isReduce","type":"bool"}],"name":"createCancelOrderRequest","outputs":[],"stateMutability":"payable","type":"function"},{"inputs":[{"internalType":"address[]","name":"_path","type":"address[]"},{"internalType":"address","name":"_indexToken","type":"address"},{"internalType":"uint256","name":"_pip","type":"uint256"},{"internalType":"uint256","name":"_sizeDeltaToken","type":"uint256"},{"internalType":"bool","name":"_isLong","type":"bool"}],"name":"createDecreaseOrderRequest","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"payable","type":"function"},{"inputs":[{"internalType":"address[]","name":"_path","type":"address[]"},{"internalType":"address","name":"_indexToken","type":"address"},{"internalType":"uint256","name":"_sizeDeltaToken","type":"uint256"},{"internalType":"bool","name":"_isLong","type":"bool"}],"name":"createDecreasePositionRequest","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"payable","type":"function"},{"inputs":[{"internalType":"address[]","name":"_path","type":"address[]"},{"internalType":"address","name":"_indexToken","type":"address"},{"internalType":"uint256","name":"_amountInUsd","type":"uint256"},{"internalType":"uint256","name":"_pip","type":"uint256"},{"internalType":"uint256","name":"_sizeDeltaToken","type":"uint256"},{"internalType":"uint16","name":"_leverage","type":"uint16"},{"internalType":"bool","name":"_isLong","type":"bool"},{"internalType":"uint256","name":"_voucherId","type":"uint256"}],"name":"createIncreaseOrderRequest","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"payable","type":"function"},{"inputs":[{"internalType":"address[]","name":"_path","type":"address[]"},{"internalType":"address","name":"_indexToken","type":"address"},{"internalType":"uint256","name":"_amountInUsd","type":"uint256"},{"internalType":"uint256","name":"_sizeDeltaToken","type":"uint256"},{"internalType":"uint16","name":"_leverage","type":"uint16"},{"internalType":"bool","name":"_isLong","type":"bool"},{"internalType":"uint256","name":"_voucherId","type":"uint256"}],"name":"createIncreasePositionRequest","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"payable","type":"function"},{"inputs":[{"internalType":"address[]","name":"_path","type":"address[]"},{"internalType":"address","name":"_indexToken","type":"address"},{"internalType":"uint256","name":"_amountOutUsd","type":"uint256"},{"internalType":"bool","name":"_isLong","type":"bool"}],"name":"createRemoveCollateralRequest","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"bytes32","name":"_key","type":"bytes32"}],"name":"executeAddCollateral","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"bytes32","name":"_key","type":"bytes32"},{"internalType":"bool","name":"_isReduce","type":"bool"},{"internalType":"uint256","name":"_amountOutUsd","type":"uint256"},{"internalType":"uint256","name":"_sizeDeltaToken","type":"uint256"},{"internalType":"uint256","name":"_entryPrice","type":"uint256"},{"internalType":"bool","name":"_isLong","type":"bool"}],"name":"executeCancelIncreaseOrder","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"_manager","type":"address"},{"internalType":"address","name":"_account","type":"address"},{"internalType":"bool","name":"_isLong","type":"bool"},{"internalType":"uint256","name":"_amountOutUsd","type":"uint256"}],"name":"executeClaimFund","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"bytes32","name":"_key","type":"bytes32"},{"internalType":"uint256","name":"_amountOutAfterFeesUsd","type":"uint256"},{"internalType":"uint256","name":"_feeUsd","type":"uint256"},{"internalType":"uint256","name":"_entryPrice","type":"uint256"},{"internalType":"uint256","name":"_sizeDeltaToken","type":"uint256"},{"internalType":"bool","name":"_isLong","type":"bool"},{"internalType":"bool","name":"_isExecutedFully","type":"bool"}],"name":"executeDecreasePosition","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"bytes","name":"_data","type":"bytes"}],"name":"executeGovFunction","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"bytes32","name":"_key","type":"bytes32"},{"internalType":"uint256","name":"_entryPrice","type":"uint256"},{"internalType":"uint256","name":"_sizeDeltaInToken","type":"uint256"},{"internalType":"bool","name":"_isLong","type":"bool"},{"internalType":"bool","name":"_isExecutedFully","type":"bool"},{"internalType":"uint16","name":"_leverage","type":"uint16"}],"name":"executeIncreasePosition","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"bytes32","name":"_key","type":"bytes32"},{"internalType":"uint256","name":"_amountOutUsd","type":"uint256"}],"name":"executeRemoveCollateral","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"executionFee","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"futurXVoucher","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"futuresAdapter","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"gatewayStorage","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"gatewayUtils","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"_account","type":"address"},{"internalType":"address","name":"_indexToken","type":"address"},{"internalType":"bool","name":"_isLong","type":"bool"}],"name":"getPositionKey","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"pure","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"indexTokens","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"_pcsId","type":"uint256"},{"internalType":"address","name":"_pscCrossChainGateway","type":"address"},{"internalType":"address","name":"_futuresAdapter","type":"address"},{"internalType":"address","name":"_vault","type":"address"},{"internalType":"address","name":"_weth","type":"address"},{"internalType":"address","name":"_gatewayUtils","type":"address"},{"internalType":"address","name":"_gatewayStorage","type":"address"},{"internalType":"uint256","name":"_executionFee","type":"uint256"}],"name":"initialize","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"isPaused","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"name":"latestExecutedCollateral","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"name":"latestIncreasePendingCollateral","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"_trader","type":"address"},{"internalType":"address","name":"_collateralToken","type":"address"},{"internalType":"address","name":"_indexToken","type":"address"},{"internalType":"uint256","name":"_positionSize","type":"uint256"},{"internalType":"uint256","name":"_positionMargin","type":"uint256"},{"internalType":"bool","name":"_isLong","type":"bool"}],"name":"liquidatePosition","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"maxGlobalLongSizes","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"maxGlobalShortSizes","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"maxTimeDelay","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"},{"internalType":"address","name":"","type":"address"},{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"bytes","name":"","type":"bytes"}],"name":"onERC721Received","outputs":[{"internalType":"bytes4","name":"","type":"bytes4"}],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"owner","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"paused","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"pcsId","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"positionKeepers","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"pscCrossChainGateway","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"referralRewardTracker","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"bytes32","name":"_key","type":"bytes32"},{"internalType":"enum CrosscallMethod.Method","name":"_method","type":"uint8"}],"name":"refund","outputs":[],"stateMutability":"payable","type":"function"},{"inputs":[],"name":"renounceOwnership","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"_newGovernanceLogic","type":"address"}],"name":"setGovernanceLogic","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"shortsTracker","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"newOwner","type":"address"}],"name":"transferOwnership","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"vault","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"weth","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"_recipient","type":"address"}],"name":"withdraw","outputs":[],"stateMutability":"nonpayable","type":"function"},{"stateMutability":"payable","type":"receive"}]
*/
