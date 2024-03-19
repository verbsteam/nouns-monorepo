// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import 'forge-std/Test.sol';
import { NounsDAOLogicBaseTest } from './NounsDAOLogicBaseTest.sol';
import { DeployUtils } from '../helpers/DeployUtils.sol';
import { SigUtils, ERC1271Stub } from '../helpers/SigUtils.sol';
import { NounsDAOProposals } from '../../../contracts/governance/NounsDAOProposals.sol';
import { NounsDAOProxyV3 } from '../../../contracts/governance/NounsDAOProxyV3.sol';
import { NounsDAOTypes, NounsDAOEventsV3 } from '../../../contracts/governance/NounsDAOInterfaces.sol';
import { NounsToken } from '../../../contracts/NounsToken.sol';
import { NounsSeeder } from '../../../contracts/NounsSeeder.sol';
import { IProxyRegistry } from '../../../contracts/external/opensea/IProxyRegistry.sol';
import { NounsDAOExecutor } from '../../../contracts/governance/NounsDAOExecutor.sol';

abstract contract UpdateProposalBaseTest is NounsDAOLogicBaseTest {
    address proposer = makeAddr('proposer');
    uint256 proposalId;
    NounsDAOProposals.ProposalTxs proposalTxs;
    uint256[] tokenIds;

    function setUp() public override {
        super.setUp();

        // mint 1 noun to proposer
        vm.startPrank(minter);
        nounsToken.mint();
        nounsToken.transferFrom(minter, proposer, 1);
        vm.roll(block.number + 1);
        vm.stopPrank();
        tokenIds = [1];

        proposalTxs = makeTxs(makeAddr('target'), 0, '', '');
        proposalId = propose(proposer, tokenIds, proposalTxs, '', 0);
        vm.roll(block.number + 1);
    }
}

