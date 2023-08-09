pragma solidity 0.8.18;

import {DataTypes} from "../lib/DataTypes.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {IPool} from "../interfaces/IPool.sol";
import {IOrderHook} from "../interfaces/IOrderHook.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {IETHUnwrapper} from "../interfaces/IETHUnwrapper.sol";

abstract contract OrderManagerStorage {
    IWETH public weth;

    IPool public pool;
    IOracle public oracle;
    IOrderHook public orderHook;
    address public executor;

    uint256 public nextLeverageOrderId;
    uint256 public nextSwapOrderId;
    uint256 public minLeverageExecutionFee;
    uint256 public minSwapExecutionFee;

    mapping(uint256 orderId => DataTypes.LeverageOrder) public leverageOrders;
    mapping(uint256 orderId => DataTypes.UpdatePositionRequest) public updatePositionRequests;
    mapping(uint256 orderId => DataTypes.SwapOrder) public swapOrders;
    mapping(address user => uint256[]) public userLeverageOrders;
    mapping(address user => uint256) public userLeverageOrderCount;
    mapping(address user => uint256[]) public userSwapOrders;
    mapping(address user => uint256) public userSwapOrderCount;

    address public controller;
    /// @notice when enable user can execute their own order
    bool public enablePublicExecution;
    /// @notice min time between order submission and execution
    uint256 public executionDelayTime;
}
