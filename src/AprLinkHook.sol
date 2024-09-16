// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";

import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract AprLinkHook is BaseHook {
    using LPFeeLibrary for uint24;

    AggregatorV3Interface internal dataFeed;

    error MustUseDynamicFee();

    // ChainLink feed for 30 rolling average ETH Staking APR
    // https://docs.chain.link/data-feeds/rates-feeds#eth-staking-apr
    address constant CHAINLINK_ETH_STAKING_APR_FEED = 0xceA6Aa74E6A86a7f85B571Ce1C34f1A60B77CD29;

    // Initialize BaseHook parent contract in the constructor
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        dataFeed = AggregatorV3Interface(CHAINLINK_ETH_STAKING_APR_FEED);
    }

    // Required override function for BaseHook to let the PoolManager know which hooks are implemented
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true, // used to ensure that pool fee is dynamic
            afterInitialize: false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true, // used to update dynamic fee
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function beforeInitialize(address, PoolKey calldata key, uint160, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        // `.isDynamicFee()` function comes from using
        // the `SwapFeeLibrary` for `uint24`
        if (!key.fee.isDynamicFee()) revert MustUseDynamicFee();
        return this.beforeInitialize.selector;
    }

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        uint24 fee = getFee();
        poolManager.updateDynamicLPFee(key, fee);
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function getFee() public view returns (uint24) {
        int256 stakingApr = getChainStakingApr();

        uint24 fee = uint24(uint256(stakingApr) / 1_000);

        return fee;
    }

    function getChainStakingApr() internal view returns (int256) {
        // prettier-ignore
        (
            /* uint80 roundID */
            ,
            int256 answer,
            /*uint startedAt*/
            ,
            /*uint timeStamp*/
            ,
            /*uint80 answeredInRound*/
        ) = dataFeed.latestRoundData();
        return answer;
    }
}