contract UpdateProposalPermissionsTest is UpdateProposalBaseTest {
    function test_givenProposalDoesntExist_reverts() public {
        vm.expectRevert('NounsDAO::state: invalid proposal id');
        updateProposal(proposer, proposalId + 1, makeAddr('target'), 0, '', '', '');

        vm.expectRevert('NounsDAO::state: invalid proposal id');
        updateProposalTransactions(proposer, proposalId + 1, makeAddr('target'), 0, '', '', '');

        vm.expectRevert('NounsDAO::state: invalid proposal id');
        vm.prank(proposer);
        dao.updateProposalDescription(proposalId + 1, '', '');
    }

    function test_givenMsgSenderNotProposer_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.OnlyProposerCanEdit.selector));
        updateProposal(makeAddr('not proposer'), proposalId, makeAddr('target'), 0, '', '', '');

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.OnlyProposerCanEdit.selector));
        updateProposalTransactions(makeAddr('not proposer'), proposalId, makeAddr('target'), 0, '', '', '');

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.OnlyProposerCanEdit.selector));
        vm.prank(makeAddr('not proposer'));
        dao.updateProposalDescription(proposalId, '', '');
    }

    function test_givenPropWithSigners_reverts() public {
        vm.startPrank(proposer);
        dao.cancel(proposalId, proposalTxs.targets, proposalTxs.values, proposalTxs.signatures, proposalTxs.calldatas);

        (address signer, uint256 signerPK) = makeAddrAndKey('signer');
        nounsToken.transferFrom(proposer, signer, 1);
        vm.stopPrank();
        vm.roll(block.number + 1);

        uint256 expirationTimestamp = block.timestamp + 1234;
        uint256 propId = proposeBySigs(
            proposer,
            signer,
            signerPK,
            makeTxs(makeAddr('target'), 0, '', ''),
            'description',
            expirationTimestamp
        );

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.ProposerCannotUpdateProposalWithSigners.selector));
        updateProposal(proposer, propId, makeAddr('target'), 1, '', '', 'description');

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.ProposerCannotUpdateProposalWithSigners.selector));
        updateProposalTransactions(proposer, propId, makeAddr('target'), 0, '', '', '');

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.ProposerCannotUpdateProposalWithSigners.selector));
        vm.prank(proposer);
        dao.updateProposalDescription(propId, '', '');
    }

    function test_givenStatesPendingActiveSucceededQueuedAndExecuted_reverts() public {
        // Pending
        vm.roll(block.number + proposalUpdatablePeriodInBlocks);
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.Pending);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        updateProposal(proposer, proposalId, makeAddr('target'), 0, '', '', '');

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        updateProposalTransactions(proposer, proposalId, makeAddr('target'), 0, '', '', '');

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        vm.prank(proposer);
        dao.updateProposalDescription(proposalId, '', '');

        // Active
        vm.roll(block.number + VOTING_DELAY);
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.Active);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        updateProposal(proposer, proposalId, makeAddr('target'), 0, '', '', '');

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        updateProposalTransactions(proposer, proposalId, makeAddr('target'), 0, '', '', '');

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        vm.prank(proposer);
        dao.updateProposalDescription(proposalId, '', '');

        // Succeeded
        vm.prank(proposer);
        dao.castRefundableVote(tokenIds, proposalId, 1);
        vm.roll(block.number + VOTING_PERIOD);
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.Succeeded);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        updateProposal(proposer, proposalId, makeAddr('target'), 0, '', '', '');

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        updateProposalTransactions(proposer, proposalId, makeAddr('target'), 0, '', '', '');

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        vm.prank(proposer);
        dao.updateProposalDescription(proposalId, '', '');

        // Queued
        dao.queue(proposalId, proposalTxs.targets, proposalTxs.values, proposalTxs.signatures, proposalTxs.calldatas);
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.Queued);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        updateProposal(proposer, proposalId, makeAddr('target'), 0, '', '', '');

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        updateProposalTransactions(proposer, proposalId, makeAddr('target'), 0, '', '', '');

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        vm.prank(proposer);
        dao.updateProposalDescription(proposalId, '', '');

        // Executed
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        dao.execute(proposalId, proposalTxs.targets, proposalTxs.values, proposalTxs.signatures, proposalTxs.calldatas);
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.Executed);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        updateProposal(proposer, proposalId, makeAddr('target'), 0, '', '', '');

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        updateProposalTransactions(proposer, proposalId, makeAddr('target'), 0, '', '', '');

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        vm.prank(proposer);
        dao.updateProposalDescription(proposalId, '', '');
    }

    function test_givenStateCanceled_reverts() public {
        vm.prank(proposer);
        dao.cancel(proposalId, proposalTxs.targets, proposalTxs.values, proposalTxs.signatures, proposalTxs.calldatas);
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.Canceled);

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        updateProposal(proposer, proposalId, makeAddr('target'), 0, '', '', '');

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        updateProposalTransactions(proposer, proposalId, makeAddr('target'), 0, '', '', '');

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        vm.prank(proposer);
        dao.updateProposalDescription(proposalId, '', '');
    }

    function test_givenStateDefeated_reverts() public {
        vm.roll(block.number + proposalUpdatablePeriodInBlocks + VOTING_DELAY);
        vm.prank(proposer);
        dao.castRefundableVote(tokenIds, proposalId, 0);
        vm.roll(block.number + VOTING_PERIOD);
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.Defeated);

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        updateProposal(proposer, proposalId, makeAddr('target'), 0, '', '', '');

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        updateProposalTransactions(proposer, proposalId, makeAddr('target'), 0, '', '', '');

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        vm.prank(proposer);
        dao.updateProposalDescription(proposalId, '', '');
    }

    function test_givenStateExpired_reverts() public {
        vm.roll(block.number + proposalUpdatablePeriodInBlocks + VOTING_DELAY);
        vm.prank(proposer);
        dao.castRefundableVote(tokenIds, proposalId, 1);
        vm.roll(block.number + VOTING_PERIOD);
        dao.queue(proposalId, proposalTxs.targets, proposalTxs.values, proposalTxs.signatures, proposalTxs.calldatas);
        vm.warp(block.timestamp + TIMELOCK_DELAY + timelock.GRACE_PERIOD());
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.Expired);

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        updateProposal(proposer, proposalId, makeAddr('target'), 0, '', '', '');

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        updateProposalTransactions(proposer, proposalId, makeAddr('target'), 0, '', '', '');

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        vm.prank(proposer);
        dao.updateProposalDescription(proposalId, '', '');
    }

    function test_givenStateVetoed_reverts() public {
        vm.prank(vetoer);
        dao.veto(proposalId, proposalTxs.targets, proposalTxs.values, proposalTxs.signatures, proposalTxs.calldatas);
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.Vetoed);

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        updateProposal(proposer, proposalId, makeAddr('target'), 0, '', '', '');

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        updateProposalTransactions(proposer, proposalId, makeAddr('target'), 0, '', '', '');

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        vm.prank(proposer);
        dao.updateProposalDescription(proposalId, '', '');
    }

    function test_givenStateObjectionPeriod_reverts() public {
        vm.roll(
            block.number + proposalUpdatablePeriodInBlocks + VOTING_DELAY + VOTING_PERIOD - lastMinuteWindowInBlocks
        );
        vm.prank(proposer);
        dao.castRefundableVote(tokenIds, proposalId, 1);
        vm.roll(block.number + lastMinuteWindowInBlocks);
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.ObjectionPeriod);

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        updateProposal(proposer, proposalId, makeAddr('target'), 0, '', '', '');

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        updateProposalTransactions(proposer, proposalId, makeAddr('target'), 0, '', '', '');

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        vm.prank(proposer);
        dao.updateProposalDescription(proposalId, '', '');
    }
}

