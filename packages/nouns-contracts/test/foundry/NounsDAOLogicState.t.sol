// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import 'forge-std/Test.sol';
import { INounsDAOLogic } from '../../contracts/interfaces/INounsDAOLogic.sol';
import { NounsDAOTypes } from '../../contracts/governance/NounsDAOInterfaces.sol';
import { NounsDescriptorV2 } from '../../contracts/NounsDescriptorV2.sol';
import { NounsToken } from '../../contracts/NounsToken.sol';
import { NounsSeeder } from '../../contracts/NounsSeeder.sol';
import { IProxyRegistry } from '../../contracts/external/opensea/IProxyRegistry.sol';
import { NounsDAOExecutor } from '../../contracts/governance/NounsDAOExecutor.sol';
import { NounsDAOLogicSharedBaseTest } from './helpers/NounsDAOLogicSharedBase.t.sol';
import { DelegationHelpers } from './helpers/DelegationHelpers.sol';
import { NounsDAOProposals } from '../../contracts/governance/NounsDAOProposals.sol';

abstract contract NounsDAOLogicStateBaseTest is NounsDAOLogicSharedBaseTest {
    address forVoter;
    address againstVoter;

    uint256[] forVoterTokens;
    uint256[] againstVoterTokens;

    function setUp() public override {
        super.setUp();

        mint(proposer, 1);
        vm.roll(block.number + 1);

        forVoter = utils.getNextUserAddress();
        againstVoter = utils.getNextUserAddress();
    }

    function testRevertsGivenProposalIdThatDoesntExist() public {
        uint256 proposalId = propose(address(0x1234), 100, '', '');
        vm.expectRevert('NounsDAO::state: invalid proposal id');
        daoProxy.state(proposalId + 1);
    }

    function testPendingGivenProposalJustCreated() public {
        uint256 proposalId = propose(address(0x1234), 100, '', '');
        uint256 state = uint256(INounsDAOLogic(payable(address(daoProxy))).state(proposalId));

        if (daoVersion() < 3) {
            assertEq(state, uint256(NounsDAOTypes.ProposalState.Pending));
        } else {
            assertEq(state, uint256(NounsDAOTypes.ProposalState.Updatable));
        }
    }

    function testActiveGivenProposalPastVotingDelay() public {
        uint256 proposalId = propose(address(0x1234), 100, '', '');
        vm.roll(block.number + daoProxy.votingDelay() + 1);
        assertTrue(daoProxy.state(proposalId) == NounsDAOTypes.ProposalState.Active);
    }

    function testCanceledGivenCanceledProposal() public {
        NounsDAOProposals.ProposalTxs memory txs = makeTxs(address(0x1234), 100, '', '');
        uint256 proposalId = propose(txs);
        vm.prank(proposer);
        daoProxy.cancel(proposalId);

        assertTrue(daoProxy.state(proposalId) == NounsDAOTypes.ProposalState.Canceled);
    }

    function testDefeatedByRunningOutOfTime() public {
        uint256 proposalId = propose(address(0x1234), 100, '', '');
        vm.roll(block.number + daoProxy.votingDelay() + daoProxy.votingPeriod() + 1);

        assertTrue(daoProxy.state(proposalId) == NounsDAOTypes.ProposalState.Defeated);
    }

    function testDefeatedByVotingAgainst() public {
        forVoterTokens = mint(forVoter, 3);
        againstVoterTokens = mint(againstVoter, 3);

        uint256 proposalId = propose(address(0x1234), 100, '', '');
        startVotingPeriod();
        vote(forVoter, forVoterTokens, proposalId, 1);
        vote(againstVoter, againstVoterTokens, proposalId, 0);
        endVotingPeriod();

        assertTrue(daoProxy.state(proposalId) == NounsDAOTypes.ProposalState.Defeated);
    }

    function testQueued() public {
        forVoterTokens = mint(forVoter, 4);
        againstVoterTokens = mint(againstVoter, 3);

        NounsDAOProposals.ProposalTxs memory txs = makeTxs(address(0x1234), 100, '', '');
        uint256 proposalId = propose(txs);
        startVotingPeriod();
        vote(forVoter, forVoterTokens, proposalId, 1);
        vote(againstVoter, againstVoterTokens, proposalId, 0);
        endVotingPeriod();
        vm.roll(block.number + 1);

        assertTrue(daoProxy.state(proposalId) == NounsDAOTypes.ProposalState.Queued);
    }

    function testExpired() public {
        forVoterTokens = mint(forVoter, 4);
        againstVoterTokens = mint(againstVoter, 3);

        NounsDAOProposals.ProposalTxs memory txs = makeTxs(address(0x1234), 100, '', '');

        uint256 proposalId = propose(txs);
        startVotingPeriod();
        vote(forVoter, forVoterTokens, proposalId, 1);
        vote(againstVoter, againstVoterTokens, proposalId, 0);
        vm.roll(daoProxy.proposalsV3(proposalId).eta + daoProxy.gracePeriod() + 1);

        assertTrue(daoProxy.state(proposalId) == NounsDAOTypes.ProposalState.Expired);
    }

    function testExecutedOnlyAfterQueued() public {
        forVoterTokens = mint(forVoter, 4);

        NounsDAOProposals.ProposalTxs memory txs = makeTxs(address(0x1234), 100, '', '');

        uint256 proposalId = propose(address(0x1234), 100, '', '');
        vm.expectRevert('NounsDAO::execute: proposal can only be executed if it is queued');
        daoProxy.execute(proposalId, txs.targets, txs.values, txs.signatures, txs.calldatas);

        startVotingPeriod();
        vote(forVoter, forVoterTokens, proposalId, 1);
        vm.expectRevert('NounsDAO::execute: proposal can only be executed if it is queued');
        daoProxy.execute(proposalId, txs.targets, txs.values, txs.signatures, txs.calldatas);

        endVotingPeriod();
        vm.expectRevert('NounsDAO::execute: proposal can only be executed at or after ETA');
        daoProxy.execute(proposalId, txs.targets, txs.values, txs.signatures, txs.calldatas);

        vm.roll(daoProxy.proposalsV3(proposalId).eta);
        vm.deal(address(timelock), 100);
        daoProxy.execute(proposalId, txs.targets, txs.values, txs.signatures, txs.calldatas);

        assertTrue(daoProxy.state(proposalId) == NounsDAOTypes.ProposalState.Executed);

        vm.roll(daoProxy.proposalsV3(proposalId).eta + daoProxy.gracePeriod() + 1);
        assertTrue(daoProxy.state(proposalId) == NounsDAOTypes.ProposalState.Executed);
    }
}

// TODO bring back fork tests. Had to remove them because of the API change with Nouns Gov
// contract NounsDAOLogicV1ForkStateTest is NounsDAOLogicStateBaseTest {
//     function daoVersion() internal pure override returns (uint256) {
//         return 1;
//     }

//     function deployDAOProxy(address, address, address) internal override returns (INounsDAOLogic) {
//         return INounsDAOLogic(address(deployForkDAOProxy()));
//     }
// }

contract NounsDAOLogicV3StateTest is NounsDAOLogicStateBaseTest {
    function deployDAOProxy(
        address timelock,
        address nounsToken,
        address vetoer
    ) internal override returns (INounsDAOLogic) {
        return _createDAOV3Proxy(timelock, nounsToken, vetoer);
    }

    function daoVersion() internal pure override returns (uint256) {
        return 3;
    }
}
