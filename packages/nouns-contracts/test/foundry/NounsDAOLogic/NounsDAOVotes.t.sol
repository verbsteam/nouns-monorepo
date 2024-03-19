// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import 'forge-std/Test.sol';
import { NounsDAOLogicBaseTest } from './NounsDAOLogicBaseTest.sol';
import { NounsDAOVotes } from '../../../contracts/governance/NounsDAOVotes.sol';
import { NounsDAOTypes } from '../../../contracts/governance/NounsDAOInterfaces.sol';
import { NounDelegationToken } from '../../../contracts/governance/NounDelegationToken.sol';
import { NounsDAOProposals } from '../../../contracts/governance/NounsDAOProposals.sol';

contract NounsDAOLogicVotesBaseTest is NounsDAOLogicBaseTest {
    address proposer = makeAddr('proposer');
    address voter = makeAddr('voter');
    uint256 proposalId;
    NounsDAOProposals.ProposalTxs proposalTxs;
    uint256[] proposerTokenIds;
    uint256[] voterTokenIds;

    function setUp() public virtual override {
        super.setUp();

        proposerTokenIds.push(mintTo(proposer));
        proposerTokenIds.push(mintTo(proposer));
        voterTokenIds.push(mintTo(voter));

        assertTrue(nounsToken.getCurrentVotes(proposer) > dao.proposalThreshold());
        proposalTxs = makeTxs(proposer, 0.01 ether, '', '');
        proposalId = propose(proposer, proposerTokenIds, proposalTxs, '', 0);
    }
}

contract NounsDAOLogicVotesTest is NounsDAOLogicVotesBaseTest {
    function setUp() public override {
        super.setUp();
    }

    function test_duringObjectionPeriod_givenForVote_reverts() public {
        // go into last minute
        vm.roll(
            block.number +
                dao.proposalUpdatablePeriodInBlocks() +
                dao.votingDelay() +
                dao.votingPeriod() -
                dao.lastMinuteWindowInBlocks() +
                1
        );

        // trigger objection period
        vm.prank(proposer);
        dao.castRefundableVote(proposerTokenIds, proposalId, 1);

        // go into objection period
        vm.roll(block.number + dao.lastMinuteWindowInBlocks());
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.ObjectionPeriod);

        vm.expectRevert(NounsDAOVotes.CanOnlyVoteAgainstDuringObjectionPeriod.selector);
        vm.prank(voter);
        dao.castRefundableVote(voterTokenIds, proposalId, 1);
    }

    function test_givenStateUpdatable_reverts() public {
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.Updatable);

        vm.expectRevert('NounsDAO::castVoteInternal: voting is closed');
        vm.prank(voter);
        dao.castRefundableVote(voterTokenIds, proposalId, 1);
    }

    function test_givenStatePending_reverts() public {
        vm.roll(block.number + dao.proposalUpdatablePeriodInBlocks() + 1);
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.Pending);

        vm.expectRevert('NounsDAO::castVoteInternal: voting is closed');
        vm.prank(voter);
        dao.castRefundableVote(voterTokenIds, proposalId, 1);
    }

    function test_givenStateDefeated_reverts() public {
        vm.roll(block.number + dao.proposalUpdatablePeriodInBlocks() + dao.votingDelay() + dao.votingPeriod() + 1);
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.Defeated);

        vm.expectRevert('NounsDAO::castVoteInternal: voting is closed');
        vm.prank(voter);
        dao.castRefundableVote(voterTokenIds, proposalId, 1);
    }

    function test_givenStateSucceeded_reverts() public {
        vm.roll(block.number + dao.proposalUpdatablePeriodInBlocks() + dao.votingDelay() + 1);
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.Active);

        vm.prank(voter);
        dao.castRefundableVote(voterTokenIds, proposalId, 1);

        vm.roll(block.number + dao.votingPeriod());
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.Succeeded);

        vm.expectRevert('NounsDAO::castVoteInternal: voting is closed');
        vm.prank(voter);
        dao.castRefundableVote(voterTokenIds, proposalId, 1);
    }

    function test_givenStateQueued_reverts() public {
        // Get the proposal to succeeded state
        vm.roll(block.number + dao.proposalUpdatablePeriodInBlocks() + dao.votingDelay() + 1);
        vm.prank(voter);
        dao.castRefundableVote(voterTokenIds, proposalId, 1);
        vm.roll(block.number + dao.votingPeriod());

        dao.queue(proposalId, proposalTxs.targets, proposalTxs.values, proposalTxs.signatures, proposalTxs.calldatas);

        vm.expectRevert('NounsDAO::castVoteInternal: voting is closed');
        vm.prank(proposer);
        dao.castRefundableVote(proposerTokenIds, proposalId, 1);
    }
}

