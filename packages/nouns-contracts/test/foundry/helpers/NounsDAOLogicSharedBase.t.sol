// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import 'forge-std/Test.sol';
import { INounsDAOLogic } from '../../../contracts/interfaces/INounsDAOLogic.sol';
import { NounsDescriptorV2 } from '../../../contracts/NounsDescriptorV2.sol';
import { DeployUtilsFork } from './DeployUtilsFork.sol';
import { NounsToken } from '../../../contracts/NounsToken.sol';
import { NounsSeeder } from '../../../contracts/NounsSeeder.sol';
import { IProxyRegistry } from '../../../contracts/external/opensea/IProxyRegistry.sol';
import { NounsDAOExecutor } from '../../../contracts/governance/NounsDAOExecutor.sol';
import { INounsTokenForkLike } from '../../../contracts/governance/fork/newdao/governance/INounsTokenForkLike.sol';
import { Utils } from './Utils.sol';
import { NounsTokenLike } from '../../../contracts/governance/NounsDAOInterfaces.sol';
import { DelegationHelpers } from './DelegationHelpers.sol';
import { NounsDAOProposals } from '../../../contracts/governance/NounsDAOProposals.sol';

interface DAOLogicFork {
    function _setQuorumVotesBPS(uint256 newQuorumVotesBPS) external;
}

abstract contract NounsDAOLogicSharedBaseTest is Test, DeployUtilsFork {
    using DelegationHelpers for address;

    INounsDAOLogic daoProxy;
    NounsToken nounsToken;
    NounsDAOExecutor timelock = new NounsDAOExecutor(address(1), TIMELOCK_DELAY);
    address vetoer = address(0x3);
    address admin = address(0x4);
    address noundersDAO = address(0x5);
    address minter = address(0x6);
    address proposer = address(0x7);
    uint256 votingPeriod = 7200;
    uint256 votingDelay = 1;
    uint256 proposalThresholdBPS = 200;
    Utils utils;

    function setUp() public virtual {
        NounsDescriptorV2 descriptor = _deployAndPopulateV2();
        nounsToken = new NounsToken(noundersDAO, minter, descriptor, new NounsSeeder(), IProxyRegistry(address(0)));

        daoProxy = deployDAOProxy(address(timelock), address(nounsToken), vetoer);

        vm.prank(address(timelock));
        timelock.setPendingAdmin(address(daoProxy));
        vm.prank(address(daoProxy));
        timelock.acceptAdmin();

        utils = new Utils();
    }

    function deployDAOProxy(
        address timelock,
        address nounsToken,
        address vetoer
    ) internal virtual returns (INounsDAOLogic);

    function daoVersion() internal virtual returns (uint256) {
        return 0; // override to specify version
    }

    function makeTxs(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data
    ) internal returns (NounsDAOProposals.ProposalTxs memory txs) {
        txs.targets = new address[](1);
        txs.targets[0] = target;
        txs.values = new uint256[](1);
        txs.values[0] = value;
        txs.signatures = new string[](1);
        txs.signatures[0] = signature;
        txs.calldatas = new bytes[](1);
        txs.calldatas[0] = data;
    }

    function propose(NounsDAOProposals.ProposalTxs memory txs) internal returns (uint256 proposalId) {
        return propose(proposer, txs);
    }

    function propose(
        address _proposer,
        NounsDAOProposals.ProposalTxs memory txs
    ) internal returns (uint256 proposalId) {
        NounsTokenLike nouns = daoProxy.nouns();
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = nouns.tokenOfOwnerByIndex(_proposer, 0);

        return propose(_proposer, tokenIds, txs);
    }

    function propose(
        address _proposer,
        uint256[] memory tokenIds,
        NounsDAOProposals.ProposalTxs memory txs
    ) internal returns (uint256 proposalId) {
        vm.prank(_proposer);
        proposalId = daoProxy.propose(tokenIds, txs.targets, txs.values, txs.signatures, txs.calldatas, 'my proposal');
    }

    function propose(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data
    ) internal returns (uint256 proposalId) {
        return propose(proposer, target, value, signature, data);
    }

    function propose(
        address _proposer,
        address target,
        uint256 value,
        string memory signature,
        bytes memory data
    ) internal returns (uint256 proposalId) {
        NounsTokenLike nouns = daoProxy.nouns();
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = nouns.tokenOfOwnerByIndex(_proposer, 0);

        return propose(_proposer, tokenIds, target, value, signature, data);
    }

    function propose(
        address _proposer,
        uint256[] memory tokenIds,
        address target,
        uint256 value,
        string memory signature,
        bytes memory data
    ) internal returns (uint256 proposalId) {
        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory values = new uint256[](1);
        values[0] = value;
        string[] memory signatures = new string[](1);
        signatures[0] = signature;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = data;

        vm.prank(_proposer);
        proposalId = daoProxy.propose(tokenIds, targets, values, signatures, calldatas, 'my proposal');
    }

    function mint(address to, uint256 amount) internal {
        vm.startPrank(minter);
        for (uint256 i = 0; i < amount; i++) {
            uint256 tokenId = nounsToken.mint();
            nounsToken.transferFrom(minter, to, tokenId);
        }
        vm.stopPrank();
        vm.roll(block.number + 1);
    }

    function startVotingPeriod() internal {
        vm.roll(block.number + daoProxy.votingDelay() + 1);
    }

    function endVotingPeriod() internal {
        vm.roll(block.number + daoProxy.votingDelay() + daoProxy.votingPeriod() + 1);
    }

    function vote(address voter, uint256 proposalId, uint8 support) internal {
        vm.startPrank(voter);
        daoProxy.castRefundableVote(voter.allVotesOf(daoProxy), proposalId, support);
        vm.stopPrank();
    }

    function voteWithReason(address voter, uint256 proposalId, uint8 support, string memory reason) internal {
        vm.startPrank(voter);
        daoProxy.castRefundableVoteWithReason(voter.allVotesOf(daoProxy), proposalId, support, reason);
        vm.stopPrank();
    }

    function deployForkDAOProxy() internal returns (INounsDAOLogic) {
        (address treasuryAddress, address tokenAddress, address daoAddress) = _deployForkDAO();
        timelock = NounsDAOExecutor(payable(treasuryAddress));
        nounsToken = NounsToken(tokenAddress);
        minter = nounsToken.minter();

        INounsDAOLogic dao = INounsDAOLogic(daoAddress);

        vm.startPrank(address(dao.timelock()));
        dao._setVotingPeriod(votingPeriod);
        dao._setVotingDelay(votingDelay);
        dao._setProposalThresholdBPS(proposalThresholdBPS);
        DAOLogicFork(address(dao))._setQuorumVotesBPS(1000);
        vm.stopPrank();

        vm.warp(INounsTokenForkLike(tokenAddress).forkingPeriodEndTimestamp());

        return INounsDAOLogic(daoAddress);
    }
}
