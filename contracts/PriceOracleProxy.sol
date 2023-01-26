// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;


import "./FErc20.sol";
import "./FToken.sol";
import "./PriceOracle.sol";
import "./Filtroller.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface V1PriceOracleInterface {
    function assetPrices(address asset) external view returns (uint);
}

contract PriceOracleProxy is PriceOracle {
    /// @notice Indicator that this is a PriceOracle contract (for inspection)
    bool public constant isPriceOracle = true;

    /// @notice The v1 price oracle, which will continue to serve prices for v1 assets
    V1PriceOracleInterface public v1PriceOracle;

    /// @notice Address of the guardian, which may set the SAI price once
    address public guardian;

    /// @notice Address of the fEther contract, which has a constant price
    address public fEthAddress;

    /// @notice Address of the fUSDC contract, which we hand pick a key for
    address public fUsdcAddress;

    /// @notice Address of the fUSDT contract, which uses the cUSDC price
    address public fUsdtAddress;

  

    /// @notice Handpicked key for USDC
    address public constant usdcOracleKey = address(1);

  

    /// @notice Frozen SAI price (or 0 if not set yet)
    uint public saiPrice;

    /**
     * @param guardian_ The address of the guardian, which may set the SAI price once
     * @param v1PriceOracle_ The address of the v1 price oracle, which will continue to operate and hold prices for collateral assets
     * @param fEthAddress_ The address of fETH, which will return a constant 1e18, since all prices relative to ether
     * @param fUsdcAddress_ The address of fUSDC, which will be read from a special oracle key
     */
    constructor(address guardian_,
                address v1PriceOracle_,
                address fEthAddress_,
                address fUsdcAddress_,
                address fUsdtAddress_) public {
        guardian = guardian_;
        v1PriceOracle = V1PriceOracleInterface(v1PriceOracle_);

        fEthAddress = fEthAddress_;
        fUsdcAddress = fUsdcAddress_;
      
        fUsdtAddress = fUsdtAddress_;
    }

    /**
     * @notice Get the underlying price of a listed fToken asset
     * @param fToken The fToken to get the underlying price of
     * @return The underlying asset price mantissa (scaled by 1e18)
     */
    function getUnderlyingPrice(FToken fToken) public view returns (uint) {
        address fTokenAddress = address(fToken);

        if (fTokenAddress == fEthAddress) {
            // ether always worth 1
            return 1e18;
        }

        if (fTokenAddress == fUsdcAddress || fTokenAddress == fUsdtAddress) {
            return v1PriceOracle.assetPrices(usdcOracleKey);
        }


        // otherwise just read from v1 oracle
        address underlying = FErc20(fTokenAddress).underlying();
        return v1PriceOracle.assetPrices(underlying);
    }

    /**
     * @notice Set the price of SAI, permanently
     * @param price The price for SAI
     */
    function setSaiPrice(uint price) public {
        require(msg.sender == guardian, "only guardian may set the SAI price");
        require(saiPrice == 0, "SAI price may only be set once");
        require(price < 0.1e18, "SAI price must be < 0.1 ETH");
        saiPrice = price;
    }
}