contract NounsDAOLogicVotes_ActiveState_Test is NounsDAOLogicVotesBaseTest {
    function setUp() public override {
        super.setUp();

        vm.roll(block.number + dao.proposalUpdatablePeriodInBlocks() + dao.votingDelay() + 1);
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.Active);
    }

    function test_givenSameVoterVotingTwiceWithDifferentTokens_works() public {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = proposerTokenIds[0];
        vm.prank(proposer);
        dao.castRefundableVote(tokenIds, proposalId, 1);
        assertEq(dao.proposalsV3(proposalId).forVotes, 1);
        assertEq(dao.proposalsV3(proposalId).againstVotes, 0);

        tokenIds[0] = proposerTokenIds[1];
        vm.prank(proposer);
        dao.castRefundableVote(tokenIds, proposalId, 0);
        assertEq(dao.proposalsV3(proposalId).forVotes, 1);
        assertEq(dao.proposalsV3(proposalId).againstVotes, 1);

        (bool hasVoted, uint8 support) = dao.votingReceipt(proposalId, proposerTokenIds[0]);
        assertTrue(hasVoted);
        assertEq(support, 1);

        (hasVoted, support) = dao.votingReceipt(proposalId, proposerTokenIds[1]);
        assertTrue(hasVoted);
        assertEq(support, 0);
    }

    function test_givenSameTokensVotingTwice_reverts() public {
        vm.prank(proposer);
        dao.castRefundableVote(proposerTokenIds, proposalId, 1);

        vm.expectRevert('NounsDAO::castVoteDuringVotingPeriodInternal: token already voted');
        vm.prank(proposer);
        dao.castRefundableVote(proposerTokenIds, proposalId, 1);
    }

    function test_givenTokenTransferAtCurrentBlock_reverts() public {
        // Minting without advancing the block in order to hit flashloan protection
        vm.startPrank(minter);
        uint256 tokenId = nounsToken.mint();
        nounsToken.transferFrom(minter, proposer, tokenId);
        vm.stopPrank();

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        vm.expectRevert('cannot use voting power updated in the current block');
        vm.prank(proposer);
        dao.castRefundableVote(tokenIds, proposalId, 1);
    }

    function test_givenDelegationTokenTransferAtCurrentBlock_reverts() public {
        NounDelegationToken dt = NounDelegationToken(dao.delegationToken());
        address delegate = makeAddr('delegate');
        uint256 tokenId = proposerTokenIds[0];
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        vm.prank(proposer);
        dt.mint(delegate, tokenId);

        vm.expectRevert('cannot use voting power updated in the current block');
        vm.prank(delegate);
        dao.castRefundableVote(tokenIds, proposalId, 1);
    }

    function test_givenZeroVotes_emitsEvent() public {
        uint256[] memory tokenIds = new uint256[](0);

        vm.expectEmit(true, true, true, true);
        emit NounsDAOVotes.VoteCast(proposer, tokenIds, proposalId, 1, tokenIds.length, '');

        vm.prank(proposer);
        dao.castRefundableVote(tokenIds, proposalId, 1);
    }
}
