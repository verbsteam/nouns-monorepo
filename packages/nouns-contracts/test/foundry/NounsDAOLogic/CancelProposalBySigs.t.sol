// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import 'forge-std/Test.sol';
import { NounsDAOLogicBaseTest } from './NounsDAOLogicBaseTest.sol';
import { NounsDAOTypes } from '../../../contracts/governance/NounsDAOInterfaces.sol';
import { NounsDAOProposals } from '../../../contracts/governance/NounsDAOProposals.sol';
import { DelegationHelpers } from '../helpers/DelegationHelpers.sol';

abstract contract ZeroState is NounsDAOLogicBaseTest {
    using DelegationHelpers for address;

    address proposer = makeAddr('proposer');
    address rando = makeAddr('rando');
    address otherUser = makeAddr('otherUser');
    uint256 proposalId;
    NounsDAOProposals.ProposalTxs proposalTxs;
    address signerWithVote;
    uint256 signerWithVotePK;
    address target = makeAddr('target');
    uint256[] tokenIds;

    event ProposalCanceled(uint256 id);
}

abstract contract ProposalUpdatableState is ZeroState {
    using DelegationHelpers for address;

    function setUp() public virtual override {
        super.setUp();

        (signerWithVote, signerWithVotePK) = makeAddrAndKey('signerWithVote');

        vm.startPrank(minter);
        nounsToken.mint();
        nounsToken.transferFrom(minter, signerWithVote, 1);
        vm.roll(block.number + 1);
        vm.stopPrank();
        tokenIds = [1];

        proposalTxs = makeTxs(makeAddr('target'), 0, '', '');
        uint256 expirationTimestamp = block.timestamp + 1234;
        NounsDAOTypes.ProposerSignature[] memory proposerSignatures = new NounsDAOTypes.ProposerSignature[](1);
        proposerSignatures[0] = NounsDAOTypes.ProposerSignature(
            signProposal(proposer, signerWithVotePK, proposalTxs, 'description', expirationTimestamp, address(dao)),
            signerWithVote,
            expirationTimestamp,
            signerWithVote.allVotesOf(dao)
        );

        vm.startPrank(proposer);
        proposalId = dao.proposeBySigs(
            proposer.allVotesOf(dao),
            proposerSignatures,
            proposalTxs.targets,
            proposalTxs.values,
            proposalTxs.signatures,
            proposalTxs.calldatas,
            'description'
        );
        vm.stopPrank();

        vm.roll(block.number + 1);

        assertEq(uint256(dao.state(proposalId)), uint256(NounsDAOTypes.ProposalState.Updatable));
    }
}

abstract contract IsCancellable is ZeroState {
    function test_proposerCanCancel() public {
        vm.expectEmit(true, true, true, true);
        emit ProposalCanceled(proposalId);
        vm.prank(proposer);
        dao.cancel(proposalId);
        assertEq(uint256(dao.state(proposalId)), uint256(NounsDAOTypes.ProposalState.Canceled));
    }

    function test_randoCantCancel() public {
        vm.expectRevert(bytes('NounsDAO::cancel: only proposer or signers can cancel'));
        vm.prank(rando);
        dao.cancel(proposalId);
    }
}

abstract contract IsNotCancellable is ZeroState {
    function test_proposerCantCancel() public {
        vm.expectRevert(NounsDAOProposals.CantCancelProposalAtFinalState.selector);
        vm.prank(proposer);
        dao.cancel(proposalId);
    }
}

contract ProposalUpdatableStateTest is ProposalUpdatableState, IsCancellable {
    function setUp() public override(ProposalUpdatableState, NounsDAOLogicBaseTest) {
        ProposalUpdatableState.setUp();
    }
}

abstract contract ProposalPendingState is ProposalUpdatableState {
    function setUp() public virtual override {
        super.setUp();

        vm.roll(dao.proposalsV3(proposalId).updatePeriodEndBlock + 1);
        assertEq(uint256(dao.state(proposalId)), uint256(NounsDAOTypes.ProposalState.Pending));
    }
}

contract ProposalPendingStateTest is ProposalPendingState, IsCancellable {
    function setUp() public override(ProposalPendingState, NounsDAOLogicBaseTest) {
        ProposalPendingState.setUp();
    }
}

abstract contract ProposalActiveState is ProposalPendingState {
    function setUp() public virtual override {
        super.setUp();

        vm.roll(dao.proposalsV3(proposalId).startBlock + 1);
        assertEq(uint256(dao.state(proposalId)), uint256(NounsDAOTypes.ProposalState.Active));
    }
}

contract ProposalActiveStateTest is ProposalActiveState, IsCancellable {
    function setUp() public override(ProposalActiveState, NounsDAOLogicBaseTest) {
        ProposalActiveState.setUp();
    }
}

abstract contract ProposalObjectionPeriodState is ProposalActiveState {
    function setUp() public virtual override {
        super.setUp();

        vm.roll(dao.proposalsV3(proposalId).endBlock - 1);
        vm.prank(signerWithVote);
        dao.castRefundableVote(tokenIds, proposalId, 1);

        vm.roll(dao.proposalsV3(proposalId).endBlock + 1);
        assertEq(uint256(dao.state(proposalId)), uint256(NounsDAOTypes.ProposalState.ObjectionPeriod));
    }
}

contract ProposalObjectionPeriodStateTest is ProposalObjectionPeriodState, IsCancellable {
    function setUp() public override(ProposalObjectionPeriodState, NounsDAOLogicBaseTest) {
        ProposalObjectionPeriodState.setUp();
    }
}

abstract contract ProposalQueuedState is ProposalActiveState {
    function setUp() public virtual override {
        super.setUp();

        vm.prank(signerWithVote);
        dao.castRefundableVote(tokenIds, proposalId, 1);

        vm.roll(dao.proposalsV3(proposalId).endBlock + 1);
        assertEq(uint256(dao.state(proposalId)), uint256(NounsDAOTypes.ProposalState.Queued));
    }
}

contract ProposalQueuedStateTest is ProposalQueuedState, IsCancellable {
    function setUp() public override(ProposalQueuedState, NounsDAOLogicBaseTest) {
        ProposalQueuedState.setUp();
    }
}

abstract contract ProposalExecutedState is ProposalQueuedState {
    function setUp() public virtual override {
        super.setUp();

        vm.roll(dao.proposalsV3(proposalId).eta + 1);
        dao.execute(proposalId, proposalTxs.targets, proposalTxs.values, proposalTxs.signatures, proposalTxs.calldatas);
        assertEq(uint256(dao.state(proposalId)), uint256(NounsDAOTypes.ProposalState.Executed));
    }
}

contract ProposalExecutedStateTest is ProposalExecutedState, IsNotCancellable {
    function setUp() public override(ProposalExecutedState, NounsDAOLogicBaseTest) {
        ProposalExecutedState.setUp();
    }
}

abstract contract ProposalDefeatedState is ProposalActiveState {
    function setUp() public virtual override {
        super.setUp();

        vm.roll(dao.proposalsV3(proposalId).endBlock + 1);
        assertEq(uint256(dao.state(proposalId)), uint256(NounsDAOTypes.ProposalState.Defeated));
    }
}

contract ProposalDefeatedStateTest is ProposalDefeatedState, IsNotCancellable {
    function setUp() public override(ProposalDefeatedState, NounsDAOLogicBaseTest) {
        ProposalDefeatedState.setUp();
    }
}
