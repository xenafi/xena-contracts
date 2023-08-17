# Xena Finance - Trading contracts

Xena concentrate on optimizing contract code readability and gas usage. We extract business logic to number of small, state-less contracts to reduce contract size and separate concern. Some changes mainly target Layer 2 network.

## Changeset

### Solidity

- Upgrade solidity to 0.8.18

### Pool

- calcSwapFee, calcAddRemoveLiquidity, calcSwap,... and number of liquidity related calculation now belong to LiquidityCalculator contract.
- introduce InterestRateModel for more flexible interest rate model can be applied to particular token.
- max global long position size now applied by tranche. For example, given max long ratio of BTC is 80%, all tranche will reserve a max value of 80% of its poolAmount
- add position revision
- fix posible overflow error when multiple two uint256

### OrderManager

- order data now being kept instead of delete after order settled. Introduce new property `orderStatus`
- introduce minExecutionDelayTime.

### Oracle

- Add guard check for L2 sequence uptime.

### Utilities

- Improve usability with number of lens contracts.
