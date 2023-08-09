// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPoolHook} from "../interfaces/IPoolHook.sol";
import {IMintableErc20} from "../interfaces/IMintableErc20.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {ITradingContest} from "../interfaces/ITradingContest.sol";
import {ITradingIncentiveController} from "../interfaces/ITradingIncentiveController.sol";
import {IReferralController} from "../interfaces/IReferralController.sol";
import {DataTypes} from "../lib/DataTypes.sol";

contract PoolHook is Ownable, IPoolHook {
    uint8 constant lpXenDecimals = 18;
    uint256 constant VALUE_PRECISION = 1e30;

    address private immutable pool;
    IMintableErc20 public immutable lpXen;

    IReferralController immutable referralController;
    ITradingContest public tradingContest;
    ITradingIncentiveController public tradingIncentiveController;

    constructor(
        address _lpXen,
        address _pool,
        address _referralController
    ) {
        if (_lpXen == address(0)) revert InvalidAddress();
        if (_pool == address(0)) revert InvalidAddress();
        if (_referralController == address(0)) revert InvalidAddress();

        lpXen = IMintableErc20(_lpXen);
        pool = _pool;
        referralController = IReferralController(_referralController);
    }

    modifier onlyPool() {
        _validatePool(msg.sender);
        _;
    }

    /**
     * @inheritdoc IPoolHook
     */
    function postIncreasePosition(
        address _owner,
        address _indexToken,
        address _collateralToken,
        DataTypes.Side _side,
        bytes calldata _extradata
    ) external onlyPool {
        (,, uint256 _feeValue) = abi.decode(_extradata, (uint256, uint256, uint256));
        _updateReferralData(_owner, _feeValue);
        _sentTradingRecord(_owner, _feeValue);
        emit PostIncreasePositionExecuted(pool, _owner, _indexToken, _collateralToken, _side, _extradata);
    }

    /**
     * @inheritdoc IPoolHook
     */
    function postDecreasePosition(
        address _owner,
        address _indexToken,
        address _collateralToken,
        DataTypes.Side _side,
        bytes calldata _extradata
    ) external onlyPool {
        ( /*uint256 sizeChange*/ , /* uint256 collateralValue */, uint256 _feeValue) =
            abi.decode(_extradata, (uint256, uint256, uint256));
        _updateReferralData(_owner, _feeValue);
        _sentTradingRecord(_owner, _feeValue);
        emit PostDecreasePositionExecuted(msg.sender, _owner, _indexToken, _collateralToken, _side, _extradata);
    }

    /**
     * @inheritdoc IPoolHook
     */
    function postLiquidatePosition(
        address _owner,
        address _indexToken,
        address _collateralToken,
        DataTypes.Side _side,
        bytes calldata _extradata
    ) external onlyPool {
        ( /*uint256 sizeChange*/ , /* uint256 collateralValue */, uint256 _feeValue) =
            abi.decode(_extradata, (uint256, uint256, uint256));
        _updateReferralData(_owner, _feeValue);
        _sentTradingRecord(_owner, _feeValue);
        emit PostLiquidatePositionExecuted(msg.sender, _owner, _indexToken, _collateralToken, _side, _extradata);
    }

    /**
     * @inheritdoc IPoolHook
     */
    function postSwap(address _user, address _tokenIn, address _tokenOut, bytes calldata _data) external onlyPool {
        ( /*uint256 amountIn*/ , /* uint256 amountOut */, uint256 feeValue, bytes memory extradata) =
            abi.decode(_data, (uint256, uint256, uint256, bytes));
        (address benificier) = extradata.length != 0 ? abi.decode(extradata, (address)) : (address(0));
        benificier = benificier == address(0) ? _user : benificier;
        _updateReferralData(benificier, feeValue);
        _sentTradingRecord(benificier, feeValue);
        emit PostSwapExecuted(msg.sender, _user, _tokenIn, _tokenOut, _data);
    }

    // ========= Admin function ========

    function setTradingRecord(address _tradingContest, address _tradingIncentiveController) external onlyOwner {
        if (_tradingContest == address(0)) revert InvalidAddress();
        if (_tradingIncentiveController == address(0)) revert InvalidAddress();
        tradingContest = ITradingContest(_tradingContest);
        tradingIncentiveController = ITradingIncentiveController(_tradingIncentiveController);
        emit TradingIncentiveSet(_tradingContest, _tradingIncentiveController);
    }

    // ========= Internal function ========

    function _updateReferralData(address _trader, uint256 _value) internal {
        if (address(referralController) != address(0) && _trader != address(0)) {
            referralController.updateFee(_trader, _value);
        }
    }

    function _sentTradingRecord(address _trader, uint256 _value) internal {
        if (_value == 0 || _trader == address(0)) {
            return;
        }

        if (address(tradingIncentiveController) != address(0)) {
            tradingIncentiveController.record(_value);
        }

        if (address(tradingContest) != address(0)) {
            tradingContest.record(_trader, _value);
        }

        uint256 _lyTokenAmount = (_value * 10 ** lpXenDecimals) / VALUE_PRECISION;
        lpXen.mint(_trader, _lyTokenAmount);
    }

    function _validatePool(address sender) internal view {
        if (sender != pool) {
            revert OnlyPool();
        }
    }

    event ReferralControllerSet(address controller);
    event TradingIncentiveSet(address tradingRecord, address tradingIncentiveController);

    error InvalidAddress();
    error OnlyPool();
}
