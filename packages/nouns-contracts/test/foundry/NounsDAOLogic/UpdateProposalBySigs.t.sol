// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import 'forge-std/Test.sol';
import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';
import { NounsDAOLogicBaseTest } from './NounsDAOLogicBaseTest.sol';
import { DeployUtils } from '../helpers/DeployUtils.sol';
import { SigUtils, ERC1271Stub } from '../helpers/SigUtils.sol';
import { NounsDAOProposals } from '../../../contracts/governance/NounsDAOProposals.sol';
import { NounsDAOProxyV3 } from '../../../contracts/governance/NounsDAOProxyV3.sol';
import { NounsDAOTypes } from '../../../contracts/governance/NounsDAOInterfaces.sol';
import { NounsToken } from '../../../contracts/NounsToken.sol';
import { NounsSeeder } from '../../../contracts/NounsSeeder.sol';
import { IProxyRegistry } from '../../../contracts/external/opensea/IProxyRegistry.sol';
import { NounsDAOExecutor } from '../../../contracts/governance/NounsDAOExecutor.sol';
import { NounDelegationToken } from '../../../contracts/governance/NounDelegationToken.sol';

contract UpdateProposalBySigsTest is NounsDAOLogicBaseTest {
    address proposer = makeAddr('proposerWithVote');
    address[] _signers;
    uint256[] _signerPKs;
    uint256[] signer0TokenIds;

    uint256 defaultExpirationTimestamp;
    uint256 proposalId;

    function setUp() public override {
        super.setUp();

        defaultExpirationTimestamp = block.timestamp + 1234;
        vm.startPrank(minter);
        for (uint256 i = 0; i < 8; ++i) {
            (address signer, uint256 signerPK) = makeAddrAndKey(string.concat('signerWithVote', Strings.toString(i)));
            _signers.push(signer);
            _signerPKs.push(signerPK);

            nounsToken.mint();
            nounsToken.transferFrom(minter, signer, i + 1);

            if (i == 0) {
                signer0TokenIds.push(i + 1);
            }
        }

        vm.roll(block.number + 1);
        vm.stopPrank();

        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = signersPKsExpirations();

        proposalId = proposeBySigs(
            proposer,
            signers,
            signerPKs,
            expirationTimestamps,
            makeTxs(makeAddr('target'), 0, '', ''),
            ''
        );
        vm.roll(block.number + 1);
    }

    function test_givenNoSigners_reverts() public {
        address[] memory signers = new address[](0);
        uint256[] memory signerPKs = new uint256[](0);
        uint256[] memory expirationTimestamps = new uint256[](0);

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.MustProvideSignatures.selector));
        updateProposalBySigs(
            proposalId,
            proposer,
            signers,
            signerPKs,
            expirationTimestamps,
            makeTxs(makeAddr('new target'), 0, '', ''),
            ''
        );
    }

    function test_givenMsgSenderNotProposer_reverts() public {
        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = signersPKsExpirations();
        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('new target'), 0, '', '');
        NounsDAOTypes.ProposerSignature[] memory sigs = makeUpdateProposalSigs(
            signers,
            signerPKs,
            expirationTimestamps,
            UpdateProposalParams(proposalId, proposer, txs, ''),
            address(dao)
        );

        vm.prank(makeAddr('not proposer'));
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.OnlyProposerCanEdit.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');
    }

    function test_givenSignerMismatch_tooFewSigners_reverts() public {
        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = fewerSignersPKsExpirations();
        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('new target'), 0, '', '');
        NounsDAOTypes.ProposerSignature[] memory sigs = makeUpdateProposalSigs(
            signers,
            signerPKs,
            expirationTimestamps,
            UpdateProposalParams(proposalId, proposer, txs, ''),
            address(dao)
        );

        vm.prank(proposer);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.SignerCountMismtach.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');
    }

    function test_givenSignerMismatch_tooManySigners_reverts() public {
        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = moreSignersPKsExpirations();
        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('new target'), 0, '', '');
        NounsDAOTypes.ProposerSignature[] memory sigs = makeUpdateProposalSigs(
            signers,
            signerPKs,
            expirationTimestamps,
            UpdateProposalParams(proposalId, proposer, txs, ''),
            address(dao)
        );

        vm.prank(proposer);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.SignerCountMismtach.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');
    }

    function test_givenSignerMismatch_sameNumberOneDifferentSigner_reverts() public {
        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = signersPKsExpirations();

        // Swap a signer
        signers[1] = _signers[_signers.length - 1];
        signerPKs[1] = _signerPKs[_signers.length - 1];

        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('new target'), 0, '', '');
        NounsDAOTypes.ProposerSignature[] memory sigs = makeUpdateProposalSigs(
            signers,
            signerPKs,
            expirationTimestamps,
            UpdateProposalParams(proposalId, proposer, txs, ''),
            address(dao)
        );

        vm.prank(proposer);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.OnlyProposerCanEdit.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');
    }

    function test_givenCanceledSig_reverts() public {
        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = signersPKsExpirations();

        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('new target'), 0, '', '');
        NounsDAOTypes.ProposerSignature[] memory sigs = makeUpdateProposalSigs(
            signers,
            signerPKs,
            expirationTimestamps,
            UpdateProposalParams(proposalId, proposer, txs, ''),
            address(dao)
        );

        vm.prank(sigs[1].signer);
        dao.cancelSig(sigs[1].sig);

        vm.prank(proposer);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.SignatureIsCancelled.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');
    }

    function test_givenExpireddSig_reverts() public {
        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = signersPKsExpirations();

        expirationTimestamps[1] = block.timestamp - 1;

        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('new target'), 0, '', '');
        NounsDAOTypes.ProposerSignature[] memory sigs = makeUpdateProposalSigs(
            signers,
            signerPKs,
            expirationTimestamps,
            UpdateProposalParams(proposalId, proposer, txs, ''),
            address(dao)
        );

        vm.prank(proposer);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.SignatureExpired.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');
    }

    function test_givenSigOnDifferentDescription_reverts() public {
        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = signersPKsExpirations();

        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('new target'), 0, '', '');
        NounsDAOTypes.ProposerSignature[] memory sigs = makeUpdateProposalSigs(
            signers,
            signerPKs,
            expirationTimestamps,
            UpdateProposalParams(proposalId, proposer, txs, 'different description'),
            address(dao)
        );

        vm.prank(proposer);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.InvalidSignature.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');
    }

    function test_givenSigOnDifferentTargets_reverts() public {
        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = signersPKsExpirations();

        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('new target'), 0, '', '');
        address[] memory updateTargets = txs.targets;

        // sign on differet new target
        address[] memory differentTargets = new address[](1);
        differentTargets[0] = makeAddr('different new target');
        txs.targets = differentTargets;
        NounsDAOTypes.ProposerSignature[] memory sigs = makeUpdateProposalSigs(
            signers,
            signerPKs,
            expirationTimestamps,
            UpdateProposalParams(proposalId, proposer, txs, ''),
            address(dao)
        );

        // set it back to the original new target
        txs.targets = updateTargets;
        vm.prank(proposer);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.InvalidSignature.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');
    }

    function test_givenSigOnDifferentValues_reverts() public {
        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = signersPKsExpirations();

        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('new target'), 0, '', '');
        uint256[] memory updateValues = txs.values;

        // sign on differet values
        uint256[] memory differentValues = new uint256[](1);
        differentValues[0] = updateValues[0] + 1234;
        txs.values = differentValues;
        NounsDAOTypes.ProposerSignature[] memory sigs = makeUpdateProposalSigs(
            signers,
            signerPKs,
            expirationTimestamps,
            UpdateProposalParams(proposalId, proposer, txs, ''),
            address(dao)
        );

        // set it back to the original update values
        txs.values = updateValues;
        vm.prank(proposer);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.InvalidSignature.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');
    }

    function test_givenSigOnDifferentSignatures_reverts() public {
        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = signersPKsExpirations();

        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('new target'), 0, '', '');
        string[] memory updateSignatures = txs.signatures;

        // sign on differet signatures
        string[] memory differentSignatures = new string[](1);
        differentSignatures[0] = 'different signature';
        txs.signatures = differentSignatures;
        NounsDAOTypes.ProposerSignature[] memory sigs = makeUpdateProposalSigs(
            signers,
            signerPKs,
            expirationTimestamps,
            UpdateProposalParams(proposalId, proposer, txs, ''),
            address(dao)
        );

        // set it back to the original update signatures
        txs.signatures = updateSignatures;
        vm.prank(proposer);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.InvalidSignature.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');
    }

    function test_givenSigOnDifferentCalldatas_reverts() public {
        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = signersPKsExpirations();

        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('new target'), 0, '', '');
        bytes[] memory updateCalldatas = txs.calldatas;

        // sign on differet calldatas
        bytes[] memory differentCalldatas = new bytes[](1);
        differentCalldatas[0] = 'different calldatas';
        txs.calldatas = differentCalldatas;
        NounsDAOTypes.ProposerSignature[] memory sigs = makeUpdateProposalSigs(
            signers,
            signerPKs,
            expirationTimestamps,
            UpdateProposalParams(proposalId, proposer, txs, ''),
            address(dao)
        );

        // set it back to the original update calldatas
        txs.calldatas = updateCalldatas;
        vm.prank(proposer);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.InvalidSignature.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');
    }

    function test_givenSigOnDifferentExpiration_reverts() public {
        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = signersPKsExpirations();

        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('new target'), 0, '', '');
        NounsDAOTypes.ProposerSignature[] memory sigs = makeUpdateProposalSigs(
            signers,
            signerPKs,
            expirationTimestamps,
            UpdateProposalParams(proposalId, proposer, txs, ''),
            address(dao)
        );

        sigs[1].expirationTimestamp = sigs[1].expirationTimestamp + 1234;

        vm.prank(proposer);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.InvalidSignature.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');
    }

    function test_givenSigOnDifferentSigner_reverts() public {
        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = signersPKsExpirations();

        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('new target'), 0, '', '');
        NounsDAOTypes.ProposerSignature[] memory sigs = makeUpdateProposalSigs(
            signers,
            signerPKs,
            expirationTimestamps,
            UpdateProposalParams(proposalId, proposer, txs, ''),
            address(dao)
        );

        sigs[1].signer = makeAddr('different signer');

        vm.prank(proposer);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.InvalidSignature.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');
    }

    function test_givenSigOnDifferentDomainName_reverts() public {
        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = signersPKsExpirations();

        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('new target'), 0, '', '');
        NounsDAOTypes.ProposerSignature[] memory sigs = makeUpdateProposalSigs(
            signers,
            signerPKs,
            expirationTimestamps,
            UpdateProposalParams(proposalId, proposer, txs, ''),
            address(dao),
            'different domain name'
        );

        vm.prank(proposer);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.InvalidSignature.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');
    }

    function test_givenSigOnDifferentVerifyingContract_reverts() public {
        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = signersPKsExpirations();

        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('new target'), 0, '', '');
        NounsDAOTypes.ProposerSignature[] memory sigs = makeUpdateProposalSigs(
            signers,
            signerPKs,
            expirationTimestamps,
            UpdateProposalParams(proposalId, proposer, txs, ''),
            makeAddr('other verifying contract')
        );

        vm.prank(proposer);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.InvalidSignature.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');
    }

    function test_givenERC1271CheckReturnsFalse_reverts() public {
        ERC1271Stub erc1271 = new ERC1271Stub();
        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = signersPKsExpirations();

        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('new target'), 0, '', '');
        NounsDAOTypes.ProposerSignature[] memory sigs = makeUpdateProposalSigs(
            signers,
            signerPKs,
            expirationTimestamps,
            UpdateProposalParams(proposalId, proposer, txs, ''),
            address(dao)
        );

        sigs[1].signer = address(erc1271);
        erc1271.setResponse(keccak256(sigs[1].sig), false);

        vm.prank(proposer);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.InvalidSignature.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');
    }

    function test_givenProposalDoesntExist_reverts() public {
        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = signersPKsExpirations();

        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('new target'), 0, '', '');
        NounsDAOTypes.ProposerSignature[] memory sigs = makeUpdateProposalSigs(
            signers,
            signerPKs,
            expirationTimestamps,
            UpdateProposalParams(proposalId, proposer, txs, ''),
            address(dao)
        );

        vm.expectRevert('NounsDAO::state: invalid proposal id');
        dao.updateProposalBySigs(proposalId + 1, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');
    }

    function test_givenNoTxs_reverts() public {
        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = signersPKsExpirations();

        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        string[] memory signatures = new string[](0);
        bytes[] memory calldatas = new bytes[](0);
        NounsDAOProposals.ProposalTxs memory txs = NounsDAOProposals.ProposalTxs(
            targets,
            values,
            signatures,
            calldatas
        );
        NounsDAOTypes.ProposerSignature[] memory sigs = makeUpdateProposalSigs(
            signers,
            signerPKs,
            expirationTimestamps,
            UpdateProposalParams(proposalId, proposer, txs, ''),
            address(dao)
        );

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.MustProvideActions.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');
    }

    function test_givenTooManyTxs_reverts() public {
        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = signersPKsExpirations();

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
        NounsDAOProposals.ProposalTxs memory txs = NounsDAOProposals.ProposalTxs(
            targets,
            values,
            signatures,
            calldatas
        );
        NounsDAOTypes.ProposerSignature[] memory sigs = makeUpdateProposalSigs(
            signers,
            signerPKs,
            expirationTimestamps,
            UpdateProposalParams(proposalId, proposer, txs, ''),
            address(dao)
        );

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.TooManyActions.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');
    }

    function test_givenTxsWithArityMismatch_reverts() public {
        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = signersPKsExpirations();

        address[] memory targets = new address[](1);
        targets[0] = makeAddr('new target');
        uint256[] memory values = new uint256[](0);
        string[] memory signatures = new string[](0);
        bytes[] memory calldatas = new bytes[](0);
        NounsDAOProposals.ProposalTxs memory txs = NounsDAOProposals.ProposalTxs(
            targets,
            values,
            signatures,
            calldatas
        );
        NounsDAOTypes.ProposerSignature[] memory sigs = makeUpdateProposalSigs(
            signers,
            signerPKs,
            expirationTimestamps,
            UpdateProposalParams(proposalId, proposer, txs, ''),
            address(dao)
        );

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.ProposalInfoArityMismatch.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');
    }

    function test_givenStatesPendingActiveSucceededQueuedAndExecuted_reverts() public {
        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = signersPKsExpirations();
        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('new target'), 0, '', '');
        NounsDAOTypes.ProposerSignature[] memory sigs = makeUpdateProposalSigs(
            signers,
            signerPKs,
            expirationTimestamps,
            UpdateProposalParams(proposalId, proposer, txs, ''),
            address(dao)
        );

        // Pending
        vm.roll(block.number + proposalUpdatablePeriodInBlocks);
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.Pending);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');

        // Active
        vm.roll(block.number + VOTING_DELAY);
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.Active);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');

        // Succeeded
        // vm.prank(proposer);
        // dao.castRefundableVote(proposalId, 1);
        vm.prank(_signers[0]);
        dao.castRefundableVote(signer0TokenIds, proposalId, 1);
        vm.roll(block.number + VOTING_PERIOD);
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.Succeeded);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');

        // Queued
        dao.queue(proposalId);
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.Queued);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');

        // Executed
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        dao.execute(proposalId);
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.Executed);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');
    }

    function test_givenStateCanceled_reverts() public {
        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = signersPKsExpirations();
        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('new target'), 0, '', '');
        NounsDAOTypes.ProposerSignature[] memory sigs = makeUpdateProposalSigs(
            signers,
            signerPKs,
            expirationTimestamps,
            UpdateProposalParams(proposalId, proposer, txs, ''),
            address(dao)
        );

        vm.prank(proposer);
        dao.cancel(proposalId);
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.Canceled);

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');
    }

    function test_givenStateDefeated_reverts() public {
        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = signersPKsExpirations();
        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('new target'), 0, '', '');
        NounsDAOTypes.ProposerSignature[] memory sigs = makeUpdateProposalSigs(
            signers,
            signerPKs,
            expirationTimestamps,
            UpdateProposalParams(proposalId, proposer, txs, ''),
            address(dao)
        );

        vm.roll(block.number + proposalUpdatablePeriodInBlocks + VOTING_DELAY + VOTING_PERIOD);
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.Defeated);

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');
    }

    function test_givenStateExpired_reverts() public {
        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = signersPKsExpirations();
        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('new target'), 0, '', '');
        NounsDAOTypes.ProposerSignature[] memory sigs = makeUpdateProposalSigs(
            signers,
            signerPKs,
            expirationTimestamps,
            UpdateProposalParams(proposalId, proposer, txs, ''),
            address(dao)
        );

        vm.roll(block.number + proposalUpdatablePeriodInBlocks + VOTING_DELAY);
        // vm.prank(proposer);
        // dao.castRefundableVote(proposalId, 1);
        vm.prank(_signers[0]);
        dao.castRefundableVote(signer0TokenIds, proposalId, 1);
        vm.roll(block.number + VOTING_PERIOD);
        dao.queue(proposalId);
        vm.warp(block.timestamp + TIMELOCK_DELAY + timelock.GRACE_PERIOD());
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.Expired);

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');
    }

    function test_givenStateVetoed_reverts() public {
        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = signersPKsExpirations();
        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('new target'), 0, '', '');
        NounsDAOTypes.ProposerSignature[] memory sigs = makeUpdateProposalSigs(
            signers,
            signerPKs,
            expirationTimestamps,
            UpdateProposalParams(proposalId, proposer, txs, ''),
            address(dao)
        );

        vm.prank(vetoer);
        dao.veto(proposalId);
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.Vetoed);

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');
    }

    function test_givenStateObjectionPeriod_reverts() public {
        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = signersPKsExpirations();
        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('new target'), 0, '', '');
        NounsDAOTypes.ProposerSignature[] memory sigs = makeUpdateProposalSigs(
            signers,
            signerPKs,
            expirationTimestamps,
            UpdateProposalParams(proposalId, proposer, txs, ''),
            address(dao)
        );

        vm.roll(
            block.number + proposalUpdatablePeriodInBlocks + VOTING_DELAY + VOTING_PERIOD - lastMinuteWindowInBlocks
        );
        // vm.prank(proposer);
        // dao.castRefundableVote(proposalId, 1);
        vm.prank(_signers[0]);
        dao.castRefundableVote(signer0TokenIds, proposalId, 1);
        vm.roll(block.number + lastMinuteWindowInBlocks);
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.ObjectionPeriod);

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.CanOnlyEditUpdatableProposals.selector));
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');
    }

    function test_givenPropNotBySigs_reverts() public {
        NounDelegationToken dt = NounDelegationToken(dao.delegationToken());

        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = signersPKsExpirations();
        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('new target'), 0, '', '');
        NounsDAOTypes.ProposerSignature[] memory sigs = makeUpdateProposalSigs(
            signers,
            signerPKs,
            expirationTimestamps,
            UpdateProposalParams(proposalId, proposer, txs, ''),
            address(dao)
        );

        // cancel the existing prop proposer has so we don't revert due to this reason
        vm.prank(proposer);
        dao.cancel(proposalId);

        // giving proposer enough votes to propose
        vm.startPrank(_signers[_signers.length - 1]);
        uint256 tokenId = dao.nouns().tokenOfOwnerByIndex(_signers[_signers.length - 1], 0);
        dt.mint(proposer, tokenId);
        vm.stopPrank();
        vm.roll(block.number + 1);

        // propose without signers
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        proposalId = propose(proposer, tokenIds, makeAddr('target'), 0, '', '', '', 0);
        vm.roll(block.number + 1);

        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.SignerCountMismtach.selector));
        vm.prank(proposer);
        dao.updateProposalBySigs(proposalId, sigs, txs.targets, txs.values, txs.signatures, txs.calldatas, '', '');
    }

    function test_givenStateUpdatable_updatesTxsAndEmitsEvent() public {
        (
            address[] memory signers,
            uint256[] memory signerPKs,
            uint256[] memory expirationTimestamps
        ) = signersPKsExpirations();
        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('new target'), 1, 'new signature', 'new calldata');
        NounsDAOTypes.ProposerSignature[] memory sigs = makeUpdateProposalSigs(
            signers,
            signerPKs,
            expirationTimestamps,
            UpdateProposalParams(proposalId, proposer, txs, 'descriptionAfter'),
            address(dao)
        );
        assertTrue(dao.state(proposalId) == NounsDAOTypes.ProposalState.Updatable);
        (
            address[] memory targetsBefore,
            uint256[] memory valuesBefore,
            string[] memory signaturesBefore,
            bytes[] memory calldatasBefore
        ) = dao.getActions(proposalId);
        assertEq(targetsBefore[0], makeAddr('target'));
        assertEq(valuesBefore[0], 0);
        assertEq(signaturesBefore[0], '');
        assertEq(calldatasBefore[0], '');

        vm.expectEmit(true, true, true, true);
        emit ProposalUpdated(
            proposalId,
            proposer,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            'descriptionAfter',
            'some update message'
        );

        vm.prank(proposer);
        dao.updateProposalBySigs(
            proposalId,
            sigs,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            'descriptionAfter',
            'some update message'
        );

        (
            address[] memory targetsAfter,
            uint256[] memory valuesAfter,
            string[] memory signaturesAfter,
            bytes[] memory calldatasAfter
        ) = dao.getActions(proposalId);
        assertEq(targetsAfter[0], makeAddr('new target'));
        assertEq(valuesAfter[0], 1);
        assertEq(signaturesAfter[0], 'new signature');
        assertEq(calldatasAfter[0], 'new calldata');
    }

    function signersPKsExpirations(
        uint256 len
    )
        internal
        view
        returns (address[] memory signers, uint256[] memory signerPKs, uint256[] memory expirationTimestamps)
    {
        signers = new address[](len);
        signerPKs = new uint256[](len);
        expirationTimestamps = new uint256[](len);

        for (uint256 i = 0; i < len; ++i) {
            signers[i] = _signers[i];
            signerPKs[i] = _signerPKs[i];
            expirationTimestamps[i] = defaultExpirationTimestamp;
        }
    }

    function signersPKsExpirations()
        internal
        view
        returns (address[] memory signers, uint256[] memory signerPKs, uint256[] memory expirationTimestamps)
    {
        return signersPKsExpirations(2);
    }

    function fewerSignersPKsExpirations()
        internal
        view
        returns (address[] memory signers, uint256[] memory signerPKs, uint256[] memory expirationTimestamps)
    {
        return signersPKsExpirations(1);
    }

    function moreSignersPKsExpirations()
        internal
        view
        returns (address[] memory signers, uint256[] memory signerPKs, uint256[] memory expirationTimestamps)
    {
        return signersPKsExpirations(3);
    }
}
