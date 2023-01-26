// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../FToken.sol";
import "../PriceOracle.sol";

contract UnitrollerAdminStorage {
    /**
    * @notice Administrator for this contract
    */
    address public admin;

    /**
    * @notice Pending administrator for this contract
    */
    address public pendingAdmin;

    /**
    * @notice Active brains of Unitroller
    */
    address public filtrollerImplementation;

    /**
    * @notice Pending brains of Unitroller
    */
    address public pendingFiltrollerImplementation;
}

contract FiltrollerV1Storage is UnitrollerAdminStorage {

    /**
     * @notice Oracle which gives the price of any given asset
     */
    PriceOracle public oracle;

    /**
     * @notice Multiplier used to calculate the maximum repayAmount when liquidating a borrow
     */
    uint public closeFactorMantissa;

    /**
     * @notice Multiplier representing the discount on collateral that a liquidator receives
     */
    uint public liquidationIncentiveMantissa;

    /**
     * @notice Max number of assets a single account can participate in (borrow or use as collateral)
     */
    uint public maxAssets;

    /**
     * @notice Per-account mapping of "assets you are in", capped by maxAssets
     */
    mapping(address => FToken[]) public accountAssets;

}

contract FiltrollerV2Storage is FiltrollerV1Storage {
    struct Market {
        /// @notice Whether or not this market is listed
        bool isListed;

        /**
         * @notice Multiplier representing the most one can borrow against their collateral in this market.
         *  For instance, 0.9 to allow borrowing 90% of collateral value.
         *  Must be between 0 and 1, and stored as a mantissa.
         */
        uint collateralFactorMantissa;

        /// @notice Per-market mapping of "accounts in this asset"
        mapping(address => bool) accountMembership;

        /// @notice Whether or not this market receives fil
        bool isFiled;
    }

    /**
     * @notice Official mapping of fTokens -> Market metadata
     * @dev Used e.g. to determine if a market is supported
     */
    mapping(address => Market) public markets;


    /**
     * @notice The Pause Guardian can pause certain actions as a safety mechanism.
     *  Actions which allow users to remove their own assets cannot be paused.
     *  Liquidation / seizing / transfer can only be paused globally, not by market.
     */
    address public pauseGuardian;
    bool public _mintGuardianPaused;
    bool public _borrowGuardianPaused;
    bool public transferGuardianPaused;
    bool public seizeGuardianPaused;
    mapping(address => bool) public mintGuardianPaused;
    mapping(address => bool) public borrowGuardianPaused;
}

contract FiltrollerV3Storage is FiltrollerV2Storage {
    struct FilMarketState {
        /// @notice The market's last updated filBorrowIndex or filSupplyIndex
        uint224 index;

        /// @notice The block number the index was last updated at
        uint32 block;
    }

    /// @notice A list of all markets
    FToken[] public allMarkets;

    /// @notice The rate at which the flywheel distributes fil, per block
    uint public filRate;

    /// @notice The portion of filRate that each market currently receives
    mapping(address => uint) public filSpeeds;

    /// @notice The fil market supply state for each market
    mapping(address => FilMarketState) public filSupplyState;

    /// @notice The fil market borrow state for each market
    mapping(address => FilMarketState) public filBorrowState;

    /// @notice The fil borrow index for each market for each supplier as of the last time they accrued fil
    mapping(address => mapping(address => uint)) public filSupplierIndex;

    /// @notice The fil borrow index for each market for each borrower as of the last time they accrued fil
    mapping(address => mapping(address => uint)) public filBorrowerIndex;

    /// @notice The fil accrued but not yet transferred to each user
    mapping(address => uint) public filAccrued;
}
