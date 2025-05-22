// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {Pool} from "@ccip/contracts/src/v0.8/ccip/libraries/Pool.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {IRebaseToken} from "./interfaces/IRebaseToken.sol";
import {console} from "forge-std/console.sol";

contract RebaseTokenPool is TokenPool {
    constructor(IERC20 _token, address[] memory _allowlist, address _rmnProxy, address _router)
        TokenPool(_token, _allowlist, _rmnProxy, _router)
    {
        // constructor logic
    }

    function lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn)
        external
        returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut)
    {
        _validateLockOrBurn(lockOrBurnIn);

        // Log the sender's balance
        console.log("Original sender balance:", i_token.balanceOf(lockOrBurnIn.originalSender));

        // Log the amount being locked/burned
        console.log("Amount to lock/burn:", lockOrBurnIn.amount);

        // Log pool balance
        uint256 poolBalance = i_token.balanceOf(address(this));
        console.log("Pool balance before:", poolBalance);

        // Make sure we have enough tokens to burn
        require(poolBalance >= lockOrBurnIn.amount, "Insufficient pool balance for burn");

        uint256 userInterestRate = IRebaseToken(address(i_token)).getUserInterestRate(lockOrBurnIn.originalSender);

        // Burn the tokens from this contract's balance
        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);

        // Log after burning
        console.log("Pool balance after:", i_token.balanceOf(address(this)));

        lockOrBurnOut = Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
            destPoolData: abi.encode(userInterestRate)
        });
    }

    function releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn)
        external
        returns (Pool.ReleaseOrMintOutV1 memory)
    {
        _validateReleaseOrMint(releaseOrMintIn);

        uint256 userInterestRate = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));
        console.log("User interest rate:", userInterestRate);

        // Mint the tokens
        IRebaseToken(address(i_token)).mint(releaseOrMintIn.receiver, releaseOrMintIn.amount, userInterestRate);

        return Pool.ReleaseOrMintOutV1({destinationAmount: releaseOrMintIn.amount});
    }
}
