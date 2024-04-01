// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import 'forge-std/Script.sol';
import { OptimizedScript } from './OptimizedScript.s.sol';
import { NounsDescriptorV2 } from '../contracts/NounsDescriptorV2.sol';
import { SVGRenderer } from '../contracts/SVGRenderer.sol';
import { INounsArt } from '../contracts/interfaces/INounsArt.sol';
import { NounsArt } from '../contracts/NounsArt.sol';
import { Inflator } from '../contracts/Inflator.sol';
import { NounsToken } from '../contracts/NounsToken.sol';
import { NounsSeeder } from '../contracts/NounsSeeder.sol';
import { IProxyRegistry } from '../contracts/external/opensea/IProxyRegistry.sol';
import { NounsAuctionHouseV2 } from '../contracts/NounsAuctionHouseV2.sol';
import { NounsAuctionHouseProxyAdmin } from '../contracts/proxies/NounsAuctionHouseProxyAdmin.sol';
import { NounsAuctionHouseProxy } from '../contracts/proxies/NounsAuctionHouseProxy.sol';
import { NounsDAOLogicV4Harness } from '../contracts/test/NounsDAOLogicV4Harness.sol';
import { INounsDAOLogic } from '../contracts/interfaces/INounsDAOLogic.sol';
import { NounsDAOExecutorV2 } from '../contracts/governance/NounsDAOExecutorV2.sol';
import { NounsDAOExecutorProxy } from '../contracts/governance/NounsDAOExecutorProxy.sol';
import { NounsDAOProxyV3 } from '../contracts/governance/NounsDAOProxyV3.sol';
import { NounsDAOTypes } from '../contracts/governance/NounsDAOInterfaces.sol';
import { NounDelegationToken } from '../contracts/governance/NounDelegationToken.sol';
import { NounsDAOForkEscrow } from '../contracts/governance/fork/NounsDAOForkEscrow.sol';
import { ForkDAODeployer } from '../contracts/governance/fork/ForkDAODeployer.sol';
import { NounsTokenFork } from '../contracts/governance/fork/newdao/token/NounsTokenFork.sol';
import { NounsAuctionHouseFork } from '../contracts/governance/fork/newdao/NounsAuctionHouseFork.sol';
import { NounsDAOLogicV1Fork } from '../contracts/governance/fork/newdao/governance/NounsDAOLogicV1Fork.sol';
import { NounsDAOExecutorForkV2 } from '../contracts/governance/fork/newdao/governance/NounsDAOExecutorForkV2.sol';
import { DescriptorHelpers } from '../test/foundry/helpers/DescriptorHelpers.sol';
import { NounsDAOData } from '../contracts/governance/data/NounsDAOData.sol';
import { NounsDAODataProxy } from '../contracts/governance/data/NounsDAODataProxy.sol';

