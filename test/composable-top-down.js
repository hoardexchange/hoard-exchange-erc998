const { assert, expect } = require('chai');
const { ethers } = require("hardhat");

describe('ComposableTopDown', async () => {
    let ComposableTopDown,
        SampleERC20,
        SampleNFT,
        ContractIERC721ReceiverNew,
        ContractIERC721ReceiverOld;

    const expectedTokenId = 1;
    const firstChildTokenId = 1;
    const aliceBalance = 1;

    const bytesFirstToken = ethers.utils.hexZeroPad('0x1', 20);
    const zeroAddress = ethers.utils.hexZeroPad('0x0', 20);
    const ERC998_MAGIC_VALUE = '0xcd740db5';

    const NFTHash = '0x1234';

    beforeEach(async () => {
        [
            alice,
            bob,
            owner,
            nonUsed,
        ] = await ethers.getSigners();
        aliceBytes32Address = ethers.utils.hexConcat([ERC998_MAGIC_VALUE, ethers.utils.hexZeroPad(alice.address, 28).toLowerCase()]);

        ComposableTopDown = await ethers.getContractFactory("ComposableTopDown");
        SampleERC20 = await ethers.getContractFactory("SampleERC20");
        SampleNFT = await ethers.getContractFactory("SampleNFT");
        ContractIERC721ReceiverNew = await ethers.getContractFactory("ContractIERC721ReceiverNew");
        ContractIERC721ReceiverOld = await ethers.getContractFactory("ContractIERC721ReceiverOld");

        composableTopDownInstance = await ComposableTopDown.deploy();
        await composableTopDownInstance.deployed();
    });


    describe('NFT Transfers', async () => {
        beforeEach(async () => {
            sampleNFTInstance = await SampleNFT.deploy();

            // mint
            await sampleNFTInstance.mint721(alice.address, NFTHash);

            await composableTopDownInstance.safeMint(alice.address);
        });

        it('Should revert when trying to get balanceOf zero address', async () => {
            const expectedRevertMessage = 'ComposableTopDown: balanceOf _tokenOwner zero address';
            await expect(composableTopDownInstance.balanceOf(zeroAddress)).to.be.revertedWith(expectedRevertMessage);
        });

        it('Should deploy SampleNFT Contract and mint to alice', async () => {
            // then:

            const hashTaken = await sampleNFTInstance.hashes(NFTHash);
            assert(hashTaken, 'NFTHash not taken');

            const balance = await composableTopDownInstance.balanceOf(alice.address);
            assert(balance.eq(aliceBalance), 'Invalid alice balance');
        });

        it('Should safeTransferFrom SampleNFT to Composable', async () => {
            // when:
            await safeTransferFromFirstToken();

            // then:
            const childExists = await composableTopDownInstance.childExists(sampleNFTInstance.address, firstChildTokenId);
            assert(childExists, 'Composable does not own SampleNFT');

            const ownerOfChild = await composableTopDownInstance.ownerOfChild(sampleNFTInstance.address, firstChildTokenId);
            assert(ownerOfChild.parentTokenId.eq(expectedTokenId), 'Invalid parent token id');

            const totalChildContracts = await composableTopDownInstance.totalChildContracts(expectedTokenId);
            assert(totalChildContracts.eq(1), 'Invalid total child contracts');

            const childContractAddress = await composableTopDownInstance.childContractByIndex(expectedTokenId, 0);
            assert(childContractAddress === sampleNFTInstance.address, 'Invalid child contract address');

            const tokenId = await composableTopDownInstance.childTokenByIndex(expectedTokenId, sampleNFTInstance.address, 0);
            assert(tokenId.eq(expectedTokenId), 'Invalid token id found when querying child token by index');

            const owner = await sampleNFTInstance.ownerOf(expectedTokenId);
            assert(owner === composableTopDownInstance.address, 'Invalid owner address');
        });

        it('Should safeTransferFromOld SampleNFT to Composable', async () => {
            // when:
            await sampleNFTInstance.connect(alice).safeTransferFromOld(
                alice.address,
                composableTopDownInstance.address,
                expectedTokenId,
                bytesFirstToken);

            // then:
            const childExists = await composableTopDownInstance.childExists(sampleNFTInstance.address, firstChildTokenId);
            assert(childExists, 'Composable does not own SampleNFT');

            const ownerOfChild = await composableTopDownInstance.ownerOfChild(sampleNFTInstance.address, firstChildTokenId);
            assert(ownerOfChild.parentTokenId.eq(expectedTokenId), 'Invalid parent token id');

            const totalChildContracts = await composableTopDownInstance.totalChildContracts(expectedTokenId);
            assert(totalChildContracts.eq(1), 'Invalid total child contracts');

            const childContractAddress = await composableTopDownInstance.childContractByIndex(expectedTokenId, 0);
            assert(childContractAddress === sampleNFTInstance.address, 'Invalid child contract address');

            const tokenId = await composableTopDownInstance.childTokenByIndex(expectedTokenId, sampleNFTInstance.address, 0);
            assert(tokenId.eq(expectedTokenId), 'Invalid token id found when querying child token by index');
        });

        it('Should revert when trying to receive an erc721 with no data', async () => {
            const erc721Instance = await ContractIERC721ReceiverOld.deploy();
            await erc721Instance.mint721(alice.address);
            const expectedRevertMessage = 'ComposableTopDown: onERC721Received(4) _data must contain the uint256 tokenId to transfer the child token to';

            await expect(erc721Instance.connect(alice)['safeTransferFrom(address,address,uint256)'](
                alice.address,
                composableTopDownInstance.address,
                expectedTokenId),
                expectedRevertMessage).to.be.revertedWith(expectedRevertMessage);
        });

        it('Should return the magic value ', async () => {
            await safeTransferFromFirstToken();
            let aliceOwner = await composableTopDownInstance.rootOwnerOf(firstChildTokenId);
            assert(aliceOwner.startsWith(ERC998_MAGIC_VALUE), 'ComposableTopDown: the magic value was not returned by rootOwnerOfChild (1)');
            assert(aliceOwner.endsWith(alice.address.toLowerCase().substring(2)), 'ComposableTopDown: rootOwnerOfChild: alice should be the owner');

            const expectedRevertMessage = 'ComposableTopDown: ownerOf _tokenId zero address';
            await expect(composableTopDownInstance.rootOwnerOf(112233)).to.be.revertedWith(expectedRevertMessage);
        });

        describe('Composable Approvals', async () => {
            beforeEach(async () => {
                await safeTransferFromFirstToken();
            });

            it('Should revert when trying to approve with not owner', async () => {
                const expectedRevertMessage = 'ComposableTopDown: approve msg.sender not owner';

                await expect(composableTopDownInstance.connect(bob).approve(bob.address, expectedTokenId)).to.be.revertedWith(expectedRevertMessage);
            });

            it('Should successfully approve bob for first token', async () => {
                // when:
                await composableTopDownInstance.connect(alice).approve(bob.address, expectedTokenId);

                // then:
                const approvedAddress = await composableTopDownInstance.getApproved(expectedTokenId);
                assert(approvedAddress === bob.address, 'Invalid approved address');
            });

            it('Should successfully emit Approval event', async () => {
                // given:
                const expectedEvent = 'Approval';

                // then:
                await expect(
                    composableTopDownInstance.connect(alice).approve(bob.address, expectedTokenId))
                    .to.emit(composableTopDownInstance,
                        expectedEvent
                    );
            });

            it('Should successfully emit Approval event arguments', async () => {
                // given:
                const expectedEvent = 'Approval';
                const approvedAddress = bob.address;

                // then:
                await expect(
                    composableTopDownInstance.connect(alice).approve(approvedAddress, expectedTokenId))
                    .to.emit(composableTopDownInstance,
                        expectedEvent).withArgs(
                            alice.address,
                            approvedAddress,
                            expectedTokenId
                        );
            });

            it('Should revert when trying to setApprovalForAll zero address', async () => {
                const expectedRevertMessage = 'ComposableTopDown: setApprovalForAll _operator zero address';
                await expect(composableTopDownInstance.setApprovalForAll(zeroAddress, true)).to.be.revertedWith(expectedRevertMessage);
            });

            it('Should successfully setApprovalForAll', async () => {
                // when:
                await composableTopDownInstance.setApprovalForAll(bob.address, true);

                // then:
                const isApproved = await composableTopDownInstance.isApprovedForAll(alice.address, bob.address);
                assert(isApproved, 'Bob not approved for owner actions');
            });

            it('Should successfully emit ApprovalForAll event', async () => {
                // given:
                const expectedEvent = 'ApprovalForAll';

                // then:
                await expect(
                    composableTopDownInstance.setApprovalForAll(bob.address, true))
                    .to.emit(
                        composableTopDownInstance,
                        expectedEvent
                    );
            });

            it('Should successfully emit ApprovalForAll event arguments', async () => {
                // given:
                const expectedEvent = 'ApprovalForAll';

                // then:
                await expect(
                    composableTopDownInstance.setApprovalForAll(bob.address, true))
                    .to.emit(
                        composableTopDownInstance,
                        expectedEvent,
                    ).withArgs(
                        alice.address,
                        bob.address,
                        true
                    );
            });

            it('Should revert isApprovedForAll _owner zero address', async () => {
                const expectedRevertMessage = 'ComposableTopDown: isApprovedForAll _owner zero address';
                await expect(composableTopDownInstance.isApprovedForAll(zeroAddress, bob.address)).to.be.revertedWith(expectedRevertMessage);
            });

            it('Should revert isApprovedForAll _operator zero address', async () => {
                const expectedRevertMessage = 'ComposableTopDown: isApprovedForAll _operator zero address';
                await expect(composableTopDownInstance.isApprovedForAll(alice.address, zeroAddress)).to.be.revertedWith(expectedRevertMessage);
            });
        });

        describe('Composable getChild', async () => {
            it('Should revert when trying to get unapproved', async () => {
                const expectedRevertMessage = 'ComposableTopDown: getChild msg.sender not approved';

                await expect(
                    composableTopDownInstance.connect(bob)
                        .getChild(alice.address, expectedTokenId, sampleNFTInstance.address, expectedTokenId)).to.be.revertedWith(
                            expectedRevertMessage);
            });

            it('Should revert when trying to get unapproved from SampleNFT', async () => {
                const expectedRevertMessage = 'ERC721: transfer caller is not owner nor approved';
                await expect(
                    composableTopDownInstance.connect(alice)
                        .getChild(alice.address, expectedTokenId, sampleNFTInstance.address, expectedTokenId)).to.be.revertedWith(
                            expectedRevertMessage);
            });

            it('Should revert when trying to get unapproved from SampleNFT', async () => {
                const expectedRevertMessage = 'ERC721: transfer caller is not owner nor approved';
                await expect(
                    composableTopDownInstance.connect(alice)
                        .getChild(alice.address, expectedTokenId, sampleNFTInstance.address, expectedTokenId)).to.be.revertedWith(
                            expectedRevertMessage);
            });

            it('Should successfully getChild', async () => {
                // given:
                await sampleNFTInstance.connect(alice)
                    .approve(composableTopDownInstance.address, expectedTokenId);

                // when:
                await composableTopDownInstance.connect(alice)
                    .getChild(alice.address, expectedTokenId, sampleNFTInstance.address, expectedTokenId);

                //then:
                const childExists = await composableTopDownInstance.childExists(sampleNFTInstance.address, firstChildTokenId);
                assert(childExists, 'Composable does not own SampleNFT');

                const ownerOfChild = await composableTopDownInstance.ownerOfChild(sampleNFTInstance.address, firstChildTokenId);
                assert(ownerOfChild.parentTokenId.eq(expectedTokenId), 'Invalid parent token id');

                const totalChildContracts = await composableTopDownInstance.totalChildContracts(expectedTokenId);
                assert(totalChildContracts.eq(1), 'Invalid total child contracts');

                const childContractAddress = await composableTopDownInstance.childContractByIndex(expectedTokenId, 0);
                assert(childContractAddress === sampleNFTInstance.address, 'Invalid child contract address');

                const tokenId = await composableTopDownInstance.childTokenByIndex(expectedTokenId, sampleNFTInstance.address, 0);
                assert(tokenId.eq(expectedTokenId), 'Invalid token id found when querying child token by index');
            });

            it('Should successfully getChild using bob as intermediary for alice using setApprovalForAll', async () => {
                // given:
                await sampleNFTInstance.connect(alice)
                    .approve(composableTopDownInstance.address, expectedTokenId);

                await sampleNFTInstance.connect(alice)
                    .setApprovalForAll(bob.address, true);

                // when:
                await composableTopDownInstance.connect(bob)
                    .getChild(alice.address, expectedTokenId, sampleNFTInstance.address, expectedTokenId);

                //then:
                const childExists = await composableTopDownInstance.childExists(sampleNFTInstance.address, firstChildTokenId);
                assert(childExists, 'Composable does not own SampleNFT');

                const ownerOfChild = await composableTopDownInstance.ownerOfChild(sampleNFTInstance.address, firstChildTokenId);
                assert(ownerOfChild.parentTokenId.eq(expectedTokenId), 'Invalid parent token id');

                const totalChildContracts = await composableTopDownInstance.totalChildContracts(expectedTokenId);
                assert(totalChildContracts.eq(1), 'Invalid total child contracts');

                const childContractAddress = await composableTopDownInstance.childContractByIndex(expectedTokenId, 0);
                assert(childContractAddress === sampleNFTInstance.address, 'Invalid child contract address');

                const tokenId = await composableTopDownInstance.childTokenByIndex(expectedTokenId, sampleNFTInstance.address, 0);
                assert(tokenId.eq(expectedTokenId), 'Invalid token id found when querying child token by index');
            });

            it('Should emit ReceiveChild event', async () => {
                // given:
                await sampleNFTInstance.connect(alice)
                    .approve(composableTopDownInstance.address, expectedTokenId);
                const expectedEvent = 'ReceivedChild';

                // then:
                await expect(
                    composableTopDownInstance.connect(alice)
                        .getChild(alice.address, expectedTokenId, sampleNFTInstance.address, expectedTokenId))
                    .to.emit(composableTopDownInstance,
                        expectedEvent);
            });

            it('Should emit ReceiveChild event arguments', async () => {
                // given:
                await sampleNFTInstance.connect(alice)
                    .approve(composableTopDownInstance.address, expectedTokenId);
                const expectedEvent = 'ReceivedChild';

                // then:
                await expect(
                    composableTopDownInstance.connect(alice)
                        .getChild(alice.address, expectedTokenId, sampleNFTInstance.address, expectedTokenId))
                    .to.emit(
                        composableTopDownInstance,
                        expectedEvent).withArgs(
                            alice.address,
                            expectedTokenId,
                            sampleNFTInstance.address,
                            expectedTokenId
                        );
            });
        });

        describe('Composable Transfers', async () => {
            beforeEach(async () => {
                await safeTransferFromFirstToken();
            });

            it('Should revert when trying to transfer unapproved', async () => {
                const expectedRevertMessage = 'ComposableTopDown: _transferFrom msg.sender not approved';
                await expect(composableTopDownInstance.connect(bob).transferFrom(alice.address, bob.address, expectedTokenId)).to.be.revertedWith(expectedRevertMessage);
            });

            it('Should revert when trying to transfer from zero address', async () => {
                const expectedRevertMessage = 'ComposableTopDown: _transferFrom _from zero address';
                await expect(composableTopDownInstance.transferFrom(zeroAddress, bob.address, expectedTokenId)).to.be.revertedWith(expectedRevertMessage);
            });

            it('Should revert when trying to transfer from not owner', async () => {
                const expectedRevertMessage = 'ComposableTopDown: _transferFrom _from not owner';
                await expect(composableTopDownInstance.transferFrom(nonUsed.address, bob.address, expectedTokenId)).to.be.revertedWith(expectedRevertMessage);
            });

            it('Should revert when trying to transfer to zero address', async () => {
                const expectedRevertMessage = 'ComposableTopDown: _transferFrom _to zero address';
                await expect(composableTopDownInstance.transferFrom(alice.address, zeroAddress, expectedTokenId)).to.be.revertedWith(expectedRevertMessage);
            });

            it('Should successfully transferFrom to bob', async () => {
                // when:
                await composableTopDownInstance.connect(alice).transferFrom(alice.address, bob.address, expectedTokenId);

                // then:
                const ownerOf = await composableTopDownInstance.ownerOf(expectedTokenId);
                assert(ownerOf === bob.address, 'Invalid owner');
            });

            it('Should successfully safeTransferFrom(3) to a contract', async () => {
                // given:
                const contractIERC721ReceiverOldInstance = await ContractIERC721ReceiverOld.deploy();

                const beforeTransferContractBalance = await composableTopDownInstance.balanceOf(contractIERC721ReceiverOldInstance.address);
                const beforeTransferAliceBalance = await composableTopDownInstance.balanceOf(alice.address);

                // when:
                await composableTopDownInstance.connect(alice)['safeTransferFrom(address,address,uint256)'](alice.address, contractIERC721ReceiverOldInstance.address, expectedTokenId);
                // then:
                const afterTransferContractBalance = await composableTopDownInstance.balanceOf(contractIERC721ReceiverOldInstance.address);
                assert(afterTransferContractBalance.eq(beforeTransferContractBalance.add(1)), 'Invalid contract balanceOf');

                const afterTransferAliceBalance = await composableTopDownInstance.balanceOf(alice.address);
                assert(afterTransferAliceBalance.eq(beforeTransferAliceBalance.sub(1)), 'Invalid alice balanceOf');

                const ownerOf = await composableTopDownInstance.ownerOf(expectedTokenId);
                assert(ownerOf === contractIERC721ReceiverOldInstance.address, 'Invalid token owner');
            });

            it('Should successfully safeTransferFrom(3) with bob used as intermediary', async () => {
                // given:
                const contractIERC721ReceiverOldInstance = await ContractIERC721ReceiverOld.deploy();
                await composableTopDownInstance.connect(alice).approve(bob.address, expectedTokenId);

                const beforeTransferContractBalance = await composableTopDownInstance.balanceOf(contractIERC721ReceiverOldInstance.address);
                const beforeTransferAliceBalance = await composableTopDownInstance.balanceOf(alice.address);

                // when:
                await composableTopDownInstance.connect(bob)['safeTransferFrom(address,address,uint256)'](alice.address, contractIERC721ReceiverOldInstance.address, expectedTokenId);
                // then:
                const afterTransferContractBalance = await composableTopDownInstance.balanceOf(contractIERC721ReceiverOldInstance.address);
                assert(afterTransferContractBalance.eq(beforeTransferContractBalance.add(1)), 'Invalid contract balanceOf');

                const afterTransferAliceBalance = await composableTopDownInstance.balanceOf(alice.address);
                assert(afterTransferAliceBalance.eq(beforeTransferAliceBalance.sub(1)), 'Invalid alice balanceOf');

                const ownerOf = await composableTopDownInstance.ownerOf(expectedTokenId);
                assert(ownerOf === contractIERC721ReceiverOldInstance.address, 'Invalid token owner');
            });

            it('Should successfully safeTransferFrom(4) to a contract', async () => {
                // given:
                const contractIERC721ReceiverOldInstance = await ContractIERC721ReceiverOld.deploy();
                const beforeTransferContractBalance = await composableTopDownInstance.balanceOf(contractIERC721ReceiverOldInstance.address);
                const beforeTransferAliceBalance = await composableTopDownInstance.balanceOf(alice.address);

                // when:
                await composableTopDownInstance.connect(alice)['safeTransferFrom(address,address,uint256,bytes)']
                    (alice.address,
                        contractIERC721ReceiverOldInstance.address,
                        expectedTokenId,
                        bytesFirstToken);
                // then:
                const afterTransferContractBalance = await composableTopDownInstance.balanceOf(contractIERC721ReceiverOldInstance.address);
                assert(afterTransferContractBalance.eq(beforeTransferContractBalance.add(1)), 'Invalid contract balanceOf');

                const afterTransferAliceBalance = await composableTopDownInstance.balanceOf(alice.address);
                assert(afterTransferAliceBalance.eq(beforeTransferAliceBalance.sub(1)), 'Invalid alice balanceOf');

                const ownerOf = await composableTopDownInstance.ownerOf(expectedTokenId);
                assert(ownerOf === contractIERC721ReceiverOldInstance.address, 'Invalid token owner');
            });

            it('Should revert when trying to safeTransferFrom(4) to a contract with != ERC721_RECEIVED_OLD', async () => {
                // given:
                const contractIERC721ReceiverNewInstance = await ContractIERC721ReceiverNew.deploy();
                const expectedRevertMessage = 'ComposableTopDown: safeTransferFrom(4) onERC721Received invalid return value';

                // then:
                await expect(composableTopDownInstance
                    .connect(alice)
                ['safeTransferFrom(address,address,uint256,bytes)']
                    (alice.address,
                        contractIERC721ReceiverNewInstance.address,
                        expectedTokenId,
                        bytesFirstToken), expectedRevertMessage).to.be.revertedWith(expectedRevertMessage);
            });

            it('Should successfully return back token', async () => {
                // given:
                await composableTopDownInstance.connect(alice).transferFrom(alice.address, bob.address, expectedTokenId);

                // when:
                await composableTopDownInstance
                    .connect(bob)['transferChild(uint256,address,address,uint256)'](
                        expectedTokenId,
                        alice.address,
                        sampleNFTInstance.address,
                        expectedTokenId
                    );

                // then:
                const owner = await sampleNFTInstance.ownerOf(expectedTokenId);
                assert(owner === alice.address, 'Invalid owner address');

                const totalChildContracts = await composableTopDownInstance.totalChildContracts(expectedTokenId);
                assert(totalChildContracts.eq(0), 'Invalid child contracts length');

                const childExists = await composableTopDownInstance.childExists(sampleNFTInstance.address, expectedTokenId);
                assert(!childExists, 'child contract exists');
            });

            describe('safeTransferChild', async () => {
                const secondToken = 2;
                const secondChildTokenId = 2;
                const secondNFTHash = '0x5678';
                const bytesSecondToken = ethers.utils.hexZeroPad('0x2', 32);
                const expectedFirstTokenTotalChildTokens = 1;

                beforeEach(async () => {
                    await composableTopDownInstance.safeMint(alice.address);
                    await sampleNFTInstance.mint721(alice.address, secondNFTHash);

                    await sampleNFTInstance
                        .connect(alice)['safeTransferFrom(address,address,uint256,bytes)'](
                            alice.address,
                            composableTopDownInstance.address,
                            secondToken,
                            bytesSecondToken);
                });

                it('Should have successfully transferred secondToken', async () => {
                    // then:
                    const childExists = await composableTopDownInstance.childExists(sampleNFTInstance.address, secondChildTokenId);
                    assert(childExists, 'Composable does not own SampleNFT');

                    const ownerOfChild = await composableTopDownInstance.ownerOfChild(sampleNFTInstance.address, secondChildTokenId);
                    assert(ownerOfChild.parentTokenId.eq(secondToken), 'Invalid parent token id');

                    const rootOwnerOfChild = await composableTopDownInstance.rootOwnerOfChild(sampleNFTInstance.address, secondChildTokenId);
                    assert(rootOwnerOfChild === aliceBytes32Address, 'Invalid root owner of second child token');

                    const totalChildContracts = await composableTopDownInstance.totalChildContracts(secondToken);
                    assert(totalChildContracts.eq(1), 'Invalid total child contracts');

                    const childContractAddress = await composableTopDownInstance.childContractByIndex(secondToken, 0);
                    assert(childContractAddress === sampleNFTInstance.address, 'Invalid child contract address');

                    const tokenId = await composableTopDownInstance.childTokenByIndex(secondToken, sampleNFTInstance.address, 0);
                    assert(tokenId.eq(secondToken), 'Invalid token id found when querying child token by index');

                    const totalChildTokens = await composableTopDownInstance.totalChildTokens(expectedTokenId, sampleNFTInstance.address);
                    assert(totalChildTokens.eq(expectedFirstTokenTotalChildTokens), 'Invalid total child tokens');
                });

                it('Should successfully safeTransferChild(5)', async () => {
                    // given:
                    const expectedRootOwnerOfChild = aliceBytes32Address;

                    // when:
                    await composableTopDownInstance
                        .connect(alice)['safeTransferChild(uint256,address,address,uint256,bytes)'](
                            secondToken,
                            composableTopDownInstance.address,
                            sampleNFTInstance.address,
                            secondToken,
                            bytesFirstToken
                        );

                    // then:
                    const contractByIndex = await composableTopDownInstance.childContractByIndex(expectedTokenId, 0);
                    assert(contractByIndex === sampleNFTInstance.address, 'Invalid child contract by index');

                    const childExists = await composableTopDownInstance.childExists(sampleNFTInstance.address, secondToken);
                    assert(childExists, 'SecondToken does not exist as child to SampleNFT');

                    const totalChildContracts = await composableTopDownInstance.totalChildContracts(expectedTokenId);
                    assert(totalChildContracts.eq(1), 'Invalid total child contracts');

                    const owner = await sampleNFTInstance.ownerOf(secondToken);
                    assert(owner === composableTopDownInstance.address, 'ComposableTopDown is not owner SecondToken');

                    const ownerOfChild = await composableTopDownInstance.ownerOfChild(sampleNFTInstance.address, secondToken);
                    assert(ownerOfChild.parentTokenId.eq(expectedTokenId), 'Invalid SampleNFT child token 2 owner');

                    const rootOwnerOfChild = await composableTopDownInstance.rootOwnerOfChild(zeroAddress, secondToken);
                    assert(rootOwnerOfChild === expectedRootOwnerOfChild, 'Invalid rootOwnerOfChild token 2');
                });

                it('Should successfully safeTransferChild(4)', async () => {
                    // given:
                    const expectedRootOwnerOfChild = aliceBytes32Address;

                    // when:
                    await composableTopDownInstance
                        .connect(alice)['safeTransferChild(uint256,address,address,uint256)'](
                            secondToken,
                            composableTopDownInstance.address,
                            sampleNFTInstance.address,
                            secondToken
                        );

                    // then:
                    const contractByIndex = await composableTopDownInstance.childContractByIndex(expectedTokenId, 0);
                    assert(contractByIndex === sampleNFTInstance.address, 'Invalid child contract by index');

                    const childExists = await composableTopDownInstance.childExists(sampleNFTInstance.address, secondToken);
                    assert(childExists, 'SecondToken does not exist as child to SampleNFT');

                    const totalChildContracts = await composableTopDownInstance.totalChildContracts(expectedTokenId);
                    assert(totalChildContracts.eq(1), 'Invalid total child contracts');

                    const owner = await sampleNFTInstance.ownerOf(secondToken);
                    assert(owner === composableTopDownInstance.address, 'ComposableTopDown is not owner SecondToken');

                    const ownerOfChild = await composableTopDownInstance.ownerOfChild(sampleNFTInstance.address, secondToken);
                    assert(ownerOfChild.parentTokenId.eq(expectedTokenId), 'Invalid SampleNFT child token 2 owner');

                    const rootOwnerOfChild = await composableTopDownInstance.rootOwnerOfChild(zeroAddress, secondToken);
                    assert(rootOwnerOfChild === expectedRootOwnerOfChild, 'Invalid rootOwnerOfChild token 2');
                });
            });

            it('Should not allow circular ownership (1)', async () => {
                // the second token, token id = 2
                await composableTopDownInstance.safeMint(alice.address);
                // transfer 2 -> 1
                await composableTopDownInstance.connect(alice)['safeTransferFrom(address,address,uint256,bytes)']
                    (alice.address,
                        composableTopDownInstance.address,
                        2,
                        bytesFirstToken);
                // transfer 1 -> 2
                const bytesSecondToken = ethers.utils.hexZeroPad('0x2', 20);
                let res = await composableTopDownInstance.connect(alice)['safeTransferFrom(address,address,uint256,bytes)']
                    (alice.address,
                        composableTopDownInstance.address,
                        1,
                        bytesSecondToken).then((result) => {return null;}).catch((err) => {return err;});
                expect(res).to.exist;
                expect(res['message']).to.be.eq('Transaction reverted: contract call run out of gas and made the transaction revert');
            });

            it('Should not allow circular ownership (2)', async () => {
                // the second token, token id = 2
                await composableTopDownInstance.safeMint(alice.address);
                // the third token, token id = 3
                await composableTopDownInstance.safeMint(alice.address);
                // transfer 2 -> 1
                await composableTopDownInstance.connect(alice)['safeTransferFrom(address,address,uint256,bytes)']
                    (alice.address,
                        composableTopDownInstance.address,
                        2,
                        bytesFirstToken);
                // transfer 3 -> 2
                const bytesSecondToken = ethers.utils.hexZeroPad('0x2', 20);
                await composableTopDownInstance.connect(alice)['safeTransferFrom(address,address,uint256,bytes)']
                    (alice.address,
                        composableTopDownInstance.address,
                        3,
                        bytesSecondToken);
                // transfer 2 -> 3
                const bytesThirdToken = ethers.utils.hexZeroPad('0x3', 20);
                let res = await composableTopDownInstance.connect(alice)['safeTransferChild(uint256,address,address,uint256,bytes)']
                    (1,
                        composableTopDownInstance.address,
                        composableTopDownInstance.address,
                        2,
                        bytesThirdToken).then((result) => {return null;}).catch((err) => {return err;});
                expect(res).to.exist;
                expect(res['message']).to.be.eq('Transaction reverted: contract call run out of gas and made the transaction revert');
            });

        });
    });


    describe('ERC20 Transfers', async () => {
        const mintTokensAmount = 1000;
        const name = 'SampleERC20';
        const symbol = 'S';
        const transferAmount = mintTokensAmount / 2;
        const secondTransferAmount = transferAmount / 2;

        beforeEach(async () => {
            sampleERC20Instance = await SampleERC20.deploy(name, symbol);

            // mint
            await sampleERC20Instance.mint(alice.address, mintTokensAmount);

            await composableTopDownInstance.safeMint(alice.address);
        });

        it('Should have proper token balance', async () => {
            const aliceBalance = await sampleERC20Instance.balanceOf(alice.address);
            assert(aliceBalance.eq(mintTokensAmount), 'Invalid initial token balance');
        });

        it('Should transfer half the value from ERC20 to Composable', async () => {
            // when:
            await sampleERC20Instance
                .connect(alice)['transfer(address,uint256,bytes)'](
                    composableTopDownInstance.address,
                    transferAmount,
                    bytesFirstToken
                );

            // then:
            const totalERC20Contracts = await composableTopDownInstance.totalERC20Contracts(expectedTokenId);
            assert(totalERC20Contracts.eq(1), 'Invalid total erc20 contracts');

            const balance = await composableTopDownInstance
                .balanceOfERC20(expectedTokenId, sampleERC20Instance.address);
            assert(balance.eq(transferAmount), 'Invalid Composable ERC20 balance');

            const erc20ContractByIndex = await composableTopDownInstance.erc20ContractByIndex(expectedTokenId, 0);
            assert(erc20ContractByIndex === sampleERC20Instance.address, 'Invalid erc20 contract by index');
        });

        it('Should transfer from Composable to bob via transferERC20', async () => {
            // given:
            await sampleERC20Instance
                .connect(alice)['transfer(address,uint256,bytes)'](
                    composableTopDownInstance.address,
                    transferAmount,
                    bytesFirstToken
                );

            // when:
            await composableTopDownInstance
                .connect(alice)
                .transferERC20(
                    expectedTokenId,
                    bob.address,
                    sampleERC20Instance.address,
                    secondTransferAmount
                );

            // then:
            const composableBalance = await composableTopDownInstance
                .balanceOfERC20(expectedTokenId, sampleERC20Instance.address);
            assert(composableBalance.eq(secondTransferAmount), 'Invalid Composable ERC20 balance');

            const bobBalance = await sampleERC20Instance.balanceOf(bob.address);
            assert(bobBalance.eq(secondTransferAmount), 'Invalid bob balance');
        });

        it('Should transfer from Composable to bob via transferERC223', async () => {
            // given:
            await sampleERC20Instance
                .connect(alice)['transfer(address,uint256,bytes)'](
                    composableTopDownInstance.address,
                    transferAmount,
                    bytesFirstToken
                );

            // when:
            await composableTopDownInstance
                .connect(alice)
                .transferERC223(
                    expectedTokenId,
                    bob.address,
                    sampleERC20Instance.address,
                    secondTransferAmount,
                    bytesFirstToken
                );

            // then:
            const composableBalance = await composableTopDownInstance
                .balanceOfERC20(expectedTokenId, sampleERC20Instance.address);
            assert(composableBalance.eq(secondTransferAmount), 'Invalid Composable ERC20 balance');

            const bobBalance = await sampleERC20Instance.balanceOf(bob.address);
            assert(bobBalance.eq(secondTransferAmount), 'Invalid bob balance');
        });

        it('Should transfer everything from Composable to bob via transferERC223', async () => {
            // given:
            await sampleERC20Instance
                .connect(alice)['transfer(address,uint256,bytes)'](
                    composableTopDownInstance.address,
                    transferAmount,
                    bytesFirstToken
                );

            // when:
            await composableTopDownInstance
                .connect(alice)
                .transferERC223(
                    expectedTokenId,
                    bob.address,
                    sampleERC20Instance.address,
                    transferAmount,
                    bytesFirstToken
                );

            // then:
            const composableBalance = await composableTopDownInstance
                .balanceOfERC20(expectedTokenId, sampleERC20Instance.address);
            assert(composableBalance.eq(0), 'Invalid Composable ERC20 balance');

            const bobBalance = await sampleERC20Instance.balanceOf(bob.address);
            assert(bobBalance.eq(transferAmount), 'Invalid bob balance');

            const totalERC20Contracts = await composableTopDownInstance.totalERC20Contracts(expectedTokenId);
            assert(totalERC20Contracts.eq(0), 'Invalid total erc20 contracts');
        });

        it('Should transfer 0 from Composable to bob via transferERC223', async () => {
            // given:
            await sampleERC20Instance
                .connect(alice)['transfer(address,uint256,bytes)'](
                    composableTopDownInstance.address,
                    transferAmount,
                    bytesFirstToken
                );

            // when:
            await composableTopDownInstance
                .connect(alice)
                .transferERC223(
                    expectedTokenId,
                    bob.address,
                    sampleERC20Instance.address,
                    0,
                    bytesFirstToken
                );

            // then:
            const composableBalance = await composableTopDownInstance
                .balanceOfERC20(expectedTokenId, sampleERC20Instance.address);
            assert(composableBalance.eq(transferAmount), 'Invalid Composable ERC20 balance');

            const bobBalance = await sampleERC20Instance.balanceOf(bob.address);
            assert(bobBalance.eq(0), 'Invalid bob balance');
        });

        it('Should get tokens using getERC20', async () => {
            // given:
            await sampleERC20Instance.connect(alice).approve(composableTopDownInstance.address, transferAmount);

            // when:
            await composableTopDownInstance.connect(alice)
                .getERC20(
                    alice.address,
                    expectedTokenId,
                    sampleERC20Instance.address,
                    transferAmount);

            // then:
            const composableBalance = await composableTopDownInstance
                .balanceOfERC20(expectedTokenId, sampleERC20Instance.address);
            assert(composableBalance.eq(transferAmount), 'Invalid Composable ERC20 balance');

            const erc20ComposableBalance = await sampleERC20Instance.balanceOf(composableTopDownInstance.address);
            assert(erc20ComposableBalance.eq(composableBalance), 'Invalid ERC20 Composable balance');
        });

        it('Should get 0 tokens using getERC20', async () => {
            // given:
            await sampleERC20Instance.connect(alice).approve(composableTopDownInstance.address, transferAmount);

            // when:
            await composableTopDownInstance.connect(alice)
                .getERC20(
                    alice.address,
                    expectedTokenId,
                    sampleERC20Instance.address,
                    0);

            // then:
            const composableBalance = await composableTopDownInstance
                .balanceOfERC20(expectedTokenId, sampleERC20Instance.address);
            assert(composableBalance.eq(0), 'Invalid Composable ERC20 balance');

            const erc20ComposableBalance = await sampleERC20Instance.balanceOf(composableTopDownInstance.address);
            assert(erc20ComposableBalance.eq(0), 'Invalid ERC20 Composable balance');
        });

        it('Should revert getERC20 with invalid contract address', async () => {
            const expectedRevertMessage = 'ComposableTopDown: getERC20 allowance failed';
            await expect(
                composableTopDownInstance
                    .connect(bob)
                    .getERC20(
                        alice.address,
                        expectedTokenId,
                        composableTopDownInstance.address,
                        transferAmount)).to.be.revertedWith(
                            expectedRevertMessage);
        });

        it('Should revert getERC20 allowed address not enough amount', async () => {
            const expectedRevertMessage = 'ComposableTopDown: getERC20 value greater than remaining';
            // when:
            await expect(
                composableTopDownInstance
                    .connect(bob)
                    .getERC20(
                        alice.address,
                        expectedTokenId,
                        sampleERC20Instance.address,
                        transferAmount)).to.be.revertedWith(
                            expectedRevertMessage);
        });

        it('Should get tokens using getERC20, using bob as approved sender', async () => {
            // given:
            await sampleERC20Instance.connect(alice).approve(bob.address, transferAmount);
            await sampleERC20Instance.connect(alice).approve(composableTopDownInstance.address, transferAmount);

            // when:
            await composableTopDownInstance.connect(bob)
                .getERC20(
                    alice.address,
                    expectedTokenId,
                    sampleERC20Instance.address,
                    transferAmount);

            // then:
            const composableBalance = await composableTopDownInstance
                .balanceOfERC20(expectedTokenId, sampleERC20Instance.address);
            assert(composableBalance.eq(transferAmount), 'Invalid Composable ERC20 balance');

            const erc20ComposableBalance = await sampleERC20Instance.balanceOf(composableTopDownInstance.address);
            assert(erc20ComposableBalance.eq(composableBalance), 'Invalid ERC20 Composable balance');
        });
    });

    describe('Multi Token tests', async () => {
        const mintTokensAmount = 1000;
        const transferAmount = 500;
        const totalTokens = 5;
        const mintedPerNFT = 3;

        beforeEach(async () => {
            await composableTopDownInstance.safeMint(alice.address);
        });

        it('Should return proper totals after addition and removal', async () => {
            // given:
            const [nfts, erc20s] = await setUpTestTokens(totalTokens, totalTokens);

            // when:

            // transfer erc20s
            for (let i = 0; i < erc20s.length; i++) {
                await erc20s[i].mint(alice.address, mintTokensAmount);
                await erc20s[i].connect(alice)['transfer(address,uint256,bytes)'](
                    composableTopDownInstance.address,
                    transferAmount,
                    bytesFirstToken
                );

                const balance = await composableTopDownInstance.balanceOfERC20(expectedTokenId, erc20s[i].address);
                assert(balance.eq(transferAmount), `Invalid balanceOfERC20 on Token ${i}`);
            }

            const totalERC20TokensAdded = await composableTopDownInstance.totalERC20Contracts(expectedTokenId);
            assert(totalERC20TokensAdded.eq(totalTokens), 'Invalid Alice total ERC20 cotracts');

            // transfer nfts
            for (let i = 0; i < nfts.length; i++) {
                for (let j = 0; j < mintedPerNFT; j++) {
                    await nfts[i].mint721(alice.address, `${i}${j}`);
                    const mintedTokenId = j + 1;
                    await nfts[i].connect(alice)['safeTransferFrom(address,address,uint256,bytes)'](
                        alice.address,
                        composableTopDownInstance.address,
                        mintedTokenId,
                        bytesFirstToken);
                }
                const nftChildren = await composableTopDownInstance.totalChildTokens(expectedTokenId, nfts[i].address);
                assert(nftChildren.eq(mintedPerNFT), `Invalid nft children for ${i}`);
            }

            const totalChildContracts = await composableTopDownInstance.totalChildContracts(expectedTokenId);
            assert(totalChildContracts.eq(totalTokens), 'Invalid child tokens contracts count');

            // remove erc20s
            let tokenERC20Contracts = await composableTopDownInstance.totalERC20Contracts(expectedTokenId);

            for (let i = 0; i < tokenERC20Contracts; i++) {
                const tokenAddress = await composableTopDownInstance.erc20ContractByIndex(expectedTokenId, i);
                const balance = await composableTopDownInstance.balanceOfERC20(expectedTokenId, tokenAddress);

                await composableTopDownInstance.connect(alice).transferERC20(expectedTokenId, alice.address, tokenAddress, balance);
                const nextNumTotalERC20Contracts = await composableTopDownInstance.totalERC20Contracts(expectedTokenId);

                assert(nextNumTotalERC20Contracts.eq(tokenERC20Contracts.sub(1)), `Expected ${tokenERC20Contracts - 1} tokenContracts but got ${nextNumTotalERC20Contracts}`);
                tokenERC20Contracts = nextNumTotalERC20Contracts;
            }

            // remove nfts
            let totalNFTsContracts = await composableTopDownInstance.totalChildContracts(expectedTokenId);

            for (let i = totalNFTsContracts; i > 0; i--) {
                const contractAddress = await composableTopDownInstance.childContractByIndex(expectedTokenId, i - 1);
                let totalChildTokens = await composableTopDownInstance.totalChildTokens(expectedTokenId, contractAddress);

                for (let j = totalChildTokens; j > 0; j--) {
                    const childTokenId = await composableTopDownInstance.childTokenByIndex(expectedTokenId, contractAddress, j - 1);
                    await composableTopDownInstance.connect(alice)['safeTransferChild(uint256,address,address,uint256)'](
                        expectedTokenId,
                        alice.address,
                        contractAddress,
                        childTokenId
                    );

                    const totalChildTokensAfterRemoval = await composableTopDownInstance.totalChildTokens(expectedTokenId, contractAddress);
                    assert(totalChildTokensAfterRemoval.eq(j - 1), 'Invalid totalChildTokens after removal');
                }

                const totalChildContractsAfterRemoval = await composableTopDownInstance.totalChildContracts(expectedTokenId);
                assert(totalChildContractsAfterRemoval.eq(i - 1), 'Invalid totalChildContracts after removal');
            }
        });
    });

    describe('Between Composables / Gas Usages', async () => {
        const bytesSecondToken = ethers.utils.hexZeroPad('0x2', 32);

        describe('5 NFTs from 1 type', async () => {
            beforeEach(async () => {
                sampleNFTInstance = await SampleNFT.deploy();

                await composableTopDownInstance.safeMint(alice.address);
                await composableTopDownInstance.safeMint(bob.address);

                for (let i = 1; i <= 5; i++) {
                    await sampleNFTInstance.mint721(alice.address, i.toString());
                    await sampleNFTInstance
                        .connect(alice)['safeTransferFrom(address,address,uint256,bytes)'](
                            alice.address,
                            composableTopDownInstance.address,
                            i,
                            bytesFirstToken);
                }
            });


            it('Should transfer to bob 5 1 Type NFTs', async () => {
                // when:
                for (let i = 1; i <= 5; i++) {
                    await composableTopDownInstance
                        .connect(alice)['safeTransferChild(uint256,address,address,uint256,bytes)'](
                            expectedTokenId,
                            composableTopDownInstance.address,
                            sampleNFTInstance.address,
                            i,
                            bytesSecondToken
                        );
                }
            });
        });

        describe('5 different NFTs', async () => {
            beforeEach(async () => {
                await composableTopDownInstance.safeMint(alice.address);
                await composableTopDownInstance.safeMint(bob.address);

                const [nfts, _] = await setUpTestTokens(5, 0);
                nftInstances = nfts;

                for (let i = 0; i < nftInstances.length; i++) {
                    await nftInstances[i].mint721(alice.address, i.toString());
                    await nftInstances[i].connect(alice)['safeTransferFrom(address,address,uint256,bytes)'](
                        alice.address,
                        composableTopDownInstance.address,
                        1,
                        bytesFirstToken);
                }
            });

            it('Should successfully transfer 5 NFTs to bob', async () => {
                for (let i = 0; i < nftInstances.length; i++) {
                    await composableTopDownInstance
                        .connect(alice)['safeTransferChild(uint256,address,address,uint256,bytes)'](
                            expectedTokenId,
                            composableTopDownInstance.address,
                            nftInstances[i].address,
                            1,
                            bytesSecondToken
                        );
                }
            });
        });
    });

    describe('Between ComposableTopDowns / Gas Usages', async () => {
        beforeEach(async () => {
            secondComposableTopDownInstance = await ComposableTopDown.deploy();

            await composableTopDownInstance.safeMint(alice.address);
            await secondComposableTopDownInstance.safeMint(bob.address);
        });

        describe('NFTs', async () => {
            beforeEach(async () => {
                sampleNFTInstance = await SampleNFT.deploy();
                // mint
                await sampleNFTInstance.mint721(alice.address, NFTHash);

                await safeTransferFromFirstToken();
            });

            it('Should successfully transfer tokenId to ComposableTopDown', async () => {
                // given:
                const expectedRootOwnerOfChild = ethers.utils.hexConcat([ERC998_MAGIC_VALUE, ethers.utils.hexZeroPad(secondComposableTopDownInstance.address, 28).toLowerCase()]);

                // WARNING: never ever do that, direct transferring a token to another composable causes that the token get stuck!
                // when:
                await composableTopDownInstance.connect(alice)
                    .transferFrom(alice.address, secondComposableTopDownInstance.address, expectedTokenId);

                // then:
                const owner = await composableTopDownInstance.rootOwnerOfChild(sampleNFTInstance.address, expectedTokenId);
                assert(owner === expectedRootOwnerOfChild, 'Invalid owner');
            });

            it('Should successfully transfer ERC998 to SecondComposable', async () => {
                // given:
                const expectedRootOwnerOf = ethers.utils.hexConcat([ERC998_MAGIC_VALUE, ethers.utils.hexZeroPad(secondComposableTopDownInstance.address, 28).toLowerCase()]);
                const expectedSecondComposableRootOwnerOf = ethers.utils.hexConcat([ERC998_MAGIC_VALUE, ethers.utils.hexZeroPad(bob.address, 28).toLowerCase()]);

                await composableTopDownInstance.connect(alice)['safeTransferFrom(address,address,uint256,bytes)'](
                    alice.address,
                    secondComposableTopDownInstance.address,
                    expectedTokenId,
                    bytesFirstToken
                );

                const owner = await composableTopDownInstance.ownerOf(expectedTokenId);
                assert(owner === secondComposableTopDownInstance.address, 'Invalid address');

                const totalChildContracts = await secondComposableTopDownInstance.totalChildContracts(expectedTokenId);
                assert(totalChildContracts.eq(1), 'Invalid total child contracts');

                const rootOwnerOf = await composableTopDownInstance.rootOwnerOf(expectedTokenId);
                assert(rootOwnerOf === expectedSecondComposableRootOwnerOf, 'Invalid first composable rootOwnerOf');
                const ownerOf = await secondComposableTopDownInstance.rootOwnerOfChild(composableTopDownInstance.address, expectedTokenId);
                assert(ownerOf === expectedSecondComposableRootOwnerOf, 'Invalid second composable rootOwnerOfChild');
            });

            it('Should successfully transfer NFT from ComposableTopDown to ComposableTopDown', async () => {
                // given:
                const expectedFirstComposableChildContracts = 0;
                const expectedSecondComposableChildContracts = 1;
                // when:
                await composableTopDownInstance.connect(alice)['safeTransferChild(uint256,address,address,uint256,bytes)'](
                    expectedTokenId,
                    secondComposableTopDownInstance.address,
                    sampleNFTInstance.address,
                    firstChildTokenId,
                    bytesFirstToken
                );

                // then:
                // First Composable
                const composableFirstChildContracts = await composableTopDownInstance.totalChildContracts(firstChildTokenId);
                assert(composableFirstChildContracts.eq(expectedFirstComposableChildContracts), 'Invalid First Composable Child Contracts');

                const firstComposableChildExists = await composableTopDownInstance.childExists(sampleNFTInstance.address, firstChildTokenId);
                assert(!firstComposableChildExists, 'First Composable Child exists');

                await expect(composableTopDownInstance.ownerOfChild(sampleNFTInstance.address, firstChildTokenId)).to.be.revertedWith('ComposableTopDown: ownerOfChild not found');

                await expect(composableTopDownInstance.childContractByIndex(expectedTokenId, 0)).to.be.revertedWith('EnumerableSet: index out of bounds');

                await expect(composableTopDownInstance.childTokenByIndex(expectedTokenId, sampleNFTInstance.address, 0)).to.be.revertedWith('EnumerableSet: index out of bounds');

                const firstComposableTotalChildTokens = await composableTopDownInstance.totalChildTokens(expectedTokenId, sampleNFTInstance.address);
                assert(firstComposableTotalChildTokens.eq(0), 'Invalid First Composable Total Child Tokens');

                // Second Composable:
                const childExists = await secondComposableTopDownInstance.childExists(sampleNFTInstance.address, firstChildTokenId);
                assert(childExists, 'Composable does not own SampleNFT');

                const ownerOfChild = await secondComposableTopDownInstance.ownerOfChild(sampleNFTInstance.address, firstChildTokenId);
                assert(ownerOfChild.parentTokenId.eq(expectedTokenId), 'Invalid parent token id');

                const totalChildContracts = await secondComposableTopDownInstance.totalChildContracts(expectedTokenId);
                assert(totalChildContracts.eq(expectedSecondComposableChildContracts), 'Invalid total child contracts');

                const childContractAddress = await secondComposableTopDownInstance.childContractByIndex(expectedTokenId, 0);
                assert(childContractAddress === sampleNFTInstance.address, 'Invalid child contract address');

                const tokenId = await secondComposableTopDownInstance.childTokenByIndex(expectedTokenId, sampleNFTInstance.address, 0);
                assert(tokenId.eq(expectedTokenId), 'Invalid token id found when querying child token by index');

                const secondComposableTotalChildTokens = await secondComposableTopDownInstance.totalChildTokens(expectedTokenId, sampleNFTInstance.address);
                assert(secondComposableTotalChildTokens.eq(1), 'Invalid First Composable Total Child Tokens');

                // SampleNFT
                const owner = await sampleNFTInstance.ownerOf(expectedTokenId);
                assert(owner === secondComposableTopDownInstance.address, 'Invalid NFT Owner');
            });

            describe('Transfer 5 NFTs to another Composable token id', async () => {
                beforeEach('Mint additional 4 NFTs', async () => {
                    for (let i = 1; i <= 4; i++) {
                        await sampleNFTInstance.mint721(alice.address, i.toString());
                        await sampleNFTInstance
                            .connect(alice)['safeTransferFrom(address,address,uint256,bytes)'](
                                alice.address,
                                composableTopDownInstance.address,
                                i + 1,
                                bytesFirstToken);
                    }
                });

                it('Should successfully transfer 5 NFTs', async () => {
                    // when:
                    for (let i = 1; i <= 5; i++) {
                        await composableTopDownInstance.connect(alice)['safeTransferChild(uint256,address,address,uint256,bytes)'](
                            expectedTokenId,
                            secondComposableTopDownInstance.address,
                            sampleNFTInstance.address,
                            i,
                            bytesFirstToken
                        );
                    }
                    // then:
                    const firstComposableTotalChildTokens = await composableTopDownInstance.totalChildTokens(expectedTokenId, sampleNFTInstance.address);
                    assert(firstComposableTotalChildTokens.eq(0), 'Invalid First Composable Total Child Tokens');

                    const secondComposableTotalChildTokens = await secondComposableTopDownInstance.totalChildTokens(expectedTokenId, sampleNFTInstance.address);
                    assert(secondComposableTotalChildTokens.eq(5), 'Invalid First Composable Total Child Tokens');
                });
            });
        });

        describe('Transfer ERC20 from ComposableTopDown to ComposableTopDown', async () => {
            const mintTokensAmount = 1000;
            const name = 'SampleERC20';
            const symbol = 'S';
            const transferAmount = mintTokensAmount / 2;
            const secondTransferAmount = transferAmount / 2;

            beforeEach(async () => {
                sampleERC20Instance = await SampleERC20.deploy(name, symbol);
                // mint
                await sampleERC20Instance.mint(alice.address, mintTokensAmount);

                // transfer to first composable
                await sampleERC20Instance
                    .connect(alice)['transfer(address,uint256,bytes)'](
                        composableTopDownInstance.address,
                        transferAmount,
                        bytesFirstToken
                    );
            });

            it('Should successfully transferERC20 half the amount', async () => {
                // when:
                await composableTopDownInstance.connect(alice)
                    .transferERC20(
                        expectedTokenId,
                        secondComposableTopDownInstance.address,
                        sampleERC20Instance.address,
                        secondTransferAmount
                    );
                const firstComposableBalance = await sampleERC20Instance.balanceOf(composableTopDownInstance.address);
                const secondComposableBalance = await sampleERC20Instance.balanceOf(secondComposableTopDownInstance.address);

                assert(firstComposableBalance.eq(secondComposableBalance), 'Invalid balances');
            });

            it('Should successfully transferERC20 everything', async () => {
                // when:
                await composableTopDownInstance.connect(alice)
                    .transferERC20(
                        expectedTokenId,
                        secondComposableTopDownInstance.address,
                        sampleERC20Instance.address,
                        transferAmount
                    );

                const firstComposableBalance = await sampleERC20Instance.balanceOf(composableTopDownInstance.address);
                const secondComposableBalance = await sampleERC20Instance.balanceOf(secondComposableTopDownInstance.address);

                assert(firstComposableBalance.eq(0), 'Invalid first composable balance');
                assert(secondComposableBalance.eq(transferAmount), 'Invalid second composable balance');
            });

            it('Should successfully transferERC223 half the amount', async () => {
                // when:
                await composableTopDownInstance.connect(alice)
                    .transferERC223(
                        expectedTokenId,
                        secondComposableTopDownInstance.address,
                        sampleERC20Instance.address,
                        secondTransferAmount,
                        bytesFirstToken
                    );

                const firstComposableBalance = await sampleERC20Instance.balanceOf(composableTopDownInstance.address);
                const secondComposableBalance = await sampleERC20Instance.balanceOf(secondComposableTopDownInstance.address);

                assert(firstComposableBalance.eq(secondComposableBalance), 'Invalid balances');
            });

            it('Should successfully transferERC223 everything', async () => {
                // when:
                await composableTopDownInstance.connect(alice)
                    .transferERC223(
                        expectedTokenId,
                        secondComposableTopDownInstance.address,
                        sampleERC20Instance.address,
                        transferAmount,
                        bytesFirstToken
                    );
                const firstComposableBalance = await sampleERC20Instance.balanceOf(composableTopDownInstance.address);
                const secondComposableBalance = await sampleERC20Instance.balanceOf(secondComposableTopDownInstance.address);

                assert(firstComposableBalance.eq(0), 'Invalid first composable balance');
                assert(secondComposableBalance.eq(transferAmount), 'Invalid second composable balance');
            });

            it('Should successfully transferERC223 everything on 5 portions', async () => {
                // given:
                const portion = transferAmount / 5;

                // when:
                for (let i = 0; i < 5; i++) {
                    await composableTopDownInstance.connect(alice)
                        .transferERC223(
                            expectedTokenId,
                            secondComposableTopDownInstance.address,
                            sampleERC20Instance.address,
                            portion,
                            bytesFirstToken
                        );
                }

                const firstComposableBalance = await sampleERC20Instance.balanceOf(composableTopDownInstance.address);
                const secondComposableBalance = await sampleERC20Instance.balanceOf(secondComposableTopDownInstance.address);

                assert(firstComposableBalance.eq(0), 'Invalid first composable balance');
                assert(secondComposableBalance.eq(transferAmount), 'Invalid second composable balance');

                const firstComposableTokenIdBalance = await composableTopDownInstance
                    .balanceOfERC20(expectedTokenId, sampleERC20Instance.address);
                assert(firstComposableTokenIdBalance.eq(0), 'Invalid first composable tokenId balance');

                const secondComposableTokenIdBalance = await secondComposableTopDownInstance
                    .balanceOfERC20(expectedTokenId, sampleERC20Instance.address);
                assert(secondComposableTokenIdBalance.eq(transferAmount), 'Invalid second composable tokenId balance');
            });
        });
    });

    describe('Multiple TopDowns scenario', async () => {
        const bytesFirst = ethers.utils.hexZeroPad('0x1', 32);
        const bytesSecond = ethers.utils.hexZeroPad('0x2', 32);
        const bytesThird = ethers.utils.hexZeroPad('0x3', 32);

        beforeEach(async () => {
            // Introduce ComposableTopDown, which represents accounts, (e.g. alice and bob have accounts)
            // Introduce ComposableTopDown, which represents characters
            // Introduce ComposableTopDown, which represents weapons (e.g. axes, swords, etc.)
            // Introduce ERC721, which represents enchantments
            // Accounts can have characters, characters can have weapons, weapons can have enchantments

            // Create alice and bob accounts
            erc998Accounts = await ComposableTopDown.connect(owner).deploy();
            await erc998Accounts.safeMint(alice.address);
            await erc998Accounts.safeMint(bob.address);

            // Create two characters
            erc998Characters = await ComposableTopDown.connect(owner).deploy();
            await erc998Characters.safeMint(owner.address); // first character
            await erc998Characters.safeMint(owner.address); // second character

            erc998Weapons = await ComposableTopDown.connect(owner).deploy();
            await erc998Weapons.safeMint(owner.address); // id 1
            await erc998Weapons.safeMint(owner.address); // id 2
            await erc998Weapons.safeMint(owner.address); // id 3
        });

        it('Should successfully populate accounts and then showcase how the deepest level NFT is transferred', async () => {
            erc721Enchantments = await SampleNFT.connect(owner).deploy();

            // Mint enchantments
            await erc721Enchantments.mint721(owner.address, 'enchantment1'); // id 1
            await erc721Enchantments.mint721(owner.address, 'enchantment2'); // id 2
            await erc721Enchantments.mint721(owner.address, 'enchantment3'); // id 3
            await erc721Enchantments.mint721(owner.address, 'enchantment4'); // id 4

            // Transfer 1,2 to first weapon, 3 to second weapon, 4 to third weapon
            await erc721Enchantments['safeTransferFrom(address,address,uint256,bytes)'](
                owner.address,
                erc998Weapons.address,
                1,
                bytesFirst);
            await erc721Enchantments['safeTransferFrom(address,address,uint256,bytes)'](
                owner.address,
                erc998Weapons.address,
                2,
                bytesFirst);
            await erc721Enchantments['safeTransferFrom(address,address,uint256,bytes)'](
                owner.address,
                erc998Weapons.address,
                3,
                bytesSecond);

            await erc721Enchantments['safeTransferFrom(address,address,uint256,bytes)'](
                owner.address,
                erc998Weapons.address,
                4,
                bytesThird);

            // Transfer 1,2 Weapons to First Character, 3 to Second Character
            await erc998Weapons['safeTransferFrom(address,address,uint256,bytes)'](
                owner.address,
                erc998Characters.address,
                1,
                bytesFirst);
            await erc998Weapons['safeTransferFrom(address,address,uint256,bytes)'](
                owner.address,
                erc998Characters.address,
                2,
                bytesFirst);
            await erc998Weapons['safeTransferFrom(address,address,uint256,bytes)'](
                owner.address,
                erc998Characters.address,
                3,
                bytesSecond);

            // Transfer Characters to Accounts
            await erc998Characters['safeTransferFrom(address,address,uint256,bytes)'](
                owner.address,
                erc998Accounts.address,
                1,
                bytesFirst);
            await erc998Characters['safeTransferFrom(address,address,uint256,bytes)'](
                owner.address,
                erc998Accounts.address,
                2,
                bytesSecond);

            const aliceAccountChildContracts = await erc998Accounts.totalChildContracts(1);
            assert(aliceAccountChildContracts.eq(1), 'Invalid alice child contracts');

            const bobAccountChildContracts = await erc998Accounts.totalChildContracts(2);
            assert(bobAccountChildContracts.eq(1), 'Invalid bob child contracts');

            // How to transfer an enchantment from FirstWeapon to SecondWeapon?
            // Transfer Character
            await erc998Accounts.connect(alice)['safeTransferChild(uint256,address,address,uint256)'](
                1,
                alice.address,
                erc998Characters.address,
                1
            );

            // Transfer Weapon
            await erc998Characters.connect(alice)['safeTransferChild(uint256,address,address,uint256)'](
                1,
                alice.address,
                erc998Weapons.address,
                1
            );

            // enchantments before transfer
            const secondWeaponEnchantmentsBeforeTransfer = await erc998Weapons.totalChildTokens(2, erc721Enchantments.address);

            // Transfer Enchantment
            await erc998Weapons.connect(alice)['safeTransferChild(uint256,address,address,uint256,bytes)'](
                1,
                erc998Weapons.address,
                erc721Enchantments.address,
                1,
                bytesSecond // transfer to second weapon
            );

            const secondWeaponEnchantmentsAfterTransfer = await erc998Weapons.totalChildTokens(2, erc721Enchantments.address);
            assert(secondWeaponEnchantmentsAfterTransfer.eq(secondWeaponEnchantmentsBeforeTransfer.add(1)),
                'Invalid total child contracts');
        });
    });

    describe('ERC165', async () => {
        it('Should declare interfaces: ERC165, ERC721, IERC998ERC721TopDown, IERC998ERC721TopDownEnumerable, IERC998ERC20TopDown, IERC998ERC20TopDownEnumerable', async () => {
            assert(await composableTopDownInstance.supportsInterface('0x01ffc9a7'), 'No interface declaration: ERC165');
            assert(await composableTopDownInstance.supportsInterface('0x80ac58cd'), 'No interface declaration: ERC721');
            assert(await composableTopDownInstance.supportsInterface('0x1bc995e4'), 'No interface declaration: IERC998ERC721TopDown from spec');
            assert(await composableTopDownInstance.supportsInterface('0xcde244d9'), 'No interface declaration: IERC998ERC721TopDown');
            assert(await composableTopDownInstance.supportsInterface('0xa344afe4'), 'No interface declaration: IERC998ERC721TopDownEnumerable');
            assert(await composableTopDownInstance.supportsInterface('0x7294ffed'), 'No interface declaration: IERC998ERC20TopDown');
            assert(await composableTopDownInstance.supportsInterface('0xc5fd96cd'), 'No interface declaration: IERC998ERC20TopDownEnumerable');
        });
    });

    async function setUpTestTokens(nftCount, erc20Count) {
        let nfts = [];
        let erc20s = [];
        for (let i = 0; i < nftCount; i++) {
            nfts.push(await SampleNFT.deploy());
        }

        for (let i = 0; i < erc20Count; i++) {
            erc20s.push(await SampleERC20.deploy(i.toString(), i.toString()));
        }

        return [nfts, erc20s];
    }

    async function safeTransferFromFirstToken() {
        await sampleNFTInstance
        // .connect(alice)
        ['safeTransferFrom(address,address,uint256,bytes)'](
            alice.address,
            composableTopDownInstance.address,
            expectedTokenId,
            bytesFirstToken);
    }
});
