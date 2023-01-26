// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./FToken.sol";

interface PriceOracle {
    /**
     * @notice Indicator that this is a PriceOracle contract (for inspection)
     */
    function isPriceOracle() external pure returns (bool);

    /**
      * @notice Get the underlying price of a fToken asset
      * @param fToken The fToken to get the underlying price of
      * @return The underlying asset price mantissa (scaled by 1e18).
      *  Zero means the price is unavailable.
      */
    function getUnderlyingPrice(FToken fToken) external view returns (uint);
}