contract UpdateProposalTransactionsTest is UpdateProposalBaseTest {
    function test_proposalsV3GetterReturnsUpdatableEndBlock() public {
        assertEq(dao.proposalsV3(proposalId).updatePeriodEndBlock, block.number - 1 + proposalUpdatablePeriodInBlocks);
    }

    function test_givenNoTxs_reverts() public {
        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        string[] memory signatures = new string[](0);
        bytes[] memory calldatas = new bytes[](0);

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.MustProvideActions.selector));
        vm.prank(proposer);
        dao.updateProposal(proposalId, targets, values, signatures, calldatas, '', '');

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.MustProvideActions.selector));
        vm.prank(proposer);
        dao.updateProposalTransactions(proposalId, targets, values, signatures, calldatas, '');
    }

    function test_givenTooManyTxs_reverts() public {
        address[] memory targets = new address[](11);
        uint256[] memory values = new uint256[](11);
        string[] memory signatures = new string[](11);
        bytes[] memory calldatas = new bytes[](11);
        for (uint256 i = 0; i < 11; ++i) {
            targets[i] = makeAddr('target');
            values[i] = i;
            signatures[i] = '';
            calldatas[i] = '';
        }

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.TooManyActions.selector));
        vm.prank(proposer);
        dao.updateProposal(proposalId, targets, values, signatures, calldatas, '', '');

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.TooManyActions.selector));
        vm.prank(proposer);
        dao.updateProposalTransactions(proposalId, targets, values, signatures, calldatas, '');
    }

    function test_givenTxsWithArityMismatch_reverts() public {
        address[] memory targets = new address[](1);
        targets[0] = makeAddr('target');
        uint256[] memory values = new uint256[](0);
        string[] memory signatures = new string[](0);
        bytes[] memory calldatas = new bytes[](0);

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.ProposalInfoArityMismatch.selector));
        vm.prank(proposer);
        dao.updateProposal(proposalId, targets, values, signatures, calldatas, '', '');

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.ProposalInfoArityMismatch.selector));
        vm.prank(proposer);
        dao.updateProposalTransactions(proposalId, targets, values, signatures, calldatas, '');
    }

    function test_givenStateUpdatable_updateProposal_updatesTxsAndEmitsEvent() public {
        bytes32 txsHashBefore = dao.proposalsV3(proposalId).txsHash;
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.Updatable);

        NounsDAOProposals.ProposalTxs memory txsAfter = makeTxs(
            makeAddr('targetAfter'),
            1,
            'signatureAfter',
            'dataAfter'
        );
        bytes32 expectedHashAfter = NounsDAOProposals.hashProposal(txsAfter);

        vm.expectEmit(true, true, true, true);
        emit NounsDAOEventsV3.ProposalUpdated(
            proposalId,
            proposer,
            txsAfter.targets,
            txsAfter.values,
            txsAfter.signatures,
            txsAfter.calldatas,
            expectedHashAfter,
            'descriptionAfter',
            'some update message'
        );
        updateProposal(
            proposer,
            proposalId,
            txsAfter.targets[0],
            txsAfter.values[0],
            txsAfter.signatures[0],
            txsAfter.calldatas[0],
            'descriptionAfter',
            'some update message'
        );

        bytes32 txsHashAfter = dao.proposalsV3(proposalId).txsHash;

        assertNotEq(txsHashBefore, txsHashAfter);
        assertEq(txsHashAfter, expectedHashAfter);
    }

    function test_givenStateUpdatable_updateProposalTransactions_updatesTxsAndEmitsEvent() public {
        bytes32 txsHashBefore = dao.proposalsV3(proposalId).txsHash;
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.Updatable);

        NounsDAOProposals.ProposalTxs memory txsAfter = makeTxs(
            makeAddr('targetAfter'),
            1,
            'signatureAfter',
            'dataAfter'
        );
        bytes32 expectedHashAfter = NounsDAOProposals.hashProposal(txsAfter);

        vm.expectEmit(true, true, true, true);
        emit NounsDAOEventsV3.ProposalTransactionsUpdated(
            proposalId,
            proposer,
            txsAfter.targets,
            txsAfter.values,
            txsAfter.signatures,
            txsAfter.calldatas,
            expectedHashAfter,
            'some update message'
        );
        updateProposalTransactions(
            proposer,
            proposalId,
            txsAfter.targets[0],
            txsAfter.values[0],
            txsAfter.signatures[0],
            txsAfter.calldatas[0],
            'some update message'
        );

        bytes32 txsHashAfter = dao.proposalsV3(proposalId).txsHash;

        assertNotEq(txsHashBefore, txsHashAfter);
        assertEq(txsHashAfter, expectedHashAfter);
    }
}

contract UpdateProposalDescriptionTest is UpdateProposalBaseTest {
    function test_givenStateUpdatable_updatesDescriptionAndEmitsEvent() public {
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.Updatable);

        vm.expectEmit(true, true, true, true);
        emit NounsDAOEventsV3.ProposalDescriptionUpdated(proposalId, proposer, 'new description', 'update message');
        vm.prank(proposer);
        dao.updateProposalDescription(proposalId, 'new description', 'update message');
    }
}
