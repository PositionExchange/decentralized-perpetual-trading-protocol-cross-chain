/**
 * @author Musket
 */
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../interfaces/IUniswapV2Router.sol";


contract BBB is OwnableUpgradeable
{

    IUniswapV2Router02 public swapRouter;
    IERC20 public posi;
    address public deadAddress = 0x000000000000000000000000000000000000dEaD;
    uint256 public startEpoch;
    uint256 public endEpoch;
    uint256 public lastTimeBBB;
    uint256 public duration;
    uint256 public amountETH;
    uint256 public amountEthRemaining;
    uint256 public amountETHPerBlock;
    address public weth;
    uint256 public totalPosiBurned;
    address public operator;

    event PosiBurned(uint256 amount);

    modifier onlyOperator() {
        require(msg.sender == operator, "only operator");
        _;
    }


    function initialize(
        IERC20 _posiToken,
        IUniswapV2Router02  _swapRouter
    ) public initializer {
        __Ownable_init();
        duration = 3600 * 24 * 7;
        posi = _posiToken;
        swapRouter = _swapRouter;
    }



    function deposit() external payable onlyOperator {
        _bbb(amountEthRemaining);
        amountETH = msg.value;
        amountEthRemaining = msg.value;
        amountETHPerBlock = amountETH / duration;

        startEpoch = block.timestamp;
        endEpoch = block.timestamp + duration;
        lastTimeBBB = block.timestamp;
    }


    function bbb() public {

        require(block.timestamp >= startEpoch, "not started");
        require(block.timestamp <= endEpoch, "ended");

        uint256 amountToBBB = availableBBB();

        _bbb(amountToBBB);
        lastTimeBBB = block.timestamp;
        amountEthRemaining -= amountToBBB;
    }


    function availableBBB() public view returns(uint256){
        uint256 timeSinceLastBBB = block.timestamp - lastTimeBBB;
        uint256 amountToBBB = timeSinceLastBBB * amountETHPerBlock;
        return amountToBBB;
    }

    function _bbb(uint256 amount) internal {

        if (amount == 0) return;

         uint256[] memory amounts = swapRouter.swapExactETHForTokens{value : amount}(0, _getTokenToPosiRoute(), deadAddress, block.timestamp);
        totalPosiBurned += amounts[amounts.length - 1];

         emit PosiBurned(amounts[amounts.length - 1]);
    }

    function _getTokenToPosiRoute()
        private
        view
        returns (address[] memory paths)
    {
        paths = new address[](2);
        paths[0] = weth;
        paths[1] = address(posi);
    }

    function setDuration(uint256 _duration) external onlyOwner{
        duration = _duration;
    }

    function setSwapRouter(IUniswapV2Router02 _swapRouter) external onlyOwner{
        swapRouter = _swapRouter;
    }

    // write function set operator
    function setOperator(address _operator) external onlyOwner{
        operator = _operator;
    }


}