contract DeployEverything is OptimizedScript, DescriptorHelpers {
    // Auction House Config
    uint256 constant AUCTION_HOUSE_DURATION = 120;
    uint192 constant AUCTION_HOUSE_RESERVE_PRICE = 1;
    uint56 constant AUCTION_HOUSE_TIME_BUFFER = 30;
    uint8 constant AUCTION_HOUSE_MIN_BID_INC_PERCENTAGE = 1;

    // Delegation Token Config
    string constant DELEGATION_TOKEN_BACKGROUND_COLOR = 'E381CB';

    // Fork Config
    uint256 public constant DELAYED_GOV_DURATION = 30 days;
    uint256 public constant FORK_DAO_VOTING_PERIOD = 25; // 5 minutes
    uint256 public constant FORK_DAO_VOTING_DELAY = 1;
    uint256 public constant FORK_DAO_PROPOSAL_THRESHOLD_BPS = 25; // 0.25%
    uint256 public constant FORK_DAO_QUORUM_VOTES_BPS = 1000; // 10%

    // Gov Config
    uint256 constant VOTING_PERIOD = 5 minutes / 12;
    uint256 constant VOTING_DELAY = 1;
    uint256 constant PROPOSAL_THRESHOLD = 1;
    uint32 constant QUEUE_PERIOD = 1 minutes / 12;
    uint32 constant GRACE_PERIOD = 14 days / 12;
    uint32 constant LAST_MINUTE_BLOCKS = 0;
    uint32 constant OBJECTION_PERIOD_BLOCKS = 0;
    uint32 constant UPDATABLE_PERIOD_BLOCKS = 2 minutes / 12;

    // Data Config
    uint256 public constant CREATE_CANDIDATE_COST = 0.01 ether;

    // TODOs
    // - fork config: create mainnet config
    // - nounders: read from config and fallback to deployer
    // - inflator: add a way to set its address instead of deploying a new instance every time
    // - art: support importing deployed art data contracts
    // - weth: allow user to set a custom address
    // - vetoer: allow user to set a custom address

    struct Contracts {
        NounsDescriptorV2 descriptor;
        NounsToken nouns;
        NounsAuctionHouseProxyAdmin ahProxyAdmin;
        NounsAuctionHouseV2 ahProxy;
        NounsDAOLogicV4Harness govLogic;
        INounsDAOLogic govProxy;
        NounsDAOExecutorV2 treasury;
        address govProxyPredictedAddress;
        NounDelegationToken delegationToken;
        NounsDAOForkEscrow forkEscrow;
        ForkDAODeployer forkDAODeployer;
        NounsDAOData dataProxy;
    }

    struct Config {
        uint256 deployerKey;
        address deployer;
        address nounders;
        address vetoer;
    }

    function run() public returns (Contracts memory c) {
        // requireDefaultProfile();

        Config memory config;
        config.deployerKey = vm.envUint('DEPLOYER_PRIVATE_KEY');
        config.deployer = vm.addr(config.deployerKey);
        config.nounders = config.deployer;
        config.vetoer = config.deployer;
        vm.startBroadcast(config.deployerKey);

        c.descriptor = new NounsDescriptorV2(INounsArt(address(0)), new SVGRenderer());
        c.descriptor.setArt(new NounsArt(address(c.descriptor), new Inflator()));

        c.nouns = new NounsToken(
            config.nounders,
            config.deployer, // temporary minter
            c.descriptor,
            new NounsSeeder(),
            IProxyRegistry(getProxyRegistryAddress())
        );
        c.delegationToken = new NounDelegationToken(address(c.nouns), DELEGATION_TOKEN_BACKGROUND_COLOR);

        c.ahProxyAdmin = new NounsAuctionHouseProxyAdmin();
        c.ahProxy = NounsAuctionHouseV2(
            address(
                new NounsAuctionHouseProxy(
                    address(new NounsAuctionHouseV2(c.nouns, getWETHAddress(), AUCTION_HOUSE_DURATION)),
                    address(c.ahProxyAdmin),
                    ''
                )
            )
        );

        c.forkDAODeployer = new ForkDAODeployer(
            address(new NounsTokenFork()),
            address(new NounsAuctionHouseFork()),
            address(new NounsDAOLogicV1Fork()),
            address(new NounsDAOExecutorForkV2()),
            DELAYED_GOV_DURATION,
            FORK_DAO_VOTING_PERIOD,
            FORK_DAO_VOTING_DELAY,
            FORK_DAO_PROPOSAL_THRESHOLD_BPS,
            FORK_DAO_QUORUM_VOTES_BPS
        );
        c.govLogic = new NounsDAOLogicV4Harness();

        c.govProxyPredictedAddress = predictContractAddress(config.deployer, 3);
        c.treasury = deployAndInitTimelockV2(c.govProxyPredictedAddress);
        c.forkEscrow = new NounsDAOForkEscrow(c.govProxyPredictedAddress, address(c.nouns));

        c.govProxy = INounsDAOLogic(
            address(
                new NounsDAOProxyV3(
                    address(c.treasury),
                    address(c.nouns),
                    address(c.delegationToken),
                    address(c.forkEscrow),
                    address(c.forkDAODeployer),
                    config.vetoer,
                    address(c.treasury),
                    address(c.govLogic),
                    defaultDAOParams(),
                    defaultDQParams()
                )
            )
        );
        require(
            address(c.govProxy) == c.govProxyPredictedAddress,
            'gov proxy address does not match prediction. fix your nonce offset value.'
        );

        c.dataProxy = deployData(address(c.nouns), address(c.govProxy), address(c.treasury));

        c.ahProxy.initialize(
            AUCTION_HOUSE_RESERVE_PRICE,
            AUCTION_HOUSE_TIME_BUFFER,
            AUCTION_HOUSE_MIN_BID_INC_PERCENTAGE
        );
        c.ahProxyAdmin.transferOwnership(address(c.treasury));
        c.nouns.setMinter(address(c.ahProxy));
        c.nouns.transferOwnership(address(c.treasury));

        _populateDescriptorV2(c.descriptor);
        c.descriptor.transferOwnership(address(c.treasury));

        c.ahProxy.unpause();
        c.ahProxy.transferOwnership(address(c.treasury));

        vm.stopBroadcast();
    }

    function deployData(address nouns, address govProxy, address treasury) internal returns (NounsDAOData) {
        NounsDAOData logic = new NounsDAOData(nouns, govProxy);

        bytes memory initCallData = abi.encodeWithSignature(
            'initialize(address,uint256,uint256,address)',
            treasury,
            CREATE_CANDIDATE_COST,
            0,
            govProxy
        );

        NounsDAODataProxy proxy = new NounsDAODataProxy(address(logic), initCallData);
        return NounsDAOData(address(proxy));
    }

    function deployAndInitTimelockV2(address govProxy) internal returns (NounsDAOExecutorV2) {
        NounsDAOExecutorV2 treasuryLogic = new NounsDAOExecutorV2();
        bytes memory initCallData = abi.encodeWithSignature('initialize(address)', address(govProxy));

        return NounsDAOExecutorV2(payable(address(new NounsDAOExecutorProxy(address(treasuryLogic), initCallData))));
    }

    function predictContractAddress(address deployer, uint256 nonceOffset) internal view returns (address) {
        return computeCreateAddress(deployer, vm.getNonce(deployer) + nonceOffset);
    }

    function getProxyRegistryAddress() internal view returns (address) {
        if (block.chainid == 1) return 0xa5409ec958C83C3f309868babACA7c86DCB077c1;
        if (block.chainid == 5) return 0x5d44754DE92363d5746485F31280E4c0c54c855c;
        if (block.chainid == 11155111) return 0x152E981d511F8c0865354A71E1cb84d0FB318470;
        return address(0);
    }

    function getWETHAddress() internal view returns (address) {
        if (block.chainid == 1) return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        if (block.chainid == 5) return 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;
        if (block.chainid == 11155111) return 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
        revert('cannot deploy without a WETH address');
    }

    function defaultDAOParams() internal pure returns (NounsDAOTypes.NounsDAOParams memory) {
        return
            NounsDAOTypes.NounsDAOParams({
                votingPeriod: VOTING_PERIOD,
                votingDelay: VOTING_DELAY,
                proposalThresholdBPS: PROPOSAL_THRESHOLD,
                lastMinuteWindowInBlocks: LAST_MINUTE_BLOCKS,
                objectionPeriodDurationInBlocks: OBJECTION_PERIOD_BLOCKS,
                proposalUpdatablePeriodInBlocks: UPDATABLE_PERIOD_BLOCKS,
                queuePeriod: QUEUE_PERIOD,
                gracePeriod: GRACE_PERIOD
            });
    }

    function defaultDQParams() internal pure returns (NounsDAOTypes.DynamicQuorumParams memory) {
        return
            NounsDAOTypes.DynamicQuorumParams({
                minQuorumVotesBPS: 200,
                maxQuorumVotesBPS: 2000,
                quorumCoefficient: 10000
            });
    }
}
