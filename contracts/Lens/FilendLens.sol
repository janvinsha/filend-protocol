// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
pragma experimental ABIEncoderV2;

import "../FErc20.sol";
import "../FToken.sol";
import "../PriceOracle.sol";
import "../libraries/EIP20Interface.sol";
import "../Governance/GovernorAlpha.sol";
import "../Governance/Fil.sol";

interface FiltrollerLensInterface {
    function markets(address) external view returns (bool, uint);
    function oracle() external view returns (PriceOracle);
    function getAccountLiquidity(address) external view returns (uint, uint, uint);
    function getAssetsIn(address) external view returns (FToken[] memory);
    function claimFil(address) external;
    function filAccrued(address) external view returns (uint);
}

contract FilendLens {
    struct FTokenMetadata {
        address fToken;
        uint exchangeRateCurrent;
        uint supplyRatePerBlock;
        uint borrowRatePerBlock;
        uint reserveFactorMantissa;
        uint totalBorrows;
        uint totalReserves;
        uint totalSupply;
        uint totalCash;
        bool isListed;
        uint collateralFactorMantissa;
        address underlyingAssetAddress;
        uint fTokenDecimals;
        uint underlyingDecimals;
    }

    function fTokenMetadata(FToken fToken) public returns (FTokenMetadata memory) {
        uint exchangeRateCurrent = fToken.exchangeRateCurrent();
        FiltrollerLensInterface filtroller = FiltrollerLensInterface(address(fToken.filtroller()));
        (bool isListed, uint collateralFactorMantissa) = filtroller.markets(address(fToken));
        address underlyingAssetAddress;
        uint underlyingDecimals;

        if (compareStrings(fToken.symbol(), "fETH")) {
            underlyingAssetAddress = address(0);
            underlyingDecimals = 18;
        } else {
            FErc20 fErc20 = FErc20(address(fToken));
            underlyingAssetAddress = fErc20.underlying();
            underlyingDecimals = EIP20Interface(fErc20.underlying()).decimals();
        }

        return FTokenMetadata({
            fToken: address(fToken),
            exchangeRateCurrent: exchangeRateCurrent,
            supplyRatePerBlock: fToken.supplyRatePerBlock(),
            borrowRatePerBlock: fToken.borrowRatePerBlock(),
            reserveFactorMantissa: fToken.reserveFactorMantissa(),
            totalBorrows: fToken.totalBorrows(),
            totalReserves: fToken.totalReserves(),
            totalSupply: fToken.totalSupply(),
            totalCash: fToken.getCash(),
            isListed: isListed,
            collateralFactorMantissa: collateralFactorMantissa,
            underlyingAssetAddress: underlyingAssetAddress,
            fTokenDecimals: fToken.decimals(),
            underlyingDecimals: underlyingDecimals
        });
    }

    function FTokenMetadataAll(FToken[] calldata fTokens) external returns (FTokenMetadata[] memory) {
        uint fTokenCount = fTokens.length;
        FTokenMetadata[] memory res = new FTokenMetadata[](fTokenCount);
        for (uint i = 0; i < fTokenCount; i++) {
            res[i] = fTokenMetadata(fTokens[i]);
        }
        return res;
    }

    struct FTokenBalances {
        address fToken;
        uint balanceOf;
        uint borrowBalanceCurrent;
        uint balanceOfUnderlying;
        uint tokenBalance;
        uint tokenAllowance;
    }

    function fTokenBalances(FToken fToken, address payable account) public returns (FTokenBalances memory) {
        uint balanceOf = fToken.balanceOf(account);
        uint borrowBalanceCurrent = fToken.borrowBalanceCurrent(account);
        uint balanceOfUnderlying = fToken.balanceOfUnderlying(account);
        uint tokenBalance;
        uint tokenAllowance;

        if (compareStrings(fToken.symbol(), "fETH")) {
            tokenBalance = account.balance;
            tokenAllowance = account.balance;
        } else {
            FErc20 fErc20 = FErc20(address(fToken));
            EIP20Interface underlying = EIP20Interface(fErc20.underlying());
            tokenBalance = underlying.balanceOf(account);
            tokenAllowance = underlying.allowance(account, address(fToken));
        }

        return FTokenBalances({
            fToken: address(fToken),
            balanceOf: balanceOf,
            borrowBalanceCurrent: borrowBalanceCurrent,
            balanceOfUnderlying: balanceOfUnderlying,
            tokenBalance: tokenBalance,
            tokenAllowance: tokenAllowance
        });
    }

    function fTokenBalancesAll(FToken[] calldata fTokens, address payable account) external returns (FTokenBalances[] memory) {
        uint fTokenCount = fTokens.length;
        FTokenBalances[] memory res = new FTokenBalances[](fTokenCount);
        for (uint i = 0; i < fTokenCount; i++) {
            res[i] = fTokenBalances(fTokens[i], account);
        }
        return res;
    }

    struct FTokenUnderlyingPrice {
        address fToken;
        uint underlyingPrice;
    }

    function fTokenUnderlyingPrice(FToken fToken) public view returns (FTokenUnderlyingPrice memory) {
        FiltrollerLensInterface filtroller = FiltrollerLensInterface(address(fToken.filtroller()));
        PriceOracle priceOracle = filtroller.oracle();

        return FTokenUnderlyingPrice({
            fToken: address(fToken),
            underlyingPrice: priceOracle.getUnderlyingPrice(fToken)
        });
    }

    function fTokenUnderlyingPriceAll(FToken[] calldata fTokens) external view returns (FTokenUnderlyingPrice[] memory) {
        uint fTokenCount = fTokens.length;
        FTokenUnderlyingPrice[] memory res = new FTokenUnderlyingPrice[](fTokenCount);
        for (uint i = 0; i < fTokenCount; i++) {
            res[i] = fTokenUnderlyingPrice(fTokens[i]);
        }
        return res;
    }

    struct AccountLimits {
        FToken[] markets;
        uint liquidity;
        uint shortfall;
    }

    function getAccountLimits(FiltrollerLensInterface filtroller, address account) public view returns (AccountLimits memory) {
        (uint errorCode, uint liquidity, uint shortfall) = filtroller.getAccountLiquidity(account);
        require(errorCode == 0);

        return AccountLimits({
            markets: filtroller.getAssetsIn(account),
            liquidity: liquidity,
            shortfall: shortfall
        });
    }

    struct GovReceipt {
        uint proposalId;
        bool hasVoted;
        bool support;
        uint96 votes;
    }

    function getGovReceipts(GovernorAlpha governor, address voter, uint[] memory proposalIds) public view returns (GovReceipt[] memory) {
        uint proposalCount = proposalIds.length;
        GovReceipt[] memory res = new GovReceipt[](proposalCount);
        for (uint i = 0; i < proposalCount; i++) {
            GovernorAlpha.Receipt memory receipt = governor.getReceipt(proposalIds[i], voter);
            res[i] = GovReceipt({
                proposalId: proposalIds[i],
                hasVoted: receipt.hasVoted,
                support: receipt.support,
                votes: receipt.votes
            });
        }
        return res;
    }

    struct GovProposal {
        uint proposalId;
        address proposer;
        uint eta;
        address[] targets;
        uint[] values;
        string[] signatures;
        bytes[] calldatas;
        uint startBlock;
        uint endBlock;
        uint forVotes;
        uint againstVotes;
        bool canceled;
        bool executed;
    }

    function setProposal(GovProposal memory res, GovernorAlpha governor, uint proposalId) internal view {
        (
            ,
            address proposer,
            uint eta,
            uint startBlock,
            uint endBlock,
            uint forVotes,
            uint againstVotes,
            bool canceled,
            bool executed
        ) = governor.proposals(proposalId);
        res.proposalId = proposalId;
        res.proposer = proposer;
        res.eta = eta;
        res.startBlock = startBlock;
        res.endBlock = endBlock;
        res.forVotes = forVotes;
        res.againstVotes = againstVotes;
        res.canceled = canceled;
        res.executed = executed;
    }

    function getGovProposals(GovernorAlpha governor, uint[] calldata proposalIds) external view returns (GovProposal[] memory) {
        GovProposal[] memory res = new GovProposal[](proposalIds.length);
        for (uint i = 0; i < proposalIds.length; i++) {
            (
                address[] memory targets,
                uint[] memory values,
                string[] memory signatures,
                bytes[] memory calldatas
            ) = governor.getActions(proposalIds[i]);
            res[i] = GovProposal({
                proposalId: 0,
                proposer: address(0),
                eta: 0,
                targets: targets,
                values: values,
                signatures: signatures,
                calldatas: calldatas,
                startBlock: 0,
                endBlock: 0,
                forVotes: 0,
                againstVotes: 0,
                canceled: false,
                executed: false
            });
            setProposal(res[i], governor, proposalIds[i]);
        }
        return res;
    }

    struct FilBalanceMetadata {
        uint balance;
        uint votes;
        address delegate;
    }

    function getFilBalanceMetadata(Fil fil, address account) external view returns (FilBalanceMetadata memory) {
        return FilBalanceMetadata({
            balance: fil.balanceOf(account),
            votes: uint256(fil.getCurrentVotes(account)),
            delegate: fil.delegates(account)
        });
    }

    struct FilBalanceMetadataExt {
        uint balance;
        uint votes;
        address delegate;
        uint allocated;
    }

    function getFilBalanceMetadataExt(Fil fil, FiltrollerLensInterface filtroller, address account) external returns (FilBalanceMetadataExt memory) {
        uint balance = fil.balanceOf(account);
        filtroller.claimFil(account);
        uint newBalance = fil.balanceOf(account);
        uint accrued = filtroller.filAccrued(account);
        uint total = add(accrued, newBalance, "sum fil total");
        uint allocated = sub(total, balance, "sub allocated");

        return FilBalanceMetadataExt({
            balance: balance,
            votes: uint256(fil.getCurrentVotes(account)),
            delegate: fil.delegates(account),
            allocated: allocated
        });
    }

    struct FilVotes {
        uint blockNumber;
        uint votes;
    }

    function getFilVotes(Fil fil, address account, uint32[] calldata blockNumbers) external view returns (FilVotes[] memory) {
        FilVotes[] memory res = new FilVotes[](blockNumbers.length);
        for (uint i = 0; i < blockNumbers.length; i++) {
            res[i] = FilVotes({
                blockNumber: uint256(blockNumbers[i]),
                votes: uint256(fil.getPriorVotes(account, blockNumbers[i]))
            });
        }
        return res;
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    function add(uint a, uint b, string memory errorMessage) internal pure returns (uint) {
        uint c = a + b;
        require(c >= a, errorMessage);
        return c;
    }

    function sub(uint a, uint b, string memory errorMessage) internal pure returns (uint) {
        require(b <= a, errorMessage);
        uint c = a - b;
        return c;
    }
}
