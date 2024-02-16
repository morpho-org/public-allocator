// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IntegrationTest} from "../lib/metamorpho/test/forge/helpers/IntegrationTest.sol";

import "../src/PublicAllocatorFactory.sol";
import {IMetaMorphoFactory} from "../lib/metamorpho/src/interfaces/IMetaMorphoFactory.sol";
import {IMetaMorphoBase} from "../lib/metamorpho/src/interfaces/IMetaMorpho.sol";
import {ErrorsLib} from "../src/libraries/ErrorsLib.sol";

contract PublicAllocatorFactoryTest is IntegrationTest {
    PublicAllocatorFactory factory;
    address metaMorphoFactory;

    function setUp() public override {
        super.setUp();

        metaMorphoFactory = makeAddr("MetaMorphoFactory");

        factory = new PublicAllocatorFactory(address(metaMorphoFactory));
    }

    function testFactoryAddressZero() public {
        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        new PublicAllocatorFactory(address(0));
    }

    function testCreatePublicAllocator(address initialOwner, address vault, bytes32 salt, bool vaultCreatedByFactory)
        public
    {
        vm.assume(address(initialOwner) != address(0));
        vm.assume(address(vault) != address(0));

        bytes32 initCodeHash = hashInitCode(type(PublicAllocator).creationCode, abi.encode(initialOwner, vault));
        address expectedAddress = computeCreate2Address(salt, initCodeHash, address(factory));

        vm.mockCall(
            metaMorphoFactory,
            abi.encodeWithSelector(IMetaMorphoFactory.isMetaMorpho.selector, vault),
            abi.encode(vaultCreatedByFactory)
        );

        if (vaultCreatedByFactory) {
            vm.mockCall(vault, abi.encodeWithSelector(IMetaMorphoBase.MORPHO.selector), abi.encode(morpho));

            vm.expectEmit(address(factory));
            emit EventsLib.CreatePublicAllocator(expectedAddress, address(this), initialOwner, vault, salt);

            IPublicAllocator publicAllocator = factory.createPublicAllocator(initialOwner, vault, salt);

            assertEq(expectedAddress, address(publicAllocator), "computeCreate2Address");

            assertTrue(factory.isPublicAllocator(address(publicAllocator)), "isPublicAllocator");

            assertEq(publicAllocator.owner(), initialOwner, "owner");
            assertEq(address(publicAllocator.VAULT()), address(vault), "vault");
        } else {
            vm.expectRevert(ErrorsLib.NotMetaMorpho.selector);
            factory.createPublicAllocator(initialOwner, vault, salt);
        }
    }
}
