const { assert, expect } = require('chai');
const { ethers } = require("hardhat");

describe('HoardBundles', async () => {
    let ComposableTopDown,
        SampleERC20,
        SampleERC1155,
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

        ComposableTopDown = await ethers.getContractFactory("HoardBundles");
        SampleERC20 = await ethers.getContractFactory("SampleERC20");
        SampleERC1155 = await ethers.getContractFactory("SampleERC1155");
        SampleNFT = await ethers.getContractFactory("SampleNFT");
        ContractIERC721ReceiverNew = await ethers.getContractFactory("ContractIERC721ReceiverNew");
        ContractIERC721ReceiverOld = await ethers.getContractFactory("ContractIERC721ReceiverOld");

        composableTopDownInstance = await ComposableTopDown.deploy("ComposableTopDown", "CTD");
        await composableTopDownInstance.deployed();
    });

    describe('Ownable', async () => {
        it('Should be deployer initially', async () => {
            let owner = await composableTopDownInstance.owner()
            assert(owner == composableTopDownInstance.signer.address, "Wrong owner")
        });

        it('Should transfer ownership', async () => {
            let tx = await composableTopDownInstance.transferOwnership(bob.address)
            await tx.wait()
            let owner = await composableTopDownInstance.owner()
            assert(owner == bob.address, "Wrong owner")
        });

        it('Should not transfer ownership', async () => {
            const expectedRevertMessage = 'Ownable: caller is not the owner';
            await expect(composableTopDownInstance.connect(bob).transferOwnership(bob.address)).to.be.revertedWith(expectedRevertMessage);
        });

        it('Should successfully emit OwnershipTransferred event arguments', async () => {
            await expect(
                composableTopDownInstance.transferOwnership(bob.address))
                .to.emit(composableTopDownInstance,
                    'OwnershipTransferred').withArgs(
                        alice.address,
                        bob.address
                    );
        });

        it('Should renounce ownership', async () => {
            let tx = await composableTopDownInstance.renounceOwnership()
            await tx.wait()
            let owner = await composableTopDownInstance.owner()
            assert(owner == zeroAddress, "Wrong owner")
        });

        it('Should not renounce ownership', async () => {
            const expectedRevertMessage = 'Ownable: caller is not the owner';
            await expect(composableTopDownInstance.connect(bob).renounceOwnership()).to.be.revertedWith(expectedRevertMessage);
        });
    });

    describe('BaseURI', async () => {
        it('Should set base uri', async () => {
            const baseURI = "https://my.token.io/"
            let tx = await composableTopDownInstance.setBaseURI(baseURI)
            await tx.wait()
            let baseURI_ = await composableTopDownInstance.baseURI()
            assert(baseURI == baseURI_, "Wrong base uri")
        });

        it('Should successfully emit OwnershipTransferred event arguments', async () => {
            const baseURI = "https://my.token.io/"
            await expect(
                composableTopDownInstance.setBaseURI(baseURI))
                .to.emit(composableTopDownInstance,
                    'NewBaseURI').withArgs(
                        baseURI
                    );
        });

        it('Should not set base uri', async () => {
            const baseURI = "https://my.token.io/"
            const expectedRevertMessage = 'Ownable: caller is not the owner';
            await expect(composableTopDownInstance.connect(bob).setBaseURI(baseURI)).to.be.revertedWith(expectedRevertMessage);
        });

        it('Should get token uri', async () => {
            const baseURI = "https://my.token.io/"
            let tx = await composableTopDownInstance.setBaseURI(baseURI)
            await tx.wait()
            tx = await composableTopDownInstance.safeMint(alice.address);  // 1 tokenId
            tx = await tx.wait();
            let tokenURI = await composableTopDownInstance.tokenURI(1)
            assert(tokenURI == baseURI+"1.json", "Wrong token uri")
        });

        it('Should not get token uri for non existing token', async () => {
            const baseURI = "https://my.token.io/"
            let tx = await composableTopDownInstance.setBaseURI(baseURI)
            await tx.wait()
            tx = await composableTopDownInstance.safeMint(alice.address);  // 1 tokenId
            tx = await tx.wait();
            const expectedRevertMessage = 'CTD: URI does not exist';
            await expect(composableTopDownInstance.tokenURI(2)).to.be.revertedWith(expectedRevertMessage);
        });

        it('Should change base uri', async () => {
            const baseURI = "https://my.token.io/"
            let tx = await composableTopDownInstance.setBaseURI(baseURI)
            await tx.wait()
            tx = await composableTopDownInstance.safeMint(alice.address);  // 1 tokenId
            tx = await tx.wait();
            tx = await composableTopDownInstance.setBaseURI(baseURI+"asset/")
            await tx.wait()
            let tokenURI = await composableTopDownInstance.tokenURI(1)
            assert(tokenURI == baseURI+"asset/"+"1.json", "Wrong token uri")
        });

    });
});
