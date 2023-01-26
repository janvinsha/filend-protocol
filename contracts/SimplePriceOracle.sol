// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./PriceOracle.sol";
import "./FErc20.sol";

contract SimplePriceOracle is PriceOracle {
    mapping(address => uint) prices;
    bool public constant isPriceOracle = true;

    function getUnderlyingPrice(FToken fToken) public view returns (uint) {
        return prices[address(FErc20(address(fToken)).underlying())];
    }

    function setUnderlyingPrice(FToken fToken, uint underlyingPriceMantissa) public {
        prices[address(FErc20(address(fToken)).underlying())] = underlyingPriceMantissa;
    }

    function setDirectPrice(address a, uint price) public {
        prices[a] = price;
    }

    // v1 price oracle interface for use as backing of proxy
    function assetPrices(address asset) external view returns (uint) {
        return prices[asset];
    }

     function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
}
