// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import 'forge-std/Test.sol';
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
import { DelegationHelpers } from '../helpers/DelegationHelpers.sol';
import { NounDelegationToken } from '../../../contracts/governance/NounDelegationToken.sol';

contract ProposeBySigsTest is NounsDAOLogicBaseTest {
    using DelegationHelpers for address;

    address proposerWithVote;
    uint256 proposerWithVotePK;
    address proposerWithNoVotes = makeAddr('proposerWithNoVotes');
    address signerWithNoVotes;
    uint256 signerWithNoVotesPK;
    address signerWithVote1;
    uint256 signerWithVote1PK;
    address signerWithVote2;
    uint256 signerWithVote2PK;

    function setUp() public override {
        super.setUp();

        (proposerWithVote, proposerWithVotePK) = makeAddrAndKey('proposerWithVote');
        (signerWithNoVotes, signerWithNoVotesPK) = makeAddrAndKey('signerWithNoVotes');
        (signerWithVote1, signerWithVote1PK) = makeAddrAndKey('signerWithVote1');
        (signerWithVote2, signerWithVote2PK) = makeAddrAndKey('signerWithVote2');

        vm.prank(address(timelock));
        dao._setProposalThresholdBPS(1_000);

        vm.startPrank(minter);
        nounsToken.mint();
        nounsToken.transferFrom(minter, proposerWithVote, 1);
        nounsToken.mint();
        nounsToken.transferFrom(minter, signerWithVote1, 2);
        nounsToken.mint();
        nounsToken.transferFrom(minter, signerWithVote2, 3);
        vm.roll(block.number + 1);
        vm.stopPrank();
    }

    function test_givenNoSigs_reverts() public {
        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('target'), 0, '', '');
        NounsDAOTypes.ProposerSignature[] memory proposerSignatures = new NounsDAOTypes.ProposerSignature[](0);

        uint256[] memory proposerTokenIds = address(this).allVotesOf(dao);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.MustProvideSignatures.selector));
        dao.proposeBySigs(
            proposerTokenIds,
            proposerSignatures,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            ''
        );
    }

    function test_givenCanceledSig_reverts() public {
        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('target'), 0, '', '');
        uint256 expirationTimestamp = block.timestamp + 1234;
        NounsDAOTypes.ProposerSignature[] memory proposerSignatures = new NounsDAOTypes.ProposerSignature[](1);
        proposerSignatures[0] = NounsDAOTypes.ProposerSignature(
            signProposal(proposerWithVote, signerWithVote1PK, txs, '', expirationTimestamp, address(dao)),
            signerWithVote1,
            expirationTimestamp,
            signerWithVote1.allVotesOf(dao)
        );

        vm.prank(signerWithVote1);
        dao.cancelSig(proposerSignatures[0].sig);

        uint256[] memory tokenIds = proposerWithVote.allVotesOf(dao);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.SignatureIsCancelled.selector));
        vm.prank(proposerWithVote);
        dao.proposeBySigs(tokenIds, proposerSignatures, txs.targets, txs.values, txs.signatures, txs.calldatas, '');
    }

    function test_givenExpireddSig_reverts() public {
        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('target'), 0, '', '');
        uint256 expirationTimestamp = block.timestamp - 1;
        NounsDAOTypes.ProposerSignature[] memory proposerSignatures = new NounsDAOTypes.ProposerSignature[](1);
        proposerSignatures[0] = NounsDAOTypes.ProposerSignature(
            signProposal(proposerWithVote, signerWithVote1PK, txs, '', expirationTimestamp, address(dao)),
            signerWithVote1,
            expirationTimestamp,
            signerWithVote1.allVotesOf(dao)
        );

        uint256[] memory proposerTokenIds = proposerWithVote.allVotesOf(dao);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.SignatureExpired.selector));
        vm.prank(proposerWithVote);
        dao.proposeBySigs(
            proposerTokenIds,
            proposerSignatures,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            ''
        );
    }

    function test_givenSigOnDifferentDescription_reverts() public {
        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('target'), 0, '', '');
        uint256 expirationTimestamp = block.timestamp + 1234;
        NounsDAOTypes.ProposerSignature[] memory proposerSignatures = new NounsDAOTypes.ProposerSignature[](1);
        proposerSignatures[0] = NounsDAOTypes.ProposerSignature(
            signProposal(
                proposerWithVote,
                signerWithVote1PK,
                txs,
                'different sig description',
                expirationTimestamp,
                address(dao)
            ),
            signerWithVote1,
            expirationTimestamp,
            signerWithVote1.allVotesOf(dao)
        );

        uint256[] memory proposerTokenIds = proposerWithVote.allVotesOf(dao);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.InvalidSignature.selector));
        vm.prank(proposerWithVote);
        dao.proposeBySigs(
            proposerTokenIds,
            proposerSignatures,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            'prop description'
        );
    }

    function test_givenSigOnDifferentTargets_reverts() public {
        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('target'), 0, '', '');
        uint256 expirationTimestamp = block.timestamp + 1234;
        NounsDAOTypes.ProposerSignature[] memory proposerSignatures = new NounsDAOTypes.ProposerSignature[](1);
        proposerSignatures[0] = NounsDAOTypes.ProposerSignature(
            signProposal(proposerWithVote, signerWithVote1PK, txs, 'description', expirationTimestamp, address(dao)),
            signerWithVote1,
            expirationTimestamp,
            signerWithVote1.allVotesOf(dao)
        );

        txs.targets[0] = makeAddr('different target');

        uint256[] memory proposerTokenIds = proposerWithVote.allVotesOf(dao);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.InvalidSignature.selector));
        vm.prank(proposerWithVote);
        dao.proposeBySigs(
            proposerTokenIds,
            proposerSignatures,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            'description'
        );
    }

    function test_givenSigOnDifferentValues_reverts() public {
        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('target'), 0, '', '');
        uint256 expirationTimestamp = block.timestamp + 1234;
        NounsDAOTypes.ProposerSignature[] memory proposerSignatures = new NounsDAOTypes.ProposerSignature[](1);
        proposerSignatures[0] = NounsDAOTypes.ProposerSignature(
            signProposal(proposerWithVote, signerWithVote1PK, txs, 'description', expirationTimestamp, address(dao)),
            signerWithVote1,
            expirationTimestamp,
            signerWithVote1.allVotesOf(dao)
        );

        txs.values[0] = 42;

        uint256[] memory proposerTokenIds = proposerWithVote.allVotesOf(dao);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.InvalidSignature.selector));
        vm.prank(proposerWithVote);
        dao.proposeBySigs(
            proposerTokenIds,
            proposerSignatures,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            'description'
        );
    }

    function test_givenSigOnDifferentSignatures_reverts() public {
        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('target'), 0, '', '');
        uint256 expirationTimestamp = block.timestamp + 1234;
        NounsDAOTypes.ProposerSignature[] memory proposerSignatures = new NounsDAOTypes.ProposerSignature[](1);
        proposerSignatures[0] = NounsDAOTypes.ProposerSignature(
            signProposal(proposerWithVote, signerWithVote1PK, txs, 'description', expirationTimestamp, address(dao)),
            signerWithVote1,
            expirationTimestamp,
            signerWithVote1.allVotesOf(dao)
        );

        txs.signatures[0] = 'different signature';

        uint256[] memory proposerTokenIds = proposerWithVote.allVotesOf(dao);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.InvalidSignature.selector));
        vm.prank(proposerWithVote);
        dao.proposeBySigs(
            proposerTokenIds,
            proposerSignatures,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            'description'
        );
    }

    function test_givenSigOnDifferentCalldatas_reverts() public {
        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('target'), 0, '', '');
        uint256 expirationTimestamp = block.timestamp + 1234;
        NounsDAOTypes.ProposerSignature[] memory proposerSignatures = new NounsDAOTypes.ProposerSignature[](1);
        proposerSignatures[0] = NounsDAOTypes.ProposerSignature(
            signProposal(proposerWithVote, signerWithVote1PK, txs, 'description', expirationTimestamp, address(dao)),
            signerWithVote1,
            expirationTimestamp,
            signerWithVote1.allVotesOf(dao)
        );

        txs.calldatas[0] = 'different calldatas';

        uint256[] memory proposerTokenIds = proposerWithVote.allVotesOf(dao);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.InvalidSignature.selector));
        vm.prank(proposerWithVote);
        dao.proposeBySigs(
            proposerTokenIds,
            proposerSignatures,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            'description'
        );
    }

    function test_givenSigOnDifferentExpiration_reverts() public {
        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('target'), 0, '', '');
        uint256 expirationTimestamp = block.timestamp + 1234;
        NounsDAOTypes.ProposerSignature[] memory proposerSignatures = new NounsDAOTypes.ProposerSignature[](1);
        proposerSignatures[0] = NounsDAOTypes.ProposerSignature(
            signProposal(proposerWithVote, signerWithVote1PK, txs, 'description', expirationTimestamp, address(dao)),
            signerWithVote1,
            expirationTimestamp,
            signerWithVote1.allVotesOf(dao)
        );

        proposerSignatures[0].expirationTimestamp = expirationTimestamp + 1;

        uint256[] memory proposerTokenIds = proposerWithVote.allVotesOf(dao);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.InvalidSignature.selector));
        vm.prank(proposerWithVote);
        dao.proposeBySigs(
            proposerTokenIds,
            proposerSignatures,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            'description'
        );
    }

    function test_givenSigOnDifferentSigner_reverts() public {
        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('target'), 0, '', '');
        uint256 expirationTimestamp = block.timestamp + 1234;
        NounsDAOTypes.ProposerSignature[] memory proposerSignatures = new NounsDAOTypes.ProposerSignature[](1);
        proposerSignatures[0] = NounsDAOTypes.ProposerSignature(
            signProposal(proposerWithVote, signerWithVote1PK, txs, 'description', expirationTimestamp, address(dao)),
            signerWithVote1,
            expirationTimestamp,
            signerWithVote1.allVotesOf(dao)
        );

        proposerSignatures[0].signer = makeAddr('different signer than sig');

        uint256[] memory proposerTokenIds = proposerWithVote.allVotesOf(dao);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.InvalidSignature.selector));
        vm.prank(proposerWithVote);
        dao.proposeBySigs(
            proposerTokenIds,
            proposerSignatures,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            'description'
        );
    }

    function test_givenSigOnDifferentDomainName_reverts() public {
        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('target'), 0, '', '');
        uint256 expirationTimestamp = block.timestamp + 1234;
        NounsDAOTypes.ProposerSignature[] memory proposerSignatures = new NounsDAOTypes.ProposerSignature[](1);
        proposerSignatures[0] = NounsDAOTypes.ProposerSignature(
            signProposal(
                proposerWithVote,
                signerWithVote1PK,
                txs,
                'description',
                expirationTimestamp,
                address(dao),
                'different domain name'
            ),
            signerWithVote1,
            expirationTimestamp,
            signerWithVote1.allVotesOf(dao)
        );

        uint256[] memory proposerTokenIds = proposerWithVote.allVotesOf(dao);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.InvalidSignature.selector));
        vm.prank(proposerWithVote);
        dao.proposeBySigs(
            proposerTokenIds,
            proposerSignatures,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            'description'
        );
    }

    function test_givenSigOnDifferentVerifyingContract_reverts() public {
        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('target'), 0, '', '');
        uint256 expirationTimestamp = block.timestamp + 1234;
        NounsDAOTypes.ProposerSignature[] memory proposerSignatures = new NounsDAOTypes.ProposerSignature[](1);
        proposerSignatures[0] = NounsDAOTypes.ProposerSignature(
            signProposal(
                proposerWithVote,
                signerWithVote1PK,
                txs,
                'description',
                expirationTimestamp,
                makeAddr('different verifying contract')
            ),
            signerWithVote1,
            expirationTimestamp,
            signerWithVote1.allVotesOf(dao)
        );

        uint256[] memory proposerTokenIds = proposerWithVote.allVotesOf(dao);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.InvalidSignature.selector));
        vm.prank(proposerWithVote);
        dao.proposeBySigs(
            proposerTokenIds,
            proposerSignatures,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            'description'
        );
    }

    function test_givenERC1271CheckReturnsFalse_reverts() public {
        ERC1271Stub erc1271 = new ERC1271Stub();

        // Giving the 1271 signer a vote
        vm.startPrank(minter);
        uint256 tokenId = nounsToken.mint();
        nounsToken.transferFrom(minter, address(erc1271), tokenId);
        vm.roll(block.number + 1);
        vm.stopPrank();

        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('target'), 0, '', '');
        uint256 expirationTimestamp = block.timestamp + 1234;
        NounsDAOTypes.ProposerSignature[] memory proposerSignatures = new NounsDAOTypes.ProposerSignature[](1);
        proposerSignatures[0] = NounsDAOTypes.ProposerSignature(
            signProposal(proposerWithVote, signerWithVote1PK, txs, 'description', expirationTimestamp, address(dao)),
            address(erc1271),
            expirationTimestamp,
            address(erc1271).allVotesOf(dao)
        );
        erc1271.setResponse(keccak256(proposerSignatures[0].sig), false);

        uint256[] memory proposerTokenIds = proposerWithVote.allVotesOf(dao);
        vm.expectRevert(abi.encodeWithSelector(NounsDAOProposals.InvalidSignature.selector));
        vm.prank(proposerWithVote);
        dao.proposeBySigs(
            proposerTokenIds,
            proposerSignatures,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            'description'
        );
    }

    function test_givenSignerWithAnActiveProp_allowsAnotherProposal() public {
        propose(signerWithVote1, makeAddr('target'), 0, '', '', '');

        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('target'), 0, '', '');
        uint256 expirationTimestamp = block.timestamp + 1234;
        NounsDAOTypes.ProposerSignature[] memory proposerSignatures = new NounsDAOTypes.ProposerSignature[](1);
        proposerSignatures[0] = NounsDAOTypes.ProposerSignature(
            signProposal(proposerWithVote, signerWithVote1PK, txs, 'description', expirationTimestamp, address(dao)),
            signerWithVote1,
            expirationTimestamp,
            signerWithVote1.allVotesOf(dao)
        );

        vm.startPrank(proposerWithVote);
        dao.proposeBySigs(
            proposerWithVote.allVotesOf(dao),
            proposerSignatures,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            'description'
        );
        vm.stopPrank();
    }

    function test_givenProposerWithAnActiveProp_allowsAnotherProposal() public {
        propose(proposerWithVote, makeAddr('target'), 0, '', '', '');

        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('target'), 0, '', '');
        uint256 expirationTimestamp = block.timestamp + 1234;
        NounsDAOTypes.ProposerSignature[] memory proposerSignatures = new NounsDAOTypes.ProposerSignature[](1);
        proposerSignatures[0] = NounsDAOTypes.ProposerSignature(
            signProposal(proposerWithVote, signerWithVote1PK, txs, 'description', expirationTimestamp, address(dao)),
            signerWithVote1,
            expirationTimestamp,
            signerWithVote1.allVotesOf(dao)
        );

        vm.startPrank(proposerWithVote);
        dao.proposeBySigs(
            proposerWithVote.allVotesOf(dao),
            proposerSignatures,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            'description'
        );
        vm.stopPrank();
    }

    function test_givenProposerAndSignerWithVotesButBelowThreshold_reverts() public {
        // Minting to push proposer and signer below threshold
        vm.startPrank(minter);
        for (uint256 i = 0; i < 16; ++i) {
            nounsToken.mint();
        }
        vm.roll(block.number + 1);
        vm.stopPrank();

        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('target'), 0, '', '');
        uint256 expirationTimestamp = block.timestamp + 1234;
        NounsDAOTypes.ProposerSignature[] memory proposerSignatures = new NounsDAOTypes.ProposerSignature[](1);
        proposerSignatures[0] = NounsDAOTypes.ProposerSignature(
            signProposal(proposerWithVote, signerWithVote1PK, txs, 'description', expirationTimestamp, address(dao)),
            signerWithVote1,
            expirationTimestamp,
            signerWithVote1.allVotesOf(dao)
        );

        uint256[] memory proposerTokenIds = proposerWithVote.allVotesOf(dao);
        vm.expectRevert(NounsDAOProposals.VotesBelowProposalThreshold.selector);
        vm.prank(proposerWithVote);
        dao.proposeBySigs(
            proposerTokenIds,
            proposerSignatures,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            'description'
        );
    }

    function test_givenProposerWithEnoughVotesAndSignerWithNoVotes_reverts() public {
        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('target'), 0, '', '');
        uint256 expirationTimestamp = block.timestamp + 1234;
        NounsDAOTypes.ProposerSignature[] memory proposerSignatures = new NounsDAOTypes.ProposerSignature[](1);
        proposerSignatures[0] = NounsDAOTypes.ProposerSignature(
            signProposal(proposerWithVote, signerWithNoVotesPK, txs, 'description', expirationTimestamp, address(dao)),
            signerWithNoVotes,
            expirationTimestamp,
            signerWithNoVotes.allVotesOf(dao)
        );

        uint256[] memory proposerTokenIds = proposerWithVote.allVotesOf(dao);
        vm.expectRevert(NounsDAOProposals.MustProvideSignatures.selector);
        vm.prank(proposerWithVote);
        dao.proposeBySigs(
            proposerTokenIds,
            proposerSignatures,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            'description'
        );
    }

    function test_givenProposerAndSignerWithEnoughVotesCombined_worksAndEmitsEvents() public {
        // Minting to push proposer below threshold, while combined with signer they have enough
        vm.startPrank(minter);
        for (uint256 i = 0; i < 6; ++i) {
            nounsToken.mint();
        }
        vm.roll(block.number + 1);
        vm.stopPrank();

        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('target'), 0, '', '');
        uint256 expirationTimestamp = block.timestamp + 1234;
        NounsDAOTypes.ProposerSignature[] memory proposerSignatures = new NounsDAOTypes.ProposerSignature[](1);
        proposerSignatures[0] = NounsDAOTypes.ProposerSignature(
            signProposal(proposerWithVote, signerWithVote1PK, txs, 'description', expirationTimestamp, address(dao)),
            signerWithVote1,
            expirationTimestamp,
            signerWithVote1.allVotesOf(dao)
        );

        address[] memory expectedSigners = new address[](1);
        expectedSigners[0] = signerWithVote1;
        expectNewPropEvents(txs, proposerWithVote, dao.proposalCount() + 1, 1, 0, expectedSigners);

        vm.startPrank(proposerWithVote);
        dao.proposeBySigs(
            proposerWithVote.allVotesOf(dao),
            proposerSignatures,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            'description'
        );
        vm.stopPrank();
    }

    function test_givenProposerIsAlsoSigner_reverts() public {
        // Minting to push proposer below threshold, while if counted twice will have enough
        vm.startPrank(minter);
        for (uint256 i = 0; i < 6; ++i) {
            nounsToken.mint();
        }
        vm.roll(block.number + 1);
        vm.stopPrank();
        assertEq(dao.proposalThreshold(), 1);

        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('target'), 0, '', '');
        uint256 expirationTimestamp = block.timestamp + 1234;
        NounsDAOTypes.ProposerSignature[] memory proposerSignatures = new NounsDAOTypes.ProposerSignature[](1);
        proposerSignatures[0] = NounsDAOTypes.ProposerSignature(
            signProposal(proposerWithVote, proposerWithVotePK, txs, 'description', expirationTimestamp, address(dao)),
            proposerWithVote,
            expirationTimestamp,
            proposerWithVote.allVotesOf(dao)
        );

        uint256[] memory proposerTokenIds = proposerWithVote.allVotesOf(dao);
        vm.expectRevert('signers and proposer have duplicates');
        vm.prank(proposerWithVote);
        dao.proposeBySigs(
            proposerTokenIds,
            proposerSignatures,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            'description'
        );
    }

    function test_givenProposerWithNoVotesAndSignerWithEnoughVotes_worksAndEmitsEvents() public {
        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('target'), 0, '', '');
        uint256 expirationTimestamp = block.timestamp + 1234;
        NounsDAOTypes.ProposerSignature[] memory proposerSignatures = new NounsDAOTypes.ProposerSignature[](1);
        proposerSignatures[0] = NounsDAOTypes.ProposerSignature(
            signProposal(proposerWithNoVotes, signerWithVote1PK, txs, 'description', expirationTimestamp, address(dao)),
            signerWithVote1,
            expirationTimestamp,
            signerWithVote1.allVotesOf(dao)
        );

        address[] memory expectedSigners = new address[](1);
        expectedSigners[0] = signerWithVote1;
        expectNewPropEvents(txs, proposerWithNoVotes, dao.proposalCount() + 1, 0, 0, expectedSigners);

        vm.startPrank(proposerWithNoVotes);
        dao.proposeBySigs(
            proposerWithNoVotes.allVotesOf(dao),
            proposerSignatures,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            'description'
        );
        vm.stopPrank();
    }

    function test_givenOnesOfSignersHasNoVotes_signerIsFilteredOut() public {
        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('target'), 0, '', '');
        uint256 expirationTimestamp = block.timestamp + 1234;
        NounsDAOTypes.ProposerSignature[] memory proposerSignatures = new NounsDAOTypes.ProposerSignature[](2);
        proposerSignatures[0] = NounsDAOTypes.ProposerSignature(
            signProposal(
                proposerWithNoVotes,
                signerWithNoVotesPK,
                txs,
                'description',
                expirationTimestamp,
                address(dao)
            ),
            signerWithNoVotes,
            expirationTimestamp,
            signerWithNoVotes.allVotesOf(dao)
        );
        proposerSignatures[1] = NounsDAOTypes.ProposerSignature(
            signProposal(proposerWithNoVotes, signerWithVote2PK, txs, 'description', expirationTimestamp, address(dao)),
            signerWithVote2,
            expirationTimestamp,
            signerWithVote2.allVotesOf(dao)
        );

        address[] memory expectedSigners = new address[](1);
        expectedSigners[0] = signerWithVote2;
        expectNewPropEvents(txs, proposerWithNoVotes, dao.proposalCount() + 1, 0, 0, expectedSigners);

        vm.startPrank(proposerWithNoVotes);
        uint256 proposalId = dao.proposeBySigs(
            proposerWithNoVotes.allVotesOf(dao),
            proposerSignatures,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            'description'
        );
        vm.stopPrank();

        NounsDAOTypes.ProposalCondensedV3 memory proposal = dao.proposalsV3(proposalId);
        assertEq(proposal.signers, expectedSigners);
    }

    function test_givenProposerWithNoVotesAndTwoSignersWithEnoughVotes_worksAndEmitsEvents() public {
        // Minting to push a single signer below threshold
        vm.startPrank(minter);
        for (uint256 i = 0; i < 6; ++i) {
            nounsToken.mint();
        }
        vm.roll(block.number + 1);
        vm.stopPrank();

        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('target'), 0, '', '');
        uint256 expirationTimestamp = block.timestamp + 1234;
        NounsDAOTypes.ProposerSignature[] memory proposerSignatures = new NounsDAOTypes.ProposerSignature[](2);
        proposerSignatures[0] = NounsDAOTypes.ProposerSignature(
            signProposal(proposerWithNoVotes, signerWithVote1PK, txs, 'description', expirationTimestamp, address(dao)),
            signerWithVote1,
            expirationTimestamp,
            signerWithVote1.allVotesOf(dao)
        );
        proposerSignatures[1] = NounsDAOTypes.ProposerSignature(
            signProposal(proposerWithNoVotes, signerWithVote2PK, txs, 'description', expirationTimestamp, address(dao)),
            signerWithVote2,
            expirationTimestamp,
            signerWithVote2.allVotesOf(dao)
        );

        address[] memory expectedSigners = new address[](2);
        expectedSigners[0] = signerWithVote1;
        expectedSigners[1] = signerWithVote2;
        expectNewPropEvents(txs, proposerWithNoVotes, dao.proposalCount() + 1, 1, 0, expectedSigners);

        vm.startPrank(proposerWithNoVotes);
        uint256 proposalId = dao.proposeBySigs(
            proposerWithNoVotes.allVotesOf(dao),
            proposerSignatures,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            'description'
        );
        vm.stopPrank();

        NounsDAOTypes.ProposalCondensedV3 memory proposal = dao.proposalsV3(proposalId);
        assertEq(proposal.signers, expectedSigners);
    }

    function test_givenProposerWithNoVotesAndTwoSignaturesBySameSigner_reverts() public {
        // Minting to push a single signer below threshold
        vm.startPrank(minter);
        for (uint256 i = 0; i < 6; ++i) {
            nounsToken.mint();
        }
        vm.roll(block.number + 1);
        vm.stopPrank();

        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('target'), 0, '', '');
        uint256 expirationTimestamp = block.timestamp + 1234;
        NounsDAOTypes.ProposerSignature[] memory proposerSignatures = new NounsDAOTypes.ProposerSignature[](2);
        proposerSignatures[0] = NounsDAOTypes.ProposerSignature(
            signProposal(proposerWithNoVotes, signerWithVote1PK, txs, 'description', expirationTimestamp, address(dao)),
            signerWithVote1,
            expirationTimestamp,
            signerWithVote1.allVotesOf(dao)
        );
        proposerSignatures[1] = NounsDAOTypes.ProposerSignature(
            signProposal(
                proposerWithNoVotes,
                signerWithVote1PK,
                txs,
                'description',
                expirationTimestamp + 1,
                address(dao)
            ),
            signerWithVote1,
            expirationTimestamp + 1,
            signerWithVote1.allVotesOf(dao)
        );

        uint256[] memory proposerTokenIds = proposerWithNoVotes.allVotesOf(dao);
        vm.expectRevert('signers and proposer have duplicates');
        vm.prank(proposerWithNoVotes);
        dao.proposeBySigs(
            proposerTokenIds,
            proposerSignatures,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            'description'
        );
    }

    function test_givenProposerWithNoVotesAndERC1271SignerWithEnoughVotes_worksAndEmitsEvents() public {
        NounDelegationToken dt = NounDelegationToken(dao.delegationToken());
        ERC1271Stub erc1271 = new ERC1271Stub();
        vm.startPrank(signerWithVote1);
        dt.mintBatch(address(erc1271), signerWithVote1.allVotesOf(dao));
        vm.stopPrank();
        vm.roll(block.number + 1);
        // important to avoid hitting the flashloan protection revert
        vm.warp(block.timestamp + 1);

        NounsDAOProposals.ProposalTxs memory txs = makeTxs(makeAddr('target'), 0, '', '');
        uint256 expirationTimestamp = block.timestamp + 1234;
        NounsDAOTypes.ProposerSignature[] memory proposerSignatures = new NounsDAOTypes.ProposerSignature[](1);
        proposerSignatures[0] = NounsDAOTypes.ProposerSignature(
            signProposal(proposerWithNoVotes, signerWithVote1PK, txs, 'description', expirationTimestamp, address(dao)),
            address(erc1271),
            expirationTimestamp,
            address(erc1271).allVotesOf(dao)
        );

        erc1271.setResponse(keccak256(proposerSignatures[0].sig), true);

        address[] memory expectedSigners = new address[](1);
        expectedSigners[0] = address(erc1271);
        expectNewPropEvents(txs, proposerWithNoVotes, dao.proposalCount() + 1, 0, 0, expectedSigners);

        uint256[] memory proposerTokenIds = proposerWithNoVotes.allVotesOf(dao);
        vm.prank(proposerWithNoVotes);
        dao.proposeBySigs(
            proposerTokenIds,
            proposerSignatures,
            txs.targets,
            txs.values,
            txs.signatures,
            txs.calldatas,
            'description'
        );
    }
}
